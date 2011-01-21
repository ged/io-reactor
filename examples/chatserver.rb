#!/usr/bin/ruby

require 'io/reactor'
require 'socket'

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
# == License
#
# Copyright (c) 2002-2011, The FaerieMUD Consortium
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
# * Redistributions of source code must retain the above copyright notice,
#   this list of conditions and the following disclaimer.
# 
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# 
# * Neither the name of the author/s, nor the names of the project's
#   contributors may be used to endorse or promote products derived from this
#   software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# == Version
#
#  $Id$
#
module Example; end

### Chatserver user class -- part of the chatserver example.
class Example::User

	# The "Maximum Transmissable Unit" when buffering
	MTU	 = 4096

	# Character constants for readability
	CR   = "\015"
	LF   = "\012"
	EOL  = CR + LF

	# The prompt to display when waiting for input
	PROMPT = 'chat> '


	### Create and return a user object which will use the specified
	### +socket+ and +server+.
	def initialize( socket, server )
		@socket    = socket
		@server    = server
		@obuffer   = ''
		@ibuffer   = ''
		@peer_host = @socket.peeraddr[2]
		@peer_port = @socket.peeraddr[1]
		@connected = true
	end


	######
	public
	######

	# Object attribute
	attr_reader :socket, :server, :ibuffer, :obuffer


	### Returns true if the user is still connected
	def connected?
		return self.connected ? true : false
	end


	### Return a stringified version of the user
	def to_s
		return "%s:%d" % [ self.peer_host, self.peer_port ]
	end


	### Add the specified string to the user's output buffer and turn on
	### output events.
	def add_output( string )
		self.obuffer << string.chomp << EOL
		self.server.reactor.enable_events( self.socket, :write )
	end
	alias :<< :add_output


	### Write as much of the output buffer to the socket as possible, and return
	### the number of bytes remaining to be sent.
	def write_output
		bytes = self.socket.syswrite( self.obuffer )
		self.obuffer.slice!( 0, bytes ) if bytes.nonzero?

		return self.obuffer.length
	end


	### Write a prompt to the user
	def prompt
		self.obuffer << PROMPT
		self.server.reactor.enable_events( self.socket, :write ) # FIXME: demeter
	end


	### Read at most MTU bytes from the socket and append them to the input
	### buffer. Split off any complete lines (one that end with EOL) and return
	### them as an Array of Strings.
	def read_input
		rary = []

		self.ibuffer << self.socket.sysread( MTU )

		# Extract any complete input lines from the input buffer by
		# slicing off chunks delimited by EOL
		while (( pos = self.ibuffer.index(EOL) ))
			rary << self.ibuffer.slice!( 0, pos )
			self.ibuffer.lstrip!
		end

		return rary

	rescue EOFError, SystemCallError
		# If there was a socket error, disconnect
		@server.disconnect_user( self )
		return []
	end


	### Handle poll events on the socket
	def handle_io_event( io, event )
		case event

		when :error
			@server.disconnect_user( self )

		when :read
			input = self.read_input
			@server.process_input( self, *input ) unless input.empty?

		when :write
			bytes_left = self.write_output
			@server.reactor.disable_events( @socket, :write ) if bytes_left.zero?

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

		self.write_output
		@socket.close
	end

end # class Example::User


### Example chatserver class -- an extremely crude and simple chat server that
### demonstrates how to use Poll to do multiplexing IO in a single thread.
class Example::Server

	BANNER = <<-EOF
	[[ IO::Reactor Example Chatserver ]]
	Commands: '/quit' to quit, '/shutdown' to shut the server down
	EOF

	### Instantiate and return a chatserver on the specified host and port
	def initialize( host="0.0.0.0", port=1138, interval=0.20 )
		@listener       = TCPServer.new( host, port )
		@users          = []
		@reactor        = IO::Reactor.new
		@poll_interval  = interval
		@shutting_down  = false

		# Register for read events on the listener socket, and call the
		# 'handle_poll_event' method when a connection comes in
		@reactor.register( @listener, :read, &self.method(:handle_poll_event) )
	end


	######
	public
	######

	# Server attributes
	attr_reader :reactor, :users, :socket


	### Start the server
	def start
		$stderr.puts "Chat server listening on #{srv.socket.addr[2]} port #{srv.socket.addr[1]}"
		self.event_loop
		$stderr.puts "Chat server finished."
	end


	### Returns +true+ if the server should shut down
	def shutting_down?
		return @shutting_down
	end


	### Main server loop
	def event_loop
		trap( "INT" ) { self.shutdown("Server caught SIGINT") }
		trap( "TERM" ) { self.shutdown("Server caught SIGTERM") }
		trap( "HUP" ) { self.disconnect_all_users(">>> Server reset <<<") }

		@reactor.poll( @poll_interval ) until @shutting_down

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
	def handle_poll_event( socket, event )
		$stderr.puts "Got #{event.inspect} event for #{socket.inspect}"

		case event
		when :error
			$stderr.puts "Socket error on the listener socket."
			self.shutdown

		when :read
			client_sock = socket.accept
			user        = Example::User.new( client_sock, self )

			$stderr.puts "Accepted connection from #{user}"
			@reactor.register( client_sock, :read, &user.method(:handle_io_event) )
			user.add_output( BANNER )
			user.prompt

			self.broadcast_msg( "[New connection: #{user}]" )
			@users << user

		end
	end


	### Process the specified input from the specified user
	def process_input( user, *input_strings )
		input_strings.each do |str|
			case str

			when %r{^/(\w+)\s*(.*)}
				self.handle_command( user, $1, $2 )

			else
				user.add_output( "You>> #{str}" )
				self.broadcast_msg_from( user, str )
			end
		end

		user.prompt if user.connected?
	end


	### Handle the given +command+ from the specified +user+
	def handle_command( user, command, args )
		case command

		when /quit/
			self.disconnect_user( user, 'Quit' )

		when /shutdown/
			self.shutdown

		when /who/
			user.add_output( self.wholist(user) )

		else
			user.add_output( "Unknown command '#{command}'" )
		end
	end


	### Broadcast the specified message to all connected users
	def broadcast_msg( msg )
		@users.each do |cl|
			cl.add_output( msg )
		end
	end


	### Broadcast the specified message from the specified user
	def broadcast_msg_from( user, msg )
		userDesc = user.to_s

		@users.each do |cl|
			next if cl == user
			cl.add_output( "#{userDesc}>> #{msg}" )
		end
	end


	### Disconnect the specified user after sending them the specified +msg+.
	def disconnect_user( user, msg='' )
		@users -= [ user ]
		@reactor.unregister( user.socket )
		user.disconnect( msg )

		self.broadcast_msg( "#{user.to_s} Disconnected." )
	end


	### Disconnect all connected users after sending them the specified +msg+.
	def disconnect_all_users( msg )
		@users.each do |user|
			@reactor.unregister( user.socket )
			user.disconnect( msg )
		end
		@users.clear
	end


	### Shut the server down
	def shutdown( msg="Server shutdown" )
		$stderr.puts "Shutting down: #{msg}"

		@shutting_down = true
		@reactor.clear

		@listener.shutdown rescue nil
		self.disconnect_all_users( msg )
		@listener.close rescue nil
	end


	### Build and return a list of connected users for the specified +user+.
	def wholist( user )
		rval = "[Connected Users]\n" <<
		       "  *#{user}*\n"

		@users.each do |u|
			next if u == user
			rval << "  #{u}\n"
		end

		return rval
	end

end # class Example::Server


if __FILE__ == $0
	Example::Server.new( *ARGV ).start
end

