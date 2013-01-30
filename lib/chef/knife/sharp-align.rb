require 'chef/knife'
require 'grit'

module KnifeSharp
  class SharpAlign < Chef::Knife

    banner "knife sharp align BRANCH ENVIRONMENT [--debug] [--quiet]"

    option :debug,
      :short => '-d',
      :long  => '--debug',
      :description => "turn debug on",
      :default => false

    option :quiet,
      :short => '-q',
      :long => '--quiet',
      :description => 'does not notifies',
      :default => false

    deps do
      require 'chef/cookbook/metadata'
      require 'chef/cookbook_loader'
      require 'chef/cookbook_uploader'
    end

    def run
      setup()
      align_cookbooks()
      align_databags()
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
      if (ENV['HOME'] && File.exist?(File.join(ENV['HOME'], '.chef', 'knife.rb')))
        Chef::Config.from_file(File.join(ENV['HOME'], '.chef', 'knife.rb'))
      else
        ui.error "Cannot find knife.rb config file"
        exit 1
      end

      # Env setup
      @branch, @environment = name_args
      @chef_path = @cfg["global"]["git_cookbook_path"]
      @cb_path = Chef::Config.cookbook_path.first
      @db_path = File.join(@chef_path, "data_bags")

      # Checking current branch
      current_branch = Grit::Repo.new(@chef_path).head.name
      if @branch != current_branch then
        ui.error "Git repo is actually on branch #{current_branch} but you want to align using #{@branch}. Checkout to the desired one."
        exit 1
      end
    end

    ### Cookbook methods ###

    def align_cookbooks
      target_versions = get_cookbook_versions_from_env(@environment)
      cb_list = target_versions.keys
      local_versions = get_cookbook_local_versions()
      cb_list += local_versions.keys

      only_local = local_versions.keys - target_versions.keys

      bumps = Hash.new()

      (cb_list - only_local).each do |cb|
        if target_versions[cb] != local_versions[cb]
          bumps[cb] = local_versions[cb]
        end
      end

      unless bumps.empty?
        ui.msg "Cookbooks not up to date on server :"
        bumps.each do |cb,version|
          ui.msg "* #{cb} gets version #{version} (currently #{target_versions[cb]})"
        end
      end

      unless only_local.empty?
        ui.msg "Cookbooks only available on local repo (not on server) :"
        only_local.each do |cb|
          ui.msg "* #{cb} (#{local_versions[cb]})"
        end
      end

      if !bumps.empty?
        answer = ui.ask_question("Upload and set version into environment #{@environment} ? Y/N ", :default => "N")
        if answer == "Y"
          bumps.each_pair do |cb,version|
            upload_cookbook(cb)
            log_action("Uploaded cookbook #{cb} version #{version}")
          end

          env = Chef::Environment.load(@environment)
          bumps.each_pair do |cb, version|
            env.cookbook_versions[cb] = version
            log_action("Bumped cookbook #{cb} to #{version} for environment #{@environment}")
            hubot_notify(cb, version, @environment)
          end
          env.save

          ui.msg "Done."
        else
          ui.msg "Aborting."
        end
      else
        ui.msg "Nothing to do : #{@environment} has same versions as #{@branch}"
      end
    end

    def upload_cookbook(cb_name)
      #cookbook names to actual cookbook objects
      @loader ||= Chef::CookbookLoader.new(@cb_path)
      cb = @loader[cb_name]

      # uploading cookbooks, dependencies first
      uploader = Chef::CookbookUploader.new(cb, @cb_path)
      uploader.upload_cookbooks
    end

    # get cookbook for a known environment
    def get_cookbook_versions_from_env(env_name)
      Chef::Environment.load(env_name).cookbook_versions.each_value {|v| v.gsub!("= ", "")}
    end

    # in your local dealer !
    def get_cookbook_local_versions
      cbs = {}

      Dir.glob("#{@cb_path}/*").each do |cookbook|
        cb_name = File.basename(cookbook)
        md = Chef::Cookbook::Metadata.new
        md.from_file("#{cookbook}/metadata.rb")
        cbs[cb_name] = md.version
      end

      return cbs
    end

    ### Databag methods ###

    def align_databags
      to_update = Hash.new

      # walk data bags json files
      Dir.glob(File.join(@db_path,"*")).each do |ld|
        dtbg_name = File.basename(ld)
        Dir.glob(File.join(ld, "*.json")).each do |item|
          item_name = File.basename(item, ".json")
          # do we have the same
          begin
            remote_item = Chef::DataBagItem.load(dtbg_name, item_name).raw_data
            # found ? load local item
            local_item = JSON::load(File.read(item))
            if local_item != remote_item
              ui.msg "#{item} data is different between local repository & server"
              if config[:debug] == true then
                ui.msg "local : #{local_item.keys.count} key(s)"
                ui.msg "remote : #{remote_item.keys.count} key(s)"
              end
              # save to the list
              to_update[dtbg_name] ||= Array.new
              to_update[dtbg_name].push(item)
            end
          rescue Net::HTTPServerException => e
            # not found on the server, warn user
            if e.data.code == "404" then
              ui.msg "item #{item_name} was not found in databag #{dtbg_name} on server"
              to_update[dtbg_name] ||= Array.new
              to_update[dtbg_name].push(item)
            end
          end
        end
      end

      if !to_update.empty?
        ui.msg "About to push the following files to the server :"
        to_update.each_pair do |dtbg, files|
          files.each do |f|
            ui.msg " * #{f} to databag #{dtbg}"
          end
        end
        answer = ui.ask_question("Upload ? Y/N ", :default => "N")
        if answer == "Y" then
          to_update.each_pair do |dtbg,files|
            files.each do |f|
              upload_databag(f,dtbg)
              log_action("Uploaded #{f} to #{dtbg}")
            end
          end

          ui.msg "Done."
        else
          ui.msg "Aborting."
        end
      else
        ui.msg "No differences in databags found."
      end
    end

    # no need for the databag item name as it is the ID key
    def upload_databag(filepath, databag_name)
      dbag = Chef::DataBagItem.new
      dbag.data_bag(databag_name)
      dbag.raw_data = JSON::load(File.read(filepath))
      dbag.save
    end

    ### Utility methods ###

    def log_action(message)
      ui.msg(message)

      if @cfg["logging"]["enabled"]
        begin
          require "logger"
          log_file = File.expand_path(@cfg["logging"]["destination"])
          log = Logger.new(log_file)
          log.info(message)
          log.close
        rescue Exception => e
          ui.error "Oops ! #{e.inspect} ! message to log was #{message}"
        end
      end
    end

    def hubot_notify(cookbook, to_version, environment)
      unless @cfg["notification"]["hubot"]["enabled"] == true and config[:quiet] == false
        ui.msg "Aborting due to quiet or config disabled" if config[:debug]
        return
      end

      begin
        require "net/http"
        require "uri"
        uri = URI.parse(@cfg["notification"]["hubot"]["url"] + @cfg["notification"]["hubot"]["channel"])
        user = @cfg["notification"]["hubot"]["username"]

        Net::HTTP.post_form(uri, { "cookbook" => cookbook,
                                   "user" => user,
                                   "to_version" => to_version,
                                   "environment" => environment })
      rescue
        ui.error "Oops ! could not notify hubot !"
      end
    end
  end
end
