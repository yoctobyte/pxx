unit dfbsdabi;

{ The Linux syscall ABI on a DragonFly BSD kernel -- EXPERIMENTAL
  (--os=dragonfly). The same design as fbsdabi.pas (read its header first):
  every kernel entry pxx emits is written against Linux, funnels through the
  shared thunk, and arrives here with the Linux number and arguments; this
  unit maps the number, rewrites what differs, makes the real DragonFly call
  from DfRawA, and maps DragonFly's errno back to Linux's.

  The code started as a copy of obsdabi.pas: DragonFly has, like OpenBSD, no
  epoll, timerfd or eventfd, so those are emulated over kqueue the same way,
  and its signal numbers, kevent, termios and most socket options are
  OpenBSD's too. What is DragonFly's own:

  - AT_FDCWD is -328243, not -100: every *at call maps the directory fd.
  - Threads are LWPs (lwp_create2) started at a function; DfLwpStartA turns
    that into a clone-style resume. A thread's exit is the shared exit stack
    of obsdabi with extexit(EXTEXIT_SETINT) releasing its lock from inside
    the kernel. Futexes are umtx_sleep/umtx_wakeup (int compare, a timeout in
    microseconds capped by kern.umtx_timeout_max, so an untimed wait loops).
  - TLS: set_tls_area(1, ..) sets the GS base, so pxx keeps its gs: TLS.
  - errno numbers are FreeBSD's.

  CONSTANTS ARE MEASURED: syscall numbers, errno, flags and clocks from
  DragonFly 6.4.2 x86_64's /usr/include; struct offsets from offsetof()
  compiled on that system (2026-11-13).

  CONTEXT RULES are fbsdabi's: no managed types, no heap, no exceptions, no
  RTL calls; DfRawA is the only kernel entry.

  Anything unmapped answers -ENOSYS. }

interface

function PXXDfbsdSyscall(nr, a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl;

implementation

const
  LX_ENOENT = 2;
  LX_EINVAL = 22;
  LX_ENOMEM = 12;
  LX_ENOTTY = 25;
  LX_ENOSYS = 38;

  { DragonFly 6.4 x86_64 syscall numbers (sys/syscall.h) }
  DF_EXIT = 1; DF_FORK = 2; DF_READ = 3; DF_WRITE = 4; DF_CLOSE = 6;
  DF_GETRANDOM = 550; DF_LINK = 9; DF_UNLINK = 10; DF_WAIT4 = 7; DF_CHDIR = 12;
  DF_FCHDIR = 13; DF_CHMOD = 15; DF_CHOWN = 16; DF_GETRUSAGE = 117;
  DF_GETPID = 20; DF_SETUID = 23; DF_GETUID = 24; DF_GETEUID = 25;
  DF_GETPPID = 39; DF_DUP = 41; DF_FSTATAT = 505; DF_GETEGID = 43;
  DF_GETGID = 47; DF_MMAP = 197; DF_FSTAT = 476; DF_IOCTL = 54; DF_SYMLINK = 57;
  DF_READLINK = 58; DF_EXECVE = 59; DF_UMASK = 60; DF_GETTIMEOFDAY = 116;
  DF_SELECT = 93; DF_MUNMAP = 73; DF_MPROTECT = 74; DF_MADVISE = 75;
  DF_GETPGRP = 81; DF_SETPGID = 82; DF_UTIMENSAT = 539; DF_CLOCK_GETTIME = 232;
  DF_CLOCK_GETRES = 234; DF_DUP2 = 90; DF_NANOSLEEP = 240; DF_FCNTL = 92;
  DF_FSYNC = 95; DF_SETPRIORITY = 96; DF_GETDENTS = 480; DF_GETPRIORITY = 100;
  DF_PIPE2 = 538; DF_KILL = 37; DF_FCHOWN = 123;
  DF_FCHMOD = 124; DF_READV = 120; DF_WRITEV = 121; DF_RENAME = 128;
  DF_FLOCK = 131; DF_MKDIR = 136; DF_RMDIR = 137; DF_SETSID = 147;
  DF_LSEEK = 199; DF_TRUNCATE = 200; DF_FTRUNCATE = 201; DF_EXTPREAD = 173;
  DF_EXTPWRITE = 174; DF_EXTPREADV = 289; DF_EXTPWRITEV = 290; DF_SETGID = 181;
  DF_GETRLIMIT = 194; DF_SETRLIMIT = 195; DF_SYSCTL = 202; DF_GETPGID = 207;
  DF_POLL = 209; DF_LCHOWN = 254; DF_GETSID = 310; DF_SCHED_YIELD = 331;
  DF_LWP_GETTID = 496; DF_GETCWD = 326; DF_FACCESSAT = 509; DF_FCHMODAT = 506;
  DF_FCHOWNAT = 507; DF_LINKAT = 531; DF_MKDIRAT = 524; DF_OPENAT = 504;
  DF_READLINKAT = 527; DF_RENAMEAT = 523; DF_SYMLINKAT = 528; DF_UNLINKAT = 508;
  DF_SET_TLS_AREA = 472; DF_GET_TLS_AREA = 473;
  DF_SIGACTION = 342; DF_SIGPROCMASK = 340; DF_SIGPENDING = 343;
  DF_GETITIMER = 86; DF_SETITIMER = 83; DF_SIGSUSPEND = 341; DF_LWP_KILL = 497;
  DF_SIGALTSTACK = 53; DF_SIGRETURN = 344; DF_SIGTIMEDWAIT = 345;
  DF_LWP_CREATE2 = 546; DF_UMTX_SLEEP = 469; DF_UMTX_WAKEUP = 470; DF_EXTEXIT = 494;
  DF_PPOLL = 543; DF_PSELECT = 499;
  DF_MKNOD = 14; DF_SYNC = 36; DF_STATFS = 157; DF_FSTATFS = 158; DF_UTIMES = 138;
  DF_GETGROUPS = 79; DF_SETGROUPS = 80; DF_FUTIMENS = 540; DF_CLOCK_SETTIME = 233;
  DF_SETREUID = 126; DF_SETREGID = 127; DF_LWP_GETNAME = 549; DF_LWP_SETNAME = 542;
  DF_MLOCK = 203; DF_MUNLOCK = 204; DF_MLOCKALL = 324; DF_MUNLOCKALL = 325;
  DF_GETRESUID = 360; DF_SETRESUID = 311; DF_GETRESGID = 361; DF_SETRESGID = 312;
  DF_MKNODAT = 526; DF_FDATASYNC = 554; DF_POSIX_FALLOCATE = 553;
  DF_LWP_GETAFFINITY = 545;
  { sockets }
  DF_RECVMSG = 27; DF_SENDMSG = 28; DF_RECVFROM = 29; DF_GETPEERNAME = 31;
  DF_GETSOCKNAME = 32; DF_SOCKET = 97; DF_CONNECT = 98; DF_BIND = 104;
  DF_SETSOCKOPT = 105; DF_LISTEN = 106; DF_GETSOCKOPT = 118; DF_SENDTO = 133;
  DF_SHUTDOWN = 134; DF_SOCKETPAIR = 135; DF_EXTACCEPT = 482;

  DF_AT_FDCWD = -328243;          { NOT Linux's -100 }
  DF_AT_SYMLINK_NOFOLLOW = $01; DF_AT_REMOVEDIR = $02; DF_AT_EACCESS = $04;
  DF_AT_SYMLINK_FOLLOW = $08;

  DF_MAP_FIXED = $10; DF_MAP_ANON = $1000; DF_MAP_STACK = $400;
  DF_RLIM_INFINITY = $7FFFFFFFFFFFFFFF;

  DF_TIOCGETA = $402C7413; DF_TIOCGWINSZ = $40087468;
  DF_FIONREAD = $4004667F; DF_FIONBIO = $8004667E;

  DF_F_DUP2FD = 10; DF_F_DUP2FD_CLOEXEC = 18;
  DF_EXTEXIT_LWP = $10000; DF_EXTEXIT_SETINT = 1;
  DF_TLS_WHICH_GS = 1;

  { DragonFly errno 35..95 -> Linux errno. 1..34 are the same on both. The
    numbers are FreeBSD's up to 92; 93..95 are DragonFly's own. }
  ErrMap: array[35..95] of Integer = (
    11, 115, 114, 88, 89, 90, 91, 92, 93, 94,      { 35 EAGAIN .. 44 ESOCKTNOSUPPORT }
    95, 96, 97, 98, 99, 100, 101, 102, 103, 104,   { 45 EOPNOTSUPP .. 54 ECONNRESET }
    105, 106, 107, 108, 109, 110, 111, 40, 36, 112, { 55 ENOBUFS .. 64 EHOSTDOWN }
    113, 39, 11, 87, 122, 116, 66, 22, 22, 22,     { 65 EHOSTUNREACH .. 74 EPROGUNAVAIL }
    22, 22, 37, 38, 22, 13, 13, 43, 42, 75,        { 75 EPROGMISMATCH .. 84 EOVERFLOW }
    125, 84, 61, 22, 74, 72, 67, 71, 123, 131,     { 85 ECANCELED .. 94 ENOTRECOVERABLE }
    130);                                          { 95 EOWNERDEAD }

  { Linux signal 0..31 -> DragonFly (the classic BSD numbers, as OpenBSD's).
    0 = no DragonFly equivalent. }
  SigMap: array[0..31] of Integer = (
    0, 1, 2, 3, 4, 5, 6, 10, 8, 9, 30, 11, 31, 13, 14, 15,
    0, 20, 19, 17, 18, 21, 22, 16, 24, 25, 26, 27, 28, 23, 0, 12);

  { Linux RLIMIT_* 0..9 (CPU FSIZE DATA STACK CORE RSS NPROC NOFILE MEMLOCK AS)
    -> DragonFly (RLIMIT_AS is RLIMIT_VMEM, 10). }
  RlimMap: array[0..9] of Integer = (0, 1, 2, 3, 4, 5, 7, 8, 6, 10);

  BRK_RESERVE = Int64(1024) * 1024 * 1024;   { PROT_NONE address space, grown by mprotect }

var
  DfBrkBase, DfBrkCur, DfBrkTop: Int64;
  DfTmpSeq: Int64;
  DfMainTid: Int64;          { the thread that first called clone; 0 = no threads yet }
  DfExitStack: Int64;        { the shared thread-exit stack (MAP_STACK) }
  DfExitLock: Integer;       { its lock; extexit(EXTEXIT_SETINT) clears it }

const
  DF_EXIT_STACK_SIZE = 16384;
  { The TLS slot the clone stub leaves free for the child's ctid pointer on
    x86-64: defs.inc's TLS_SLOT_FS_ENTRY (14), i386's fs entry slot, never
    written on x86-64. fbsdabi uses the same slot for the same purpose. }
  DF_TLS_SLOT_CTID = 14;

{ The ONE kernel entry. args -> [nr, a0..a5, rdx-out, cf-out]. DragonFly
  reports an error with CF set and the
  positive errno in rax; the sbb/xor/sub trio negates rax exactly then. }
function DfRawA(args: Pointer): Int64; assembler;
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

{ DfRawA with a seventh argument, which the kernel copies from [rsp+8] (the
  slot above a return address) -- only mmap needs one: DragonFly's mmap
  still has FreeBSD's old pad word before the offset. args -> [nr, a0..a6,
  rdx-out, cf-out]. }
function DfRaw7A(args: Pointer): Int64; assembler;
{$asmMode intel}
asm
  push r12
  mov r12, args
  sub rsp, 16
  mov rax, [r12+56]
  mov [rsp+8], rax
  mov rax, [r12]
  mov rdi, [r12+8]
  mov rsi, [r12+16]
  mov rdx, [r12+24]
  mov r10, [r12+32]
  mov r8, [r12+40]
  mov r9, [r12+48]
  syscall
  add rsp, 16
  mov [r12+64], rdx
  sbb rcx, rcx
  mov [r12+72], rcx
  xor rax, rcx
  sub rax, rcx
  pop r12
end;

{ A new LWP starts at lwp_func with rdi = lwp_arg and rsp = lwp_stack - 8
  (the kernel writes a NULL return address there). DfClone points lwp_arg at
  two words below the clone stub's stage area -- [cont, stage] -- and this
  resumes the child at cont with rsp = stage, as a clone child would resume.
  Registers only: nothing here depends on the entry rsp. }
procedure DfLwpStartA; assembler;
{$asmMode intel}
asm
  mov rax, [rdi]
  mov rsp, [rdi+8]
  push rax                { jmp rax: the assembler takes label targets only }
  ret
end;

{ The last steps of a non-main thread's exit: the CLONE_CHILD_CLEARTID work
  Linux's kernel does and DragonFly's does not. The moment the tid word is
  zero a joiner may unmap this thread's stack, so the clear and the wake run
  on a shared exit stack (mapped by the translator) taken under a spin lock,
  and the lock is released by extexit(EXTEXIT_LWP | EXTEXIT_SETINT, 0, lock):
  the KERNEL writes the 0, once this thread no longer runs on that stack.
  umtx_wakeup(ctid, 0) wakes every waiter, private or shared (umtx queues are
  keyed by physical address). DfRawA is called by address: registers and the
  exit stack only. Does not return. }
procedure DfThreadExitA(ctid, lock, top, raw: Int64); assembler;
{$asmMode intel}
asm
  mov r12, ctid
  mov r13, lock
  mov r14, top
  mov r15, raw
  jmp dfte_spin
dfte_raw:                 { call r15: the assembler takes label targets only }
  push r15
  ret
dfte_spin:
  mov eax, 1
  xchg [r13], eax
  test eax, eax
  jz dfte_got
  pause
  jmp dfte_spin
dfte_got:
  mov rsp, r14
  xor eax, eax
  mov [r12], eax
  sub rsp, 80
  mov qword [rsp], 470
  mov [rsp+8], r12
  mov qword [rsp+16], 0
  mov qword [rsp+24], 0
  mov qword [rsp+32], 0
  mov qword [rsp+40], 0
  mov qword [rsp+48], 0
  mov rdi, rsp
  call dfte_raw
  mov qword [rsp], 494
  mov qword [rsp+8], $10001
  mov qword [rsp+16], 0
  mov [rsp+24], r13
  mov rdi, rsp
  call dfte_raw
end;

var
  DfRdx: Int64;

function DfSys(nr, a0, a1, a2, a3, a4, a5: Int64): Int64;
var a: array[0..8] of Int64;
begin
  a[0] := nr; a[1] := a0; a[2] := a1; a[3] := a2;
  a[4] := a3; a[5] := a4; a[6] := a5; a[7] := 0; a[8] := 0;
  Result := DfRawA(@a[0]);
  DfRdx := a[7];
end;

{ pipe2(fds, flags): DragonFly answers the two fds in rax and rdx, as the
  old pipe() did, and does not store them -- this does (measured). }
function DfPipe2(fds, flags: Int64): Int64;
begin
  Result := DfSys(DF_PIPE2, fds, flags, 0, 0, 0, 0);
  if Result >= 0 then
  begin
    PInteger(fds)^ := Integer(Result);
    PInteger(fds + 4)^ := Integer(DfRdx);
    Result := 0;
  end;
end;

{ mmap(addr, len, prot, flags, fd, pad, pos): DragonFly flags already. }
function DfMmap(addr, len, prot, flags, fd, pos: Int64): Int64;
var a: array[0..9] of Int64;
begin
  a[0] := DF_MMAP; a[1] := addr; a[2] := len; a[3] := prot; a[4] := flags;
  a[5] := fd; a[6] := 0; a[7] := pos; a[8] := 0; a[9] := 0;
  Result := DfRaw7A(@a[0]);
end;

{ -DragonFly errno -> -Linux errno; anything else unchanged. }
function Lx(r: Int64): Int64;
begin
  if (r < -34) and (r >= -95) then Result := -ErrMap[Integer(-r)]
  else Result := r;
end;

function DfOpenFlags(f: Int64): Int64;
var r: Int64;
begin
  r := f and 3;                                       { O_ACCMODE, same }
  if (f and $40) <> 0 then r := r or $200;            { O_CREAT }
  if (f and $80) <> 0 then r := r or $800;            { O_EXCL }
  if (f and $100) <> 0 then r := r or $8000;          { O_NOCTTY }
  if (f and $200) <> 0 then r := r or $400;           { O_TRUNC }
  if (f and $400) <> 0 then r := r or $8;             { O_APPEND }
  if (f and $800) <> 0 then r := r or $4;             { O_NONBLOCK }
  if (f and $1000) <> 0 then r := r or $80;           { O_DSYNC / O_SYNC }
  if (f and $10000) <> 0 then r := r or $8000000;     { O_DIRECTORY }
  if (f and $20000) <> 0 then r := r or $100;         { O_NOFOLLOW }
  if (f and $80000) <> 0 then r := r or $20000;       { O_CLOEXEC }
  Result := r;                                        { O_LARGEFILE, O_NOATIME, O_DIRECT, O_PATH: dropped }
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
  if (f and $80) <> 0 then r := r or $101000;
  if (f and $8000000) <> 0 then r := r or $10000;
  if (f and $100) <> 0 then r := r or $20000;
  if (f and $20000) <> 0 then r := r or $80000;
  Result := r;
end;

{ Linux MAP_* -> DragonFly. NOT a pass-through: only SHARED, PRIVATE and
  FIXED agree; NORESERVE and POPULATE are dropped. }
function DfMmapFlags(f: Int64): Int64;
var r: Int64;
begin
  r := f and $13;                                     { SHARED, PRIVATE, FIXED: same }
  if (f and $20) <> 0 then r := r or DF_MAP_ANON;     { MAP_STACK dropped: DragonFly's grows down }
  Result := r;
end;

{ Linux AT_FDCWD (-100) -> DragonFly's (-328243); other fds unchanged. }
function DfDir(d: Int64): Int64;
begin
  if d = -100 then Result := DF_AT_FDCWD else Result := d;
end;

function DfAtFlags(f: Int64): Int64;
var r: Int64;
begin
  r := 0;
  if (f and $100) <> 0 then r := r or DF_AT_SYMLINK_NOFOLLOW;
  if (f and $400) <> 0 then r := r or DF_AT_SYMLINK_FOLLOW;
  Result := r;
end;

{ Linux clocks: REALTIME 0, MONOTONIC 1, PROCESS_CPUTIME 2, THREAD_CPUTIME 3,
  MONOTONIC_RAW 4, REALTIME_COARSE 5, MONOTONIC_COARSE 6, BOOTTIME 7.
  DragonFly: REALTIME 0, MONOTONIC 4, UPTIME 5, REALTIME_FAST 10,
  MONOTONIC_FAST 12, THREAD_CPUTIME 14, PROCESS_CPUTIME 15; no BOOTTIME (a
  DragonFly MONOTONIC keeps counting across suspend anyway). }
function DfClock(id: Int64): Int64;
begin
  case Integer(id) of
    0: Result := 0;
    1: Result := 4;
    2: Result := 15;
    3: Result := 14;
    4: Result := 4;
    5: Result := 10;
    6: Result := 12;
    7: Result := 4;
  else
    Result := id;
  end;
end;

function DfSig(s: Int64): Int64;
begin
  if (s >= 0) and (s <= 31) then Result := SigMap[Integer(s)]
  else Result := s;
end;

{ DragonFly struct stat (128 B) at df -> Linux x86-64 struct stat (144 B).
  DragonFly: ino 0, nlink 8 (u32), dev 12 (u32), mode 16 (u16), uid 20,
  gid 24, rdev 28 (u32), atim 32, mtim 48, ctim 64, size 80, blocks 88,
  blksize 112 (i64). }
procedure StatToLinux(df, lx: Pointer);
var i: Integer;
begin
  for i := 0 to 17 do PInt64(Int64(lx) + i * 8)^ := 0;
  PInt64(Int64(lx) + 0)^ := PLongWord(Int64(df) + 12)^;             { st_dev }
  PInt64(Int64(lx) + 8)^ := PInt64(Int64(df) + 0)^;                 { st_ino }
  PInt64(Int64(lx) + 16)^ := PLongWord(Int64(df) + 8)^;             { st_nlink }
  PLongWord(Int64(lx) + 24)^ := PWord(Int64(df) + 16)^;             { st_mode }
  PLongWord(Int64(lx) + 28)^ := PLongWord(Int64(df) + 20)^;         { st_uid }
  PLongWord(Int64(lx) + 32)^ := PLongWord(Int64(df) + 24)^;         { st_gid }
  PInt64(Int64(lx) + 40)^ := PLongWord(Int64(df) + 28)^;            { st_rdev }
  PInt64(Int64(lx) + 48)^ := PInt64(Int64(df) + 80)^;               { st_size }
  PInt64(Int64(lx) + 56)^ := PInt64(Int64(df) + 112)^;              { st_blksize }
  PInt64(Int64(lx) + 64)^ := PInt64(Int64(df) + 88)^;               { st_blocks }
  PInt64(Int64(lx) + 72)^ := PInt64(Int64(df) + 32)^;               { st_atim }
  PInt64(Int64(lx) + 80)^ := PInt64(Int64(df) + 40)^;
  PInt64(Int64(lx) + 88)^ := PInt64(Int64(df) + 48)^;               { st_mtim }
  PInt64(Int64(lx) + 96)^ := PInt64(Int64(df) + 56)^;
  PInt64(Int64(lx) + 104)^ := PInt64(Int64(df) + 64)^;              { st_ctim }
  PInt64(Int64(lx) + 112)^ := PInt64(Int64(df) + 72)^;
end;

{ DragonFly struct stat -> Linux struct statx (256 B). No birth time:
  STATX_BASIC_STATS only. }
procedure StatToStatx(df, sx: Pointer);
var i: Integer;
procedure Ts(lxOff, dfOff: Integer);
begin
  PInt64(Int64(sx) + lxOff)^ := PInt64(Int64(df) + dfOff)^;
  PLongWord(Int64(sx) + lxOff + 8)^ := LongWord(PInt64(Int64(df) + dfOff + 8)^);
end;
begin
  for i := 0 to 31 do PInt64(Int64(sx) + i * 8)^ := 0;
  PLongWord(Int64(sx) + 0)^ := $7FF;                                { BASIC_STATS }
  PLongWord(Int64(sx) + 4)^ := LongWord(PInt64(Int64(df) + 112)^);  { blksize }
  PLongWord(Int64(sx) + 16)^ := PLongWord(Int64(df) + 8)^;          { nlink }
  PLongWord(Int64(sx) + 20)^ := PLongWord(Int64(df) + 20)^;         { uid }
  PLongWord(Int64(sx) + 24)^ := PLongWord(Int64(df) + 24)^;         { gid }
  PWord(Int64(sx) + 28)^ := PWord(Int64(df) + 16)^;                 { mode }
  PInt64(Int64(sx) + 32)^ := PInt64(Int64(df) + 0)^;                { ino }
  PInt64(Int64(sx) + 40)^ := PInt64(Int64(df) + 80)^;               { size }
  PInt64(Int64(sx) + 48)^ := PInt64(Int64(df) + 88)^;               { blocks }
  Ts(64, 32);                                                       { atime }
  Ts(96, 64);                                                       { ctime }
  Ts(112, 48);                                                      { mtime }
  PLongWord(Int64(sx) + 128)^ := (PLongWord(Int64(df) + 28)^ shr 8) and $FF;  { rdev major }
  PLongWord(Int64(sx) + 132)^ := PLongWord(Int64(df) + 28)^ and $FF;          { rdev minor }
  PLongWord(Int64(sx) + 136)^ := (PLongWord(Int64(df) + 12)^ shr 8) and $FF;  { dev major }
  PLongWord(Int64(sx) + 140)^ := PLongWord(Int64(df) + 12)^ and $FF;          { dev minor }
end;

{ getdents64 over getdirentries. A DragonFly dirent has no record length --
  d_ino 0, d_namlen 8 (u16), d_type 10, d_name 16, the record rounded up to
  8 -- and a Linux dirent64 (d_ino, d_off, d_reclen 16, d_type 18, d_name 19)
  is up to 8 bytes longer, so the records are read into a buffer here and
  copied out. Asking for 3/4 of the caller's room (a Linux record is at most
  4/3 of the DragonFly one) keeps every record read one that fits. }
function DfGetdents(fd, buf, len: Int64): Int64;
var tmp: array[0..8191] of Byte; base, n, p, q, nameLen, rec, i: Int64;
begin
  n := (len * 3) div 4;
  if n > 8192 then n := 8192;
  n := n and (not Int64(7));
  if n < 512 then begin Result := -LX_EINVAL; Exit; end;
  base := 0;
  n := DfSys(DF_GETDENTS, fd, Int64(@tmp[0]), n, Int64(@base), 0, 0);
  if n <= 0 then begin Result := Lx(n); Exit; end;
  p := 0; q := 0;
  while p < n do
  begin
    nameLen := PWord(Int64(@tmp[0]) + p + 8)^;
    rec := (19 + nameLen + 1 + 7) and (not Int64(7));
    if q + rec > len then Break;
    PInt64(buf + q)^ := PInt64(Int64(@tmp[0]) + p)^;
    PInt64(buf + q + 8)^ := q + rec;
    PWord(buf + q + 16)^ := Word(rec);
    PByte(buf + q + 18)^ := PByte(Int64(@tmp[0]) + p + 10)^;
    for i := 0 to nameLen - 1 do PByte(buf + q + 19 + i)^ := PByte(Int64(@tmp[0]) + p + 16 + i)^;
    for i := 19 + nameLen to rec - 1 do PByte(buf + q + i)^ := 0;
    q := q + rec;
    p := p + ((16 + nameLen + 1 + 7) and (not Int64(7)));
  end;
  Result := q;
end;

{ Linux brk on a PROT_NONE reservation grown with mprotect, as obsdabi does
  (DragonFly's break is not Linux's brk). Linux semantics: the new break on success, the old one
  on failure, never an error code. }
function DfBrk(want: Int64): Int64;
var top, r: Int64;
begin
  if DfBrkBase = 0 then
  begin
    r := DfMmap(0, BRK_RESERVE, 0, 2 or DF_MAP_ANON, -1, 0);   { PROT_NONE, PRIVATE|ANON }
    if r < 0 then begin Result := 0; Exit; end;
    DfBrkBase := r; DfBrkCur := r; DfBrkTop := r;
  end;
  Result := DfBrkCur;
  if (want < DfBrkBase) or (want > DfBrkBase + BRK_RESERVE) then Exit;
  if want > DfBrkTop then
  begin
    top := (want + $FFFF) and (not Int64($FFFF));
    if top > DfBrkBase + BRK_RESERVE then top := DfBrkBase + BRK_RESERVE;
    r := DfSys(DF_MPROTECT, DfBrkTop, top - DfBrkTop, 3, 0, 0, 0);
    if r < 0 then Exit;
    DfBrkTop := top;
  end;
  DfBrkCur := want;
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
  if DfSys(DF_SYSCTL, Int64(@mib[0]), 2, dst, Int64(@len), 0, 0) < 0 then len := 0;
  if len > cap - 1 then len := cap - 1;
  PByte(dst + len)^ := 0;
end;

{ Linux struct utsname: six 65-byte fields, built from sysctl as libc does. }
function DfUname(u: Int64): Int64;
var i: Integer;
const
  SysName: array[0..8] of Byte = (68, 114, 97, 103, 111, 110, 70, 108, 121);   { DragonFly }
  Machine: array[0..5] of Byte = (120, 56, 54, 95, 54, 52);         { x86_64 }
begin
  for i := 0 to 389 do PByte(u + i)^ := 0;
  for i := 0 to 8 do PByte(u + i)^ := SysName[i];
  SysctlStr(1, 10, u + 65, 65);      { kern.hostname }
  SysctlStr(1, 2, u + 130, 65);      { kern.osrelease }
  SysctlStr(1, 4, u + 195, 65);      { kern.version }
  for i := 0 to 5 do PByte(u + 260 + i)^ := Machine[i];
  Result := 0;
end;

function DfGetRlimit(res, lim: Int64): Int64;
var r: Int64;
begin
  if (res < 0) or (res > 9) then begin Result := -LX_EINVAL; Exit; end;
  if RlimMap[Integer(res)] < 0 then
  begin
    PInt64(lim)^ := -1; PInt64(lim + 8)^ := -1;      { RLIMIT_AS: unlimited }
    Result := 0; Exit;
  end;
  r := DfSys(DF_GETRLIMIT, RlimMap[Integer(res)], lim, 0, 0, 0, 0);
  if r = 0 then
  begin
    if PInt64(lim)^ = DF_RLIM_INFINITY then PInt64(lim)^ := -1;
    if PInt64(lim + 8)^ = DF_RLIM_INFINITY then PInt64(lim + 8)^ := -1;
  end;
  Result := Lx(r);
end;

function DfSetRlimit(res, lim: Int64): Int64;
var v: array[0..1] of Int64;
begin
  if (res < 0) or (res > 9) then begin Result := -LX_EINVAL; Exit; end;
  if RlimMap[Integer(res)] < 0 then begin Result := 0; Exit; end;
  v[0] := PInt64(lim)^; v[1] := PInt64(lim + 8)^;
  if v[0] = -1 then v[0] := DF_RLIM_INFINITY;
  if v[1] = -1 then v[1] := DF_RLIM_INFINITY;
  Result := Lx(DfSys(DF_SETRLIMIT, RlimMap[Integer(res)], Int64(@v[0]), 0, 0, 0, 0));
end;

{ fstatat with Linux flags; AT_EMPTY_PATH ($1000) with "" is fstat(dirfd). }
function DfStatAt(dirfd, path, buf, flags: Int64): Int64;
var sb: array[0..15] of Int64; r: Int64;
begin
  if ((flags and $1000) <> 0) and ((path = 0) or (PByte(path)^ = 0)) then
    r := DfSys(DF_FSTAT, dirfd, Int64(@sb[0]), 0, 0, 0, 0)
  else
    r := DfSys(DF_FSTATAT, DfDir(dirfd), path, Int64(@sb[0]), DfAtFlags(flags), 0, 0);
  if r = 0 then StatToLinux(@sb[0], Pointer(buf));
  Result := Lx(r);
end;

{ ---- /proc files the runtime reads ------------------------------------- }

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
  ProcHostname: array[0..24] of Byte = (47,112,114,111,99,47,115,121,115,47,107,101,
                                        114,110,101,108,47,104,111,115,116,110,97,
                                        109,101);                       { /proc/sys/kernel/hostname }
  DevFull: array[0..8] of Byte = (47,100,101,118,47,102,117,108,108);  { /dev/full }
  DevZero: array[0..9] of Byte = (47,100,101,118,47,122,101,114,111,0); { /dev/zero, NUL-terminated }

{ An fd that reads back len bytes from buf. DragonFly has no anonymous shm and
  no memfd, so: a pipe when the bytes fit its buffer (16 KiB, no file system
  touched), else an unlinked file in /tmp. }
function DfDataFd(buf, len: Int64): Int64;
var fds: array[0..1] of Integer; name: array[0..47] of Byte;
    fd, v, i, k: Int64;
const Pre: array[0..10] of Byte = (47,116,109,112,47,46,112,120,120,101,110);   { /tmp/.pxxen }
begin
  if len <= 16384 then
  begin
    fds[0] := -1; fds[1] := -1;
    Result := DfPipe2(Int64(@fds[0]), $20000);                       { O_CLOEXEC }
    if Result < 0 then begin Result := Lx(Result); Exit; end;
    if len > 0 then DfSys(DF_WRITE, fds[1], buf, len, 0, 0, 0);
    DfSys(DF_CLOSE, fds[1], 0, 0, 0, 0, 0);
    Result := fds[0];
    Exit;
  end;
  for i := 0 to 10 do name[i] := Pre[i];
  k := 11;
  DfTmpSeq := DfTmpSeq + 1;
  v := DfSys(DF_GETPID, 0, 0, 0, 0, 0, 0) * 1000 + DfTmpSeq;
  while v > 0 do begin name[k] := 48 + (v mod 10); v := v div 10; k := k + 1; end;
  name[k] := 0;
  fd := DfSys(DF_OPENAT, DF_AT_FDCWD, Int64(@name[0]), 2 or $200 or $800 or $20000, 384, 0, 0);
  if fd < 0 then begin Result := Lx(fd); Exit; end;
  DfSys(DF_UNLINK, Int64(@name[0]), 0, 0, 0, 0, 0);
  DfSys(DF_WRITE, fd, buf, len, 0, 0, 0);
  DfSys(DF_LSEEK, fd, 0, 0, 0, 0, 0);                         { lseek(fd, pad, 0, SEEK_SET) }
  Result := fd;
end;

{ /proc/self/environ: "k=v\0k=v\0". DragonFly has no kern.proc.env; the
  environment the process was started with is on its initial stack, and
  struct ps_strings (address from kern.ps_strings) points at it:
  ps_envstr at 16, a NULL-terminated pointer array, as Linux's environ file
  shows the start-up environment too. }
function DfProcEnviron: Int64;
var mib: array[0..1] of Integer; ps, len, p, s, i, n, sz, outp: Int64;
begin
  mib[0] := 1; mib[1] := 32;                                  { kern.ps_strings }
  ps := 0; len := 8;
  p := DfSys(DF_SYSCTL, Int64(@mib[0]), 2, Int64(@ps), Int64(@len), 0, 0);
  if (p < 0) or (ps = 0) then begin Result := -LX_ENOENT; Exit; end;
  sz := 0; p := PInt64(ps + 16)^;
  while PInt64(p)^ <> 0 do
  begin
    sz := sz + StrLen0(PInt64(p)^) + 1;
    p := p + 8;
  end;
  sz := (sz + 1 + $FFF) and (not Int64($FFF));
  outp := DfMmap(0, sz, 3, 2 or DF_MAP_ANON, -1, 0);
  if outp < 0 then begin Result := -LX_ENOMEM; Exit; end;
  n := 0; p := PInt64(ps + 16)^;
  while PInt64(p)^ <> 0 do
  begin
    s := PInt64(p)^;
    i := 0;
    while PByte(s + i)^ <> 0 do
    begin
      PByte(outp + n)^ := PByte(s + i)^; n := n + 1; i := i + 1;
    end;
    PByte(outp + n)^ := 0; n := n + 1;
    p := p + 8;
  end;
  Result := DfDataFd(outp, n);
  DfSys(DF_MUNMAP, outp, sz, 0, 0, 0, 0);
end;

{ /proc/sys/kernel/hostname: kern.hostname and a newline. }
function DfProcHostname: Int64;
var b: array[0..271] of Byte; n: Int64;
begin
  SysctlStr(1, 10, Int64(@b[0]), 256);
  n := StrLen0(Int64(@b[0]));
  b[n] := 10;
  Result := DfDataFd(Int64(@b[0]), n + 1);
end;

{ readlink("/proc/self/exe"): kern.proc.pathname (CTL_KERN, KERN_PROC,
  KERN_PROC_PATHNAME, -1). Linux semantics: no NUL, truncate silently,
  return the byte count. }
function DfProcExe(buf, cap: Int64): Int64;
var mib: array[0..3] of Integer; len, r: Int64;
    tmp: array[0..1023] of Byte;
    i: Integer;
begin
  mib[0] := 1; mib[1] := 14; mib[2] := 9; mib[3] := -1;
  len := 1024;
  r := DfSys(DF_SYSCTL, Int64(@mib[0]), 4, Int64(@tmp[0]), Int64(@len), 0, 0);
  if r < 0 then begin Result := Lx(r); Exit; end;
  if (len > 0) and (tmp[len - 1] = 0) then len := len - 1;
  if len > cap then len := cap;
  for i := 0 to Integer(len) - 1 do PByte(buf + i)^ := tmp[i];
  Result := len;
end;

{ ---- Signals ----------------------------------------------------------------
  fbsdabi's design (read its Signals header): the program's handler speaks
  the Linux SA_SIGINFO ABI and may REWRITE the saved RIP/RSP in the Linux
  ucontext it is given (the fault-to-raise path), so rt_sigaction installs
  DfSigEntry instead. DfSigEntry builds a Linux siginfo/ucontext, calls the
  program's handler, copies the registers back into DragonFly's ucontext and
  returns to the kernel's sigcode, which does sigreturn.

  DragonFly's side is FreeBSD's shape: sigset_t is 4 x 32 bits passed by
  pointer, struct sigaction is handler, flags (int), mask (32 B), siginfo is
  signo, errno, code, pid, uid, status, addr (24). What is its own: the
  ucontext (uc_sigmask 0, uc_mcontext 64: mc_onstack, rdi, rsi, rdx, rcx,
  r8, r9, rax, rbx, rbp, r10..r15, then trapno 136, addr 144, err 160,
  rip 168, rflags 184, rsp 192, fpformat 212, fpregs 256), and the user
  si_codes (0, -1 QUEUE, -2 TIMER, -3 ASYNCIO, -4 MESGQ; Linux swaps the
  last two). Fault codes are FreeBSD's (SIGFPE's INTOVF/INTDIV swapped).
  Offsets measured with offsetof() on DragonFly 6.4.2 (2026-11-13). }

const
  DF_SA_ONSTACK = $1; DF_SA_RESTART = $2; DF_SA_RESETHAND = $4;
  DF_SA_NOCLDSTOP = $8; DF_SA_NODEFER = $10; DF_SA_NOCLDWAIT = $20;
  DF_SA_SIGINFO = $40;
  LX_SA_NOCLDSTOP = $1; LX_SA_NOCLDWAIT = $2; LX_SA_SIGINFO = $4;
  LX_SA_ONSTACK = $08000000; LX_SA_RESTART = $10000000;
  LX_SA_NODEFER = $40000000; LX_SA_RESETHAND = $80000000;
  DF_UC_MCONTEXT = 64;
  { Linux gregs[0..17] (R8 R9 R10 R11 R12 R13 R14 R15 RDI RSI RBP RBX RDX RAX
    RCX RSP RIP EFL) -> offset in DragonFly's mcontext. }
  DfGregOff: array[0..17] of Integer = (
    40, 48, 80, 88, 96, 104, 112, 120, 8, 16, 72, 64, 24, 56, 32, 192, 168, 184);
  DF_MC_TRAPNO = 136; DF_MC_ADDR = 144; DF_MC_ERR = 160; DF_MC_FPFORMAT = 212;
  DF_MC_FPREGS = 256; DF_MC_FPFMT_XMM = $10002;
  LX_UC_GREGS = 40;
  LX_UC_SIGMASK = 296;

var
  DfLxHandler: array[0..32] of Int64;   { by DragonFly signal number }

function LxSig(s: Int64): Int64;
var i: Integer;
begin
  for i := 1 to 31 do
    if SigMap[i] = s then begin Result := i; Exit; end;
  Result := s;
end;

{ Linux 64-bit mask (bit s-1) -> DragonFly sigset_t (4 x 32 bits). Signals
  with no DragonFly equivalent (16, 30, the real-time range) drop out. }
procedure MaskToDf(lx, df: Int64);
var s, b: Int64;
begin
  PInt64(df)^ := 0; PInt64(df + 8)^ := 0;
  for s := 1 to 31 do
    if ((lx shr (s - 1)) and 1) <> 0 then
    begin
      b := SigMap[Integer(s)];
      if (b >= 1) and (b <= 32) then
        PLongWord(df)^ := PLongWord(df)^ or LongWord(Int64(1) shl (b - 1));
    end;
end;

function MaskToLx(df: Int64): Int64;
var b, s: Int64;
begin
  Result := 0;
  for b := 1 to 32 do
    if ((PLongWord(df)^ shr (b - 1)) and 1) <> 0 then
    begin
      s := LxSig(b);
      if (s >= 1) and (s <= 64) then Result := Result or (Int64(1) shl (s - 1));
    end;
end;

function SaFlagsToDf(f: Int64): Int64;
begin
  Result := 0;
  if (f and LX_SA_NOCLDSTOP) <> 0 then Result := Result or DF_SA_NOCLDSTOP;
  if (f and LX_SA_NOCLDWAIT) <> 0 then Result := Result or DF_SA_NOCLDWAIT;
  if (f and LX_SA_SIGINFO) <> 0 then Result := Result or DF_SA_SIGINFO;
  if (f and LX_SA_ONSTACK) <> 0 then Result := Result or DF_SA_ONSTACK;
  if (f and LX_SA_RESTART) <> 0 then Result := Result or DF_SA_RESTART;
  if (f and LX_SA_NODEFER) <> 0 then Result := Result or DF_SA_NODEFER;
  if (f and LX_SA_RESETHAND) <> 0 then Result := Result or DF_SA_RESETHAND;
end;

function SaFlagsToLx(f: Int64): Int64;
begin
  Result := 0;
  if (f and DF_SA_NOCLDSTOP) <> 0 then Result := Result or LX_SA_NOCLDSTOP;
  if (f and DF_SA_NOCLDWAIT) <> 0 then Result := Result or LX_SA_NOCLDWAIT;
  if (f and DF_SA_SIGINFO) <> 0 then Result := Result or LX_SA_SIGINFO;
  if (f and DF_SA_ONSTACK) <> 0 then Result := Result or LX_SA_ONSTACK;
  if (f and DF_SA_RESTART) <> 0 then Result := Result or LX_SA_RESTART;
  if (f and DF_SA_NODEFER) <> 0 then Result := Result or LX_SA_NODEFER;
  if (f and DF_SA_RESETHAND) <> 0 then Result := Result or LX_SA_RESETHAND;
end;

{ DragonFly si_code -> Linux si_code. }
function LxSiCode(sig, c: Int64): Int64;
begin
  case c of
    -3: Result := -4;          { SI_ASYNCIO }
    -4: Result := -3;          { SI_MESGQ }
  else
    Result := c;
    if sig = 8 then            { SIGFPE: INTOVF/INTDIV are swapped; 3.. agree }
      if c = 1 then Result := 2 else if c = 2 then Result := 1;
  end;
end;

{ DragonFly siginfo_t (df, 80 B) -> Linux siginfo_t (lx, 128 B). }
procedure SiginfoToLx(df, lx: Int64);
var i: Integer; c, ls: Int64;
begin
  for i := 0 to 15 do PInt64(lx + i * 8)^ := 0;
  ls := LxSig(PInteger(df)^);
  PInteger(lx)^ := Integer(ls);                               { si_signo }
  PInteger(lx + 4)^ := PInteger(df + 4)^;                     { si_errno }
  c := PInteger(df + 8)^;
  PInteger(lx + 8)^ := Integer(LxSiCode(ls, c));              { si_code }
  if c <= 0 then
  begin
    PInteger(lx + 16)^ := PInteger(df + 12)^;                 { si_pid }
    PInteger(lx + 20)^ := PInteger(df + 16)^;                 { si_uid }
  end
  else
    PInt64(lx + 16)^ := PInt64(df + 24)^;                     { si_addr }
end;

type
  TDfLxHandler = procedure(sig, info, uc: Int64); cdecl;

{ The handler DragonFly actually calls (SA_SIGINFO: rdi, rsi, rdx = uc). }
procedure DfSigEntry(sig, info, uc: Int64); cdecl;
var li: array[0..15] of Int64;        { Linux siginfo_t, 128 B }
    lu: array[0..63] of Int64;        { Linux ucontext_t through uc_sigmask }
    i: Integer;
    h, ls, mc: Int64;
begin
  if (sig < 1) or (sig > 32) then Exit;
  h := DfLxHandler[Integer(sig)];
  if h = 0 then Exit;
  ls := LxSig(sig);
  for i := 0 to 63 do lu[i] := 0;
  if info <> 0 then SiginfoToLx(info, Int64(@li[0]))
  else
  begin
    for i := 0 to 15 do li[i] := 0;
    PInteger(@li[0])^ := Integer(ls);
  end;
  mc := uc + DF_UC_MCONTEXT;
  if uc <> 0 then
  begin
    for i := 0 to 17 do
      lu[LX_UC_GREGS div 8 + i] := PInt64(mc + DfGregOff[i])^;
    lu[LX_UC_GREGS div 8 + 19] := PInt64(mc + DF_MC_ERR)^;              { ERR }
    lu[LX_UC_GREGS div 8 + 20] := PInt64(mc + DF_MC_TRAPNO)^;           { TRAPNO }
    lu[LX_UC_GREGS div 8 + 22] := PInt64(mc + DF_MC_ADDR)^;             { CR2 }
    lu[LX_UC_SIGMASK div 8] := MaskToLx(uc);
    { An SSE floating-point trap arrives with si_code 0 (measured on 6.4.2;
      7, FPE_FLTINV, is handled the same way): it is re-derived the Linux
      way, from the saved MXCSR's flags that are set AND unmasked, in Linux's
      priority order; FPC-style runtime errors depend on it. The fxsave
      image (XMM or YMM format alike) starts at mc_fpregs. }
    if (sig = 8) and (info <> 0)
       and ((PInteger(Int64(@li[0]) + 8)^ = 7) or (PInteger(Int64(@li[0]) + 8)^ = 0))
       and ((PInteger(mc + DF_MC_FPFORMAT)^ = DF_MC_FPFMT_XMM)
            or (PInteger(mc + DF_MC_FPFORMAT)^ = DF_MC_FPFMT_XMM + 1)) then
    begin
      h := PLongWord(mc + DF_MC_FPREGS + 24)^;                  { fxsave mxcsr }
      h := h and (not (h shr 7)) and $3F;
      if (h and $01) <> 0 then PInteger(Int64(@li[0]) + 8)^ := 7          { FPE_FLTINV }
      else if (h and $04) <> 0 then PInteger(Int64(@li[0]) + 8)^ := 3     { FPE_FLTDIV }
      else if (h and $08) <> 0 then PInteger(Int64(@li[0]) + 8)^ := 4     { FPE_FLTOVF }
      else if (h and $12) <> 0 then PInteger(Int64(@li[0]) + 8)^ := 5     { FPE_FLTUND }
      else if (h and $20) <> 0 then PInteger(Int64(@li[0]) + 8)^ := 6;    { FPE_FLTRES }
      h := DfLxHandler[Integer(sig)];
    end;
  end;
  if info <> 0 then TDfLxHandler(h)(ls, Int64(@li[0]), Int64(@lu[0]))
  else TDfLxHandler(h)(ls, 0, Int64(@lu[0]));
  if uc <> 0 then
    for i := 0 to 17 do
      PInt64(mc + DfGregOff[i])^ := lu[LX_UC_GREGS div 8 + i];
end;

function DfRtSigaction(sig, act, oact: Int64): Int64;
var fa, fo: array[0..3] of Int64;     { DragonFly struct sigaction, 32 B }
    ds, h, oldh, r: Int64;
begin
  ds := DfSig(sig);
  if (ds < 1) or (ds > 32) then begin Result := -LX_EINVAL; Exit; end;
  oldh := DfLxHandler[Integer(ds)];
  fa[0] := 0; fa[1] := 0; fa[2] := 0; fa[3] := 0;
  fo[0] := 0; fo[1] := 0; fo[2] := 0; fo[3] := 0;
  if act <> 0 then
  begin
    h := PInt64(act)^;
    MaskToDf(PInt64(act + 24)^, Int64(@fa[0]) + 12);
    PInteger(Int64(@fa[0]) + 8)^ := Integer(SaFlagsToDf(PInt64(act + 8)^));
    if (h = 0) or (h = 1) then fa[0] := h                 { SIG_DFL / SIG_IGN }
    else
    begin
      DfLxHandler[Integer(ds)] := h;
      fa[0] := Int64(@DfSigEntry);
      PInteger(Int64(@fa[0]) + 8)^ := PInteger(Int64(@fa[0]) + 8)^ or DF_SA_SIGINFO;
    end;
    r := DfSys(DF_SIGACTION, ds, Int64(@fa[0]), Int64(@fo[0]), 0, 0, 0);
    if r <> 0 then DfLxHandler[Integer(ds)] := oldh
    else if (h = 0) or (h = 1) then DfLxHandler[Integer(ds)] := 0;
  end
  else
    r := DfSys(DF_SIGACTION, ds, 0, Int64(@fo[0]), 0, 0, 0);
  if (r = 0) and (oact <> 0) then
  begin
    if fo[0] = Int64(@DfSigEntry) then PInt64(oact)^ := oldh
    else PInt64(oact)^ := fo[0];
    PInt64(oact + 8)^ := SaFlagsToLx(PInteger(Int64(@fo[0]) + 8)^);
    PInt64(oact + 16)^ := 0;
    PInt64(oact + 24)^ := MaskToLx(Int64(@fo[0]) + 12);
  end;
  Result := Lx(r);
end;

function DfRtSigprocmask(how, nset, oset: Int64): Int64;
var fn, fo: array[0..1] of Int64;
    r: Int64;
begin
  if (how < 0) or (how > 2) then begin Result := -LX_EINVAL; Exit; end;
  fo[0] := 0; fo[1] := 0;
  if nset <> 0 then
  begin
    MaskToDf(PInt64(nset)^, Int64(@fn[0]));
    r := DfSys(DF_SIGPROCMASK, how + 1, Int64(@fn[0]), Int64(@fo[0]), 0, 0, 0);
  end
  else
    r := DfSys(DF_SIGPROCMASK, how + 1, 0, Int64(@fo[0]), 0, 0, 0);
  if (r = 0) and (oset <> 0) then PInt64(oset)^ := MaskToLx(Int64(@fo[0]));
  Result := Lx(r);
end;

{ sigaltstack: Linux stack_t is sp, flags(int), size; DragonFly's is sp,
  size, flags; SS_DISABLE is 2 on Linux and 4 on DragonFly. }
function DfSigaltstack(ss, oss: Int64): Int64;
var t, o: array[0..2] of Int64; r, f, pt, po: Int64;
begin
  pt := 0; po := 0;
  if ss <> 0 then
  begin
    t[0] := PInt64(ss)^;
    t[1] := PInt64(ss + 16)^;
    f := PInteger(ss + 8)^;
    t[2] := 0;
    if (f and 1) <> 0 then t[2] := t[2] or 1;          { SS_ONSTACK }
    if (f and 2) <> 0 then t[2] := t[2] or 4;          { SS_DISABLE }
    pt := Int64(@t[0]);
  end;
  if oss <> 0 then po := Int64(@o[0]);
  r := DfSys(DF_SIGALTSTACK, pt, po, 0, 0, 0, 0);
  if (r = 0) and (oss <> 0) then
  begin
    PInt64(oss)^ := o[0];
    f := 0;
    if (PInteger(@o[2])^ and 1) <> 0 then f := f or 1;
    if (PInteger(@o[2])^ and 4) <> 0 then f := f or 2;
    PInteger(oss + 8)^ := Integer(f);
    PInt64(oss + 16)^ := o[1];
  end;
  Result := Lx(r);
end;

{ tkill/tgkill: lwp_kill(pid, tid, sig). }
function DfThrKill(tid, sig: Int64): Int64;
var ds: Int64;
begin
  ds := DfSig(sig);
  if (ds = 0) and (sig <> 0) then begin Result := -LX_EINVAL; Exit; end;
  Result := Lx(DfSys(DF_LWP_KILL, DfSys(DF_GETPID, 0, 0, 0, 0, 0, 0), tid and $FFFF, ds, 0, 0, 0));
end;

{ ---- Threads -----------------------------------------------------------------
  The clone stub's translator leg (thread_emit.inc, shared with OpenBSD and
  NetBSD) calls clone through the thunk, with the child's resume address in
  r9. That becomes lwp_create2 started at DfLwpStartA, which resumes the
  child at that address on the stage area, as a clone child resumes. Linux
  flags are honoured as far as pxx uses them: the stack, PARENT_SETTID
  (lwp_tid2), CHILD_CLEARTID (the ctid pointer is parked in the child's TLS
  block, which the stub has already carved at stage+16, and acted on by the
  thread's exit). A new LWP inherits its creator's TLS bases, like a Linux
  clone without CLONE_SETTLS; the stub then installs the child's block with
  arch_prctl, through the translator. }

{ Thread ids. DragonFly numbers a process's LWPs from 1 and hands an exited
  LWP's number to the next one at once; Linux tids are effectively never
  reused within a run, and code keys things by them (crtl's pthread_join
  finds its registry slot by tid). So the tid a Linux program sees is
  lwpid + gen * 65536, with gen a per-clone counter (1..32767) kept in the
  thread's own TLS slot 14 above the ctid pointer (bits 48..63; a user
  pointer leaves them clear). The main thread's gen is 0: its tid is its
  lwpid. tkill/tgkill take the low 16 bits back off. }
var
  DfGen: Int64;

function DfGettid: Int64;
var l: Int64;
begin
  l := DfSys(DF_LWP_GETTID, 0, 0, 0, 0, 0, 0);
  { No clone yet: the only thread, gen 0 -- and possibly no TLS block yet
    (set_tid_address runs at start-up, before the GS base is set). }
  if (l > 0) and (l < 65536) and (DfMainTid <> 0) then
    l := l + ((PInt64(Int64(__pxxTlsBase) + 8 * DF_TLS_SLOT_CTID)^ shr 48) and $7FFF) shl 16;
  Result := l;
end;

function DfClone(flags, stack, ptid, ctid, cont: Int64): Int64;
var p: array[0..4] of Int64; tid: Integer; r, gen: Int64;
begin
  if ((flags and $100) = 0) or (stack = 0) or (cont = 0) then
  begin
    Result := -LX_EINVAL; Exit;                           { only CLONE_VM threads }
  end;
  if DfMainTid = 0 then DfMainTid := DfSys(DF_LWP_GETTID, 0, 0, 0, 0, 0, 0);
  if DfExitStack = 0 then
  begin
    Result := DfMmap(0, DF_EXIT_STACK_SIZE, 3, 2 or DF_MAP_ANON, -1, 0);
    if Result < 0 then begin Result := -LX_ENOMEM; Exit; end;
    DfExitStack := Result;
  end;
  DfGen := (DfGen mod 32767) + 1;     { not atomic: two racing clones may share a gen, but two live LWPs never share an lwpid }
  gen := DfGen;
  if (flags and $00200000) = 0 then ctid := 0;            { CLONE_CHILD_CLEARTID }
  PInt64(stack + 16 + 8 * DF_TLS_SLOT_CTID)^ := ctid or (gen shl 48);
  PInt64(stack - 16)^ := cont;                            { DfLwpStartA's [cont, stage] }
  PInt64(stack - 8)^ := stack;
  tid := 0;
  p[0] := Int64(@DfLwpStartA);                            { lwp_func }
  p[1] := stack - 16;                                     { lwp_arg }
  p[2] := stack - 16;                                     { lwp_stack: the NULL return goes below }
  p[3] := Int64(@tid);                                    { lwp_tid1 }
  p[4] := 0;
  r := DfSys(DF_LWP_CREATE2, Int64(@p[0]), 0, 0, 0, 0, 0);
  if r < 0 then begin Result := Lx(r); Exit; end;
  Result := tid;
  if (tid > 0) and (tid < 65536) then Result := tid + (gen shl 16);
  { CLONE_PARENT_SETTID, written here rather than by the kernel (lwp_tid2
    would write the bare lwpid). The child may already run; its exit waits
    for this word to be set before it clears it. }
  if (flags and $00100000) <> 0 then PInteger(ptid)^ := Integer(Result);
end;

{ exit(2): this thread. The main thread (or a program that never made one)
  ends the process, as pxx's runtime expects. }
procedure DfExitThread(code: Int64);
var ctid: Int64;
begin
  if (DfMainTid = 0) or (DfSys(DF_LWP_GETTID, 0, 0, 0, 0, 0, 0) = DfMainTid) then
    DfSys(DF_EXIT, code, 0, 0, 0, 0, 0);
  ctid := PInt64(Int64(__pxxTlsBase) + 8 * DF_TLS_SLOT_CTID)^ and $FFFFFFFFFFFF;
  if ctid = 0 then DfSys(DF_EXTEXIT, DF_EXTEXIT_LWP, 0, 0, 0, 0, 0);
  { The parent stores the tid after lwp_create2 returns, and this thread may
    get here first: wait until it is set, or the clear below would be undone
    and the joiner would wait for a dead thread. }
  while PInteger(ctid)^ = 0 do DfSys(DF_SCHED_YIELD, 0, 0, 0, 0, 0, 0);
  DfThreadExitA(ctid, Int64(@DfExitLock), DfExitStack + DF_EXIT_STACK_SIZE, Int64(@DfRawA));
end;

{ futex over umtx_sleep / umtx_wakeup. Linux WAIT 0, WAKE 1, REQUEUE 3,
  WAIT_BITSET 9, WAKE_BITSET 10 (a bitset op with a full mask is the plain
  op); FUTEX_PRIVATE_FLAG is ignored: umtx queues are keyed by physical
  address, which serves both. umtx_sleep(addr, val, usec) answers EBUSY when
  *addr <> val (Linux's EAGAIN), EWOULDBLOCK on its timeout -- which
  kern.umtx_timeout_max caps, so a wait loops until its own deadline (none:
  until woken). WAIT's timeout is relative, WAIT_BITSET's absolute
  (CLOCK_MONOTONIC, or CLOCK_REALTIME with FUTEX_CLOCK_REALTIME 256).
  REQUEUE wakes everyone on uaddr instead (waiters must tolerate a spurious
  wake). WAKE answers 0, not the number woken: umtx_wakeup does not count. }
function DfFutex(uaddr, op, val, ts, uaddr2, val3: Int64): Int64;
var now: array[0..1] of Int64; dl, left, r, clk: Int64;
begin
  case op and 127 of
    0, 9:
      begin
        if ((op and 127) = 9) and ((val3 and $FFFFFFFF) <> $FFFFFFFF) then
        begin Result := -LX_EINVAL; Exit; end;
        clk := 4;                                             { CLOCK_MONOTONIC }
        if ((op and 127) = 9) and ((op and 256) <> 0) then clk := 0;
        dl := -1;
        if ts <> 0 then
        begin
          dl := PInt64(ts)^ * 1000000 + PInt64(ts + 8)^ div 1000;   { usec }
          if (op and 127) = 0 then
          begin
            DfSys(DF_CLOCK_GETTIME, clk, Int64(@now[0]), 0, 0, 0, 0);
            dl := dl + now[0] * 1000000 + now[1] div 1000;
          end;
        end;
        repeat
          left := 1000000;
          if dl >= 0 then
          begin
            DfSys(DF_CLOCK_GETTIME, clk, Int64(@now[0]), 0, 0, 0, 0);
            left := dl - (now[0] * 1000000 + now[1] div 1000);
            if left <= 0 then begin Result := -110; Exit; end;   { ETIMEDOUT }
            if left > 1000000 then left := 1000000;
          end;
          r := DfSys(DF_UMTX_SLEEP, uaddr, Integer(val), left, 0, 0, 0);
          if r = 0 then begin Result := 0; Exit; end;
          if r = -16 then begin Result := -11; Exit; end;           { EBUSY -> EAGAIN }
          if r <> -35 then begin Result := Lx(r); Exit; end;        { EINTR .. }
        until False;
      end;
    1, 10:
      begin
        if ((op and 127) = 10) and ((val3 and $FFFFFFFF) <> $FFFFFFFF) then
        begin Result := -LX_EINVAL; Exit; end;
        if (val <= 0) or (val >= $7FFFFFFF) then val := 0;    { 0 = all }
        Result := Lx(DfSys(DF_UMTX_WAKEUP, uaddr, val, 0, 0, 0, 0));
      end;
    3: Result := Lx(DfSys(DF_UMTX_WAKEUP, uaddr, 0, 0, 0, 0, 0));
  else
    Result := -LX_ENOSYS;
  end;
end;

{ ---- Sockets -----------------------------------------------------------------
  fbsdabi's code with DragonFly's numbers: the structs are FreeBSD's (BSD
  sockaddr header -- u8 length, u8 family; 48-byte msghdr with 32-bit
  iovlen/controllen; 12-byte cmsghdr with the data at 16; 104-byte sun_path).
  What is DragonFly's: AF_INET6 is 28, SOCK_NONBLOCK/SOCK_CLOEXEC are
  $20000000/$10000000, MSG_NOSIGNAL is $400 and MSG_CMSG_CLOEXEC $1000,
  TCP_KEEPIDLE/INTVL/CNT are $100/$200/$400, and there is no SO_PEERCRED
  (LOCAL_PEERCRED answers an xucred instead) or SO_DOMAIN/SO_PROTOCOL.
  Measured on 6.4.2 with offsetof() and the headers (2026-11-13). }
const
  DF_ACCEPT4 = 541;
  LX_EAFNOSUPPORT = 97; LX_ENOPROTOOPT = 92;

function DfAf(a: Int64): Int64;
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
function DfSockType(t: Int64): Int64;
begin
  Result := t and $FF;
  if (t and $800) <> 0 then Result := Result or $20000000;
  if (t and $80000) <> 0 then Result := Result or $10000000;
end;

function DfMsgFlags(f: Int64): Int64;
begin
  Result := f and $7;                                          { OOB PEEK DONTROUTE }
  if (f and $8) <> 0 then Result := Result or $20;             { CTRUNC }
  if (f and $20) <> 0 then Result := Result or $10;            { TRUNC }
  if (f and $40) <> 0 then Result := Result or $80;            { DONTWAIT }
  if (f and $80) <> 0 then Result := Result or $8;             { EOR }
  if (f and $100) <> 0 then Result := Result or $40;           { WAITALL }
  if (f and $4000) <> 0 then Result := Result or $400;         { NOSIGNAL }
  if (f and $40000000) <> 0 then Result := Result or $1000;    { CMSG_CLOEXEC }
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
function SaToDf(src, len, dst: Int64): Int64;
var i, af: Int64;
begin
  if (src = 0) or (len < 2) then begin Result := -LX_EINVAL; Exit; end;
  if len > 128 then len := 128;
  for i := 0 to len - 1 do PByte(dst + i)^ := PByte(src + i)^;
  af := DfAf(PWord(src)^);
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

{ socket option (level, name) -> DragonFly; level -1 = no equivalent. }
procedure SockOptToDf(var level, name: Int64);
begin
  case level of
    1: begin                                                    { SOL_SOCKET }
         level := $FFFF;
         case name of
           1: name := $1; 2: name := $4; 3: name := $1008; 4: name := $1007;
           5: name := $10; 6: name := $20; 7: name := $1001; 8: name := $1002;
           9: name := $8; 10: name := $100; 13: name := $80; 15: name := $200;
           18: name := $1004; 19: name := $1003; 20: name := $1006; 21: name := $1005;
           30: name := $2;
         else level := -1;
         end;
       end;
    6: case name of                                             { IPPROTO_TCP }
         1, 2: ;
         4: name := $100; 5: name := $200; 6: name := $400;       { KEEPIDLE KEEPINTVL KEEPCNT }
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

function DfSockopt(isGet: Boolean; fd, level, name, val, lenp: Int64): Int64;
var lv, nm, r, e: Int64;
begin
  lv := level; nm := name;
  SockOptToDf(lv, nm);
  if lv < 0 then begin Result := -LX_ENOPROTOOPT; Exit; end;
  if not isGet then
  begin
    Result := Lx(DfSys(DF_SETSOCKOPT, fd, lv, nm, val, lenp, 0));
    Exit;
  end;
  r := DfSys(DF_GETSOCKOPT, fd, lv, nm, val, lenp, 0);
  if (r = 0) and (lv = $FFFF) and (val <> 0) then
  begin
    if nm = $1007 then                                          { SO_ERROR holds an errno }
    begin
      e := PInteger(val)^;
      if (e >= 35) and (e <= 95) then PInteger(val)^ := ErrMap[Integer(e)];
    end
  end;
  Result := Lx(r);
end;

function DfSockAddrCall(nr, fd, sa, len: Int64): Int64;    { connect, bind }
var b: array[0..15] of Int64; n: Int64;
begin
  n := SaToDf(sa, len, Int64(@b[0]));
  if n < 0 then Result := n
  else Result := Lx(DfSys(nr, fd, Int64(@b[0]), n, 0, 0, 0));
end;

function DfSockAddrOut(nr, fd, sa, lenp, flags: Int64): Int64;  { accept4, getsockname, getpeername }
var r: Int64;
begin
  if nr = DF_ACCEPT4 then
  begin
    r := 0;
    if (flags and $800) <> 0 then r := r or $20000000;
    if (flags and $80000) <> 0 then r := r or $10000000;
    r := DfSys(nr, fd, sa, lenp, r, 0, 0);
  end
  else r := DfSys(nr, fd, sa, lenp, 0, 0, 0);
  if r >= 0 then SaToLx(sa, lenp);
  Result := Lx(r);
end;

function DfSendto(fd, buf, len, flags, sa, salen: Int64): Int64;
var b: array[0..15] of Int64; n: Int64;
begin
  if sa = 0 then
  begin
    Result := Lx(DfSys(DF_SENDTO, fd, buf, len, DfMsgFlags(flags), 0, 0));
    Exit;
  end;
  n := SaToDf(sa, salen, Int64(@b[0]));
  if n < 0 then Result := n
  else Result := Lx(DfSys(DF_SENDTO, fd, buf, len, DfMsgFlags(flags), Int64(@b[0]), n));
end;

function DfRecvfrom(fd, buf, len, flags, sa, lenp: Int64): Int64;
var r: Int64;
begin
  r := DfSys(DF_RECVFROM, fd, buf, len, DfMsgFlags(flags), sa, lenp);
  if r >= 0 then SaToLx(sa, lenp);
  Result := Lx(r);
end;

{ Linux cmsg chain (size_t len, int level, int type; data at 16) <-> OpenBSD
  (u32 len, int level, int type; data at 16 -- _ALIGN(12) on amd64). Rewritten
  in place: both headers fit the same 16 bytes and the data does not move.
  SOL_SOCKET is the only level renumbered; SCM_RIGHTS is 1 on both. }
procedure CmsgToDf(ctl, clen: Int64);
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

{ msghdr: Linux 56 B (size_t iovlen/controllen, flags at 48), OpenBSD 48 B. }
function DfMsg(isSend: Boolean; fd, lm, flags: Int64): Int64;
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
      n := SaToDf(fm[0], fm[1], Int64(@nb[0]));
      if n < 0 then begin Result := n; Exit; end;
      fm[0] := Int64(@nb[0]); fm[1] := n;
    end;
    CmsgToDf(fm[4], fm[5]);
    r := DfSys(DF_SENDMSG, fd, Int64(@fm[0]), DfMsgFlags(flags), 0, 0, 0);
    CmsgToLx(fm[4], fm[5]);                                     { the caller's buffer, restored }
  end
  else
  begin
    r := DfSys(DF_RECVMSG, fd, Int64(@fm[0]), DfMsgFlags(flags), 0, 0, 0);
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



const
  DF_KQUEUE = 362; DF_KEVENT = 363;
  DF_EVFILT_READ = -1; DF_EVFILT_WRITE = -2;
  DF_EV_ADD = $1; DF_EV_DELETE = $2; DF_EV_ENABLE = $4; DF_EV_ONESHOT = $10;
  DF_EV_CLEAR = $20; DF_EV_ERROR = $4000; DF_EV_EOF = $8000;
  LX_EPOLLIN = $1; LX_EPOLLPRI = $2; LX_EPOLLOUT = $4; LX_EPOLLERR = $8;
  LX_EPOLLHUP = $10; LX_EPOLLRDHUP = $2000;
  EP_MAX = 64;                    { kevents fetched per epoll_wait }

{ ---- epoll over kqueue ------------------------------------------------------
  fbsdabi's emulation. DragonFly's struct kevent has FreeBSD's field offsets
  (ident 0, filter 8, flags 10, fflags 12, data 16, udata 24) but no ext[],
  so it is 32 bytes, not 64; the EVFILT_/EV_ values agree (measured on
  6.4.2). DragonFly has no epoll. An epoll instance IS a kqueue; an interest in an fd is
  up to two kevent filters (READ for EPOLLIN/PRI/RDHUP, WRITE for EPOLLOUT)
  carrying the caller's epoll_data as udata. EPOLLET -> EV_CLEAR, EPOLLONESHOT
  -> EV_ONESHOT. epoll_wait folds the READ and WRITE kevents of one fd back
  into one epoll_event, as Linux reports it. struct epoll_event is PACKED on
  x86-64: u32 events at 0, u64 data at 4, 12 bytes. }

function DfKev1(kq, ident, filter, flags, udata: Int64): Int64;
var kv: array[0..3] of Int64;     { struct kevent, 32 B }
    i: Integer;
begin
  for i := 0 to 3 do kv[i] := 0;
  kv[0] := ident;
  PSmallInt(Int64(@kv[0]) + 8)^ := SmallInt(filter);
  PWord(Int64(@kv[0]) + 10)^ := Word(flags);
  kv[3] := udata;
  Result := DfSys(DF_KEVENT, kq, Int64(@kv[0]), 1, 0, 0, 0);
end;

function DfEpollCtl(kq, op, fd, ev: Int64): Int64;
var e, data, fl, r: Int64;
begin
  if (op = 2) or (ev = 0) then                                 { EPOLL_CTL_DEL }
  begin
    r := DfKev1(kq, fd, DF_EVFILT_READ, DF_EV_DELETE, 0);
    if DfKev1(kq, fd, DF_EVFILT_WRITE, DF_EV_DELETE, 0) = 0 then r := 0;
    Result := Lx(r);
    Exit;
  end;
  e := PInteger(ev)^ and $FFFFFFFF;
  data := PInt64(ev + 4)^;
  fl := DF_EV_ADD or DF_EV_ENABLE;
  if (e and $80000000) <> 0 then fl := fl or DF_EV_CLEAR;      { EPOLLET }
  if (e and $40000000) <> 0 then fl := fl or DF_EV_ONESHOT;    { EPOLLONESHOT }
  r := 0;
  if (e and (LX_EPOLLIN or LX_EPOLLPRI or LX_EPOLLRDHUP)) <> 0 then
    r := DfKev1(kq, fd, DF_EVFILT_READ, fl, data)
  else if op = 3 then DfKev1(kq, fd, DF_EVFILT_READ, DF_EV_DELETE, 0);
  if r < 0 then begin Result := Lx(r); Exit; end;
  if (e and LX_EPOLLOUT) <> 0 then
    r := DfKev1(kq, fd, DF_EVFILT_WRITE, fl, data)
  else if op = 3 then DfKev1(kq, fd, DF_EVFILT_WRITE, DF_EV_DELETE, 0);
  Result := Lx(r);
end;

function DfEpollWait(kq, evs, maxev, ms: Int64): Int64;
var kv: array[0..EP_MAX * 4 - 1] of Int64;
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
  r := DfSys(DF_KEVENT, kq, 0, 0, Int64(@kv[0]), maxev, tp);
  if r < 0 then begin Result := Lx(r); Exit; end;
  n := 0;
  for i := 0 to r - 1 do
  begin
    base := Int64(@kv[0]) + i * 32;
    ident := PInt64(base)^;
    fl := PWord(base + 10)^;
    e := 0;
    if PSmallInt(base + 8)^ = DF_EVFILT_READ then e := LX_EPOLLIN
    else e := LX_EPOLLOUT;
    if (fl and DF_EV_EOF) <> 0 then
    begin
      e := e or LX_EPOLLHUP;
      if PSmallInt(base + 8)^ = DF_EVFILT_READ then e := e or LX_EPOLLRDHUP;
      if PInteger(base + 12)^ <> 0 then e := e or LX_EPOLLERR;  { fflags = socket error }
    end;
    if (fl and DF_EV_ERROR) <> 0 then e := LX_EPOLLERR;
    { fold into an earlier event for the same fd; kv[] holds ident, the
      output array holds only data -- so match on the kevent list }
    j := 0;
    while j < i do
    begin
      if PInt64(Int64(@kv[0]) + j * 32)^ = ident then Break;
      Inc(j);
    end;
    if j < i then
    begin
      { the earlier kevent j was emitted at output slot PInteger(kv j .data)^ }
      j := PInt64(Int64(@kv[0]) + j * 32 + 16)^;
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

{ ---- termios -----------------------------------------------------------------
  Linux's kernel struct termios is 36 bytes (4 flag words, c_line, c_cc[19]),
  with the line speed coded into c_cflag (CBAUD); DragonFly's is 44 (4 flag
  words, c_cc[20], c_ispeed, c_ospeed as plain numbers). Almost every flag bit
  and every c_cc index differs; a disabled control char is 0 on Linux and
  0xff (_POSIX_VDISABLE) on DragonFly. fbsdabi's tables, with what DragonFly
  6.4.2 measures differently: no IUTF8 (dropped), OCRNL/ONOCR/ONLRET at
  $10/$20/$40, CRTSCTS $30000. The c_cc indices and the ioctl numbers are
  FreeBSD's. }
const
  TIflLx: array[0..13] of Int64 = ($1,$2,$4,$8,$10,$20,$40,$80,$100,$400,$1000,$800,$2000,$4000);
  TIflDf: array[0..13] of Int64 = ($1,$2,$4,$8,$10,$20,$40,$80,$100,$200,$400,$800,$2000,0);   { no IUTF8 }
  TOflLx: array[0..5] of Int64 = ($1,$4,$1800,$8,$10,$20);
  TOflDf: array[0..5] of Int64 = ($1,$2,$4,$10,$20,$40);
  TCflLx: array[0..6] of Int64 = ($40,$80,$100,$200,$400,$800,$80000000);
  TCflDf: array[0..6] of Int64 = ($400,$800,$1000,$2000,$4000,$8000,$30000);
  TLflLx: array[0..13] of Int64 = ($1,$2,$8,$10,$20,$40,$80,$100,$200,$400,$800,$1000,$4000,$8000);
  TLflDf: array[0..13] of Int64 = ($80,$100,$8,$2,$4,$10,$80000000,$400000,$40,$20,$1,$800000,$20000000,$400);
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
    if (src[i] <> 0) and ((v and src[i]) = src[i]) then Result := Result or dst[i];   { 0 = no counterpart }
end;

function SpeedToLx(n: Int64): Int64;
var i: Integer;
begin
  for i := 0 to 15 do if TBaudLo[i] = n then begin Result := i; Exit; end;
  for i := 1 to 15 do if TBaudHi[i] = n then begin Result := $1000 or i; Exit; end;
  Result := 15;                                                 { unknown: B38400 }
end;

function SpeedToDf(c: Int64): Int64;
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
  PInteger(lx)^ := Integer(MapBits(PInteger(fb)^, TIflDf, TIflLx));
  PInteger(lx + 4)^ := Integer(MapBits(PInteger(fb + 4)^, TOflDf, TOflLx));
  cf := MapBits(PInteger(fb + 8)^ and $FFFFFFFF, TCflDf, TCflLx);
  cf := cf or (((PInteger(fb + 8)^ shr 8) and 3) shl 4);        { CSIZE }
  cf := cf or SpeedToLx(PInteger(fb + 40)^);                    { c_ospeed -> CBAUD }
  PInteger(lx + 8)^ := Integer(cf);
  PInteger(lx + 12)^ := Integer(MapBits(PInteger(fb + 12)^ and $FFFFFFFF, TLflDf, TLflLx));
  for i := 0 to 16 do
  begin
    ix := TCcMap[i];
    if ix < 0 then Continue;
    c := PByte(fb + 16 + ix)^;
    if (c = $FF) and (i <> 5) and (i <> 6) then c := 0;         { VTIME/VMIN are numbers }
    PByte(lx + 17 + i)^ := c;
  end;
end;

procedure TermiosToDf(lx, fb: Int64);
var i, ix: Integer; c: Byte; cf, sp: Int64;
begin
  for i := 0 to 43 do PByte(fb + i)^ := 0;
  for i := 0 to 19 do PByte(fb + 16 + i)^ := $FF;
  PInteger(fb)^ := Integer(MapBits(PInteger(lx)^, TIflLx, TIflDf));
  PInteger(fb + 4)^ := Integer(MapBits(PInteger(lx + 4)^, TOflLx, TOflDf));
  cf := PInteger(lx + 8)^ and $FFFFFFFF;
  PInteger(fb + 8)^ := Integer(MapBits(cf, TCflLx, TCflDf) or (((cf shr 4) and 3) shl 8));
  PInteger(fb + 12)^ := Integer(MapBits(PInteger(lx + 12)^, TLflLx, TLflDf));
  for i := 0 to 16 do
  begin
    ix := TCcMap[i];
    if ix < 0 then Continue;
    c := PByte(lx + 17 + i)^;
    if (c = 0) and (i <> 5) and (i <> 6) then c := $FF;
    PByte(fb + 16 + ix)^ := c;
  end;
  sp := SpeedToDf(cf);
  PInteger(fb + 36)^ := Integer(sp);
  PInteger(fb + 40)^ := Integer(sp);
end;

{ ---- timerfd over kqueue -----------------------------------------------------
  DragonFly has no timerfd, and pxx's scheduler parks every timed wait on one
  (CoSleep, the *Timeout waits, DNS). A timerfd here is a kqueue holding one
  EVFILT_TIMER: a kqueue fd is itself readable while it has a pending event,
  so epoll (kqueue) and poll see it fire exactly as they would a timerfd. read
  fetches the timer's kevent, whose data is the expiration count -- the u64 a
  timerfd read answers. DfTfd marks which fds are such kqueues (bit 0), their
  TFD_NONBLOCK (bit 1) and CLOCK_REALTIME (bit 2); close clears the mark.
  DragonFly's EVFILT_TIMER counts in milliseconds (no NOTE_* units), so a
  time is rounded UP to a whole millisecond.
  NOT EMULATED: an interval different from the first expiry (the kqueue timer
  is periodic at one rate: the first fire comes at the interval), and
  timerfd_gettime / the old value (answered as disarmed). }

const
  DF_EVFILT_TIMER = -7;
  DF_TFD_MAX = 4096;

var
  DfTfd: array[0..DF_TFD_MAX - 1] of Byte;

function DfIsTfd(fd: Int64): Boolean;
begin
  Result := (fd >= 0) and (fd < DF_TFD_MAX) and ((DfTfd[Integer(fd)] and 1) <> 0);
end;

function DfTimerfdCreate(clock, flags: Int64): Int64;
var r: Int64;
begin
  if (clock <> 0) and (clock <> 1) and (clock <> 7) then begin Result := -LX_EINVAL; Exit; end;
  r := DfSys(DF_KQUEUE, 0, 0, 0, 0, 0, 0);
  if r < 0 then begin Result := Lx(r); Exit; end;
  if r >= DF_TFD_MAX then
  begin
    DfSys(DF_CLOSE, r, 0, 0, 0, 0, 0);
    Result := -24; Exit;                                      { EMFILE }
  end;
  if (flags and $80000) <> 0 then DfSys(DF_FCNTL, r, 2, 1, 0, 0, 0);   { TFD_CLOEXEC }
  DfTfd[Integer(r)] := 1;
  if (flags and $800) <> 0 then DfTfd[Integer(r)] := DfTfd[Integer(r)] or 2;   { TFD_NONBLOCK }
  if clock = 0 then DfTfd[Integer(r)] := DfTfd[Integer(r)] or 4;
  Result := r;
end;

function DfTimerfdSettime(fd, flags, nv, ov: Int64): Int64;
var kv: array[0..3] of Int64; ts: array[0..1] of Int64;
    valNs, intNs, i: Int64;
begin
  if not DfIsTfd(fd) then begin Result := -LX_EINVAL; Exit; end;
  if nv = 0 then begin Result := -14; Exit; end;              { EFAULT }
  if ov <> 0 then for i := 0 to 3 do PInt64(ov + i * 8)^ := 0;
  intNs := PInt64(nv)^ * 1000000000 + PInt64(nv + 8)^;
  valNs := PInt64(nv + 16)^ * 1000000000 + PInt64(nv + 24)^;
  for i := 0 to 3 do kv[i] := 0;
  kv[0] := 1;                                                 { ident }
  PSmallInt(Int64(@kv[0]) + 8)^ := DF_EVFILT_TIMER;
  if valNs = 0 then
  begin                                                       { disarm }
    PWord(Int64(@kv[0]) + 10)^ := DF_EV_DELETE;
    DfSys(DF_KEVENT, fd, Int64(@kv[0]), 1, 0, 0, 0);
    Result := 0; Exit;
  end;
  if (flags and 1) <> 0 then                                  { TFD_TIMER_ABSTIME }
  begin
    if (DfTfd[Integer(fd)] and 4) <> 0 then DfSys(DF_CLOCK_GETTIME, 0, Int64(@ts[0]), 0, 0, 0, 0)
    else DfSys(DF_CLOCK_GETTIME, 4, Int64(@ts[0]), 0, 0, 0, 0);
    valNs := valNs - (ts[0] * 1000000000 + ts[1]);
    if valNs < 1 then valNs := 1;
  end;
  if intNs > 0 then
  begin
    PWord(Int64(@kv[0]) + 10)^ := DF_EV_ADD or DF_EV_ENABLE;
    kv[2] := (intNs + 999999) div 1000000;
  end
  else
  begin
    PWord(Int64(@kv[0]) + 10)^ := DF_EV_ADD or DF_EV_ENABLE or DF_EV_ONESHOT;
    kv[2] := (valNs + 999999) div 1000000;
  end;
  Result := Lx(DfSys(DF_KEVENT, fd, Int64(@kv[0]), 1, 0, 0, 0));
end;

{ read(timerfd): the expiration count as a u64, or EAGAIN when not fired
  and non-blocking. }
function DfTimerfdRead(fd, buf, len: Int64): Int64;
var kv: array[0..3] of Int64; ts: array[0..1] of Int64; r: Int64;
begin
  if len < 8 then begin Result := -LX_EINVAL; Exit; end;
  ts[0] := 0; ts[1] := 0;
  if (DfTfd[Integer(fd)] and 2) <> 0 then
    r := DfSys(DF_KEVENT, fd, 0, 0, Int64(@kv[0]), 1, Int64(@ts[0]))
  else
    r := DfSys(DF_KEVENT, fd, 0, 0, Int64(@kv[0]), 1, 0);
  if r < 0 then begin Result := Lx(r); Exit; end;
  if r = 0 then begin Result := -11; Exit; end;               { EAGAIN }
  PInt64(buf)^ := kv[2];
  Result := 8;
end;

{ ---- process odds and ends -------------------------------------------------- }

{ A wait status carries a signal number twice: the terminating signal in bits
  0..6, the stopping one in bits 8..15. The layout is Linux's, except
  "continued": 19 (SIGCONT) on DragonFly, $FFFF on Linux. }
function WaitStatusToLx(st: Int64): Int64;
var lo: Int64;
begin
  st := st and $FFFF;
  lo := st and $7F;
  if st = 19 then Result := $FFFF
  else if lo = $7F then Result := (LxSig((st shr 8) and $FF) shl 8) or $7F
  else if lo <> 0 then Result := (st and not Int64($7F)) or LxSig(lo)
  else Result := st;
end;

function DfWait4(pid, status, options, rusage: Int64): Int64;
var st, r: Int64;
begin
  st := 0;
  r := options and 3;                                         { WNOHANG WUNTRACED agree }
  if (options and 8) <> 0 then r := r or 4;                   { WCONTINUED }
  r := DfSys(DF_WAIT4, pid, Int64(@st), r, rusage, 0, 0);
  if (r > 0) and (status <> 0) then PInteger(status)^ := Integer(WaitStatusToLx(st));
  Result := Lx(r);
end;

{ rt_sigtimedwait -> sigtimedwait(set, info, timeout). Answers the LINUX
  signal number; a timeout is EAGAIN on both. }
function DfRtSigtimedwait(nset, info, ts: Int64): Int64;
var ds: array[0..1] of Int64;
    di: array[0..9] of Int64;                                 { DragonFly siginfo_t, 80 B }
    r: Int64;
begin
  MaskToDf(PInt64(nset)^, Int64(@ds[0]));
  r := DfSys(DF_SIGTIMEDWAIT, Int64(@ds[0]), Int64(@di[0]), ts, 0, 0, 0);
  if r > 0 then
  begin
    if info <> 0 then SiginfoToLx(Int64(@di[0]), info);
    Result := LxSig(r);
  end
  else Result := Lx(r);
end;

{ times(): no DragonFly syscall. struct tms in Linux's USER_HZ (100) from
  getrusage; the result is a monotonic tick count. }
function DfTimes(buf: Int64): Int64;
var ru: array[0..17] of Int64;     { struct rusage, 144 B on both }
    ts: array[0..1] of Int64;
begin
  if buf <> 0 then
  begin
    DfSys(DF_GETRUSAGE, 0, Int64(@ru[0]), 0, 0, 0, 0);
    PInt64(buf)^ := ru[0] * 100 + ru[1] div 10000;         { utime }
    PInt64(buf + 8)^ := ru[2] * 100 + ru[3] div 10000;     { stime }
    DfSys(DF_GETRUSAGE, -1, Int64(@ru[0]), 0, 0, 0, 0);
    PInt64(buf + 16)^ := ru[0] * 100 + ru[1] div 10000;    { cutime }
    PInt64(buf + 24)^ := ru[2] * 100 + ru[3] div 10000;    { cstime }
  end;
  DfSys(DF_CLOCK_GETTIME, 4, Int64(@ts[0]), 0, 0, 0, 0);
  Result := ts[0] * 100 + ts[1] div 10000000;
end;

{ DragonFly struct statfs (320 B, measured: f_bsize 8, f_blocks 24 ..
  f_ffree 56, f_fsid 64, f_flags 80 (int), f_fstypename 104) -> Linux struct
  statfs (120 B). DragonFly reports no name length: 255. }
function DfStatfs(nr, arg, lx: Int64): Int64;
var fs: array[0..39] of Int64;
    r, fl, ty, i, nm: Int64;
begin
  r := DfSys(nr, arg, Int64(@fs[0]), 0, 0, 0, 0);
  if r < 0 then begin Result := Lx(r); Exit; end;
  for i := 0 to 14 do PInt64(lx + i * 8)^ := 0;
  nm := Int64(@fs[0]) + 104;                                  { f_fstypename }
  ty := 0;
  case PByte(nm)^ of                                          { Linux f_type magics }
    117: ty := $00011954;                                     { ufs }
    104: ty := $5346544E;                                     { hammer, hammer2: no Linux magic; NTFS's is as good as any }
    116: ty := $01021994;                                     { tmpfs }
    109: if PByte(nm + 1)^ = 102 then ty := $01021994         { mfs }
         else ty := $4D44;                                    { msdos }
    110: if PByte(nm + 1)^ = 102 then ty := $6969;            { nfs }
    99:  ty := $9660;                                         { cd9660 }
    112: ty := $9FA0;                                         { procfs }
  end;
  PInt64(lx)^ := ty;
  PInt64(lx + 8)^ := fs[1];                                   { f_bsize }
  for i := 0 to 4 do PInt64(lx + 16 + i * 8)^ := fs[3 + i];   { blocks bfree bavail files ffree }
  PInt64(lx + 56)^ := fs[8];                                  { f_fsid }
  PInt64(lx + 64)^ := 255;                                    { f_namelen }
  PInt64(lx + 72)^ := fs[1];                                  { f_frsize }
  fl := PLongWord(Int64(@fs[0]) + 80)^;
  r := 0;
  if (fl and $1) <> 0 then r := r or 1;                       { ST_RDONLY }
  if (fl and $8) <> 0 then r := r or 2;                       { ST_NOSUID }
  if (fl and $10) <> 0 then r := r or 4;                      { ST_NODEV }
  if (fl and $4) <> 0 then r := r or 8;                       { ST_NOEXEC }
  if (fl and $2) <> 0 then r := r or 16;                      { ST_SYNCHRONOUS }
  if (fl and $10000000) <> 0 then r := r or 1024;             { ST_NOATIME }
  PInt64(lx + 80)^ := r;
  Result := 0;
end;

{ utimensat / futimens. UTIME_NOW/UTIME_OMIT are (1<<30)-1 / (1<<30)-2 on
  Linux, -1 / -2 on DragonFly; a nil path means "the fd itself" on Linux only. }
function DfUtimensat(dirfd, path, times, flags: Int64): Int64;
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
  if path = 0 then Result := Lx(DfSys(DF_FUTIMENS, dirfd, tp, 0, 0, 0, 0))
  else Result := Lx(DfSys(DF_UTIMENSAT, DfDir(dirfd), path, tp, DfAtFlags(flags), 0, 0));
end;

{ fallocate mode 0, as obsdabi does it (posix_fallocate is EINVAL on most
  DragonFly file systems):  the visible part
  of Linux's semantics -- a file that ends short of offset+len grows to it --
  is done with ftruncate. Other modes are EOPNOTSUPP, as on a Linux file
  system without them. }
function DfFallocate(fd, mode, off, len: Int64): Int64;
var sb: array[0..15] of Int64; r: Int64;
begin
  if mode <> 0 then begin Result := -95; Exit; end;
  if (off < 0) or (len <= 0) then begin Result := -LX_EINVAL; Exit; end;
  r := DfSys(DF_FSTAT, fd, Int64(@sb[0]), 0, 0, 0, 0);
  if r < 0 then begin Result := Lx(r); Exit; end;
  if (PWord(Int64(@sb[0]) + 16)^ and $F000) <> $8000 then begin Result := -19; Exit; end;   { not a regular file: ENODEV }
  if off + len > sb[10] then r := DfSys(DF_FTRUNCATE, fd, 0, off + len, 0, 0, 0)
  else r := 0;
  Result := Lx(r);
end;

var
  DfPersona: Int64;                         { personality(2): Linux's default PER_LINUX }

{ prctl: PR_SET_NAME (15) / PR_GET_NAME (16) -> lwp_setname / lwp_getname
  on this thread. Any other option is EINVAL, as an unknown one is on
  Linux. }
function DfPrctl(op, arg: Int64): Int64;
var i: Integer;
begin
  case op of
    15: Result := Lx(DfSys(DF_LWP_SETNAME, DfSys(DF_LWP_GETTID, 0, 0, 0, 0, 0, 0), arg, 0, 0, 0, 0));
    16: begin
          for i := 0 to 15 do PByte(arg + i)^ := 0;
          Result := Lx(DfSys(DF_LWP_GETNAME, DfSys(DF_LWP_GETTID, 0, 0, 0, 0, 0, 0), arg, 16, 0, 0, 0));
        end;
  else
    Result := -LX_EINVAL;
  end;
end;

{ sched_getaffinity: every CPU (hw.ncpu), as an unrestricted Linux process
  sees. }
function DfGetAffinity(len, mask: Int64): Int64;
var mib: array[0..1] of Integer; n, sz, i: Int64; nc: Integer;
begin
  if len < 8 then begin Result := -LX_EINVAL; Exit; end;
  if len > 128 then len := 128;
  mib[0] := 6; mib[1] := 3;                                   { hw.ncpu }
  nc := 1; sz := 4;
  if DfSys(DF_SYSCTL, Int64(@mib[0]), 2, Int64(@nc), Int64(@sz), 0, 0) < 0 then nc := 1;
  for i := 0 to len - 1 do PByte(mask + i)^ := 0;
  n := nc;
  if n > len * 8 then n := len * 8;
  for i := 0 to n - 1 do
    PByte(mask + i div 8)^ := PByte(mask + i div 8)^ or (1 shl (i mod 8));
  Result := len;
end;

{ readlink("/proc/self/fd/N"). DragonFly keeps no path for an open file, but
  a DIRECTORY's can be had: fchdir into it, getcwd, and fchdir back to a saved
  "." -- which is what crtl's fchdir and similar fd-to-path users need. Any
  other fd is ENOENT, as for a deleted file on Linux. -4096 = not that path. }
function DfProcFdLink(path, buf, cap: Int64): Int64;
var i, fd, here, r, n: Int64; tmp: array[0..1023] of Byte;
const Pre: array[0..13] of Byte = (47,112,114,111,99,47,115,101,108,102,47,102,100,47);   { /proc/self/fd/ }
      Dot: array[0..1] of Byte = (46, 0);
begin
  Result := -4096;
  if path = 0 then Exit;
  for i := 0 to 13 do
    if PByte(path + i)^ <> Pre[i] then Exit;
  fd := 0; i := 14;
  if (PByte(path + i)^ < 48) or (PByte(path + i)^ > 57) then Exit;
  while (PByte(path + i)^ >= 48) and (PByte(path + i)^ <= 57) do
  begin
    fd := fd * 10 + PByte(path + i)^ - 48; i := i + 1;
  end;
  if PByte(path + i)^ <> 0 then Exit;
  here := DfSys(DF_OPENAT, DF_AT_FDCWD, Int64(@Dot[0]), $8000000 or $20000, 0, 0, 0);   { O_DIRECTORY|O_CLOEXEC }
  if here < 0 then begin Result := Lx(here); Exit; end;
  r := DfSys(DF_FCHDIR, fd, 0, 0, 0, 0, 0);
  if r < 0 then
  begin
    DfSys(DF_CLOSE, here, 0, 0, 0, 0, 0);
    if r = -9 then Result := -9 else Result := -LX_ENOENT;    { EBADF stays EBADF }
    Exit;
  end;
  r := DfSys(DF_GETCWD, Int64(@tmp[0]), 1024, 0, 0, 0, 0);
  DfSys(DF_FCHDIR, here, 0, 0, 0, 0, 0);
  DfSys(DF_CLOSE, here, 0, 0, 0, 0, 0);
  if r < 0 then begin Result := Lx(r); Exit; end;
  n := StrLen0(Int64(@tmp[0]));
  if n > cap then n := cap;
  for i := 0 to n - 1 do PByte(buf + i)^ := tmp[i];
  Result := n;
end;

{ ---- ptys ----------------------------------------------------------------
  Linux: open /dev/ptmx, TIOCGPTN gives N, the slave is /dev/pts/N.
  DragonFly has the same files (opening /dev/ptmx makes /dev/pts/N), so opens
  pass through; N comes from the master's device name, "ptm/N", which
  FIODNAME (_IOW('f', 120, struct fiodname_args {name, len})) answers. There
  is no slave lock: TIOCSPTLCK only checks that the fd is a master. }
const
  DevPtmx: array[0..8] of Byte = (47,100,101,118,47,112,116,109,120);   { /dev/ptmx }

{ The pty number of a master fd, or -ENOTTY for anything else. }
function DfPtyMinor(fd: Int64): Int64;
var nm: array[0..63] of Byte; a: array[0..1] of Int64; r, i, n: Int64;
begin
  for i := 0 to 63 do nm[i] := 0;
  a[0] := Int64(@nm[0]); a[1] := 63;
  r := DfSys(DF_IOCTL, fd, $80106678, Int64(@a[0]), 0, 0, 0);              { FIODNAME }
  if (r < 0) or (nm[0] <> 112) or (nm[1] <> 116) or (nm[2] <> 109) or (nm[3] <> 47) then
  begin Result := -LX_ENOTTY; Exit; end;                                    { not "ptm/" }
  n := 0; i := 4;
  if (nm[i] < 48) or (nm[i] > 57) then begin Result := -LX_ENOTTY; Exit; end;
  while (i < 63) and (nm[i] >= 48) and (nm[i] <= 57) do
  begin
    n := n * 10 + nm[i] - 48; i := i + 1;
  end;
  Result := n;
end;

{ open/openat with the paths DragonFly lacks. /dev/full is /dev/zero whose
  writes fail with ENOSPC (bit 3 of DfTfd marks the fd). }
function DfOpenAt(dirfd, path, flags, mode: Int64): Int64;
begin
  if PathIs(path, ProcEnviron) then Result := DfProcEnviron
  else if PathIs(path, ProcHostname) then Result := DfProcHostname
  else if PathIs(path, DevFull) then
  begin
    Result := Lx(DfSys(DF_OPENAT, DF_AT_FDCWD, Int64(@DevZero[0]), DfOpenFlags(flags) and not Int64($E00), 0, 0, 0));
    if (Result >= 0) and (Result < DF_TFD_MAX) then DfTfd[Integer(Result)] := 8;
  end
  else
  begin
    Result := Lx(DfSys(DF_OPENAT, DfDir(dirfd), path, DfOpenFlags(flags), mode, 0, 0));
    if (Result = -31) and ((flags and $20000) <> 0) then Result := -40;  { O_NOFOLLOW on a symlink: EMLINK -> ELOOP }
  end;
end;

{ faccessat with DragonFly flags already. DragonFly lets root pass X_OK on a
  file with no execute bit at all (POSIX allows it); Linux refuses, so a
  successful X_OK check on a non-directory with no x bit answers EACCES. }
function DfAccess(dirfd, path, mode, flags: Int64): Int64;
var sb: array[0..15] of Int64; m: Int64;
begin
  Result := DfSys(DF_FACCESSAT, DfDir(dirfd), path, mode, flags, 0, 0);
  if (Result = 0) and ((mode and 1) <> 0) then
    if DfSys(DF_FSTATAT, DfDir(dirfd), path, Int64(@sb[0]), flags and DF_AT_SYMLINK_NOFOLLOW, 0, 0) = 0 then
    begin
      m := PWord(Int64(@sb[0]) + 16)^;
      if ((m and $F000) <> $4000) and ((m and $49) = 0) then Result := -13;   { EACCES }
    end;
  Result := Lx(Result);
end;

{ read(2). A directory answers EINVAL (or 0 for a 0-byte read) on DragonFly,
  EISDIR on Linux -- NilPy's open() tells a directory by exactly that. }
function DfRead(fd, buf, n: Int64): Int64;
var sb: array[0..15] of Int64;
begin
  Result := DfSys(DF_READ, fd, buf, n, 0, 0, 0);
  if ((Result = -22) or ((Result = 0) and (n = 0)))
     and (DfSys(DF_FSTAT, fd, Int64(@sb[0]), 0, 0, 0, 0) = 0)
     and ((PWord(Int64(@sb[0]) + 16)^ and $F000) = $4000) then Result := -21;
  Result := Lx(Result);
end;

{ TCGETS / TCSETS* on a pty MASTER: Linux's master is a tty that shares the
  slave's termios; DragonFly's master answers ENOTTY. The slave (/dev/pts/N,
  opened O_NOCTTY for the call) answers instead. -4096 = not a master. }
function DfMasterTermios(fd, req, arg: Int64): Int64;
var nm: array[0..23] of Byte; n, k, i, s: Int64; d: array[0..19] of Byte;
const Pts: array[0..8] of Byte = (47,100,101,118,47,112,116,115,47);   { /dev/pts/ }
begin
  Result := -4096;
  n := DfPtyMinor(fd);
  if n < 0 then Exit;
  for i := 0 to 8 do nm[i] := Pts[i];
  k := 0;
  repeat d[k] := 48 + (n mod 10); n := n div 10; k := k + 1; until n = 0;
  for i := 0 to k - 1 do nm[9 + i] := d[k - 1 - i];
  nm[9 + k] := 0;
  s := DfSys(DF_OPENAT, DF_AT_FDCWD, Int64(@nm[0]), 2 or $8000 or $20000, 0, 0, 0);   { O_RDWR|O_NOCTTY|O_CLOEXEC }
  if s < 0 then Exit;
  Result := DfSys(DF_IOCTL, s, req, arg, 0, 0, 0);
  DfSys(DF_CLOSE, s, 0, 0, 0, 0, 0);
end;

{ ---- the dispatcher ------------------------------------------------------- }

function PXXDfbsdSyscall(nr, a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl;
var sb: array[0..15] of Int64; t: array[0..3] of Int64; r, f, i, n: Int64;
begin
  case nr of
    0: if DfIsTfd(a0) then Result := DfTimerfdRead(a0, a1, a2)
       else Result := DfRead(a0, a1, a2);
    1: if (a0 >= 0) and (a0 < DF_TFD_MAX) and ((DfTfd[Integer(a0)] and 8) <> 0) and (a2 > 0) then
         Result := -28                                          { /dev/full: ENOSPC }
       else Result := Lx(DfSys(DF_WRITE, a0, a1, a2, 0, 0, 0));
    2: Result := DfOpenAt(DF_AT_FDCWD, a0, a1, a2);
    257: Result := DfOpenAt(a0, a1, a2, a3);
    3: begin
         if (a0 >= 0) and (a0 < DF_TFD_MAX) then DfTfd[Integer(a0)] := 0;
         Result := Lx(DfSys(DF_CLOSE, a0, 0, 0, 0, 0, 0));
       end;
    4: Result := DfStatAt(DF_AT_FDCWD, a0, a1, 0);              { stat }
    5: begin                                                    { fstat }
         r := DfSys(DF_FSTAT, a0, Int64(@sb[0]), 0, 0, 0, 0);
         if r = 0 then StatToLinux(@sb[0], Pointer(a1));
         Result := Lx(r);
       end;
    6: Result := DfStatAt(DF_AT_FDCWD, a0, a1, $100);           { lstat }
    262: Result := DfStatAt(a0, a1, a2, a3);                    { newfstatat }
    332: begin                                                  { statx }
           if ((a2 and $1000) <> 0) and ((a1 = 0) or (PByte(a1)^ = 0)) then
             r := DfSys(DF_FSTAT, a0, Int64(@sb[0]), 0, 0, 0, 0)
           else
             r := DfSys(DF_FSTATAT, DfDir(a0), a1, Int64(@sb[0]), DfAtFlags(a2), 0, 0);
           if r = 0 then StatToStatx(@sb[0], Pointer(a4));
           Result := Lx(r);
         end;
    7: Result := Lx(DfSys(DF_POLL, a0, a1, a2, 0, 0, 0));       { POLLIN..POLLNVAL bits are the same }
    8: Result := Lx(DfSys(DF_LSEEK, a0, 0, a1, a2, 0, 0));      { lseek(fd, pad, off, whence) }
    9: Result := Lx(DfMmap(a0, a1, a2, DfMmapFlags(a3), a4, a5));
    10: Result := Lx(DfSys(DF_MPROTECT, a0, a1, a2, 0, 0, 0));
    11: Result := Lx(DfSys(DF_MUNMAP, a0, a1, 0, 0, 0, 0));
    12: Result := DfBrk(a0);
    16: case Integer(a1) of                                              { ioctl }
          $5401: begin                                          { TCGETS -> TIOCGETA }
                   r := DfSys(DF_IOCTL, a0, $402C7413, Int64(@sb[0]), 0, 0, 0);
                   if (r = -25) or (r = -35) then                { a master: ENOTTY, or EAGAIN before a slave is open }
                   begin
                     r := DfMasterTermios(a0, $402C7413, Int64(@sb[0]));
                     if r = -4096 then r := -25;
                   end;
                   if r = -19 then r := -25;                     { ENODEV (/dev/null) -> ENOTTY }
                   if (r = 0) and (a2 <> 0) then TermiosToLx(Int64(@sb[0]), a2);
                   Result := Lx(r);
                 end;
          $5402, $5403, $5404: begin                            { TCSETS/W/F -> TIOCSETA/W/F }
                   TermiosToDf(a2, Int64(@sb[0]));
                   r := DfSys(DF_IOCTL, a0, $802C7414 + (a1 - $5402), Int64(@sb[0]), 0, 0, 0);
                   if (r = -25) or (r = -35) then
                   begin
                     r := DfMasterTermios(a0, $802C7414 + (a1 - $5402), Int64(@sb[0]));
                     if r = -4096 then r := -25;
                   end;
                   if r = -19 then r := -25;
                   Result := Lx(r);
                 end;
          $540B: begin                                          { TCFLSH -> TIOCFLUSH(FREAD/FWRITE) }
                   if (a2 < 0) or (a2 > 2) then Result := -LX_EINVAL
                   else
                   begin
                     t[0] := a2 + 1;
                     Result := Lx(DfSys(DF_IOCTL, a0, $80047410, Int64(@t[0]), 0, 0, 0));
                   end;
                 end;
          $5409: if a2 <> 0 then Result := Lx(DfSys(DF_IOCTL, a0, $2000745E, 0, 0, 0, 0))  { TCSBRK: drain }
                 else Result := 0;                              { (the 0.25 s break is not sent) }
          $540A: case Integer(a2) of                            { TCXONC }
                   0: Result := Lx(DfSys(DF_IOCTL, a0, $2000746F, 0, 0, 0, 0));   { TCOOFF -> TIOCSTOP }
                   1: Result := Lx(DfSys(DF_IOCTL, a0, $2000746E, 0, 0, 0, 0));   { TCOON -> TIOCSTART }
                 else Result := 0;
                 end;
          $5427: Result := Lx(DfSys(DF_IOCTL, a0, $2000747B, 0, 0, 0, 0));   { TIOCSBRK }
          -2147199952: begin                                    { $80045430 TIOCGPTN (the case is on Integer) }
                   r := DfPtyMinor(a0);
                   if r >= 0 then begin PInteger(a2)^ := Integer(r); Result := 0; end
                   else Result := r;
                 end;
          $40045431: begin                                      { TIOCSPTLCK: DragonFly ptys have no lock }
                   r := DfPtyMinor(a0);
                   if r >= 0 then Result := 0 else Result := r;
                 end;
          $5428: Result := Lx(DfSys(DF_IOCTL, a0, $2000747A, 0, 0, 0, 0));   { TIOCCBRK }
          $5413: Result := Lx(DfSys(DF_IOCTL, a0, $40087468, a2, 0, 0, 0));  { TIOCGWINSZ }
          $541B: Result := Lx(DfSys(DF_IOCTL, a0, $4004667F, a2, 0, 0, 0));  { FIONREAD }
          $540E: Result := Lx(DfSys(DF_IOCTL, a0, $20007461, 0, 0, 0, 0));   { TIOCSCTTY }
          $540F, $5410: begin                                   { TIOCGPGRP / TIOCSPGRP }
                   { tty only: BSD pipes and sockets also accept these
                     (as the SIGIO owner), Linux answers ENOTTY }
                   r := DfSys(DF_IOCTL, a0, $402C7413, Int64(@sb[0]), 0, 0, 0);
                   if r = -25 then Result := -LX_ENOTTY
                   else if r < 0 then Result := Lx(r)
                   else if a1 = $540F then Result := Lx(DfSys(DF_IOCTL, a0, $40047477, a2, 0, 0, 0))
                   else Result := Lx(DfSys(DF_IOCTL, a0, $80047476, a2, 0, 0, 0));
                 end;
          $5411: Result := Lx(DfSys(DF_IOCTL, a0, $40047473, a2, 0, 0, 0));  { TIOCOUTQ }
          $5414: Result := Lx(DfSys(DF_IOCTL, a0, $80087467, a2, 0, 0, 0));  { TIOCSWINSZ }
          $5421: Result := Lx(DfSys(DF_IOCTL, a0, $8004667E, a2, 0, 0, 0));  { FIONBIO }
          $5422: Result := Lx(DfSys(DF_IOCTL, a0, $20007471, 0, 0, 0, 0));   { TIOCNOTTY }
          $5429: Result := Lx(DfSys(DF_IOCTL, a0, $40047463, a2, 0, 0, 0));  { TIOCGSID }
          $5450: Result := Lx(DfSys(DF_IOCTL, a0, $20006602, 0, 0, 0, 0));   { FIONCLEX }
          $5451: Result := Lx(DfSys(DF_IOCTL, a0, $20006601, 0, 0, 0, 0));   { FIOCLEX }
          $5452: Result := Lx(DfSys(DF_IOCTL, a0, $8004667D, a2, 0, 0, 0));  { FIOASYNC }
        else
          { unmapped: a bad fd is still EBADF, as the kernel would say first }
          if DfSys(DF_FCNTL, a0, 1, 0, 0, 0, 0) < 0 then Result := -9
          else Result := -LX_ENOTTY;
        end;
    17: Result := Lx(DfSys(DF_EXTPREAD, a0, a1, a2, 0, a3, 0));
    18: Result := Lx(DfSys(DF_EXTPWRITE, a0, a1, a2, 0, a3, 0));
    19: Result := Lx(DfSys(DF_READV, a0, a1, a2, 0, 0, 0));
    20: Result := Lx(DfSys(DF_WRITEV, a0, a1, a2, 0, 0, 0));
    21: Result := DfAccess(-100, a0, a1, 0);
    269, 439: begin                                             { faccessat, faccessat2 }
           f := 0;
           if (a3 and $200) <> 0 then f := f or DF_AT_EACCESS;
           if (a3 and $100) <> 0 then f := f or DF_AT_SYMLINK_NOFOLLOW;
           Result := DfAccess(a0, a1, a2, f);
         end;
    22: Result := Lx(DfPipe2(a0, 0));
    293: Result := Lx(DfPipe2(a0, DfOpenFlags(a1) and ($20000 or $4)));
    23: Result := Lx(DfSys(DF_SELECT, a0, a1, a2, a3, a4, 0));
    24: Result := Lx(DfSys(DF_SCHED_YIELD, 0, 0, 0, 0, 0, 0));
    28: Result := Lx(DfSys(DF_MADVISE, a0, a1, a2, 0, 0, 0));
    32: Result := Lx(DfSys(DF_DUP, a0, 0, 0, 0, 0, 0));
    33: Result := Lx(DfSys(DF_DUP2, a0, a1, 0, 0, 0, 0));
    292: if a0 = a1 then Result := -LX_EINVAL                   { dup3 -> fcntl(F_DUP2FD[_CLOEXEC]) }
         else if (a2 and $80000) <> 0 then Result := Lx(DfSys(DF_FCNTL, a0, DF_F_DUP2FD_CLOEXEC, a1, 0, 0, 0))
         else Result := Lx(DfSys(DF_FCNTL, a0, DF_F_DUP2FD, a1, 0, 0, 0));
    35: Result := Lx(DfSys(DF_NANOSLEEP, a0, a1, 0, 0, 0, 0));
    39: Result := DfSys(DF_GETPID, 0, 0, 0, 0, 0, 0);
    186: Result := DfGettid;                                                { gettid }
    57, 58: begin                                               { fork, vfork }
              r := DfSys(DF_FORK, 0, 0, 0, 0, 0, 0);
              if (r >= 0) and (DfRdx <> 0) then r := 0;        { the child: rdx = 1 }
              Result := Lx(r);
            end;
    59: Result := Lx(DfSys(DF_EXECVE, a0, a1, a2, 0, 0, 0));
    60: begin DfExitThread(a0); Result := 0; end;
    231: begin DfSys(DF_EXIT, a0, 0, 0, 0, 0, 0); Result := 0; end;
    56: Result := DfClone(a0, a1, a2, a3, a5);
    202: Result := DfFutex(a0, a1, a2, a3, a4, a5);
    61: Result := DfWait4(a0, a1, a2, a3);
    62: begin
          f := DfSig(a1);
          if (f = 0) and (a1 <> 0) then Result := -LX_EINVAL
          else Result := Lx(DfSys(DF_KILL, a0, f, 0, 0, 0, 0));
        end;
    63: Result := DfUname(a0);
    72: begin                                                   { fcntl }
          case a1 of
            0, 1, 2: Result := Lx(DfSys(DF_FCNTL, a0, a1, a2, 0, 0, 0));
            3: begin
                 r := DfSys(DF_FCNTL, a0, 3, 0, 0, 0, 0);
                 if r < 0 then Result := Lx(r) else Result := LxOpenFlags(r);
               end;
            4: Result := Lx(DfSys(DF_FCNTL, a0, 4, DfOpenFlags(a2), 0, 0, 0));
            1030: Result := Lx(DfSys(DF_FCNTL, a0, 10, a2, 0, 0, 0));   { F_DUPFD_CLOEXEC }
          else
            Result := -LX_EINVAL;
          end;
        end;
    73: Result := Lx(DfSys(DF_FLOCK, a0, a1, 0, 0, 0, 0));
    74, 75: Result := Lx(DfSys(DF_FSYNC, a0, 0, 0, 0, 0, 0));
    76: Result := Lx(DfSys(DF_TRUNCATE, a0, 0, a1, 0, 0, 0));     { (path, pad, length) }
    77: Result := Lx(DfSys(DF_FTRUNCATE, a0, 0, a1, 0, 0, 0));
    217: begin                                                  { getdents64 }
           Result := DfGetdents(a0, a1, a2);
         end;
    79: begin                                                   { getcwd: Linux returns the length with the NUL }
          r := DfSys(DF_GETCWD, a0, a1, 0, 0, 0, 0);
          if r < 0 then Result := Lx(r) else Result := StrLen0(a0) + 1;
        end;
    80: Result := Lx(DfSys(DF_CHDIR, a0, 0, 0, 0, 0, 0));
    81: Result := Lx(DfSys(DF_FCHDIR, a0, 0, 0, 0, 0, 0));
    82: Result := Lx(DfSys(DF_RENAME, a0, a1, 0, 0, 0, 0));
    264: Result := Lx(DfSys(DF_RENAMEAT, DfDir(a0), a1, DfDir(a2), a3, 0, 0));
    316: if a4 <> 0 then Result := -LX_EINVAL
         else Result := Lx(DfSys(DF_RENAMEAT, DfDir(a0), a1, DfDir(a2), a3, 0, 0));
    83: Result := Lx(DfSys(DF_MKDIR, a0, a1, 0, 0, 0, 0));
    258: Result := Lx(DfSys(DF_MKDIRAT, DfDir(a0), a1, a2, 0, 0, 0));
    84: Result := Lx(DfSys(DF_RMDIR, a0, 0, 0, 0, 0, 0));
    86: Result := Lx(DfSys(DF_LINK, a0, a1, 0, 0, 0, 0));
    265: Result := Lx(DfSys(DF_LINKAT, DfDir(a0), a1, DfDir(a2), a3, DfAtFlags(a4), 0));
    87: Result := Lx(DfSys(DF_UNLINK, a0, 0, 0, 0, 0, 0));
    263: begin                                                  { unlinkat }
           f := 0;
           if (a2 and $200) <> 0 then f := DF_AT_REMOVEDIR;
           Result := Lx(DfSys(DF_UNLINKAT, DfDir(a0), a1, f, 0, 0, 0));
         end;
    88: Result := Lx(DfSys(DF_SYMLINK, a0, a1, 0, 0, 0, 0));
    266: Result := Lx(DfSys(DF_SYMLINKAT, a0, DfDir(a1), a2, 0, 0, 0));
    89: if PathIs(a0, ProcExe) then Result := DfProcExe(a1, a2)
        else begin
          Result := DfProcFdLink(a0, a1, a2);
          if Result = -4096 then Result := Lx(DfSys(DF_READLINK, a0, a1, a2, 0, 0, 0));
        end;
    267: if PathIs(a1, ProcExe) then Result := DfProcExe(a2, a3)
         else begin
           Result := DfProcFdLink(a1, a2, a3);
           if Result = -4096 then Result := Lx(DfSys(DF_READLINKAT, DfDir(a0), a1, a2, a3, 0, 0));
         end;
    90: Result := Lx(DfSys(DF_CHMOD, a0, a1, 0, 0, 0, 0));
    91: Result := Lx(DfSys(DF_FCHMOD, a0, a1, 0, 0, 0, 0));
    268: Result := Lx(DfSys(DF_FCHMODAT, DfDir(a0), a1, a2, 0, 0, 0));
    92: Result := Lx(DfSys(DF_CHOWN, a0, a1, a2, 0, 0, 0));
    93: Result := Lx(DfSys(DF_FCHOWN, a0, a1, a2, 0, 0, 0));
    94: Result := Lx(DfSys(DF_LCHOWN, a0, a1, a2, 0, 0, 0));
    260: Result := Lx(DfSys(DF_FCHOWNAT, DfDir(a0), a1, a2, a3, DfAtFlags(a4), 0));
    95: Result := DfSys(DF_UMASK, a0, 0, 0, 0, 0, 0);
    96: Result := Lx(DfSys(DF_GETTIMEOFDAY, a0, a1, 0, 0, 0, 0));
    97: Result := DfGetRlimit(a0, a1);
    160: Result := DfSetRlimit(a0, a1);
    302: begin                                                  { prlimit64(0, res, new, old) }
           if (a0 <> 0) and (a0 <> DfSys(DF_GETPID, 0, 0, 0, 0, 0, 0)) then
             Result := -LX_EINVAL
           else
           begin
             Result := 0;
             if a3 <> 0 then Result := DfGetRlimit(a1, a3);
             if (Result = 0) and (a2 <> 0) then Result := DfSetRlimit(a1, a2);
           end;
         end;
    98: Result := Lx(DfSys(DF_GETRUSAGE, a0, a1, 0, 0, 0, 0));  { struct rusage: same 144 B }
    102: Result := DfSys(DF_GETUID, 0, 0, 0, 0, 0, 0);
    104: Result := DfSys(DF_GETGID, 0, 0, 0, 0, 0, 0);
    107: Result := DfSys(DF_GETEUID, 0, 0, 0, 0, 0, 0);
    108: Result := DfSys(DF_GETEGID, 0, 0, 0, 0, 0, 0);
    105: Result := Lx(DfSys(DF_SETUID, a0, 0, 0, 0, 0, 0));
    106: Result := Lx(DfSys(DF_SETGID, a0, 0, 0, 0, 0, 0));
    109: Result := Lx(DfSys(DF_SETPGID, a0, a1, 0, 0, 0, 0));
    110: Result := DfSys(DF_GETPPID, 0, 0, 0, 0, 0, 0);
    111: Result := DfSys(DF_GETPGRP, 0, 0, 0, 0, 0, 0);
    112: Result := Lx(DfSys(DF_SETSID, 0, 0, 0, 0, 0, 0));
    121: Result := Lx(DfSys(DF_GETPGID, a0, 0, 0, 0, 0, 0));
    124: Result := Lx(DfSys(DF_GETSID, a0, 0, 0, 0, 0, 0));
    140: begin                                                  { getpriority: Linux returns 20 - nice }
           r := DfSys(DF_GETPRIORITY, a0, a1, 0, 0, 0, 0);
           if (r < 0) and (r >= -95) and (r <> -1) then Result := Lx(r)
           else Result := 20 - r;
         end;
    141: Result := Lx(DfSys(DF_SETPRIORITY, a0, a1, a2, 0, 0, 0));
    158: begin                                                  { arch_prctl }
           case a0 of
             $1001, $1002: begin                                { SET_GS / SET_FS: set_tls_area(1 / 0) }
                             t[0] := a1; t[1] := -1;                { tls_info: base, size (-1: no limit) }
                             Result := Lx(DfSys(DF_SET_TLS_AREA, Ord(a0 = $1001), Int64(@t[0]), 16, 0, 0, 0));
                           end;
             $1003, $1004: begin                                { GET_FS / GET_GS }
                             t[0] := 0; t[1] := 0;
                             r := DfSys(DF_GET_TLS_AREA, Ord(a0 = $1004), Int64(@t[0]), 16, 0, 0, 0);
                             if r >= 0 then PInt64(a1)^ := t[0];
                             Result := Lx(r);
                           end;
           else
             Result := -LX_EINVAL;
           end;
         end;
    201: begin                                                  { time }
           r := DfSys(DF_CLOCK_GETTIME, 0, Int64(@t[0]), 0, 0, 0, 0);
           if r < 0 then Result := Lx(r)
           else begin
             if a0 <> 0 then PInt64(a0)^ := t[0];
             Result := t[0];
           end;
         end;
    228: Result := Lx(DfSys(DF_CLOCK_GETTIME, DfClock(a0), a1, 0, 0, 0, 0));
    229: Result := Lx(DfSys(DF_CLOCK_GETRES, DfClock(a0), a1, 0, 0, 0, 0));
    230: if a1 = 0 then                                         { clock_nanosleep, relative }
           Result := Lx(DfSys(DF_NANOSLEEP, a2, a3, 0, 0, 0, 0))
         else
           Result := -LX_EINVAL;                                { TIMER_ABSTIME: not yet }
    280: Result := DfUtimensat(a0, a1, a2, a3);
    295: Result := Lx(DfSys(DF_EXTPREADV, a0, a1, a2, 0, a3, 0));
    296: Result := Lx(DfSys(DF_EXTPWRITEV, a0, a1, a2, 0, a3, 0));
    318: Result := Lx(DfSys(DF_GETRANDOM, a0, a1, 0, 0, 0, 0));  { getrandom; flags: urandom never blocks once seeded }
    41: begin                                                   { socket }
          { Linux's check order (__sys_socket[pair], __sock_create): stray
            flag bits in the type word, then the family, then the type. }
          f := DfAf(a0);
          if (a1 and not Int64($8080F)) <> 0 then Result := -LX_EINVAL   { type 0..15, SOCK_CLOEXEC $80000, SOCK_NONBLOCK $800 }
          else if f < 0 then Result := -LX_EAFNOSUPPORT
          else if (a1 and $F) >= 11 then Result := -LX_EINVAL            { SOCK_MAX = 11 }
          else Result := Lx(DfSys(DF_SOCKET, f, DfSockType(a1), a2, 0, 0, 0));
        end;
    42: Result := DfSockAddrCall(DF_CONNECT, a0, a1, a2);
    43: Result := DfSockAddrOut(DF_ACCEPT4, a0, a1, a2, 0);
    288: Result := DfSockAddrOut(DF_ACCEPT4, a0, a1, a2, a3);
    44: Result := DfSendto(a0, a1, a2, a3, a4, a5);
    45: Result := DfRecvfrom(a0, a1, a2, a3, a4, a5);
    46: Result := DfMsg(True, a0, a1, a2);
    47: Result := DfMsg(False, a0, a1, a2);
    48: Result := Lx(DfSys(DF_SHUTDOWN, a0, a1, 0, 0, 0, 0));
    49: Result := DfSockAddrCall(DF_BIND, a0, a1, a2);
    50: Result := Lx(DfSys(DF_LISTEN, a0, a1, 0, 0, 0, 0));
    51: Result := DfSockAddrOut(DF_GETSOCKNAME, a0, a1, a2, 0);
    52: Result := DfSockAddrOut(DF_GETPEERNAME, a0, a1, a2, 0);
    53: begin                                                   { socketpair }
          { Linux's check order (__sys_socket[pair], __sock_create): stray
            flag bits in the type word, then the family, then the type. }
          f := DfAf(a0);
          if (a1 and not Int64($8080F)) <> 0 then Result := -LX_EINVAL   { type 0..15, SOCK_CLOEXEC $80000, SOCK_NONBLOCK $800 }
          else if f < 0 then Result := -LX_EAFNOSUPPORT
          else if (a1 and $F) >= 11 then Result := -LX_EINVAL            { SOCK_MAX = 11 }
          else Result := Lx(DfSys(DF_SOCKETPAIR, f, DfSockType(a1), a2, a3, 0, 0));
        end;
    54: Result := DfSockopt(False, a0, a1, a2, a3, a4);
    55: Result := DfSockopt(True, a0, a1, a2, a3, a4);
    271: begin                                                  { ppoll }
           if a3 <> 0 then
           begin
             MaskToDf(PInt64(a3)^, Int64(@t[0]));
             Result := Lx(DfSys(DF_PPOLL, a0, a1, a2, Int64(@t[0]), 0, 0));
           end
           else Result := Lx(DfSys(DF_PPOLL, a0, a1, a2, 0, 0, 0));
         end;
    270: begin                                                  { pselect6: a5 -> {sigset *, size} }
           if (a5 <> 0) and (PInt64(a5)^ <> 0) then
           begin
             MaskToDf(PInt64(PInt64(a5)^)^, Int64(@t[0]));
             Result := Lx(DfSys(DF_PSELECT, a0, a1, a2, a3, a4, Int64(@t[0])));
           end
           else Result := Lx(DfSys(DF_PSELECT, a0, a1, a2, a3, a4, 0));
         end;
    213, 291: begin                                             { epoll_create, epoll_create1 }
                r := DfSys(DF_KQUEUE, 0, 0, 0, 0, 0, 0);
                if (r >= 0) and (nr = 291) and ((a0 and $80000) <> 0) then
                  DfSys(DF_FCNTL, r, 2, 1, 0, 0, 0);            { F_SETFD FD_CLOEXEC }
                Result := Lx(r);
              end;
    233: Result := DfEpollCtl(a0, a1, a2, a3);
    232, 281: Result := DfEpollWait(a0, a1, a2, a3);            { epoll_pwait: mask not applied }
    283: Result := DfTimerfdCreate(a0, a1);
    286: Result := DfTimerfdSettime(a0, a1, a2, a3);
    287: if DfIsTfd(a0) then                                    { timerfd_gettime: disarmed }
         begin
           for i := 0 to 3 do PInt64(a1 + i * 8)^ := 0;
           Result := 0;
         end
         else Result := -LX_EINVAL;
    128: Result := DfRtSigtimedwait(a0, a1, a2);
    100: Result := DfTimes(a0);
    137: Result := DfStatfs(DF_STATFS, a0, a1);
    138: Result := DfStatfs(DF_FSTATFS, a0, a1);
    113: Result := Lx(DfSys(DF_SETREUID, a0, a1, 0, 0, 0, 0));
    114: Result := Lx(DfSys(DF_SETREGID, a0, a1, 0, 0, 0, 0));
    115: Result := Lx(DfSys(DF_GETGROUPS, a0, a1, 0, 0, 0, 0));
    116: Result := Lx(DfSys(DF_SETGROUPS, a0, a1, 0, 0, 0, 0));
    117: Result := Lx(DfSys(DF_SETRESUID, a0, a1, a2, 0, 0, 0));
    118: Result := Lx(DfSys(DF_GETRESUID, a0, a1, a2, 0, 0, 0));
    119: Result := Lx(DfSys(DF_SETRESGID, a0, a1, a2, 0, 0, 0));
    120: Result := Lx(DfSys(DF_GETRESGID, a0, a1, a2, 0, 0, 0));
    133: Result := Lx(DfSys(DF_MKNOD, a0, a1, a2, 0, 0, 0));      { dev_t: same encoding for small numbers }
    259: Result := Lx(DfSys(DF_MKNODAT, DfDir(a0), a1, a2, a3, 0, 0));
    135: begin                                                  { personality }
           Result := DfPersona;
           if a0 <> $FFFFFFFF then DfPersona := a0 and $FFFFFFFF;
         end;
    { sched_*: OpenBSD has no POSIX scheduling policies. Answer as Linux does
      for a SCHED_OTHER process, the only kind there is here: priority 0,
      and FIFO/RR refused as for a process without CAP_SYS_NICE. }
    142: if (a1 = 0) or (PInteger(a1)^ <> 0) then Result := -LX_EINVAL else Result := 0;
    143: if a1 = 0 then Result := -LX_EINVAL
         else begin PInteger(a1)^ := 0; Result := 0; end;
    144: case a1 and $3FFFFFFF of
           0, 3, 5: if (a2 = 0) or (PInteger(a2)^ <> 0) then Result := -LX_EINVAL else Result := 0;
           1, 2: Result := -1;                                  { EPERM }
         else Result := -LX_EINVAL;
         end;
    145: Result := 0;                                           { SCHED_OTHER }
    146: case a0 of 1, 2: Result := 99; 0, 3, 5: Result := 0; else Result := -LX_EINVAL; end;
    147: case a0 of 1, 2: Result := 1; 0, 3, 5: Result := 0; else Result := -LX_EINVAL; end;
    148: begin PInt64(a1)^ := 0; PInt64(a1 + 8)^ := 100000000; Result := 0; end;
    203: Result := 0;                                           { sched_setaffinity: nothing to restrict }
    204: Result := DfGetAffinity(a1, a2);
    149: Result := Lx(DfSys(DF_MLOCK, a0, a1, 0, 0, 0, 0));
    150: Result := Lx(DfSys(DF_MUNLOCK, a0, a1, 0, 0, 0, 0));
    151: Result := Lx(DfSys(DF_MLOCKALL, a0 and 3, 0, 0, 0, 0, 0));   { MCL_CURRENT/FUTURE agree }
    152: Result := Lx(DfSys(DF_MUNLOCKALL, 0, 0, 0, 0, 0, 0));
    157: Result := DfPrctl(a0, a1);
    162: begin DfSys(DF_SYNC, 0, 0, 0, 0, 0, 0); Result := 0; end;
    218: Result := DfGettid;                                               { set_tid_address: the tid }
    227: Result := Lx(DfSys(DF_CLOCK_SETTIME, DfClock(a0), a1, 0, 0, 0, 0));
    235: Result := Lx(DfSys(DF_UTIMES, a0, a1, 0, 0, 0, 0));
    272: if a0 = 0 then Result := 0 else Result := -LX_EINVAL;  { unshare: nothing to unshare succeeds on Linux too }
    285: Result := DfFallocate(a0, a1, a2, a3);
    13: Result := DfRtSigaction(a0, a1, a2);
    14: Result := DfRtSigprocmask(a0, a1, a2);
    127: begin                                                  { rt_sigpending }
           t[0] := 0; t[1] := 0;
           r := DfSys(DF_SIGPENDING, Int64(@t[0]), 0, 0, 0, 0, 0);
           if r < 0 then Result := Lx(r)
           else begin PInt64(a0)^ := MaskToLx(Int64(@t[0])); Result := 0; end;
         end;
    130: begin
           MaskToDf(PInt64(a0)^, Int64(@t[0]));
           Result := Lx(DfSys(DF_SIGSUSPEND, Int64(@t[0]), 0, 0, 0, 0, 0));
         end;
    34: begin                                                   { pause: sigsuspend(the current mask) }
          t[0] := 0; t[1] := 0;
          DfSys(DF_SIGPROCMASK, 1, 0, Int64(@t[0]), 0, 0, 0);
          Result := Lx(DfSys(DF_SIGSUSPEND, Int64(@t[0]), 0, 0, 0, 0, 0));
        end;
    131: Result := DfSigaltstack(a0, a1);
    200: Result := DfThrKill(a0, a1);                           { tkill }
    234: if (a0 <> DfSys(DF_GETPID, 0, 0, 0, 0, 0, 0)) and (a0 > 0) then
           Result := -3                                         { ESRCH: not our process }
         else Result := DfThrKill(a1, a2);                      { tgkill }
    36: Result := Lx(DfSys(DF_GETITIMER, a0, a1, 0, 0, 0, 0)); { struct itimerval: same }
    38: Result := Lx(DfSys(DF_SETITIMER, a0, a1, a2, 0, 0, 0));
    37: begin                                                   { alarm }
          for i := 0 to 3 do t[i] := 0;
          t[2] := a0;
          for i := 0 to 3 do sb[i] := 0;
          r := DfSys(DF_SETITIMER, 0, Int64(@t[0]), Int64(@sb[0]), 0, 0, 0);
          if r < 0 then Result := Lx(r)
          else begin
            Result := sb[2];
            if sb[3] > 0 then Result := Result + 1;
          end;
        end;
  else
    Result := -LX_ENOSYS;
  end;
end;

end.
