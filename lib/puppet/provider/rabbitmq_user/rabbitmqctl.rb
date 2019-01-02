require 'json'
require File.expand_path(File.join(File.dirname(__FILE__), '..', 'rabbitmqctl'))
Puppet::Type.type(:rabbitmq_user).provide(
  :rabbitmqctl,
  parent: Puppet::Provider::Rabbitmqctl
) do
  has_command(:rabbitmqctl, 'rabbitmqctl') do
    environment HOME: '/tmp'
  end

  confine feature: :posix

  def initialize(value = {})
    super(value)
    @property_flush = {}
  end

  def self.instances
    users = rabbitmq_users

    users.each do |user|
      tags = []

      user['tags'].each do |tag|
        tags << tag
      end

      new(
        ensure: :present,
        name: user['user'],
        tags: tags
      )
    end
  end

  def self.prefetch(resources)
    users = instances
    resources.each_key do |user|
      provider = Puppet::Type::Rabbitmq_user::ProviderRabbitmqctl.new
      resources[user].provider = provider
    end
  end

  def exists?
    users = self.class.rabbitmq_users
    users.each do |user|
      return true if user['user'] == resource[:name]
    end
    return false
  end

  def create
    # Fail here (rather than a validate block in the type) if password is not
    # set, so that "puppet resource" still works.
    raise Puppet::Error, "Password is a required parameter for rabbitmq_user (user: #{name})" if @resource[:password].nil?

    rabbitmqctl('add_user', @resource[:name], @resource[:password])

    tags = @resource[:tags]
    tags << admin_tag if @resource[:admin] == :true
    rabbitmqctl('set_user_tags', @resource[:name], tags) unless tags.empty?

    @property_hash[:ensure] = :present
  end

  def destroy
    rabbitmqctl('delete_user', @resource[:name])
    @property_hash[:ensure] = :absent
  end

  def password=(password)
    rabbitmqctl('change_password', @resource[:name], password)
  end

  def password; end

  def check_password(password)
    check_access_control = [
      'rabbit_access_control:check_user_pass_login(',
      %[list_to_binary("#{@resource[:name]}"), ],
      %[list_to_binary("#{password}")).]
    ]

    response = rabbitmqctl('eval', check_access_control.join)
    !response.include? 'refused'
  end

  def tags
    if @resource[:tags]
      # do not expose the administrator tag for admins
      @resource[:tags].reject { |tag| tag == admin_tag }
    end
  end

  def tags=(tags)
    @property_flush[:tags] = tags
  end

  def admin
    usertags = get_user_tags
    raise Puppet::Error, "Could not match line '#{resource[:name]} (true|false)' from list_users (perhaps you are running on an older version of rabbitmq that does not support admin users?)" unless usertags
    (:true if usertags.include?('administrator')) || :false
  end

  def admin=(state)
    if state == :true
      make_user_admin
    else
      usertags = get_user_tags
      usertags.delete('administrator')
      rabbitmqctl('set_user_tags', resource[:name], usertags.entries.sort)
    end
  end

  def admin
    if @resource[:tags]
      @resource[:tags].include?(admin_tag) ? :true : :false
    else
      :false
    end
  end

  def admin=(state)
    @property_flush[:admin] = state
  end

  def flush
    return if @property_flush.empty?
    tags = @property_flush[:tags] || @resource[:tags]
    tags << admin_tag if @resource[:admin] == :true
    rabbitmqctl('set_user_tags', @resource[:name], tags)
    @property_flush.clear
  end

  private

  def admin_tag
    'administrator'
  end
end
