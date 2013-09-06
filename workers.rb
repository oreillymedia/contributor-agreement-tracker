require 'rubygems'
require 'bundler'
Bundler.require
require 'mustache'
require 'logger'
require 'resque'
require 'resque-status'
require 'redis'
require 'mail'
require 'octokit'

require 'dotenv'
Dotenv.load

require './database.rb'


# To start these, use this command:
#   rake resque:work QUEUE=*
#
# If testing locally, I've got a proxy set up on the atlas-worker staging that I
# use as an endpoint for the webhooks
#
#   ssh -g -R 3000:127.0.0.1:3000 root@atlas-worker-staging.makerpress.com 

def log(logger, queue, process_id, msg)
  logger.info "#{queue} \t #{process_id} \t #{msg}"
end

# Get a hook to redis to use as a cahce
uri = URI.parse(ENV["REDIS_URL"])
@cache = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password, :thread_safe => true)

# This will mark a user as recently nagged.  TTL is how long the cache will hold the record
def mark(status, user, ttl)
  @cache.setex "#{status}:#{user}", ttl, "yes"
end

def check?(status,user)
  if @cache.get("#{status}:#{user}") then
    true
  else
    false
  end
end

# this method has a side effects in the cache
def notify?(user)
  ret_val = false
  if !check?("verified", user)
    u = Contributor.first(:email => user)
    if u
      # the user has registered
      # now test if they have verified
      # if they have not verified, then send them a nag if they haven't already been nagged
      # if they have accepted, then mark them in the cache
      if u.date_accepted
         mark("verified", user, 86400)
      else
        if !check?("nagged", user, 3600)
           ret_val = true        
           mark("nagged",user)
        end
      end
    end
  end
  return ret_val
end

      
#
# Email queue for sending notices
#
class EmailWorker

  include Resque::Plugins::Status
  @queue = "email_worker"
  @logger ||= Logger.new(STDOUT)   
    
  
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
  
  
  def self.perform(process_id, msg)       
    log(@logger, @queue, process_id, "Attempting to send an email #{msg}")
    email_body = IO.read(msg['email_src'])
    mail = Mail.deliver do
      to msg['to']
      cc ENV["CLA_ALIAS"]
      from ENV["CLA_ALIAS"]
      subject msg['subject']
      text_part do
        body Mustache.render(email_body,msg['payload'])
      end
    end
  end
    
end


# This worker adds a webhook to the specified repo.
class AddWebhookWorker

  include Resque::Plugins::Status
  @queue = "webhook_worker"
  @logger ||= Logger.new(STDOUT)   
  @github_client = Octokit::Client.new( :access_token => ENV["GITHUB_TOKEN"])
    
  def self.perform(process_id, msg)
    log(@logger, @queue, process_id, "Attempting to add webhook #{msg} #{ENV['GITHUB_LOGIN']}")
    begin
      # Create an event for a push request
       @github_client.create_hook(
         msg["repo"],
         'web',
         {
           :url => ENV["PUSH_VALIDATION_HOOK"],
           :content_type => 'json'
         },
         {
           :events => ['push'],
           :active => true
         }
       )
       # Create an event for a pull request
        @github_client.create_hook(
          msg["repo"],
          'web',
          {
            :url => ENV["PULL_VALIDATION_HOOK"],
            :content_type => 'json'
          },
          {
            :events => ['pull_request'],
            :active => true
          }
        )
       log(@logger, @queue, process_id, "Created webhook")
    rescue Exception => e
       log(@logger, @queue, process_id, "Could not connect to github API - #{e}")
       raise e
    end
  end
end

# This worker responds to a pull request sent to a repo and sends a CLS
class CLAPushWorker

  include Resque::Plugins::Status
  @queue = "cla_push_worker"
  @logger ||= Logger.new(STDOUT)   
  @github_client = Octokit::Client.new( :access_token => ENV["GITHUB_TOKEN"])
  
  def self.perform(process_id, msg)
    # get a list of all contributors
     authorsArray = msg["body"]["commits"].map { |hash| hash["author"] }
     log(@logger, @queue, process_id, "Contributors are #{authorsArray}")   
     authorsArray.each do |c|
       log(@logger, @queue, process_id, "Sending email to #{c}")           
       m = {
         :email_src => 'docs/push_webhook_issue_text.md',
         :subject => "O'Reilly Media Contributor License Agreement",
         :to => c["email"],
         :payload => { :url => msg["body"]["repository"]["url"] || "missing repo"}
       }
       # send this user an email if they haven't been verified or nagged
       if notify?(c.email)
          job = EmailWorker.create(m)
       end
    end
  end
  
end


# This worker responds to a pull request sent to a repo and sends a CLS
class CLAPullWorker

  include Resque::Plugins::Status
  @queue = "cla_pull_worker"
  @logger ||= Logger.new(STDOUT)   
  @github_client = Octokit::Client.new( :access_token => ENV["GITHUB_TOKEN"])

  $WEBHOOK_ISSUE_TEXT = IO.read('docs/pull_webhook_issue_text.md')
  
  def self.perform(process_id, msg)
    dat = {
       "number" => msg["body"]["number"],
       "issue_url" => msg["body"]["pull_request"]["issue_url"],
       "sender" => msg["body"]["sender"]["login"],
       "sender_url" => msg["body"]["sender"]["url"],
       "body" => msg["body"]["pull_request"]["body"],
       "diff_url" => msg["body"]["pull_request"]["diff_url"],
       "base" => {
          "url" => msg["body"]["pull_request"]["base"]["repo"]["html_url"],
          "description" => msg["body"]["pull_request"]["base"]["repo"]["description"],
          "full_name" => msg["body"]["pull_request"]["base"]["repo"]["full_name"],
          "owner" => msg["body"]["pull_request"]["base"]["repo"]["owner"]["login"],
          "owner_url" => msg["body"]["pull_request"]["base"]["repo"]["owner"]["url"]
       },
       "request" => {
          "url" => msg["body"]["pull_request"]["head"]["repo"]["html_url"],
          "description" => msg["body"]["pull_request"]["head"]["repo"]["description"],
          "full_name" => msg["body"]["pull_request"]["head"]["repo"]["full_name"],
          "owner" => msg["body"]["pull_request"]["head"]["repo"]["owner"]["login"],
          "owner_url" => msg["body"]["pull_request"]["head"]["repo"]["owner"]["url"]
       }
    }
    log(@logger, @queue, process_id, "The payload for the template is #{dat}")
    # Pull out the template from the checklist repo on github and process the variables using mustache
    message_body = Mustache.render($WEBHOOK_ISSUE_TEXT, dat).encode('utf-8', :invalid => :replace, :undef => :replace, :replace => '_')
    log(@logger, @queue, process_id, "The message is #{message_body}")
    @github_client.create_issue(dat["base"]["full_name"], "Contributor license is required", message_body)     
    
  end

end




