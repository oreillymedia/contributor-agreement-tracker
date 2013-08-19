require 'rubygems'
require 'mail'
require 'bundler'
require 'sinatra/cookies'
require 'sinatra/flash'
require 'logger'
require 'dotenv'

Dotenv.load

Bundler.require
require './database.rb'

class App < Sinatra::Base
  set :root, File.dirname(__FILE__)
  enable :sessions
  helpers Sinatra::Cookies
  register Sinatra::Flash
  set :session_secret, "My session secret"

  #create logger
  @@logger = Logger.new(STDOUT)  
  
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
  $VERIFICATION_EMAIL = IO.read('docs/verification_email.md')
  $CONFIRMATION_EMAIL = IO.read('docs/confirmation_email.md')
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
    @@logger.info "confirm -- generating acceptance request for #{params.to_json}"
    confirmation_code = (0...10).map{(65+rand(26)).chr}.join
    begin 

      # Now store data as a persistent cookie so that their info appears each time      
      response.set_cookie 'data', {:value=> params.to_json, :max_age => "2592000"}

      u = Contributor.new
      u.fullname = params[:fullname]
      u.email = params[:email]
      u.address = params[:address]
      u.date_invited = Date.today
      u.confirmation_code = confirmation_code
      u.save
  
      # Send an email
      mail = Mail.deliver do
        to u.email
        cc "contributor-agreements@oreilly.com"
        from "contributor-agreements@oreilly.com"
        subject "Please confirm your O'Reilly Media Contributor Agreement"
        text_part do
           body Mustache.render($VERIFICATION_EMAIL,u)
        end
      end

      @@logger.info "confirm -- sent confirmation for #{u.to_json}"
      
      erb :confirm, :locals => {:email => params[:email]}
      
    rescue Exception => e
      puts e
      @logger.info 'confirm -- exception #{e} occurred'
      flash[:error] = "An error occurred! Try again."
      redirect "/"
    end 
  end 
  
  get '/verify/:confirmation_code' do
     @@logger.info "verify -- verifying confirmation code for #{params.to_json}"
     u = Contributor.first(:confirmation_code => params[:confirmation_code])
     if u then
       u.date_accepted = Date.today
       u.save
       # Send an email
       mail = Mail.deliver do
         to u.email
         cc "contributor-agreements@oreilly.com"
         from "contributor-agreements@oreilly.com"
         subject "Your O'Reilly Media Contributor Agreement confirmation"
         text_part do
            body Mustache.render($CONFIRMATION_EMAIL,{
              :fullname => u.fullname,
              :email => u.email,
              :address => u.address,
              :cla_md => $CLA_MD
            })
         end
       end
       @@logger.info "verify -- verified confirmation code for #{u.to_json}"
     else
       flash[:error] = "This record could not be found.  Please try registering again."
     end      
     erb :verification
  end

  get '/faq' do
    erb :faq
  end
  
end