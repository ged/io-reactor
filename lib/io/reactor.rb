#!/usr/bin/ruby
# 
# An object-oriented multiplexing asynchronous IO mechanism for Ruby.
# 
# == Synopsis
# 
#	require 'io/reactor'
#	require 'socket'
#	
#	reactorobj = IO::Reactor::new
#	
#	sock = TCPServer::new('localhost', 1138)
#	reactorobj.register( sock, :read ) {|sock,event|
#		case event
#		when :read
#			clsock = sock.accept
#			reactorobj.register( clsock, :read, :write ) {|sock,event|
#				clientHandler( sock, event )
#			}
#	
#		when :error
#			reactorobj.remove( io )
#			$stderr.puts "Server error: Shutting down"
#	
#		else
#			$stderr.puts "Unhandled event: #{event}"
#		end
#	}
#	
#	Thread::new { reactorobj.poll( 0 ) until reactorobj.handles.empty? }
# 
# == Author
# 
# Michael Granger <ged@FaerieMUD.org>
# 
# Copyright (c) 2002, 2003 The FaerieMUD Consortium. All rights reserved.
# 
# This module is free software. You may use, modify, and/or redistribute this
# software under the same terms as Ruby itself.
# 
# This library is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.
#
# == Version
#
#  $Id: reactor.rb,v 1.12 2003/07/22 16:31:17 deveiant Exp $
# 

require 'delegate'
require 'rbconfig'

class IO

### An object-oriented multiplexing asynchronous IO reactor class.
class Reactor

	### Class constants
	Version = /([\d\.]+)/.match( %q{$Revision: 1.12 $} )[1]
	Rcsid = %q$Id: reactor.rb,v 1.12 2003/07/22 16:31:17 deveiant Exp $

	ValidEvents = [:read, :write, :error]

	### Create and return a new IO reactor object.
	def initialize
		@handles		= Hash::new {|hsh,key|
			hsh[ key ] = {
				:events		=> [],
				:handler	=> nil,
			}
		}
		@pendingEvents	= Hash::new {|hsh,key| hsh[ key ] = []}
	end


	######
	public
	######

	# The Hash of handles (instances of IO or its subclasses) associated with
	# the reactor. The keys are the IO objects, and the values are a Hash of
	# event/s => handler.
	attr_reader :handles

	# The Hash of unhandled events which occurred in the last event loop, keyed
	# by handle.
	attr_reader :pendingEvents


	### Register the specified IO object with the reactor for the given
	### <tt>events</tt>. The reactor will test the given <tt>io</tt> for the
	### events specified whenever #poll is called. See the #poll method for a
	### list of valid events. If no <tt>events</tt> are specified, only
	### <tt>:error</tt> events will be polled for.
	###
	### If a <tt>handler</tt> is specified, it will be called whenever the
	### <tt>io</tt> has any of the specified <tt>events</tt> occur to it. It
	### should take two parameters: the <tt>io</tt> and the <tt>event</tt>.
	###
	### Registering a handle will unregister any previously registered
	### event/handler pairs associated with the handle.
	def register( io, *events, &handler )
		self.unregister( io )
		self.enableEvents( io, *events )
		self.setHandler( io, &handler ) if handler

		return self
	end
	alias_method :add, :register


	### Add the specified +events+ to the list that will be polled for on the
	### given +io+ handle.
	def enableEvents( io, *events )
		@handles[ io ][:events] |= events
	end


	### Remove the specified +events+ from the list that will be polled for on
	### the given +io+ handle.
	def disableEvents( io, *events )
		raise RuntimeError, "Cannot disable the :error event" if
			events.include?( :error )
		@handles[ io ][:events] -= events
	end


	### Set the handler for events on the given +io+ handle to the specified
	### +handler+. Returns the previously-registered handler, if any.
	def setHandler( io, &handler )
		rval = @handles[ io ][:handler]
		@handles[ io ][:handler] = handler
		return rval
	end


	### Remove and return the handler for events on the given +io+ handle.
	def removeHandler( io )
		rval = @handles[ io ][:handler]
		@handles[ io ][:handler] = nil
		return rval
	end


	### Remove the specified <tt>io</tt> from the receiver's list of registered
	### handles, if present. Returns the handle if it was registered, or
	### <tt>nil</tt> if it was not.
	def unregister( io )
		@pendingEvents.delete( io )
		@handles.delete( io )
	end
	alias_method :remove, :unregister


	### Returns true if the specified <tt>io</tt> is registered with the poll
	### object.
	def registered?( io )
		return @handles.has_key?( io )
	end


	### Clear all registered handles from the poll object. Returns the handles
	### that were cleared.
	def clear
		rv = @handles.keys

		@pendingEvents.clear
		@handles.clear

		return rv
	end


	
	### Poll the handles registered to the reactor for pending events. The
	### following event types are defined:
	###
	### [<tt>:read</tt>]
	###   Data may be read from the handle without blocking.
	### [<tt>:write</tt>]
	###   Data may be written to the handle without blocking.
	### [<tt>:error</tt>]
	###   An error has occurred on the handle. This event type is always
	###   enabled, regardless of whether or not it is passed as one of the
	###   <tt>events</tt>.
	###
	### Any handlers specified when the handles were registered are run for
	### those handles with events. If a block is given, it will be invoked once
	### for each handle which doesn't have an explicit handler. If no block is
	### given, events without explicit handlers are inserted into the reactor's
	### #pendingEvents.
	###
	### The <tt>timeout</tt> argument is the number of floating-point seconds to
	### wait for an event before returning (ie., fourth argument to the
	### underlying <tt>select()</tt> call); negative timeout values will cause
	### #poll to block until there is at least one event to report.
	###
	### This method returns the number of handles on which one or more events
	### occurred.
	def poll( timeout=-1 ) # :yields: io, eventMask
		timeout = timeout.to_f
		@pendingEvents.clear
		count = 0

		unless @handles.empty?
			timeout = nil if timeout < 0
			eventedHandles = self.getPendingEvents( timeout )

			# For each event of each io that had an event happen, call any
			# associated callback, or any provided block, or failing both of
			# those, add the event to the hash of unhandled pending events.
			eventedHandles.each {|io,events|
				count += 1
				events.each {|ev|
					if @handles[ io ][:handler]
						@handles[ io ][:handler].call( io, ev )
					elsif block_given?
						yield( io, ev )
					else
						@pendingEvents[io].push( ev )
					end
				}
			}
		end

		return count
	end


	### Returns <tt>true</tt> if no handles are associated with the receiver.
	def empty?
		@handles.empty?
	end


	#########
	protected
	#########

	### Select on the registered handles, returning a Hash of handles => events
	### for handles which had events occur.
	def getPendingEvents( timeout )
		eventHandles = IO::select( self.getReadHandles, self.getWriteHandles,
			@handles.keys, timeout ) or return {}
		eventHash = Hash::new {|hsh,io| hsh[io] = []}

		# Fill in the hash with pending events of each type
		[:read, :write, :error].each_with_index {|event,i|
			eventHandles[i].each {|io| eventHash[io].push( event )}
		}
		return eventHash
	end


	### Return an Array of handles which have handlers for the <tt>:read</tt>
	### event.
	def getReadHandles
		@handles.
			find_all {|io,hsh| hsh[:events].include?( :read )}.
			collect {|io,hsh| io}
	end


	### Return an Array of handles which have handlers for the <tt>:write</tt>
	### event.
	def getWriteHandles
		@handles.
			find_all {|io,hsh| hsh[:events].include?( :write )}.
			collect {|io,hsh| io}
	end


end # class Reactor
end # class IO

