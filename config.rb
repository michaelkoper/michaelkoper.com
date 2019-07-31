
activate :external_pipeline,
  name: :webpack,
  command: build? ?  "yarn run build" : "yarn run start",
  source: ".tmp/dist",
  latency: 1

activate :directory_indexes

configure :development do
  activate :livereload
end

set :css_dir, 'assets/stylesheets'
set :js_dir, 'assets/javascript'
set :images_dir, 'images'

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
