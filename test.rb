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
#  $Id: test.rb,v 1.9 2003/08/07 02:19:38 deveiant Exp $
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
		File::unlink TMPFILE unless File::ALT_SEPARATOR
		@sock = TCPServer::new( HOST, PORT )
	end
	alias_method :set_up, :setup

	# Teardown method
	def teardown
		@reactor = nil
		@tmpfile.close
		@sock.close
		File::unlink( TMPFILE ) if File::exists?( TMPFILE )
	end
	alias_method :tear_down, :teardown


	# Test to make sure require worked
	def test_00_Requires
		assert_instance_of Class, IO::Reactor
		assert_instance_of IO::Reactor, @reactor
	end


	# Test set and reset with an IO
	def test_10_RegisterIO
		assert_nothing_raised { @reactor.register $stdout, :write }
		assert_nothing_raised { @reactor.add $stdout, :write }
		assert @reactor.registered?( $stdout )
		assert_equal [:write], @reactor.handles[ $stdout ][:events]
	end


	# Test set and reset with a File
	def test_11_RegisterFilehandle
		assert_nothing_raised { @reactor.register @tmpfile, :write }
		assert_nothing_raised { @reactor.add @tmpfile, :write }
		assert @reactor.registered?( @tmpfile )
		assert_equal [:write], @reactor.handles[ @tmpfile ][:events]
	end


	# Test set and reset with a File
	def test_12_RegisterSocket
		assert_nothing_raised { @reactor.register @sock, :read, :write }
		assert_nothing_raised { @reactor.add @sock, :read }
		assert @reactor.registered?( @sock )
		assert_equal [:read], @reactor.handles[ @sock ][:events]
	end


	# Test registration with a callback as an inline block
	def test_20_RegisterWithBlock
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
	def test_21_RegisterWithProc
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
	def test_22_RegisterWithMethod
		assert_nothing_raised {
			@reactor.register $stdout, :write, &$stderr.method( :puts )
		}
		assert @reactor.handles.key?( $stdout ),
			"handles hash doesn't contain $stdout"
	end


	# Test registering with an argument
	def test_23_RegisterWithArgs
		assert_nothing_raised {
			@reactor.register $stdout, :write, "foo", &$stderr.method( :puts )
		}
		assert @reactor.handles.key?( $stdout ),
			"handles hash doesn't contain $stdout"
		assert_equal ["foo"], @reactor.handles[$stdout][:args]
	end


	# Test the clear method
	def test_30_Clear
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
	def test_40_Poll
		rv = nil

		@reactor.register $stdout, :write
		@reactor.register @tmpfile, :write

		assert_nothing_raised { rv = @reactor.poll(0.1) }
		assert_equal 2, rv

		assert_nothing_raised { @reactor.pendingEvents.keys.include?($stdout) }
		assert_nothing_raised { @reactor.pendingEvents.keys.include?(@tmpfile) }
	end


	# Test #poll with a block default handler
	def test_41_PollWithBlock
		rv = nil

		@reactor.register $stdout, :write
		@reactor.register @tmpfile, :write

		assert_nothing_raised {
			rv = @reactor.poll( 15 ) {|io,event|
				$stderr.puts "Default handler got #{io.inspect} with mask #{event}" if $VERBOSE
			}
		}
	end

	# Test polling with an argument
	def test_42_PollWithArgs
		setval = nil
		testAry = %w{foo bar baz}
		
		@reactor.register( $stdout, :write, *testAry )
		assert_equal testAry, @reactor.handles[$stdout][:args]

		assert_nothing_raised {
			@reactor.poll( 15 ) {|io,ev,*args|
				setval = args
			}
		}

		assert_equal testAry, setval
	end


end # class PollTestCase








