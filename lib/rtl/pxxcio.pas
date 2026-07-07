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
function __pxx_malloc(n: NativeInt): Pointer;
procedure __pxx_free(p: Pointer);
function __pxx_realloc(p: Pointer; n: NativeInt): Pointer;

{ C process exit (exit/abort/_Exit) -> the PAL/RTL terminate path. }
procedure __pxx_exit(code: Integer);

{ C time bridge: wall-clock seconds since the Unix epoch (time()) and process
  CPU time in microseconds (clock()), both via a per-arch clock_gettime syscall.
  Libc-free; UTC. Returns 0 on an unsupported target (never asserts). }
function __pxx_time: Int64;
function __pxx_clock: Int64;

{ C filesystem-metadata bridge for sqlite's unix VFS (libc-free). stat/fstat/lstat
  fill this fixed-layout record (5 Int64 + 2 Integer = 48 bytes, identical on every
  target); the C veneer copies it into the caller's `struct stat`. }
type
  PPxxStatBuf = ^TPxxStatBuf;
  TPxxStatBuf = record
    Size:    Int64;
    MTime:   Int64;
    Ino:     Int64;
    Dev:     Int64;
    Blocks:  Int64;
    Mode:    Integer;
    BlkSize: Integer;
  end;

function __pxx_fstat(fd: Integer; sb: PPxxStatBuf): Integer;
function __pxx_stat(path: PChar; sb: PPxxStatBuf): Integer;
function __pxx_lstat(path: PChar; sb: PPxxStatBuf): Integer;
function __pxx_fcntl(fd, cmd: Integer; arg: Int64): Integer;
function __pxx_fsync(fd: Integer): Integer;
function __pxx_fchmod(fd, mode: Integer): Integer;
function __pxx_mkdir(path: PChar; mode: Integer): Integer;
function __pxx_getpid: Integer;
function __pxx_getcwd(buf: PChar; size: Integer): Integer;
function __pxx_nanosleep(sec, nsec: Int64): Integer;
function __pxx_utimes(path: PChar; atimeSec, mtimeSec: Int64): Integer;
{ fills two Int64 out-slots the C gettimeofday veneer narrows into struct timeval }
function __pxx_realtime(secOut, usecOut: Pointer): Integer;

implementation

type
  PLongWord = ^LongWord;
  PInteger = ^Integer;
  PInt64 = ^Int64;

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

function __pxx_malloc(n: NativeInt): Pointer;
begin
  Result := PXXAlloc(n, 8);
end;

procedure __pxx_free(p: Pointer);
begin
  PXXFree(p);
end;

function __pxx_realloc(p: Pointer; n: NativeInt): Pointer;
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

{ clock_gettime syscall number per target (mirrors baseunix.pas SysClockGettime).
  riscv32 omitted intentionally — no lua/sqlite test exercises time on it, so it
  falls through to the 0 stub rather than risking the rv32 time64 ABI. }
function SysClockGettimeNr: Integer;
begin
  Result := -1;
  {$ifdef CPUX86_64} Result := 228; {$endif}
  {$ifdef CPU_I386}  Result := 265; {$endif}
  {$ifdef CPU_AARCH64} Result := 113; {$endif}
  {$ifdef CPU_ARM32} Result := 263; {$endif}
end;

type
  TKernelTimeSpec2 = record
    Sec:  NativeInt;
    Nsec: NativeInt;
  end;

function __pxx_time: Int64;
var ts: TKernelTimeSpec2; n: Integer; r: Int64;
begin
  Result := 0;
  n := SysClockGettimeNr;
  if n = -1 then Exit;
  r := __pxxrawsyscall(n, 0, Int64(@ts), 0, 0, 0, 0); { 0 = CLOCK_REALTIME }
  if r = 0 then Result := ts.Sec;
end;

function __pxx_clock: Int64;
var ts: TKernelTimeSpec2; n: Integer; r: Int64;
begin
  Result := 0;
  n := SysClockGettimeNr;
  if n = -1 then Exit;
  { 2 = CLOCK_PROCESS_CPUTIME_ID; report microseconds (CLOCKS_PER_SEC=1e6). }
  r := __pxxrawsyscall(n, 2, Int64(@ts), 0, 0, 0, 0);
  if r = 0 then Result := Int64(ts.Sec) * 1000000 + Int64(ts.Nsec) div 1000;
end;

procedure FillStatBuf(const info: TPalFileStat; sb: PPxxStatBuf);
begin
  sb^.Size    := info.Size;
  sb^.MTime   := info.MTimeSec;
  sb^.Ino     := info.Ino;
  sb^.Dev     := info.Dev;
  sb^.Blocks  := info.Blocks;
  sb^.Mode    := info.Mode;
  sb^.BlkSize := info.BlkSize;
end;

function __pxx_fstat(fd: Integer; sb: PPxxStatBuf): Integer;
var info: TPalFileStat;
begin
  Result := PalFstat(fd, info);
  if Result >= 0 then FillStatBuf(info, sb);
end;

function __pxx_stat(path: PChar; sb: PPxxStatBuf): Integer;
var info: TPalFileStat;
begin
  Result := PalStat(path, info);
  if Result >= 0 then FillStatBuf(info, sb);
end;

function __pxx_lstat(path: PChar; sb: PPxxStatBuf): Integer;
var info: TPalFileStat;
begin
  Result := PalLstat(path, info);
  if Result >= 0 then FillStatBuf(info, sb);
end;

function __pxx_fcntl(fd, cmd: Integer; arg: Int64): Integer;
begin
  Result := PalFcntl(fd, cmd, arg);
end;

function __pxx_fsync(fd: Integer): Integer;
begin
  Result := PalFsync(fd);
end;

function __pxx_fchmod(fd, mode: Integer): Integer;
begin
  Result := PalFchmod(fd, mode);
end;

function __pxx_mkdir(path: PChar; mode: Integer): Integer;
begin
  Result := PalMkdir(path, mode);
end;

function __pxx_getpid: Integer;
begin
  Result := PalGetpid;
end;

{ Returns path length incl. NUL, or -errno (PAL passes the raw syscall result). }
function __pxx_getcwd(buf: PChar; size: Integer): Integer;
begin
  Result := PalGetcwd(buf, size);
end;

function __pxx_nanosleep(sec, nsec: Int64): Integer;
begin
  Result := PalNanosleep(sec, nsec);
end;

function __pxx_utimes(path: PChar; atimeSec, mtimeSec: Int64): Integer;
begin
  Result := PalUtimes(path, atimeSec, mtimeSec);
end;

function __pxx_realtime(secOut, usecOut: Pointer): Integer;
var sec, nsec: Int64;
begin
  Result := PalRealtime(sec, nsec);
  PInt64(secOut)^ := sec;
  PInt64(usecOut)^ := nsec div 1000;
end;

end.
