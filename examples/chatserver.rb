#!/usr/bin/ruby
# = chatserver.rb
# 
# This is an extremely crude and simple single-threaded multiplexing chat
# server. It (hopefully) demonstrates how to use a Poll object to do IO
# multiplexing with events.
#
# == Synopsis
#
#   $ chatserver.rb [HOST [PORT [POLLDELAY]]]
#
# [HOST]
#   The host or IP the server will bind to
#
# [PORT]
#   The port the server will listen on
#
# [POLLDELAY]
#   The number of floating-point seconds between polls. Specifying -1 (or any
#   negative number, really) here will make the server call poll() in blocking
#   mode.
#
# == Author
# 
# Michael Granger <ged@FaerieMUD.org>
# 
# Copyright (c) 2002 The FaerieMUD Consortium. All rights reserved.
# 
# This program is free software. You may use, modify, and/or redistribute this
# software under the same terms as Ruby itself.
# 
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.
#
# == Version
#
#  $Id: chatserver.rb,v 1.1 2002/04/17 12:45:30 deveiant Exp $
# 

require 'poll'
require 'socket'


### Chat client class
class Client

	MTU	 = 4096
	CR   = "\015"
	LF   = "\012"
	EOL  = CR + LF
	
	PROMPT = 'chat> '

	### Create and return a client object which will use the specified
	### <tt>socket</tt> and <tt>pollObj</tt>.
	def initialize( socket, server )
		@socket = socket
		@server = server
		@obuffer = ''
		@ibuffer = ''
		@peerHost = @socket.peeraddr[2]
		@peerPort = @socket.peeraddr[1]
		@connected = true
	end

	# Object attribute
	attr_reader :socket, :server, :ibuffer, :obuffer


	### Return a stringified version of the client
	def to_s
		"%s:%d" % [ @peerHost, @peerPort ]
	end


	### Add the specified string to the client's output buffer and turn on
	### output events.
	def addOutput( string )
		@obuffer << string.chomp << EOL
		@server.pollObj.addMask( @socket, Poll::WRNORM )
	end
	alias :<< :addOutput


	### Write as much of the output buffer to the socket as possible, and return
	### the number of bytes remaining to be sent.
	def writeOutput
		bytes = @socket.syswrite( @obuffer )
		@obuffer[ 0, bytes ] = '' if bytes.nonzero?
		return @obuffer.length
	end


	### Write a prompt to the client
	def prompt
		@obuffer << PROMPT
		@server.pollObj.addMask( @socket, Poll::WRNORM )
	end


	### Read at most MTU bytes from the socket and append them to the input
	### buffer. Split off any complete lines (one that end with EOL) and return
	### them as an Array of Strings.
	def readInput
		rary = []
		@ibuffer << @socket.sysread( MTU )
		$stderr.puts "Input buffer for client #{self} now: #@ibuffer" if $VERBOSE
		while (( pos = @ibuffer.index EOL ))
			$stderr.puts "Found terminating EOL. Splitting off 0..#{pos} of the input buffer." if $VERBOSE
			rary << @ibuffer[ 0, pos ]
			@ibuffer[ 0, pos + EOL.length ] = ''
		end

		return rary
	rescue EOFError
		@server.disconnectClient( self )
		return []
	end


	### Handle poll events on the socket
	def handlePollEvent( io, evmask )
		case evmask

		when Poll::ERR|Poll::HUP|Poll::NVAL
			@server.disconnectClient( self )
			
		when Poll::RDNORM
			input = readInput()
			@server.processInput( self, *input ) unless input.empty?

		when Poll::WRNORM
			bytesLeft = writeOutput()
			@server.pollObj.removeMask( @socket, Poll::WRNORM ) if bytesLeft.zero?

		end

	end


	### Disconnect the client
	def disconnect( msg='' )
		@connected = false
		unless msg.empty?
			@obuffer = ">>> Disconnected: #{msg} <<<" + EOL
		else
			@obuffer = ">>> Disconnected <<<" + EOL
		end
		writeOutput()
		@socket.close
	end


	### Returns true if the client is still connected
	def connected?
		@connected
	end
end


### Chat server class
class Server

	BANNER = <<-EOF
	[[ Ruby-Poll Example Chatserver ]]
	Commands: '/quit' to quit, '/shutdown' to shut the server down
	EOF

	### Instantiate and return a chatserver on the specified host and port
	def initialize( listenHost="0.0.0.0", listenPort=1138, interval=0.20 )
		raise "This server requires the POLLRDNORM and POLLWRNORM constants, which " +
			"don't seem to be defined by your machine's implementation. Sorry. " unless
			Poll.const_defined?( :RDNORM ) && Poll.const_defined?( :WRNORM )

		@socket			= TCPServer::new( listenHost, listenPort )
		@clients		= []
		@pollObj		= Poll::new
		@pollInterval	= interval
		@shuttingDown	= false

		@pollObj.register @socket, Poll::RDNORM, method(:handlePollEvent)
	end

	# Server attributes
	attr_reader :pollObj, :clients, :socket


	### Main server loop
	def pollLoop

		trap( "INT" ) { shutdown("Server caught SIGINT") }
		trap( "TERM" ) { shutdown("Server caught SIGTERM") }
		trap( "HUP" ) { disconnectAllClients(">>> Server reset <<<") }

		until @shuttingDown
			eventCount = @pollObj.poll( @pollInterval )
			$stderr.puts "#{eventCount} poll events..." if eventCount.nonzero?
		end

	rescue StandardError => e
		shutdown( "Server error: #{e.message}" )
	rescue SignalException => e
		shutdown( "Server caught #{e.type.name}" )
	ensure
		trap( "INT", "SIG_IGN" )
		trap( "TERM", "SIG_IGN" )
		trap( "HUP", "SIG_IGN" )

		$stderr.puts "Server exiting poll loop."
	end


	### Handle a poll event specified by <tt>evmask</tt> on the specified
	### <tt>socket</tt>
	def handlePollEvent( socket, evmask )
		case evmask

		when Poll::ERR|Poll::HUP|Poll::NVAL
			shutdown()

		when Poll::RDNORM
			clSock = socket.accept
			client = Client::new( clSock, self )
			$stderr.puts "Accepted connection from #{client}"
			@pollObj.register clSock, Poll::RDNORM, client.method(:handlePollEvent)
			client.addOutput( BANNER )
			client.prompt
			broadcastMsg( "[New connection: #{client}]" )
			@clients << client

		end
	end


	### Process the specified input from the specified client
	def processInput( client, *inputStrings )
		inputStrings.each {|str|
			case str

			when %r{^/(\w+)\s*(.*)}
				handleCommand( client, $1, $2 )

			else
				client.addOutput( "You>> #{str}" )
				broadcastMsgFrom( client, str )
			end
		}

		client.prompt if client.connected?
	end


	### Handle the specified command from the specified client
	def handleCommand( client, command, args )
		case command

		when /quit/
			disconnectClient( client, 'Quit' )
			
		when /shutdown/
			shutdown()

		when /who/
			client.addOutput( self.wholist(client) )

		else
			client.addOutput("Unknown command '#{command}'")
		end
	end


	### Broadcast the specified message to all connected clients
	def broadcastMsg( msg )
		@clients.each {|cl|
			cl.addOutput( msg )
		}
	end


	### Broadcast the specified message from the specified client
	def broadcastMsgFrom( client, msg )
		clientDesc = client.to_s

		@clients.each {|cl|
			next if cl == client
			cl.addOutput( "#{clientDesc}>> #{msg}" )
		}
	end


	### Disconnect the specified client
	def disconnectClient( client, msg='' )
		@clients -= [ client ]
		@pollObj.unregister client.socket
		client.disconnect( msg )
		broadcastMsg( "#{client.to_s} Disconnected." )
	end


	### Disconnect all connected clients
	def disconnectAllClients( msg )
		@clients.each {|cl| cl.disconnect(msg) }
		@clients.clear
	end


	### Shut the server down
	def shutdown( msg="Server shutdown" )
		@shuttingDown = true
		@pollObj.clear
		begin
			@socket.shutdown
		rescue
		end
		disconnectAllClients( msg )
		begin
			@socket.close
		rescue
		end
	end

	### Build and return a list of connected clients for the specified client.
	def wholist( client )
		rval = "[Connected Users]\n" <<
			"  *#{client}*\n"
		@clients.each {|cl|
			next if cl == client
			rval << "  #{cl}\n"
		}

		return rval
	end

end

srv = Server::new( *ARGV )
$stderr.puts "Chat server listening on #{srv.socket.addr[2]} port #{srv.socket.addr[1]}"
srv.pollLoop
$stderr.puts "Chat server finished."

