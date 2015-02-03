require 'chef/knife'
require 'knife-sharp/common'
require 'grit'

module KnifeSharp
  class SharpAlign < Chef::Knife
    include KnifeSharp::Common

    banner "knife sharp align BRANCH ENVIRONMENT [OPTS]"

    [:cookbooks, :databags, :roles].each do |opt|
      option opt,
        :short => "-#{opt.to_s[0,1].upcase}",
        :long => "--#{opt}-only",
        :description => "sync #{opt} only",
        :default => false
    end

    option :force_align,
      :short => "-f",
      :long => "--force-align",
      :description => "force local cookbook versions, allow downgrade",
      :default => false

    option :dump_remote_only,
      :short => "-B",
      :long => "--dump-remote-only",
      :description => "dump items not present locally (roles/databags)",
      :default => false

    deps do
      require 'chef/environment'
      require 'chef/role'
      require 'chef/cookbook/metadata'
      require 'chef/cookbook_loader'
      require 'chef/cookbook_uploader'
    end

    def run
      # Checking args
      ensure_branch_and_environment_provided!

      # Checking repo branch
      ensure_correct_branch_provided!

      # check cli flags
      if config[:cookbooks] or config[:databags] or config[:roles]
        do_cookbooks, do_databags, do_roles = config[:cookbooks], config[:databags], config[:roles]
      else
        do_cookbooks, do_databags, do_roles = true, true, true
      end

      ui.msg(ui.color("On server #{chef_server}", :bold)) if chef_server

      cookbooks_to_update = do_cookbooks ? check_cookbooks(environment) : []
      databags_to_update = do_databags ? check_databags : {}
      roles_to_update = do_roles ? check_roles : {}

      # All questions asked, can we proceed ?
      if cookbooks_to_update.empty? and databags_to_update.empty? and roles_to_update.empty?
        ui.msg "Nothing else to do"
        exit 0
      end

      ui.confirm(ui.color("> Proceed ", :bold))
      bump_cookbooks(environment, cookbooks_to_update) if do_cookbooks
      update_databags(databags_to_update) if do_databags
      update_roles(roles_to_update) if do_roles
    end

    ### Cookbook methods ###

    def check_cookbooks(env)
      to_update = Array.new

      unless File.exists?(cookbook_path)
        ui.warn "Bad cookbook path, skipping cookbook sync."
        return to_update
      end

      ui.msg(ui.color("== Cookbooks ==", :bold))

      updated_versions = Hash.new
      local_versions = local_cookbook_versions
      remote_versions = remote_cookbook_versions(env)

      if local_versions.empty?
        ui.warn "No local cookbooks found, is the cookbook path correct ? (#{cookbook_path})"
        return to_update
      end

      # get local-only cookbooks
      (local_versions.keys - remote_versions.keys).each do |cb|
        updated_versions[cb] = local_versions[cb]
        ui.msg "* #{cb} is local only (version #{local_versions[cb]})"
      end

      # get cookbooks not up-to-date
      (remote_versions.keys & local_versions.keys).each do |cb|
        if Chef::VersionConstraint.new("> #{remote_versions[cb]}").include?(local_versions[cb])
          updated_versions[cb] = local_versions[cb]
          ui.msg "* #{cb} is not up-to-date (local: #{local_versions[cb]}/remote: #{remote_versions[cb]})"
        elsif Chef::VersionConstraint.new("> #{local_versions[cb]}").include?(remote_versions[cb]) and config[:force_align]
          updated_versions[cb] = local_versions[cb]
          ui.msg "* #{cb} is to be downgraded (local: #{local_versions[cb]}/remote: #{remote_versions[cb]})"
        end
      end

      if sharp_config[chef_server] and sharp_config[chef_server].has_key?("ignore_cookbooks")
        (updated_versions.keys & sharp_config[chef_server]["ignore_cookbooks"]).each do |cb|
          updated_versions.delete(cb)
          ui.msg "* Skipping #{cb} cookbook (ignore list)"
        end
      end

      if !updated_versions.empty?
        all = false
        updated_versions.each_pair do |cb,version|
          answer = ui.ask_question("> Update #{cb} cookbook to #{version} on server ? Y/N/(A)ll/(Q)uit ", :default => "N").upcase unless all

          if answer == "A"
            all = true
          elsif answer == "Q"
            ui.msg "* Skipping next cookbooks alignment."
            break
          end

          if all or answer == "Y"
            to_update << cb
          else
            ui.msg "* Skipping #{cb} cookbook"
          end
        end
      else
        ui.msg "* Environment #{env} is up-to-date."
      end

      to_update
    end


    def bump_cookbooks(env_name, cookbook_list)
      unless cookbook_list.empty?
        env = Chef::Environment.load(env_name)
        cbs = Array.new
        backup_data = Hash.new
        backup_data["environment"] = env.name
        backup_data["cookbook_versions"] = Hash.new
        cookbook_list.each do |cb_name|
          cb = cookbook_loader[cb_name]
          if sharp_config["rollback"] && sharp_config["rollback"]["enabled"] == true
            backup_data["cookbook_versions"][cb_name] = env.cookbook_versions[cb_name]
          end
          # Force "= a.b.c" in cookbook version, as chef11 will not accept "a.b.c"
          env.cookbook_versions[cb_name] = "= #{cb.version}"
          cbs << cb
        end

        ui.msg "* Uploading cookbook(s) #{cookbook_list.join(", ")}"
        cookbook_uploader(cbs).upload_cookbooks

        if env.save
          cbs.each do |cb|
            ui.msg "* Bumping #{cb.name} to #{cb.version} for environment #{env.name}"
            log_action("bumping #{cb.name} to #{cb.version} for environment #{env.name}")
          end
        end

        if sharp_config["rollback"] && sharp_config["rollback"]["enabled"] == true
          identifier = Time.now.to_i
          Dir.mkdir(sharp_config["rollback"]["destination"]) unless File.exists?(sharp_config["rollback"]["destination"])
          fp = open(File.join(sharp_config["rollback"]["destination"], "#{identifier}.json"), "w")
          fp.write(JSON.pretty_generate(backup_data))
          fp.close()
        end
      end
    end

    ### Databag methods ###

    def check_databags
      to_update = Hash.new

      unless File.exists?(data_bag_path)
        ui.warn "Bad data bag path, skipping data bag sync."
        return to_update
      end

      ui.msg(ui.color("== Data bags ==", :bold))

      updated_dbs = Hash.new
      local_dbs = Dir.glob(File.join(data_bag_path, "**/*.json")).map {|f| [File.dirname(f).split("/").last, File.basename(f, ".json")]}
      remote_dbs = Chef::DataBag.list.keys.map {|db| Chef::DataBag.load(db).keys.map{|dbi| [db, dbi]}}.flatten(1)

      if local_dbs.empty?
        ui.warn "No local data bags found, is the data bag path correct ? (#{data_bag_path})"
        return to_update
      end

      # Dump missing data bags locally
      (remote_dbs - local_dbs).each do |db|
        ui.msg "* #{db.join("/")} data bag item is remote only"
        if config[:dump_remote_only]
          ui.msg "* Dumping to #{File.join(data_bag_path, "#{db.join("/")}.json")}"
          begin
            remote_db = Chef::DataBagItem.load(db.first, db.last).raw_data
            Dir.mkdir(File.join(data_bag_path, db.first)) unless File.exists?(File.join(data_bag_path, db.first))
            File.open(File.join(data_bag_path, "#{db.join("/")}.json"), "w") do |file|
              file.puts JSON.pretty_generate(remote_db)
            end
          rescue Exception => e
            ui.error "Unable to dump #{db.join("/")} data bag item (#{e.message})"
          end
        end
      end

      # Create new data bags on server
      (local_dbs - remote_dbs).each do |db|
        begin
          local_db = JSON::load(File.read(File.join(data_bag_path, "#{db.join("/")}.json")))
          updated_dbs[db] = local_db
          ui.msg "* #{db.join("/")} data bag item is local only"
        rescue Exception => e
          ui.error "Unable to load #{db.join("/")} data bag item (#{e.message})"
        end
      end

      # Compare roles common to local and remote
      (remote_dbs & local_dbs).each do |db|
        begin
          remote_db = Chef::DataBagItem.load(db.first, db.last).raw_data
          local_db = JSON::load(File.read(File.join(data_bag_path, "#{db.join("/")}.json")))
          if remote_db != local_db
            updated_dbs[db] = local_db
            ui.msg("* #{db.join("/")} data bag item is not up-to-date")
          end
        rescue Exception => e
          ui.error "Unable to load #{db.join("/")} data bag item (#{e.message})"
        end
      end

      if sharp_config[chef_server] and sharp_config[chef_server].has_key?("ignore_databags")
        (updated_dbs.keys.map{|k| k.join("/")} & sharp_config[chef_server]["ignore_databags"]).each do |db|
          updated_dbs.delete(db.split("/"))
          ui.msg "* Skipping #{db} data bag (ignore list)"
        end
      end

      if !updated_dbs.empty?
        all = false
        updated_dbs.each do |name, obj|
          answer = nil
          answer = ui.ask_question("> Update #{name.join("/")} data bag item on server ? Y/N/(A)ll/(Q)uit ", :default => "N").upcase unless all

          if answer == "A"
            all = true
          elsif answer == "Q"
            ui.msg "* Aborting data bag alignment."
            break
          end

          if all or answer == "Y"
            to_update[name] = obj
          else
            ui.msg "* Skipping #{name.join("/")} data bag item"
          end
        end
      else
        ui.msg "* Data bags are up-to-date."
      end

      to_update
    end

    def update_databags(databag_list)
      parent_databags = Chef::DataBag.list.keys
      databag_list.each do |name, obj|
        begin
          # create the parent if needed
          unless parent_databags.include?(name.first)
            db = Chef::DataBag.new
            db.name(name.first)
            db.create
            # add it to the list to avoid trying to recreate it
            parent_databags.push(name.first)
            ui.msg("* Creating data bag #{name.first}")
            log_action("creating data bag #{name.first}")
          end
          db = Chef::DataBagItem.new
          db.data_bag(name.first)
          db.raw_data = obj
          db.save
          ui.msg "* Updating #{name.join("/")} data bag item"
          log_action("updating #{name.join("/")} data bag item")
        rescue Exception => e
          ui.error "Unable to update #{name.join("/")} data bag item"
        end
      end
    end

    ### Role methods ###

    def check_roles
      to_update = Hash.new

      unless File.exists?(role_path)
        ui.warn "Bad role path, skipping role sync."
        return to_update
      end

      ui.msg(ui.color("== Roles ==", :bold))

      updated_roles = Hash.new
      local_roles = Dir.glob(File.join(role_path, "*.json")).map {|file| File.basename(file, ".json")}
      remote_roles = Chef::Role.list.keys

      if local_roles.empty?
        ui.warn "No local roles found, is the role path correct ? (#{role_path})"
        return to_update
      end

      # Dump missing roles locally
      (remote_roles - local_roles).each do |role|
        ui.msg "* #{role} role is remote only"
        if config[:dump_remote_only]
          ui.msg "* Dumping to #{File.join(role_path, "#{role}.json")}"
          begin
            remote_role = Chef::Role.load(role)
            File.open(File.join(role_path, "#{role}.json"), "w") do |file|
              file.puts JSON.pretty_generate(remote_role)
            end
          rescue Exception => e
            ui.error "Unable to dump #{role} role (#{e.message})"
          end
        end
      end

      # Create new roles on server
      (local_roles - remote_roles).each do |role|
        begin
          local_role = Chef::Role.from_disk(role)
          updated_roles[role] = local_role
          ui.msg "* #{role} role is local only"
        rescue Exception => e
          ui.error "Unable to load #{role} role (#{e.message})"
        end
      end

      # Compare roles common to local and remote
      (remote_roles & local_roles).each do |role|
        remote_role = Chef::Role.load(role)
        local_role = Chef::Role.from_disk(role)

        diffs = Array.new
        relevant_role_keys.each do |method, display|
          if remote_role.send(method) != local_role.send(method)
            updated_roles[role] = local_role
            diffs << display
          end
        end
        ui.msg("* #{role} role is not up-to-date (#{diffs.join(",")})") unless diffs.empty?
      end

      if sharp_config[chef_server] and sharp_config[chef_server].has_key?("ignore_roles")
        (updated_roles.keys & sharp_config[chef_server]["ignore_roles"]).each do |r|
          updated_roles.delete(r)
          ui.msg "* Skipping #{r} role (ignore list)"
        end
      end

      if !updated_roles.empty?
        all = false
        updated_roles.each do |name, obj|
          answer = ui.ask_question("> Update #{name} role on server ? Y/N/(A)ll/(Q)uit ", :default => "N").upcase unless all

          if answer == "A"
            all = true
          elsif answer == "Q"
            ui.msg "* Aborting role alignment."
            break
          end

          if all or answer == "Y"
            to_update[name] = obj
          else
            ui.msg "* Skipping #{name} role"
          end
        end
      else
        ui.msg "* Roles are up-to-date."
      end

      to_update
    end

    def update_roles(role_list)
      role_list.each do |name, obj|
        begin
          obj.save
          ui.msg "* Updating #{name} role"
          log_action("updating #{name} role")
        rescue Exception => e
          ui.error "Unable to update #{name} role"
        end
      end
    end

    def cookbook_loader
      @cookbook_loader ||= Chef::CookbookLoader.new(Chef::Config.cookbook_path)
    end

    def cookbook_uploader(cookbooks)
      if Gem::Version.new(Chef::VERSION).release >= Gem::Version.new('12.0.0')
        uploader = Chef::CookbookUploader.new(cookbooks)
      else
        uploader = Chef::CookbookUploader.new(cookbooks, Chef::Config.cookbook_path)
      end
    end

    def local_cookbook_versions
      Hash[Dir.glob("#{cookbook_path}/*").select {|cb| File.directory?(cb)}.map {|cb| [File.basename(cb), cookbook_loader[File.basename(cb)].version] }]
    end

    def remote_cookbook_versions(env)
      Chef::Environment.load(env).cookbook_versions.each_value {|v| v.gsub!("= ", "")}
    end

    def relevant_role_keys
      # role sections to compare (methods)
      {
        "env_run_lists" => "run list",
        "default_attributes" => "default attributes",
        "override_attributes" => "override attributes"
      }
    end
  end
end
