#!/usr/bin/ruby
#
#	Ruby-Project Documentation Generation Script
#	$Id: makesitedocs.rb,v 1.1 2002/04/18 18:01:03 deveiant Exp $
#
#	Copyright (c) 2001,2002 The FaerieMUD Consortium.
#
#	This is free software. You may use, modify, and/or redistribute this
#	software under the terms of the Perl Artistic License. (See
#	http://language.perl.com/misc/Artistic.html)
#

# Muck with the load path and the cwd
$basedir = File::expand_path( $0 ).sub( %r{/makesitedocs.rb}, '' )
unless $basedir.empty? || Dir.getwd == $basedir
	$stderr.puts "Changing working directory from '#{Dir.getwd}' to '#$basedir'"
	Dir.chdir( $basedir ) 
end

$LOAD_PATH.unshift "docs/lib"

# Load modules
require 'getoptlong'
require 'rdoc/rdoc'
require 'ftools'

require './utils.rb'
include UtilityFunctions


# Extract the project name from CVS
$project = extractProjectName()

# Read command-line options
opts = GetoptLong.new
opts.set_options(
	[ '--debug',	'-d',	GetoptLong::NO_ARGUMENT ],
	[ '--verbose',	'-v',	GetoptLong::NO_ARGUMENT ],
	[ '--upload',	'-u',	GetoptLong::REQUIRE_ARGUMENT ]
)

$docsdir = "docs/html"
$libdirs = %w{lib examples README}
opts.each {|opt,val|
	case opt

	when '--debug'
		$debug = true

	when '--verbose'
		$verbose = true

	when '--upload'
		$upload = val

	end
}


header "Making documentation in #$docsdir from files in #{$libdirs.join(', ')}."

flags = [
	'--all',
	'--inline-source',
	'--main', 'README',
	'--fmt', 'myhtml',
	'--include', 'docs',
	'--template', 'faeriemud',
	'--op', $docsdir,
	'--title', "Ruby-Poll"
]

message "Running 'rdoc #{flags.join(' ')} #{$libdirs.join(' ')}'\n" if $verbose

unless $debug
	begin
		r = RDoc::RDoc.new
		r.document( flags + $libdirs  )
	rescue RDoc::RDocError => e
		$stderr.puts e.message
		exit(1)
	end
end

if $upload
	header "Uploading new docs snapshot to #$upload."
	case $upload
	
	# SSH target
	when %r{^ssh://(.*)}
		target = $1
		if target =~ %r{^([^/]+)/(.*)}
			host, dir = $1, $2
			unless $debug
				system( "tar -C docs/html -cf - . | ssh #{host} 'tar -C #{dir}/Ruby-Poll -xvf -'" )
			else
				message %{system( "tar -C docs/html -cf - . | ssh galendril 'tar -C /www/devEiate.org/public/code/Ruby-Poll -xvf -'" )}
			end

	else
			File.makedirs TARGETDIR
			Dir["docs/html/**/*"].each {|file|
				fname = file.gsub( %r{docs/html/}, '' )
				if File.directory? file
					unless $debug
						File.makedirs File.join(TARGETDIR, fname), true
					else
						message %{File.makedirs %s, true\n} % File.join(TARGETDIR, fname)
					end
				else
					unless $debug
						File.install( file, File.join(TARGETDIR, fname), 0444, true )
					else
						message %{File.install( %s, %s, 0444, true )\n} % [
							file,
							File.join(TARGETDIR, fname),
						]
					end
				end
			}
		else
		end
	end
end

# rdoc \
#	--all \
#	--inline_source \
#	--main README \
#	--fmt myhtml \
#	--include docs \
#	--template faeriemud \
#	--title "Ruby-Poll" \
#		lib ext examples README
