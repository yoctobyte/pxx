unit fbsdabi;

{ The Linux syscall ABI on a FreeBSD kernel -- a small linuxulator INSIDE the
  program, so that pxx output for FreeBSD keeps the libc-free, raw-syscall
  identity Linux output has.

  WHY TRANSLATE RATHER THAN PORT EVERY CALL SITE. Every kernel entry pxx emits
  -- the compiler's own (startup, heap, signals, TLS, the sys* intrinsics) and
  the RTL's (~190 __pxxrawsyscall sites, 98 distinct calls) -- is written
  against the Linux ABI: Linux numbers, Linux flag bits, Linux structs, and
  Linux's -errno return. Under --os=freebsd they all funnel through ONE shared
  thunk (EmitLibcSyscallThunk, symtab.inc), the same seam --rtl-libc uses, and
  the thunk calls PXXFbsdSyscall below with the Linux number and arguments.
  This unit maps the number, rewrites the arguments and structs that differ,
  issues the real FreeBSD syscall, and maps FreeBSD's errno back to Linux's.
  So all FreeBSD knowledge lives in this file, the RTL is untouched, and the
  Linux default build is byte-identical.

  CONSTANTS ARE MEASURED, NOT REMEMBERED: every number here was read from
  FreeBSD 15.1-RELEASE amd64's own headers (/usr/include/sys/syscall.h,
  errno.h, fcntl.h, mman.h, _clock_id.h, x86/sysarch.h) and the struct
  offsets from offsetof() compiled on that system (2026-11-12).

  CONTEXT RULES -- this runs from every syscall site, including before the
  heap and TLS exist, inside signal handlers and in a fresh fork child. So:
  no managed types, no heap, no exceptions, no RTL calls, locals only (plus
  the brk emulation's three globals). And it must never reach IR_SYSCALL
  itself -- that would re-enter the thunk -- which is why the kernel entry is
  the assembler routine FbRawA, whose `syscall` the thunk hook never sees.

  PHASE 1 SCOPE (feature-port-freebsd-native): files, memory, time, process
  basics, TLS, and the two /proc files the runtime reads (environ, exe). Signals (see FbSigEntry), epoll over
  kqueue, sockets, termios and ptys, futex over _umtx_op. Thread CREATION is
  not here: clone is the compiler's stub (thread_emit.inc), which has a
  thr_new leg under --os=freebsd. Anything unmapped answers -ENOSYS. }

interface

function PXXFbsdSyscall(nr, a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl;

implementation

const
  { Linux errno values this unit hands back directly }
  LX_ENOENT = 2;
  LX_EINVAL = 22;
  LX_ENOMEM = 12;
  LX_ENOTTY = 25;
  LX_ENOSYS = 38;

  { FreeBSD amd64 syscall numbers (sys/syscall.h) }
  FB_EXIT = 1; FB_FORK = 2; FB_READ = 3; FB_WRITE = 4; FB_OPEN = 5; FB_CLOSE = 6;
  FB_WAIT4 = 7; FB_UNLINK = 10; FB_CHDIR = 12; FB_CHMOD = 15; FB_GETPID = 20;
  FB_GETUID = 24; FB_GETEUID = 25; FB_ACCESS = 33; FB_SYNC = 36; FB_KILL = 37;
  FB_GETPPID = 39; FB_DUP = 41; FB_GETEGID = 43; FB_GETGID = 47; FB_IOCTL = 54;
  FB_READLINK = 58; FB_EXECVE = 59; FB_UMASK = 60; FB_MUNMAP = 73;
  FB_MPROTECT = 74; FB_MADVISE = 75; FB_DUP2 = 90; FB_FCNTL = 92; FB_FSYNC = 95;
  FB_GETTIMEOFDAY = 116; FB_READV = 120; FB_WRITEV = 121; FB_RENAME = 128;
  FB_MKDIR = 136; FB_RMDIR = 137; FB_SETSID = 147; FB_SYSARCH = 165;
  FB_GETRLIMIT = 194; FB_SETRLIMIT = 195; FB_SYSCTL = 202; FB_POLL = 209;
  FB_CLOCK_GETTIME = 232; FB_CLOCK_GETRES = 234; FB_NANOSLEEP = 240;
  FB_CLOCK_NANOSLEEP = 244; FB_GETCWD = 326; FB_SCHED_YIELD = 331;
  FB_THR_SELF = 432; FB_PREAD = 475; FB_PWRITE = 476; FB_MMAP = 477;
  FB_LSEEK = 478; FB_FTRUNCATE = 480; FB_FACCESSAT = 489; FB_MKDIRAT = 496;
  FB_OPENAT = 499; FB_READLINKAT = 500; FB_RENAMEAT = 501; FB_UNLINKAT = 503;
  FB_PIPE2 = 542; FB_FSTAT = 551; FB_FSTATAT = 552; FB_GETDIRENTRIES = 554;
  FB_GETRANDOM = 563; FB_SIGALTSTACK = 53; FB_SHM_OPEN2 = 571;
  FB_LINK = 9; FB_FCHDIR = 13; FB_CHOWN = 16; FB_SETUID = 23; FB_SYMLINK = 57;
  FB_GETPGRP = 81; FB_SETPGID = 82; FB_SETITIMER = 83; FB_GETITIMER = 86;
  FB_SETPRIORITY = 96; FB_GETPRIORITY = 100; FB_GETRUSAGE = 117;
  FB_FCHOWN = 123; FB_FCHMOD = 124; FB_SETREUID = 126; FB_SETREGID = 127;
  FB_FLOCK = 131; FB_UTIMES = 138; FB_SETGID = 181; FB_GETPGID = 207;
  FB_CLOCK_SETTIME = 233; FB_LCHOWN = 254; FB_GETSID = 310; FB_TRUNCATE = 479;
  FB_FCHMODAT = 490; FB_FCHOWNAT = 491; FB_LINKAT = 495; FB_SYMLINKAT = 502;
  FB_FUTIMENS = 546; FB_UTIMENSAT = 547; FB_FDATASYNC = 550; FB_MKNODAT = 559;
  FB_GETGROUPS = 595; FB_SETGROUPS = 596;
  FB_PREADV = 289; FB_PWRITEV = 290; FB_SELECT = 93; FB_PSELECT = 522;
  FB_PPOLL = 545; FB_STATFS = 555; FB_FSTATFS = 556; FB_POSIX_OPENPT = 504;
  FB_THR_EXIT = 431; FB_THR_KILL = 433; FB_UMTX_OP = 454;
  FB_MLOCK = 203; FB_MUNLOCK = 204; FB_SCHED_SETPARAM = 327; FB_SCHED_GETPARAM = 328;
  FB_SCHED_SETSCHEDULER = 329; FB_SCHED_GETSCHEDULER = 330; FB_SCHED_GET_PRIORITY_MAX = 332;
  FB_SCHED_GET_PRIORITY_MIN = 333; FB_SCHED_RR_GET_INTERVAL = 334; FB_SWAPON = 85;
  FB_SWAPOFF = 582; FB_THR_SET_NAME = 464; FB_POSIX_FALLOCATE = 530;
  FB_KQUEUE = 362; FB_KEVENT = 560; FB_TIMERFD_CREATE = 585;
  FB_TIMERFD_GETTIME = 586; FB_TIMERFD_SETTIME = 587; FB_SPECIALFD = 577;
  FB_EVFILT_READ = -1; FB_EVFILT_WRITE = -2;
  FB_EV_ADD = $1; FB_EV_DELETE = $2; FB_EV_ENABLE = $4; FB_EV_ONESHOT = $10;
  FB_EV_CLEAR = $20; FB_EV_ERROR = $4000; FB_EV_EOF = $8000;
  LX_EPOLLIN = $1; LX_EPOLLPRI = $2; LX_EPOLLOUT = $4; LX_EPOLLERR = $8;
  LX_EPOLLHUP = $10; LX_EPOLLRDHUP = $2000;
  EP_MAX = 64;                    { kevents fetched per epoll_wait }
  FB_F_GETFD = 1; FB_F_KINFO = 22; FB_KINFO_FILE_SIZE = 1392; FB_KF_PATH = 368;

  FB_AT_FDCWD = -100;            { same value as Linux }
  FB_AT_EACCESS = $100; FB_AT_SYMLINK_NOFOLLOW = $200; FB_AT_SYMLINK_FOLLOW = $400;
  FB_AT_REMOVEDIR = $800; FB_AT_EMPTY_PATH = $4000;

  FB_MAP_FIXED = $10; FB_MAP_STACK = $400; FB_MAP_ANON = $1000;
  FB_MAP_GUARD = $2000; FB_MAP_EXCL = $4000; FB_MAP_PREFAULT_READ = $40000;

  FB_RLIM_INFINITY = $7FFFFFFFFFFFFFFF;

  { FreeBSD errno 35..97 -> Linux errno. 1..34 are the same on both. }
  ErrMap: array[35..97] of Integer = (
    11, 115, 114, 88, 89, 90, 91, 92, 93, 94,      { 35 EAGAIN .. 44 ESOCKTNOSUPPORT }
    95, 96, 97, 98, 99, 100, 101, 102, 103, 104,   { 45 EOPNOTSUPP .. 54 ECONNRESET }
    105, 106, 107, 108, 109, 110, 111, 40, 36, 112, { 55 ENOBUFS .. 64 EHOSTDOWN }
    113, 39, 11, 87, 122, 116, 66, 22, 22, 22,     { 65 EHOSTUNREACH .. 74 EPROGUNAVAIL }
    22, 22, 37, 38, 22, 13, 13, 43, 42, 75,        { 75 EPROGMISMATCH .. 84 EOVERFLOW }
    125, 84, 61, 22, 74, 72, 67, 71, 1, 1,         { 85 ECANCELED .. 94 ECAPMODE }
    131, 130, 5);                                  { 95 ENOTRECOVERABLE .. 97 EINTEGRITY }

  { Linux signal 0..31 -> FreeBSD. 0 = no FreeBSD equivalent. }
  SigMap: array[0..31] of Integer = (
    0, 1, 2, 3, 4, 5, 6, 10, 8, 9, 30, 11, 31, 13, 14, 15,
    0, 20, 19, 17, 18, 21, 22, 16, 24, 25, 26, 27, 28, 23, 0, 12);

  { Linux RLIMIT_* 0..9 -> FreeBSD (CPU FSIZE DATA STACK CORE RSS NPROC NOFILE MEMLOCK AS) }
  RlimMap: array[0..9] of Integer = (0, 1, 2, 3, 4, 5, 7, 8, 6, 10);

  BRK_RESERVE = Int64(64) * 1024 * 1024 * 1024;   { address space only (MAP_GUARD) }

var
  FbBrkBase, FbBrkCur, FbBrkTop: Int64;    { brk emulation, see FbBrk }
  FbMainTid: Int64;                        { the first thread to enter: SYS_exit there ends the process }

{ The kernel entry. args -> [nr, a0..a5, rdx-out, cf-out]. FreeBSD reports an error
  with CF set and the positive errno in rax; this returns -errno instead (the
  sbb/xor/sub trio negates rax exactly when CF is set), so the rest of the
  unit speaks one convention. rdx is written back because fork() answers in
  it (1 in the child). r12 holds the pointer across the syscall, which
  clobbers rcx and r11. }
function FbRawA(args: Pointer): Int64; assembler;
{$asmMode intel}
asm
  push r12
  mov r12, args
  mov rax, [r12]
  mov rdi, [r12+8]
  mov rsi, [r12+16]
  mov rdx, [r12+24]
  mov r10, [r12+32]
  mov r8, [r12+40]
  mov r9, [r12+48]
  syscall
  mov [r12+56], rdx
  sbb rcx, rcx
  mov [r12+64], rcx
  xor rax, rcx
  sub rax, rcx
  pop r12
end;

{ The last steps of a non-main thread's SYS_exit: zero the CLONE_CHILD_CLEARTID
  word at ctid, wake its waiters on both umtx queues, thr_exit. Registers
  only, never the stack: the moment the word is zero the joiner may unmap
  this thread's stack, and a Pascal FbSys storing its result there after the
  wake segfaulted (1 run in ~80 of lib_fpc_thread_surface, 2026-11-12). On
  Linux the kernel clears the word after the thread is gone. Does not return. }
procedure FbClearTidExit(ctid: Int64); assembler;
{$asmMode intel}
asm
  mov r12, ctid
  xor eax, eax
  mov [r12], eax
  mov rdi, r12
  mov esi, 3
  mov edx, $7FFFFFFF
  xor r10d, r10d
  xor r8d, r8d
  mov eax, 454
  syscall
  mov rdi, r12
  mov esi, 16
  mov edx, $7FFFFFFF
  xor r10d, r10d
  xor r8d, r8d
  mov eax, 454
  syscall
  xor edi, edi
  mov eax, 431
  syscall
end;

var
  FbRdx: Int64;
  FbErr: Boolean;    { CF of the last FbSys: the only way to tell a negative
                       RESULT (getpriority's nice) from a -errno }

function FbSys(nr, a0, a1, a2, a3, a4, a5: Int64): Int64;
var a: array[0..8] of Int64;
begin
  a[0] := nr; a[1] := a0; a[2] := a1; a[3] := a2;
  a[4] := a3; a[5] := a4; a[6] := a5; a[7] := 0; a[8] := 0;
  Result := FbRawA(@a[0]);
  FbRdx := a[7];
  FbErr := a[8] <> 0;
end;

{ -FreeBSD errno -> -Linux errno; anything else unchanged. }
function Lx(r: Int64): Int64;
begin
  if (r < -34) and (r >= -97) then Result := -ErrMap[Integer(-r)]
  else Result := r;
end;

function FbOpenFlags(f: Int64): Int64;
var r: Int64;
begin
  r := f and 3;                                       { O_ACCMODE, same }
  if (f and $40) <> 0 then r := r or $200;            { O_CREAT }
  if (f and $80) <> 0 then r := r or $800;            { O_EXCL }
  if (f and $100) <> 0 then r := r or $8000;          { O_NOCTTY }
  if (f and $200) <> 0 then r := r or $400;           { O_TRUNC }
  if (f and $400) <> 0 then r := r or $8;             { O_APPEND }
  if (f and $800) <> 0 then r := r or $4;             { O_NONBLOCK }
  if (f and $1000) <> 0 then r := r or $1000000;      { O_DSYNC }
  if (f and $4000) <> 0 then r := r or $10000;        { O_DIRECT }
  if (f and $10000) <> 0 then r := r or $20000;       { O_DIRECTORY }
  if (f and $20000) <> 0 then r := r or $100;         { O_NOFOLLOW }
  if (f and $80000) <> 0 then r := r or $100000;      { O_CLOEXEC }
  if (f and $100000) <> 0 then r := r or $80;         { O_SYNC (Linux sets $101000) }
  if (f and $200000) <> 0 then r := r or $400000;     { O_PATH }
  Result := r;                                        { O_LARGEFILE, O_NOATIME: dropped }
end;

function LxOpenFlags(f: Int64): Int64;
var r: Int64;
begin
  r := f and 3;
  if (f and $200) <> 0 then r := r or $40;
  if (f and $800) <> 0 then r := r or $80;
  if (f and $8000) <> 0 then r := r or $100;
  if (f and $400) <> 0 then r := r or $200;
  if (f and $8) <> 0 then r := r or $400;
  if (f and $4) <> 0 then r := r or $800;
  if (f and $1000000) <> 0 then r := r or $1000;
  if (f and $10000) <> 0 then r := r or $4000;
  if (f and $20000) <> 0 then r := r or $10000;
  if (f and $100) <> 0 then r := r or $20000;
  if (f and $100000) <> 0 then r := r or $80000;
  if (f and $80) <> 0 then r := r or $101000;
  Result := r;
end;

function FbMmapFlags(f: Int64): Int64;
var r: Int64;
begin
  r := f and $13;                                     { SHARED, PRIVATE, FIXED: same }
  if (f and $20) <> 0 then r := r or FB_MAP_ANON;
  if (f and $20000) <> 0 then r := r or FB_MAP_STACK;
  if (f and $8000) <> 0 then r := r or FB_MAP_PREFAULT_READ;     { MAP_POPULATE }
  if (f and $100000) <> 0 then r := r or FB_MAP_FIXED or FB_MAP_EXCL;  { FIXED_NOREPLACE }
  Result := r;                                        { NORESERVE, GROWSDOWN, ...: dropped }
end;

{ Linux AT_* -> FreeBSD for the stat/open family. unlinkat and faccessat
  reuse bit $200 for a different meaning and are handled at their call. }
function FbAtFlags(f: Int64): Int64;
var r: Int64;
begin
  r := 0;
  if (f and $100) <> 0 then r := r or FB_AT_SYMLINK_NOFOLLOW;
  if (f and $400) <> 0 then r := r or FB_AT_SYMLINK_FOLLOW;
  if (f and $1000) <> 0 then r := r or FB_AT_EMPTY_PATH;
  Result := r;
end;

function FbClock(id: Int64): Int64;
begin
  case Integer(id) of
    0: Result := 0;        { REALTIME }
    1: Result := 4;        { MONOTONIC }
    2: Result := 15;       { PROCESS_CPUTIME_ID }
    3: Result := 14;       { THREAD_CPUTIME_ID }
    4: Result := 4;        { MONOTONIC_RAW }
    5: Result := 10;       { REALTIME_COARSE -> REALTIME_FAST }
    6: Result := 12;       { MONOTONIC_COARSE -> MONOTONIC_FAST }
    7: Result := 4;        { BOOTTIME -> MONOTONIC (FreeBSD's BOOTTIME alias) }
  else
    Result := id;
  end;
end;

function FbSig(s: Int64): Int64;
begin
  if (s >= 0) and (s <= 31) then Result := SigMap[Integer(s)]
  else if (s >= 32) and (s <= 64) then Result := s + 33   { Linux RT 32.. -> FreeBSD SIGRTMIN 65.. }
  else Result := s;
end;

{ FreeBSD struct stat (224 B) at fb -> Linux x86-64 struct stat (144 B) at lx. }
procedure StatToLinux(fb, lx: Pointer);
var i: Integer;
begin
  for i := 0 to 17 do PInt64(Int64(lx) + i * 8)^ := 0;
  PInt64(Int64(lx) + 0)^ := PInt64(Int64(fb) + 0)^;                 { st_dev }
  PInt64(Int64(lx) + 8)^ := PInt64(Int64(fb) + 8)^;                 { st_ino }
  PInt64(Int64(lx) + 16)^ := PInt64(Int64(fb) + 16)^;               { st_nlink }
  PLongWord(Int64(lx) + 24)^ := PWord(Int64(fb) + 24)^;             { st_mode }
  PLongWord(Int64(lx) + 28)^ := PLongWord(Int64(fb) + 28)^;         { st_uid }
  PLongWord(Int64(lx) + 32)^ := PLongWord(Int64(fb) + 32)^;         { st_gid }
  PInt64(Int64(lx) + 40)^ := PInt64(Int64(fb) + 40)^;               { st_rdev }
  PInt64(Int64(lx) + 48)^ := PInt64(Int64(fb) + 112)^;              { st_size }
  PInt64(Int64(lx) + 56)^ := PInteger(Int64(fb) + 128)^;            { st_blksize }
  PInt64(Int64(lx) + 64)^ := PInt64(Int64(fb) + 120)^;              { st_blocks }
  PInt64(Int64(lx) + 72)^ := PInt64(Int64(fb) + 48)^;               { st_atim }
  PInt64(Int64(lx) + 80)^ := PInt64(Int64(fb) + 56)^;
  PInt64(Int64(lx) + 88)^ := PInt64(Int64(fb) + 64)^;               { st_mtim }
  PInt64(Int64(lx) + 96)^ := PInt64(Int64(fb) + 72)^;
  PInt64(Int64(lx) + 104)^ := PInt64(Int64(fb) + 80)^;              { st_ctim }
  PInt64(Int64(lx) + 112)^ := PInt64(Int64(fb) + 88)^;
end;

{ FreeBSD struct stat -> Linux struct statx (256 B). }
procedure StatToStatx(fb, sx: Pointer);
var i: Integer;
procedure Ts(lxOff, fbOff: Integer);
begin
  PInt64(Int64(sx) + lxOff)^ := PInt64(Int64(fb) + fbOff)^;
  PLongWord(Int64(sx) + lxOff + 8)^ := LongWord(PInt64(Int64(fb) + fbOff + 8)^);
end;
begin
  for i := 0 to 31 do PInt64(Int64(sx) + i * 8)^ := 0;
  PLongWord(Int64(sx) + 0)^ := $FFF;                                { BASIC_STATS | BTIME }
  PLongWord(Int64(sx) + 4)^ := LongWord(PInteger(Int64(fb) + 128)^); { blksize }
  PLongWord(Int64(sx) + 16)^ := LongWord(PInt64(Int64(fb) + 16)^);  { nlink }
  PLongWord(Int64(sx) + 20)^ := PLongWord(Int64(fb) + 28)^;         { uid }
  PLongWord(Int64(sx) + 24)^ := PLongWord(Int64(fb) + 32)^;         { gid }
  PWord(Int64(sx) + 28)^ := PWord(Int64(fb) + 24)^;                 { mode }
  PInt64(Int64(sx) + 32)^ := PInt64(Int64(fb) + 8)^;                { ino }
  PInt64(Int64(sx) + 40)^ := PInt64(Int64(fb) + 112)^;              { size }
  PInt64(Int64(sx) + 48)^ := PInt64(Int64(fb) + 120)^;              { blocks }
  Ts(64, 48);                                                       { atime }
  Ts(80, 96);                                                       { btime }
  Ts(96, 80);                                                       { ctime }
  Ts(112, 64);                                                      { mtime }
  PLongWord(Int64(sx) + 128)^ := LongWord(PInt64(Int64(fb) + 40)^ shr 32);  { rdev major }
  PLongWord(Int64(sx) + 132)^ := LongWord(PInt64(Int64(fb) + 40)^);         { rdev minor }
  PLongWord(Int64(sx) + 136)^ := LongWord(PInt64(Int64(fb) + 0)^ shr 32);   { dev major }
  PLongWord(Int64(sx) + 140)^ := LongWord(PInt64(Int64(fb) + 0)^);          { dev minor }
end;

{ FreeBSD dirents -> Linux dirent64, in place. The name moves from offset 24
  to 19; each record keeps its d_reclen, which is still large enough. }
procedure DirentsToLinux(buf: Pointer; n: Int64);
var p, recLen, nameLen, i: Int64;
begin
  p := 0;
  while p < n do
  begin
    recLen := PWord(Int64(buf) + p + 16)^;
    nameLen := PWord(Int64(buf) + p + 20)^;
    if recLen = 0 then Exit;
    for i := 0 to nameLen do        { includes the NUL }
      PByte(Int64(buf) + p + 19 + i)^ := PByte(Int64(buf) + p + 24 + i)^;
    p := p + recLen;
  end;
end;

{ Linux brk on top of a MAP_GUARD reservation. FreeBSD's break(2) cannot be
  asked for the current break, and brk(0) is exactly how a Linux program
  asks. Linux semantics: return the new break on success, the old one on
  failure; never an error code. }
function FbBrk(want: Int64): Int64;
var top, r: Int64;
begin
  if FbBrkBase = 0 then
  begin
    r := FbSys(FB_MMAP, 0, BRK_RESERVE, 0, FB_MAP_GUARD, -1, 0);
    if r < 0 then begin Result := 0; Exit; end;
    FbBrkBase := r; FbBrkCur := r; FbBrkTop := r;
  end;
  Result := FbBrkCur;
  if (want < FbBrkBase) or (want > FbBrkBase + BRK_RESERVE) then Exit;
  if want > FbBrkTop then
  begin
    top := (want + $FFFF) and (not Int64($FFFF));
    r := FbSys(FB_MMAP, FbBrkTop, top - FbBrkTop, 3,
               $1002 or FB_MAP_FIXED, -1, 0);           { PRIVATE|ANON|FIXED, RW }
    if r < 0 then Exit;
    FbBrkTop := top;
  end;
  FbBrkCur := want;
  Result := want;
end;

function StrLen0(p: Int64): Int64;
var n: Int64;
begin
  n := 0;
  while PByte(p + n)^ <> 0 do n := n + 1;
  Result := n;
end;

procedure SysctlStr(m0, m1: Integer; dst: Int64; cap: Int64);
var mib: array[0..1] of Integer; len: Int64;
begin
  mib[0] := m0; mib[1] := m1; len := cap - 1;
  if FbSys(FB_SYSCTL, Int64(@mib[0]), 2, dst, Int64(@len), 0, 0) < 0 then len := 0;
  if len > cap - 1 then len := cap - 1;
  PByte(dst + len)^ := 0;
end;

{ Linux struct utsname: six 65-byte fields. FreeBSD has no uname syscall;
  libc builds it from sysctl, and so does this. Bytes, not strings: no
  managed types in this unit (see the header). }
function FbUname(u: Int64): Int64;
var i: Integer;
const
  SysName: array[0..6] of Byte = (70, 114, 101, 101, 66, 83, 68);   { FreeBSD }
  Machine: array[0..5] of Byte = (120, 56, 54, 95, 54, 52);         { x86_64 }
begin
  for i := 0 to 389 do PByte(u + i)^ := 0;
  for i := 0 to 6 do PByte(u + i)^ := SysName[i];
  SysctlStr(1, 10, u + 65, 65);      { kern.hostname }
  SysctlStr(1, 2, u + 130, 65);      { kern.osrelease }
  SysctlStr(1, 4, u + 195, 65);      { kern.version }
  for i := 0 to 5 do PByte(u + 260 + i)^ := Machine[i];
  Result := 0;
end;

function FbGetRlimit(res, lim: Int64): Int64;
var r: Int64;
begin
  if (res < 0) or (res > 9) then begin Result := -LX_EINVAL; Exit; end;
  r := FbSys(FB_GETRLIMIT, RlimMap[Integer(res)], lim, 0, 0, 0, 0);
  if r = 0 then
  begin
    if PInt64(lim)^ = FB_RLIM_INFINITY then PInt64(lim)^ := -1;
    if PInt64(lim + 8)^ = FB_RLIM_INFINITY then PInt64(lim + 8)^ := -1;
  end;
  Result := Lx(r);
end;

function FbSetRlimit(res, lim: Int64): Int64;
var v: array[0..1] of Int64;
begin
  if (res < 0) or (res > 9) then begin Result := -LX_EINVAL; Exit; end;
  v[0] := PInt64(lim)^; v[1] := PInt64(lim + 8)^;
  if v[0] = -1 then v[0] := FB_RLIM_INFINITY;
  if v[1] = -1 then v[1] := FB_RLIM_INFINITY;
  Result := Lx(FbSys(FB_SETRLIMIT, RlimMap[Integer(res)], Int64(@v[0]), 0, 0, 0, 0));
end;

function FbStatAt(dirfd, path, buf, flags: Int64): Int64;
var sb: array[0..27] of Int64; r: Int64;
begin
  r := FbSys(FB_FSTATAT, dirfd, path, Int64(@sb[0]), FbAtFlags(flags), 0, 0);
  if r = 0 then StatToLinux(@sb[0], Pointer(buf));
  Result := Lx(r);
end;

{ ---- the two /proc files the runtime reads ------------------------------
  FreeBSD has no /proc by default. The RTL, the C runtime, NilPy's runtime
  and the compiler itself all read the environment from /proc/self/environ,
  and pyos/sysutils resolve their own path through /proc/self/exe. Rather
  than teach four readers about FreeBSD, the translator answers those two
  paths the way linuxulator's linprocfs would: from sysctl, which hands back
  the environment in exactly /proc's NUL-separated format. }

{ Does the C string at p equal the bytes in w? }
function PathIs(p: Int64; const w: array of Byte): Boolean;
var i: Integer;
begin
  Result := False;
  if p = 0 then Exit;
  for i := 0 to High(w) do
    if PByte(p + i)^ <> w[i] then Exit;
  Result := PByte(p + Length(w))^ = 0;
end;

const
  ProcEnviron: array[0..17] of Byte = (47,112,114,111,99,47,115,101,108,102,47,
                                       101,110,118,105,114,111,110);   { /proc/self/environ }
  ProcExe: array[0..13] of Byte = (47,112,114,111,99,47,115,101,108,102,47,
                                   101,120,101);                        { /proc/self/exe }
  DevPtmx: array[0..8] of Byte = (47,100,101,118,47,112,116,109,120);   { /dev/ptmx }
  ProcHostname: array[0..24] of Byte = (47,112,114,111,99,47,115,121,115,47,107,101,114,
                                        110,101,108,47,104,111,115,116,110,97,109,101);  { /proc/sys/kernel/hostname }

{ An anonymous shared-memory fd holding kern.proc.env, rewound: reads see
  what /proc/self/environ would hold. The buffer is a scratch mapping, not
  the heap -- this can run before the heap exists. }
function FbShmFile(buf, len: Int64): Int64;
{ An anonymous shm fd holding len bytes at buf, rewound -- how this unit
  answers an open() of a /proc file FreeBSD does not have. }
var fd: Int64;
begin
  fd := FbSys(FB_SHM_OPEN2, 1, 2 or $100000, 384, 0, 0, 0);   { SHM_ANON, O_RDWR|O_CLOEXEC, 0600 }
  if (fd >= 0) and (len > 0) then
  begin
    FbSys(FB_FTRUNCATE, fd, len, 0, 0, 0, 0);   { a shm object does not grow on write }
    FbSys(FB_WRITE, fd, buf, len, 0, 0, 0);
    FbSys(FB_LSEEK, fd, 0, 0, 0, 0, 0);
  end;
  if fd < 0 then Result := Lx(fd) else Result := fd;
end;

{ /proc/sys/kernel/hostname: kern.hostname and a newline. }
function FbProcHostname: Int64;
var b: array[0..299] of Byte; n: Int64;
begin
  SysctlStr(1, 10, Int64(@b[0]), 256);
  n := StrLen0(Int64(@b[0]));
  b[n] := 10;
  Result := FbShmFile(Int64(@b[0]), n + 1);
end;

function FbProcEnviron: Int64;
var mib: array[0..3] of Integer; len, buf, size, fd, r: Int64;
begin
  mib[0] := 1; mib[1] := 14; mib[2] := 35;
  mib[3] := Integer(FbSys(FB_GETPID, 0, 0, 0, 0, 0, 0));
  len := 0;
  r := FbSys(FB_SYSCTL, Int64(@mib[0]), 4, 0, Int64(@len), 0, 0);
  if r < 0 then begin Result := Lx(r); Exit; end;
  size := (len + 4096 + $FFF) and (not Int64($FFF));
  buf := FbSys(FB_MMAP, 0, size, 3, $1002, -1, 0);
  if buf < 0 then begin Result := -LX_ENOMEM; Exit; end;
  len := size;
  r := FbSys(FB_SYSCTL, Int64(@mib[0]), 4, buf, Int64(@len), 0, 0);
  if r < 0 then len := 0;
  Result := FbShmFile(buf, len);
  FbSys(FB_MUNMAP, buf, size, 0, 0, 0, 0);
end;

{ readlink("/proc/self/exe"): kern.proc.pathname. Linux semantics: no NUL,
  truncate silently, return the byte count. }
function FbProcExe(buf, cap: Int64): Int64;
var mib: array[0..3] of Integer; len, r: Int64;
    tmp: array[0..1023] of Byte;
    i: Integer;
begin
  mib[0] := 1; mib[1] := 14; mib[2] := 12; mib[3] := -1;
  len := 1024;
  r := FbSys(FB_SYSCTL, Int64(@mib[0]), 4, Int64(@tmp[0]), Int64(@len), 0, 0);
  if r < 0 then begin Result := Lx(r); Exit; end;
  if (len > 0) and (tmp[len - 1] = 0) then len := len - 1;
  if len > cap then len := cap;
  for i := 0 to Integer(len) - 1 do PByte(buf + i)^ := tmp[i];
  Result := len;
end;

{ ---- Signals ----------------------------------------------------------------
  The program's handler (the compiler's dispatch stub, or anything else that
  installs one) speaks the Linux SA_SIGINFO ABI: Linux signal number in edi, a
  Linux siginfo_t in rsi, a Linux ucontext_t in rdx -- the fault-to-raise path
  reads and REWRITES the saved RIP/RSP in it (__pxxSigPCPtr/SPPtr). FreeBSD's
  frame has a different siginfo (si_addr at 24, not 16; its own si_code
  values) and a different mcontext order. So rt_sigaction never hands FreeBSD
  the program's handler: it records it in FbLxHandler and installs FbSigEntry,
  which builds Linux-shaped siginfo/ucontext on its own stack, calls the
  handler, and copies the register file back before returning to FreeBSD's
  sigcode trampoline (which does sigreturn -- so the program's SA_RESTORER
  stub is never used here). Offsets measured with offsetof() on 15.1. }

const
  FB_SIGPROCMASK = 340; FB_SIGACTION = 416;
  FB_SA_ONSTACK = $1; FB_SA_RESTART = $2; FB_SA_RESETHAND = $4;
  FB_SA_NOCLDSTOP = $8; FB_SA_NODEFER = $10; FB_SA_NOCLDWAIT = $20;
  FB_SA_SIGINFO = $40;
  LX_SA_NOCLDSTOP = $1; LX_SA_NOCLDWAIT = $2; LX_SA_SIGINFO = $4;
  LX_SA_ONSTACK = $08000000; LX_SA_RESTART = $10000000;
  LX_SA_NODEFER = $40000000; LX_SA_RESETHAND = $80000000;
  { Linux gregs[0..17] (R8 R9 R10 R11 R12 R13 R14 R15 RDI RSI RBP RBX RDX RAX
    RCX RSP RIP EFL) -> offset in FreeBSD mcontext_t. }
  FbGregOff: array[0..17] of Integer = (
    40, 48, 80, 88, 96, 104, 112, 120, 8, 16, 72, 64, 24, 56, 32, 184, 160, 176);
  FB_UC_MCONTEXT = 16;
  LX_UC_GREGS = 40;           { uc_flags, uc_link, uc_stack(24) }
  LX_UC_SIGMASK = 296;        { after the kernel's 256-byte sigcontext }

var
  FbLxHandler: array[0..127] of Int64;   { by FreeBSD signal number }

{ FreeBSD signal -> Linux signal (inverse of FbSig). }
function LxSig(s: Int64): Int64;
var i: Integer;
begin
  if s >= 65 then begin Result := s - 33; Exit; end;
  for i := 1 to 31 do
    if SigMap[i] = s then begin Result := i; Exit; end;
  Result := s;
end;

{ Linux 64-bit mask (bit s-1) -> FreeBSD sigset_t (4 x 32 bits, bit s-1). }
procedure MaskToFb(lx, fb: Int64);
var s, b: Int64;
begin
  PInt64(fb)^ := 0; PInt64(fb + 8)^ := 0;
  for s := 1 to 64 do
    if ((lx shr (s - 1)) and 1) <> 0 then
    begin
      b := FbSig(s);
      if (b >= 1) and (b <= 128) then
        PInteger(fb + ((b - 1) shr 5) * 4)^ :=
          PInteger(fb + ((b - 1) shr 5) * 4)^ or Integer(Int64(1) shl ((b - 1) and 31));
    end;
end;

function MaskToLx(fb: Int64): Int64;
var b, s: Int64;
begin
  Result := 0;
  for b := 1 to 128 do
    if ((PInteger(fb + ((b - 1) shr 5) * 4)^ shr ((b - 1) and 31)) and 1) <> 0 then
    begin
      s := LxSig(b);
      if (s >= 1) and (s <= 64) then Result := Result or (Int64(1) shl (s - 1));
    end;
end;

function SaFlagsToFb(f: Int64): Int64;
begin
  Result := 0;
  if (f and LX_SA_NOCLDSTOP) <> 0 then Result := Result or FB_SA_NOCLDSTOP;
  if (f and LX_SA_NOCLDWAIT) <> 0 then Result := Result or FB_SA_NOCLDWAIT;
  if (f and LX_SA_SIGINFO) <> 0 then Result := Result or FB_SA_SIGINFO;
  if (f and LX_SA_ONSTACK) <> 0 then Result := Result or FB_SA_ONSTACK;
  if (f and LX_SA_RESTART) <> 0 then Result := Result or FB_SA_RESTART;
  if (f and LX_SA_NODEFER) <> 0 then Result := Result or FB_SA_NODEFER;
  if (f and LX_SA_RESETHAND) <> 0 then Result := Result or FB_SA_RESETHAND;
end;

function SaFlagsToLx(f: Int64): Int64;
begin
  Result := 0;
  if (f and FB_SA_NOCLDSTOP) <> 0 then Result := Result or LX_SA_NOCLDSTOP;
  if (f and FB_SA_NOCLDWAIT) <> 0 then Result := Result or LX_SA_NOCLDWAIT;
  if (f and FB_SA_SIGINFO) <> 0 then Result := Result or LX_SA_SIGINFO;
  if (f and FB_SA_ONSTACK) <> 0 then Result := Result or LX_SA_ONSTACK;
  if (f and FB_SA_RESTART) <> 0 then Result := Result or LX_SA_RESTART;
  if (f and FB_SA_NODEFER) <> 0 then Result := Result or LX_SA_NODEFER;
  if (f and FB_SA_RESETHAND) <> 0 then Result := Result or LX_SA_RESETHAND;
end;

{ The program's handler, called as SysV C: rdi, rsi, rdx. FbSigEntry keeps
  nothing in registers across the call (pxx locals live in the frame), and
  FreeBSD's sigreturn restores the interrupted register file from uc. }
type
  TFbLxHandler = procedure(sig, info, uc: Int64); cdecl;

{ FreeBSD si_code -> Linux si_code. }
function LxSiCode(sig, c: Int64): Int64;
begin
  case c of
    $10001: Result := 0;       { SI_USER }
    $10002: Result := -1;      { SI_QUEUE }
    $10003: Result := -2;      { SI_TIMER }
    $10004: Result := -3;      { SI_MESGQ }
    $10005: Result := -4;      { SI_ASYNCIO }
    $10006: Result := $80;     { SI_KERNEL }
    $10007: Result := -6;      { SI_LWP -> SI_TKILL }
  else
    Result := c;
    if sig = 8 then            { SIGFPE: INTOVF/INTDIV are swapped; 3.. agree }
      if c = 1 then Result := 2 else if c = 2 then Result := 1;
  end;
end;

{ The handler FreeBSD actually calls (SA_SIGINFO: rdi, rsi, rdx). }
procedure FbSigEntry(sig, info, uc: Int64); cdecl;
var li: array[0..15] of Int64;        { Linux siginfo_t, 128 B }
    lu: array[0..63] of Int64;        { Linux ucontext_t through uc_sigmask }
    i: Integer;
    h, ls, c: Int64;
begin
  if (sig < 0) or (sig > 127) then Exit;
  h := FbLxHandler[Integer(sig)];
  if h = 0 then Exit;
  ls := LxSig(sig);
  for i := 0 to 15 do li[i] := 0;
  for i := 0 to 63 do lu[i] := 0;
  PInteger(@li[0])^ := Integer(ls);                       { si_signo }
  if info <> 0 then
  begin
    PInteger(Int64(@li[0]) + 4)^ := PInteger(info + 4)^; { si_errno }
    c := PInteger(info + 8)^;
    PInteger(Int64(@li[0]) + 8)^ := Integer(LxSiCode(ls, c));
    if c >= $10000 then
    begin
      PInteger(Int64(@li[0]) + 16)^ := PInteger(info + 12)^;   { si_pid }
      PInteger(Int64(@li[0]) + 20)^ := PInteger(info + 16)^;   { si_uid }
    end
    else
      li[2] := PInt64(info + 24)^;                            { si_addr }
  end;
  if uc <> 0 then
  begin
    for i := 0 to 17 do
      lu[LX_UC_GREGS div 8 + i] := PInt64(uc + FB_UC_MCONTEXT + FbGregOff[i])^;
    lu[LX_UC_GREGS div 8 + 19] := PInt64(uc + FB_UC_MCONTEXT + 152)^;          { ERR }
    lu[LX_UC_GREGS div 8 + 20] := PInteger(uc + FB_UC_MCONTEXT + 128)^;        { TRAPNO }
    lu[LX_UC_GREGS div 8 + 22] := PInt64(uc + FB_UC_MCONTEXT + 136)^;          { CR2 }
    lu[LX_UC_SIGMASK div 8] := MaskToLx(uc);
  end;
  if info <> 0 then TFbLxHandler(h)(ls, Int64(@li[0]), Int64(@lu[0]))
  else TFbLxHandler(h)(ls, 0, Int64(@lu[0]));
  if uc <> 0 then
    for i := 0 to 17 do
      PInt64(uc + FB_UC_MCONTEXT + FbGregOff[i])^ := lu[LX_UC_GREGS div 8 + i];
end;

function FbRtSigaction(sig, act, oact: Int64): Int64;
var fa, fo: array[0..3] of Int64;     { FreeBSD struct sigaction, 32 B }
    fs, h, oldh, r: Int64;
begin
  fs := FbSig(sig);
  if (fs < 1) or (fs > 127) then begin Result := -LX_EINVAL; Exit; end;
  oldh := FbLxHandler[Integer(fs)];
  fa[0] := 0; fa[1] := 0; fa[2] := 0; fa[3] := 0;
  fo[0] := 0; fo[1] := 0; fo[2] := 0; fo[3] := 0;
  if act <> 0 then
  begin
    h := PInt64(act)^;
    PInteger(Int64(@fa[0]) + 8)^ := Integer(SaFlagsToFb(PInt64(act + 8)^));
    MaskToFb(PInt64(act + 24)^, Int64(@fa[0]) + 12);
    if (h = 0) or (h = 1) then fa[0] := h                 { SIG_DFL / SIG_IGN }
    else
    begin
      FbLxHandler[Integer(fs)] := h;
      fa[0] := Int64(@FbSigEntry);
      PInteger(Int64(@fa[0]) + 8)^ := PInteger(Int64(@fa[0]) + 8)^ or FB_SA_SIGINFO;
    end;
    r := FbSys(FB_SIGACTION, fs, Int64(@fa[0]), Int64(@fo[0]), 0, 0, 0);
    if r <> 0 then FbLxHandler[Integer(fs)] := oldh
    else if (h = 0) or (h = 1) then FbLxHandler[Integer(fs)] := 0;
  end
  else
    r := FbSys(FB_SIGACTION, fs, 0, Int64(@fo[0]), 0, 0, 0);
  if (r = 0) and (oact <> 0) then
  begin
    if fo[0] = Int64(@FbSigEntry) then PInt64(oact)^ := oldh
    else PInt64(oact)^ := fo[0];
    PInt64(oact + 8)^ := SaFlagsToLx(PInteger(Int64(@fo[0]) + 8)^);
    PInt64(oact + 16)^ := 0;
    PInt64(oact + 24)^ := MaskToLx(Int64(@fo[0]) + 12);
  end;
  Result := Lx(r);
end;

function FbRtSigprocmask(how, nset, oset: Int64): Int64;
var fn, fo: array[0..1] of Int64;
    r: Int64;
begin
  if (how < 0) or (how > 2) then begin Result := -LX_EINVAL; Exit; end;
  fo[0] := 0; fo[1] := 0;
  if nset <> 0 then
  begin
    MaskToFb(PInt64(nset)^, Int64(@fn[0]));
    r := FbSys(FB_SIGPROCMASK, how + 1, Int64(@fn[0]), Int64(@fo[0]), 0, 0, 0);
  end
  else
    r := FbSys(FB_SIGPROCMASK, how + 1, 0, Int64(@fo[0]), 0, 0, 0);
  if (r = 0) and (oset <> 0) then PInt64(oset)^ := MaskToLx(Int64(@fo[0]));
  Result := Lx(r);
end;


const
  FB_SIGSUSPEND = 341; FB_SIGPENDING = 343; FB_SIGTIMEDWAIT = 345;

{ FreeBSD siginfo_t (fb) -> Linux siginfo_t (lx, 128 bytes). }
procedure SiginfoToLx(fb, lx: Int64);
var i: Integer;
    c, ls: Int64;
begin
  for i := 0 to 15 do PInt64(lx + i * 8)^ := 0;
  ls := LxSig(PInteger(fb)^);
  PInteger(lx)^ := Integer(ls);
  PInteger(lx + 4)^ := PInteger(fb + 4)^;
  c := PInteger(fb + 8)^;
  PInteger(lx + 8)^ := Integer(LxSiCode(ls, c));
  if c >= $10000 then
  begin
    PInteger(lx + 16)^ := PInteger(fb + 12)^;                 { si_pid }
    PInteger(lx + 20)^ := PInteger(fb + 16)^;                 { si_uid }
  end
  else
    PInt64(lx + 16)^ := PInt64(fb + 24)^;                     { si_addr }
end;

{ rt_sigtimedwait(set, info, timeout): answers the LINUX signal number. }
function FbRtSigtimedwait(nset, info, ts: Int64): Int64;
var fs: array[0..1] of Int64;
    fi: array[0..9] of Int64;                                 { FreeBSD siginfo_t, 80 B }
    r: Int64;
begin
  MaskToFb(PInt64(nset)^, Int64(@fs[0]));
  r := FbSys(FB_SIGTIMEDWAIT, Int64(@fs[0]), Int64(@fi[0]), ts, 0, 0, 0);
  if r > 0 then
  begin
    if info <> 0 then SiginfoToLx(Int64(@fi[0]), info);
    Result := LxSig(r);
  end
  else Result := Lx(r);
end;

{ A wait status carries a signal number twice over: the terminating signal
  in bits 0..6, the stopping signal in bits 8..15. FreeBSD "continued" is
  0x13 (its SIGCONT), Linux's is 0xffff. }
function WaitStatusToLx(st: Int64): Int64;
var lo: Int64;
begin
  st := st and $FFFF;
  lo := st and $7F;
  if st = $13 then Result := $FFFF
  else if lo = $7F then Result := (LxSig((st shr 8) and $FF) shl 8) or $7F
  else if lo <> 0 then Result := (st and not Int64($7F)) or LxSig(lo)
  else Result := st;
end;

function FbWait4(pid, status, options, rusage: Int64): Int64;
var o, st, r: Int64;
begin
  o := options and 3;                                         { WNOHANG, WUNTRACED agree }
  if (options and 8) <> 0 then o := o or 4;                   { WCONTINUED }
  st := 0;
  r := FbSys(FB_WAIT4, pid, Int64(@st), o, rusage, 0, 0);
  if (r > 0) and (status <> 0) then PInteger(status)^ := Integer(WaitStatusToLx(st));
  Result := Lx(r);
end;


{ utimensat / futimens: Linux UTIME_NOW/UTIME_OMIT are (1<<30)-1 / -2,
  FreeBSD's are -1 / -2. A nil path means "the fd itself" on Linux only. }
function FbUtimensat(dirfd, path, times, flags: Int64): Int64;
var ts: array[0..3] of Int64;
    tp, i: Int64;
begin
  tp := 0;
  if times <> 0 then
  begin
    for i := 0 to 3 do ts[i] := PInt64(times + i * 8)^;
    for i := 0 to 1 do
      if ts[i * 2 + 1] = $3FFFFFFF then ts[i * 2 + 1] := -1
      else if ts[i * 2 + 1] = $3FFFFFFE then ts[i * 2 + 1] := -2;
    tp := Int64(@ts[0]);
  end;
  if path = 0 then Result := Lx(FbSys(FB_FUTIMENS, dirfd, tp, 0, 0, 0, 0))
  else Result := Lx(FbSys(FB_UTIMENSAT, dirfd, path, tp, FbAtFlags(flags), 0, 0));
end;

{ times(): no FreeBSD syscall. struct tms (4 x clock_t = long) in Linux's
  USER_HZ (100) from getrusage; the result is a monotonic tick count. }
function FbTimes(buf: Int64): Int64;
var ru: array[0..17] of Int64;     { struct rusage, 144 B on both }
    ts: array[0..1] of Int64;
begin
  if buf <> 0 then
  begin
    FbSys(FB_GETRUSAGE, 0, Int64(@ru[0]), 0, 0, 0, 0);
    PInt64(buf)^ := ru[0] * 100 + ru[1] div 10000;         { utime }
    PInt64(buf + 8)^ := ru[2] * 100 + ru[3] div 10000;     { stime }
    FbSys(FB_GETRUSAGE, -1, Int64(@ru[0]), 0, 0, 0, 0);
    PInt64(buf + 16)^ := ru[0] * 100 + ru[1] div 10000;    { cutime }
    PInt64(buf + 24)^ := ru[2] * 100 + ru[3] div 10000;    { cstime }
  end;
  FbSys(FB_CLOCK_GETTIME, 4, Int64(@ts[0]), 0, 0, 0, 0);
  Result := ts[0] * 100 + ts[1] div 10000000;
end;

{ alarm(): no FreeBSD syscall; ITIMER_REAL, answering the seconds left. }
function FbAlarm(secs: Int64): Int64;
var nv, ov: array[0..3] of Int64;  { struct itimerval: interval, value }
begin
  nv[0] := 0; nv[1] := 0; nv[2] := secs; nv[3] := 0;
  ov[2] := 0; ov[3] := 0;
  FbSys(FB_SETITIMER, 0, Int64(@nv[0]), Int64(@ov[0]), 0, 0, 0);
  Result := ov[2];
  if ov[3] >= 500000 then Inc(Result);
  if (Result = 0) and ((ov[2] <> 0) or (ov[3] <> 0)) then Result := 1;
end;


{ /proc/self/fd/N -> the fd's path, via fcntl(F_KINFO) (FreeBSD 13.1+).
  Answers -1 when p is not that shape, else the fd number. }
function ProcFdNum(p: Int64): Int64;
const pre: array[0..13] of Byte = (47,112,114,111,99,47,115,101,108,102,47,102,100,47); { /proc/self/fd/ }
var i: Integer; c: Byte;
begin
  Result := -1;
  if p = 0 then Exit;
  for i := 0 to 13 do
    if PByte(p + i)^ <> pre[i] then Exit;
  i := 14;
  c := PByte(p + i)^;
  if (c < 48) or (c > 57) then Exit;
  Result := 0;
  while (c >= 48) and (c <= 57) do
  begin
    Result := Result * 10 + (c - 48);
    Inc(i);
    c := PByte(p + i)^;
  end;
  if c <> 0 then Result := -1;
end;

function FbProcFd(fd, buf, cap: Int64): Int64;
var kf: array[0..173] of Int64;     { struct kinfo_file, 1392 B }
    n, i, r: Int64;
begin
  for i := 0 to 173 do kf[i] := 0;
  PInteger(@kf[0])^ := FB_KINFO_FILE_SIZE;
  r := FbSys(FB_FCNTL, fd, FB_F_KINFO, Int64(@kf[0]), 0, 0, 0);
  if r < 0 then begin Result := Lx(r); Exit; end;
  n := StrLen0(Int64(@kf[0]) + FB_KF_PATH);
  if n = 0 then begin Result := -LX_ENOENT; Exit; end;
  if n > cap then n := cap;
  for i := 0 to n - 1 do PByte(buf + i)^ := PByte(Int64(@kf[0]) + FB_KF_PATH + i)^;
  Result := n;
end;

{ FreeBSD struct statfs (2344 B) -> Linux struct statfs (120 B). }
function FbStatfs(nr, arg, lx: Int64): Int64;
var fs: array[0..292] of Int64;
    r, fl, ty, i: Int64;
    nm: Int64;
begin
  r := FbSys(nr, arg, Int64(@fs[0]), 0, 0, 0, 0);
  if r < 0 then begin Result := Lx(r); Exit; end;
  for i := 0 to 14 do PInt64(lx + i * 8)^ := 0;
  nm := Int64(@fs[0]) + 280;                                  { f_fstypename }
  ty := 0;
  case PByte(nm)^ of                                          { Linux f_type magics }
    117: ty := $00011954;                                     { ufs }
    122: ty := $2FC12FC1;                                     { zfs }
    116: ty := $01021994;                                     { tmpfs }
    100: ty := $1373;                                         { devfs }
    112: ty := $9FA0;                                         { procfs }
    110: ty := $6969;                                         { nfs }
    109: ty := $4D44;                                         { msdosfs }
    99:  ty := $9660;                                         { cd9660 }
  end;
  PInt64(lx)^ := ty;
  PInt64(lx + 8)^ := fs[2];                                   { f_bsize }
  for i := 0 to 4 do PInt64(lx + 16 + i * 8)^ := fs[4 + i];   { blocks bfree bavail files ffree }
  PInt64(lx + 56)^ := fs[24];                                 { f_fsid }
  PInt64(lx + 64)^ := PInteger(Int64(@fs[0]) + 184)^;         { f_namelen }
  PInt64(lx + 72)^ := fs[2];                                  { f_frsize }
  fl := fs[1];
  r := 0;
  if (fl and $1) <> 0 then r := r or 1;                       { ST_RDONLY }
  if (fl and $8) <> 0 then r := r or 2;                       { ST_NOSUID }
  if (fl and $4) <> 0 then r := r or 8;                       { ST_NOEXEC }
  if (fl and $2) <> 0 then r := r or 16;                      { ST_SYNCHRONOUS }
  if (fl and $10000000) <> 0 then r := r or 1024;             { ST_NOATIME }
  PInt64(lx + 80)^ := r;
  Result := 0;
end;

{ poll event bits: the low six agree; WRNORM, WRBAND and RDHUP do not.
  Rewritten in place around the call and restored after. }
function PollBitsToFb(e: Integer): Integer;
begin
  Result := e and $FF;
  if (e and $100) <> 0 then Result := Result or $4;           { POLLWRNORM = POLLOUT }
  if (e and $200) <> 0 then Result := Result or $100;         { POLLWRBAND }
  if (e and $2000) <> 0 then Result := Result or $4000;       { POLLRDHUP }
end;

function PollBitsToLx(e, asked: Integer): Integer;
begin
  Result := e and $FF;
  if ((e and $4) <> 0) and ((asked and $100) <> 0) then Result := Result or $100;
  if (e and $100) <> 0 then Result := Result or $200;
  if (e and $4000) <> 0 then Result := Result or $2000;
end;

function FbPoll(fds, n, ts, mask: Int64; isPpoll: Boolean): Int64;
var i, r: Int64;
    m: array[0..1] of Int64;
    orig: array[0..63] of Integer;   { the caller's events, restored exactly }
    asked: Integer;
begin
  for i := 0 to n - 1 do
  begin
    asked := PSmallInt(fds + i * 8 + 4)^ and $FFFF;
    if i < 64 then orig[i] := asked;
    PSmallInt(fds + i * 8 + 4)^ := SmallInt(PollBitsToFb(asked));
  end;
  if not isPpoll then r := FbSys(FB_POLL, fds, n, ts, 0, 0, 0)
  else if mask <> 0 then
  begin
    MaskToFb(PInt64(mask)^, Int64(@m[0]));
    r := FbSys(FB_PPOLL, fds, n, ts, Int64(@m[0]), 0, 0);
  end
  else r := FbSys(FB_PPOLL, fds, n, ts, 0, 0, 0);
  for i := 0 to n - 1 do
  begin
    if i < 64 then asked := orig[i]
    else asked := PollBitsToLx(PSmallInt(fds + i * 8 + 4)^ and $FFFF, $FFFF);
    PSmallInt(fds + i * 8 + 4)^ := SmallInt(asked);
    PSmallInt(fds + i * 8 + 6)^ := SmallInt(PollBitsToLx(PSmallInt(fds + i * 8 + 6)^ and $FFFF, asked));
  end;
  Result := Lx(r);
end;


{ ---- epoll over kqueue ------------------------------------------------------
  FreeBSD has no epoll. An epoll instance IS a kqueue; an interest in an fd is
  up to two kevent filters (READ for EPOLLIN/PRI/RDHUP, WRITE for EPOLLOUT)
  carrying the caller's epoll_data as udata. EPOLLET -> EV_CLEAR, EPOLLONESHOT
  -> EV_ONESHOT. epoll_wait folds the READ and WRITE kevents of one fd back
  into one epoll_event, as Linux reports it. struct epoll_event is PACKED on
  x86-64: u32 events at 0, u64 data at 4, 12 bytes. }

function FbKev1(kq, ident, filter, flags, udata: Int64): Int64;
var kv: array[0..7] of Int64;     { struct kevent, 64 B }
    i: Integer;
begin
  for i := 0 to 7 do kv[i] := 0;
  kv[0] := ident;
  PSmallInt(Int64(@kv[0]) + 8)^ := SmallInt(filter);
  PWord(Int64(@kv[0]) + 10)^ := Word(flags);
  kv[3] := udata;
  Result := FbSys(FB_KEVENT, kq, Int64(@kv[0]), 1, 0, 0, 0);
end;

function FbEpollCtl(kq, op, fd, ev: Int64): Int64;
var e, data, fl, r: Int64;
begin
  if (op = 2) or (ev = 0) then                                 { EPOLL_CTL_DEL }
  begin
    r := FbKev1(kq, fd, FB_EVFILT_READ, FB_EV_DELETE, 0);
    if FbKev1(kq, fd, FB_EVFILT_WRITE, FB_EV_DELETE, 0) = 0 then r := 0;
    Result := Lx(r);
    Exit;
  end;
  e := PInteger(ev)^ and $FFFFFFFF;
  data := PInt64(ev + 4)^;
  fl := FB_EV_ADD or FB_EV_ENABLE;
  if (e and $80000000) <> 0 then fl := fl or FB_EV_CLEAR;      { EPOLLET }
  if (e and $40000000) <> 0 then fl := fl or FB_EV_ONESHOT;    { EPOLLONESHOT }
  r := 0;
  if (e and (LX_EPOLLIN or LX_EPOLLPRI or LX_EPOLLRDHUP)) <> 0 then
    r := FbKev1(kq, fd, FB_EVFILT_READ, fl, data)
  else if op = 3 then FbKev1(kq, fd, FB_EVFILT_READ, FB_EV_DELETE, 0);
  if r < 0 then begin Result := Lx(r); Exit; end;
  if (e and LX_EPOLLOUT) <> 0 then
    r := FbKev1(kq, fd, FB_EVFILT_WRITE, fl, data)
  else if op = 3 then FbKev1(kq, fd, FB_EVFILT_WRITE, FB_EV_DELETE, 0);
  Result := Lx(r);
end;

function FbEpollWait(kq, evs, maxev, ms: Int64): Int64;
var kv: array[0..EP_MAX * 8 - 1] of Int64;
    ts: array[0..1] of Int64;
    tp, r, i, j, n, e, fl, ident: Int64;
    base: Int64;
begin
  if maxev <= 0 then begin Result := -LX_EINVAL; Exit; end;
  if maxev > EP_MAX then maxev := EP_MAX;
  tp := 0;
  if ms >= 0 then
  begin
    ts[0] := ms div 1000; ts[1] := (ms mod 1000) * 1000000;
    tp := Int64(@ts[0]);
  end;
  r := FbSys(FB_KEVENT, kq, 0, 0, Int64(@kv[0]), maxev, tp);
  if r < 0 then begin Result := Lx(r); Exit; end;
  n := 0;
  for i := 0 to r - 1 do
  begin
    base := Int64(@kv[0]) + i * 64;
    ident := PInt64(base)^;
    fl := PWord(base + 10)^;
    e := 0;
    if PSmallInt(base + 8)^ = FB_EVFILT_READ then e := LX_EPOLLIN
    else e := LX_EPOLLOUT;
    if (fl and FB_EV_EOF) <> 0 then
    begin
      e := e or LX_EPOLLHUP;
      if PSmallInt(base + 8)^ = FB_EVFILT_READ then e := e or LX_EPOLLRDHUP;
      if PInteger(base + 12)^ <> 0 then e := e or LX_EPOLLERR;  { fflags = socket error }
    end;
    if (fl and FB_EV_ERROR) <> 0 then e := LX_EPOLLERR;
    { fold into an earlier event for the same fd; kv[] holds ident, the
      output array holds only data -- so match on the kevent list }
    j := 0;
    while j < i do
    begin
      if PInt64(Int64(@kv[0]) + j * 64)^ = ident then Break;
      Inc(j);
    end;
    if j < i then
    begin
      { the earlier kevent j was emitted at output slot PInteger(kv j .data)^ }
      j := PInt64(Int64(@kv[0]) + j * 64 + 16)^;
      PInteger(evs + j * 12)^ := PInteger(evs + j * 12)^ or Integer(e);
      PInt64(base + 16)^ := j;
    end
    else
    begin
      PInteger(evs + n * 12)^ := Integer(e);
      PInt64(evs + n * 12 + 4)^ := PInt64(base + 24)^;
      PInt64(base + 16)^ := n;                                 { remember the slot }
      Inc(n);
    end;
  end;
  Result := n;
end;

{ TFD_* / EFD_* NONBLOCK and CLOEXEC are the O_* bits on both kernels. }
function FbFdFlags(f: Int64): Int64;
begin
  Result := f and 3;                                           { EFD_SEMAPHORE / TFD_TIMER_* }
  if (f and $800) <> 0 then Result := Result or 4;
  if (f and $80000) <> 0 then Result := Result or $100000;
end;

function FbEventfd(initval, flags: Int64): Int64;
var a: array[0..1] of Integer;
begin
  a[0] := Integer(initval);
  a[1] := Integer(FbFdFlags(flags));
  Result := Lx(FbSys(FB_SPECIALFD, 1, Int64(@a[0]), 8, 0, 0, 0));   { SPECIALFD_EVENTFD }
end;


{ ---- Sockets -----------------------------------------------------------------
  The wire structs agree except for the sockaddr HEADER: Linux has a u16
  family, BSD a u8 length then a u8 family; and AF_INET6 is 10 vs 28. Every
  sockaddr crossing the boundary is rewritten -- inbound into a local copy,
  outbound in place. SOL_SOCKET, the SO_/IP_/IPV6_ option numbers and the MSG_
  flags are renumbered; msghdr and cmsghdr widen/narrow their length fields
  (size_t on Linux, 32-bit on FreeBSD). Measured on 15.1 with offsetof(). }
const
  FB_SOCKET = 97; FB_CONNECT = 98; FB_ACCEPT = 30; FB_SENDTO = 133;
  FB_RECVFROM = 29; FB_SENDMSG = 28; FB_RECVMSG = 27; FB_SHUTDOWN = 134;
  FB_BIND = 104; FB_LISTEN = 106; FB_GETSOCKNAME = 32; FB_GETPEERNAME = 31;
  FB_SOCKETPAIR = 135; FB_SETSOCKOPT = 105; FB_GETSOCKOPT = 118; FB_ACCEPT4 = 541;
  LX_EAFNOSUPPORT = 97; LX_ENOPROTOOPT = 92;

function FbAf(a: Int64): Int64;
begin
  case a of
    0, 1, 2: Result := a;
    10: Result := 28;
  else Result := -1;
  end;
end;

function LxAf(a: Int64): Int64;
begin
  if a = 28 then Result := 10 else Result := a;
end;

{ SOCK_NONBLOCK / SOCK_CLOEXEC ride in the type word on both, at other bits. }
function FbSockType(t: Int64): Int64;
begin
  Result := t and $FF;
  if (t and $800) <> 0 then Result := Result or $20000000;
  if (t and $80000) <> 0 then Result := Result or $10000000;
end;

function FbMsgFlags(f: Int64): Int64;
begin
  Result := f and $7;                                          { OOB PEEK DONTROUTE }
  if (f and $8) <> 0 then Result := Result or $20;             { CTRUNC }
  if (f and $20) <> 0 then Result := Result or $10;            { TRUNC }
  if (f and $40) <> 0 then Result := Result or $80;            { DONTWAIT }
  if (f and $80) <> 0 then Result := Result or $8;             { EOR }
  if (f and $100) <> 0 then Result := Result or $40;           { WAITALL }
  if (f and $4000) <> 0 then Result := Result or $20000;       { NOSIGNAL }
  if (f and $40000000) <> 0 then Result := Result or $40000;   { CMSG_CLOEXEC }
end;

function LxMsgFlags(f: Int64): Int64;
begin
  Result := f and $7;
  if (f and $20) <> 0 then Result := Result or $8;
  if (f and $10) <> 0 then Result := Result or $20;
  if (f and $80) <> 0 then Result := Result or $40;
  if (f and $8) <> 0 then Result := Result or $80;
  if (f and $40) <> 0 then Result := Result or $100;
end;

{ Linux sockaddr (src, len) -> BSD sockaddr in dst (128 B). Answers the
  length to pass, or -errno. }
function SaToFb(src, len, dst: Int64): Int64;
var i, af: Int64;
begin
  if (src = 0) or (len < 2) then begin Result := -LX_EINVAL; Exit; end;
  if len > 128 then len := 128;
  for i := 0 to len - 1 do PByte(dst + i)^ := PByte(src + i)^;
  af := FbAf(PWord(src)^);
  if af < 0 then begin Result := -LX_EAFNOSUPPORT; Exit; end;
  if (af = 1) and (len > 106) then len := 106;                  { sun_path 108 -> 104 }
  PByte(dst)^ := Byte(len);
  PByte(dst + 1)^ := Byte(af);
  Result := len;
end;

{ BSD sockaddr at p, in place, -> Linux shape. }
procedure SaToLx(p, lenp: Int64);
begin
  if (p = 0) or (lenp = 0) or (PInteger(lenp)^ < 2) then Exit;
  PWord(p)^ := Word(LxAf(PByte(p + 1)^));
end;

{ socket option (level, name) -> FreeBSD; level -1 = no equivalent. }
procedure SockOptToFb(var level, name: Int64);
begin
  case level of
    1: begin                                                    { SOL_SOCKET }
         level := $FFFF;
         case name of
           1: name := $1; 2: name := $4; 3: name := $1008; 4: name := $1007;
           5: name := $10; 6: name := $20; 7: name := $1001; 8: name := $1002;
           9: name := $8; 10: name := $100; 13: name := $80; 15: name := $200;
           18: name := $1004; 19: name := $1003; 20: name := $1006; 21: name := $1005;
           30: name := $2; 38: name := $1016; 39: name := $1019;
         else level := -1;
         end;
       end;
    6: case name of                                             { IPPROTO_TCP }
         1, 2: ;
         4: name := $100; 5: name := $200; 6: name := $400;
       else level := -1;
       end;
    0: case name of                                             { IPPROTO_IP }
         1: name := 3; 2: name := 4;
         32: name := 9; 33: name := 10; 34: name := 11; 35: name := 12; 36: name := 13;
       else level := -1;
       end;
    41: case name of                                            { IPPROTO_IPV6 }
          26: name := 27; 16: name := 4; 17: name := 9; 18: name := 10;
          19: name := 11; 20: name := 12; 21: name := 13;
        else level := -1;
        end;
  else
    if level <> 17 then level := -1;                            { IPPROTO_UDP: nothing renumbered }
  end;
end;

function FbSockopt(isGet: Boolean; fd, level, name, val, lenp: Int64): Int64;
var lv, nm, r, e: Int64;
begin
  lv := level; nm := name;
  SockOptToFb(lv, nm);
  if lv < 0 then begin Result := -LX_ENOPROTOOPT; Exit; end;
  if not isGet then
  begin
    Result := Lx(FbSys(FB_SETSOCKOPT, fd, lv, nm, val, lenp, 0));
    Exit;
  end;
  r := FbSys(FB_GETSOCKOPT, fd, lv, nm, val, lenp, 0);
  if (r = 0) and (lv = $FFFF) and (val <> 0) then
  begin
    if nm = $1007 then                                          { SO_ERROR holds an errno }
    begin
      e := PInteger(val)^;
      if (e >= 35) and (e <= 97) then PInteger(val)^ := ErrMap[Integer(e)];
    end
    else if nm = $1019 then PInteger(val)^ := Integer(LxAf(PInteger(val)^));   { SO_DOMAIN }
  end;
  Result := Lx(r);
end;

function FbSockAddrCall(nr, fd, sa, len: Int64): Int64;    { connect, bind }
var b: array[0..15] of Int64; n: Int64;
begin
  n := SaToFb(sa, len, Int64(@b[0]));
  if n < 0 then Result := n
  else Result := Lx(FbSys(nr, fd, Int64(@b[0]), n, 0, 0, 0));
end;

function FbSockAddrOut(nr, fd, sa, lenp, flags: Int64): Int64;  { accept4, getsockname, getpeername }
var r: Int64;
begin
  if nr = FB_ACCEPT4 then
  begin
    r := 0;
    if (flags and $800) <> 0 then r := r or $20000000;
    if (flags and $80000) <> 0 then r := r or $10000000;
    r := FbSys(nr, fd, sa, lenp, r, 0, 0);
  end
  else r := FbSys(nr, fd, sa, lenp, 0, 0, 0);
  if r >= 0 then SaToLx(sa, lenp);
  Result := Lx(r);
end;

function FbSendto(fd, buf, len, flags, sa, salen: Int64): Int64;
var b: array[0..15] of Int64; n: Int64;
begin
  if sa = 0 then
  begin
    Result := Lx(FbSys(FB_SENDTO, fd, buf, len, FbMsgFlags(flags), 0, 0));
    Exit;
  end;
  n := SaToFb(sa, salen, Int64(@b[0]));
  if n < 0 then Result := n
  else Result := Lx(FbSys(FB_SENDTO, fd, buf, len, FbMsgFlags(flags), Int64(@b[0]), n));
end;

function FbRecvfrom(fd, buf, len, flags, sa, lenp: Int64): Int64;
var r: Int64;
begin
  r := FbSys(FB_RECVFROM, fd, buf, len, FbMsgFlags(flags), sa, lenp);
  if r >= 0 then SaToLx(sa, lenp);
  Result := Lx(r);
end;

{ Linux cmsg chain (size_t len, int level, int type; data at 16) <-> FreeBSD
  (u32 len, int level, int type; data at 16 -- _ALIGN(12) on amd64). Rewritten
  in place: both headers fit the same 16 bytes and the data does not move.
  SOL_SOCKET is the only level renumbered; SCM_RIGHTS is 1 on both. }
procedure CmsgToFb(ctl, clen: Int64);
var p, l: Int64;
begin
  p := ctl;
  while (ctl <> 0) and (p + 16 <= ctl + clen) do
  begin
    l := PInt64(p)^;
    if l < 16 then Exit;
    PInteger(p)^ := Integer(l);
    PInteger(p + 4)^ := PInteger(p + 8)^;                       { level }
    if PInteger(p + 4)^ = 1 then PInteger(p + 4)^ := $FFFF;
    PInteger(p + 8)^ := PInteger(p + 12)^;                      { type }
    PInteger(p + 12)^ := 0;
    p := p + ((l + 7) and not Int64(7));
  end;
end;

procedure CmsgToLx(ctl, clen: Int64);
var p, l, lv, ty: Int64;
begin
  p := ctl;
  while (ctl <> 0) and (p + 16 <= ctl + clen) do
  begin
    l := PInteger(p)^ and $FFFFFFFF;
    if l < 12 then Exit;
    lv := PInteger(p + 4)^; ty := PInteger(p + 8)^;
    if lv = $FFFF then lv := 1;
    PInt64(p)^ := l;                                            { CMSG_LEN(n) = 16 + n on both }
    PInteger(p + 8)^ := Integer(lv);
    PInteger(p + 12)^ := Integer(ty);
    p := p + ((l + 7) and not Int64(7));
  end;
end;

{ msghdr: Linux 56 B (size_t iovlen/controllen, flags at 48), FreeBSD 48 B. }
function FbMsg(isSend: Boolean; fd, lm, flags: Int64): Int64;
var fm: array[0..5] of Int64;
    nb: array[0..15] of Int64;
    r, n: Int64;
begin
  fm[0] := PInt64(lm)^;                                         { msg_name }
  fm[1] := PInteger(lm + 8)^;                                   { msg_namelen (int, upper 4 = 0) }
  fm[2] := PInt64(lm + 16)^;                                    { msg_iov }
  fm[3] := PInt64(lm + 24)^ and $FFFFFFFF;                      { msg_iovlen }
  fm[4] := PInt64(lm + 32)^;                                    { msg_control }
  fm[5] := PInt64(lm + 40)^ and $FFFFFFFF;                      { msg_controllen; flags = 0 }
  if isSend then
  begin
    if fm[0] <> 0 then
    begin
      n := SaToFb(fm[0], fm[1], Int64(@nb[0]));
      if n < 0 then begin Result := n; Exit; end;
      fm[0] := Int64(@nb[0]); fm[1] := n;
    end;
    CmsgToFb(fm[4], fm[5]);
    r := FbSys(FB_SENDMSG, fd, Int64(@fm[0]), FbMsgFlags(flags), 0, 0, 0);
    CmsgToLx(fm[4], fm[5]);                                     { the caller's buffer, restored }
  end
  else
  begin
    r := FbSys(FB_RECVMSG, fd, Int64(@fm[0]), FbMsgFlags(flags), 0, 0, 0);
    if r >= 0 then
    begin
      if fm[0] <> 0 then
      begin
        PWord(fm[0])^ := Word(LxAf(PByte(fm[0] + 1)^));
        PInteger(lm + 8)^ := PInteger(Int64(@fm[1]))^;
      end;
      n := PInteger(Int64(@fm[5]))^ and $FFFFFFFF;
      CmsgToLx(fm[4], n);
      PInt64(lm + 40)^ := n;
      PInteger(lm + 48)^ := Integer(LxMsgFlags(PInteger(Int64(@fm[5]) + 4)^));
    end;
  end;
  Result := Lx(r);
end;


{ ---- termios -----------------------------------------------------------------
  Linux's kernel struct termios is 36 bytes (4 flag words, c_line, c_cc[19]),
  with the line speed coded into c_cflag (CBAUD); FreeBSD's is 44 (4 flag
  words, c_cc[20], c_ispeed, c_ospeed as plain numbers). Almost every flag bit
  and every c_cc index differs; a disabled control char is 0 on Linux and
  0xff (_POSIX_VDISABLE) on FreeBSD. Both sides measured from headers. }
const
  TIflLx: array[0..13] of Int64 = ($1,$2,$4,$8,$10,$20,$40,$80,$100,$400,$1000,$800,$2000,$4000);
  TIflFb: array[0..13] of Int64 = ($1,$2,$4,$8,$10,$20,$40,$80,$100,$200,$400,$800,$2000,$4000);
  TOflLx: array[0..5] of Int64 = ($1,$4,$1800,$8,$10,$20);
  TOflFb: array[0..5] of Int64 = ($1,$2,$4,$10,$20,$40);
  TCflLx: array[0..6] of Int64 = ($40,$80,$100,$200,$400,$800,$80000000);
  TCflFb: array[0..6] of Int64 = ($400,$800,$1000,$2000,$4000,$8000,$30000);
  TLflLx: array[0..13] of Int64 = ($1,$2,$8,$10,$20,$40,$80,$100,$200,$400,$800,$1000,$4000,$8000);
  TLflFb: array[0..13] of Int64 = ($80,$100,$8,$2,$4,$10,$80000000,$400000,$40,$20,$1,$800000,$20000000,$400);
  { Linux c_cc index -> FreeBSD index (-1: VSWTC, none) }
  TCcMap: array[0..16] of Integer = (8,9,3,5,0,17,16,-1,12,13,10,1,6,15,4,14,2);
  { Linux CBAUD codes 0..15 and $1001..$100F as line speeds }
  TBaudLo: array[0..15] of Integer = (0,50,75,110,134,150,200,300,600,1200,1800,2400,4800,9600,19200,38400);
  TBaudHi: array[1..15] of Integer = (57600,115200,230400,460800,500000,576000,921600,
                                      1000000,1152000,1500000,2000000,2500000,3000000,3500000,4000000);

function MapBits(v: Int64; const src, dst: array of Int64): Int64;
var i: Integer;
begin
  Result := 0;
  for i := 0 to High(src) do
    if (v and src[i]) = src[i] then Result := Result or dst[i];
end;

function SpeedToLx(n: Int64): Int64;
var i: Integer;
begin
  for i := 0 to 15 do if TBaudLo[i] = n then begin Result := i; Exit; end;
  for i := 1 to 15 do if TBaudHi[i] = n then begin Result := $1000 or i; Exit; end;
  Result := 15;                                                 { unknown: B38400 }
end;

function SpeedToFb(c: Int64): Int64;
begin
  c := c and $100F;
  if c <= 15 then Result := TBaudLo[Integer(c)]
  else if (c and $F) >= 1 then Result := TBaudHi[Integer(c and $F)]
  else Result := 38400;
end;

procedure TermiosToLx(fb, lx: Int64);
var i, ix: Integer; c: Byte; cf: Int64;
begin
  for i := 0 to 35 do PByte(lx + i)^ := 0;
  PInteger(lx)^ := Integer(MapBits(PInteger(fb)^, TIflFb, TIflLx));
  PInteger(lx + 4)^ := Integer(MapBits(PInteger(fb + 4)^, TOflFb, TOflLx));
  cf := MapBits(PInteger(fb + 8)^ and $FFFFFFFF, TCflFb, TCflLx);
  cf := cf or (((PInteger(fb + 8)^ shr 8) and 3) shl 4);        { CSIZE }
  cf := cf or SpeedToLx(PInteger(fb + 40)^);                    { c_ospeed -> CBAUD }
  PInteger(lx + 8)^ := Integer(cf);
  PInteger(lx + 12)^ := Integer(MapBits(PInteger(fb + 12)^ and $FFFFFFFF, TLflFb, TLflLx));
  for i := 0 to 16 do
  begin
    ix := TCcMap[i];
    if ix < 0 then Continue;
    c := PByte(fb + 16 + ix)^;
    if (c = $FF) and (i <> 5) and (i <> 6) then c := 0;         { VTIME/VMIN are numbers }
    PByte(lx + 17 + i)^ := c;
  end;
end;

procedure TermiosToFb(lx, fb: Int64);
var i, ix: Integer; c: Byte; cf, sp: Int64;
begin
  for i := 0 to 43 do PByte(fb + i)^ := 0;
  for i := 0 to 19 do PByte(fb + 16 + i)^ := $FF;
  PInteger(fb)^ := Integer(MapBits(PInteger(lx)^, TIflLx, TIflFb));
  PInteger(fb + 4)^ := Integer(MapBits(PInteger(lx + 4)^, TOflLx, TOflFb));
  cf := PInteger(lx + 8)^ and $FFFFFFFF;
  PInteger(fb + 8)^ := Integer(MapBits(cf, TCflLx, TCflFb) or (((cf shr 4) and 3) shl 8));
  PInteger(fb + 12)^ := Integer(MapBits(PInteger(lx + 12)^, TLflLx, TLflFb));
  for i := 0 to 16 do
  begin
    ix := TCcMap[i];
    if ix < 0 then Continue;
    c := PByte(lx + 17 + i)^;
    if (c = 0) and (i <> 5) and (i <> 6) then c := $FF;
    PByte(fb + 16 + ix)^ := c;
  end;
  sp := SpeedToFb(cf);
  PInteger(fb + 36)^ := Integer(sp);
  PInteger(fb + 40)^ := Integer(sp);
end;

{ ---- Scheduler, process odds and ends -------------------------------------- }

{ Policies: Linux OTHER 0 / FIFO 1 / RR 2, FreeBSD FIFO 1 / OTHER 2 / RR 3.
  Linux's SCHED_RESET_ON_FORK ($40000000) has no FreeBSD twin and is dropped. }
function FbPolicy(p: Int64): Int64;
begin
  case p and $3FFFFFFF of
    0: Result := 2; 1: Result := 1; 2: Result := 3;
  else Result := -1;
  end;
end;

function LxPolicy(p: Int64): Int64;
begin
  case p of
    2: Result := 0; 1: Result := 1; 3: Result := 2;
  else Result := p;
  end;
end;

{ open/openat: a symlink met under O_NOFOLLOW is EMLINK on FreeBSD (POSIX
  allows either) and ELOOP on Linux. }
function FbOpenAt(dirfd, path, flags, mode: Int64): Int64;
begin
  Result := Lx(FbSys(FB_OPENAT, dirfd, path, FbOpenFlags(flags), mode, 0, 0));
  if (Result = -31) and ((flags and $20000) <> 0) then Result := -40;
end;

var
  FbPersona: Int64;                         { personality(2): Linux's default PER_LINUX }
  FbCommSet: Boolean;
  FbComm: array[0..15] of Byte;             { PR_SET_NAME's copy: FreeBSD can set a thread name but not read one back cheaply }

{ prctl: PR_SET_NAME (15) -> thr_set_name on this thread, PR_GET_NAME (16)
  answers the last name set, else the executable's basename as Linux's comm
  would (15 chars). Any other option is EINVAL, as an unknown one is on Linux. }
function FbPrctl(op, arg: Int64): Int64;
var tid: Int64; i, n, s: Integer; tmp: array[0..1023] of Byte;
begin
  case op of
    15: begin
          for i := 0 to 15 do FbComm[i] := 0;
          i := 0;
          while (i < 15) and (PByte(arg + i)^ <> 0) do begin FbComm[i] := PByte(arg + i)^; i := i + 1; end;
          FbCommSet := True;
          tid := 0;
          FbSys(FB_THR_SELF, Int64(@tid), 0, 0, 0, 0, 0);
          FbSys(FB_THR_SET_NAME, tid, Int64(@FbComm[0]), 0, 0, 0, 0);
          Result := 0;
        end;
    16: begin
          if not FbCommSet then begin
            n := Integer(FbProcExe(Int64(@tmp[0]), 1024));
            s := 0;
            for i := 0 to n - 1 do if tmp[i] = 47 then s := i + 1;
            for i := 0 to 15 do FbComm[i] := 0;
            i := 0;
            while (i < 15) and (s + i < n) do begin FbComm[i] := tmp[s + i]; i := i + 1; end;
          end;
          for i := 0 to 15 do PByte(arg + i)^ := FbComm[i];
          Result := 0;
        end;
  else Result := -LX_EINVAL;               { Linux's answer to an option it does not know }
  end;
end;

function PXXFbsdSyscall(nr, a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl;
var sb: array[0..27] of Int64;
    t: array[0..5] of Int64;
    r, f: Int64;
    i: Integer;
begin
  if FbMainTid = 0 then                    { the very first syscall is the main thread's }
  begin
    FbSys(FB_THR_SELF, Int64(@FbMainTid), 0, 0, 0, 0, 0);
    if FbMainTid = 0 then FbMainTid := -1;
  end;
  case Integer(nr) of
    0: begin
         { a 0-byte read of a directory is EISDIR on Linux (pylib's open()
           uses it as the directory probe) and 0 on FreeBSD }
         if (a2 = 0) and (FbSys(FB_FSTAT, a0, Int64(@sb[0]), 0, 0, 0, 0) = 0) and
            ((PWord(Int64(@sb[0]) + 24)^ and $F000) = $4000) then Result := -21
         else Result := Lx(FbSys(FB_READ, a0, a1, a2, 0, 0, 0));
       end;
    1: Result := Lx(FbSys(FB_WRITE, a0, a1, a2, 0, 0, 0));
    2: if PathIs(a0, ProcEnviron) then Result := FbProcEnviron
       else if PathIs(a0, DevPtmx) then Result := Lx(FbSys(FB_POSIX_OPENPT, FbOpenFlags(a1), 0, 0, 0, 0, 0))
       else if PathIs(a0, ProcHostname) then Result := FbProcHostname
       else Result := FbOpenAt(FB_AT_FDCWD, a0, a1, a2);
    3: Result := Lx(FbSys(FB_CLOSE, a0, 0, 0, 0, 0, 0));
    4: Result := FbStatAt(FB_AT_FDCWD, a0, a1, 0);              { stat }
    5: begin                                                    { fstat }
         r := FbSys(FB_FSTAT, a0, Int64(@sb[0]), 0, 0, 0, 0);
         if r = 0 then StatToLinux(@sb[0], Pointer(a1));
         Result := Lx(r);
       end;
    6: Result := FbStatAt(FB_AT_FDCWD, a0, a1, $100);           { lstat }
    7: Result := FbPoll(a0, a1, a2, 0, False);
    8: Result := Lx(FbSys(FB_LSEEK, a0, a1, a2, 0, 0, 0));
    9: Result := Lx(FbSys(FB_MMAP, a0, a1, a2, FbMmapFlags(a3), a4, a5));
    10: Result := Lx(FbSys(FB_MPROTECT, a0, a1, a2, 0, 0, 0));
    11: Result := Lx(FbSys(FB_MUNMAP, a0, a1, 0, 0, 0, 0));
    12: Result := FbBrk(a0);
    13: Result := FbRtSigaction(a0, a1, a2);
    14: Result := FbRtSigprocmask(a0, a1, a2);
    127: begin                                                  { rt_sigpending }
           t[0] := 0; t[1] := 0;
           r := FbSys(FB_SIGPENDING, Int64(@t[0]), 0, 0, 0, 0, 0);
           if r = 0 then PInt64(a0)^ := MaskToLx(Int64(@t[0]));
           Result := Lx(r);
         end;
    128: Result := FbRtSigtimedwait(a0, a1, a2);
    130: begin                                                  { rt_sigsuspend }
           MaskToFb(PInt64(a0)^, Int64(@t[0]));
           Result := Lx(FbSys(FB_SIGSUSPEND, Int64(@t[0]), 0, 0, 0, 0, 0));
         end;
    16: case Integer(a1) of                                              { ioctl }
          $5401: begin                                          { TCGETS -> TIOCGETA }
                   r := FbSys(FB_IOCTL, a0, $402C7413, Int64(@sb[0]), 0, 0, 0);
                   if (r = 0) and (a2 <> 0) then TermiosToLx(Int64(@sb[0]), a2);
                   Result := Lx(r);
                 end;
          $5402, $5403, $5404: begin                            { TCSETS/W/F -> TIOCSETA/W/F }
                   TermiosToFb(a2, Int64(@sb[0]));
                   Result := Lx(FbSys(FB_IOCTL, a0, $802C7414 + (a1 - $5402), Int64(@sb[0]), 0, 0, 0));
                 end;
          $540B: begin                                          { TCFLSH -> TIOCFLUSH(FREAD/FWRITE) }
                   if (a2 < 0) or (a2 > 2) then Result := -LX_EINVAL
                   else
                   begin
                     t[0] := a2 + 1;
                     Result := Lx(FbSys(FB_IOCTL, a0, $80047410, Int64(@t[0]), 0, 0, 0));
                   end;
                 end;
          $5409: if a2 <> 0 then Result := Lx(FbSys(FB_IOCTL, a0, $2000745E, 0, 0, 0, 0))  { TCSBRK: drain }
                 else Result := 0;                              { (the 0.25 s break is not sent) }
          $540A: case Integer(a2) of                            { TCXONC }
                   0: Result := Lx(FbSys(FB_IOCTL, a0, $2000746F, 0, 0, 0, 0));   { TCOOFF -> TIOCSTOP }
                   1: Result := Lx(FbSys(FB_IOCTL, a0, $2000746E, 0, 0, 0, 0));   { TCOON -> TIOCSTART }
                 else Result := 0;
                 end;
          $5427: Result := Lx(FbSys(FB_IOCTL, a0, $2000747B, 0, 0, 0, 0));   { TIOCSBRK }
          -2147199952: begin                                    { $80045430 TIOCGPTN (the case is on Integer): FIODGNAME "pts/N" -> N }
                   t[0] := 64; t[1] := Int64(@sb[0]);
                   r := FbSys(FB_IOCTL, a0, $80106678, Int64(@t[0]), 0, 0, 0);
                   if r < 0 then begin Result := Lx(r); Exit; end;
                   f := 0; i := 4;                              { past "pts/" }
                   while (PByte(Int64(@sb[0]) + i)^ >= 48) and (PByte(Int64(@sb[0]) + i)^ <= 57) do
                   begin
                     f := f * 10 + PByte(Int64(@sb[0]) + i)^ - 48;
                     Inc(i);
                   end;
                   PInteger(a2)^ := Integer(f);
                   Result := 0;
                 end;
          $40045431: Result := 0;                               { TIOCSPTLCK: FreeBSD ptys have no lock }
          $5428: Result := Lx(FbSys(FB_IOCTL, a0, $2000747A, 0, 0, 0, 0));   { TIOCCBRK }
          $5413: Result := Lx(FbSys(FB_IOCTL, a0, $40087468, a2, 0, 0, 0));  { TIOCGWINSZ }
          $541B: Result := Lx(FbSys(FB_IOCTL, a0, $4004667F, a2, 0, 0, 0));  { FIONREAD }
          $540E: Result := Lx(FbSys(FB_IOCTL, a0, $20007461, 0, 0, 0, 0));   { TIOCSCTTY }
          $540F, $5410: begin                                   { TIOCGPGRP / TIOCSPGRP }
                   { tty only: FreeBSD pipes and sockets also accept these
                     (as the SIGIO owner), Linux answers ENOTTY }
                   r := FbSys(FB_IOCTL, a0, $402C7413, Int64(@sb[0]), 0, 0, 0);
                   if r = -25 then Result := -LX_ENOTTY
                   else if r < 0 then Result := Lx(r)
                   else if a1 = $540F then Result := Lx(FbSys(FB_IOCTL, a0, $40047477, a2, 0, 0, 0))
                   else Result := Lx(FbSys(FB_IOCTL, a0, $80047476, a2, 0, 0, 0));
                 end;
          $5411: Result := Lx(FbSys(FB_IOCTL, a0, $40047473, a2, 0, 0, 0));  { TIOCOUTQ }
          $5414: Result := Lx(FbSys(FB_IOCTL, a0, $80087467, a2, 0, 0, 0));  { TIOCSWINSZ }
          $5421: Result := Lx(FbSys(FB_IOCTL, a0, $8004667E, a2, 0, 0, 0));  { FIONBIO }
          $5422: Result := Lx(FbSys(FB_IOCTL, a0, $20007471, 0, 0, 0, 0));   { TIOCNOTTY }
          $5429: Result := Lx(FbSys(FB_IOCTL, a0, $40047463, a2, 0, 0, 0));  { TIOCGSID }
          $5450: Result := Lx(FbSys(FB_IOCTL, a0, $20006602, 0, 0, 0, 0));   { FIONCLEX }
          $5451: Result := Lx(FbSys(FB_IOCTL, a0, $20006601, 0, 0, 0, 0));   { FIOCLEX }
          $5452: Result := Lx(FbSys(FB_IOCTL, a0, $8004667D, a2, 0, 0, 0));  { FIOASYNC }
        else
          { unmapped: a bad fd is still EBADF, as the kernel would say first }
          if FbSys(FB_FCNTL, a0, FB_F_GETFD, 0, 0, 0, 0) < 0 then Result := -9
          else Result := -LX_ENOTTY;
        end;
    17: Result := Lx(FbSys(FB_PREAD, a0, a1, a2, a3, 0, 0));
    18: Result := Lx(FbSys(FB_PWRITE, a0, a1, a2, a3, 0, 0));
    19: Result := Lx(FbSys(FB_READV, a0, a1, a2, 0, 0, 0));
    20: Result := Lx(FbSys(FB_WRITEV, a0, a1, a2, 0, 0, 0));
    23: Result := Lx(FbSys(FB_SELECT, a0, a1, a2, a3, a4, 0));  { fd_set, timeval identical }
    21: Result := Lx(FbSys(FB_ACCESS, a0, a1, 0, 0, 0, 0));
    22: Result := Lx(FbSys(FB_PIPE2, a0, 0, 0, 0, 0, 0));
    24: Result := Lx(FbSys(FB_SCHED_YIELD, 0, 0, 0, 0, 0, 0));
    28: begin                                                   { madvise: advice is a hint }
          f := a2;
          if f = 8 then f := 5;                                 { MADV_FREE }
          if f > 5 then Result := 0
          else Result := Lx(FbSys(FB_MADVISE, a0, a1, f, 0, 0, 0));
        end;
    32: Result := Lx(FbSys(FB_DUP, a0, 0, 0, 0, 0, 0));
    33: Result := Lx(FbSys(FB_DUP2, a0, a1, 0, 0, 0, 0));
    35: Result := Lx(FbSys(FB_NANOSLEEP, a0, a1, 0, 0, 0, 0));
    39: Result := FbSys(FB_GETPID, 0, 0, 0, 0, 0, 0);
    57: begin                                                   { fork: rdx = 1 in the child }
          r := FbSys(FB_FORK, 0, 0, 0, 0, 0, 0);
          if (r >= 0) and (FbRdx <> 0) then r := 0;
          Result := Lx(r);
        end;
    59: Result := Lx(FbSys(FB_EXECVE, a0, a1, a2, 0, 0, 0));
    60: begin                                                   { exit: THIS thread }
          t[0] := 0;
          FbSys(FB_THR_SELF, Int64(@t[0]), 0, 0, 0, 0, 0);
          if t[0] <> FbMainTid then
          begin
            { CLONE_CHILD_CLEARTID, as the clone stub's own exit does: the tid
              word's address is in this thread's TLS slot 14 (put there by the
              stub's thr_new entry); clear it once the parent has stored the
              tid, and wake the joiner. }
            r := PInt64(Int64(__pxxTlsBase) + 8 * 14)^;
            if r <> 0 then
            begin
              while PInteger(r)^ = 0 do FbSys(FB_SCHED_YIELD, 0, 0, 0, 0, 0, 0);
              FbClearTidExit(r);                                { no stack use after the clear }
            end;
            FbSys(FB_THR_EXIT, 0, 0, 0, 0, 0, 0);
          end;
          FbSys(FB_EXIT, a0, 0, 0, 0, 0, 0);
          Result := 0;
        end;
    231: begin FbSys(FB_EXIT, a0, 0, 0, 0, 0, 0); Result := 0; end;   { exit_group }
    202: begin                                                  { futex -> _umtx_op }
           f := a1 and 127;                                     { minus PRIVATE / CLOCK_REALTIME }
           if f = 0 then                                        { FUTEX_WAIT }
           begin
             if (a1 and 128) <> 0 then f := 15 else f := 11;    { UMTX_OP_WAIT_UINT[_PRIVATE] }
             if a3 <> 0 then r := FbSys(FB_UMTX_OP, a0, f, a2 and $FFFFFFFF, 16, a3, 0)
             else r := FbSys(FB_UMTX_OP, a0, f, a2 and $FFFFFFFF, 0, 0, 0);
             Result := Lx(r);
           end
           else if f = 1 then                                   { FUTEX_WAKE }
           begin
             if (a1 and 128) <> 0 then f := 16 else f := 3;     { UMTX_OP_WAKE[_PRIVATE] }
             r := FbSys(FB_UMTX_OP, a0, f, a2, 0, 0, 0);
             if r >= 0 then Result := 0 else Result := Lx(r);   { (Linux answers the count woken) }
           end
           else Result := -LX_ENOSYS;
         end;
    200: Result := Lx(FbSys(FB_THR_KILL, a0, FbSig(a1), 0, 0, 0, 0));    { tkill }
    203, 204: begin                                             { sched_set/getaffinity -> cpuset_* }
                { CPU_LEVEL_WHICH; pid 0 = the calling thread (CPU_WHICH_TID, -1),
                  else that process. The mask bits agree (bit i = cpu i). Linux
                  answers the mask size it copied; FreeBSD answers 0. }
                for i := 0 to 15 do sb[i] := 0;                 { cpuset_t, 128 B }
                if a0 = 0 then begin f := 1; r := -1; end else begin f := 2; r := a0; end;
                if a1 > 128 then a1 := 128;
                if nr = 203 then
                begin
                  for i := 0 to Integer(a1) - 1 do PByte(Int64(@sb[0]) + i)^ := PByte(a2 + i)^;
                  Result := Lx(FbSys(488, 3, f, r, 128, Int64(@sb[0]), 0));
                end
                else
                begin
                  r := FbSys(487, 3, f, r, 128, Int64(@sb[0]), 0);
                  if r < 0 then Result := Lx(r)
                  else
                  begin
                    for i := 0 to Integer(a1) - 1 do PByte(a2 + i)^ := PByte(Int64(@sb[0]) + i)^;
                    Result := a1;
                  end;
                end;
              end;
    234: Result := Lx(FbSys(FB_THR_KILL, a1, FbSig(a2), 0, 0, 0, 0));    { tgkill }
    61: Result := FbWait4(a0, a1, a2, a3);
    62: Result := Lx(FbSys(FB_KILL, a0, FbSig(a1), 0, 0, 0, 0));
    63: Result := FbUname(a0);
    72: case Integer(a1) of                                              { fcntl }
          3: begin
               r := FbSys(FB_FCNTL, a0, 3, 0, 0, 0, 0);
               if r >= 0 then r := LxOpenFlags(r);
               Result := Lx(r);
             end;
          4: Result := Lx(FbSys(FB_FCNTL, a0, 4, FbOpenFlags(a2), 0, 0, 0));
          0, 1, 2: Result := Lx(FbSys(FB_FCNTL, a0, a1, a2, 0, 0, 0));
          1030: Result := Lx(FbSys(FB_FCNTL, a0, 17, a2, 0, 0, 0));     { F_DUPFD_CLOEXEC }
        else
          Result := -LX_ENOSYS;                                 { locks: struct flock differs }
        end;
    74: Result := Lx(FbSys(FB_FSYNC, a0, 0, 0, 0, 0, 0));
    77: Result := Lx(FbSys(FB_FTRUNCATE, a0, a1, 0, 0, 0, 0));
    79: begin                                                   { getcwd: Linux returns the length }
          r := FbSys(FB_GETCWD, a0, a1, 0, 0, 0, 0);
          if r = 0 then r := StrLen0(a0) + 1;
          Result := Lx(r);
        end;
    80: Result := Lx(FbSys(FB_CHDIR, a0, 0, 0, 0, 0, 0));
    82: Result := Lx(FbSys(FB_RENAME, a0, a1, 0, 0, 0, 0));
    83: Result := Lx(FbSys(FB_MKDIR, a0, a1, 0, 0, 0, 0));
    84: Result := Lx(FbSys(FB_RMDIR, a0, 0, 0, 0, 0, 0));
    87: Result := Lx(FbSys(FB_UNLINK, a0, 0, 0, 0, 0, 0));
    89: if PathIs(a0, ProcExe) then Result := FbProcExe(a1, a2)
        else if ProcFdNum(a0) >= 0 then Result := FbProcFd(ProcFdNum(a0), a1, a2)
        else Result := Lx(FbSys(FB_READLINK, a0, a1, a2, 0, 0, 0));
    90: Result := Lx(FbSys(FB_CHMOD, a0, a1, 0, 0, 0, 0));
    95: Result := FbSys(FB_UMASK, a0, 0, 0, 0, 0, 0);
    96: Result := Lx(FbSys(FB_GETTIMEOFDAY, a0, a1, 0, 0, 0, 0));
    97: Result := FbGetRlimit(a0, a1);
    102: Result := FbSys(FB_GETUID, 0, 0, 0, 0, 0, 0);
    104: Result := FbSys(FB_GETGID, 0, 0, 0, 0, 0, 0);
    107: Result := FbSys(FB_GETEUID, 0, 0, 0, 0, 0, 0);
    108: Result := FbSys(FB_GETEGID, 0, 0, 0, 0, 0, 0);
    110: Result := FbSys(FB_GETPPID, 0, 0, 0, 0, 0, 0);
    112: Result := Lx(FbSys(FB_SETSID, 0, 0, 0, 0, 0, 0));
    131: begin                                                  { sigaltstack: field order differs }
           if a0 <> 0 then
           begin
             t[0] := PInt64(a0)^;                               { ss_sp }
             t[1] := PInt64(a0 + 16)^;                          { ss_size }
             f := PInteger(a0 + 8)^;                            { ss_flags }
             t[2] := 0;
             if (f and 1) <> 0 then t[2] := t[2] or 1;          { SS_ONSTACK }
             if (f and 2) <> 0 then t[2] := t[2] or 4;          { SS_DISABLE }
           end;
           r := 0;
           if a0 <> 0 then r := Int64(@t[0]);
           f := 0;
           if a1 <> 0 then f := Int64(@t[3]);
           r := FbSys(FB_SIGALTSTACK, r, f, 0, 0, 0, 0);
           if (r = 0) and (a1 <> 0) then
           begin
             PInt64(a1)^ := t[3];
             PInt64(a1 + 16)^ := t[4];
             f := 0;
             if (t[5] and 1) <> 0 then f := f or 1;
             if (t[5] and 4) <> 0 then f := f or 2;
             PInteger(a1 + 8)^ := Integer(f);
           end;
           Result := Lx(r);
         end;
    158: case Integer(a0) of                                             { arch_prctl -> sysarch }
           $1001: begin t[0] := a1; Result := Lx(FbSys(FB_SYSARCH, 131, Int64(@t[0]), 0, 0, 0, 0)); end;
           $1002: begin t[0] := a1; Result := Lx(FbSys(FB_SYSARCH, 129, Int64(@t[0]), 0, 0, 0, 0)); end;
           $1003: Result := Lx(FbSys(FB_SYSARCH, 128, a1, 0, 0, 0, 0));
           $1004: Result := Lx(FbSys(FB_SYSARCH, 130, a1, 0, 0, 0, 0));
         else
           Result := -LX_EINVAL;
         end;
    160: Result := FbSetRlimit(a0, a1);
    186, 218: begin                                             { gettid, set_tid_address }
                t[0] := 0;
                FbSys(FB_THR_SELF, Int64(@t[0]), 0, 0, 0, 0, 0);
                Result := t[0];
              end;
    201: begin                                                  { time }
           FbSys(FB_CLOCK_GETTIME, 0, Int64(@t[0]), 0, 0, 0, 0);
           if a0 <> 0 then PInt64(a0)^ := t[0];
           Result := t[0];
         end;
    217: begin                                                  { getdents64 }
           r := FbSys(FB_GETDIRENTRIES, a0, a1, a2, 0, 0, 0);
           if r > 0 then DirentsToLinux(Pointer(a1), r);
           Result := Lx(r);
         end;
    228: Result := Lx(FbSys(FB_CLOCK_GETTIME, FbClock(a0), a1, 0, 0, 0, 0));
    229: Result := Lx(FbSys(FB_CLOCK_GETRES, FbClock(a0), a1, 0, 0, 0, 0));
    230: Result := Lx(FbSys(FB_CLOCK_NANOSLEEP, FbClock(a0), a1, a2, a3, 0, 0));
    257: if PathIs(a1, ProcEnviron) then Result := FbProcEnviron
         else if PathIs(a1, DevPtmx) then Result := Lx(FbSys(FB_POSIX_OPENPT, FbOpenFlags(a2), 0, 0, 0, 0, 0))
         else if PathIs(a1, ProcHostname) then Result := FbProcHostname
         else Result := FbOpenAt(a0, a1, a2, a3);
    258: Result := Lx(FbSys(FB_MKDIRAT, a0, a1, a2, 0, 0, 0));
    262: Result := FbStatAt(a0, a1, a2, a3);                    { newfstatat }
    263: begin                                                  { unlinkat }
           f := 0;
           if (a2 and $200) <> 0 then f := FB_AT_REMOVEDIR;
           Result := Lx(FbSys(FB_UNLINKAT, a0, a1, f, 0, 0, 0));
         end;
    264: Result := Lx(FbSys(FB_RENAMEAT, a0, a1, a2, a3, 0, 0));
    267: if PathIs(a1, ProcExe) then Result := FbProcExe(a2, a3)
         else if ProcFdNum(a1) >= 0 then Result := FbProcFd(ProcFdNum(a1), a2, a3)
         else Result := Lx(FbSys(FB_READLINKAT, a0, a1, a2, a3, 0, 0));
    269: begin                                                  { faccessat }
           f := 0;
           if (a3 and $200) <> 0 then f := FB_AT_EACCESS;
           Result := Lx(FbSys(FB_FACCESSAT, a0, a1, a2, f, 0, 0));
         end;
    292: begin                                                  { dup3 }
           if a0 = a1 then Result := -LX_EINVAL
           else if (a2 and $80000) <> 0 then
             Result := Lx(FbSys(FB_FCNTL, a0, 18, a1, 0, 0, 0)) { F_DUP2FD_CLOEXEC }
           else
             Result := Lx(FbSys(FB_FCNTL, a0, 10, a1, 0, 0, 0)); { F_DUP2FD }
         end;
    293: Result := Lx(FbSys(FB_PIPE2, a0, FbOpenFlags(a1), 0, 0, 0, 0));
    302: begin                                                  { prlimit64, self only }
           if a0 <> 0 then begin Result := -LX_EINVAL; Exit; end;
           r := 0;
           if a3 <> 0 then r := FbGetRlimit(a1, a3);
           if (r = 0) and (a2 <> 0) then r := FbSetRlimit(a1, a2);
           Result := r;
         end;
    318: Result := Lx(FbSys(FB_GETRANDOM, a0, a1, a2, 0, 0, 0));
    34: begin                                                   { pause }
          t[0] := 0; t[1] := 0;
          FbSys(FB_SIGPROCMASK, 1, 0, Int64(@t[0]), 0, 0, 0);
          Result := Lx(FbSys(FB_SIGSUSPEND, Int64(@t[0]), 0, 0, 0, 0, 0));
        end;
    36: Result := Lx(FbSys(FB_GETITIMER, a0, a1, 0, 0, 0, 0));
    37: Result := FbAlarm(a0);
    38: Result := Lx(FbSys(FB_SETITIMER, a0, a1, a2, 0, 0, 0));
    58: begin                                                   { vfork: as fork -- a shared-memory child }
          r := FbSys(FB_FORK, 0, 0, 0, 0, 0, 0);                { would return through this frame }
          if (r >= 0) and (FbRdx <> 0) then r := 0;
          Result := Lx(r);
        end;
    73: Result := Lx(FbSys(FB_FLOCK, a0, a1, 0, 0, 0, 0));
    75: Result := Lx(FbSys(FB_FDATASYNC, a0, 0, 0, 0, 0, 0));
    76: Result := Lx(FbSys(FB_TRUNCATE, a0, a1, 0, 0, 0, 0));
    81: Result := Lx(FbSys(FB_FCHDIR, a0, 0, 0, 0, 0, 0));
    86: Result := Lx(FbSys(FB_LINK, a0, a1, 0, 0, 0, 0));
    88: Result := Lx(FbSys(FB_SYMLINK, a0, a1, 0, 0, 0, 0));
    91: Result := Lx(FbSys(FB_FCHMOD, a0, a1, 0, 0, 0, 0));
    92: Result := Lx(FbSys(FB_CHOWN, a0, a1, a2, 0, 0, 0));
    93: Result := Lx(FbSys(FB_FCHOWN, a0, a1, a2, 0, 0, 0));
    94: Result := Lx(FbSys(FB_LCHOWN, a0, a1, a2, 0, 0, 0));
    98: Result := Lx(FbSys(FB_GETRUSAGE, a0, a1, 0, 0, 0, 0));  { struct rusage identical }
    100: Result := FbTimes(a0);
    105: Result := Lx(FbSys(FB_SETUID, a0, 0, 0, 0, 0, 0));
    106: Result := Lx(FbSys(FB_SETGID, a0, 0, 0, 0, 0, 0));
    109: Result := Lx(FbSys(FB_SETPGID, a0, a1, 0, 0, 0, 0));
    111: Result := FbSys(FB_GETPGRP, 0, 0, 0, 0, 0, 0);
    113: Result := Lx(FbSys(FB_SETREUID, a0, a1, 0, 0, 0, 0));
    114: Result := Lx(FbSys(FB_SETREGID, a0, a1, 0, 0, 0, 0));
    115: Result := Lx(FbSys(FB_GETGROUPS, a0, a1, 0, 0, 0, 0));
    116: Result := Lx(FbSys(FB_SETGROUPS, a0, a1, 0, 0, 0, 0));
    121: Result := Lx(FbSys(FB_GETPGID, a0, 0, 0, 0, 0, 0));
    124: Result := Lx(FbSys(FB_GETSID, a0, 0, 0, 0, 0, 0));
    140: begin                                                  { getpriority: Linux answers 20 - nice }
           r := FbSys(FB_GETPRIORITY, a0, a1, 0, 0, 0, 0);
           if FbErr then Result := Lx(r) else Result := 20 - r;
         end;
    141: Result := Lx(FbSys(FB_SETPRIORITY, a0, a1, a2, 0, 0, 0));
    162: begin FbSys(FB_SYNC, 0, 0, 0, 0, 0, 0); Result := 0; end;
    227: Result := Lx(FbSys(FB_CLOCK_SETTIME, FbClock(a0), a1, 0, 0, 0, 0));
    235: Result := Lx(FbSys(FB_UTIMES, a0, a1, 0, 0, 0, 0));
    259: Result := Lx(FbSys(FB_MKNODAT, a0, a1, a2, a3, 0, 0));
    260: Result := Lx(FbSys(FB_FCHOWNAT, a0, a1, a2, a3, FbAtFlags(a4), 0));
    265: Result := Lx(FbSys(FB_LINKAT, a0, a1, a2, a3, FbAtFlags(a4), 0));
    266: Result := Lx(FbSys(FB_SYMLINKAT, a0, a1, a2, 0, 0, 0));
    268: Result := Lx(FbSys(FB_FCHMODAT, a0, a1, a2, FbAtFlags(a3), 0, 0));
    280: Result := FbUtimensat(a0, a1, a2, a3);
    41: begin                                                   { socket }
          { Linux's check order (__sys_socket[pair], __sock_create): stray
            flag bits in the type word, then the family, then the type. }
          f := FbAf(a0);
          if (a1 and not Int64($8080F)) <> 0 then Result := -LX_EINVAL   { type 0..15, SOCK_CLOEXEC $80000, SOCK_NONBLOCK $800 }
          else if f < 0 then Result := -LX_EAFNOSUPPORT
          else if (a1 and $F) >= 11 then Result := -LX_EINVAL            { SOCK_MAX = 11 }
          else Result := Lx(FbSys(FB_SOCKET, f, FbSockType(a1), a2, 0, 0, 0));
        end;
    42: Result := FbSockAddrCall(FB_CONNECT, a0, a1, a2);
    43: Result := FbSockAddrOut(FB_ACCEPT4, a0, a1, a2, 0);
    288: Result := FbSockAddrOut(FB_ACCEPT4, a0, a1, a2, a3);
    44: Result := FbSendto(a0, a1, a2, a3, a4, a5);
    45: Result := FbRecvfrom(a0, a1, a2, a3, a4, a5);
    46: Result := FbMsg(True, a0, a1, a2);
    47: Result := FbMsg(False, a0, a1, a2);
    48: Result := Lx(FbSys(FB_SHUTDOWN, a0, a1, 0, 0, 0, 0));
    49: Result := FbSockAddrCall(FB_BIND, a0, a1, a2);
    50: Result := Lx(FbSys(FB_LISTEN, a0, a1, 0, 0, 0, 0));
    51: Result := FbSockAddrOut(FB_GETSOCKNAME, a0, a1, a2, 0);
    52: Result := FbSockAddrOut(FB_GETPEERNAME, a0, a1, a2, 0);
    53: begin                                                   { socketpair }
          { Linux's check order (__sys_socket[pair], __sock_create): stray
            flag bits in the type word, then the family, then the type. }
          f := FbAf(a0);
          if (a1 and not Int64($8080F)) <> 0 then Result := -LX_EINVAL   { type 0..15, SOCK_CLOEXEC $80000, SOCK_NONBLOCK $800 }
          else if f < 0 then Result := -LX_EAFNOSUPPORT
          else if (a1 and $F) >= 11 then Result := -LX_EINVAL            { SOCK_MAX = 11 }
          else Result := Lx(FbSys(FB_SOCKETPAIR, f, FbSockType(a1), a2, a3, 0, 0));
        end;
    54: Result := FbSockopt(False, a0, a1, a2, a3, a4);
    55: Result := FbSockopt(True, a0, a1, a2, a3, a4);
    213, 291: begin                                             { epoll_create, epoll_create1 }
                r := FbSys(FB_KQUEUE, 0, 0, 0, 0, 0, 0);
                if (r >= 0) and (nr = 291) and ((a0 and $80000) <> 0) then
                  FbSys(FB_FCNTL, r, 2, 1, 0, 0, 0);            { F_SETFD FD_CLOEXEC }
                Result := Lx(r);
              end;
    233: Result := FbEpollCtl(a0, a1, a2, a3);
    232, 281: Result := FbEpollWait(a0, a1, a2, a3);            { epoll_pwait: mask not applied }
    283: Result := Lx(FbSys(FB_TIMERFD_CREATE, FbClock(a0), FbFdFlags(a1), 0, 0, 0, 0));
    286: Result := Lx(FbSys(FB_TIMERFD_SETTIME, a0, a1, a2, a3, 0, 0));
    287: Result := Lx(FbSys(FB_TIMERFD_GETTIME, a0, a1, 0, 0, 0, 0));
    284: Result := FbEventfd(a0, 0);
    290: Result := FbEventfd(a0, a1);
    137: Result := FbStatfs(FB_STATFS, a0, a1);
    138: Result := FbStatfs(FB_FSTATFS, a0, a1);
    270: begin                                                  { pselect6: a5 -> (sigset*, size) }
           f := 0;
           if (a5 <> 0) and (PInt64(a5)^ <> 0) then
           begin
             MaskToFb(PInt64(PInt64(a5)^)^, Int64(@t[0]));
             f := Int64(@t[0]);
           end;
           Result := Lx(FbSys(FB_PSELECT, a0, a1, a2, a3, a4, f));
         end;
    271: Result := FbPoll(a0, a1, a2, a3, True);              { ppoll }
    295: Result := Lx(FbSys(FB_PREADV, a0, a1, a2, a3, 0, 0));
    296: Result := Lx(FbSys(FB_PWRITEV, a0, a1, a2, a3, 0, 0));
    332: begin                                                  { statx }
           r := FbSys(FB_FSTATAT, a0, a1, Int64(@sb[0]), FbAtFlags(a2), 0, 0);
           if r = 0 then StatToStatx(@sb[0], Pointer(a4));
           Result := Lx(r);
         end;
    135: begin                                                  { personality }
           Result := FbPersona;
           if a0 <> $FFFFFFFF then FbPersona := a0 and $FFFFFFFF;
         end;
    142: Result := Lx(FbSys(FB_SCHED_SETPARAM, a0, a1, 0, 0, 0, 0));
    143: begin                                                  { sched_getparam }
           Result := Lx(FbSys(FB_SCHED_GETPARAM, a0, a1, 0, 0, 0, 0));
           { SCHED_OTHER's priority is always 0 on Linux; FreeBSD reports its
             internal timeshare priority there }
           if (Result = 0) and (FbSys(FB_SCHED_GETSCHEDULER, a0, 0, 0, 0, 0, 0) = 2) then
             PInteger(a1)^ := 0;
         end;
    144: begin                                                  { sched_setscheduler }
           f := FbPolicy(a1);
           if f < 0 then Result := -LX_EINVAL
           else Result := Lx(FbSys(FB_SCHED_SETSCHEDULER, a0, f, a2, 0, 0, 0));
         end;
    145: begin                                                  { sched_getscheduler }
           r := FbSys(FB_SCHED_GETSCHEDULER, a0, 0, 0, 0, 0, 0);
           if r < 0 then Result := Lx(r) else Result := LxPolicy(r);
         end;
    146, 147: begin                                             { sched_get_priority_max/min }
           f := FbPolicy(a0);
           if f < 0 then Result := -LX_EINVAL
           else if nr = 146 then Result := Lx(FbSys(FB_SCHED_GET_PRIORITY_MAX, f, 0, 0, 0, 0, 0))
           else Result := Lx(FbSys(FB_SCHED_GET_PRIORITY_MIN, f, 0, 0, 0, 0, 0));
         end;
    148: Result := Lx(FbSys(FB_SCHED_RR_GET_INTERVAL, a0, a1, 0, 0, 0, 0));
    149: Result := Lx(FbSys(FB_MLOCK, a0, a1, 0, 0, 0, 0));
    150: Result := Lx(FbSys(FB_MUNLOCK, a0, a1, 0, 0, 0, 0));
    157: Result := FbPrctl(a0, a1);
    167: Result := Lx(FbSys(FB_SWAPON, a0, 0, 0, 0, 0, 0));
    168: Result := Lx(FbSys(FB_SWAPOFF, a0, 0, 0, 0, 0, 0));
    272: if a0 = 0 then Result := 0 else Result := -LX_EINVAL;  { unshare: nothing to unshare is a success on Linux too }
    285: if a1 <> 0 then Result := -95                          { fallocate: only mode 0 (EOPNOTSUPP otherwise) }
         else begin
           { posix_fallocate hands its error back as the return VALUE }
           r := FbSys(FB_POSIX_FALLOCATE, a0, a2, a3, 0, 0, 0);
           if r > 0 then Result := Lx(-r) else Result := Lx(r);
         end;
  else
    Result := -LX_ENOSYS;
  end;
end;

end.
