require 'rubygems'
require 'bundler'
Bundler.require
require './database.rb'

class App < Sinatra::Base
  set :root, File.dirname(__FILE__)

  get '/' do
    erb :index
  end
  
  get '/contributor_agreement' do
    erb :contributor_agreement
  end 

  post '/confirm' do
    @email = params[:email]
    erb :confirm
  end 
  
  get '/faq' do
    erb :faq
  end
  
end