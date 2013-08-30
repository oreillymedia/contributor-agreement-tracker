require 'mustache'
require 'logger'
require 'resque'
require 'resque-status'
require 'redis'
require 'mail'
require 'octokit'
require 'dotenv'

Dotenv.load

# To start these, use this command:
#   rake resque:work QUEUE=*

def log(logger, queue, process_id, msg)
  logger.info "#{queue} \t #{process_id} \t #{msg}"
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
class WebhookWorker

  include Resque::Plugins::Status
  @queue = "webhook_worker"
  @logger ||= Logger.new(STDOUT)   
  @github_client ||= Octokit::Client.new(:login => ENV["GITHUB_LOGIN"], :oauth_token => ENV["GITHUB_TOKEN"])
    
  def self.perform(process_id, msg)
    log(@logger, @queue, process_id, "Attempting to add webhook #{msg} #{ENV['GITHUB_LOGIN']}")
    begin
       @github_client.create_hook(
         msg["repo"],
         'web',
         {
           :url => ENV["VALIDATION_HOOK"],
           :content_type => 'json'
         },
         {
           :events => ['pull_request', 'push'],
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
class CLAWorker

  include Resque::Plugins::Status
  @queue = "cla_worker"
  @logger ||= Logger.new(STDOUT)   
  @github_client ||= Octokit::Client.new(:login => ENV["GITHUB_LOGIN"], :oauth_token => ENV["GITHUB_TOKEN"])

  $WEBHOOK_ISSUE_TEXT = IO.read('docs/webhook_issue_text.md')
  
  def self.perform(process_id, msg)
    # get a list of all contributors
    authorsArray = x["body"]["commits"].map { |hash| hash["author"] }
    log(@logger, @queue, process_id, "The contributors are #{authorsArray}")

#    # Pull out the template from the checklist repo on github and process the variables using mustache
#    message_body = Mustache.render($WEBHOOK_ISSUE_TEXT, dat).encode('utf-8', :invalid => :replace, :undef => :replace, :replace => '_')
#    log(@logger, @queue, process_id, "The message is #{message_body}")
#    @github_client.add_comment(dat["base"]["full_name"], dat["number"], message_body)     
    
  end

end






