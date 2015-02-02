require 'chef/knife'

module KnifeSharp
  class SharpBackup < Chef::Knife

    banner "knife sharp backup"

    deps do
      require 'chef/environment'
      require 'chef/role'
      require 'chef/data_bag'
      require 'chef/data_bag_item'
    end

    def run
      setup()
      backup()
    end

    def setup
      # Sharp config
      cfg_files = [ "/etc/sharp-config.yml", "~/.chef/sharp-config.yml" ]
      loaded = false
      cfg_files.each do |cfg_file|
        begin
          @cfg = YAML::load_file(File.expand_path(cfg_file))
          loaded = true
        rescue Exception => e
          ui.error "Error on loading config : #{e.inspect}" if config[:debug]
        end
      end
      unless loaded == true
        ui.error "config could not be loaded ! Tried the following files : #{cfg_files.join(", ")}"
        exit 1
      end

      # Knife config
      if (ENV['HOME'] && File.exist?(File.join(ENV['HOME'], '.chef', 'knife.rb')))
        Chef::Config.from_file(File.join(ENV['HOME'], '.chef', 'knife.rb'))
      else
        ui.error "Cannot find knife.rb config file"
        exit 1
      end

    end

    def backup
      timestamp = Time.now.to_i

      unless  @cfg["global"]["backupdir"]
        ui.error "You need to add global/backupdir to your config file"
        exit 1
      end

      backup_path = @cfg["global"]["backupdir"] + "/backup-#{timestamp}"

      if File.exist?(backup_path)
        ui.error "Backup path (#{backup_path}) exists. Will not overwrite."
        exit 1
      end

      ui.msg("Backing up roles")
      FileUtils.mkdir_p(backup_path + "/roles")
      Chef::Role.list.keys.each do |role|
        begin
          remote_role = Chef::Role.load(role)
          File.open(backup_path + "/roles/#{role}.json", "w") do |file|
            file.puts JSON.pretty_generate(remote_role)
          end
        rescue Exception => e
          ui.error "Unable to dump #{role} role (#{e.message})"
        end
      end

      ui.msg("Backing up environments")
      FileUtils.mkdir_p(backup_path + "/environments")
      Chef::Environment.list.keys.each do |environment|
        begin
          env = Chef::Environment.load(environment)
          File.open(backup_path + "/environments/#{environment}.json", "w") do |file|
            file.puts JSON.pretty_generate(env)
          end
        rescue Exception => e
          ui.error "Unable to dump #{environment} environment (#{e.message})"
        end
      end

      ui.msg("Backing up databags")
      FileUtils.mkdir_p(backup_path + "/databags")
      Chef::DataBag.list.keys.each do |bag|
        Dir.mkdir(backup_path + "/databags/" + bag)
        Chef::DataBag.load(bag).keys.each do |item|
          begin
            data = Chef::DataBagItem.load(bag,item)
            File.open(backup_path + "/databags/#{bag}/#{item}.json", "w") do |file|
              file.puts JSON.pretty_generate(data)
            end
          rescue Exception => e
            ui.error "Unable to dump item #{item} from databag #{bag} (#{e.message})"
          end
        end
      end

    end

  end
end
