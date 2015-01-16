require 'knife-sharp/common'

module KnifeSharp
  class SharpRollback < Chef::Knife
    include KnifeSharp::Common

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
      require 'chef/environment'
      require 'chef/cookbook/metadata'
    end

    def run()
      setup()

      if config[:list]
        list_rollback_points()
        exit 0
      end

      if config[:show]
        identifier = name_args
        show_rollback_point(identifier)
        exit 0
      end

      if config[:to]
        identifier = name_args
        rollback_to(identifier)
        exit 0
      end
    end

    def setup()
      actions = 0
      [:to, :list, :show].each do |action|
        if config[action]
          actions+=1
        end
      end

      if actions > 1
        ui.error("please specify only one action")
        exit 1
      end

      chefcfg = Chef::Config
      @cb_path = chefcfg.cookbook_path.is_a?(Array) ? chefcfg.cookbook_path.first : chefcfg.cookbook_path
    end

    def list_rollback_points()
      ui.msg("Available rollback points :")
      Dir.glob(File.join(sharp_config["rollback"]["destination"], "*.json")).each do |f|
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
        fp = File.open(File.join(sharp_config["rollback"]["destination"],"#{identifier}.json"),"r")
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
        fp = File.open(File.join(sharp_config["rollback"]["destination"],"#{identifier}.json"),"r")
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
