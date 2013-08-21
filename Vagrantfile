Vagrant.configure("2") do |config|
  config.vm.box = "lucid64"
  config.vm.box_url = "http://files.vagrantup.com/lucid64.box"

  parent_folder = File.expand_path("..", Dir.pwd)

  config.vm.network :forwarded_port, guest: 9393, host: 9393
  config.vm.network :forwarded_port, guest: 3000, host: 3000
  config.vm.network :forwarded_port, guest: 8888, host: 8888

  config.vm.provision :shell, :inline => "gem install chef --version 11.6.0.rc2 --no-rdoc --no-ri --conservative"

  config.vm.provision "chef_solo" do |chef|
    chef.cookbooks_path = File.join(parent_folder, "orm-atlas-cookbooks")
    chef.json = {
      "deploy_to" => "/vagrant",
      "bundle_path" => ".bundle",
      "user" => "vagrant",
      "group" => "vagrant",
      "environment" => {
        "RACK_ENV" => "development",
        "PORT" => "3000",
        "REDISTOGO_URL" => "redis://localhost:6379/",
      },
      "postgresql" => {
        "password" => {
          "postgres" => "atlas"
        },
        "config" => {
          'listen_addresses' => "*"
        }
      },
      'rbenv' => {
        'user_installs' => [
          {
            'user' => 'vagrant',
            'rubies' => [ "1.9.3-p448" ],
            'global' => '1.9.3-p448'
          }
        ]
      }
    }

    chef.add_recipe "atlas::configure_localhost"
    chef.add_recipe "atlasworkers::configure_localhost"
  end

end
