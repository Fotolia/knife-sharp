module KnifeSharp
  class SharpRollback < Chef::Knife

    banner "knife sharp rollback [--list] [--to <identifier>] [--show <identifier>]"

    option :list,
      :short => '-l',
      :long  => '--list',
      :description => "lists rollback points",
      :default => false

    option :to,
      :short => "-t",
      :long  => "--to",
      :description => "the rollback point identifier",
      :default => nil

    option :show,
      :short => "-s",
      :long => "--show",
      :description => "show what the rollback point contains",
      :default => false

    deps do
      require 'chef/cookbook/metadata'
      require 'chef/cookbook_loader'
      require 'chef/cookbook_uploader'
    end

    def run()
      setup()
      list_rollback_points() if @do_list
      show_rollback_point(@identifier) if @do_show
      rollback_to(@identifier) if @do_rollback
    end

    def setup()
      @do_list, @do_show, @do_rollback = false, false, false

      # check cli flags
      if config[:list]
        @do_list = true
      end

      if config[:show]
        @do_show = true
        @identifier = name_args
      end

      if config[:to]
        @do_rollback = true
        @identifier = name_args
      end

      # Sharp config
      cfg_files = [ "/etc/sharp-config.yml", "~/.chef/sharp-config.yml" ]
      loaded = false
      cfg_files.each do |cfg_file|
        begin
          @cfg = YAML::load_file(File.expand_path(cfg_file))
          loaded = true
        rescue Exception => e
          ui.error "Error on loading config : #{e.inspect}" if config[:verbosity] > 0
        end
      end
      unless loaded == true
        ui.error "config could not be loaded ! Tried the following files : #{cfg_files.join(", ")}"
        exit 1
      end

      # Knife config
      if Chef::Knife.chef_config_dir && File.exists?(File.join(Chef::Knife.chef_config_dir, "knife.rb"))
        Chef::Config.from_file(File.join(Chef::Knife.chef_config_dir, "knife.rb"))
      else
        ui.error "Cannot find knife.rb config file"
        exit 1
      end

      chefcfg = Chef::Config
      @cb_path = chefcfg.cookbook_path.is_a?(Array) ? chefcfg.cookbook_path.first : chefcfg.cookbook_path
      @loader = Chef::CookbookLoader.new(@cb_path)
    end

    def list_rollback_points()
      ui.msg("Available rollback points :")
      Dir.glob(File.join(@cfg["rollback"]["destination"], "*.json")).each do |f|
        ts = File.basename(f, ".json")
        ui.msg("  * #{ts} (#{Time.at(ts.to_i).to_s})")
      end
      exit 0
    end

    def rollback_to(identifier)
      show_rollback_point(identifier)
      answer = ui.ask_question("Continue rollback ? Y/(N) ", :default => "N").upcase
      if answer != "Y"
        ui.msg("Aborting !")
        exit 0
      end

      begin
        fp = File.open(File.join(@cfg["rollback"]["destination"],"#{identifier}.json"),"r")
        infos = JSON.load(fp)
      rescue
        ui.error("could not load rollback point #{identifier}")
        exit 1
      end

      env = Chef::Environment.load(infos["environment"])
      infos["cookbook_versions"].each do |cb, version|
          env.cookbook_versions[cb] = version
          ui.msg("Setting #{cb} to version #{version}")
      end
      env.save
    end

    def show_rollback_point(identifier)
      begin
        fp = File.open(File.join(@cfg["rollback"]["destination"],"#{identifier}.json"),"r")
      rescue
        ui.error("could not load rollback point #{identifier}")
        exit 1
      end
      infos = JSON.load(fp)
      ui.msg("Rollback point has the following informations :")
      ui.msg("  environment : #{infos["environment"]}")
      ui.msg("  cookbooks versions :")
      infos["cookbook_versions"].each do |cb, version|
        ui.msg("   * #{cb} => #{version}")
      end
    end

  end
end
