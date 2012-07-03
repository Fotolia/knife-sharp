Gem::Specification.new do |s|
  s.name        = 'knife-sharp'
  s.version     = '0.0.2'
  s.date        = '2012-06-15'
  s.summary     = "Knife sharp plugin"
  s.description = "Sharpen your knife"
  s.authors     = ["Nicolas Szalay"]
  s.email       = 'nico@rottenbytes.info'
  s.files       = %w[ 
                    README.md
                    ext/sharp-config.yml
                    lib/knife-sharp.rb
                    lib/chef/knife/sharp-align.rb
                    lib/chef/knife/sharp-history.rb
                  ]
  s.homepage    = 'http://www.rottenbytes.info'
end
