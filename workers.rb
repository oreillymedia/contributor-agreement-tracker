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


def log(logger, queue, process_id, msg)
  logger.info "#{queue} \t #{process_id} \t #{msg}"
end




# This worker adds a webhook to the specified repo.
class WebhookWorker

  include Resque::Plugins::Status
  @queue = "webhook_worker"
  @logger ||= Logger.new(STDOUT)   
  @github_client ||= Octokit::Client.new(:login => ENV["GITHUB_LOGIN"], :oauth_token => ENV["GITHUB_TOKEN"])
  
  def self.perform(process_id, msg)
    log(@logger, @queue, process_id, "Attempting to add webhook #{msg}")
    begin
       @github_client.create_hook(
         msg["repo"],
         'web',
         {
           :url => msg["callback"],
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
class CLAWorker

  include Resque::Plugins::Status
  @queue = "cla_worker"
  @logger ||= Logger.new(STDOUT)   
  @github_client ||= Octokit::Client.new(:login => ENV["GITHUB_LOGIN"], :oauth_token => ENV["GITHUB_TOKEN"])
  
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
    c = @github_client.contents("oreillymedia/checklists", {:path => "legal/cla_missing.md"})
    checklist_text = Base64.decode64(c["content"])
    message_body = Mustache.render(checklist_text, dat).encode('utf-8', :invalid => :replace, :undef => :replace, :replace => '_')
    log(@logger, @queue, process_id, "The message is #{message_body}")
    @github_client.add_comment(dat["base"]["full_name"], dat["number"], message_body)     
    
  end

end


