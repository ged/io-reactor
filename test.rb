#!/usr/bin/ruby
# = test.rb
#
#	Test suite for Ruby-Poll
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
#  $Id: test.rb,v 1.7 2003/07/21 06:55:26 deveiant Exp $
# 
#

$:.unshift "lib", "tests"

require 'test/unit'
require 'io/reactor'
require 'socket'

TMPFILE = "testfile.#{$$}"
HOST	= 'localhost'
PORT	= 5656

$stderr.sync = $stdout.sync = true

### Reactor test case
class IOReactorTestCase < Test::Unit::TestCase

	# Setup method
	def setup
		@reactor = IO::Reactor::new
		@tmpfile = File::open( TMPFILE, "w" )
		File::unlink TMPFILE
		@sock = TCPServer::new( HOST, PORT )
	end
	alias_method :set_up, :setup

	# Teardown method
	def teardown
		@reactor = nil
		@tmpfile.close
		@sock.close
	end
	alias_method :tear_down, :teardown


	# Test to make sure require worked
	def test_00Requires
		assert_instance_of Class, IO::Reactor
		assert_instance_of IO::Reactor, @reactor
	end


	# Test set and reset with an IO
	def test_03RegisterIO
		assert_nothing_raised { @reactor.register $stdout, :write }
		assert_nothing_raised { @reactor.add $stdout, :write }
		assert @reactor.registered?( $stdout )
		assert_equal [:write], @reactor.handles[ $stdout ][:events]
	end


	# Test set and reset with a File
	def test_04RegisterFilehandle
		assert_nothing_raised { @reactor.register @tmpfile, :write }
		assert_nothing_raised { @reactor.add @tmpfile, :write }
		assert @reactor.registered?( @tmpfile )
		assert_equal [:write], @reactor.handles[ @tmpfile ][:events]
	end


	# Test set and reset with a File
	def test_05RegisterSocket
		assert_nothing_raised { @reactor.register @sock, :read, :write }
		assert_nothing_raised { @reactor.add @sock, :read }
		assert @reactor.registered?( @sock )
		assert_equal [:read], @reactor.handles[ @sock ][:events]
	end


	# Test registration with a callback as an inline block
	def test_06RegisterWithBlock
		assert_nothing_raised {
			@reactor.register($stdout, :write) {|io,eventMask|
				$stderr.puts "Got an output event for STDOUT"
			}
		}
		assert @reactor.handles.key?( $stdout ),
			"handles hash doesn't contain $stdout"
		assert_equal [:write], @reactor.handles[ $stdout ][:events]
	end


	# Test registration with a Proc argument
	def test_07RegisterWithProc
		handlerProc = Proc::new {|io,eventMask|
			$stderr.puts "Got an output event for STDOUT"
		}
		assert_nothing_raised {
			@reactor.register( $stdout, :write, &handlerProc )
		}
		assert @reactor.handles.key?( $stdout ),
			"handles hash doesn't contain $stdout"
	end


	# Test registration with a Method argument
	def test_08RegisterWithMethod
		assert_nothing_raised {
			@reactor.register $stdout, :write, &$stderr.method( :puts )
		}
		assert @reactor.handles.key?( $stdout ),
			"handles hash doesn't contain $stdout"
	end


	# Test the clear method
	def test_09Clear
		# Make sure it's empty
		assert_nothing_raised {
			@reactor.clear
		}

		# Test it with one registered
		assert_nothing_raised {
			@reactor.register $stdout, :write, &$stdout.method( :puts )
			@reactor.clear
		}
		assert ! @reactor.registered?( $stdout ),
			"$stdout still registed with the poll handle after clear"
		assert_equal 0, @reactor.handles.length
	end


	# Test the #poll method
	def test_11Poll
		rv = nil

		@reactor.register $stdout, :write
		@reactor.register @tmpfile, :write

		assert_nothing_raised { rv = @reactor.poll(0.1) }
		assert_equal 2, rv

		assert_nothing_raised { @reactor.pendingEvents.keys.include?($stdout) }
		assert_nothing_raised { @reactor.pendingEvents.keys.include?(@tmpfile) }
	end


	# Test #poll with a block default handler
	def test_12PollWithBlock
		rv = nil

		@reactor.register $stdout, :write
		@reactor.register @tmpfile, :write

		assert_nothing_raised {
			rv = @reactor.poll( 15 ) {|io,event|
				$stderr.puts "Default handler got #{io.inspect} with mask #{event}" if $VERBOSE
			}
		}
	end

end # class PollTestCase








