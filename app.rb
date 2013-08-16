require 'rubygems'
require 'mail'
require 'bundler'
require 'dotenv'
Dotenv.load

Bundler.require
require './database.rb'

class App < Sinatra::Base
  set :root, File.dirname(__FILE__)

  # Configure the mailer
  Mail.defaults do
    delivery_method :smtp, {
      :address              => "smtp.sendgrid.net",
      :port                 => 587,
      :user_name            => ENV['SENDGRID_USERNAME'],
      :password             => ENV['SENDGRID_PASSWORD'],
      :domain               => ENV['SENDGRID_DOMAIN'],
      :authentication       => 'plain',
      :enable_starttls_auto => true  }      
  end

  get '/' do
    erb :index
  end
  
  get '/contributor_agreement' do
    erb :contributor_agreement
  end 

  post '/confirm' do

    confirmation_code = (0...10).map{(65+rand(26)).chr}.join
    email = params[:email]
    u = Contributor.new
    u.fullname = params[:fullname]
    u.email = params[:email]
    u.address = params[:address]
    u.accepted_agreement = params[:accept_cla]
    u.date_invited = Date.today
    u.confirmation_code = confirmation_code
    u.save
    
    link = "http://contributor-agreements.oreilly.com/verify/#{confirmation_code}"
    # Send an email
    mail = Mail.deliver do
      to email
      cc "contributor-agreements@oreilly.com"
      from "contributor-agreements@oreilly.com"
      subject "Please confirm your contributor agreement"
      text_part do
        body "\n\n Click this link to verify your account #{link}"
      end
    end
    
    @email = params[:email]
    erb :confirm
  end 
  
  get '/verify/:confirmation_code' do
     u = Contributor.first(:confirmation_code => params[:confirmation_code])
     if u
       "Found you #{u}"
     else
       "Sorry!  Can't find this code"
     end
  end

  get '/faq' do
    erb :faq
  end
  
end