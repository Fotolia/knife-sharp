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
    end

    def self.included(receiver)
      receiver.extend(ClassMethods)
      receiver.send(:include, InstanceMethods)
    end
  end
end

