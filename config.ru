require 'resque/server'
require 'bundler'
Bundler.require

require 'dotenv'
Dotenv.load

require './app'

# With this method of creating a URL Map, instantiate apps using the new method
run Rack::URLMap.new({
  "/"       => App.new,
  "/resque" => Resque::Server.new
})
