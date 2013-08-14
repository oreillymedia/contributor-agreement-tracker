require 'rubygems'
require 'bundler'
Bundler.require
require './database.rb'

class App < Sinatra::Base
  set :root, File.dirname(__FILE__)

  get '/' do
    erb :hello
  end
end