#!/usr/bin/env ruby

BEGIN {
	require 'pathname'
	basedir = Pathname.new( __FILE__ ).dirname.parent.parent

	libdir = basedir + "lib"

	$LOAD_PATH.unshift( libdir ) unless $LOAD_PATH.include?( libdir )
}

require 'rspec'
require 'tempfile'
require 'socket'

require 'io/reactor'


describe IO::Reactor do

	before( :all ) do
		@test_data = File.read( __FILE__ )
	end

	before( :each ) do
		@reactor = IO::Reactor.new
		@reader, @writer = IO.pipe
	end

	after( :each ) do
		@reactor.clear
	end


	### #register/#registered? with no block
	it "allows registration of an IO for write events" do
		@reactor.register( @writer, :write )

		@reactor.should be_registered( @writer )
		@reactor.handles[ @writer ][ :events ].should == [:write]
	end

	it "allows registration of an IO for read events" do
		@reactor.register( @reader, :read )

		@reactor.should be_registered( @reader )
		@reactor.handles[ @reader ][ :events ].should == [:read]
	end

	it "allows registration of an IO for error events" do
		@reactor.register( @writer, :error )

		@reactor.should be_registered( @writer )
		@reactor.handles[ @writer ][ :events ].should == [:error]
	end

	it "allows registration of an IO for multiple events" do
		@reactor.register( @writer, :read, :write )

		@reactor.should be_registered( @writer )
		@reactor.handles[ @writer ][ :events ].should have(2).members
		@reactor.handles[ @writer ][ :events ].should include( :read )
		@reactor.handles[ @writer ][ :events ].should include( :write )
	end


	it "allows registration of a handler with an IO for selected events" do
		@reactor.register( @writer, :write ) {|io, event|  }

		@reactor.should be_registered( @writer )
		@reactor.handles[ @writer ][ :events ].should == [:write]
	end


	it "allows registration of an argument list with a handler" do
		@reactor.register( @writer, :write, "foo", :bar, :something ) {|io, event|  }

		@reactor.should be_registered( @writer )
		@reactor.handles[ @writer ][ :events ].should == [:write]
		@reactor.handles[ @writer ][ :args ].should == ["foo", :bar, :something]
	end


	it "allows all registered handles to be cleared" do
		@reactor.register( @reader, :read )
		@reactor.register( @writer, :write )

		@reactor.clear

		@reactor.handles.should be_empty()
		@reactor.should_not be_registered( @writer )
		@reactor.should_not be_registered( @reader )
	end


	it "calls registered handlers for events on an IO when they occur" do
		data_to_send = @test_data.dup
		received_data = ''

		@reactor.register( @reader, :read ) do |io, event|
			if io.eof?
				@reactor.unregister( io )
				io.close
			else
				received_data << io.read( 256 )
			end
		end
		@reactor.register( @writer, :write ) do |io, event|
			if data_to_send.empty?
				@reactor.unregister( io )
				io.close
			else
				bytes = io.write( data_to_send )
				data_to_send.slice!( 0, bytes )
			end
		end

		@reactor.poll until @reactor.empty?

		received_data.should == @test_data
	end


	it "calls a provided fallback handler if there is no handler registered for an " +
	   "event when it occurs" do

		data_to_send = @test_data.dup
		received_data = ''

		@reactor.register( @reader, :read )
		@reactor.register( @writer, :write )

		until @reactor.empty?
			@reactor.poll do |io, event|
				case event
				when :read
					if io.eof?
						@reactor.unregister( io )
						io.close
					else
						received_data << io.read( 256 )
					end

				when :write
					if data_to_send.empty?
						@reactor.unregister( io )
						io.close
					else
						bytes = io.write( data_to_send )
						data_to_send.slice!( 0, bytes )
					end

				when :error
					@reactor.unregister( io )
					io.close
				else
					fail "Reactor got unexpected event %p on %p" % [ event, io ]
				end
			end
		end

		received_data.should == @test_data
	end


	### A class that will encapsulate how we want to read or write from the Reactor
	class IOStrategy
		def initialize( reactor, buffer='' )
			@reactor = reactor
			@buffer = buffer
		end

		attr_reader :buffer

		def read_from( io, event )
			raise ArgumentError, "expected to read, not #{event}" unless event == :read
			if io.eof?
				@reactor.unregister( io )
				io.close
			else
				@buffer << io.read( 256 )
			end
		end

		def write_to( io, event )
			raise ArgumentError, "expected to write, not #{event}" unless event == :write
			if @buffer.empty?
				@reactor.unregister( io )
				io.close
			else
				bytes = io.write( @buffer )
				@buffer.slice!( 0, bytes )
			end
		end
	end

	it "uses method or proc handlers if those are used instead of blocks" do
		reader = IOStrategy.new( @reactor )
		writer = IOStrategy.new( @reactor, @test_data.dup )

		@reactor.register( @reader, :read, &reader.method(:read_from) )
		@reactor.register( @writer, :write, &writer.method(:write_to) )
		@reactor.poll until @reactor.empty?

		reader.buffer.should == @test_data
	end


	it "saves pending events if there is no handler registered for them and no fallback " +
	   "handler provided" do

		@reactor.register( $stdout, :write )
		@reactor.poll( 1.0 ).should == 1

		@reactor.pending_events.should have(1).members
		@reactor.pending_events.keys.should include( $stdout )
		@reactor.pending_events[ $stdout ].should == [ :write ]
	end

	it "knows what events are enabled for which handles" do
		@reactor.register( @writer )
		@reactor.should_not have_event_enabled( @writer, :read )
		@reactor.enable_events( @writer, :read, :write )
		@reactor.should have_event_enabled( @writer, :read )
		@reactor.should have_event_enabled( @writer, :write )
	end


	it "allows events to be unregistered for a handle" do
		@reactor.register( @writer, :write, :read )
		@reactor.disable_events( @writer, :read )
		@reactor.should_not have_event_enabled( @writer, :read )
	end


	it "doesn't allow the error event to be disabled for a handle" do
		@reactor.register( @writer, :write )
		lambda {
			@reactor.disable_events( @writer, :error )
		}.should raise_error
	end


	it "can remove the handler for a handle" do
		handler = lambda { }
		@reactor.register( @writer, :write, &handler )
		@reactor.remove_handler( @writer ).should == handler
	end


	it "can clear the handler arguments for a handle" do
		@reactor.register( @writer, :write, :an_arg )
		@reactor.remove_args( @writer )
		@reactor.handles[ @writer ][:args].should be_empty()
	end

end # class PollTestCase

