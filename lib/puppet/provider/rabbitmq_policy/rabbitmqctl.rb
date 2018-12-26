require 'json'
require 'puppet/util/package'

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'rabbitmqctl'))
Puppet::Type.type(:rabbitmq_policy).provide(:rabbitmqctl, parent: Puppet::Provider::Rabbitmqctl) do
  confine feature: :posix

  @policies = {}

  def self.populate_policies
    all_policies = run_with_retries do
      rabbitmqctl('eval', 'io:format("~s", [rabbit_json:encode(rabbit_policy:list())]).').gsub('ok', '')
    end

    JSON.parse(all_policies).each do |policy|
      marshal_policy = policy

      vhost = policy['vhost']
      policy_name = policy['name']

      @policies[vhost] = {} unless @policies[vhost]
      @policies[vhost][policy_name] = { 
        'apply-to' => policy['apply-to'],
        'priority' => policy['priority'],
        'definition' => policy['definition'],
        'pattern' => policy['pattern'],
      }
    end
  end

  def self.policies(vhost,name)
    unless @policies[vhost]
      puts "Could not find populated policies for vhost #{vhost}"
      self.populate_policies
    end

    unless @policies[vhost][name]
      puts "Could not find policy #{name} for #{vhost}"
    else
      @policies[vhost][name]
    end
  end

  # cache policies
  def self.old_policies(vhost, name)
    @policies = {} unless @policies
    unless @policies[vhost]
      @policies[vhost] = {}
      policy_list = run_with_retries do
        rabbitmqctl(exec_args, 'list_policies', '-p', vhost)
      end

      # rabbitmq<3.2 does not support the applyto field
      # 1 2      3?  4  5                                            6
      # / ha-all all .* {"ha-mode":"all","ha-sync-mode":"automatic"} 0 << This is for RabbitMQ v < 3.7.0
      # / ha-all .* all {"ha-mode":"all","ha-sync-mode":"automatic"} 0 << This is for RabbitMQ v >= 3.7.0
      if Puppet::Util::Package.versioncmp(rabbitmq_version, '3.7') >= 0
        regex = %r{^(\S+)\s+(\S+)\s+(\S+)\s+(all|exchanges|queues)?\s+(\S+)\s+(\d+)$}
        applyto_index = 4
        pattern_index = 3
      else
        regex = %r{^(\S+)\s+(\S+)\s+(all|exchanges|queues)?\s*(\S+)\s+(\S+)\s+(\d+)$}
        applyto_index = 3
        pattern_index = 4
      end

      policy_list.split(%r{\n}).each do |line|
        raise Puppet::Error, "cannot parse line from list_policies:#{line}" unless line =~ regex
        n          = Regexp.last_match(2)
        applyto    = Regexp.last_match(applyto_index) || 'all'
        priority   = Regexp.last_match(6)
        definition = JSON.parse(Regexp.last_match(5))
        # be aware that the gsub will reset the captures
        # from the regexp above
        pattern    = Regexp.last_match(pattern_index).to_s.gsub(%r{\\\\}, '\\')

        @policies[vhost][n] = {
          applyto: applyto,
          pattern: pattern,
          definition: definition,
          priority: priority
        }
      end
    end
    @policies[vhost][name]
  end

  def policies(vhost, name)
    self.class.policies(vhost, name)
  end

  def should_policy
    @should_policy ||= resource[:name].rpartition('@').first
  end

  def should_vhost
    @should_vhost ||= resource[:name].rpartition('@').last
  end

  def create
    set_policy
  end

  def destroy
    rabbitmqctl('clear_policy', '-p', should_vhost, should_policy)
  end

  def exists?
    policies(should_vhost, should_policy)
  end

  def pattern
    policies(should_vhost, should_policy)["pattern"]
  end

  def pattern=(_pattern)
    set_policy
  end

  def applyto
    policies(should_vhost, should_policy)["apply-to"]
  end

  def applyto=(_applyto)
    set_policy
  end

  def definition
    policies(should_vhost, should_policy)["definition"]
  end

  def definition=(_definition)
    set_policy
  end

  def priority
    policies(should_vhost, should_policy)["priority"]
  end

  def priority=(_priority)
    set_policy
  end

  def set_policy
    return if @set_policy
    @set_policy = true
    resource["apply-to"]    ||= applyto
    resource["definition"] ||= definition
    resource["pattern"]    ||= pattern
    resource["priority"]   ||= priority
    # rabbitmq>=3.2.0
    if Puppet::Util::Package.versioncmp(self.class.rabbitmq_version, '3.2.0') >= 0
      rabbitmqctl(
        'set_policy',
        '-p', should_vhost,
        '--priority', resource["priority"],
        '--apply-to', resource["apply-to"].to_s,
        should_policy,
        resource["pattern"],
        resource["definition"].to_json
      )
    else
      rabbitmqctl(
        'set_policy',
        '-p', should_vhost,
        should_policy,
        resource["pattern"],
        resource["definition"].to_json,
        resource["priority"]
      )
    end
  end
end
