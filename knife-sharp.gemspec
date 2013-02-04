require 'date'
require File.join(File.dirname(__FILE__), "lib", "knife-sharp.rb")

Gem::Specification.new do |s|
  s.name        = 'knife-sharp'
  s.version     = KnifeSharp::VERSION
  s.date        = Date.today.to_s
  s.summary     = "Knife sharp plugin"
  s.description = "Sharpen your knife"
  s.authors     = [ "Nicolas Szalay", "Jonathan Amiez" ]
  s.email       = [ "nico@rottenbytes.info", "jonathan.amiez@gmail.com" ]
  s.files       = %w[
                    README.md
                    ext/sharp-config.yml
                    lib/knife-sharp.rb
                    lib/chef/knife/sharp-align.rb
                    lib/chef/knife/sharp-backup.rb
                    lib/chef/knife/sharp-history.rb
                    lib/chef/knife/sharp-server.rb
                  ]
  s.homepage    = "https://github.com/Fotolia/knife-sharp"
  s.add_dependency "chef", ">= 10.14.0"
  s.add_dependency "grit", "~> 2.5.0"
end
