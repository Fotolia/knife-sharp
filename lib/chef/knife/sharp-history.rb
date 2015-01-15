require 'knife-sharp/common'

module KnifeSharp
  class SharpHistory < Chef::Knife
    include KnifeSharp::Common

    banner "knife sharp history"

    option :debug,
      :long  => '--debug',
      :description => "turn debug on",
      :default => false

    def run
      show_logs()
    end

    def show_logs()
      begin
        fp = File.open(File.expand_path(sharp_config["logging"]["destination"]), "r")
        fp.readlines.each do |line|
          puts line
        end
      rescue Exception => e
        ui.error "oops ! #{e.inspect}"
      end
    end
  end
end
