#!/usr/bin/ruby
# = test.rb
#
#	Test suite for Ruby-Poll
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
#  $Id: test.rb,v 1.6 2003/04/21 04:37:01 deveiant Exp $
# 
#

$:.unshift "lib", "tests"

require 'test/unit'
require 'poll'
require 'socket'

TMPFILE = "testfile.#{$$}"
HOST	= 'localhost'
PORT	= 5656

### Poll test case
class PollTestCase < Test::Unit::TestCase

	# Setup method
	def setup
		@poll = Poll::new
		@tmpfile = File::open( TMPFILE, "w" )
		File::unlink TMPFILE
		@sock = TCPServer::new( HOST, PORT )
	end
	alias_method :set_up, :setup

	# Teardown method
	def teardown
		@poll = nil
		@tmpfile.close
		@sock.close
	end
	alias_method :tear_down, :teardown


	# Test to make sure require worked
	def test_00Requires
		assert_instance_of Class, Poll
		assert_instance_of Poll, @poll
	end


	# Test for the presence of constants
	def test_01Constants
		%w{POLLIN POLLOUT POLLPRI POLLERR POLLHUP POLLNVAL IN OUT PRI ERR HUP NVAL}.each {|sym|
			assert Poll.const_defined?( sym.intern ), "Poll doesn't define the #{sym} constant."
		}
	end


	# Test the #mask method with various arguments
	def test_02RegisterTypeChecking
		assert_raises( TypeError ) { @poll.register "a test string", Poll::OUT }
		assert_raises( TypeError ) { @poll.add "a test string", Poll::OUT }
	end


	# Test set and reset with an IO
	def test_03RegisterIO
		assert_nothing_raised { @poll.register $stdout, Poll::OUT }
		assert_nothing_raised { @poll.add $stdout, Poll::OUT|Poll::PRI }
		assert @poll.registered?( $stdout )
		assert_equal Poll::OUT|Poll::PRI, @poll.mask( $stdout )
	end


	# Test set and reset with a File
	def test_04RegisterFilehandle
		assert_nothing_raised { @poll.register @tmpfile, Poll::PRI|Poll::OUT }
		assert_nothing_raised { @poll.add @tmpfile, Poll::PRI }
		assert @poll.registered?( @tmpfile )
		assert_equal Poll::PRI, @poll.mask( @tmpfile )
	end


	# Test set and reset with a File
	def test_05RegisterSocket
		assert_nothing_raised { @poll.register @sock, Poll::PRI|Poll::OUT|Poll::IN }
		assert_nothing_raised { @poll.add @sock, Poll::PRI|Poll::IN }
		assert @poll.registered?( @sock )
		assert_equal Poll::PRI|Poll::IN, @poll.mask( @sock )
	end


	# Test registration with a callback as an inline block
	def test_06RegisterWithBlock
		assert_nothing_raised {
			@poll.register($stdout, Poll::OUT) {|io,eventMask|
				$stderr.puts "Got an output event for STDOUT"
			}
		}
		assert @poll.has_callback?( $stdout ), "has_callback? returned false"
		assert @poll.hasCallback?( $stdout ), "hasCallback? returned false"
	end


	# Test registration with a callback as an inline block and a callback arg
	def test_06b_RegisterWithBlockAndArg
		assert_nothing_raised {
			@poll.register($stdout, Poll::OUT, nil, "foo") {|io,eventMask,arg|
				$stderr.puts "Got an output event for STDOUT"
			}
		}
		assert @poll.has_callback?( $stdout ), "has_callback? returned false"
		assert @poll.hasCallback?( $stdout ), "hasCallback? returned false"
	end


	# Test registration with a Proc argument
	def test_07RegisterWithProc
		assert_nothing_raised {
			@poll.register $stdout,
				Poll::OUT,
				Proc::new {|io,eventMask| $stderr.puts "Got an output event for STDOUT"},
				"foo"
		}
		assert @poll.has_callback?( $stdout ), "has_callback? returned false"
		assert @poll.hasCallback?( $stdout ), "hasCallback? returned false"
	end


	# Test registration with a Proc argument and a callback arg
	def test_07RegisterWithProcAndArg
		assert_nothing_raised {
			@poll.register $stdout,
				Poll::OUT,
				Proc::new {|io,eventMask| $stderr.puts "Got an output event for STDOUT"},
				"foo"
		}
		assert @poll.has_callback?( $stdout ), "has_callback? returned false"
		assert @poll.hasCallback?( $stdout ), "hasCallback? returned false"
	end


	# Test registration with a Method argument
	def test_08RegisterWithMethod
		assert_nothing_raised {
			@poll.register $stdout, Poll::OUT, $stderr.method( :puts )
		}
		assert @poll.has_callback?( $stdout ), "has_callback? returned false"
		assert @poll.hasCallback?( $stdout ), "hasCallback? returned false"
	end


	# Test registration with a Method argument and a callback arg
	def test_08RegisterWithMethodAndArg
		assert_nothing_raised {
			@poll.register $stdout, Poll::OUT, $stderr.method( :puts ), "foo"
		}
		assert @poll.has_callback?( $stdout ), "has_callback? returned false"
		assert @poll.hasCallback?( $stdout ), "hasCallback? returned false"
	end


	# Test the clear method
	def test_09Clear
		# Test it empty
		assert_nothing_raised {
			@poll.clear
		}

		# Test it with one registered
		assert_nothing_raised {
			@poll.register $stdout, Poll::OUT, $stdout.method( :puts )
			@poll.clear
		}
		assert ! @poll.registered?( $stdout ), "$stdout wasn't registed with the poll handle"
		assert_equal 0, @poll.handles.length
	end


	# Test the #events method without a #poll first
	def test_10Events
		rv = nil

		@poll.register $stdout, Poll::OUT|Poll::PRI
		@poll.register @tmpfile, Poll::PRI

		# Test without calling poll() first
		assert_nothing_raised { @poll.events }
		assert_nothing_raised { rv = @poll.events.find {|h| h == $stdout} }
		assert_equal nil, rv
	end


	# Test the #poll method
	def test_11Poll
		rv = nil

		@poll.register $stdout, Poll::OUT|Poll::PRI
		@poll.register @tmpfile, Poll::PRI

		assert_nothing_raised { rv = @poll.poll(0.1) }
		assert_equal 1, rv

		assert_nothing_raised { rv = @poll.events Poll::OUT }
		assert_instance_of Array, rv
		assert_equal rv[0], $stdout
		assert ! @poll.events.find {|h| h == @tmpfile}, "@tmpfile was in the events hash"
	end


	# Test #poll with a block default handler
	def test_12PollWithBlock
		rv = nil

		@poll.register $stdout, Poll::OUT|Poll::PRI
		@poll.register @tmpfile, Poll::PRI

		assert_nothing_raised {
			rv = @poll.poll( 15 ) {|io,eventMask|
				$stderr.puts "Default handler got #{io.inspect} with mask #{eventMask}" if $VERBOSE
			}
		}
	end


	# Test the #handles method with various arguments
	def test_13Handles
		@poll.register $stdout, Poll::OUT|Poll::PRI
		@poll.register @tmpfile, Poll::PRI

		assert_equal 2, @poll.handles.length
		assert_equal 1, @poll.handles( Poll::OUT ).length
		assert_equal $stdout, @poll.handles( Poll::OUT )[0]
		assert_equal 2, @poll.handles( Poll::PRI ).length
	end

	# Test the #callback method
	def test_14Callback
		testProc = Proc::new {|io,eventMask|
			$stderr.puts "Default handler got #{io.inspect} with mask #{eventMask}" if $VERBOSE
		}
		@poll.register( $stdout, Poll::OUT|Poll::PRI, testProc )

		assert_equal testProc, @poll.callback( $stdout )
	end

end # class PollTestCase








