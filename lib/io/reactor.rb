#!/usr/bin/env ruby

class IO # :nodoc:

# An object-oriented multiplexing asynchronous IO mechanism for Ruby.
# 
# == Synopsis
# 
#    reactor = IO::Reactor.new
#    data_to_send = "some stuff to send"
#    
#    reader, writer = IO.pipe
#    
#    # Read from the reader end of the pipe until the writer finishes
#    reactor.register( reader, :read ) do |io,event|
#        if io.eof?
#            reactor.unregister( io )
#            io.close
#        else
#            puts io.read( 256 )
#        end
#    end
#    
#    # Write to the writer end of the pipe until there's no data left
#    reactor.register( writer, :write ) do |io,event|
#        bytes = io.write( data_to_send )
#        data_to_send.slice!( 0, bytes )
#    
#        if data_to_send.empty?
#            reactor.unregister( io )
#            io.close
#        end
#    end
#    
#    # Now pump the reactor until both sides are done
#    reactor.poll until reactor.empty?
#
# == Author
# 
# Michael Granger <ged@FaerieMUD.org>
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
# == Version
#
#  $Id$
# 
class Reactor

	### Class constants

	# SVN Revision
	SVNRev = %q$Rev: 388 $

	# SVN Id
	SVNId = %q$Id$

	# Package version
	VERSION = '1.0.0'

	# List of valid event types, in the order IO#select returns them
	VALID_EVENTS = [:read, :write, :error]
	VALID_EVENTS.freeze


	#################################################################
	###	I N S T A N C E   M E T H O D S
	#################################################################

	### Create and return a new IO reactor object.
	def initialize
		@handles		= Hash.new {|hsh,key|
			hsh[ key ] = {
				:events		=> [],
				:handler	=> nil,
				:args		=> [],
			}
		}
		@pending_events	= Hash.new {|hsh,key| hsh[ key ] = []}
	end


	######
	public
	######

	# The Hash of handles (instances of IO or its subclasses) associated with
	# the reactor. The keys are the IO objects, and the values are a Hash of
	# event/s => handler.
	attr_reader :handles

	# The Hash of unhandled events which occurred in the last call to #poll,
	# keyed by handle.
	attr_reader :pending_events
	alias_method :pendingEvents, :pending_events


	### Register the specified IO object with the reactor for events given as
	### <tt>args</tt>. The reactor will test the given <tt>io</tt> for the
	### events specified whenever #poll is called. See the #poll method for a
	### list of valid events. If no events are specified, only <tt>:error</tt>
	### events will be polled for.
	###
	### If a <tt>handler</tt> is specified, it will be called whenever the
	### <tt>io</tt> has any of the specified <tt>events</tt> occur to it. It
	### should take at least two parameters: the <tt>io</tt> and the event.
	###
	### If +args+ contains any objects except the Symbols '<tt>:read</tt>',
	### '<tt>:write</tt>', or '<tt>:error</tt>', and a +handler+ is specified,
	### they will be saved and passed to handler for each event.
	### 
	### Registering a handle will unregister any previously registered
	### event/handler+arguments pairs associated with the handle.
	def register( io, *args, &handler )
		events = VALID_EVENTS & args
		args -= events

		self.unregister( io )
		self.enable_events( io, *events )
		if handler
			self.set_handler( io, *args, &handler )
		else
			self.set_args( io, *args )
		end

		return self
	end
	alias_method :add, :register


	### Returns +true+ if the given +io+ handle is registered with the reactor.
	def registered?( io )
		return @handles.key?( io )
	end


	### Add the specified +events+ to the list that will be polled for on the
	### given +io+ handle.
	def enable_events( io, *events )
		@handles[ io ][:events] |= events
	end
	alias_method :enableEvents, :enable_events


	### Remove the specified +events+ from the list that will be polled for on
	### the given +io+ handle.
	def disable_events( io, *events )
		raise RuntimeError, "Cannot disable the :error event" if
			events.include?( :error )
		@handles[ io ][:events] -= events
	end
	alias_method :disableEvents, :disable_events


	### Returns +true+ if the specified +event+ is enabled for the given +io+.
	def event_enabled?( io, event )
		return false unless @handles.key?( io )
		return true if event == :error # Error is always enabled for all handles
		return @handles[ io ][ :events ].include?( event )
	end
	alias_method :has_event_enabled?, :event_enabled?
	

	### Set the handler for events on the given +io+ handle to the specified
	### +handler+. If any +args+ are present, they will be passed as an exploded
	### array to the handler for each event. Returns the previously-registered
	### handler, if any.
	def set_handler( io, *args, &handler )
		rval = @handles[ io ][:handler]
		@handles[ io ][:handler] = handler
		self.set_args( io, *args )
		return rval
	end
	alias_method :setHandler, :set_handler


	### Remove and return the handler for events on the given +io+ handle.
	def remove_handler( io )
		rval = @handles[ io ][:handler]
		@handles[ io ][:handler] = nil
		self.remove_args( io )
		return rval
	end
	alias_method :removeHandler, :remove_handler


	### Set the additional arguments to pass to the handler for the given +io+
	### handle on each event to the given +args+.
	def set_args( io, *args )
		rval = @handles[ io ][:args]
		@handles[ io ][:args] = args
		return rval
	end
	alias_method :setArgs, :set_args


	### Remove the arguments for the given handle to the given +args+.
	def remove_args( io )
		return @handles[ io ][:args].clear
	end
	alias_method :removeArgs, :remove_args


	### Remove the specified <tt>io</tt> from the receiver's list of registered
	### handles, if present. Returns the handle if it was registered, or
	### <tt>nil</tt> if it was not.
	def unregister( io )
		@pending_events.delete( io )
		@handles.delete( io )
	end
	alias_method :remove, :unregister


	### Clear all registered handles from the poll object. Returns the handles
	### that were cleared.
	def clear
		rv = @handles.keys

		@pending_events.clear
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
	### <tt>pending_events</tt> attribute.
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
		@pending_events.clear
		count = 0

		unless @handles.empty?
			timeout = nil if timeout < 0
			evented_handles = self.get_pending_events( timeout )

			# For each event of each io that had an event happen, call any
			# associated callback, or any provided block, or failing both of
			# those, add the event to the hash of unhandled pending events.
			evented_handles.each do |io,events|
				count += 1
				events.each do |ev|
					# Don't continue if the io was unregistered by an earlier handler
					break unless @handles.key?( io )
					
					args = @handles[ io ][:args]

					if @handles[ io ][:handler]
						@handles[ io ][:handler].call( io, ev, *args )
					elsif block_given?
						yield( io, ev, *args )
					else
						@pending_events[io].push( ev )
					end
				end
			end
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
	def get_pending_events( timeout )
		@handles.delete_if {|io,_| io.closed? }

		eventHandles = select( self.get_read_handles, self.get_write_handles,
			@handles.keys, timeout ) or return {}
		eventHash = Hash.new {|hsh,io| hsh[io] = []}

		# Fill in the hash with pending events of each type
		VALID_EVENTS.each_with_index do |event,i|
			eventHandles[i].each {|io| eventHash[io].push( event )}
		end
		return eventHash
	end
	alias_method :getPendingEvents, :get_pending_events


	### Return an Array of handles which have handlers for the <tt>:read</tt>
	### event.
	def get_read_handles
		@handles.
			find_all {|io,hsh| hsh[:events].include?( :read )}.
			collect {|io,_| io }
	end
	alias_method :getReadHandles, :get_read_handles


	### Return an Array of handles which have handlers for the <tt>:write</tt>
	### event.
	def get_write_handles
		@handles.
			find_all {|io,hsh| hsh[:events].include?( :write )}.
			collect {|io,_| io }
	end
	alias_method :getWriteHandles, :get_write_handles


end # class Reactor
end # class IO

