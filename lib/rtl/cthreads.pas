{ SPDX-License-Identifier: Zlib }
unit cthreads;
{ Compatibility shim: exists so portable FPC sources compile unedited.

  On Unix, FPC requires `cthreads` FIRST in a threaded program's uses clause —
  it installs the C (pthread) thread manager over the default single-threaded
  one, and without it TThread fails at run time. So essentially every portable
  threaded Pascal source in the world begins:

      uses {$IFDEF UNIX}cthreads,{$ENDIF} Classes, SysUtils;

  and that `{$IFDEF UNIX}` is the point. pxx has no thread manager to install
  and no libc to install one from: threads are native and libc-free
  (palthread/palsync/palthreadobj), always present, never swapped at run time.
  So the correct pxx implementation of "install the C thread manager" is to do
  nothing — and doing nothing under the name FPC code already writes is what
  makes that code compile as-is, which is the mission line
  (compat-pascal-thread-api-surface-differs-from-fpc).

  This unit is therefore deliberately EMPTY, and that emptiness is the feature.
  It does not pull in the thread machinery: `uses cthreads` alone must not drag
  __pxxclone's --threadsafe gate into a program that merely inherited the line
  from a portable header. The program's own TThread use is what pulls palthreadobj
  in, exactly as on FPC. }

interface

implementation

end.
