
activate :external_pipeline,
  name: :webpack,
  command: build? ?  "yarn run build" : "yarn run start",
  source: ".tmp/dist",
  latency: 1

activate :directory_indexes

activate :s3_sync do |s3_sync|
  s3_sync.bucket                     = 'michaelkoper.com' # The name of the S3 bucket you are targeting. This is globally unique.
  s3_sync.region                     = 'eu-west-1'     # The AWS region for your bucket.
  s3_sync.delete                     = true # We delete stray files by default.
  s3_sync.after_build                = false # We do not chain after the build step by default.
  s3_sync.prefer_gzip                = true
  s3_sync.path_style                 = true
  s3_sync.reduced_redundancy_storage = false
  s3_sync.acl                        = 'public-read'
  s3_sync.encryption                 = false
  s3_sync.prefix                     = ''
  s3_sync.version_bucket             = false
  s3_sync.index_document             = 'index.html'
  s3_sync.error_document             = '404.html'
end

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
end
