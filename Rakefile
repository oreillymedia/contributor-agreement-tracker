require "./workers"
require "resque/tasks"

namespace :db do

  desc "create a database"
  task :create do
     `createdb -h localhost agreements`    
  end
  
end