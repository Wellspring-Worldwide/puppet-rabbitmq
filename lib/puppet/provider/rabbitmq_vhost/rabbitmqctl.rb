require 'json'
require File.expand_path(File.join(File.dirname(__FILE__), '..', 'rabbitmqctl'))
Puppet::Type.type(:rabbitmq_vhost).provide(:rabbitmqctl, parent: Puppet::Provider::Rabbitmqctl) do
  if Puppet::PUPPETVERSION.to_f < 3
    commands rabbitmqctl: 'rabbitmqctl'
  else
    has_command(:rabbitmqctl, 'rabbitmqctl') do
      environment HOME: '/tmp'
    end
  end

  def self.instances
    vhosts = rabbitmq_vhosts

    vhosts.each do |vhost|
      unless vhosts.include? (vhost)
        vhosts << vhost
      end

      new(name: vhost)
    end
  end

  def create
    rabbitmqctl('add_vhost', resource[:name])
  end

  def destroy
    rabbitmqctl('delete_vhost', resource[:name])
  end

  def exists?
    vhosts = self.class.rabbitmq_vhosts unless vhosts
    return vhosts.include? (resource[:name])
  end
end
