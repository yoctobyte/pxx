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
    { Appended so the fields above keep their offsets — this record's layout is
      an ABI shared with lib/crtl/src/sys/stat.c's struct __pxx_statbuf, and the
      two must stay in step. }
    Nlink:   Int64;
    Rdev:    Int64;
    ATime:   Int64;
    CTime:   Int64;
    Uid:     Integer;
    Gid:     Integer;
  end;

function __pxx_fstat(fd: Integer; sb: PPxxStatBuf): Integer;
function __pxx_stat(path: PChar; sb: PPxxStatBuf): Integer;
function __pxx_lstat(path: PChar; sb: PPxxStatBuf): Integer;
function __pxx_fcntl(fd, cmd: Integer; arg: Int64): Integer;
function __pxx_fsync(fd: Integer): Integer;
{ dup/dup2 for crtl. PalDup2 already existed; dup(oldFd) is expressed as
  "lowest free descriptor", which the PAL has no primitive for, so it is
  fcntl(F_DUPFD, 0) — the same thing dup() is defined to be. }
function __pxx_chdir(path: PChar): Integer;
function __pxx_symlink(target, linkpath: PChar): Integer;
function __pxx_link(oldPath, newPath: PChar): Integer;
function __pxx_dup(oldFd: Integer): Integer;
function __pxx_dup2(oldFd, newFd: Integer): Integer;
function __pxx_fchmod(fd, mode: Integer): Integer;
function __pxx_chmod(path: PChar; mode: Integer): Integer;
function __pxx_umask(mask: Integer): Integer;
function __pxx_ftruncate(fd: Integer; length: Int64): Integer;
function __pxx_access(path: PChar; mode: Integer): Integer;
function __pxx_fchown(fd, owner, group: Integer): Integer;
function __pxx_isatty(fd: Integer): Integer;
function __pxx_ioctl(fd: Integer; req: NativeInt; argp: Pointer): Integer;
function __pxx_poll(fds: Pointer; nfds: Integer; timeoutMs: Integer): Integer;
function __pxx_mmap_anon_prot(length: Int64; prot: Integer): Pointer;
function __pxx_mprotect(addr: Pointer; length: Int64; prot: Integer): Integer;
function __pxx_munmap(addr: Pointer; length: Int64): Integer;
function __pxx_getuid: Integer;
function __pxx_getgid: Integer;
function __pxx_getegid: Integer;
function __pxx_getppid: Integer;
function __pxx_pipe2(fds: Pointer; flags: Integer): Integer;
function __pxx_kill(pid, sig: Integer): Integer;
function __pxx_geteuid: Integer;
function __pxx_readlink(path: PChar; buf: Pointer; bufsz: Integer): Integer;
function __pxx_mkdir(path: PChar; mode: Integer): Integer;
function __pxx_rmdir(path: PChar): Integer;
function __pxx_getpid: Integer;
function __pxx_getcwd(buf: PChar; size: Integer): Integer;
function __pxx_nanosleep(sec, nsec: Int64): Integer;
function __pxx_utimes(path: PChar; atimeSec, mtimeSec: Int64): Integer;
{ fills two Int64 out-slots the C gettimeofday veneer narrows into struct timeval }
function __pxx_realtime(secOut, usecOut: Pointer): Integer;
function __pxx_clock_gettime(clkId: Integer; secOut, nsecOut: Pointer): Integer;

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

{ exit_group's syscall number is PER TARGET, like SysClockGettimeNr below. It
  was hardcoded to 231 — x86-64's number. On i386, 231 is fgetxattr: C's
  `exit(3)` quietly failed an xattr call, returned, and the process wound up
  exiting 0, so every i386 program that reported failure through exit() reported
  SUCCESS instead. (`return 3` from main was unaffected — that path is the entry
  stub's own exit, which is why nothing caught it.) arm32's 231 is fgetxattr
  too; aarch64/riscv32 share 94. Found by tools/gcc_diff_probe.sh --target i386. }
function SysExitGroupNr: Integer;
begin
  Result := -1;
  {$ifdef CPUX86_64} Result := 231; {$endif}
  {$ifdef CPU_I386}  Result := 252; {$endif}
  {$ifdef CPU_AARCH64} Result := 94; {$endif}
  {$ifdef CPU_ARM32} Result := 248; {$endif}
  {$ifdef CPU_RISCV32} Result := 94; {$endif}
end;

{ Per-target `exit` syscall, the single-thread fallback when exit_group is not
  known: x86-64 60, i386 1, arm32 1, aarch64/riscv32 93. }
function SysExitNr: Integer;
begin
  Result := -1;
  {$ifdef CPUX86_64} Result := 60; {$endif}
  {$ifdef CPU_I386}  Result := 1; {$endif}
  {$ifdef CPU_AARCH64} Result := 93; {$endif}
  {$ifdef CPU_ARM32} Result := 1; {$endif}
  {$ifdef CPU_RISCV32} Result := 93; {$endif}
end;

procedure __pxx_exit(code: Integer);
var r: Int64; n: Integer;
begin
  { exit_group(code) — terminate the process directly (PAL posix). Assigned form
    because __pxxrawsyscall is intercepted in expression context; the syscall
    never returns, so r is unused. If exit_group somehow does return, fall back
    to exit(2) rather than letting the caller run on with the process alive. }
  n := SysExitGroupNr;
  if n >= 0 then r := __pxxrawsyscall(n, code, 0, 0, 0, 0, 0);
  n := SysExitNr;
  if n >= 0 then r := __pxxrawsyscall(n, code, 0, 0, 0, 0, 0);
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
  if r = 0 then
    Result := Int64(ts.Sec) * 1000000 + Int64(ts.Nsec) div 1000;
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
  sb^.Nlink   := info.Nlink;
  sb^.Rdev    := info.Rdev;
  sb^.ATime   := info.ATimeSec;
  sb^.CTime   := info.CTimeSec;
  sb^.Uid     := info.Uid;
  sb^.Gid     := info.Gid;
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

function __pxx_chdir(path: PChar): Integer;
begin
  Result := PalChdir(path);
end;

function __pxx_symlink(target, linkpath: PChar): Integer;
begin
  Result := PalSymlink(target, linkpath);
end;

function __pxx_link(oldPath, newPath: PChar): Integer;
begin
  Result := PalLink(oldPath, newPath);
end;

function __pxx_dup2(oldFd, newFd: Integer): Integer;
begin
  Result := PalDup2(oldFd, newFd);
end;

function __pxx_dup(oldFd: Integer): Integer;
{ F_DUPFD = 0: duplicate onto the lowest free descriptor >= the third arg.
  That IS dup()'s definition, so this is the primitive rather than a
  workaround for a missing one. }
begin
  Result := PalFcntl(oldFd, 0, 0);
end;

function __pxx_fchmod(fd, mode: Integer): Integer;
begin
  Result := PalFchmod(fd, mode);
end;

function __pxx_chmod(path: PChar; mode: Integer): Integer;
begin
  Result := PalChmod(path, mode);
end;

function __pxx_umask(mask: Integer): Integer;
begin
  Result := PalUmask(mask);
end;

function __pxx_ftruncate(fd: Integer; length: Int64): Integer;
begin
  Result := PalFtruncate(fd, length);
end;

function __pxx_access(path: PChar; mode: Integer): Integer;
begin
  Result := PalAccess(path, mode);
end;

function __pxx_fchown(fd, owner, group: Integer): Integer;
begin
  Result := PalFchown(fd, owner, group);
end;

function __pxx_geteuid: Integer;
begin
  Result := PalGeteuid;
end;

function __pxx_isatty(fd: Integer): Integer;
{ isatty is the TCGETS ioctl succeeding — that is what libc does, and it is the
  only test that distinguishes a terminal from another character device.
  fstat + S_ISCHR does NOT: /dev/null is a character device and is not a tty,
  so the fstat version answers 1 for redirected output and every "am I
  interactive" branch takes the wrong path. TCGETS is 0x5401 on every target pxx
  builds for (asm-generic/ioctls.h; only mips/alpha/sparc/powerpc differ). }
var termios: array[0..63] of Byte;   { struct termios is 60 bytes on Linux }
begin
  if PalIoctl(fd, $5401, @termios[0]) = 0 then Result := 1 else Result := 0;
end;

function __pxx_ioctl(fd: Integer; req: NativeInt; argp: Pointer): Integer;
{ The general form of what __pxx_isatty above does for the single TCGETS case.
  PalIoctl has always been a fully general ioctl syscall bridge — the crtl
  ticket's claim that a new PAL entry was needed was wrong, so measure before
  believing a ticket's scoping line. Returns the raw PAL result (negative errno
  on failure); the crtl wrapper does the -1/errno conversion. }
begin
  Result := PalIoctl(fd, req, argp);
end;

function __pxx_poll(fds: Pointer; nfds: Integer; timeoutMs: Integer): Integer;
{ C's poll(). The caller's `struct pollfd` array goes straight through to the
  PAL — the layout is identical — so revents are written back in the caller's
  own memory. Returns the raw PAL result (ready count, 0 on timeout, negative
  errno on failure); the crtl wrapper does the -1/errno conversion.

  NOT a loop over __pxx_isatty-style single polls: a set poll must block on the
  whole set, which is why this needed a new PAL entry (PalPollSet) rather than
  reusing the per-handle PalPoll. }
begin
  Result := PalPollSet(fds, nfds, timeoutMs);
end;

function __pxx_mmap_anon_prot(length: Int64; prot: Integer): Pointer;
{ C's mmap for the ANONYMOUS case, which is what a JIT needs: tcc -run maps
  pages, writes code in and jumps. File-backed mmap stays refused in crtl. }
begin
  Result := PalMmapAnonProt(length, prot);
end;

function __pxx_mprotect(addr: Pointer; length: Int64; prot: Integer): Integer;
begin
  Result := PalMprotect(addr, length, prot);
end;

function __pxx_munmap(addr: Pointer; length: Int64): Integer;
begin
  Result := PalMunmap(addr, length);
end;

function __pxx_getuid: Integer;
begin
  Result := PalGetuid;
end;

function __pxx_getgid: Integer;
begin
  Result := PalGetgid;
end;

function __pxx_getegid: Integer;
begin
  Result := PalGetegid;
end;

function __pxx_getppid: Integer;
begin
  Result := PalGetppid;
end;

function __pxx_pipe2(fds: Pointer; flags: Integer): Integer;
{ PalPipe2 takes an open array; C hands us a bare int[2], so copy across rather
  than alias — the two layouts agree today but a var-open-array is not an ABI. }
var local: array[0..1] of Integer; rc: Integer; p: ^Integer;
begin
  local[0] := -1; local[1] := -1;
  rc := PalPipe2(local, flags);
  if rc >= 0 then
  begin
    p := fds;
    p^ := local[0];
    p := Pointer(Int64(fds) + SizeOf(Integer));
    p^ := local[1];
  end;
  Result := rc;
end;

function __pxx_kill(pid, sig: Integer): Integer;
begin
  Result := PalKill(pid, sig);
end;

function __pxx_readlink(path: PChar; buf: Pointer; bufsz: Integer): Integer;
begin
  Result := PalReadlink(path, buf, bufsz);
end;

function __pxx_mkdir(path: PChar; mode: Integer): Integer;
begin
  Result := PalMkdir(path, mode);
end;

function __pxx_rmdir(path: PChar): Integer;
begin
  Result := PalRmdir(path);
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

{ General clock_gettime for crtl. Without it, C's clock_gettime was DECLARED in
  <time.h> but had no body, so the C frontend's unresolved-extern fallback bound
  it to libc.so.6: the program ran correctly on a glibc host while quietly
  turning a self-contained static binary into a dynamic one (readelf showed the
  NEEDED entry). That is the failure mode the crtl declaration probe exists to
  catch — "it works" and "it links libc-free" are different questions.
  Nanosecond precision, unlike __pxx_realtime which narrows to microseconds. }
function __pxx_clock_gettime(clkId: Integer; secOut, nsecOut: Pointer): Integer;
var ts: TKernelTimeSpec2; n: Integer; r: Int64;
begin
  Result := -1;
  PInt64(secOut)^ := 0;
  PInt64(nsecOut)^ := 0;
  n := SysClockGettimeNr;
  if n = -1 then Exit;
  r := __pxxrawsyscall(n, clkId, Int64(@ts), 0, 0, 0, 0);
  if r <> 0 then Exit;
  { implicit widening, NOT Int64(ts.Sec) — see the __pxx_clock note above and
    bug-a-explicit-int64-cast-of-nativeint-does-not-extend-on-32bit }
  PInt64(secOut)^ := ts.Sec;
  PInt64(nsecOut)^ := ts.Nsec;
  Result := 0;
end;

end.
