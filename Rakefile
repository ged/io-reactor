#!rake
#
# IO-Reactor rakefile
#
# Copyright (c) 2002-2008 The FaerieMUD Consortium. All rights reserved.
# 
# This module is free software. You may use, modify, and/or redistribute this
# software under the same terms as Ruby itself.
# 
# This library is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.
#

BEGIN {
	require 'pathname'
	basedir = Pathname.new( __FILE__ ).dirname
	libdir = basedir + 'lib'
	docsdir = basedir + 'docs'

	$LOAD_PATH.unshift( libdir.to_s ) unless $LOAD_PATH.include?( libdir.to_s )
	$LOAD_PATH.unshift( docsdir.to_s ) unless $LOAD_PATH.include?( docsdir.to_s )
}


require 'rubygems'
require 'rake'
require 'rake/rdoctask'
require 'rake/packagetask'
require 'rake/gempackagetask'
require 'pathname'

$dryrun = false

# Pathname constants
BASEDIR       = Pathname.new( __FILE__ ).dirname.expand_path
LIBDIR        = BASEDIR + 'lib'
DOCSDIR       = BASEDIR + 'docs'
MISCDIR       = BASEDIR + 'misc'
PKGDIR        = BASEDIR + 'pkg'
SPECDIR       = BASEDIR + 'spec'

# Directory for CruiseControl.rb to store its build artifacts
ARTIFACTS_DIR = Pathname.new( ENV['CC_BUILD_ARTIFACTS'] || '' )

TEXT_FILES    = %w( Rakefile README ).collect {|filename| BASEDIR + filename }
LIB_FILES     = Pathname.glob( LIBDIR + '**/*.rb').delete_if {|item| item =~ /\.svn/ }
SPEC_FILES    = Pathname.glob( SPECDIR + '**/*_spec.rb' ).delete_if {|item| item =~ /\.svn/ }

SPEC_EXCLUDES = 'spec,monkeypatches,/Library/Ruby'

RELEASE_FILES = TEXT_FILES + LIB_FILES + SPEC_FILES

# Load some helper functions
require MISCDIR + 'rake_helpers'

### Package constants
PKG_NAME      = 'io-reactor'
PKG_TITLE     = "IO::Reactor -- multiplexed asynchronous single-thread IO via the Reactor pattern"
PKG_VERSION   = find_pattern_in_file( /VERSION = '(\d+\.\d+\.\d+)'/, LIBDIR + 'io/reactor.rb' ).first
PKG_FILE_NAME = "#{PKG_NAME}-#{PKG_VERSION}"

RELEASE_NAME  = "REL #{PKG_VERSION}"

# Load task plugins
RAKE_TASKDIR = MISCDIR
Pathname.glob( RAKE_TASKDIR + '*.rb' ).each do |tasklib|
	next if tasklib =~ %r{/rake_helpers.rb$}
	require tasklib
end


# Turn on trace/dryrun via globals like it used to
if Rake.application.options.trace
	$trace = true
	log "$trace is enabled"
end

if Rake.application.options.dryrun
	$dryrun = true
	log "$dryrun is enabled"
	Rake.application.options.dryrun = false
end

### Default task
task :default  => [:clean, :spec, :verify, :package]


### Task: clean
desc "Clean pkg, coverage, and rdoc; remove .bak files"
task :clean => [ :clobber_rdoc, :clobber_package, :clobber_coverage ] do
	files = FileList['**/*.bak']
	files.clear_exclude
	File.rm( files ) unless files.empty?
	FileUtils.rm_rf( 'artifacts' )
end


### Task: docs -- Convenience task for rebuilding dynamic docs, including coverage, api 
### docs, and manual
task :docs => [ :coverage, :rdoc ]


### Task: rdoc
Rake::RDocTask.new do |rdoc|
	rdoc.rdoc_dir = 'docs/api'
	rdoc.title    = PKG_TITLE

	rdoc.options += [
		'-w', '4',
		'-SHN',
		'-i', 'docs',
		'-f', 'darkfish',
		'-m', 'README',
		'-W', 'http://deveiate.org/projects/IO-Reactor/browser/trunk/'
	  ]
	
	rdoc.rdoc_files.include 'README'
	rdoc.rdoc_files.include LIB_FILES.collect {|f| f.relative_path_from(BASEDIR).to_s }
end


### Task: gem
gemspec = Gem::Specification.new do |gem|
	pkg_build = get_svn_rev( BASEDIR ) || 0
	
	gem.name    	= PKG_NAME
	gem.version 	= PKG_VERSION

	gem.summary     = "Multiplexed IO Reactor class"
	gem.description = <<-EOD
	This module is a pure-Ruby implementation of an asynchronous multiplexed IO
	Reactor which is based on the Reactor design pattern found in _Pattern-Oriented
	Software Architecture, Volume 2: Patterns for Concurrent and Networked
	Objects_. It allows a single thread to demultiplex and dispatch events from one
	or more IO objects to the appropriate handler.
	EOD

	gem.authors  	= "Michael Granger"
	gem.email  	    = "ged@FaerieMUD.org"
	gem.homepage 	= "http://deveiate.org/projects/IO-Reactor/"
	gem.signing_key = Pathname.new( "~/.gemkey.pem" ).expand_path.to_s
	gem.cert_chain  = [ Pathname.new("~/.gemcert.pem").expand_path.to_s ]

	gem.rubyforge_project = "arrow"
	gem.has_rdoc 	= true

	gem.files      	= RELEASE_FILES.
		collect {|f| f.relative_path_from(BASEDIR).to_s }
	gem.test_files 	= SPEC_FILES.
		collect {|f| f.relative_path_from(BASEDIR).to_s }
end
Rake::GemPackageTask.new( gemspec ) do |task|
	task.gem_spec     = gemspec
	task.need_tar     = false
	task.need_tar_gz  = true
	task.need_tar_bz2 = true
	task.need_zip     = true
end


### Task: install
task :install_gem => [:package] do
	$stderr.puts 
	installer = Gem::Installer.new( %{pkg/#{PKG_FILE_NAME}.gem} )
	installer.install
end

### Task: uninstall
task :uninstall_gem => [:clean] do
	uninstaller = Gem::Uninstaller.new( PKG_FILE_NAME )
	uninstaller.uninstall
end



### Cruisecontrol task
desc "Cruisecontrol build"
task :cruise => [:clean, :coverage, :package] do |task|
	raise "Artifacts dir not set." if ARTIFACTS_DIR.to_s.empty?
	artifact_dir = ARTIFACTS_DIR.cleanpath
	artifact_dir.mkpath
	
	$stderr.puts "Copying coverage stats..."
	FileUtils.cp_r( 'coverage', artifact_dir )
	
	$stderr.puts "Copying packages..."
	FileUtils.cp_r( FileList['pkg/*'].to_a, artifact_dir )
end



### RSpec tasks
begin
	gem 'rspec', '>= 1.1.1'
	require 'spec/rake/spectask'

	COMMON_SPEC_OPTS = ['-c', '-f', 's']

	### Task: spec
	Spec::Rake::SpecTask.new( :spec ) do |task|
		task.spec_files = SPEC_FILES
		task.libs += [LIBDIR]
		task.spec_opts = COMMON_SPEC_OPTS
	end
	task :test => [:spec]


	namespace :spec do
		desc "Run rspec every time there's a change to one of the files"
        task :autotest do
            require 'autotest/rspec'

			### Mmmm... smells like monkeys
			class Autotest::Rspec

				### Search the path for 'spec' in addition to the simple included methods
				### for finding it.
				def spec_commands
					path = ENV['PATH'].split( File::PATH_SEPARATOR )
					return path.collect {|dir| File.join(dir, 'spec') } +
					[
						File.join('bin', 'spec'),
						File.join(Config::CONFIG['bindir'], 'spec')
					]
				end

			end

            autotester = Autotest::Rspec.new
			autotester.exceptions = %r{\.svn|\.skel}
            autotester.run
        end

	
		desc "Generate HTML output for a spec run"
		Spec::Rake::SpecTask.new( :html ) do |task|
			task.spec_files = SPEC_FILES
			task.spec_opts = ['-f','h', '-D']
		end

		desc "Generate plain-text output for a CruiseControl.rb build"
		Spec::Rake::SpecTask.new( :text ) do |task|
			task.spec_files = SPEC_FILES
			task.spec_opts = ['-f','p']
		end
	end
rescue LoadError => err
	task :no_rspec do
		$stderr.puts "Testing tasks not defined: RSpec rake tasklib not available: %s" %
			[ err.message ]
	end
	
	task :spec => :no_rspec
	namespace :spec do
		task :autotest => :no_rspec
		task :html => :no_rspec
		task :text => :no_rspec
	end
end


### RCov (via RSpec) tasks
begin
	gem 'rcov'
	gem 'rspec', '>= 1.1.1'

	RCOV_OPTS = ['--exclude', SPEC_EXCLUDES, '--xrefs']

	### Task: coverage (via RCov)
	### Task: spec
	desc "Build test coverage reports"
	Spec::Rake::SpecTask.new( :coverage ) do |task|
		task.spec_files = SPEC_FILES
		task.libs += [LIBDIR]
		task.spec_opts = ['-f', 'p', '-b']
		task.rcov_opts = RCOV_OPTS + ['--save']
		task.rcov = true
	end
	
	task :rcov => [:coverage] do; end
	
	### Other coverage tasks
	namespace :coverage do
		desc "Generate a detailed text coverage report"
		Spec::Rake::SpecTask.new( :text ) do |task|
			task.spec_files = SPEC_FILES
			task.rcov_opts = RCOV_OPTS + ['--text-report']
			task.rcov = true
		end

		desc "Show differences in coverage from last run"
		Spec::Rake::SpecTask.new( :diff ) do |task|
			task.spec_files = SPEC_FILES
			task.rcov_opts = RCOV_OPTS + ['--text-coverage-diff']
			task.rcov = true
		end

		### Task: verify coverage
		desc "Build coverage statistics"
		VerifyTask.new( :verify => :rcov ) do |task|
			task.threshold = 85.0
		end
		
		desc "Run RCov in 'spec-only' mode to check coverage from specs"
		Spec::Rake::SpecTask.new( :speconly ) do |task|
			task.spec_files = SPEC_FILES
			task.rcov_opts = ['--exclude', SPEC_EXCLUDES, '--text-report']
			task.rcov = true
		end
	end

rescue LoadError => err
	task :no_rcov do
		$stderr.puts "Coverage tasks not defined: RSpec+RCov tasklib not available: %s" %
			[ err.message ]
	end

	task :coverage => :no_rcov
	task :clobber_coverage
	task :rcov => :no_rcov
	namespace :coverage do
		task :text => :no_rcov
		task :diff => :no_rcov
	end
	task :verify => :no_rcov
end



### Coding style checks and fixes
namespace :style do
	
	BLANK_LINE = /^\s*$/
	GOOD_INDENT = /^(\t\s*)?\S/

	# A list of the files that have legitimate leading whitespace, etc.
	PROBLEM_FILES = []
	
	desc "Check source files for inconsistent indent and fix them"
	task :fix_indent do
		files = LIB_FILES + SPEC_FILES

		badfiles = Hash.new {|h,k| h[k] = [] }
		
		trace "Checking files for indentation"
		files.each do |file|
			if PROBLEM_FILES.include?( file )
				trace "  skipping problem file #{file}..."
				next
			end
			
			trace "  #{file}"
			linecount = 0
			file.each_line do |line|
				linecount += 1
				
				# Skip blank lines
				next if line =~ BLANK_LINE
				
				# If there's a line with incorrect indent, note it and skip to the 
				# next file
				if line !~ GOOD_INDENT
					trace "    Bad line %d: %p" % [ linecount, line ]
					badfiles[file] << [ linecount, line ]
				end
			end
		end

		if badfiles.empty?
			log "No indentation problems found."
		else
			log "Found incorrect indent in #{badfiles.length} files:\n  "
			badfiles.each do |file, badlines|
				log "  #{file}:\n" +
					"    " + badlines.collect {|badline| "%5d: %p" % badline }.join( "\n    " )
			end
		end
	end

end


