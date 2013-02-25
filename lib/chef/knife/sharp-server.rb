module KnifeSharp
  class SharpServer < Chef::Knife

    banner "knife sharp server [SERVERNAME] [--machine]"

    option :machine,
      :short => '-m',
      :long  => '--machine',
      :description => "turn machine output on",
      :default => false

    def run
      if File.exists?(knife_conf) and !File.symlink?(knife_conf)
        ui.error "#{knife_conf} is not a symlink."
        ui.msg "Copy it to #{knife_conf("<server name>")} and try again."
        exit 1
      end
      unless name_args.size == 1
        list_configs
        exit 0
      end
      update_config(name_args.first)
    end

    def update_config(new_server)
      cur_conf = knife_conf
      new_conf = knife_conf(new_server)
      if File.exists?(new_conf)
        File.unlink(cur_conf) if File.exists?(cur_conf)
        File.symlink(new_conf, cur_conf)
        ui.msg "The knife configuration has been updated to use #{new_server}."
      else
        ui.error "Knife configuration for #{new_server} not found."
        list_configs
        exit 1
      end
    end

    def list_configs
      if config[:machine] == true
        server = current_server()
        if server
          ui.msg server
        else
          ui.msg "invalid"
        end
      else
        avail_confs = Dir.glob(File.join(Chef::Knife::chef_config_dir, "knife-*.rb"))
        if !avail_confs.empty?
          ui.msg "Available servers:"
          avail_confs.each do |file|
            server = extract_server(file)
            prefix = (server == current_server) ? ">> " : "   "
            ui.msg "#{prefix}#{server} (#{file})"
          end
        else
          ui.msg "No knife server configuration file found."
        end
      end
    end

    def extract_server(config_filename)
      match = config_filename.match(/#{Chef::Knife::chef_config_dir}\/knife-(\w+)\.rb/)
      match ? match[1] : nil
    end

    def knife_conf(server = nil)
      srv = server ? "-#{server}" : ""
      File.join(Chef::Knife::chef_config_dir, "knife#{srv}.rb")
    end

    def current_server
      cur_conf = knife_conf
      extract_server(File.readlink(cur_conf)) if File.exists?(cur_conf) and File.symlink?(cur_conf)
    end
  end
end
