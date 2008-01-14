#!/usr/bin/env ruby

require 'io/reactor'

def debug( msg )
	return unless $DEBUG
	$stderr.puts( "  " + msg )
end

reactor = IO::Reactor.new
data_to_send = "some stuff to send"

reader, writer = IO.pipe

# Read from the reader end of the pipe until the writer finishes
reactor.register( reader, :read ) do |io,event|
	if io.eof?
		debug "done with reading, closing reader"
		reactor.unregister( io )
		io.close
	else
		debug "reading..."
		puts io.read( 256 )
	end
end

# Write to the writer end of the pipe until there's no data left
reactor.register( writer, :write ) do |io,event|
	debug "writing..."
	bytes = io.write( data_to_send )
	data_to_send.slice!( 0, bytes )

	if data_to_send.empty?
		debug "done with writing; closing writer."
		reactor.unregister( io )
		io.close
	end
end

# Now pump the reactor until both sides are done
puts "Starting IO"
until reactor.empty?
	debug "polling..."
	reactor.poll
end
puts "done, exiting."


# $ ruby -d -Ilib examples/simple.rb
# Starting IO
#   polling...
#   writing...
#   done with writing; closing writer.
#   polling...
#   reading...
# some stuff to send
#   polling...
#   done with reading, closing reader
# done, exiting.
