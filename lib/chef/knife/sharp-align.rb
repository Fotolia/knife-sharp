require 'chef/knife'
require 'grit'

module KnifeSharp
  class SharpAlign < Chef::Knife

    banner "knife sharp align BRANCH ENVIRONMENT [--debug]"

    option :debug,
      :short => '-d',
      :long  => '--debug',
      :description => "turn debug on",
      :default => false

    deps do
      require 'chef/cookbook/metadata'
      require 'chef/cookbook_loader'
      require 'chef/cookbook_uploader'
    end

    def run
      setup()
      ui.msg "On server #{@chef_server}" if @chef_server
      ui.msg "Aligning cookbooks"
      align_cookbooks()
      ui.msg "Aligning data bags"
      align_databags()
      ui.msg "Aligning roles"
      align_roles()
    end

    def setup
      # Checking args
      if name_args.count != 2
        ui.error "Usage : knife align BRANCH ENVIRONMENT [--debug]"
        exit 1
      end

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
      if Chef::Knife.chef_config_dir && File.exists?(File.join(Chef::Knife.chef_config_dir, "knife.rb"))
        Chef::Config.from_file(File.join(Chef::Knife.chef_config_dir, "knife.rb"))
      else
        ui.error "Cannot find knife.rb config file"
        exit 1
      end

      # Logger
      if @cfg["logging"]["enabled"]
        begin
          require "logger"
          log_file = File.expand_path(@cfg["logging"]["destination"])
          @log = Logger.new(log_file)
        rescue Exception => e
          ui.error "Unable to set up logger (#{e.inspect})."
          exit 1
        end
      end

      # Env setup
      @branch, @environment = name_args
      @chef_path = @cfg["global"]["git_cookbook_path"]

      chefcfg = Chef::Config
      @cb_path = chefcfg.cookbook_path.is_a?(Array) ? chefcfg.cookbook_path.first : chefcfg.cookbook_path
      @db_path = chefcfg.data_bag_path.is_a?(Array) ? chefcfg.data_bag_path.first : chefcfg.data_bag_path
      @role_path = chefcfg.role_path.is_a?(Array) ? chefcfg.role_path.first : chefcfg.role_path

      @chef_server = SharpServer.new.current_server
      @loader = Chef::CookbookLoader.new(@cb_path)

      # Checking current branch
      current_branch = Grit::Repo.new(@chef_path).head.name
      if @branch != current_branch then
        ui.error "Git repo is actually on branch #{current_branch} but you want to align using #{@branch}. Checkout to the desired one."
        exit 1
      end
    end

    ### Cookbook methods ###

    def align_cookbooks
      updated_versions = Hash.new()
      local_versions = Hash[Dir.glob("#{@cb_path}/*").map {|cb| [File.basename(cb), @loader[File.basename(cb)].version] }]
      remote_versions = Chef::Environment.load(@environment).cookbook_versions.each_value {|v| v.gsub!("= ", "")}

      (local_versions.keys - remote_versions.keys).each do |cb|
        updated_versions[cb] = local_versions[cb]
        ui.msg "* #{cb} is local only (version #{local_versions[cb]})"
      end

      (remote_versions.keys & local_versions.keys).each do |cb|
        if remote_versions[cb] != local_versions[cb]
          updated_versions[cb] = local_versions[cb]
          ui.msg "* #{cb} is not up-to-date (local: #{local_versions[cb]}/remote: #{remote_versions[cb]})"
        end
      end

      if !updated_versions.empty?
        all = false
        bumped = Array.new
        env = Chef::Environment.load(@environment)
        updated_versions.each_pair do |cb,version|
          answer = nil

          if @cfg[@chef_server]
            if @cfg[@chef_server]["ignore_cookbooks"]
              if @cfg[@chef_server]["ignore_cookbooks"].include?(cb)
                answer = "N"
              end
            end
          end

          if answer.nil?
            answer = ui.ask_question("Update #{cb} cookbook item on server ? Y/N/(A)ll/(Q)uit ", :default => "N").upcase unless all
          end

          if answer == "A"
            all = true
          elsif answer == "Q"
            ui.msg "> Skipping next cookbooks alignment."
            break
          end

          if all or answer == "Y"
            # Force "= a.b.c" in cookbook version, as chef11 will not accept "a.b.c"
            env.cookbook_versions[cb] = "= #{version}"
            bumped << @loader[cb]
          else
            ui.msg "* Skipping #{cb} cookbook"
          end
        end

        unless bumped.empty?
          ui.msg "* Uploading cookbook(s) #{bumped.map{|cb| cb.name.to_s}.join(",")}"
          uploader = Chef::CookbookUploader.new(bumped, @cb_path)
          uploader.upload_cookbooks
          if env.save
            bumped.each do |cb|
              ui.msg "* Bumping #{cb.name.to_s} to #{cb.version} for environment #{@environment}"
              log_action("bumping #{cb.name.to_s} to #{cb.version} for environment #{@environment}")
            end
          end
        end
      else
        ui.msg "> Environment #{@environment} is up-to-date."
      end
    end

    ### Databag methods ###

    def align_databags
      unless File.exists?(@db_path)
        ui.warn "Bad data bag path, skipping data bag sync."
        return
      end

      updated_dbs = Hash.new
      local_dbs = Dir.glob(File.join(@db_path, "**/*.json")).map {|f| [File.dirname(f).split("/").last, File.basename(f, ".json")]}
      remote_dbs = Chef::DataBag.list.keys.map {|db| Chef::DataBag.load(db).keys.map{|dbi| [db, dbi]}}.flatten(1)

      ui.warn "No local data bags found, is the role path correct ? (#{@role_path})" if local_dbs.empty?

      # Create new data bags on server
      (local_dbs - remote_dbs).each do |db|
        ui.msg "+ #{db.join("/")} data bag item is local only. Creating"
        begin
          local_db = Chef::DataBagItem.new
          local_db.data_bag(db.first)
          local_db.raw_data = JSON::load(File.read(File.join(@db_path, "#{db.join("/")}.json")))
          local_db.save
        rescue Exception => e
          ui.error "Unable to create #{db.join("/")} data bag item (#{e.message})"
        end
      end

      # Dump missing data bags locally
      (remote_dbs - local_dbs).each do |db|
        ui.msg "- #{db.join("/")} data bag item is remote only. Dumping to #{File.join(@db_path, "#{db.join("/")}.json")}"
        begin
          remote_db = Chef::DataBagItem.load(db.first, db.last).raw_data
          Dir.mkdir(File.join(@db_path, db.first)) unless File.exists?(File.join(@db_path, db.first))
          File.open(File.join(@db_path, "#{db.join("/")}.json"), "w") do |file|
            file.puts JSON.pretty_generate(remote_db)
          end
        rescue Exception => e
          ui.error "Unable to dump #{db.join("/")} data bag item (#{e.message})"
        end
      end

      # Compare roles common to local and remote
      (remote_dbs & local_dbs).each do |db|
        remote_db = Chef::DataBagItem.load(db.first, db.last).raw_data
        local_db = JSON::load(File.read(File.join(@db_path, "#{db.join("/")}.json")))

        if remote_db != local_db
          updated_dbs[db] = local_db
          ui.msg("* #{db.join("/")} data bag item is not up-to-date")
        end
      end

      if !updated_dbs.empty?
        all = false
        updated_dbs.each do |name, obj|
          answer = ui.ask_question("Update #{name.join("/")} data bag item on server ? Y/N/(A)ll/(Q)uit ", :default => "N").upcase unless all

          if answer == "A"
            all = true
          elsif answer == "Q"
            ui.msg "> Aborting data bag alignment."
            break
          end

          if all or answer == "Y"
            ui.msg "* Updating #{name.join("/")} data bag item"
            log_action("updating #{name.join("/")} data bag item")
            db = Chef::DataBagItem.new
            db.data_bag(name.first)
            db.raw_data = obj
            db.save
          else
            ui.msg "* Skipping #{name.join("/")} data bag item"
          end
        end
      else
        ui.msg "> Data bags are up-to-date."
      end
    end

    ### Role methods ###

    def align_roles
      # role sections to compare (methods)
      to_check = {
        "env_run_lists" => "run list",
        "default_attributes" => "default attributes",
        "override_attributes" => "override attributes"
      }

      unless File.exists?(@role_path)
        ui.warn "Bad role path, skipping role sync."
        return
      end

      updated_roles = Hash.new
      local_roles = Dir.glob(File.join(@role_path, "*.json")).map {|file| File.basename(file, ".json")}
      remote_roles = Chef::Role.list.keys

      ui.warn "No local roles found, is the role path correct ? (#{@role_path})" if local_roles.empty?

      # Create new roles on server
      (local_roles - remote_roles).each do |role|
        ui.msg "+ #{role} role is local only. Creating"
        begin
          local_role = Chef::Role.from_disk(role)
          local_role.save
        rescue Exception => e
          ui.error "Unable to create #{role} role (#{e.message})"
        end
      end

      # Dump missing roles locally
      (remote_roles - local_roles).each do |role|
        ui.msg "- #{role} role is remote only. Dumping to #{File.join(@role_path, "#{role}.json")}"
        begin
          remote_role = Chef::Role.load(role)
          File.open(File.join(@role_path, "#{role}.json"), "w") do |file|
            file.puts JSON.pretty_generate(remote_role)
          end
        rescue Exception => e
          ui.error "Unable to dump #{role} role (#{e.message})"
        end
      end

      # Compare roles common to local and remote
      (remote_roles & local_roles).each do |role|
        remote_role = Chef::Role.load(role)
        local_role = Chef::Role.from_disk(role)

        diffs = Array.new
        to_check.each do |method, display|
          if remote_role.send(method) != local_role.send(method)
            updated_roles[role] = local_role
            diffs << display
          end
        end
        ui.msg("* #{role} role is not up-to-date (#{diffs.join(",")})") unless diffs.empty?
      end

      if !updated_roles.empty?
        all = false
        updated_roles.each do |name, obj|
          answer = ui.ask_question("Update #{name} role on server ? Y/N/(A)ll/(Q)uit ", :default => "N").upcase unless all

          if answer == "A"
            all = true
          elsif answer == "Q"
            ui.msg "> Aborting role alignment."
            break
          end

          if all or answer == "Y"
            ui.msg "* Updating #{name} role"
            log_action("updating #{name} role")
            obj.save
          else
            ui.msg "* Skipping #{name} role"
          end
        end
      else
        ui.msg "> Roles are up-to-date."
      end
    end

    ### Utility methods ###

    def log_action(message)
      # log file if enabled
      log_message = message
      log_message += " on server #{@chef_server}" if @chef_server
      @log.info(log_message) if @cfg["logging"]["enabled"]

      # any defined notification method (currently, only hubot, defined below)
      if @cfg["notification"]
        @cfg["notification"].each do |carrier, data|
          skipped = Array.new
          skipped = data["skip"] if data["skip"]

          if data["enabled"] and !skipped.include?(@chef_server)
            send(carrier, message, data)
          end
        end
      end
    end

    def hubot(message, config={})
      begin
        require "net/http"
        require "uri"
        uri = URI.parse("#{config["url"]}/#{config["channel"]}")
        notif = "chef: #{message} by #{config["username"]}"
        Net::HTTP.post_form(uri, { "message" => notif })
      rescue
        ui.error "Unable to notify via hubot."
      end
    end

  end
end
