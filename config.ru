require 'resque/server'
require 'bundler'
Bundler.require

require 'dotenv'
Dotenv.load

require './app'

run Rack::URLMap.new(
  "/"       => Sinatra::App.new,
  "/resque" =>  Resque::Server.new
)
