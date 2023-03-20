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
end
