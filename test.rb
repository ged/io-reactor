#!/usr/bin/ruby
#
#	Test suite for Poll
#
#

$:.unshift "src", "ext", "tests"

require 'test/unit'
require 'poll'

TMPFILE = "testfile.#{$$}"

### Reqyure tests
class PollTestCase < Test::Unit::TestCase

	# Setup method
	def set_up
		@poll = Poll::new
		@tmpfile = File::open( TMPFILE, 'w' )
		File::unlink TMPFILE
	end

	# Teardown method
	def tear_down
		@poll = nil
	end

	# Test to make sure require worked
	def test_00Requires
		assert_instance_of Class, Poll
		assert_instance_of Poll, @poll
	end

	# Test for the presence of constants
	def test_01Constants
		%w{POLLIN POLLOUT POLLPRI POLLERR POLLHUP POLLNVAL}.each {|sym|
			assert Poll.const_defined?( sym.intern ), "Poll doesn't define the #{sym} constant."
		}
	end

	# Test the #mask method with various arguments
	def test_02Masks
		assert_raises( ArgumentError ) { @poll.mask "a test string", Poll::POLLOUT }

		assert_nothing_raised { @poll.mask $stdout, Poll::POLLOUT }
		assert_equal Poll::POLLOUT, @poll.mask( $stdout )

		assert_nothing_raised { @poll.mask @tmpfile, Poll::POLLPRI }
		assert_equal Poll::POLLPRI, @poll.mask( @tmpfile )

		assert_nothing_raised { @poll.mask $stdout, Poll::POLLOUT|Poll::POLLPRI }
		assert( (@poll.mask( $stdout ) & Poll::POLLOUT).nonzero? )

		assert_nothing_raised {
			@poll.mask($stdout, Poll::POLLOUT) {|io,eventMask|
				$stderr.puts "Got an output event for STDOUT"
			}
		}
		assert_nothing_raised {
			@poll.has_callback?( $stdout )
		}

	end

	# Test the #poll method with various arguments
	def test_03Poll
		rv = nil

		@poll.mask $stdout, Poll::POLLOUT|Poll::POLLPRI
		@poll.mask @tmpfile, Poll::POLLPRI

		# Test without calling poll() first
		assert_nothing_raised { rv = @poll.events($stdout) }
		assert_equal 0, rv

		assert_nothing_raised { rv = @poll.poll(0.1) }

		assert_equal 1, rv
		assert_equal Poll::POLLOUT, @poll.events( $stdout )
		assert_equal 0, @poll.events( @tmpfile )

		assert_nothing_raised {
			rv = @poll.poll( 15 ) {|io,eventMask|
				$stderr.puts "Default handler got #{io.inspect} with mask #{eventMask}"
			}
		}
	end

	# Test the #handles method with various arguments
	def test_04Handles
		@poll.mask $stdout, Poll::POLLOUT|Poll::POLLPRI
		@poll.mask @tmpfile, Poll::POLLPRI

		assert_equal 2, @poll.handles.length
		assert_equal 0, @poll.handles( Poll::POLLOUT ).length
		
		assert_nothing_raised { @poll.poll }

		assert_equal 2, @poll.handles.length
		assert_equal $stdout, @poll.handles( Poll::POLLOUT )[0]
	end

end # class PollTestCase








