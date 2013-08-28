require 'rubygems'
require 'resque'
require 'resque-status'
require 'bundler'
require 'sinatra/cookies'
require 'sinatra/flash'
require 'newrelic_rpm'
require 'logger'
require './workers.rb'
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
  
  # Configure redis
  uri = URI.parse(ENV["REDIS_URL"])
  Resque.redis = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password, :thread_safe => true)


  #create logger
  @@logger = Logger.new(STDOUT)  

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
  
  get '/faq' do
    erb :faq
  end
  
  get '/contributor_status' do
    erb :contributor_status
  end
  
  get "/webhook" do
    erb :webhook
  end
  
  post "/webhook" do
    msg = {
      :repo => params[:repo], 
      :callback => params[:callback]
    }
    job = WebhookWorker.create(msg) 
    flash[:notice] = "Your webhook request has been added as job #{job}"
    redirect "/webhook"
  end
  
  post '/contributor_status' do
    response = {}
    emails = params[:contributors].gsub("\n",",").split(",")
    emails.each do |e|
      key = e.strip
      clas = Contributor.all(:email => key)
      out = []
      clas.each do |cla|
         c = {
          :fullname => cla.fullname,
          :date_invited => cla.date_invited,
          :date_accepted => cla.date_accepted,
          :confirmation_code => cla.confirmation_code
         }
         out << c
      end   
      response[key] = out
    end
    content_type :json
    JSON.pretty_generate(response)+"\n"
  end
  
  
  post '/confirm' do
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
  
      msg = {
        :email_src => 'docs/verification_email.md',
        :subject => "Please confirm your O'Reilly Media Contributor Agreement",
        :to => u.email,
        :payload => u
      }
      job = EmailWorker.create(msg)
      erb :confirm, :locals => {:email => params[:email]}      
    rescue Exception => e
      puts e
      flash[:error] = "An error occurred! Try again."
      redirect "/"
    end 
  end 
  
  get '/verify/:confirmation_code' do
     u = Contributor.first(:confirmation_code => params[:confirmation_code])
     if u then
       u.date_accepted = Date.today
       u.save
       # Send an email
       msg = {
         :email_src => 'docs/confirmation_email.md',
         :subject => "Your O'Reilly Media Contributor Agreement confirmation",
         :to => u.email,
         :payload => {
             :fullname => u.fullname,
             :email => u.email,
             :address => u.address,
             :cla_md => $CLA_MD
         }
       }
       job = EmailWorker.create(msg)
     else
       flash[:error] = "This record could not be found.  Please try registering again."
     end      
     erb :verification
  end

  
end