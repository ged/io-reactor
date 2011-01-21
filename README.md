# io_reactor

* http://deveiate.org/projects/IO-Reactor

## Description

An implementation of the Reactor design pattern for multiplexed asynchronous single-thread IO.

This module is a pure-Ruby implementation of an asynchronous multiplexed IO Reactor which is based on the Reactor design pattern found in _Pattern-Oriented Software Architecture, Volume 2: Patterns for Concurrent and Networked Objects_. It allows a single thread to demultiplex and dispatch events from one or more IO objects to the appropriate handler.

### Trivial Example

This is a very trivial example -- in most circumstances you'd only use a Reactor when you're trying to manage reading and writing on more than a single IO object.

	require 'io/reactor'
	
	reactor = IO::Reactor.new
	data_to_send = "some stuff to send"
	
	reader, writer = IO.pipe
	
	# Read from the reader end of the pipe until the writer finishes
	reactor.register( reader, :read ) do |io,event|
	    if io.eof?
	        reactor.unregister( io )
	        io.close
	    else
	        puts io.read( 256 )
	    end
	end
	
	# Write to the writer end of the pipe until there's no data left
	reactor.register( writer, :write ) do |io,event|
	    bytes = io.write( data_to_send )
	    data_to_send.slice!( 0, bytes )
	
	    if data_to_send.empty?
	        reactor.unregister( io )
	        io.close
	    end
	end
	
	# Now pump the reactor until both sides are done
	puts "Starting IO"
	reactor.poll until reactor.empty?
	puts "done, exiting."

See the examples/ directory for some working, more full-featured examples.


## Installation

    gem install io-reactor


## Contributing

You can check out the current development source with Mercurial like so:

    hg clone http://repo.deveiate.org/IO-Reactor

Or if you prefer Git, via its Github mirror:

    https://github.com/ged/io-reactor

After checking out the source, run:

	$ rake newb

This task will install any missing dependencies, run the tests/specs, and generate the API documentation.


## License

Copyright (c) 2011, Michael Granger
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice,
  this list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

* Neither the name of the author/s, nor the names of the project's
  contributors may be used to endorse or promote products derived from this
  software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
