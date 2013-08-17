require 'rubygems'
require 'mail'
require 'bundler'
require 'sinatra/cookies'
require 'dotenv'

Dotenv.load

Bundler.require
require './database.rb'

class App < Sinatra::Base
  set :root, File.dirname(__FILE__)
  enable :sessions
  helpers Sinatra::Cookies
  
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


  # Grab the text of the cla agreement and make it a global constant.  
  # We need md for the confirmation emails and html for the web interface
  $CLA_MD = IO.read('docs/contributor_agreement.md')
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML, :autolink => true, :space_after_headers => true)
  $CLA_HTML = markdown.render($CLA_MD)
  
  get '/' do
    data = {}
    if cookies[:data] then
      data = JSON.parse cookies[:data]
    end
    erb :index, :locals => { :data => data }
  end
  
  get '/contributor_agreement' do
    erb :contributor_agreement
  end 

  post '/confirm' do
    confirmation_code = (0...10).map{(65+rand(26)).chr}.join
    email = params[:email]
#    begin 
      u = Contributor.new
      u.fullname = params[:fullname]
      u.email = params[:email]
      u.address = params[:address]
      u.date_invited = Date.today
      u.confirmation_code = confirmation_code
      u.save
    
    
      # Now store data as a cookie
      
      response.set_cookie 'data', {:value=> u.to_json, :max_age => "2592000"}
#      response.set_cookie 'email', {:value=> params[:email], :max_age => "2592000"}
#      response.set_cookie 'address', {:value=> params[:address], :max_age => "2592000"}
      
      link = "http://contributor-agreements.oreilly.com/verify/#{confirmation_code}"
      # Send an email
#      mail = Mail.deliver do
#        to email
#        cc "contributor-agreements@oreilly.com"
#        from "contributor-agreements@oreilly.com"
#v       subject "Please confirm your contributor agreement"
#        text_part do
#          body "\n\n Click this link to verify your account #{link} \n #{@cla_md}"
#        end
#      end
      redirect "/"
#    rescue
#      erb :save_error
#    end 
  end 
  
  get '/verify/:confirmation_code' do
     u = Contributor.first(:confirmation_code => params[:confirmation_code])
     erb :verification
  end

  get '/faq' do
    erb :faq
  end
  
end