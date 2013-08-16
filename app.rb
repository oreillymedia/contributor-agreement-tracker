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
    confirmation_code = (0...10).map{(65+rand(26)).chr}.join
    u = Contributor.new
    u.fullname = params[:fullname]
    u.email = params[:email]
    u.address = params[:address]
    u.accepted_agreement = params[:accept_cla]
    u.date_invited = Date.today
    u.confirmation_code = confirmation_code
    u.save
    @email = params[:email]
    erb :confirm
  end 
  
  get '/faq' do
    erb :faq
  end
  
end