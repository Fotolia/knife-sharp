require 'chef/knife'
require 'knife-sharp/common'

module KnifeSharp
  class SharpDataBagAlign < Chef::Knife
    include KnifeSharp::Common

    banner "knife sharp data bag align BRANCH [OPTS]"

    deps do
      require 'chef/data_bag'
      require 'chef/data_bag_item'
    end

    def run
      ui.error "Not implemented yet. Use ```knife sharp align -D```"
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
  end
end
