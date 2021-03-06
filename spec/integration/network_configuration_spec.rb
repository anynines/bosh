require 'spec_helper'

describe 'network configuration', type: :integration do
  with_reset_sandbox_before_each

  it 'reserves first available dynamic ip' do
    manifest_hash = Bosh::Spec::Deployments.simple_manifest
    manifest_hash['networks'].first['subnets'][0] = {
      'range'    => '192.168.1.0/24',
      'gateway'  => '192.168.1.1',
      'dns'      => ['192.168.1.1'],
      'static'   => ['192.168.1.11', '192.168.1.14'],
      'reserved' => %w(
        192.168.1.2-192.168.1.10
        192.168.1.12-192.168.1.13
        192.168.1.20-192.168.1.254
      ),
      'cloud_properties' => {},
    }

    manifest_hash['resource_pools'].first['size'] = 3
    manifest_hash['jobs'].first['instances'] = 3
    deploy_simple(manifest_hash: manifest_hash)

    # Available dynamic ips - 192.168.1.15 - 192.168.1.19
    # First two (192.168.1.15, 192.168.1.16) to compile packages foo and bar
    output = bosh_runner.run('vms')
    expect(output).to match(/foobar.* 192\.168\.1\.17/)
    expect(output).to match(/foobar.* 192\.168\.1\.18/)
    expect(output).to match(/foobar.* 192\.168\.1\.19/)
  end

  it 'creates new VM if existing VM cannot be reconfigured to desired network settings' do
    manifest_hash = Bosh::Spec::Deployments.simple_manifest
    manifest_hash['networks'].first['subnets'].first['static'] = %w(192.168.1.100)
    manifest_hash['resource_pools'].first['size'] = 1
    manifest_hash['jobs'].first['instances'] = 1
    deploy_simple(manifest_hash: manifest_hash)

    current_sandbox.cpi.commands.make_configure_networks_not_supported(
      current_sandbox.cpi.vm_cids.first,
    )

    manifest_hash['jobs'].first['networks'].first['static_ips'] = '192.168.1.100'
    deploy_simple_manifest(manifest_hash: manifest_hash)

    output = bosh_runner.run('vms')
    expect(output).to match(/192\.168\.1\.100/)
  end

  it 'preserves existing network reservations on a second deployment' do
    manifest_hash = Bosh::Spec::Deployments.simple_manifest
    # For routed subnets larger than /31 or /32,
    # the number of available host addresses is usually reduced by two,
    # namely the largest address, which is reserved as the broadcast address,
    # and the smallest address, which identifies the network itself.

    # range(8) - identity(1) - broadcast(1) - dns(2) = 4 available IPs
    manifest_hash['networks'].first['subnets'][0] = {
      'range'    => '192.168.1.0/29',
      'gateway'  => '192.168.1.1',
      'dns'      => ['192.168.1.1', '192.168.1.2'],
      'static'   => [],
      'reserved' => [],
      'cloud_properties' => {},
    }
    manifest_hash['resource_pools'].first['size'] = 4
    manifest_hash['jobs'].first['instances'] = 4

    deploy_simple(manifest_hash: manifest_hash)

    deploy_simple_manifest(manifest_hash: manifest_hash) # expected to not failed
  end
end
