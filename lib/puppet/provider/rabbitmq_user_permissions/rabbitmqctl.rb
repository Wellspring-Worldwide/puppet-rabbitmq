require File.expand_path(File.join(File.dirname(__FILE__), '..', 'rabbitmqctl'))
Puppet::Type.type(:rabbitmq_user_permissions).provide(:rabbitmqctl, parent: Puppet::Provider::Rabbitmqctl) do
  if Puppet::PUPPETVERSION.to_f < 3
    commands rabbitmqctl: 'rabbitmqctl'
  else
    has_command(:rabbitmqctl, 'rabbitmqctl') do
      environment HOME: '/tmp'
    end
  end

  confine feature: :posix

  @users = {}

  def self.populate_users
    if Puppet::Util::Package.versioncmp(rabbitmq_version, '3.6') >= 0
      all_users = run_with_retries do
        rabbitmqctl('eval', 'io:format("~s", [rabbit_json:encode(rabbit_auth_backend_internal:list_permissions())]).')
      end
    else
      all_users = run_with_retries do
        rabbitmqctl('eval', 'case rabbit_misc:json_encode(rabbit_auth_backend_internal:list_permissions()) of {ok, JSON} -> io:format("~s", [JSON]) end.')
      end
    end

    all_users.gsub!('ok', '')

    json_users = JSON.parse(all_users)

    if json_users.empty?
      return
    else
      json_users.each do |user|
        puts user
        vhost = user['vhost']
        user_name = user['user']

        configure = user['configure']
        read = user['read']
        write = user['write']

        @users[user_name] = {} unless @users[user_name]
        @users[user_name][vhost] = {
          configure: configure,
          read: read,
          write: write
        }
      end
    end
  end

  # cache users permissions
  def self.users(name, vhost)
    unless @users[name]
     self.populate_users
    end

    if @users[name]
      return @users[name][vhost] if @users[name][vhost]
    else
      return
    end
  end

  def users(name, vhost)
    self.class.users(name, vhost)
  end

  def should_user
    if @should_user
      @should_user
    else
      @should_user = resource[:name].split('@')[0]
    end
  end

  def should_vhost
    if @should_vhost
      @should_vhost
    else
      @should_vhost = resource[:name].split('@')[1]
    end
  end

  def create
    resource[:configure_permission] ||= "''"
    resource[:read_permission]      ||= "''"
    resource[:write_permission]     ||= "''"
    rabbitmqctl('set_permissions', '-p', should_vhost, should_user, resource[:configure_permission], resource[:write_permission], resource[:read_permission])
  end

  def destroy
    rabbitmqctl('clear_permissions', '-p', should_vhost, should_user)
  end

  # I am implementing prefetching in exists b/c I need to be sure
  # that the rabbitmq package is installed before I make this call.
  def exists?
    users(should_user, should_vhost)
  end

  def configure_permission
    users(should_user, should_vhost)[:configure]
  end

  def configure_permission=(_perm)
    set_permissions
  end

  def read_permission
    users(should_user, should_vhost)[:read]
  end

  def read_permission=(_perm)
    set_permissions
  end

  def write_permission
    users(should_user, should_vhost)[:write]
  end

  def write_permission=(_perm)
    set_permissions
  end

  # implement memoization so that we only call set_permissions once
  def set_permissions
    return if @permissions_set

    @permissions_set = true
    resource[:configure_permission] ||= configure_permission
    resource[:read_permission]      ||= read_permission
    resource[:write_permission]     ||= write_permission
    rabbitmqctl(
      'set_permissions',
      '-p', should_vhost,
      should_user,
      resource[:configure_permission],
      resource[:write_permission],
      resource[:read_permission]
    )
  end

  def self.strip_backslashes(string)
    # See: https://github.com/rabbitmq/rabbitmq-server/blob/v1_7/docs/rabbitmqctl.1.pod#output-escaping
    string.gsub(%r{\\\\}, '\\')
  end
end