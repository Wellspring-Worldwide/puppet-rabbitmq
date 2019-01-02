require 'json'
class Puppet::Provider::Rabbitmqctl < Puppet::Provider
  initvars
  commands rabbitmqctl: 'rabbitmqctl'

  def self.rabbitmq_version
    @@rabbit_version ||= eval(rabbitmqctl('eval', 'rabbit_misc:version().'))
  end

  def self.rabbitmq_vhosts
    @@rabbit_vhosts ||= JSON.parse(rabbitmqctl('eval', '[binary_to_list(X) || X <- rabbit_vhost:list()].'))
    return @@rabbit_vhosts
  end

  def self.rabbitmq_users
    if Puppet::Util::Package.versioncmp(rabbitmq_version, '3.7') >= 0
      @@rabbit_users ||= JSON.parse(rabbitmqctl('eval', 'io:format("~s", [rabbit_json:encode(rabbit_auth_backend_internal:list_users())]).').gsub('ok', ''))
    else
      @@rabbit_users ||= JSON.parse(rabbitmqctl('eval', 'case rabbit_misc:json_encode(rabbit_auth_backend_internal:list_users()) ok {ok, JSON} -> io:format("~s", [JSON]) end.').gsub('ok', ''))
    end
    return @@rabbit_users
  end

  def self.exec_args
    if Puppet::Util::Package.versioncmp(rabbitmq_version, '3.7.9') >= 0
      ['--no-table-headers', '-q']
    else
      '-q'
    end
  end

  # Retry the given code block 'count' retries or until the
  # command suceeeds. Use 'step' delay between retries.
  # Limit each query time by 'timeout'.
  # For example:
  #   users = self.class.run_with_retries { rabbitmqctl 'list_users' }
  def self.run_with_retries(count = 30, step = 6, timeout = 10)
    count.times do |_n|
      begin
        output = Timeout.timeout(timeout) do
          yield
        end
      rescue Puppet::ExecutionFailure, Timeout::Error
        Puppet.debug 'Command failed, retrying'
        sleep step
      else
        Puppet.debug 'Command succeeded'
        return output
      end
    end
    raise Puppet::Error, "Command is still failing after #{count * step} seconds expired!"
  end
end
