module KnifeSharp
  class SharpServer < Chef::Knife

    banner "knife sharp server [SERVERNAME]"

    def run
      if File.exists?(knife_conf)
        if !File.symlink?(knife_conf)
          ui.error "#{knife_conf} is not a symlink."
          ui.msg "Copy it to #{knife_conf("<server name>")} and try again."
          exit 1
        end
      end
      unless name_args.size == 1
        list_configs
        exit 0
      end

      update_config(name_args.first)
    end

    def update_config(new_server)
      if File.exists?(knife_conf(new_server))
        File.unlink(knife_conf) if File.exists?(knife_conf)
        File.symlink(knife_conf(new_server), knife_conf)
        ui.msg "The knife configuration has been updated to use #{new_server}."
      else
        ui.error "Knife configuration for #{new_server} not found."
        list_configs
        exit 1
      end
    end

    def list_configs
      current_conf = File.readlink(knife_conf) if File.exists?(knife_conf)
      avail_confs = Dir.glob(File.join(Chef::Knife::chef_config_dir, "knife-*.rb"))
      if !avail_confs.empty?
        ui.msg "Available servers:"
        avail_confs.each do |file|
          name = file.match(/#{Chef::Knife::chef_config_dir}\/knife-(?<srv>.*)\.rb/)
          prefix = (file == current_conf) ? ">> " : "   "
          ui.msg "#{prefix}#{name[:srv]} (#{file})"
        end
      else
        ui.msg "No knife server configuration file found."
      end
    end

    def knife_conf(server = nil)
      srv = server ? "-#{server}" : ""
      File.join(Chef::Knife::chef_config_dir, "knife#{srv}.rb")
    end
  end
end
