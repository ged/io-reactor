/*
 *		poll.c - A poll() implementation for Ruby
 *		$Id: poll.c,v 1.2 2002/04/17 12:47:29 deveiant Exp $
 *
 *		Author: Michael Granger <ged@FaerieMUD.org>
 *		Copyright (c) 2002 The FaerieMUD Consortium. All rights reserved.
 *
 *		This library is free software; you can redistribute it and/or modify it
 *		under the same terms as Ruby itself.
 *
 *		This library is distributed in the hope that it will be useful, but
 *		WITHOUT ANY WARRANTY; without even the implied warranty of
 *		MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 *
 */

#define _GNU_SOURCE

#include <ruby.h>
#include <rubyio.h>
#include <poll.h>


/* -------------------------------------------------------
 * Globals
 * ------------------------------------------------------- */

VALUE poll_cPoll;
VALUE poll_cPollError;


// Debugging function
#ifdef HAVE_STDARG_PROTOTYPES
# include <stdarg.h>
# define va_init_list(a,b) va_start(a,b)
void
poll_debug(const char *fmt, ...)
#else
# include <varargs.h>
# define va_init_list(a,b) va_start(a)
void
poll_debug(fmt, va_alist)
    const char *fmt;
    va_dcl
#endif
{
  char		buf[BUFSIZ], buf2[BUFSIZ];
  va_list	args;

  if (!RTEST(ruby_verbose)) return;

  snprintf( buf, BUFSIZ, "POLL Debug>>> %s", fmt );

  va_init_list( args, fmt );
  vsnprintf( buf2, BUFSIZ, buf, args );
  fputs( buf2, stderr );
  fputs( "\n", stderr );
  fflush( stderr );
  va_end( args );
}


/* -------------------------------------------------------
 * Backend function
 * ------------------------------------------------------- */

VALUE
_poll( self, fdArray, timeoutArg )
	 VALUE self, fdArray, timeoutArg;
{
#ifdef HAVE_POLL_H
  unsigned long fdCount;
  int timeout;
  struct pollfd *fds;
  int i, evCount;
  VALUE handlePair, evHash;
  OpenFile *fptr;
  
  // Make sure the first arg is an array, then get its length
  Check_Type( fdArray, T_ARRAY );
  fdCount = (unsigned long)RARRAY( fdArray )->len;
  poll_debug( "Got %d handles for polling.", fdCount );

  // Get the timeout
  timeout = NUM2INT( timeoutArg );
  poll_debug( "Poll timeout = %d", timeout );

  // Alloc a pollfd array of the needed size from the stack
  fds = (struct pollfd *)ALLOCA_N( struct pollfd, fdCount );

  // Iterate over the handles in the list and add each to the pollfd array
  for ( i = 0 ; i < fdCount ; i++ ) {
	handlePair = rb_ary_entry( fdArray, i );
	GetOpenFile( rb_ary_entry(handlePair, 0), fptr );
	fds[i].fd = fileno(fptr->f);
	fds[i].events = NUM2INT( rb_ary_entry(handlePair, 1) );
	fds[i].revents = 0;
  }

  // Create the event hash that'll be returned
  evHash = rb_hash_new();

  // Do the poll, if it returns a positive number, add the events which occured
  // to the event hash.
  if ( (evCount = poll( fds, fdCount, timeout )) >= 0 ) {

	// Iterate over the filehandles, looking for ones with revents. Ones we find
	// get added to the event hash.
	for ( i = 0 ; i < fdCount ; i++ ) {
	  if ( fds[i].revents != 0 ) {
		handlePair = rb_ary_entry( fdArray, i );
		rb_hash_aset( evHash, rb_ary_entry(handlePair,0), INT2NUM(fds[i].revents) );
	  }
	}
  }

  // Handle errors by setting Errno and raising a PollError
  else if ( evCount < 0 )
	rb_sys_fail( "Poll error" );

  return evHash;

#else
  rb_notimplement();
#endif // HAVE_POLL_H
}


/* -------------------------------------------------------
 * Extension init function
 * ------------------------------------------------------- */
void
Init_poll( void )
{
  poll_debug( "Initializing poll modules" );

  // Classes
  poll_cPoll		= rb_define_class( "Poll", rb_cObject );
  poll_cPollError	= rb_define_class( "PollError", rb_eStandardError );

  // Constants
  rb_define_const( poll_cPoll, "POLLIN",		INT2NUM(POLLIN) );
  rb_define_const( poll_cPoll, "IN",			INT2NUM(POLLIN) );

  rb_define_const( poll_cPoll, "POLLPRI",		INT2NUM(POLLPRI) );
  rb_define_const( poll_cPoll, "PRI",			INT2NUM(POLLPRI) );

  rb_define_const( poll_cPoll, "POLLOUT",		INT2NUM(POLLOUT) );
  rb_define_const( poll_cPoll, "OUT",			INT2NUM(POLLOUT) );

  rb_define_const( poll_cPoll, "POLLERR",		INT2NUM(POLLERR) );
  rb_define_const( poll_cPoll, "ERR",			INT2NUM(POLLERR) );

  rb_define_const( poll_cPoll, "POLLHUP",		INT2NUM(POLLHUP) );
  rb_define_const( poll_cPoll, "HUP",			INT2NUM(POLLHUP) );

  rb_define_const( poll_cPoll, "POLLNVAL",		INT2NUM(POLLNVAL) );
  rb_define_const( poll_cPoll, "NVAL",			INT2NUM(POLLNVAL) );

#ifdef POLLRDNORM
  rb_define_const( poll_cPoll, "POLLRDNORM",	INT2NUM(POLLRDNORM) );
  rb_define_const( poll_cPoll, "RDNORM",		INT2NUM(POLLRDNORM) );
#endif

#ifdef POLLRDBAND
  rb_define_const( poll_cPoll, "POLLRDBAND",	INT2NUM(POLLRDBAND) );
  rb_define_const( poll_cPoll, "RDBAND",		INT2NUM(POLLRDBAND) );
#endif

#ifdef POLLWRNORM
  rb_define_const( poll_cPoll, "POLLWRNORM",	INT2NUM(POLLWRNORM) );
  rb_define_const( poll_cPoll, "WRNORM",		INT2NUM(POLLWRNORM) );
#endif

#ifdef POLLWRBAND
  rb_define_const( poll_cPoll, "POLLWRBAND",	INT2NUM(POLLWRBAND) );
  rb_define_const( poll_cPoll, "WRBAND",		INT2NUM(POLLWRBAND) );
#endif

#ifdef POLLMSG
  rb_define_const( poll_cPoll, "POLLMSG",		INT2NUM(POLLMSG) );
  rb_define_const( poll_cPoll, "MSG",			INT2NUM(POLLMSG) );
#endif

  // Methods
  rb_define_protected_method( poll_cPoll, "_poll", _poll, 2 );

  // Load the Ruby front end
  rb_require( "poll.rb" );
}


