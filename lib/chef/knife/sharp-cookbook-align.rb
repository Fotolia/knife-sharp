require 'chef/knife'
require 'knife-sharp/common'

module KnifeSharp
  class SharpCookbookAlign < Chef::Knife
    include KnifeSharp::Common

    banner "knife sharp cookbook align BRANCH ENVIRONMENT [OPTS]"

    deps do
      require 'chef/cookbook/metadata'
      require 'chef/cookbook_loader'
      require 'chef/cookbook_uploader'
      require 'chef/environment'
    end

    def run
      ui.error "Not implemented yet. Use ```knife sharp align -C```"
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
  end
end
