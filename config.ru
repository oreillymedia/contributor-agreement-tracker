require 'bundler'
Bundler.require

require 'dotenv'
Dotenv.load

require './app'

map '/' do
  run App
end
