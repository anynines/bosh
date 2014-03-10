# Copyright (c) 2009-2012 VMware, Inc.

module Bosh::Agent
  class Platform::Linux::Disk
    include Bosh::Exec

    VSPHERE_DATA_DISK = "/dev/sdb"
    WARDEN_DATA_DISK = "/dev/invalid" # Warden doesn't use any data disk
    DEV_PATH_TIMEOUT=180
    DISK_RETRY_MAX_DEFAULT = 30

    def initialize
      @config   = Bosh::Agent::Config
      @platform_name = @config.platform_name
      @logger   = @config.logger
      @store_dir = File.join(@config.base_dir, 'store')
      @dev_path_timeout = DEV_PATH_TIMEOUT
      @disk_retry_timeout = DISK_RETRY_MAX_DEFAULT
      @mounter = Mounter.new(@logger)
    end

    def mount_persistent_disk(cid, options={})
      FileUtils.mkdir_p(@store_dir)
      disk = lookup_disk_by_cid(cid)
      partition = is_disk_blockdev?? "#{disk}1" : "#{disk}"
      mount_partition(partition, @store_dir, options)
    end

    def is_disk_blockdev?
      case @config.infrastructure_name
        when "vsphere", "aws", "openstack"
          true
        when "warden"
          false
        else
          raise Bosh::Agent::FatalError, "call is_disk_blockdev failed, unsupported infrastructure #{Bosh::Agent::Config.infrastructure_name}"
      end
    end

    def mount_partition(partition, mount_point, options={})
      infra_option = {}
      case @config.infrastructure_name
        when "vsphere", "aws", "openstack"
          nil
        when "warden"
          infra_option = { bind_mount: true }
        else
          raise Bosh::Agent::FatalError, "call is_disk_blockdev failed, unsupported infrastructure #{Bosh::Agent::Config.infrastructure_name}"
      end

      proceed_mount = is_disk_blockdev?? File.blockdev?(partition) : true

      if proceed_mount && !mount_exists?(partition)
        mounter.mount(partition, mount_point, options.merge(infra_option))
      end
    end

    def get_data_disk_device_name
      case @config.infrastructure_name
        when "vsphere", "vcloud"
          VSPHERE_DATA_DISK
        when "aws", "openstack"
          settings = @config.settings
          dev_path = settings['disks']['ephemeral']
          unless dev_path
            raise Bosh::Agent::FatalError, "Unknown data or ephemeral disk" if @config.infrastructure_name == "aws"
            @logger.warn("No ephemeral disk set, using root device for BOSH agent data!!!")
            return nil
          end
          get_available_path(dev_path)
        when "warden"
          WARDEN_DATA_DISK
        else
          raise Bosh::Agent::FatalError, "Lookup disk failed, unsupported infrastructure #{Bosh::Agent::Config.infrastructure_name}"
      end
    end

    def lookup_disk_by_cid(cid)
      disk_id = @config.settings['disks']['persistent'][cid]

      if disk_id.nil?
        raise Bosh::Agent::FatalError, "Unknown persistent disk: #{cid}"
      end

      case @config.infrastructure_name
        when "vsphere", "vcloud"
          # VSphere passes in scsi disk id
          get_available_scsi_path(disk_id)
        when "aws", "openstack"
          # AWS & OpenStack pass in the device name
          get_available_path(disk_id)
        when "warden"
          # Warden directly stores the device path
          disk_id
        else
          raise Bosh::Agent::FatalError, "Lookup disk failed, unsupported infrastructure #{Bosh::Agent::Config.infrastructure_name}"
      end
    end

    def detect_block_device(disk_id)
      device_path = "/sys/bus/scsi/devices/2:0:#{disk_id}:0/block/*"
      dirs = Dir.glob(device_path, 0)
      raise Bosh::Agent::DiskNotFoundError, "Unable to find disk #{device_path}" if dirs.empty?

      File.basename(dirs.first)
    end

    private

    def rescan_scsi_bus
      sh "rescan-scsi-bus.sh"
    end

    def get_dev_paths(dev_path)
      dev_paths = [] << dev_path
      dev_path_suffix = dev_path.match("/dev/sd(.*)")
      unless dev_path_suffix.nil?
        dev_paths << "/dev/vd#{dev_path_suffix[1]}"  # KVM
        dev_paths << "/dev/xvd#{dev_path_suffix[1]}" # Xen
      end
      dev_paths
    end

    def get_available_path(dev_path)
      start = Time.now
      dev_paths = get_dev_paths(dev_path)
      while Dir.glob(dev_paths).empty?
        @logger.info("Waiting for #{dev_paths}")
        sleep 0.1
        if (Time.now - start) > @dev_path_timeout
          raise Bosh::Agent::FatalError, "Timed out waiting for #{dev_paths}"
        end
      end
      Dir.glob(dev_paths).last
    end

    def get_available_scsi_path(disk_id)
      rescan_scsi_bus
      blockdev = nil
      Bosh::Common.retryable(tries: @disk_retry_timeout, on: Bosh::Agent::DiskNotFoundError) do
        blockdev = detect_block_device(disk_id)
      end
      File.join('/dev', blockdev)
    end

    def mount_exists?(partition)
      `mount`.lines.select { |l| l.match(/#{partition}/) }.first
    end

    private

    attr_reader :mounter
  end
end
