require 'bundler'
Bundler.require

require './app'

builder = Rack::Builder.new do

  # Mount the Sinatra app in ./app at the base route.
  map '/' do
    run App
  end

  # Mount Sprockets in the /assets route, stylesheets + javascripts are both
  # hoisted one level so the file ./assets/stylesheets/atlas_assets.scss is
  # at /assets/atlas_assets.css in the browser
  map '/assets' do
    environment = Sprockets::Environment.new
    environment.append_path 'assets/javascripts'
    environment.append_path 'assets/stylesheets'
    environment.append_path HandlebarsAssets.path
    HandlebarsAssets::Config.template_namespace = 'JST'
    run environment
  end

end

run builder