#!/usr/bin/ruby
# 
# An object-oriented poll() implementation for Ruby
# 
# == Synopsis
# 
#	require 'poll'
#	require 'socket'
#	
#	pollobj = Poll::new
#	
#	sock = TCPServer::new('localhost', 1138)
#	pollobj.register( sock, Poll::RDNORM ) {|sock,evmask|
#		case evmask
#		when Poll::RDNORM
#			clsock = sock.accept
#			pollobj.mask( clsock, Poll::RDNORM, clientHandler )
#	
#		when Poll::HUP|Poll::ERR|Poll::NVAL
#			pollobj.remove( io )
#			$stderr.puts "Server error: Shutting down"
#	
#		else
#			$stderr.puts "Unhandled event: #{evmask}"
#		end
#	}
#	
#	pollobj.poll( 0.25 ) until poll.handles.empty?
# 
# == Author
# 
# Michael Granger <ged@FaerieMUD.org>
# 
# Copyright (c) 2002 The FaerieMUD Consortium. All rights reserved.
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
#  $Id: poll.rb,v 1.2 2002/04/17 12:48:17 deveiant Exp $
# 

require 'delegate'
require 'poll.so'

### An object-oriented poll() implementation for Ruby
class Poll

	### A Fixnum derivative that does bitwise AND for ===.
	class EventMask < DelegateClass( Fixnum )

		### Create and return a new Poll::EventMask object with the specified
		### bitmask (an Integer).
		def initialize( mask )
			mask = mask.to_i
			@mask = mask
			super( mask )
		end

		### Returns true if the receiver bitwise ANDed with <tt>otherNum</tt> is
		### non-zero. This is useful for using bitmasks in case blocks.
		def ===( otherNum )
			( self & otherNum ).nonzero?
		end

		### Returns a new EventMask aftering ORing the reciever with the
		### specified value.
		def |( otherNum )
			otherNum = otherNum.to_i
			return EventMask::new( @mask | otherNum )
		end

		### Returns a new EventMask aftering ORing the reciever with the
		### specified value.
		def &( otherNum )
			otherNum = otherNum.to_i
			return EventMask::new( @mask & otherNum )
		end

		### Returns a new EventMask aftering ORing the reciever with the
		### specified value.
		def ^( otherNum )
			otherNum = otherNum.to_i
			return EventMask::new( @mask ^ otherNum )
		end
	end # class Poll::EventMask


	### Class constants
	Version = /([\d\.]+)/.match( %q$Revision: 1.2 $ )[1]
	Rcsid = %q$Id: poll.rb,v 1.2 2002/04/17 12:48:17 deveiant Exp $

	### Create and return new poll object.
	def initialize
		@masks		= {}
		@events		= Hash::new( 0 )
		@callbacks	= {}
	end


	######
	public
	######

	### Register the specified IO object with the specified
	### <tt>eventMask</tt>. If the optional <tt>callback</tt> parameter (a
	### Method or Proc object) or a block is given, it will be called with
	### <tt>io</tt> and the mask of the event/s whenever #poll generates any
	### events for <tt>io</tt>. If the <tt>callback</tt> parameter is given, the
	### <tt>block</tt> is ignored.
	def register( io, eventMask, callback=nil, &block )
		
		raise TypeError, "No implicit conversion to IO from #{io.type.name}" unless
			io.kind_of? IO

		# Clear any old events for this handle
		@events.delete( io )

		# Set the callback, if given, else just make sure its clear
		if callback || block
			@callbacks[ io ] = callback || block
		else
			@callbacks.delete( io )
		end

		# Set the mask
		eventMask = eventMask.to_i
		@masks[ io ] = EventMask::new( eventMask )
	end
	alias :add :register


	### Remove the specified <tt>io</tt> from the receiver's list of registered
	### handles, if present. Returns the handle if it was registered, or
	### <tt>nil</tt> if it was not.
	def unregister( io )
		@events.delete( io )
		@callbacks.delete( io )
		@masks.delete( io )
	end
	alias :remove :unregister


	### Returns true if the specified <tt>io</tt> is registered with the poll
	### object.
	def registered?( io )
		return @masks.has_key?( io )
	end


	### Clear all registered handles from the poll object. Returns the handles
	### that were cleared.
	def clear
		rv = @masks.keys

		@events.clear
		@callbacks.clear
		@masks.clear

		return rv
	end

	
	### Get the EventMask for the specified <tt>io</tt>.
	def mask( io )
		raise ArgumentError, "Handle #{io.inspect} is not registered" unless
			@masks.has_key?( io )

		return @masks[ io ]
	end


	### Add (butwise OR) the specified <tt>eventMask</tt> to the mask for the
	### specified <tt>io</tt>. Returns the new mask.
	def addMask( io, eventMask )
		raise ArgumentError, "Handle #{io.inspect} is not registered" unless
			@masks.has_key?( io )

		@masks[ io ] |= eventMask.to_i
	end


	### Remove (bitwise XOR) the specified <tt>eventMask</tt> from the mask for
	### the specified <tt>io</tt>. Returns the new mask.
	def removeMask( io, eventMask )
		raise ArgumentError, "Handle #{io.inspect} is not registered" unless
			@masks.has_key?( io )

		@masks[ io ] ^= eventMask.to_i
	end


	### Returns <tt>true</tt> if the specified <tt>io</tt> has a callback
	### associated with it.
	def hasCallback?( io )
		@callbacks.has_key?( io )
	end
	alias :has_callback? :hasCallback?


	### Reset the per-handle callback associated with the specified <tt>io</tt>
	### to the specified <tt>callback</tt> (a Proc or Method object) or
	### <tt>block</tt>, if given, or to nil if not specified. Returns the old
	### callback.
	def setCallback( io, callback=nil, &block )
		raise ArgumentError, "Handle #{io.inspect} is not registered" unless
			@masks.has_key?( io )

		rv = @callback[ io ]

		if callback || block
			@callback[ io ] = callback || block
		else
			@callback.delete( io )
		end

		return rv
	end


	### Call the system-level poll function with the handles registered to the
	### receiver. Any callbacks specified when the handles were registered are
	### run for those handles with events. If a block is given, it will be
	### invoked once for each handle which doesn't have an explicit
	### handler. This method returns the number of handles which had events
	### occur.
	def poll( timeout=-1 )
		raise TypeError, "Timeout must be Numeric, not a #{timeout.type.name}" unless
			timeout.kind_of? Numeric
		timeout = timeout.to_f

		@events.clear

		unless @masks.empty?
			@events = _poll( @masks.to_a, timeout*1000 )

			# For each io that had an event happen, call any callback associated
			# with it, or failing that, any provided block
			@events.each {|io,evmask|
				if @callbacks.has_key?( io )
					@callbacks[ io ].call( io, EventMask::new(evmask) )
				elsif block_given?
					yield( io, EventMask::new(evmask) )
				end
			}
		end

		@events.default = EventMask::new( 0 )
		return @events.length
	end


	### Fetch an Array of handles which had the events specified by
	### <tt>eventMask</tt> happen to them in the last call to #poll. If
	### <tt>eventMask</tt> is <tt>nil</tt>, an Array of all handles
	### with pending events is returned.
	def events( eventMask=nil )
		if eventMask
			eventMask = eventMask.to_i
			@events.find_all {|io,evmask| (evmask & eventMask).nonzero? }.collect {|io,evmask| io}
		else
			@events.keys
		end
	end


	### Fetch an Array of handles that are masked to receive the specified
	### <tt>eventMask</tt>. If <tt>eventMask</tt> is nil, an Array of all
	### registered handles is returned.
	def handles( eventMask=nil )
		if eventMask
			eventMask = eventMask.to_i
			@masks.find_all {|io,evmask| (evmask & eventMask).nonzero? }.collect {|io,evmask| io}
		else
			@masks.keys
		end
	end


	### Return a human-readable string describing the poll object.
	def inspect
		"<Poll: handles: %s, %d pending events>" % [@masks.inspect, @events.length]
	end

end # class Poll

