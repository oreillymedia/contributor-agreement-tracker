require 'bundler'
Bundler.require

Dir["./src/*.rb"].each {|file| require file }
Dir["./src/*/*.rb"].each {|file| require file }

builder = Rack::Builder.new do

  # Asset Pipeline
  map '/assets' do
    environment = Sprockets::Environment.new
    environment.append_path 'src/assets/javascripts'
    environment.append_path 'src/assets/stylesheets'
    environment.append_path HandlebarsAssets.path
    HandlebarsAssets::Config.template_namespace = 'JST'
    run environment
  end

end

run builder


require './app'
run Sinatra::Application
