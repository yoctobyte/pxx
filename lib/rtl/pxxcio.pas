{ SPDX-License-Identifier: Zlib }
unit pxxcio;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
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

uses platform, platform_types, builtinheap;

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
function __pxx_send(fd: Integer; buf: Pointer; len: Integer; flags: Integer): Int64;
function __pxx_recv(fd: Integer; buf: Pointer; len: Integer; flags: Integer): Int64;
function __pxx_sendto_ipv4(fd: Integer; buf: Pointer; len: Integer; host: LongWord; port: Integer; flags: Integer): Int64;
function __pxx_recvfrom_ipv4(fd: Integer; buf: Pointer; len: Integer; outHost, outPort: Pointer; flags: Integer): Int64;
function __pxx_shutdown(fd, how: Integer): Integer;
function __pxx_socket_close(fd: Integer): Integer;
function __pxx_getsockname_ipv4(fd: Integer; outHost, outPort: Pointer): Integer;
function __pxx_getpeername_ipv4(fd: Integer; outHost, outPort: Pointer): Integer;
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

{ C atexit support. The handler TABLE lives here, in Pascal, and not in
  lib/crtl/src/stdlib.c, for one reason: a C program's normal exit is a plain
  `return` from main, which the entry stub turns into
  `call main; __pxx_run_finalizers; exit_group(retval)` — and that runner walks
  UNIT FINALIZATION sections, a Pascal-only hook. crtl calls into Pascal (see the
  unit note above), never the other way round, so a table on the C side could be
  drained by exit() and would be silently skipped on the return path. Keeping it
  here lets ONE list serve both.
  __pxx_atexit records a handler (0 = ok, -1 = full/nil, as C's atexit);
  __pxx_atexit_run drains it LIFO and is called from crtl's exit() as well as
  from this unit's finalization, whichever comes first — the drain pops, so the
  second caller finds it empty. _Exit and abort deliberately do NOT call it. }
function __pxx_atexit(fn: Pointer): Integer;
procedure __pxx_atexit_run;

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
function __pxx_sync: Integer;
function __pxx_setsid: Integer;
function __pxx_getgroups(count: Integer; list: Pointer): Integer;
function __pxx_getpriority(which, who: Integer): Integer;
function __pxx_setpriority(which, who, prio: Integer): Integer;
function __pxx_getsid(pid: Integer): Integer;
function __pxx_syscall(num, a1, a2, a3, a4, a5, a6: NativeInt): NativeInt;
function __pxx_setpgid(pid, pgid: Integer): Integer;
function __pxx_getpgid(pid: Integer): Integer;
function __pxx_alarm(seconds: LongWord): Integer;
function __pxx_sethostname(name: PChar; len: Integer): Integer;
function __pxx_setgroups(count: Integer; list: Pointer): Integer;
function __pxx_sigtimedwait(setPtr: Pointer; setSize, sec, nsec: Integer): Integer;
function __pxx_sigprocmask(how: Integer; setPtr, oldSetPtr: Pointer; setSize: Integer): Integer;
function __pxx_clock_settime(clockId: Integer; sec, nsec: Int64): Integer;
function __pxx_utimensat(dirFd: Integer; path: PChar;
                         aSec, aNsec, mSec, mNsec: Int64;
                         flags: Integer): Integer;
function __pxx_fsync(fd: Integer): Integer;
function __pxx_fdatasync(fd: Integer): Integer;
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
function __pxx_chown(path: PChar; owner, group: Integer): Integer;
function __pxx_lchown(path: PChar; owner, group: Integer): Integer;
function __pxx_prlimit(resource: Integer; newLim, oldLim: Pointer): Integer;
function __pxx_uname(buf: Pointer): Integer;
function __pxx_times(buf: Pointer): Int64;
function __pxx_truncate(path: PChar; length: Int64): Integer;
function __pxx_mknod(path: PChar; mode: Integer; dev: Int64): Integer;
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
function __pxx_execve(path: PChar; argv, envp: Pointer): Integer;
function __pxx_kill(pid, sig: Integer): Integer;

{ C SIGNAL DISPOSITIONS. crtl's signal()/sigaction() were LINK-ONLY STUBS that
  returned 0 and installed nothing (bug-b-crtl-signal-and-sigaction-report-
  success-and-install-nothing): a caller checking the documented error path saw
  none, ran on with the kernel's default disposition, and was killed by the
  first signal it had written a handler for. Returning 0 is what made it a
  WRONG ANSWER rather than a missing feature.

  `handler` is the C function pointer, or the two sentinels crtl's <signal.h>
  spells: 0 = SIG_DFL, 1 = SIG_IGN. Returns 0, or a NEGATIVE errno the C side
  turns into -1/errno, matching every other bridge in this file.

  It is here and not re-implemented inside crtl because rt_sigaction, the
  restorer trampoline and the altstack policy already exist ONCE, in the
  compiler's signal runtime. A second copy in C would be the second mechanism
  for one concept that root-cause-over-microfix.md is about. }
function __pxx_c_signal(sig: Integer; handler: Pointer): Integer;
function __pxx_fork: Integer;
function __pxx_wait4(pid: Integer; wstatus: Pointer; options: Integer; rusage: Pointer): Integer;
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
{ getdents64: fills the caller's buffer with kernel linux_dirent64 records and
  returns the byte count, 0 at end of directory, or -errno. crtl's opendir /
  readdir sit directly on this — the record layout it returns IS what
  <dirent.h> declares, so nothing translates. }
function __pxx_getdents64(fd: Integer; buf: Pointer; len: Integer): Int64;

implementation

type
  PLongWord = ^LongWord;
  PInteger = ^Integer;
  PInt64 = ^Int64;

function __pxx_write(fd: Integer; buf: Pointer; n: Int64): Int64;
begin
  Result := PalWrite(fd, buf, Integer(n));
end;

{ execve replaces the process image; on SUCCESS it does not return at all, so
  every return is a failure and carries a negative errno. }
function __pxx_execve(path: PChar; argv, envp: Pointer): Integer;
begin
  Result := PalExecve(path, argv, envp);
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

{ THE `flags' ARGUMENT IS THE C SIDE OF
  bug-b-fprecv-and-fpsend-silently-discard-their-flags-argument, and crtl had
  the SAME defect as sockets.pas from the same cause -- lib/crtl/src/netinet/in.c
  said `(void)flags;' in send, recv, sendto and recvfrom. The ticket named only
  the Pascal arm. Fixing one and not the other is exactly what
  devdocs/dev/normalise-dont-special-case.md means by the second path staying
  broken, so both go through this one veneer.

  IT TAKES LINUX'S NUMBERS, not the PAL's, because its callers are C programs
  holding <sys/socket.h>'s MSG_*. The conversion is PalMsgFromPosix, shared
  with sockets.pas. -EINVAL for a bit the PAL does not carry -- the C wrapper
  turns that into -1/EINVAL like any other PAL error. }
function __pxx_send(fd: Integer; buf: Pointer; len: Integer; flags: Integer): Int64;
var f: Integer;
begin
  if not PalMsgFromPosix(flags, f) then begin Result := PAL_ERR_INVALID; Exit; end;
  Result := PalSend(fd, buf, len, f);
end;

function __pxx_recv(fd: Integer; buf: Pointer; len: Integer; flags: Integer): Int64;
var f: Integer;
begin
  if not PalMsgFromPosix(flags, f) then begin Result := PAL_ERR_INVALID; Exit; end;
  Result := PalRecv(fd, buf, len, f);
end;

function __pxx_sendto_ipv4(fd: Integer; buf: Pointer; len: Integer; host: LongWord; port: Integer; flags: Integer): Int64;
var f: Integer;
begin
  if not PalMsgFromPosix(flags, f) then begin Result := PAL_ERR_INVALID; Exit; end;
  Result := PalSendToIpv4(fd, buf, len, host, port, f);
end;

function __pxx_recvfrom_ipv4(fd: Integer; buf: Pointer; len: Integer; outHost, outPort: Pointer; flags: Integer): Int64;
var host: LongWord; port: Integer; f: Integer;
begin
  if not PalMsgFromPosix(flags, f) then begin Result := PAL_ERR_INVALID; Exit; end;
  Result := PalRecvFromIpv4(fd, buf, len, host, port, f);
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

function __pxx_getpeername_ipv4(fd: Integer; outHost, outPort: Pointer): Integer;
{ The peer side of the pair above. PalGetPeerNameIpv4 has been here all along;
  only the C bridge was missing, which is why libbb/xconnect.c's get_peer_lsa
  had no getpeername to name. }
var host: LongWord; port: Integer;
begin
  Result := PalGetPeerNameIpv4(fd, host, port);
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

{ THROUGH THE PAL, and the incident below is why the numbers no longer live here.

  exit_group's number is PER TARGET, and getting it wrong here was SILENT. It
  was hardcoded to 231 -- x86-64's. On i386, 231 is fgetxattr: C's `exit(3)`
  quietly failed an xattr call, returned, and the process wound up exiting 0, so
  every i386 program that reported failure through exit() reported SUCCESS
  instead. (`return 3` from main was unaffected -- that path is the entry stub's
  own exit, which is why nothing caught it.) The repair at the time was a second
  per-target table, in this file. platform.pas already had a table for the same
  targets; a private copy is how the first one went wrong and is no defence
  against the second.

  The wasm32 half is the same shape as Sleep's: `if n >= 0 then` reads as a soft
  failure and is a RUNTIME test in front of an instruction that is still EMITTED,
  so a backend with no syscall lowering refused the whole BODY. PalExit reaches
  wasi's proc_exit, which is a real exit rather than a defined failure.

  Both exit_group AND exit still happen, in that order; that fallback now lives
  in the posix backend beside the numbers it needs. }
procedure __pxx_exit(code: Integer);
var ignored: Integer;
begin
  ignored := PalExit(code);
end;

type
  TPxxAtExitProc = procedure;
  PPxxCodePtr = ^Pointer;

const
  { C requires an implementation to accept at least 32 registrations (C99
    7.20.4.2), but glibc grows without bound, so a fixed cap is an observable
    divergence from the oracle: 100 registrations answer 0 under gcc and -1 here.
    The list therefore grows on the shared PXXAlloc heap (the same one malloc
    rides), starting at this many slots and doubling. }
  PXX_ATEXIT_INITIAL = 32;

var
  gAtExitFns: Pointer;      { PXXAlloc'd array of code addresses, gAtExitCap wide }
  gAtExitCap: Integer;
  gAtExitCount: Integer;

{ Slot address is spelled inline at both use sites rather than through an
  AtExitSlot(i) helper, which is what this wants to be: `AtExitSlot(i)^ := fn`
  compiles and silently stores NOTHING —
  [[bug-a-assignment-through-a-pointer-returned-by-a-function-call-is-dropped]].
  Reading through the call result is fine, and so is the cast expression used
  here; only the call-result-as-assignment-target arm is broken. Restore the
  helper when that ticket closes. }
function __pxx_atexit(fn: Pointer): Integer;
var newCap: Integer; p: Pointer;
begin
  if fn = nil then
  begin
    Result := -1;
    Exit;
  end;
  if gAtExitCount >= gAtExitCap then
  begin
    if gAtExitCap = 0 then newCap := PXX_ATEXIT_INITIAL else newCap := gAtExitCap * 2;
    p := PXXRealloc(gAtExitFns, newCap * SizeOf(Pointer), SizeOf(Pointer));
    if p = nil then
    begin
      { Out of memory is the ONLY failure now, and C's atexit reports it the
        same way — nonzero. The existing list is untouched. }
      Result := -1;
      Exit;
    end;
    gAtExitFns := p;
    gAtExitCap := newCap;
  end;
  PPxxCodePtr(NativeInt(gAtExitFns) + gAtExitCount * SizeOf(Pointer))^ := fn;
  gAtExitCount := gAtExitCount + 1;
  Result := 0;
end;

procedure __pxx_atexit_run;
var p: TPxxAtExitProc;
begin
  { LAST registered runs FIRST (C99 7.20.4.3). Popping as we go is what makes
    this safe to call twice and safe to re-enter: a handler that itself calls
    exit() re-enters through crtl's exit(), finds the remaining prefix, and the
    ones already run are gone rather than running again. }
  while gAtExitCount > 0 do
  begin
    gAtExitCount := gAtExitCount - 1;
    p := TPxxAtExitProc(PPxxCodePtr(NativeInt(gAtExitFns) + gAtExitCount * SizeOf(Pointer))^);
    p;
  end;
end;

{ THE CLOCK BODIES, all three through PalClockGetTime.

  This unit used to carry its own clock_gettime number table, which -- like the
  exit one above -- omitted riscv32 ON PURPOSE: "no lua/sqlite test exercises
  time on it, so it falls through to the 0 stub rather than risking the rv32
  time64 ABI". That was right about the risk and it is exactly what hid the real
  defect: the PAL's own riscv32 clock is -ENOSYS
  (bug-b-palnanosleep-answers-enosys-on-riscv32-because-rv32-has-no-nanosleep-syscall,
  measured across the whole time family). Two silences stacked, and removing
  this one makes the other reachable. riscv32 answers 0 either way today.

  The explicit `Int64(ts.Sec)` casts that were here are gone rather than fixed:
  PalClockGetTime hands back Int64 out-parameters, so there is no NativeInt to
  widen and bug-a-explicit-int64-cast-of-nativeint-does-not-extend-on-32bit
  cannot be reached from this file at all. }
function __pxx_time: Int64;
var sec, nsec: Int64;
begin
  Result := 0;
  if PalClockGetTime(0, sec, nsec) = 0 then    { 0 = CLOCK_REALTIME }
    Result := sec;
end;

function __pxx_clock: Int64;
var sec, nsec: Int64;
begin
  Result := 0;
  { 2 = CLOCK_PROCESS_CPUTIME_ID; report microseconds (CLOCKS_PER_SEC=1e6). }
  if PalClockGetTime(2, sec, nsec) = 0 then
    Result := sec * 1000000 + nsec div 1000;
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

function __pxx_fdatasync(fd: Integer): Integer;
begin
  Result := PalFdatasync(fd);
end;

function __pxx_sync: Integer;
begin
  Result := PalSync;
end;

function __pxx_setsid: Integer;
begin
  Result := PalSetsid;
end;

function __pxx_getgroups(count: Integer; list: Pointer): Integer;
begin
  Result := PalGetGroups(count, list);
end;

function __pxx_getpriority(which, who: Integer): Integer;
begin
  Result := PalGetPriority(which, who);
end;

function __pxx_setpriority(which, who, prio: Integer): Integer;
begin
  Result := PalSetPriority(which, who, prio);
end;

function __pxx_getsid(pid: Integer): Integer;
begin
  Result := PalGetSid(pid);
end;

function __pxx_syscall(num, a1, a2, a3, a4, a5, a6: NativeInt): NativeInt;
begin
  Result := PalRawSyscall(num, a1, a2, a3, a4, a5, a6);
end;

function __pxx_setpgid(pid, pgid: Integer): Integer;
begin
  Result := PalSetPgid(pid, pgid);
end;

function __pxx_getpgid(pid: Integer): Integer;
begin
  Result := PalGetPgid(pid);
end;

function __pxx_alarm(seconds: LongWord): Integer;
begin
  Result := PalAlarm(seconds);
end;

function __pxx_sethostname(name: PChar; len: Integer): Integer;
begin
  Result := PalSetHostname(name, len);
end;

function __pxx_setgroups(count: Integer; list: Pointer): Integer;
begin
  Result := PalSetGroups(count, list);
end;

function __pxx_sigtimedwait(setPtr: Pointer; setSize, sec, nsec: Integer): Integer;
begin
  Result := PalSigTimedWait(setPtr, setSize, sec, nsec);
end;

function __pxx_sigprocmask(how: Integer; setPtr, oldSetPtr: Pointer; setSize: Integer): Integer;
begin
  Result := PalSigProcMask(how, setPtr, oldSetPtr, setSize);
end;

function __pxx_clock_settime(clockId: Integer; sec, nsec: Int64): Integer;
begin
  Result := PalClockSetTime(clockId, sec, nsec);
end;

function __pxx_utimensat(dirFd: Integer; path: PChar;
                         aSec, aNsec, mSec, mNsec: Int64;
                         flags: Integer): Integer;
begin
  Result := PalUtimensat(dirFd, path, aSec, aNsec, mSec, mNsec, flags);
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

function __pxx_chown(path: PChar; owner, group: Integer): Integer;
begin
  Result := PalChown(path, owner, group);
end;

function __pxx_lchown(path: PChar; owner, group: Integer): Integer;
begin
  Result := PalLchown(path, owner, group);
end;

function __pxx_truncate(path: PChar; length: Int64): Integer;
begin
  Result := PalTruncate(path, length);
end;

function __pxx_times(buf: Pointer): Int64;
begin
  Result := PalTimes(buf);
end;

function __pxx_uname(buf: Pointer): Integer;
begin
  Result := PalUname(buf);
end;

function __pxx_prlimit(resource: Integer; newLim, oldLim: Pointer): Integer;
begin
  Result := PalPrlimit(resource, newLim, oldLim);
end;

function __pxx_mknod(path: PChar; mode: Integer; dev: Int64): Integer;
begin
  Result := PalMknod(path, mode, dev);
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

{ THE WHOLE C SIGNAL BRIDGE IS BEHIND PXX_HAS_SIGNALS, and the else-arm below
  REFUSES rather than silently doing nothing -- which is the entire bug it
  replaces. A build with no signal runtime must TELL a C caller so, not hand it
  a success it will act on. THE SET IS NOT ENUMERATED HERE ON PURPOSE -- the
  define below IS the enumeration, and a list in a comment is what goes stale.
  (It was ESP platforms and windowed xtensa when this was written; wasm32 joined
  the day after, 2466279ad, when TargetHasSignalRuntime got the arm it had never
  had. Had this comment been the guard, it would have been wrong within a day.)

  PXX_HAS_SIGNALS is a compiler define (lexer.inc) reading the one predicate
  TargetHasSignalRuntime, so this guard cannot go stale the way signals.pas's
  `{$ifndef CPUX86_64}` did -- that one named an ARCH for a capability, kept
  refusing four targets for four days after they gained it, and its message
  read as current the whole time. }
{$ifdef PXX_HAS_SIGNALS}
const
  PXX_CSIG_MAX = 64;
  PXX_CSIG_DFL = 0;
  PXX_CSIG_IGN = 1;
  PXX_EINVAL   = 22;

type
  TCSignalHandler = procedure(sig: Longint); cdecl;

var
  CSigHandlers: array[1..PXX_CSIG_MAX] of Pointer;

{ One parameterless hook serves every signal; __pxxSigNum says which. The bounds
  check is not defensive noise -- an unwritten slot reads as a number the table
  does not cover, and dispatching that is worse than dropping it.

  Same shape as signals.pas's trampoline, deliberately: that one is the FPC
  surface over this hook and this is the C surface. Two SURFACES over one
  mechanism, not two mechanisms. }
procedure CSigTrampoline;
var n: Longint; h: TCSignalHandler;
begin
  n := __pxxSigNum;
  if (n >= 1) and (n <= PXX_CSIG_MAX) then
    if (CSigHandlers[n] <> Pointer(PXX_CSIG_DFL)) and
       (CSigHandlers[n] <> Pointer(PXX_CSIG_IGN)) then
    begin
      h := TCSignalHandler(CSigHandlers[n]);
      h(n);
    end;
end;

function __pxx_c_signal(sig: Integer; handler: Pointer): Integer;
begin
  { SIGKILL (9) and SIGSTOP (19) cannot be caught or ignored. The kernel refuses
    too; refusing here means the answer does not depend on which of the two
    layers happens to notice first. }
  if (sig < 1) or (sig > PXX_CSIG_MAX) or (sig = 9) or (sig = 19) then
  begin
    Result := -PXX_EINVAL;
    Exit;
  end;

  if handler = Pointer(PXX_CSIG_IGN) then
  begin
    { A real ignore through rt_sigaction, not a disposition that merely looks
      like one. Mapping SIG_IGN onto SIG_DFL would be invisible until the signal
      arrived and then killed the process. }
    CSigHandlers[sig] := Pointer(PXX_CSIG_IGN);
    Result := PalIgnoreSignal(sig);
    if Result > 0 then Result := -Result;
  end
  else if handler = Pointer(PXX_CSIG_DFL) then
  begin
    CSigHandlers[sig] := Pointer(PXX_CSIG_DFL);
    SetSignalHandler(sig, nil);         { revert on next delivery }
    Result := 0;
  end
  else
  begin
    { Store BEFORE installing: the signal can arrive between the two. }
    CSigHandlers[sig] := handler;
    SetSignalHandler(sig, @CSigTrampoline);
    Result := 0;
  end;
end;
{$else}
function __pxx_c_signal(sig: Integer; handler: Pointer): Integer;
begin
  { -ENOSYS, never 0. The C side turns this into -1/ENOSYS, so a caller that
    checks -- which is what careful code does -- finds out HERE instead of dying
    on the first delivery. }
  Result := -38;
end;
{$endif}


{ fork(2) for crtl. PalFork was called PalVfork until today and its body was
  always a real fork -- see the note at PalBackendFork. crtl's fork() had been
  an ENOSYS stub purely because the OLD NAME said the entry was a vfork, so
  busybox ash reported `can't fork' against a PAL that could. }
function __pxx_fork: Integer;
begin
  Result := PalFork;
end;

{ wait4(2), the syscall waitpid() is expressed over. PalWait4 already existed
  and subprocess.pas already used it; nothing had bridged it to C, because
  crtl's waitpid() returned ECHILD on the reasoning that "with fork()
  unavailable there are no children" -- true when written and false the moment
  fork works. The pair moves together. }
function __pxx_wait4(pid: Integer; wstatus: Pointer; options: Integer; rusage: Pointer): Integer;
begin
  Result := PalWait4(pid, wstatus, options, rusage);
end;

function __pxx_readlink(path: PChar; buf: Pointer; bufsz: Integer): Integer;
begin
  Result := PalReadlink(path, buf, bufsz);
end;

{ The PAL has had PalGetDents64 all along; crtl was about to ship an ENOSYS
  opendir on the assumption that it did not. Same trap PalIoctl's note records
  a few hundred lines below: measure the PAL before believing a scoping line
  that says an entry is missing. }
function __pxx_getdents64(fd: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := PalGetDents64(fd, buf, len);
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
var sec, nsec: Int64;
begin
  Result := -1;
  PInt64(secOut)^ := 0;
  PInt64(nsecOut)^ := 0;
  if PalClockGetTime(clkId, sec, nsec) <> 0 then Exit;
  PInt64(secOut)^ := sec;
  PInt64(nsecOut)^ := nsec;
  Result := 0;
end;

finalization
  { The `return`-from-main path: the C entry stub calls __pxx_run_finalizers
    before exit_group, and this is the only hook it walks
    (feature-c-entry-stub-must-run-finalizers, pinned v256). crtl's exit() drains
    first and leaves the list empty, so this is the branch that carries a plain
    return — the one a C-side table could not have served. }
  __pxx_atexit_run;

end.
