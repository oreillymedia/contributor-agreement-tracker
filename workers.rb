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

LOGGER ||= Logger.new(STDOUT)   

def log(queue, process_id, msg)
  LOGGER.info "#{queue} \t #{process_id} \t #{msg}"
end

# Get a hook to redis to use as a cache
uri = URI.parse(ENV["REDIS_URL"])
Resque.redis = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password, :thread_safe => true)


      
#
# Email queue for sending notices
#
class EmailWorker

  include Resque::Plugins::Status
  @queue = "email_worker"
  
  
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
    log(@queue, process_id, "sending an email to #{msg['to']}")
    mail = Mail.deliver do
      to msg['to']
      cc msg['cc']
      from msg['from']
      subject msg['subject']
      text_part do
        body msg['body']
      end
    end
  end
    
end


# This worker adds a webhook to the specified repo.
class AddWebhookWorker

  include Resque::Plugins::Status
  @queue = "webhook_worker"
  @github_client = Octokit::Client.new( :access_token => ENV["GITHUB_TOKEN"])
    
  def self.perform(process_id, msg)
    log(@queue, process_id, "Attempting to add webhook #{msg} #{ENV['GITHUB_LOGIN']}")
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
       log(@queue, process_id, "Created webhook")
    rescue Exception => e
       log(@queue, process_id, "Could not connect to github API - #{e}")
       raise e
    end
  end
end


# 
# This fuction returns whether or not a given user should get a notification.  Return value invclede
#   none -- do not send a notice
#   request -- send a requst, which means it's the first time we're contracting the user
#   remind -- send a reminder, which happens after the initial contact
#
def notify_user(user, user_type, queue, process_id)
  action = "request"
  log(queue, process_id, "notification testing for #{user}")   
  c = Contributor.first(:email => user)    
  n = Notification.first(:user => user)
  if user_type == "github"
    c = Contributor.first(:github_handle => user)    
  end
      
  if c
    log(queue, process_id, "Contributor record exists for #{user}")   
    if c.date_accepted
      log(queue, process_id, "#{user} has accepted the contributor agreement")   
      action = "none"
    else
      log(queue, process_id, "#{user} has not accepted the contributor agreement")   
      if n
        if (Date.today - n.date_sent).to_i < 3
          log(queue, process_id, "#{user} has been notified in the last 3 days")   
          action = "none"
        else
          log(queue, process_id, "#{user} has not been notified in the last 3 days")   
          action = "remind"
        end  
      end
    end
  else
    log(queue, process_id, "Contributor record does not exist for #{user}")   
    if n
      if (Date.today - n.date_sent).to_i < 3
        log(queue, process_id, "#{user} has been notified in the last 3 days")   
        action = "none"
      else
        log(queue, process_id, "#{user} has not been notified in the last 3 days")   
      end          
    end
  end
  return action
end


# This worker responds to a pull request sent to a repo and sends a CLS
class CLAPushWorker

  include Resque::Plugins::Status
  @queue = "cla_push_worker"
  
  def self.perform(process_id, msg)
       
    # get a list of all contributors
    @process_id = process_id
     authorsArray = msg["body"]["commits"].map { |hash| hash["author"] }
     log(@queue, process_id, "Contributors are #{authorsArray}")   
     authorsArray.each do |c|   
       # Set the message to a request to register
        subject = "O'Reilly Media Contribution Agreement"
        body = IO.read('docs/email_request.md')
        payload = { 
          "url" => msg["body"]["repository"]["url"] 
        }       
        
        action = notify_user(c["email"], "email", @queue, process_id)
        
        # If the action require a reminder, then make the necessary changes
        if action == "remind"
          subject = "Reminder about your O'Reilly Media contribution"
          body = IO.read('docs/email_reminder.md')
          c = Contributor.first(:email => user)    
          payload = { 
            "url" => msg["body"]["repository"]["url"], 
            "confirmation_code" => c.confirmation_code
          }
         end
        
         if action != "none"
           log(@queue, @process_id, "Sending #{c['email']} a nag!")  
           # If we're sending a notification, destroy any existing notification records (if any)
           n = Notification.first(:user => c["email"])
           if n
             n.destroy
           end    
           #
           # queue up an email notification
           #       
           job = EmailWorker.create({
             "to" => c["email"],
             "from" => ENV["CLA_ALIAS"],
             "cc" => ENV["CLA_ALIAS"],
             "subject" => subject,
             "body" => Mustache.render(body, payload)
           })         
           #
           # Update the notification list to record when we last contacted the user
           #  
           n = Notification.new
           n.user  = c["email"]
           n.date_sent = Date.today
           n.save
        end       
     end
  end
  
end


# This worker responds to a pull request sent to a repo and sends a CLS
class CLAPullWorker

  include Resque::Plugins::Status
  @queue = "cla_pull_worker"
  @github_client = Octokit::Client.new( :access_token => ENV["GITHUB_TOKEN"])

  def self.perform(process_id, msg)
    # Pull out the template from the checklist repo on github and process the variables using mustache
    log(@queue, process_id, "Processing pull request from #{msg['body']['sender']['login']}")
    
    # we only care about pull requests being opened
    if msg["body"]["action"] != "opened"
      return "none"
    end
    
    subject = "O'Reilly Media Contribution Agreement"
    body = IO.read('docs/issue_request.md')
    payload = {
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

    action = notify_user(payload["sender"], "github", @queue, process_id)
    
    if action != "none"
      log(@queue, process_id, "Sending notice to #{msg['body']['sender']['login']}")
      # If we're sending a notification, destroy any existing notification records (if any)
      n = Notification.first(:user => payload["sender"])
      if n
        n.destroy
      end          
      message_body = Mustache.render(body, payload)
      @github_client.create_issue(payload["base"]["full_name"], subject, Mustache.render(body,payload))       
      #
      # Update the notification list to record when we last contacted the user
      #  
      n = Notification.new
      n.user  = payload["sender"]
      n.date_sent = Date.today
      n.save
         
    end
  end

end




