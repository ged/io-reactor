#!/usr/bin/ruby
# = chatserver.rb
# 
# This is an extremely crude and simple single-threaded multiplexing chat
# server. It (hopefully) demonstrates how to use a IO::Reactor object to do IO
# multiplexing with events.
#
# == Synopsis
#
#   $ chatserver.rb [HOST [PORT [LOOPTIMEOUT]]]
#
# [HOST]
#   The host or IP the server will bind to
#
# [PORT]
#   The port the server will listen on
#
# [LOOPTIMEOUT]
#   The number of floating-point seconds between polls. Specifying -1 (or any
#   negative number, really) here will make the server's event loop block on the
#   call to #poll.
#
# == Author
# 
# Michael Granger <ged@FaerieMUD.org>
# 
# Copyright (c) 2002, 2003 The FaerieMUD Consortium. All rights reserved.
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
#  $Id: chatserver.rb,v 1.4 2003/08/04 23:53:32 deveiant Exp $
# 

require 'io/reactor'
require 'socket'

module Example

### Chatserver user class -- part of the chatserver example.
class User

	MTU	 = 4096
	CR   = "\015"
	LF   = "\012"
	EOL  = CR + LF
	
	PROMPT = 'chat> '

	### Create and return a user object which will use the specified
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


	### Return a stringified version of the user
	def to_s
		"%s:%d" % [ @peerHost, @peerPort ]
	end


	### Add the specified string to the user's output buffer and turn on
	### output events.
	def addOutput( string )
		@obuffer << string.chomp << EOL
		@server.reactor.enableEvents( @socket, :write )
	end
	alias :<< :addOutput


	### Write as much of the output buffer to the socket as possible, and return
	### the number of bytes remaining to be sent.
	def writeOutput
		bytes = @socket.syswrite( @obuffer )
		@obuffer[ 0, bytes ] = '' if bytes.nonzero?
		return @obuffer.length
	end


	### Write a prompt to the user
	def prompt
		@obuffer << PROMPT
		@server.reactor.enableEvents( @socket, :write )
	end


	### Read at most MTU bytes from the socket and append them to the input
	### buffer. Split off any complete lines (one that end with EOL) and return
	### them as an Array of Strings.
	def readInput
		rary = []
		@ibuffer << @socket.sysread( MTU )
		$stderr.puts "Input buffer for user #{self} now: #@ibuffer" if $VERBOSE
		while (( pos = @ibuffer.index EOL ))
			$stderr.puts "Found terminating EOL. "\
				"Splitting off 0..#{pos} of the input buffer." if $VERBOSE
			rary << @ibuffer[ 0, pos ]
			@ibuffer[ 0, pos + EOL.length ] = ''
		end

		return rary
	rescue EOFError
		@server.disconnectUser( self )
		return []
	end


	### Handle poll events on the socket
	def handleIOEvent( io, event )
		case event

		when :error
			@server.disconnectUser( self )
			
		when :read
			input = readInput()
			@server.processInput( self, *input ) unless input.empty?

		when :write
			bytesLeft = writeOutput()
			@server.reactor.disableEvents( @socket, :write ) if bytesLeft.zero?

		end

	end


	### Disconnect the user
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


	### Returns true if the user is still connected
	def connected?
		@connected
	end
end # class User


### Example chatserver class -- an extremely crude and simple chat server that
### demonstrates how to use Poll to do multiplexing IO in a single thread.
class Server

	BANNER = <<-EOF
	[[ IO::Reactor Example Chatserver ]]
	Commands: '/quit' to quit, '/shutdown' to shut the server down
	EOF

	### Instantiate and return a chatserver on the specified host and port
	def initialize( listenHost="0.0.0.0", listenPort=1138, interval=0.20 )
		@socket			= TCPServer::new( listenHost, listenPort )
		@users			= []
		@reactor		= IO::Reactor::new
		@pollInterval	= interval
		@shuttingDown	= false

		@reactor.register @socket, :read, &method(:handlePollEvent)
	end

	# Server attributes
	attr_reader :reactor, :users, :socket


	### Main server loop
	def eventLoop
		trap( "INT" ) { shutdown("Server caught SIGINT") }
		trap( "TERM" ) { shutdown("Server caught SIGTERM") }
		trap( "HUP" ) { disconnectAllUsers(">>> Server reset <<<") }

		until @shuttingDown
			eventCount = @reactor.poll( @pollInterval )
		end

	rescue StandardError => e
		$stderr.puts "Error in server: #{e.message}"
		$stderr.puts "\t" + e.backtrace.join( "\n\t" )
		shutdown( "Server error: #{e.message}" )
	rescue SignalException => e
		shutdown( "Server caught #{e.type.name}" )
	ensure
		trap( "INT", "SIG_IGN" )
		trap( "TERM", "SIG_IGN" )
		trap( "HUP", "SIG_IGN" )

		$stderr.puts "Server exiting event loop."
	end


	### Handle a poll event specified by <tt>event</tt> on the specified
	### <tt>socket</tt>
	def handlePollEvent( socket, event )
		$stderr.puts "Got #{event.inspect} event for #{socket.inspect}"

		case event
		when :error
			$stderr.puts "Socket error on the listener socket."
			shutdown()

		when :read
			clSock = socket.accept
			user = User::new( clSock, self )
			$stderr.puts "Accepted connection from #{user}"
			@reactor.register clSock, :read, &user.method(:handleIOEvent)
			user.addOutput( BANNER )
			user.prompt
			broadcastMsg( "[New connection: #{user}]" )
			@users << user

		end
	end


	### Process the specified input from the specified user
	def processInput( user, *inputStrings )
		inputStrings.each {|str|
			case str

			when %r{^/(\w+)\s*(.*)}
				handleCommand( user, $1, $2 )

			else
				user.addOutput( "You>> #{str}" )
				broadcastMsgFrom( user, str )
			end
		}

		user.prompt if user.connected?
	end


	### Handle the specified command from the specified user
	def handleCommand( user, command, args )
		case command

		when /quit/
			disconnectUser( user, 'Quit' )
			
		when /shutdown/
			shutdown()

		when /who/
			user.addOutput( self.wholist(user) )

		else
			user.addOutput("Unknown command '#{command}'")
		end
	end


	### Broadcast the specified message to all connected users
	def broadcastMsg( msg )
		@users.each {|cl|
			cl.addOutput( msg )
		}
	end


	### Broadcast the specified message from the specified user
	def broadcastMsgFrom( user, msg )
		userDesc = user.to_s

		@users.each {|cl|
			next if cl == user
			cl.addOutput( "#{userDesc}>> #{msg}" )
		}
	end


	### Disconnect the specified user
	def disconnectUser( user, msg='' )
		@users -= [ user ]
		@reactor.unregister( user.socket )
		user.disconnect( msg )
		broadcastMsg( "#{user.to_s} Disconnected." )
	end


	### Disconnect all connected users
	def disconnectAllUsers( msg )
		@users.each {|user|
			@reactor.unregister( user.socket )
			user.disconnect( msg )
		}
		@users.clear
	end


	### Shut the server down
	def shutdown( msg="Server shutdown" )
		$stderr.puts "Shutting down: #{msg}"
		@shuttingDown = true
		@reactor.clear
		begin
			@socket.shutdown
		rescue
		end
		disconnectAllUsers( msg )
		begin
			@socket.close
		rescue
		end
	end

	### Build and return a list of connected users for the specified user.
	def wholist( user )
		rval = "[Connected Users]\n" <<
			"  *#{user}*\n"
		@users.each {|u|
			next if u == user
			rval << "  #{u}\n"
		}

		return rval
	end

end # class Server
end # module Example

srv = Example::Server::new( *ARGV )
$stderr.puts "Chat server listening on #{srv.socket.addr[2]} port #{srv.socket.addr[1]}"
srv.eventLoop
$stderr.puts "Chat server finished."

