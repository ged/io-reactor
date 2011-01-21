#!/usr/bin/env rake

require 'hoe'

Hoe.plugin :mercurial
Hoe.plugin :yard
Hoe.plugin :signing

Hoe.plugins.delete :rubyforge

hoespec = Hoe.spec 'io_reactor' do
	self.readme_file = 'README.md'
	self.history_file = 'History.md'

	self.developer 'Michael Granger', 'ged@FaerieMUD.org'

	self.extra_dev_deps.push *{
		'rspec' => '~> 2.4',
	}

	self.spec_extras[:licenses] = ["Ruby"]
	self.spec_extras[:signing_key] = '/Volumes/Keys/ged-private_gem_key.pem'

	self.require_ruby_version( '>=1.8.6' )

	self.hg_sign_tags = true if self.respond_to?( :hg_sign_tags= )
	self.yard_opts = [ '--protected', '--verbose' ] if self.respond_to?( :yard_opts= )

	self.rdoc_locations << "deveiate:/usr/local/www/public/code/#{remote_rdoc_dir}"
end

ENV['VERSION'] ||= hoespec.spec.version.to_s

# Ensure the specs pass before checking in
task 'hg:precheckin' => :spec

begin
	include Hoe::MercurialHelpers

	### Task: prerelease
	desc "Append the package build number to package versions"
	task :pre do
		rev = get_numeric_rev()
		trace "Current rev is: %p" % [ rev ]
		hoespec.spec.version.version << "pre#{rev}"
		Rake::Task[:gem].clear

		Gem::PackageTask.new( hoespec.spec ) do |pkg|
			pkg.need_zip = true
			pkg.need_tar = true
		end
	end

	### Make the ChangeLog update if the repo has changed since it was last built
	file '.hg/branch'
	file 'ChangeLog' => '.hg/branch' do |task|
		$stderr.puts "Updating the changelog..."
		content = make_changelog()
		File.open( task.name, 'w', 0644 ) do |fh|
			fh.print( content )
		end
	end

	# Rebuild the ChangeLog immediately before release
	task :prerelease => 'ChangeLog'

rescue NameError => err
	task :no_hg_helpers do
		fail "Couldn't define the :pre task: %s: %s" % [ err.class.name, err.message ]
	end

	task :pre => :no_hg_helpers
	task 'ChangeLog' => :no_hg_helpers

end

