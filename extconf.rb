#!/usr/bin/ruby
#
#	extconf.rb - Extension config script for the Ruby IO::Poll class
#
#	See the README file for instructions on how to use this script.
#
#	Author: Michael Granger (with lots of code borrowed from the bdb Ruby
#				extension's extconf.rb)
#
#	Copyright (c) 2002 The FaerieMUD Consortium. All rights reserved.
#
#	This program is free software; you can redistribute it and/or modify it
#	under the same terms as Ruby itself.
#
#	This library is distributed in the hope that it will be useful, but
#	WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#

require 'mkmf'

### Print an error message and exit with an error condition
def abort( msg )
	$stderr.puts( msg )
	exit 1
end

MSWINTEST1 = Proc::new {|func|
	%{
#include <windows.h>
#include <winsock.h>
int main() { return 0; }
int t() { #{func}(); return 0; }
	}
}

MSWINTEST2 = Proc::new {|func|
	%{
#include <windows.h>
#include <winsock.h>
int main() { return 0; }
int t() { void ((*p)()); p = (void ((*)()))#{func}; return 0; }
	}
}

GENERICTEST = Proc::new {|func|
	%{
int main() { return 0; }
int t() { #{func}(); return 0; }
	}
}

### Version of have_library() that doesn't append (for checking a library that
### we already found, but may not be recent enough)
def have_library_no_append(lib, func="main")
	print "checking for %s() in -l%s... " % [ func, lib ]
	$stdout.flush

	if func && func != ""
		tmplibs = append_library( $libs, lib )
		if /mswin32|mingw/ =~ RUBY_PLATFORM
			r = try_link(MSWINTEST1[func], tmplibs) || try_link(MSWINTEST2[func], tmplibs)
		else
			r = try_link(GENERICTEST[func], tmplibs)
		end

		unless r
			print "no\n"
			return false
		end
	else
		raise "Empty library function specified"
	end

	print "yes\n"
	return true
end




# Add some cflags
$CFLAGS << ' -Wall '

dir_config( "poll" )

# Make sure we have the ODE library and header available
if enable_config("fakepoll") || !have_library_no_append( "c", "poll" )
	puts "Using rb_thread_select() instead of native poll()."
	$defs << "-DUSE_FAKE_POLL"
else
	have_header( "poll.h" ) || have_header( "sys/poll.h" ) or
		abort( "Can't find a suitable poll.h." )
end
have_header( "limits.h" )

# Write the Makefile
create_makefile( "poll" )

# Read the makefile in and fix the fscked-up lib install targets
last_target = nil
makefile = IO::readlines( "Makefile" ).collect {|line|
	if line =~ /^(\S+):/
		last_target = $1
	end

	if last_target =~ /site-install/
		line.gsub!( %r{\$\(rubylibdir\)\$\(target_prefix\)/lib}, '$(target_prefix)$(sitelibdir)' )
	elsif last_target =~ /install/
		line.gsub!( %r{\$\(rubylibdir\)\$\(target_prefix\)/lib}, '$(target_prefix)$(rubylibdir)' )
	end

	line
}


# Now write the makefile back out and add some more targets to the end
File.open( "Makefile", "w" ) {|make|
	make.print makefile
	make.print <<EOF

depend:
	$(CC) $(CFLAGS) $(CPPFLAGS) -MM *.c > depend

.PHONY: docs html test debugtest

docs: 
	$(RUBY) makedocs.rb

html: docs

test: all
	$(RUBY) test.rb

debugtest: clean all
	$(RUBY) -wd test.rb

EOF
}

