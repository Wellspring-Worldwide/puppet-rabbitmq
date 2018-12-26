require 'json'
require 'puppet/util/package'

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'rabbitmqctl'))
Puppet::Type.type(:rabbitmq_policy).provide(:rabbitmqctl, parent: Puppet::Provider::Rabbitmqctl) do
  confine feature: :posix

  @policies = {}

  def self.populate_policies
    if Puppet::Util::Package.versioncmp(rabbitmq_version, '3.7') >= 0
      all_policies = run_with_retries do
        rabbitmqctl('eval', 'io:format("~s", [rabbit_json:encode(rabbit_policy:list())]).').gsub('ok', '')
      end
    else
      all_policies = run_with_retries do
        rabbitmqctl('eval', 'case rabbit_misc:json_encode(rabbit_policy:list()) of {ok, JSON} -> io:format("~s", [JSON]) end.').gsub('ok', '')
      end
    end

    json_policies = JSON.parse(all_policies)

    if json_policies.empty?
      #puts "empty policy list"
      return
    else
      json_policies.each do |policy|
        marshal_policy = policy

        vhost = policy['vhost']
        policy_name = policy['name']

        @policies[vhost] = {} unless @policies[vhost]

        policy_hash = {
          applyto: policy['apply-to'],
          priority: policy['priority'].to_s,
          definition: policy['definition'],
          pattern: policy['pattern']
        }
        @policies[vhost][policy_name] = policy_hash
      end
    end
  end

  def self.policies(vhost,name)
    unless @policies[vhost]
      self.populate_policies
    end

    if @policies[vhost]
      #puts 'vhost exists'
      return @policies[vhost][name] if @policies[vhost][name]
    else
      return
    end
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
    policies(should_vhost, should_policy)[:pattern]
  end

  def pattern=(_pattern)
    set_policy
  end

  def applyto
    policies(should_vhost, should_policy)[:applyto]
  end

  def applyto=(_applyto)
    set_policy
  end

  def definition
    policies(should_vhost, should_policy)[:definition]
  end

  def definition=(_definition)
    set_policy
  end

  def priority
    policies(should_vhost, should_policy)[:priority]
  end

  def priority=(_priority)
    set_policy
  end

  def set_policy
    return if @set_policy
    @set_policy = true
    resource[:applyto]    ||= applyto
    resource[:definition] ||= definition
    resource[:pattern]    ||= pattern
    resource[:priority]   ||= priority
    # rabbitmq>=3.2.0
    if Puppet::Util::Package.versioncmp(self.class.rabbitmq_version, '3.2.0') >= 0
      rabbitmqctl(
        'set_policy',
        '-p', should_vhost,
        '--priority', resource[:priority],
        '--apply-to', resource[:applyto].to_s,
        should_policy,
        resource[:pattern],
        resource[:definition].to_json
      )
    else
      rabbitmqctl(
        'set_policy',
        '-p', should_vhost,
        should_policy,
        resource[:pattern],
        resource[:definition].to_json,
        resource[:priority]
      )
    end
  end
end