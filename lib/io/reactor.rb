#!/usr/bin/ruby
# 
# An object-oriented implementation of poll(2) for Ruby
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
#  $Id: reactor.rb,v 1.6 2002/07/18 15:40:39 deveiant Exp $
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

		### Returns a new EventMask after ORing the receiver with the specified
		### value.
		def |( otherNum )
			otherNum = otherNum.to_i
			return EventMask::new( @mask | otherNum )
		end

		### Returns a new EventMask after ANDing the receiver with the specified
		### value.
		def &( otherNum )
			otherNum = otherNum.to_i
			return EventMask::new( @mask & otherNum )
		end

		### Returns a new EventMask after XORing the receiver with the specified
		### value.
		def ^( otherNum )
			otherNum = otherNum.to_i
			return EventMask::new( @mask ^ otherNum )
		end
	end # class Poll::EventMask


	### Class constants
	Version = /([\d\.]+)/.match( %q$Revision: 1.6 $ )[1]
	Rcsid = %q$Id: reactor.rb,v 1.6 2002/07/18 15:40:39 deveiant Exp $

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
	### Method or Proc object) or a <tt>block</tt> is given, it will be called
	### with <tt>io</tt> and the mask of the event/s whenever #poll generates
	### any events for <tt>io</tt>. If the <tt>callback</tt> parameter is given,
	### the <tt>block</tt> is ignored. The following event masks can be set in
	### the <tt>eventMask</tt>:
	### [<tt>Poll::IN</tt>]
	###   Data other than high-priority data may be read without blocking.
	### [<tt>Poll::PRI</tt>]
	###   High-priority data may be received without blocking.
	### [<tt>Poll::OUT</tt>]
	###   Normal data (priority band equals 0) may be written without blocking.
	###
	### The following masks are ignored in the <tt>eventMask</tt>, as they are
	### always implicitly set, but they may be specified in the handler
	### <tt>callback</tt> or <tt>block</tt> to trap the conditions they
	### represent:
	### [<tt>Poll::ERR</tt>]
	###   An error has occurred on the device.
	### [<tt>Poll::HUP</tt>]
	###   The device has been disconnected. This event and Poll::OUT are
	###   mutually exclusive; a device can never be writable once a hangup has
	###   occurred. However, this event and Poll::IN, Poll::RDNORM,
	###   Poll::RDBAND, or Poll::PRI are not mutually exclusive.
	### [<tt>Poll::NVAL</tt>]
	###   The <tt>io</tt> object specified is invalid -- it has been closed, has
	###   a bad file descriptor, etc.
	###
	### If your operating system defines them, these masks are also available:
	### [<tt>Poll::RDNORM</tt>]
	###   Normal data (priority band equals 0) may be read without blocking.
	### [<tt>Poll::RDBAND</tt>]
	###   Data from a non-zero priority band may be read without blocking.
	### [<tt>Poll::WRNORM</tt>]
	###   Same as Poll::OUT.
	### [<tt>Poll::WRBAND</tt>]
	###   Priority data (priority band greater than 0) may be written.
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
	### invoked once for each handle which doesn't have an explicit handler. The
	### <tt>timeout</tt> argument is the number of floating-point seconds to
	### wait for an event before returning; negative timeout values will cause
	### #poll to block until there is at least one event to report. This method
	### returns the number of handles on which one or more events occurred.
	def poll( timeout=-1 ) # :yields: io, eventMask
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

