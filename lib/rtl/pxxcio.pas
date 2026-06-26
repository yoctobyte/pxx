unit pxxcio;
{ C runtime IO bridge — the libc-free byte sink for the C frontend's stdio
  veneer (lib/crtl/src/stdio.c).

  Rule: C stdio must stay libc-free and REUSE the existing cross-platform Pascal
  PAL (posix syscalls / ESP-IDF), so C and Pascal share ONE IO path. The C side
  declares `extern long __pxx_write(int, const void*, unsigned long)`; because
  these are bodied Pascal procs compiled into the same binary, the C call
  resolves to them internally (FindProc), NOT as a dynamic libc import.

  The C driver auto-pulls this unit for every C program (ParseCProgram), the same
  way the Pascal driver pulls `builtin`/`textfile`. }

interface

uses platform;

function __pxx_write(fd: Integer; buf: Pointer; n: Int64): Int64;
function __pxx_read(fd: Integer; buf: Pointer; n: Int64): Int64;

implementation

function __pxx_write(fd: Integer; buf: Pointer; n: Int64): Int64;
begin
  Result := PalWrite(fd, buf, Integer(n));
end;

function __pxx_read(fd: Integer; buf: Pointer; n: Int64): Int64;
begin
  Result := PalRead(fd, buf, Integer(n));
end;

end.
