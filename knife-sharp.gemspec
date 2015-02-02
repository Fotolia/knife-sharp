require 'date'
require File.join(File.dirname(__FILE__), "lib", "knife-sharp.rb")

Gem::Specification.new do |s|
  s.name        = 'knife-sharp'
  s.version     = KnifeSharp::VERSION
  s.date        = Date.today.to_s
  s.summary     = "Knife sharp plugin"
  s.description = "Sharpen your knife"
  s.homepage    = "https://github.com/Fotolia/knife-sharp"
  s.authors     = [ "Nicolas Szalay", "Jonathan Amiez" ]
  s.email       = [ "nico@rottenbytes.info", "jonathan.amiez@gmail.com" ]
  s.license     = "3-BSD"

  s.files       = %x(git ls-files).split("\n")
  s.require_paths = [ "lib" ]

  s.add_dependency "chef", ">= 11"
  s.add_dependency "grit", "~> 2.5"
end
