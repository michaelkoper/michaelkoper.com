---
title: Blocking Tor traffic in Rails with Rack::Attack
date: 2026-08-18
published: true
description: How I block every Tor exit node at Nusii with a daily list sync, an in-memory IP set, and a three-line Rack::Attack rule.
---

# Blocking Tor traffic in Rails with Rack::Attack

When I added [Turnstile to the Nusii signup form](/articles/stopping-bot-signups-with-cloudflare-turnstile/), I also started logging the IP address of every failed captcha. One pattern stood out: many of those IPs were Tor exit nodes. [Nusii](https://nusii.com){:target="_blank"} is a proposal tool for businesses, and real customers do not send proposals through Tor. So I now block the whole Tor network. It took surprisingly little code.

## The Tor Project publishes every exit node

Tor is easy to block because the Tor Project publishes [the full list of exit IPs](https://check.torproject.org/torbulkexitlist){:target="_blank"}. It hovers around 1,500 addresses.

~~~ruby
# app/models/tor_exit_list.rb
class TorExitList
  SOURCE_URL = 'https://check.torproject.org/torbulkexitlist'.freeze

  # The list has hovered around 1,000-1,500 exits for years. A response far
  # below that is truncated or broken and must never wipe a good list.
  MIN_PLAUSIBLE_COUNT = 500

  def self.sync!
    ips = fetch
    return false if ips.size < MIN_PLAUSIBLE_COUNT

    DeniedIp.replace_network!(DeniedIp::TOR, ips)
    true
  end

  def self.fetch
    response = Faraday.new(request: { open_timeout: 5, timeout: 15 }).get(SOURCE_URL)
    return [] unless response.status == 200

    response.body.to_s.each_line.filter_map do |line|
      line = line.strip
      IPAddr.new(line).to_s if line.present?
    rescue IPAddr::InvalidAddressError
      nil
    end.uniq
  end
end
~~~

The `MIN_PLAUSIBLE_COUNT` guard matters. If the download returns a half list or an error page, the sync refuses it and keeps yesterday's list. The production version also reports refused and failed syncs to AppSignal.

## Store it in Postgres

~~~ruby
# db/migrate/20260805090000_create_denied_ips.rb
create_table :denied_ips do |t|
  t.string :ip_address, null: false
  t.string :network, null: false
  t.timestamps
end
add_index :denied_ips, [:ip_address, :network], unique: true
~~~

The `network` column is there so the same table can hold other lists later, like manually banned IPs.

~~~ruby
# app/models/denied_ip.rb
class DeniedIp < ApplicationRecord
  TOR = 'tor'.freeze

  # Atomically swaps one network's rows, leaving every other network alone.
  def self.replace_network!(network, ips)
    now = Time.current
    transaction do
      where(network: network).delete_all
      insert_all(ips.map { |ip| { network: network, ip_address: ip, created_at: now, updated_at: now } })
    end
  end
end
~~~

A daily job keeps it fresh. With SolidQueue that is a few lines of YAML:

~~~yaml
# config/recurring.yml
sync_tor_exit_list:
  command: "TorExitList.sync!"
  schedule: "40 2 * * *"
~~~

## Answer from process memory

The blocklist check runs on every request. I do not want a database query there, and not a Redis round trip either. Each process keeps the list in a plain Ruby Set and re-reads the table once an hour.

~~~ruby
# app/models/blocked_ip_set.rb
class BlockedIpSet
  BLOCKED_NETWORKS = [DeniedIp::TOR].freeze
  REFRESH_INTERVAL = 1.hour
  RETRY_INTERVAL = 1.minute

  @ips = Set.new.freeze
  @expires_at = nil
  @mutex = Mutex.new

  class << self
    # A failed refresh answers from the stale copy. An empty first load
    # fails open: nobody blocked.
    def blocked?(ip)
      refresh if stale?
      @ips.include?(ip.to_s)
    end

    private

    def stale?
      @expires_at.nil? || Time.current >= @expires_at
    end

    def refresh
      @mutex.synchronize do
        return unless stale?

        @ips = DeniedIp.where(network: BLOCKED_NETWORKS).pluck(:ip_address).to_set.freeze
        @expires_at = REFRESH_INTERVAL.from_now
      rescue StandardError
        @expires_at = RETRY_INTERVAL.from_now
      end
    end
  end
end
~~~

A lookup in a 1,500 item Set costs nanoseconds. The hourly refresh is a few milliseconds, paid by the one request that finds the copy stale. If the database hiccups, the stale copy keeps answering.

## The actual block

After that plumbing, the rule itself is three lines:

~~~ruby
# config/initializers/rack_attack.rb
Rack::Attack.blocklist('blocked networks') do |req|
  BlockedIpSet.blocked?(req.ip)
end
~~~

Blocked requests get a plain 403 in middleware and never reach a controller. One caveat: behind a reverse proxy, make sure `req.ip` is the real client IP and not your proxy. At Nusii I patch `Rack::Attack::Request` to read the `X-Real-IP` header that Caddy sets.

## Count what you block

Rack::Attack instruments every match, so one subscriber turns blocks into an AppSignal counter, tagged by rule:

~~~ruby
# config/initializers/rack_attack.rb
ActiveSupport::Notifications.subscribe(/\A(throttle|blocklist)\.rack_attack\z/) do |name, _start, _finish, _id, payload|
  rule = payload[:request].env['rack.attack.matched'].to_s
  Appsignal.increment_counter('rack_attack_match', 1.0, kind: name.split('.').first, rule: rule)
end
~~~

In the first six days the chart showed about 30 blocked requests. Scanner noise, spread over the day, and not a single complaint from a customer.

## What this does not do

- It blocks exit nodes only. Traffic from VPNs and data center proxies is a different problem.
- It fails open. An empty table or a broken sync blocks nobody. For a business app that is the right default: availability wins over a perfect blocklist.
- It is not instant. A new exit node is picked up by the nightly sync and reaches every process within the hour.

That is the whole thing. One HTTP fetch, one table, one in-memory Set, and a three-line Rack::Attack rule.
