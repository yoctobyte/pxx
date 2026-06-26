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

uses platform, builtinheap, math;

function __pxx_write(fd: Integer; buf: Pointer; n: Int64): Int64;
function __pxx_read(fd: Integer; buf: Pointer; n: Int64): Int64;

{ C heap bridge: malloc/free/realloc ride the same mmap-backed pool as Pascal
  GetMem (PXXAlloc/PXXFree/PXXRealloc), which self-inits lazily (HeapPtr=0 ->
  fresh mmap) so no program prologue is needed — libc-free, one heap with Pascal.
  PXXAlloc returns zeroed memory, so calloc needs no extra clear. }
function __pxx_malloc(n: Int64): Pointer;
procedure __pxx_free(p: Pointer);
function __pxx_realloc(p: Pointer; n: Int64): Pointer;

{ C process exit (exit/abort/_Exit) -> the PAL/RTL terminate path. }
procedure __pxx_exit(code: Integer);

implementation

function __pxx_write(fd: Integer; buf: Pointer; n: Int64): Int64;
begin
  Result := PalWrite(fd, buf, Integer(n));
end;

function __pxx_read(fd: Integer; buf: Pointer; n: Int64): Int64;
begin
  Result := PalRead(fd, buf, Integer(n));
end;

function __pxx_malloc(n: Int64): Pointer;
begin
  Result := PXXAlloc(n, 8);
end;

procedure __pxx_free(p: Pointer);
begin
  PXXFree(p);
end;

function __pxx_realloc(p: Pointer; n: Int64): Pointer;
begin
  Result := PXXRealloc(p, n, 8);
end;

procedure __pxx_exit(code: Integer);
var r: Int64;
begin
  { exit_group(code) — terminate the process directly (PAL posix). Assigned form
    because __pxxrawsyscall is intercepted in expression context; the syscall
    never returns, so r is unused. }
  r := __pxxrawsyscall(231, code, 0, 0, 0, 0, 0);
end;

end.
