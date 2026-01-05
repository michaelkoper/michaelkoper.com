activate :blog do |blog|
  blog.prefix = "articles"
  blog.sources = "posts/{title}.html"
  blog.permalink = "{title}.html"
  blog.layout = "blog_layout"
  blog.default_extension = ".md"
end

activate :external_pipeline do |pipeline|
  pipeline.name = :esbuild
  pipeline.command = build? ? "node esbuild.config.js" : "node esbuild.config.js --watch"
  pipeline.source = 'tmp/dist'
  pipeline.latency = 1
end

activate :directory_indexes

configure :development do
  activate :livereload
end

page "/sitemap.xml", layout: false
page "/404.html", directory_index: false

configure :build do
  # Enable cache buster (except for images)
  activate :asset_hash, ignore: [/\.jpg\Z/, /\.png\Z/]
  activate :gzip
end

helpers do
  def svg(name)
    root = Middleman::Application.root
    file_path = "#{root}/source/images/#{name}.svg"
    return File.read(file_path) if File.exists?(file_path)
    '(not found)'
  end

  def link_to(*args, &block)
    options = args.extract_options!
    url = args[block_given? ? 0 : 1]

    if url && current_resource.url == url_for(url)
      options['aria-current'] = :page
    end

    super(*args, options, &block)
  end
end
