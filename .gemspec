# -*- ruby -*-
#
# IO-Reactor RubyGem specification
# $Id$
#

require 'rubygems'
require './utils.rb'
include UtilityFunctions
require 'date'

spec = Gem::Specification.new do |s|
  s.name = extractProjectName()
  s.version = extractVersion().join('.')
  s.date = Date.today.to_s
  s.summary = %q{An implementation of the Reactor design pattern for multiplexed asynchronous single-thread IO.}
  s.description =<<DESCRIPTION
An implementation of the Reactor design pattern for multiplexed asynchronous single-thread IO.
DESCRIPTION
  s.author = %q{Michael Granger}
  s.email = %q{ged@FaerieMUD.org}
  s.homepage = %q{http://www.deveiate.org/code/IO-Reactor.html}
  s.files = getVettedManifest()
  s.require_path = %w{lib}
  s.autorequire = %q{io/reactor}
  s.has_rdoc = true
  s.rdoc_options = ["--main", "README"]
  s.extra_rdoc_files = ["README"]
  s.test_file = 'test.rb'
  s.required_ruby_version = Gem::Version::Requirement.new(">= 1.8.0")
end

if $0==__FILE__
	p spec
	Gem.manage_gems
	Gem::Builder.new(spec).build
end
