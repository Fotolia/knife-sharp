require File.join(File.dirname(__FILE__), "lib", "knife-sharp.rb")

Gem::Specification.new do |s|
  s.name        = 'knife-sharp'
  s.version     = KnifeSharp::VERSION
  s.date        = '2012-10-12'
  s.summary     = "Knife sharp plugin"
  s.description = "Sharpen your knife"
  s.authors     = [ "Nicolas Szalay", "Jonathan Amiez" ]
  s.email       = 'nico@rottenbytes.info'
  s.files       = %w[
                    README.md
                    ext/sharp-config.yml
                    lib/knife-sharp.rb
                    lib/chef/knife/sharp-align.rb
                    lib/chef/knife/sharp-history.rb
                    lib/chef/knife/sharp-backup.rb
                  ]
  s.homepage    = 'http://www.rottenbytes.info'
  s.add_dependency "grit", "~> 2.5.0"
end
