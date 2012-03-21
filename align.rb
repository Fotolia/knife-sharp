require 'chef/knife'
begin
  require 'grit'
rescue
  puts "you need the grit gem"
  exit 1
end

module Fotolia
  class Align < Chef::Knife

    banner "knife align [BRANCH] [ENVIRONMENT]"

    deps do
      require 'chef/knife/search'
      require 'chef/environment'
      require 'chef/cookbook/metadata'
      require 'chef/knife/core/object_loader'
    end

    def run
      if name_args.count < 2 then
        ui.error "Usage : knife align [BRANCH] [ENVIRONMENT]"
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

  end
end
