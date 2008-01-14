#!/usr/bin/env ruby

require 'socket'
require 'io/reactor'

listener = TCPServer.new( '127.0.0.1', 18181 )
reactor = IO::Reactor.new

Signal.trap( 'HUP' ) { reactor.clear }
Signal.trap( 'INT' ) { reactor.clear }

reactor.register( listener, :read ) do |sock, _|
	client = sock.accept
	$stderr.puts "Accepted client from %s:%d" % [ client.peeraddr[2], client.peeraddr[1] ]
	# message = Time.now.to_s + "\r\n\r\n"
	message = File.read(__FILE__) + "\r\n\r\n"

	reactor.register( client, message, :write ) do |io, event, buf|
		bytes = io.write( buf )
		buf.slice!( 0, bytes )

		if buf.empty?
			reactor.unregister( io )
			io.close
		end
	end
end


$stdout.puts "Starting up..."
until reactor.empty?
	reactor.poll( 0.1 ) do |io, event|
		case event
		when :error
			$stderr.puts "  %p: in the error event handler" % [ io ]
			reactor.unregister( io )
			io.close
		else
			fail "Reactor got unexpected event %p on %p" % [ event, io ]
		end
	end
end
$stdout.puts "Server shut down."

