require 'chef/knife'
require 'knife-sharp/common'

module KnifeSharp
  class SharpEnvironmentAlign < Chef::Knife
    include KnifeSharp::Common

    banner "knife sharp environment align BRANCH [OPTS]"

    deps do
      require "chef/environment"
    end

    def run
      # Checking args
      ensure_branch_provided!

      # Checking repo branch
      ensure_correct_branch_provided!

      to_update = check_environments

      if to_update.empty?
        ui.msg "Nothing else to do"
        exit 0
      end

      ui.confirm(ui.color("> Proceed ", :bold))

      update_environments(to_update)
    end

    def check_environments
      not_up_to_date = Array.new
      to_update = Array.new

      unless File.exists?(environment_path)
        ui.warn("Bad environment path, skipping environment sync.")
        return to_update
      end

      ui.msg(ui.color("On server #{chef_server}", :bold)) if chef_server
      ui.msg(ui.color("== Environments ==", :bold))

      local_envs = Dir.glob(File.join(environment_path, "*.json")).map {|file| File.basename(file, ".json")}
      remote_envs = Chef::Environment.list.keys

      if local_envs.empty?
        ui.warn("No local environment found, is the environment path correct ? (#{environment_path})")
        return to_update
      end

      # Create new environments on server
      (local_envs - remote_envs).each do |env|
        local_env = Chef::Environment.load_from_file(env)
        message = "* #{local_env.name} environment is local only"
        if ignore_list(:environments).include(local_env.name)
          message += " (ignored)"
        else
          not_up_to_date << local_env
        end
        ui.msg(message)
      end

      # Compare envs common to local and remote
      (remote_envs & local_envs).each do |env|
        remote_env = Chef::Environment.load(env)
        local_env = Chef::Environment.load_from_file(env)

        diffs = relevant_env_keys.map do |method, display|
          if remote_env.send(method) != local_env.send(method)
            remote_env.send("#{method}=", local_env.send(method))
            display
          end
        end.compact

        unless diffs.empty?
          message = "* #{remote_env.name} environment is not up-to-date (#{diffs.join(", ")})"
          if ignore_list(:environments).include?(remote_env.name)
            message += " (ignored)"
          else
            not_up_to_date << remote_env
          end
          ui.msg(message)
        end
      end

      if !not_up_to_date.empty?
        all = false
        not_up_to_date.each do |env|
          answer = all ? "Y" : ui.ask_question("> Update #{env.name} environment on server ? Y/N/(A)ll/(Q)uit ", :default => "N").upcase

          if answer == "A"
            all = true
          elsif answer == "Q"
            ui.msg "* Aborting environment alignment."
            break
          end

          if all or answer == "Y"
            to_update << env
          else
            ui.msg "* Skipping #{env.name} environment"
          end
        end
      else
        ui.msg "* Environments are up-to-date."
      end

      to_update
    end

    def update_environments(env_list)
      env_list.each do |env|
        begin
          env.save
          ui.msg("* Updating #{env.name} environment")
        rescue Exception => e
          ui.error("Unable to update #{env.name} environment (#{e.message})")
        end
      end
    end

    def relevant_env_keys
      # env sections to compare (methods)
      {
        "default_attributes" => "default attributes",
        "override_attributes" => "override attributes"
      }
    end
  end
end
