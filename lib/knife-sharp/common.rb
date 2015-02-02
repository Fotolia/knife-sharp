require 'logger'

module KnifeSharp
  module Common
    module ClassMethods; end

    module InstanceMethods
      def sharp_config
        return @sharp_config unless @sharp_config.nil?

        config_file = File.expand_path("~/.chef/sharp-config.yml")

        begin
          @sharp_config = YAML::load_file(config_file)
        rescue Exception => e
          ui.error "Failed to load config file #{config_file}: #{e.message}"
          exit 1
        end

        @sharp_config
      end

      def ensure_correct_branch_provided!
        # Checking current branch
        given_branch = @name_args.first
        current_branch = Grit::Repo.new(sharp_config["global"]["git_cookbook_path"]).head.name

        if given_branch != current_branch then
          ui.error "Git repo is actually on branch #{current_branch} but you want to align using #{given_branch}. Checkout to the desired one."
          exit 1
        end
      end

      def ensure_branch_and_environment_provided!
        if @name_args.size != 2
          show_usage
          exit 1
        end
      end

      def environment
        @environment ||= @name_args.last
      end

      def cookbook_path
        @cookbook_path ||= [Chef::Config.send(:cookbook_path)].flatten.first
      end

      def data_bag_path
        @data_bag_path ||= [Chef::Config.send(:data_bag_path)].flatten.first
      end

      def role_path
        @role_path ||= [Chef::Config.send(:role_path)].flatten.first
      end

      def logger
        return @logger unless @logger.nil?

        begin
          log_file = sharp_config["logging"]["destination"] || "~/.chef/sharp.log"
          @logger = Logger.new(File.expand_path(log_file))
        rescue Exception => e
          ui.error "Unable to set up logger (#{e.inspect})."
          exit 1
        end

        @logger
      end

      def chef_server
        @chef_server ||= SharpServer.new.current_server
      end
    end

    def self.included(receiver)
      receiver.extend(ClassMethods)
      receiver.send(:include, InstanceMethods)
    end
  end
end

