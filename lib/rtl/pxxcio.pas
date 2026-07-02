{ SPDX-License-Identifier: Zlib }
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
function __pxx_open(path: PChar; flags, mode: Integer): Integer;
function __pxx_close(fd: Integer): Integer;
function __pxx_seek(fd: Integer; offset: Int64; whence: Integer): Int64;
function __pxx_remove(path: PChar): Integer;
function __pxx_rename(oldPath, newPath: PChar): Integer;

{ C socket bridge: BSD-shaped C wrappers parse/fill sockaddr_in and bottom out
  on these PAL IPv4 primitives, so C and Pascal share one socket backend. }
function __pxx_socket(domain, kind, proto: Integer): Integer;
function __pxx_setsockopt(fd, level, optname: Integer; val: Pointer; len: Integer): Integer;
function __pxx_bind_ipv4(fd: Integer; host: LongWord; port: Integer): Integer;
function __pxx_connect_ipv4(fd: Integer; host: LongWord; port: Integer): Integer;
function __pxx_listen(fd, backlog: Integer): Integer;
function __pxx_accept_ipv4(fd: Integer; outHost, outPort: Pointer): Integer;
function __pxx_send(fd: Integer; buf: Pointer; len: Integer): Int64;
function __pxx_recv(fd: Integer; buf: Pointer; len: Integer): Int64;
function __pxx_sendto_ipv4(fd: Integer; buf: Pointer; len: Integer; host: LongWord; port: Integer): Int64;
function __pxx_recvfrom_ipv4(fd: Integer; buf: Pointer; len: Integer; outHost, outPort: Pointer): Int64;
function __pxx_shutdown(fd, how: Integer): Integer;
function __pxx_socket_close(fd: Integer): Integer;
function __pxx_getsockname_ipv4(fd: Integer; outHost, outPort: Pointer): Integer;
function __pxx_getsockerror(fd: Integer): Integer;

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

type
  PLongWord = ^LongWord;
  PInteger = ^Integer;

function __pxx_write(fd: Integer; buf: Pointer; n: Int64): Int64;
begin
  Result := PalWrite(fd, buf, Integer(n));
end;

function __pxx_read(fd: Integer; buf: Pointer; n: Int64): Int64;
begin
  Result := PalRead(fd, buf, Integer(n));
end;

function __pxx_open(path: PChar; flags, mode: Integer): Integer;
begin
  Result := PalOpen(path, flags, mode);
end;

function __pxx_close(fd: Integer): Integer;
begin
  Result := PalClose(fd);
end;

function __pxx_seek(fd: Integer; offset: Int64; whence: Integer): Int64;
begin
  Result := PalSeek(fd, offset, whence);
end;

function __pxx_remove(path: PChar): Integer;
begin
  Result := PalDelete(path);
end;

function __pxx_rename(oldPath, newPath: PChar): Integer;
begin
  Result := PalRename(oldPath, newPath);
end;

function __pxx_socket(domain, kind, proto: Integer): Integer;
begin
  Result := PalSocket(domain, kind, proto);
end;

function __pxx_setsockopt(fd, level, optname: Integer; val: Pointer; len: Integer): Integer;
begin
  Result := PalSetSockOpt(fd, level, optname, val, len);
end;

function __pxx_bind_ipv4(fd: Integer; host: LongWord; port: Integer): Integer;
begin
  Result := PalBindIpv4(fd, host, port);
end;

function __pxx_connect_ipv4(fd: Integer; host: LongWord; port: Integer): Integer;
begin
  Result := PalConnectIpv4(fd, host, port);
end;

function __pxx_listen(fd, backlog: Integer): Integer;
begin
  Result := PalListen(fd, backlog);
end;

function __pxx_accept_ipv4(fd: Integer; outHost, outPort: Pointer): Integer;
var host: LongWord; port: Integer;
begin
  Result := PalAcceptIpv4(fd, host, port);
  if Result >= 0 then
  begin
    PLongWord(outHost)^ := host;
    PInteger(outPort)^ := port;
  end;
end;

function __pxx_send(fd: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := PalSend(fd, buf, len);
end;

function __pxx_recv(fd: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := PalRecv(fd, buf, len);
end;

function __pxx_sendto_ipv4(fd: Integer; buf: Pointer; len: Integer; host: LongWord; port: Integer): Int64;
begin
  Result := PalSendToIpv4(fd, buf, len, host, port);
end;

function __pxx_recvfrom_ipv4(fd: Integer; buf: Pointer; len: Integer; outHost, outPort: Pointer): Int64;
var host: LongWord; port: Integer;
begin
  Result := PalRecvFromIpv4(fd, buf, len, host, port);
  if Result >= 0 then
  begin
    PLongWord(outHost)^ := host;
    PInteger(outPort)^ := port;
  end;
end;

function __pxx_shutdown(fd, how: Integer): Integer;
begin
  Result := PalShutdown(fd, how);
end;

function __pxx_socket_close(fd: Integer): Integer;
begin
  Result := PalSocketClose(fd);
end;

function __pxx_getsockname_ipv4(fd: Integer; outHost, outPort: Pointer): Integer;
var host: LongWord; port: Integer;
begin
  Result := PalGetSockNameIpv4(fd, host, port);
  if Result >= 0 then
  begin
    PLongWord(outHost)^ := host;
    PInteger(outPort)^ := port;
  end;
end;

function __pxx_getsockerror(fd: Integer): Integer;
begin
  Result := PalGetSockError(fd);
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
