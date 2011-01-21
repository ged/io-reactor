## 1.0.4 [2009-08-15] Michael Granger <ged@FaerieMUD.org>

Cleanup and documentation fixes.

Bugfixes:

* Applied bugfix for auto-vivification bug and another related edgecase (fixes #3)

## 0.0.6 [2004-11-16] Michael Granger <ged@FaerieMUD.org>

* Removed unneeded docs-generation scripts.
* Added gemspec by Chad Fowler.

## 0.0.5 [2004-11-16] Michael Granger <ged@FaerieMUD.org>

Bugfixes, courtesy of Daniel J. Berger <djberge at qwest dot com>:

- Removed duplicate #registered? method. Spotted by .
- Added workarounds for Win32. Thanks to Daniel Berger.

## 0.04 [2003-07-22] Michael Granger <ged@FaerieMUD.org>

- Documentation improvements
- Added argument list given to handlers.

## 0.03 [2002-10-21] Michael Granger <ged@FaerieMUD.org>

- Renamed to IO::Reactor (from IO::Poll), and converted the poll(2)-based 
  C backend to one that uses IO#select.

## 0.02 [2002-10-21] Michael Granger <ged@FaerieMUD.org>

Enhancements:

- New methods: #setMask, #callback, #args.

Bugfixes:

- Removed dependence on as-yet-undistributed xhtml RDoc template.
- Added interrupt-handling to the _poll call.
- Added more-informative debugging.
- Added missing callback *args to #setCallback().
- Cleared up documentation for #register.
- Got rid of a type-checking statement, as it didn't account for using an IO
  inside a wrappered or delegated object.
- Fixed use of deprecated 'type' method.

## 0.01 [2002-09-18] Michael Granger <ged@FaerieMUD.org>

Initial release.

