require 'chef/knife'
begin
  require 'grit'
rescue
  puts "you need the grit gem"
  exit 1
end

module Fotolia
  class Align < Chef::Knife

    banner "knife align BRANCH ENVIRONMENT [--debug]"

    option :debug,
      :short => '-d',
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

    def run
      align_cookbooks()
      align_databags()
    end

    def align_cookbooks
      if name_args.count < 2 then
        ui.error "Usage : knife align BRANCH ENVIRONMENT [--debug]"
        exit 1
      end

      branch = name_args.first
      environment = name_args[1]

      if Chef::Config::git_cookbook_path then
        path = Chef::Config::git_cookbook_path
      else
        path = Chef::Config::cookbook_path
      end

      current_branch = Grit::Repo.new(path).head.name
      if branch != current_branch then
        puts "Git repo is actually on branch #{current_branch} but you want to align using #{branch}. Checkout to the desired one."
        exit -1
      end

      target_versions = get_versions_from_env(environment)
      local_versions = get_local_versions()

      only_local = target_versions.keys - local_versions.keys

      unless only_local.empty?
        puts "Cookbooks only available on local repo (not on server) :"
        only_local.each do |cb|
          puts "* #{cb}"
        end
      end

      bumps = Hash.new()

      target_versions.each_pair do |t_cb, t_version|
        local_versions.each_pair do |l_cb,l_version|
          if l_cb == t_cb then
            if t_version != l_version then
#              puts "#{t_cb} : local is #{l_version} => #{t_version} (remote)"
              bumps[t_cb] = l_version
            end
          end
        end
      end

      if bumps.empty? then
        puts "Nothing to do : #{environment} has same versions as #{branch}"
      else
        puts ""
        puts "Will change in environment #{environment} :"
        bumps.each_pair do |cb,version|
          puts "* #{cb} gets version #{version}"
        end

        puts "Upload and set version into environment #{environment} ? Y/N"
        answer="N"
        answer = STDIN.getc
        answer = answer.chr
        if answer != "Y" then
          puts "Aborting"
        else # upload cookbooks, then change version
          bumps.each_pair do |cb,version|
            # call "knife cookbook upload, rather than re(invent|implement) the wheel
            result=%x[knife cookbook upload #{cb}]
            if $? != 0 then
              puts "Uploading #{cb} failed. stopping"
              exit -1
            else
              puts "Successfull upload for #{cb}"
            end
          end

          puts "Aligning #{bumps.count} cookbooks"
          env=Chef::Environment.load(environment)

          # create a temp file for this modification
          tmp=Tempfile.new(["chef", ".json"], "/tmp")
          tmpf = File.open(tmp.path,'w')
          bumps.each_pair do |cb,version|
              env.cookbook_versions[cb]=version
          end
          tmpf.write(env.to_json)
          tmpf.close

          loader=Chef::Knife::Core::ObjectLoader.new(Chef::Environment, ui)
          updated = loader.object_from_file(tmp.path)
          updated.save
          tmp.unlink

          puts "Done."
        end
      end

    end # end of run()

    # get cookbook for a known environment
    def get_versions_from_env(env_name)
      cbs = {}

      env = Chef::Environment.load(env_name)
      env.cookbook_versions.each_pair do |name,version|
        cbs[name] = version.gsub("= ","")
      end
      return cbs
    end

    # in your local dealer !
    def get_local_versions
      cbs = {}
      if (ENV['HOME'] && File.exist?(File.join(ENV['HOME'], '.chef', 'knife.rb')))
        Chef::Config.from_file(File.join(ENV['HOME'], '.chef', 'knife.rb'))
      end

      Dir.glob("#{Chef::Config.cookbook_path}/*").each do |cookbook|
        md = Chef::Cookbook::Metadata.new

        cb_name = File.basename(cookbook)
        md.name(cb_name)
        md.from_file("#{cookbook}/metadata.rb")
        cbs[cb_name] = md.version
      end

      return cbs
    end

    def align_databags
      if Chef::Config::git_cookbook_path then
        path = Chef::Config::git_cookbook_path
      else
        path = Chef::Config::cookbook_path
      end

      to_update = Hash.new

      # walk data bags json files
      dtbg_dir = Dir.open(path + "/data_bags")
      local_dtbgs = dtbg_dir.entries
      # dropping dots
      local_dtbgs.delete("..")
      local_dtbgs.delete(".")

      local_dtbgs.each do |ld|
        dtbg_items = Dir.open(path + "data_bags/" + ld).entries
        dtbg_items.delete("..")
        dtbg_items.delete(".")
        dtbg_items.each do |item|
          item_name = item.gsub(".json","")
          # do we have the same
          begin
            remote_item = Chef::DataBagItem.load(ld, item_name).raw_data
            # found ? load local item
            item_path = path + "data_bags/" + ld + "/" + item
            fp = open(item_path,"r")
            local_item = JSON::load(fp)
            if local_item != remote_item then
              puts "#{item} data is different between local repository & server"
              if config[:debug] == true then
                puts "local : #{local_item.keys.count} key(s)"
                puts "remote : #{remote_item.keys.count} key(s)"
              end
              # save to the list
              unless to_update.has_key?(ld)
                to_update[ld]=Array.new
              end
              to_update[ld].push(item_path)
            end
          rescue Net::HTTPServerException => e
            # not found on the server, warn user
            if e.data.code == "404" then
              if config[:debug] == true then
                puts "--- WARNING : item #{item_name} was not found in databag #{ld} on server"
              end
              unless to_update.has_key?(ld)
                to_update[ld]=Array.new
              end
              to_update[ld].push(item_path)
            end

          end
        end
      end
     
      if to_update.empty? == false then
        puts "About to push the following files to the server :"
        to_update.each_pair do |dtbg, files|
          files.each do |f|
            puts " * #{f} to databag #{dtbg}"
          end
        end
        puts "Upload ? Y/N"
        answer="N"
        answer = STDIN.getc
        answer = answer.chr
        if answer != "Y" then
          puts "Aborting"
        else
          to_update.each_pair do |dtbg,files|
            files.each do |f|
              upload_databag(f,dtbg)
            end
          end
        end
      else
        puts "No differences in databags found"
      end
    end

    # no need for the databag item name as it is the ID key
    def upload_databag(filepath, databag_name)
      dbag = Chef::DataBagItem.new
      dbag.data_bag(databag_name)
      fp = open(filepath,"r")
      dbag.raw_data = JSON::load(fp)
      dbag.save
      if config[:debug] == true then
        puts "uploaded #{filepath} to #{databag_name}/#{dbag.id}"
      end
    end



  end
end
