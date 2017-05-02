xml.instruct!
xml.urlset 'xmlns' => "http://www.sitemaps.org/schemas/sitemap/0.9" do
  sitemap.resources
      .select { |page| page.path.match(/\.html/) }
      .reject{ |page| page.data.exclude_sitemap }
      .sort_by{ |page| -(page.data.priority.try(:to_f).presence || 0.5)}
      .each do |page|
    xml.url do
      loc = if page.path == 'index.html'
        ''
      elsif page.path =~ /\/index.html$/
        page.path.gsub('index.html', '')
      elsif page.path =~ /.html$/
        page.path.gsub(/.html$/, '/')
      else
        page.path
      end
      xml.loc "#{data.sitemap.url}#{loc}".gsub(/\/$/, '')
      xml.lastmod Date.today.to_time.iso8601
      xml.changefreq page.data.changefreq || "monthly"
      xml.priority page.data.priority || "0.5"
    end
  end
end

