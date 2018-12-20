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
    vhost_list = run_with_retries do
      rabbitmqctl('exec', 'rabbit_vhost:list().')
    end

    vhost_list.split(',').map do |line|
      raise Puppet::Error, "Cannot parse invalid vhost line: #{line}" unless line =~ %r{^(\S+)$}
      new(name: Regexp.last_match(1))
    end
  end

  def create
    rabbitmqctl('add_vhost', resource[:name])
  end

  def destroy
    rabbitmqctl('delete_vhost', resource[:name])
  end

  def exists?
    self.class.run_with_retries { rabbitmqctl('eval', 'rabbit_vhost:list().') }.include? resource[:name]
  end
end