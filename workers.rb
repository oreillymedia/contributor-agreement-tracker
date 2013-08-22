require 'mustache'
require 'dotenv'
require 'logger'
require 'resque'
require 'resque-status'
require 'redis'
require 'mail'

Dotenv.load

# To start these, use this command:
#   rake resque:work QUEUE=*

# Configure redis
uri = URI.parse(ENV["REDIS_URL"])
Resque.redis = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password, :thread_safe => true)


def log(logger, queue, process_id, msg)
  logger.info "#{queue} \t #{process_id} \t #{msg}"
end


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
  
  
  def perform(process_id, msg)   
    
    log(@logger, @queue, process_id, "Attempting to send an email #{msg}")
    email_body = IO.read(msg['email_src'])
    mail = Mail.deliver do
      to msg['to']
      cc ENV["CLA_ALIAS"]
      from cc ENV["CLA_ALIAS"]
      subject msg['subject']
      text_part do
        body Mustache.render(email_body,msg['payload'])
      end
    end
  end
    
end


