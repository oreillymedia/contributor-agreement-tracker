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
    log(@queue, process_id, "Attempting to send an email #{msg}")
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

# This worker responds to a pull request sent to a repo and sends a CLS
class CLAPushWorker

  include Resque::Plugins::Status
  @queue = "cla_push_worker"
  @process_id = ""

  def self.send_email(to, subject, body)
    job = EmailWorker.create({
      "to" => to,
      "from" => ENV["CLA_ALIAS"],
      "cc" => ENV["CLA_ALIAS"],
      "subject" => subject,
      "body" => body
    })
  end 
  
  def self.notify_user(user_rec, msg)
    notify = true
    log(@queue, @process_id, "notification testing for #{user_rec}")   
    subject = "O'Reilly Media Contribution Agreement"
    body = IO.read('docs/email_request.md')
    payload = { "url" => msg["body"]["repository"]["url"] }
    u = Contributor.first(:email => user_rec['email'])        
    if u && u['date_accepted']
      # they've accepted the agreement, so we're all set
      log(@queue, @process_id, "#{user_rec} has accepted the contributor agreement on #{u.date_accepted}")   
      notify = false
    else 
      log(@queue, @process_id, "User has not accepted the agreement. Checking if we need to notify him or her")   
      n = Notification.first(:user => user_rec["email"], :channel => "email")
      if n && ((Date.today - n.date_sent).to_i > 2) 
         email_data["subject"] = "Reminder about your O'Reilly Media contribution"
         # if they've already started the process and just forgotten to click verify, then send them their link again
         if u
           message_body = IO.read('docs/email_reminder.md')
           message_payload["confirmation_code"] = u.confirmation_code
         end
         n.destroy   # delete the current notification record
      end
    end               
    # Now send the notice, if necessary
    if notify
      self.send_email(user_rec["email"], subject, Mustache.render(body, payload))
      n = Notification.new
      n.user  = user_rec["email"]
      n.channel = "email"
      n.date_sent = Date.today
      n.save
    end  
  end
  
  def self.perform(process_id, msg)
    # get a list of all contributors
    @process_id = process_id
     authorsArray = msg["body"]["commits"].map { |hash| hash["author"] }
     log(@queue, process_id, "Contributors are #{authorsArray}")   
     authorsArray.each do |c|   
        self.notify_user(c, msg)
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
    log(@queue, process_id, "Processing request from #{msg['body']['sender']['login']}")
    user = Contributor.first(:github_handle => msg["body"]["sender"]["login"])
#    action =  notify_user_action(user)         
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
    action = "none"
    if action != "none"
      issue_text = IO.read('docs/pull_webhook_issue_text.md')
      if action == "nag"
        issue_text = IO.read('docs/pull_webhook_issue_reminder_text.md')
        dat["confirmation_code"] = user.confirmation_code
      end 
      log(@queue, process_id, "Sending notice to #{msg['body']['sender']['login']}")
      message_body = Mustache.render(issue_text, dat).encode('utf-8', :invalid => :replace, :undef => :replace, :replace => '_')       
      @github_client.create_issue(dat["base"]["full_name"], "Contributor license is required", message_body)     
    else
      log(@queue, process_id, "#{msg['body']['sender']['login']} has already registered.")
    end
  end

end




