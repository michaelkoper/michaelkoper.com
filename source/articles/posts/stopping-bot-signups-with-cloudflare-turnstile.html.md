---
title: Stopping bot signups with Cloudflare Turnstile
date: 2026-07-02
published: true
description: How I added Cloudflare Turnstile to the Nusii signup form, why it fails open by design, and how I log IP addresses and user agents to fight spammers.
---

# Stopping bot signups with Cloudflare Turnstile

It started while I was moving house. 36 degrees outside, boxes stacked to the ceiling, and my phone would not stop buzzing. Every buzz was another signup, and none of them were customers. Bots. Dozens of fake accounts a day, pouring in faster than I could clear them out, while I was hauling furniture in the Spanish summer heat.

<figure>
  <img src="/images/articles/spam_signups_slack.png" alt="A stream of New signup notifications in Slack, all from the middle of the night, each with a plan and a credit card attached">
  <figcaption>New signup notifications landing in Slack through the night. Notice the plan, the country, and the card on almost every one.</figcaption>
</figure>

And these weren't harmless junk accounts. Look closely at the notifications and almost every one attached a real credit card. That's the tell. This is card testing: fraudsters push stolen card numbers through any signup form with a payment step, just to see which cards still work before spending them somewhere that matters. My signup form had quietly turned into a free validation service for stolen cards, at 3 in the morning, while I was carrying boxes up a staircase.

Not the week I would have picked for it. But spam doesn't wait for you to unpack, so between boxes I added a captcha to step one of the signup.

I went with [Cloudflare Turnstile](https://www.cloudflare.com/products/turnstile/){:target="_blank"} instead of reCAPTCHA. It doesn't make people click on traffic lights, it doesn't track users across the web, and for most visitors it's completely invisible. It just watches how the browser behaves and hands back a token.

Here's how I wired it into [Nusii](https://nusii.com){:target="_blank"}, and how I made sure it would never block a real customer.

## Two layers

Before Turnstile there's a cheaper layer: an invisible honeypot from the [invisible_captcha](https://github.com/markets/invisible_captcha){:target="_blank"} gem. It adds a hidden field and a timestamp check. Naive bots fill in the hidden field or submit too fast, and they get rejected without costing me a single API call.

Turnstile is the second layer, and it only runs once the honeypot passes. I put both behind a small controller concern:

~~~ruby
# app/controllers/concerns/captcha_protection.rb

included do
  invisible_captcha only: [:create],
    on_spam: :honeypot_spam_callback,
    on_timestamp_spam: :timestamp_spam_callback
  # Registered after invisible_captcha's filter so the honeypot runs first.
  before_action :verify_turnstile, only: [:create]
end

def verify_turnstile
  return unless Flipper.enabled?(:signup_captcha) && CloudflareTurnstile.configured?

  result = CloudflareTurnstile.verify(
    token: params['cf-turnstile-response'],
    remote_ip: request.remote_ip
  )
  return unless result.deny?

  reason = result.outcome == :missing_token ? 'missing_token' : 'invalid_token'
  CaptchaFailure.record(source: CaptchaFailure::TURNSTILE, reason: reason,
    request: request, params: params, error_codes: result.error_codes)
  flash.now[:spam_error] = "We couldn't verify that you're human. Please try again."
  rebuild_signup
  render :new, status: :unprocessable_content
end
~~~

It's behind a [Flipper](https://github.com/flippercloud/flipper){:target="_blank"} flag, so if Turnstile ever misbehaves I can turn it off in one click without a deploy.

## The widget

On the front end, Turnstile is just a script tag and a `div`. Cloudflare's script finds the `.cf-turnstile` element and injects the hidden `cf-turnstile-response` input into the form by itself:

~~~erb
<%# app/views/registrations/new.html.erb %>

<script src="<%= CloudflareTurnstile.script_url %>" async defer></script>
<div class="cf-turnstile"
  data-sitekey="<%= CloudflareTurnstile.site_key %>"
  data-action="signup"
  data-appearance="interaction-only"></div>
~~~

The `interaction-only` appearance keeps the widget hidden unless Cloudflare decides a visitor needs a challenge. Most people never see a thing. (I also had to allow `challenges.cloudflare.com` in our [Content-Security-Policy](/articles/how-a-content-security-policy-caught-malware-in-a-customers-browser/), otherwise the browser blocks the script.)

## Verifying on the server, and failing open

The widget only produces a token. The real check happens on the server, where I send that token to Cloudflare's `siteverify` endpoint with our secret key:

~~~ruby
# app/models/cloudflare_turnstile.rb

# Verdicts that prove the token is bad (bot, forged, expired or replayed).
DENY_CODES = %w[
  missing-input-response invalid-input-response
  invalid-widget-id timeout-or-duplicate
].freeze

def interpret(response)
  return fail_open('non-200 response') unless response.status == 200

  body = response.body
  return Result.new(:pass) if body['success'] == true

  codes = Array(body['error-codes']).map(&:to_s)
  if codes.present? && (codes - DENY_CODES).empty?
    Result.new(:fail, codes)   # definitely a bad token, block it
  else
    fail_open('unexpected codes', codes) # our problem, not the visitor's
  end
end
~~~

This is the part I care about most. A signup is only blocked when Cloudflare gives a definitive verdict that the token itself is bad. Everything else fails open: if Cloudflare times out, returns a 500, sends back garbage, or if I misconfigured the secret key, the signup goes through.

The trade-off is deliberate. A captcha that fails closed will, on a bad day, quietly block paying customers and you might never hear about it. They just leave. Blocking a real signup is far more expensive than letting a bot slip past a layer that already has a honeypot in front of it.

## Logging every failure

Here's the other half. Every blocked attempt, from both layers, gets written to a `captcha_failures` table. And I store more than just the fact that it happened:

~~~ruby
# db/migrate/20260702130000_create_captcha_failures.rb

class CreateCaptchaFailures < ActiveRecord::Migration[8.1]
  def change
    create_table :captcha_failures do |t|
      t.string :source, null: false   # 'turnstile' or 'invisible_captcha'
      t.string :reason, null: false   # 'missing_token', 'invalid_token', 'honeypot', 'timestamp'
      t.string :email
      t.string :ip_address
      t.string :country_code
      t.string :user_agent
      t.string :time_zone
      t.string :plan_name
      t.jsonb  :error_codes, null: false, default: []
      t.string :referer
      t.string :accept_language

      t.timestamps
    end

    add_index :captcha_failures, :created_at
    add_index :captcha_failures, :ip_address
    add_index :captcha_failures, :email
  end
end
~~~

The IP address and user agent are the interesting fields. They serve two purposes.

First, they let me catch the opposite of a bot: a real customer being wrongly blocked. If someone emails saying "I can't sign up," I can search this table by email or IP and see exactly what tripped, and why.

Second, they build a profile of who's attacking me. A spam wave usually shares an IP range, a user agent, or a country. The more of that I record, the easier the next wave is to recognise. The logging is careful: every string is length-capped, and if the write itself fails it's reported and swallowed so it can never break a real signup.

## Tracking the signups that get through

The failures table only sees the attempts I stopped. But the spammers I really want to catch are the ones that get *through*. So on every successful signup I also store the IP address and user agent, this time on the account itself:

~~~ruby
# app/models/account.rb

create_attribution!(
  # ...marketing attribution...
  ip_address: ip_address || Current.ip_address,
  user_agent: Current.user_agent
)
~~~

This is playing the long game. When I later discover an account was a spammer, and it always happens eventually, I can look up its IP and user agent and cross-reference them against every other account and every logged failure. Patterns fall out. That gives me the data to hunt down the rest and block them before they ever finish signing up.

## Wrapping up

The whole thing comes down to a few ideas that I think apply to any captcha:

- **Put a free layer first.** A honeypot catches the cheap bots so you don't pay to verify them.
- **Fail open.** Never let an outage in your bot defense block a real customer.
- **Log everything.** IPs and user agents on both the failures and the successful signups. It's how you spot false positives, and how you build a case against the spammers who slip through.
- **Keep a kill switch.** A feature flag means you can turn it all off if it goes wrong.

Bot signups are annoying, but the cure can be worse than the disease. A captcha that occasionally frustrates real customers is a much bigger problem than a few junk accounts. Fail open, log everything, and keep the off switch handy.

\- Michael
