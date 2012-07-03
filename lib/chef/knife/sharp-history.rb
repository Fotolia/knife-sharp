module KnifeSharp
  class SharpHistory < Chef::Knife
    banner "knife sharp history"
    
    option :debug,
      :long  => '--debug',
      :description => "turn debug on",
      :default => false

    deps do
      require 'chef/data_bag'
      require 'chef/data_bag_item'
      require 'chef/json_compat'
      require 'chef/knife/search'
      require 'chef/environment'
      require 'chef/cookbook/metadata'
      require 'chef/knife/core/object_loader'
    end

    @@cfg_files = [ "/etc/sharp-config.yml", "~/.chef/sharp-config.yml" ]
    
    def load_config
      loaded = false
      @@cfg_files.each do |cfg_file|
        begin
          @@cfg=YAML::load_file(File.expand_path(cfg_file))
          loaded = true
        rescue Exception => e
          puts "Error on loading config : #{e.inspect}" if config[:debug]
        end
      end
      unless loaded == true
        ui.error "config could not be loaded ! Tried the following files : #{@@cfg_files.join(", ")}"
        exit 1
      end
      puts @@cfg.inspect if config[:debug]
    end

    def run
      load_config()
      show_logs()
    end

    def show_logs()
      begin
        fp = File.open(File.expand_path(@@cfg["logging"]["destination"]), "r")
        fp.readlines.each do |line|
          puts line
        end
      rescue Exception => e
        ui.error "oops ! #{e.inspect}"
      end
    end


  end
end
