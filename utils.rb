#
#	Install/distribution utility functions
#	$Id: utils.rb,v 1.1 2002/04/18 18:01:03 deveiant Exp $
#
#	Copyright (c) 2001, The FaerieMUD Consortium.
#
#	This is free software. You may use, modify, and/or redistribute this
#	software under the terms of the Perl Artistic License. (See
#	http://language.perl.com/misc/Artistic.html)
#

require "readline"
include Readline

module UtilityFunctions

	# The list of regexen that eliminate files from the MANIFEST
	ANTIMANIFEST = [
		/makedist\.rb/,
		/\bCVS\b/,
		/~$/,
		/^#/,
		%r{docs/html},
		%r{docs/man},
		/^TEMPLATE/,
		/\.cvsignore/
	]

	# Set some ANSI escape code constants (Shamelessly stolen from Perl's
	# Term::ANSIColor by Russ Allbery <rra@stanford.edu> and Zenin <zenin@best.com>
	AnsiAttributes = {
		'clear'      => 0,
		'reset'      => 0,
		'bold'       => 1,
		'dark'       => 2,
		'underline'  => 4,
		'underscore' => 4,
		'blink'      => 5,
		'reverse'    => 7,
		'concealed'  => 8,

		'black'      => 30,   'on_black'   => 40, 
		'red'        => 31,   'on_red'     => 41, 
		'green'      => 32,   'on_green'   => 42, 
		'yellow'     => 33,   'on_yellow'  => 43, 
		'blue'       => 34,   'on_blue'    => 44, 
		'magenta'    => 35,   'on_magenta' => 45, 
		'cyan'       => 36,   'on_cyan'    => 46, 
		'white'      => 37,   'on_white'   => 47
	}
	def ansiCode( *attributes )
		attr = attributes.collect {|a| AnsiAttributes[a] ? AnsiAttributes[a] : nil}.compact.join(';')
		if attr.empty? 
			return ''
		else
			return "\e[%sm" % attr
		end
	end
	ErasePreviousLine = "\033[A\033[K"

	def testForLibrary( lib, nicename=nil )
		nicename ||= "'lib'"
		message( "Testing for the #{nicename} library..." )
		if $:.detect {|dir| File.exists?(File.join(dir,"#{lib}.rb")) || File.exists?(File.join(dir,"#{lib}.so"))}
			message( "found.\n" )
			return true
		else
			message( "not found.\n" )
			return false
		end
	end

	def testForRequiredLibrary( lib, nicename=nil, raaUrl=nil, downloadUrl=nil )
		nicename ||= "'lib'"
		unless testForLibrary( lib, nicename )
			msgs = [ "You are missing the #{nicename} library.\n" ]
			msgs << "RAA: #{raaUrl}\n" if raaUrl
			msgs << "Download: #{downloadUrl}\n" if downloadUrl
			message( msgs )
			exit 1
		end
		return true
	end

	def header( msg )
		msg.chomp!
		print ansiCode( 'bold', 'white', 'on_blue' ) + msg + ansiCode( 'reset' ) + "\n"
	end

	def message( msg )
		$stdout.print msg
		$stdout.flush
	end

	def replaceMessage( *msg )
		print ErasePreviousLine
		message( *msg )
	end

	def abort( msg )
		print ansiCode( 'bold', 'red' ) + "Aborted: " + msg.chomp + ansiCode( 'reset' ) + "\n\n"
		Kernel.exit!( 1 )
	end

	def prompt( promptString )
		promptString.chomp!
		return readline( ansiCode('bold', 'green') + "#{promptString}: " + ansiCode('reset') ).strip
	end

	def promptWithDefault( promptString, default )
		response = prompt( "%s [%s]" % [ promptString, default ] )
		if response.empty?
			return default
		else
			return response
		end
	end

	def findProgram( progname )
		ENV['PATH'].split(File::PATH_SEPARATOR).each {|d|
			file = File.join( d, progname )
			return file if File.executable?( file )
		}
		return nil
	end

	def extractNextVersionFromTags( file )
		message "Attempting to extract next release version from CVS tags for #{file}...\n"
		raise RuntimeError, "No such file '#{file}'" unless File.exists?( file )
		cvsPath = findProgram( 'cvs' ) or
			raise RuntimeError, "Cannot find the 'cvs' program. Aborting."

		output = %x{#{cvsPath} log #{file}}
		release = [ 0, 0 ]
		output.scan( /RELEASE_(\d+)_(\d+)/ ) {|match|
			if $1.to_i > release[0] || $2.to_i > release[1]
				release = [ $1.to_i, $2.to_i ]
				replaceMessage( "Found %d.%02d...\n" % release )
			end
		}

		if release[1] >= 99
			release[0] += 1
			release[1] = 1
		else
			release[1] += 1
		end

		return "%d.%02d" % release
	end

	def extractProjectName
		File.open( "CVS/Repository", "r").readline.chomp
	end

	def readManifest( manifestName="MANIFEST" )
		raise "Missing #{manifestName}, please remake it" unless File.exists? manifestName

		manifest = IO::readlines( manifestName ).collect {|line|
			line.chomp
		}.select {|line|
			line !~ /^(\s*(#.*)?)?$/
		}

		filelist = []
		for pat in manifest
			filelist |= Dir.glob( pat ).find_all {|f| FileTest.file?(f)}
		end

		return filelist
	end

	def vetManifest( filelist, antimanifest=ANITMANIFEST )
		origLength = filelist.length

		for regex in antimanifest
			filelist.delete_if {|file| regex.match(file)}
		end

		return filelist
	end

	def getVettedManifest( manifestName="MANIFEST", antimanifest=ANTIMANIFEST )
		vetManifest( readManifest(manifestName), antimanifest )
	end

	def findRdocableFiles
		startlist = []
		if File.exists? "docs/CATALOG"
			message "Using docs/CATALOG\n"
			startlist = getVettedManifest( "docs/CATALOG" )
		else
			message "Using default MANIFEST\n"
			startlist = getVettedManifest()
		end

		message "Looking for RDoc comments in:\n"
		startlist.select {|fn|
			message "  #{fn}: "
			found = false
			File::open( fn, "r" ) {|fh|
				fh.each {|line|
					if line =~ /^#\s*=/ || line =~ /#\s*:\w+:/ || line =~ %r{/*}
						found = true
						break
					end
				}
			}

			message( (found ? "yes" : "no") + "\n" )
			found
		}
	end
end
