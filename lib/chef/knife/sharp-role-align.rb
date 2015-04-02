require 'chef/knife'
require 'knife-sharp/common'

module KnifeSharp
  class SharpRoleAlign < Chef::Knife
    include KnifeSharp::Common

    banner "knife sharp role align BRANCH [OPTS]"

    deps do
      require 'chef/role'
    end

    def run
      ui.error "Not implemented yet. Use ```knife sharp align -R```"
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
