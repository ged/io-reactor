#!/usr/bin/ruby
#
#	extconf.rb - Extension config script for the Ruby IO::Poll class
#
#	See the INSTALL file for instructions on how to use this script.
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

def rule(target, clean = nil)
   wr = "#{target}:
\t@for subdir in $(SUBDIRS); do \\
\t\t$(MAKE) -C $${subdir} #{target}; \\
\tdone;
"
   if clean != nil
     # wr << "\t@-rm tmp/* tests/tmp/* 2> /dev/null\n"
	  wr << "\t@-rm -f mkmf.log src/mkmf.log 2> /dev/null\n"
	  wr << "\t@-rm -f src/depend 2> /dev/null\n"
      wr << "\t@rm Makefile\n" if clean
   end
   wr
end

subdirs = Dir["*"].select do |subdir|
   File.file?(subdir + "/extconf.rb")
end

begin
   make = open("Makefile", "w")
   make.print <<-EOF
SUBDIRS = #{subdirs.join(' ')}

#{rule('all')}
#{rule('clean', false)}
#{rule('distclean', true)}
#{rule('realclean', true)}
#{rule('install')}
#{rule('depend')}
#{rule('site-install')}
#{rule('unknown')}
docs:
	rdoc -S --title 'Ruby IO::Poll' --main README README src ext

html: docs

test: all
	ruby test.rb

debugtest: clean all
	ruby -wd test.rb

	EOF
ensure
   make.close
end

subdirs.each do |subdir|
   STDERR.puts("#{$0}: Entering directory `#{subdir}'")
   Dir.chdir(subdir)
   system("#{Config::CONFIG['RUBY_INSTALL_NAME']} extconf.rb " + ARGV.join(" "))
   Dir.chdir("..")
   STDERR.puts("#{$0}: Leaving directory `#{subdir}'")
end
