#!/usr/bin/ruby -*- ruby -*-

BEGIN {
	require 'pathname'
	basedir = Pathname.new( __FILE__ ).dirname.expand_path
	libdir = basedir + "lib"

	puts ">>> Adding #{libdir} to load path..."
	$LOAD_PATH.unshift( libdir.to_s )
}


# Try to require the 'thingfish' library
begin
	require 'io/reactor'
rescue => e
	$stderr.puts "Ack! IO::Reactor library failed to load: #{e.message}\n\t" +
		e.backtrace.join( "\n\t" )
end

