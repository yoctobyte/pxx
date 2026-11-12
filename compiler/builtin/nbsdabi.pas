unit nbsdabi;

{ The Linux syscall ABI on a NetBSD kernel (--os=netbsd, EXPERIMENTAL) -- the
  same in-program translator design as fbsdabi.pas, which explains it at
  length: every kernel entry pxx emits is written against Linux (numbers,
  flag bits, structs, -errno) and funnels through one thunk into
  PXXNbsdSyscall below, which maps it onto NetBSD and maps the answer back.
  The Linux build is untouched.

  CONSTANTS ARE MEASURED, NOT REMEMBERED: numbers from NetBSD 11.1 amd64's
  own headers (sys/syscall.h, sys/syscallargs.h, errno.h, fcntl.h, ...) and
  struct offsets from offsetof() compiled on that system (2026-11-12).

  WHERE NETBSD DIFFERS FROM FREEBSD, which this unit was ported from:
  - Some calls keep a PAD argument before a 64-bit one (mmap, lseek, pread,
    pwrite, preadv, pwritev, truncate, ftruncate, posix_fallocate, mknodat),
    and mmap's offset is then the SEVENTH argument, which NetBSD reads from
    the user stack at [rsp+8]. NbRawA always pushes a seventh word.
  - Versioned names: __fstat50, __getdents30, __socket30, __sigaction_sigtramp
    and so on. The plain numbers are the old ABIs.
  - Native timerfd, eventfd, futex (Linux semantics) and epoll; but the
    kernel's struct epoll_event is 16 bytes (data at offset 8), not Linux's
    packed 12 (measured), so epoll_ctl/epoll_wait repack it.
  - TLS is in fs, set with _lwp_setprivate: setcontext, which ends every
    signal handler, restores the fs base from the saved context
    (_mc_tlsbase). TlsSegPrefix in defs.inc emits fs: for this target.
  - Signals are installed with __sigaction_sigtramp and a trampoline; the
    entry here ends with setcontext(uc) itself, as the trampoline would.
  - Threads: the clone stub calls clone through the thunk with the child's
    resume address in r9; NbClone turns that into _lwp_create (see there).

  CONTEXT RULES (as fbsdabi): no managed types, no heap, no exceptions, no
  RTL calls; the kernel entry is the assembler routine NbRawA. }

interface

function PXXNbsdSyscall(nr, a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl;

implementation

const
  LX_ENOENT = 2;
  LX_EINVAL = 22;
  LX_ENOMEM = 12;
  LX_ENOTTY = 25;
  LX_ENOSYS = 38;
  LX_EEXIST = 17;

  { NetBSD amd64 syscall numbers (sys/syscall.h, 11.1) }
  NB_EXIT = 1; NB_FORK = 2; NB_READ = 3; NB_WRITE = 4; NB_CLOSE = 6;
  NB_LINK = 9; NB_UNLINK = 10; NB_CHDIR = 12; NB_FCHDIR = 13; NB_CHMOD = 15;
  NB_CHOWN = 16; NB_GETPID = 20; NB_SETUID = 23; NB_GETUID = 24; NB_GETEUID = 25;
  NB_ACCESS = 33; NB_SYNC = 36; NB_KILL = 37; NB_GETPPID = 39; NB_DUP = 41;
  NB_GETEGID = 43; NB_GETGID = 47; NB_IOCTL = 54; NB_SYMLINK = 57; NB_READLINK = 58;
  NB_EXECVE = 59; NB_UMASK = 60; NB_MUNMAP = 73; NB_MPROTECT = 74; NB_MADVISE = 75;
  NB_GETGROUPS = 79; NB_SETGROUPS = 80; NB_GETPGRP = 81; NB_SETPGID = 82;
  NB_DUP2 = 90; NB_GETRANDOM = 91; NB_FCNTL = 92; NB_FSYNC = 95; NB_SETPRIORITY = 96;
  NB_GETPRIORITY = 100; NB_READV = 120; NB_WRITEV = 121; NB_FCHOWN = 123;
  NB_FCHMOD = 124; NB_SETREUID = 126; NB_SETREGID = 127; NB_RENAME = 128;
  NB_FLOCK = 131; NB_MKDIR = 136; NB_RMDIR = 137; NB_SETSID = 147;
  NB_SYSARCH = 165; NB_FUTEX = 166; NB_PREAD = 173; NB_PWRITE = 174;
  NB_TIMERFD_CREATE = 177; NB_TIMERFD_SETTIME = 178; NB_TIMERFD_GETTIME = 179;
  NB_SETGID = 181; NB_GETRLIMIT = 194; NB_SETRLIMIT = 195; NB_MMAP = 197;
  NB_LSEEK = 199; NB_TRUNCATE = 200; NB_FTRUNCATE = 201; NB_SYSCTL = 202;
  NB_MLOCK = 203; NB_MUNLOCK = 204; NB_GETPGID = 207; NB_POLL = 209;
  NB_FDATASYNC = 241; NB_MLOCKALL = 242; NB_MUNLOCKALL = 243; NB_EVENTFD = 267;
  NB_LCHOWN = 275; NB_SIGALTSTACK = 281; NB_GETSID = 286; NB_PREADV = 289;
  NB_PWRITEV = 290; NB_SIGPENDING = 292; NB_SIGPROCMASK = 293; NB_SIGSUSPEND = 294;
  NB_GETCWD = 296; NB_SETCONTEXT = 308; NB_LWP_SELF = 311; NB_LWP_GETPRIVATE = 316;
  NB_LWP_SETPRIVATE = 317; NB_LWP_KILL = 318; NB_LWP_SETNAME = 323;
  NB_LWP_GETNAME = 324; NB_SIGACTION = 340; NB_SCHED_YIELD = 350;
  NB_GETDENTS = 390; NB_SOCKET = 394; NB_SELECT = 417; NB_GETTIMEOFDAY = 418;
  NB_UTIMES = 420; NB_SETITIMER = 425; NB_GETITIMER = 426; NB_CLOCK_GETTIME = 427;
  NB_CLOCK_SETTIME = 428; NB_CLOCK_GETRES = 429; NB_NANOSLEEP = 430;
  NB_SIGTIMEDWAIT = 431; NB_PSELECT = 436; NB_POLLTS = 437; NB_FSTAT = 440;
  NB_GETRUSAGE = 445; NB_WAIT4 = 449; NB_PIPE2 = 453; NB_PACCEPT = 456;
  NB_LINKAT = 457; NB_RENAMEAT = 458; NB_MKNODAT = 460; NB_MKDIRAT = 461;
  NB_FACCESSAT = 462; NB_FCHMODAT = 463; NB_FCHOWNAT = 464; NB_FSTATAT = 466;
  NB_UTIMENSAT = 467; NB_OPENAT = 468; NB_READLINKAT = 469; NB_SYMLINKAT = 470;
  NB_UNLINKAT = 471; NB_FUTIMENS = 472; NB_CLOCK_NANOSLEEP = 477;
  NB_POSIX_FALLOCATE = 479; NB_STATVFS = 484; NB_FSTATVFS = 485;
  NB_MEMFD_CREATE = 500; NB_EPOLL_CREATE1 = 502; NB_EPOLL_CTL = 503;
  NB_EPOLL_PWAIT2 = 504; NB_DUP3 = 505;
  NB_GETCONTEXT = 307; NB_LWP_CREATE = 309; NB_LWP_EXIT = 310;
  NB_LWP_DETACHED = $40; NB_UC_TLSBASE = $80000;
  NB_TLS_SLOT_CTID = 14;           { TLS_SLOT_FS_ENTRY: free on x86-64, as fbsdabi uses it }

  NB_AT_FDCWD = -100;
  NB_AT_EACCESS = $100; NB_AT_SYMLINK_NOFOLLOW = $200; NB_AT_SYMLINK_FOLLOW = $400;
  NB_AT_REMOVEDIR = $800;
  NB_O_NONBLOCK = $4; NB_O_CLOEXEC = $400000;
  NB_MAP_FIXED = $10; NB_MAP_ANON = $1000; NB_MAP_STACK = $2000;
  NB_RLIM_INFINITY = $7FFFFFFFFFFFFFFF;
  NB_F_GETPATH = 15;

  { NetBSD errno 35..98 -> Linux. 1..34 are the same; 35..84 are FreeBSD's. }
  ErrMap: array[35..98] of Integer = (
    11, 115, 114, 88, 89, 90, 91, 92, 93, 94,      { 35 EAGAIN .. 44 ESOCKTNOSUPPORT }
    95, 96, 97, 98, 99, 100, 101, 102, 103, 104,   { 45 EOPNOTSUPP .. 54 ECONNRESET }
    105, 106, 107, 108, 109, 110, 111, 40, 36, 112, { 55 ENOBUFS .. 64 EHOSTDOWN }
    113, 39, 11, 87, 122, 116, 66, 22, 22, 22,     { 65 EHOSTUNREACH .. 74 EPROGUNAVAIL }
    22, 22, 37, 38, 22, 13, 13, 43, 42, 75,        { 75 EPROGMISMATCH .. 84 EOVERFLOW }
    84, 95, 125, 74, 61, 63, 60, 62, 61, 72,       { 85 EILSEQ .. 94 EMULTIHOP }
    67, 71, 130, 131);                             { 95 ENOLINK .. 98 ENOTRECOVERABLE }

  { Linux signal 0..31 -> NetBSD. 0 = none (SIGSTKFLT). Linux SIGPWR 30 is
    NetBSD 32; the rest are FreeBSD's numbering. }
  SigMap: array[0..31] of Integer = (
    0, 1, 2, 3, 4, 5, 6, 10, 8, 9, 30, 11, 31, 13, 14, 15,
    0, 20, 19, 17, 18, 21, 22, 16, 24, 25, 26, 27, 28, 23, 32, 12);

  { Linux RLIMIT_* 0..9 -> NetBSD (CPU FSIZE DATA STACK CORE RSS NPROC NOFILE MEMLOCK AS) }
  RlimMap: array[0..9] of Integer = (0, 1, 2, 3, 4, 5, 7, 8, 6, 10);

  BRK_RESERVE = Int64(64) * 1024 * 1024 * 1024;   { address space only, PROT_NONE }

var
  NbBrkBase, NbBrkCur, NbBrkTop: Int64;

{ The kernel entry. args -> [nr, a0..a5, a6, rdx-out, cf-out]. a6 is the
  seventh argument, which NetBSD reads from [rsp+8] at the syscall (mmap's
  offset after its PAD); the word under it stands where a call's return
  address would. CF set = error, rax the positive errno: turned into -errno
  here. CF is captured before the stack is restored, since add changes it. }
function NbRawA(args: Pointer): Int64; assembler;
{$asmMode intel}
asm
  push r12
  mov r12, args
  mov rcx, [r12+56]
  push rcx
  push rcx
  mov rax, [r12]
  mov rdi, [r12+8]
  mov rsi, [r12+16]
  mov rdx, [r12+24]
  mov r10, [r12+32]
  mov r8, [r12+40]
  mov r9, [r12+48]
  syscall
  sbb rcx, rcx
  mov [r12+64], rdx
  mov [r12+72], rcx
  add rsp, 16
  mov rcx, [r12+72]
  xor rax, rcx
  sub rax, rcx
  pop r12
end;

{ The signal trampoline __sigaction_sigtramp requires. NbSigEntry never
  returns to it (it ends with setcontext itself), but the kernel wants one:
  setcontext(uc), uc in r15 as the kernel leaves it. }
procedure NbSigTramp; assembler;
{$asmMode intel}
asm
  mov rdi, r15
  mov eax, 308
  syscall
  mov edi, 70
  mov eax, 1
  syscall
end;

{ The last steps of a non-main thread: clear the CLONE_CHILD_CLEARTID word,
  wake its waiters on both futex queues, _lwp_exit. The moment the word is
  zero the joiner may unmap this thread's stack, so nothing here may touch it:
  registers only, signals already blocked by the caller, and rsp moved to
  area -- __futex takes a 7th argument, which the kernel reads from [rsp+8],
  so rsp must point at readable memory. area is shared by every exiting
  thread and only ever read. Does not return. }
procedure NbClearTidExitA(ctid, area: Int64); assembler;
{$asmMode intel}
asm
  mov r12, ctid
  mov r13, area
  mov rsp, r13
  xor eax, eax
  mov [r12], eax
  mov rdi, r12
  mov esi, 1
  mov edx, $7FFFFFFF
  xor r10d, r10d
  xor r8d, r8d
  xor r9d, r9d
  mov eax, 166
  syscall
  mov rdi, r12
  mov esi, 129
  mov edx, $7FFFFFFF
  xor r10d, r10d
  xor r8d, r8d
  xor r9d, r9d
  mov eax, 166
  syscall
  mov eax, 310
  syscall
end;

var
  NbRdx: Int64;
  NbErr: Boolean;
  NbExitArea: array[0..15] of Int64;

function NbSys7(nr, a0, a1, a2, a3, a4, a5, a6: Int64): Int64;
var a: array[0..9] of Int64;
begin
  a[0] := nr; a[1] := a0; a[2] := a1; a[3] := a2;
  a[4] := a3; a[5] := a4; a[6] := a5; a[7] := a6; a[8] := 0; a[9] := 0;
  Result := NbRawA(@a[0]);
  NbRdx := a[8];
  NbErr := a[9] <> 0;
end;

function NbSys(nr, a0, a1, a2, a3, a4, a5: Int64): Int64;
begin
  Result := NbSys7(nr, a0, a1, a2, a3, a4, a5, 0);
end;

{ -NetBSD errno -> -Linux errno; anything else unchanged. }
function Lx(r: Int64): Int64;
begin
  if (r < -34) and (r >= -98) then Result := -ErrMap[Integer(-r)]
  else Result := r;
end;

function NbOpenFlags(f: Int64): Int64;
var r: Int64;
begin
  r := f and 3;                                       { O_ACCMODE, same }
  if (f and $40) <> 0 then r := r or $200;            { O_CREAT }
  if (f and $80) <> 0 then r := r or $800;            { O_EXCL }
  if (f and $100) <> 0 then r := r or $8000;          { O_NOCTTY }
  if (f and $200) <> 0 then r := r or $400;           { O_TRUNC }
  if (f and $400) <> 0 then r := r or $8;             { O_APPEND }
  if (f and $800) <> 0 then r := r or $4;             { O_NONBLOCK }
  if (f and $1000) <> 0 then r := r or $10000;        { O_DSYNC }
  if (f and $2000) <> 0 then r := r or $40;           { O_ASYNC }
  if (f and $4000) <> 0 then r := r or $80000;        { O_DIRECT }
  if (f and $10000) <> 0 then r := r or $200000;      { O_DIRECTORY }
  if (f and $20000) <> 0 then r := r or $100;         { O_NOFOLLOW }
  if (f and $80000) <> 0 then r := r or $400000;      { O_CLOEXEC }
  if (f and $100000) <> 0 then r := r or $80;         { O_SYNC (Linux sets $101000) }
  Result := r;                                        { O_PATH, O_LARGEFILE, O_NOATIME: dropped }
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
  if (f and $10000) <> 0 then r := r or $1000;
  if (f and $40) <> 0 then r := r or $2000;
  if (f and $80000) <> 0 then r := r or $4000;
  if (f and $200000) <> 0 then r := r or $10000;
  if (f and $100) <> 0 then r := r or $20000;
  if (f and $400000) <> 0 then r := r or $80000;
  if (f and $80) <> 0 then r := r or $101000;
  Result := r;
end;

function NbMmapFlags(f: Int64): Int64;
var r: Int64;
begin
  r := f and $13;                                     { SHARED, PRIVATE, FIXED: same }
  if (f and $20) <> 0 then r := r or NB_MAP_ANON;
  if (f and $20000) <> 0 then r := r or NB_MAP_STACK;
  Result := r;                                        { NORESERVE, POPULATE, GROWSDOWN: dropped }
end;

{ Linux AT_* -> NetBSD for the stat/link/chown family. unlinkat and
  faccessat reuse bit $200 for another meaning and are mapped at their call. }
function NbAtFlags(f: Int64): Int64;
begin
  Result := 0;
  if (f and $100) <> 0 then Result := Result or NB_AT_SYMLINK_NOFOLLOW;
  if (f and $400) <> 0 then Result := Result or NB_AT_SYMLINK_FOLLOW;
end;

function NbClock(id: Int64): Int64;
begin
  case Integer(id) of
    0: Result := 0;            { REALTIME }
    1: Result := 3;            { MONOTONIC }
    2: Result := $40000000;    { PROCESS_CPUTIME_ID }
    3: Result := $20000000;    { THREAD_CPUTIME_ID }
    4: Result := 3;            { MONOTONIC_RAW }
    5: Result := 0;            { REALTIME_COARSE }
    6: Result := 3;            { MONOTONIC_COARSE }
    7: Result := 3;            { BOOTTIME }
  else
    Result := id;
  end;
end;

{ Linux RT signals 32..62 are NetBSD's 33..63; 63 and 64 have no twin. }
function NbSig(s: Int64): Int64;
begin
  if (s >= 0) and (s <= 31) then Result := SigMap[Integer(s)]
  else if (s >= 32) and (s <= 62) then Result := s + 1
  else if (s = 63) or (s = 64) then Result := 0
  else Result := s;
end;

function LxSig(s: Int64): Int64;
var i: Integer;
begin
  if (s >= 33) and (s <= 63) then begin Result := s - 1; Exit; end;
  for i := 1 to 31 do
    if SigMap[i] = s then begin Result := i; Exit; end;
  Result := s;
end;

{ NetBSD struct stat (152 B) -> Linux x86-64 struct stat (144 B). dev_t's
  major/minor packing agrees with glibc's for 32-bit values. }
procedure StatToLinux(nb, lx: Pointer);
var i: Integer;
begin
  for i := 0 to 17 do PInt64(Int64(lx) + i * 8)^ := 0;
  PInt64(Int64(lx) + 0)^ := PInt64(Int64(nb) + 0)^;                 { st_dev }
  PInt64(Int64(lx) + 8)^ := PInt64(Int64(nb) + 16)^;                { st_ino }
  PInt64(Int64(lx) + 16)^ := PLongWord(Int64(nb) + 24)^;            { st_nlink }
  PLongWord(Int64(lx) + 24)^ := PLongWord(Int64(nb) + 8)^;          { st_mode }
  PLongWord(Int64(lx) + 28)^ := PLongWord(Int64(nb) + 28)^;         { st_uid }
  PLongWord(Int64(lx) + 32)^ := PLongWord(Int64(nb) + 32)^;         { st_gid }
  PInt64(Int64(lx) + 40)^ := PInt64(Int64(nb) + 40)^;               { st_rdev }
  PInt64(Int64(lx) + 48)^ := PInt64(Int64(nb) + 112)^;              { st_size }
  PInt64(Int64(lx) + 56)^ := PLongWord(Int64(nb) + 128)^;           { st_blksize }
  PInt64(Int64(lx) + 64)^ := PInt64(Int64(nb) + 120)^;              { st_blocks }
  PInt64(Int64(lx) + 72)^ := PInt64(Int64(nb) + 48)^;               { st_atim }
  PInt64(Int64(lx) + 80)^ := PInt64(Int64(nb) + 56)^;
  PInt64(Int64(lx) + 88)^ := PInt64(Int64(nb) + 64)^;               { st_mtim }
  PInt64(Int64(lx) + 96)^ := PInt64(Int64(nb) + 72)^;
  PInt64(Int64(lx) + 104)^ := PInt64(Int64(nb) + 80)^;              { st_ctim }
  PInt64(Int64(lx) + 112)^ := PInt64(Int64(nb) + 88)^;
end;

{ NetBSD struct stat -> Linux struct statx (256 B). }
procedure StatToStatx(nb, sx: Pointer);
var i: Integer;
procedure Ts(lxOff, nbOff: Integer);
begin
  PInt64(Int64(sx) + lxOff)^ := PInt64(Int64(nb) + nbOff)^;
  PLongWord(Int64(sx) + lxOff + 8)^ := LongWord(PInt64(Int64(nb) + nbOff + 8)^);
end;
begin
  for i := 0 to 31 do PInt64(Int64(sx) + i * 8)^ := 0;
  PLongWord(Int64(sx) + 0)^ := $FFF;                                { BASIC_STATS | BTIME }
  PLongWord(Int64(sx) + 4)^ := PLongWord(Int64(nb) + 128)^;         { blksize }
  PLongWord(Int64(sx) + 16)^ := PLongWord(Int64(nb) + 24)^;         { nlink }
  PLongWord(Int64(sx) + 20)^ := PLongWord(Int64(nb) + 28)^;         { uid }
  PLongWord(Int64(sx) + 24)^ := PLongWord(Int64(nb) + 32)^;         { gid }
  PWord(Int64(sx) + 28)^ := PWord(Int64(nb) + 8)^;                  { mode }
  PInt64(Int64(sx) + 32)^ := PInt64(Int64(nb) + 16)^;               { ino }
  PInt64(Int64(sx) + 40)^ := PInt64(Int64(nb) + 112)^;              { size }
  PInt64(Int64(sx) + 48)^ := PInt64(Int64(nb) + 120)^;              { blocks }
  Ts(64, 48);                                                       { atime }
  Ts(80, 96);                                                       { btime }
  Ts(96, 80);                                                       { ctime }
  Ts(112, 64);                                                      { mtime }
  PLongWord(Int64(sx) + 128)^ := LongWord((PInt64(Int64(nb) + 40)^ shr 8) and $FFF);   { rdev major }
  PLongWord(Int64(sx) + 132)^ := LongWord((PInt64(Int64(nb) + 40)^ and $FF) or
                                 ((PInt64(Int64(nb) + 40)^ shr 12) and $FFF00));        { rdev minor }
  PLongWord(Int64(sx) + 136)^ := LongWord((PInt64(Int64(nb) + 0)^ shr 8) and $FFF);    { dev major }
  PLongWord(Int64(sx) + 140)^ := LongWord((PInt64(Int64(nb) + 0)^ and $FF) or
                                 ((PInt64(Int64(nb) + 0)^ shr 12) and $FFF00));         { dev minor }
end;

{ getdents64. NetBSD's record (ino 0, reclen 8, namlen 10, type 12, name 13)
  is up to 8 bytes shorter than Linux's (ino 0, off 8, reclen 16, type 18,
  name 19), so the records cannot be widened in place. They are read into a
  scratch buffer two thirds the caller's size -- the most a record grows is
  16 -> 24 bytes -- and written out widened. }
function NbGetdents(fd, buf, cap: Int64): Int64;
var tmp: array[0..8191] of Byte;
    want, r, p, o, nl, rl, i: Int64;
begin
  want := (cap * 2) div 3;
  if want > 8192 then want := 8192;
  r := NbSys(NB_GETDENTS, fd, Int64(@tmp[0]), want, 0, 0, 0);
  if r <= 0 then begin Result := Lx(r); Exit; end;
  p := 0; o := 0;
  while p < r do
  begin
    rl := PWord(Int64(@tmp[0]) + p + 8)^;
    nl := PWord(Int64(@tmp[0]) + p + 10)^;
    if rl = 0 then Break;
    i := (19 + nl + 1 + 7) and not Int64(7);
    if o + i > cap then Break;
    PInt64(buf + o)^ := PInt64(Int64(@tmp[0]) + p)^;                  { d_ino }
    PInt64(buf + o + 8)^ := o + i;                                    { d_off }
    PWord(buf + o + 16)^ := Word(i);                                  { d_reclen }
    PByte(buf + o + 18)^ := PByte(Int64(@tmp[0]) + p + 12)^;          { d_type: DT_* agree }
    for rl := 0 to nl do
      PByte(buf + o + 19 + rl)^ := PByte(Int64(@tmp[0]) + p + 13 + rl)^;   { name and NUL }
    for rl := 19 + nl + 1 to i - 1 do PByte(buf + o + rl)^ := 0;
    o := o + i;
    p := p + PWord(Int64(@tmp[0]) + p + 8)^;
  end;
  Result := o;
end;

{ Linux brk on a PROT_NONE reservation: brk(0) must answer the current
  break, which NetBSD's break(2) cannot. }
function NbBrk(want: Int64): Int64;
var top, r: Int64;
begin
  if NbBrkBase = 0 then
  begin
    r := NbSys7(NB_MMAP, 0, BRK_RESERVE, 0, $1002, -1, 0, 0);     { PRIVATE|ANON, PROT_NONE }
    if r < 0 then begin Result := 0; Exit; end;
    NbBrkBase := r; NbBrkCur := r; NbBrkTop := r;
  end;
  Result := NbBrkCur;
  if (want < NbBrkBase) or (want > NbBrkBase + BRK_RESERVE) then Exit;
  if want > NbBrkTop then
  begin
    top := (want + $FFFF) and (not Int64($FFFF));
    r := NbSys7(NB_MMAP, NbBrkTop, top - NbBrkTop, 3, $1002 or NB_MAP_FIXED, -1, 0, 0);
    if r < 0 then Exit;
    NbBrkTop := top;
  end;
  NbBrkCur := want;
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
  if NbSys(NB_SYSCTL, Int64(@mib[0]), 2, dst, Int64(@len), 0, 0) < 0 then len := 0;
  if len > cap - 1 then len := cap - 1;
  PByte(dst + len)^ := 0;
end;

{ Linux struct utsname from sysctl, as NetBSD's libc builds it. Machine is
  Linux's spelling (x86_64), as the FreeBSD translator answers. }
function NbUname(u: Int64): Int64;
var i: Integer;
const
  SysName: array[0..5] of Byte = (78, 101, 116, 66, 83, 68);       { NetBSD }
  Machine: array[0..5] of Byte = (120, 56, 54, 95, 54, 52);         { x86_64 }
begin
  for i := 0 to 389 do PByte(u + i)^ := 0;
  for i := 0 to 5 do PByte(u + i)^ := SysName[i];
  SysctlStr(1, 10, u + 65, 65);      { kern.hostname }
  SysctlStr(1, 2, u + 130, 65);      { kern.osrelease }
  SysctlStr(1, 4, u + 195, 65);      { kern.version }
  for i := 0 to 5 do PByte(u + 260 + i)^ := Machine[i];
  Result := 0;
end;

function NbGetRlimit(res, lim: Int64): Int64;
var r: Int64;
begin
  if (res < 0) or (res > 9) then begin Result := -LX_EINVAL; Exit; end;
  r := NbSys(NB_GETRLIMIT, RlimMap[Integer(res)], lim, 0, 0, 0, 0);
  if r = 0 then
  begin
    if PInt64(lim)^ = NB_RLIM_INFINITY then PInt64(lim)^ := -1;
    if PInt64(lim + 8)^ = NB_RLIM_INFINITY then PInt64(lim + 8)^ := -1;
  end;
  Result := Lx(r);
end;

function NbSetRlimit(res, lim: Int64): Int64;
var v: array[0..1] of Int64;
begin
  if (res < 0) or (res > 9) then begin Result := -LX_EINVAL; Exit; end;
  v[0] := PInt64(lim)^; v[1] := PInt64(lim + 8)^;
  if v[0] = -1 then v[0] := NB_RLIM_INFINITY;
  if v[1] = -1 then v[1] := NB_RLIM_INFINITY;
  Result := Lx(NbSys(NB_SETRLIMIT, RlimMap[Integer(res)], Int64(@v[0]), 0, 0, 0, 0));
end;

{ fstatat, with Linux's AT_EMPTY_PATH (an empty path means dirfd itself),
  which NetBSD lacks, done as fstat. }
function NbStatRaw(dirfd, path, sb, flags: Int64): Int64;
begin
  if ((flags and $1000) <> 0) and (path <> 0) and (PByte(path)^ = 0) then
    Result := NbSys(NB_FSTAT, dirfd, sb, 0, 0, 0, 0)
  else
    Result := NbSys(NB_FSTATAT, dirfd, path, sb, NbAtFlags(flags), 0, 0);
end;

function NbStatAt(dirfd, path, buf, flags: Int64): Int64;
var sb: array[0..18] of Int64; r: Int64;
begin
  r := NbStatRaw(dirfd, path, Int64(@sb[0]), flags);
  if r = 0 then StatToLinux(@sb[0], Pointer(buf));
  Result := Lx(r);
end;

{ ---- the /proc files the runtime reads -----------------------------------
  NetBSD's /proc may not be mounted, and its layout is not Linux's. The
  environment and the executable's path come from sysctl kern.proc_args; an
  open() of such a file answers a memfd holding what Linux would serve. }

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
  ProcHostname: array[0..24] of Byte = (47,112,114,111,99,47,115,121,115,47,107,101,114,
                                        110,101,108,47,104,111,115,116,110,97,109,101);  { /proc/sys/kernel/hostname }
  MemfdName: array[0..3] of Byte = (112, 120, 120, 0);                  { pxx }

{ A memfd holding len bytes at buf, rewound. }
function NbDataFd(buf, len: Int64): Int64;
var fd: Int64;
begin
  fd := NbSys(NB_MEMFD_CREATE, Int64(@MemfdName[0]), 1, 0, 0, 0, 0);   { MFD_CLOEXEC }
  if (fd >= 0) and (len > 0) then
  begin
    NbSys(NB_WRITE, fd, buf, len, 0, 0, 0);
    NbSys(NB_LSEEK, fd, 0, 0, 0, 0, 0);                              { (fd, PAD, 0, SEEK_SET) }
  end;
  Result := Lx(fd);
end;

function NbProcHostname: Int64;
var b: array[0..299] of Byte; n: Int64;
begin
  SysctlStr(1, 10, Int64(@b[0]), 256);
  n := StrLen0(Int64(@b[0]));
  b[n] := 10;
  Result := NbDataFd(Int64(@b[0]), n + 1);
end;

{ kern.proc_args.<pid>.env: the strings NUL-separated, as /proc serves them. }
function NbProcEnviron: Int64;
var mib: array[0..3] of Integer; len, buf, size, r: Int64;
begin
  mib[0] := 1; mib[1] := 48; mib[2] := Integer(NbSys(NB_GETPID, 0, 0, 0, 0, 0, 0)); mib[3] := 3;
  len := 0;
  r := NbSys(NB_SYSCTL, Int64(@mib[0]), 4, 0, Int64(@len), 0, 0);
  if r < 0 then begin Result := Lx(r); Exit; end;
  size := (len + 4096 + $FFF) and (not Int64($FFF));
  buf := NbSys7(NB_MMAP, 0, size, 3, $1002, -1, 0, 0);
  if buf < 0 then begin Result := -LX_ENOMEM; Exit; end;
  len := size;
  r := NbSys(NB_SYSCTL, Int64(@mib[0]), 4, buf, Int64(@len), 0, 0);
  if r < 0 then len := 0;
  Result := NbDataFd(buf, len);
  NbSys(NB_MUNMAP, buf, size, 0, 0, 0, 0);
end;

{ readlink("/proc/self/exe"): kern.proc_args.-1.pathname. }
function NbProcExe(buf, cap: Int64): Int64;
var mib: array[0..3] of Integer; len, r: Int64;
    tmp: array[0..1023] of Byte;
    i: Integer;
begin
  mib[0] := 1; mib[1] := 48; mib[2] := -1; mib[3] := 5;
  len := 1024;
  r := NbSys(NB_SYSCTL, Int64(@mib[0]), 4, Int64(@tmp[0]), Int64(@len), 0, 0);
  if r < 0 then begin Result := Lx(r); Exit; end;
  if (len > 0) and (tmp[len - 1] = 0) then len := len - 1;
  if len > cap then len := cap;
  for i := 0 to Integer(len) - 1 do PByte(buf + i)^ := tmp[i];
  Result := len;
end;

{ /proc/self/fd/N -> N, or -1 when p is not that shape. }
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

{ readlink("/proc/self/fd/N") via fcntl(F_GETPATH). }
function NbProcFd(fd, buf, cap: Int64): Int64;
var tmp: array[0..1023] of Byte;
    n, i, r: Int64;
begin
  tmp[0] := 0;
  r := NbSys(NB_FCNTL, fd, NB_F_GETPATH, Int64(@tmp[0]), 0, 0, 0);
  if r < 0 then begin Result := Lx(r); Exit; end;
  n := StrLen0(Int64(@tmp[0]));
  if n = 0 then begin Result := -LX_ENOENT; Exit; end;
  if n > cap then n := cap;
  for i := 0 to n - 1 do PByte(buf + i)^ := tmp[i];
  Result := n;
end;

{ ---- Signals ----------------------------------------------------------------
  As in fbsdabi: rt_sigaction records the program's (Linux-ABI) handler and
  installs NbSigEntry, which builds a Linux siginfo/ucontext, calls the
  handler, copies the register file back and resumes with setcontext.
  NetBSD's ucontext: uc_sigmask at 16, uc_mcontext at 56 holding __gregs[26]
  (_REG_* order, below), _mc_tlsbase at 208 and the fxsave area at 216. }

const
  NB_SIGTRAMP_VERSION = 2;          { __SIGTRAMP_SIGINFO_VERSION }
  NB_SA_ONSTACK = $1; NB_SA_RESTART = $2; NB_SA_RESETHAND = $4;
  NB_SA_NOCLDSTOP = $8; NB_SA_NODEFER = $10; NB_SA_NOCLDWAIT = $20;
  NB_SA_SIGINFO = $40;
  LX_SA_NOCLDSTOP = $1; LX_SA_NOCLDWAIT = $2; LX_SA_SIGINFO = $4;
  LX_SA_ONSTACK = $08000000; LX_SA_RESTART = $10000000;
  LX_SA_NODEFER = $40000000; LX_SA_RESETHAND = $80000000;
  { Linux gregs[0..17] (R8 R9 R10 R11 R12 R13 R14 R15 RDI RSI RBP RBX RDX RAX
    RCX RSP RIP EFL) -> NetBSD _REG_* index. }
  NbGregIx: array[0..17] of Integer = (
    4, 5, 6, 7, 8, 9, 10, 11, 0, 1, 12, 13, 2, 14, 3, 24, 21, 23);
  NB_UC_MCONTEXT = 56;
  NB_UC_SIGMASK = 16;
  NB_MC_FPREGS = 216;
  LX_UC_GREGS = 40;
  LX_UC_SIGMASK = 296;

var
  NbLxHandler: array[0..127] of Int64;   { by NetBSD signal number }

{ Linux 64-bit mask (bit s-1) -> NetBSD sigset_t (4 x 32 bits, bit s-1). }
procedure MaskToNb(lx, nb: Int64);
var s, b: Int64;
begin
  PInt64(nb)^ := 0; PInt64(nb + 8)^ := 0;
  for s := 1 to 64 do
    if ((lx shr (s - 1)) and 1) <> 0 then
    begin
      b := NbSig(s);
      if (b >= 1) and (b <= 127) then
        PInteger(nb + ((b - 1) shr 5) * 4)^ :=
          PInteger(nb + ((b - 1) shr 5) * 4)^ or Integer(Int64(1) shl ((b - 1) and 31));
    end;
end;

function MaskToLx(nb: Int64): Int64;
var b, s: Int64;
begin
  Result := 0;
  for b := 1 to 127 do
    if ((PInteger(nb + ((b - 1) shr 5) * 4)^ shr ((b - 1) and 31)) and 1) <> 0 then
    begin
      s := LxSig(b);
      if (s >= 1) and (s <= 64) then Result := Result or (Int64(1) shl (s - 1));
    end;
end;

function SaFlagsToNb(f: Int64): Int64;
begin
  Result := 0;
  if (f and LX_SA_NOCLDSTOP) <> 0 then Result := Result or NB_SA_NOCLDSTOP;
  if (f and LX_SA_NOCLDWAIT) <> 0 then Result := Result or NB_SA_NOCLDWAIT;
  if (f and LX_SA_SIGINFO) <> 0 then Result := Result or NB_SA_SIGINFO;
  if (f and LX_SA_ONSTACK) <> 0 then Result := Result or NB_SA_ONSTACK;
  if (f and LX_SA_RESTART) <> 0 then Result := Result or NB_SA_RESTART;
  if (f and LX_SA_NODEFER) <> 0 then Result := Result or NB_SA_NODEFER;
  if (f and LX_SA_RESETHAND) <> 0 then Result := Result or NB_SA_RESETHAND;
end;

function SaFlagsToLx(f: Int64): Int64;
begin
  Result := 0;
  if (f and NB_SA_NOCLDSTOP) <> 0 then Result := Result or LX_SA_NOCLDSTOP;
  if (f and NB_SA_NOCLDWAIT) <> 0 then Result := Result or LX_SA_NOCLDWAIT;
  if (f and NB_SA_SIGINFO) <> 0 then Result := Result or LX_SA_SIGINFO;
  if (f and NB_SA_ONSTACK) <> 0 then Result := Result or LX_SA_ONSTACK;
  if (f and NB_SA_RESTART) <> 0 then Result := Result or LX_SA_RESTART;
  if (f and NB_SA_NODEFER) <> 0 then Result := Result or LX_SA_NODEFER;
  if (f and NB_SA_RESETHAND) <> 0 then Result := Result or LX_SA_RESETHAND;
end;

type
  TNbLxHandler = procedure(sig, info, uc: Int64); cdecl;

{ NetBSD siginfo_t (signo 0, code 4, errno 8; pid 16, uid 20 / addr 16)
  -> Linux siginfo_t (signo 0, errno 4, code 8; pid 16, uid 20 / addr 16).
  The si_code values are Linux's, except SI_LWP (-5), Linux's SI_TKILL (-6). }
procedure SiginfoToLx(nb, lx: Int64);
var i: Integer;
    c, ls: Int64;
begin
  for i := 0 to 15 do PInt64(lx + i * 8)^ := 0;
  ls := LxSig(PInteger(nb)^);
  PInteger(lx)^ := Integer(ls);
  PInteger(lx + 4)^ := PInteger(nb + 8)^;
  c := PInteger(nb + 4)^;
  if c = -5 then c := -6;
  PInteger(lx + 8)^ := Integer(c);
  PInt64(lx + 16)^ := PInt64(nb + 16)^;                       { si_pid+si_uid, or si_addr }
  if (ls = 17) and (c > 0) then                               { SIGCHLD: si_status }
    PInteger(lx + 24)^ := PInteger(nb + 24)^;
end;

{ The handler NetBSD calls (rdi sig, rsi siginfo, rdx ucontext). It resumes
  the interrupted context with setcontext, as the trampoline would. }
procedure NbSigEntry(sig, info, uc: Int64); cdecl;
var li: array[0..15] of Int64;        { Linux siginfo_t, 128 B }
    lu: array[0..63] of Int64;        { Linux ucontext_t through uc_sigmask }
    i: Integer;
    h, ls, mc: Int64;
begin
  if (sig >= 0) and (sig <= 127) then h := NbLxHandler[Integer(sig)] else h := 0;
  if h <> 0 then
  begin
    ls := LxSig(sig);
    for i := 0 to 15 do li[i] := 0;
    for i := 0 to 63 do lu[i] := 0;
    if info <> 0 then SiginfoToLx(info, Int64(@li[0]))
    else PInteger(@li[0])^ := Integer(ls);
    if uc <> 0 then
    begin
      mc := uc + NB_UC_MCONTEXT;
      for i := 0 to 17 do
        lu[LX_UC_GREGS div 8 + i] := PInt64(mc + NbGregIx[i] * 8)^;
      lu[LX_UC_GREGS div 8 + 19] := PInt64(mc + 20 * 8)^;              { ERR }
      lu[LX_UC_GREGS div 8 + 20] := PInt64(mc + 19 * 8)^;              { TRAPNO }
      if info <> 0 then lu[LX_UC_GREGS div 8 + 22] := PInt64(info + 16)^;   { CR2 = si_addr }
      lu[LX_UC_GREGS div 8 + 23] := mc + NB_MC_FPREGS;                 { fpregs: fxsave, as Linux's }
      lu[LX_UC_SIGMASK div 8] := MaskToLx(uc + NB_UC_SIGMASK);
    end;
    TNbLxHandler(h)(ls, Int64(@li[0]), Int64(@lu[0]));
    if uc <> 0 then
      for i := 0 to 17 do
        PInt64(uc + NB_UC_MCONTEXT + NbGregIx[i] * 8)^ := lu[LX_UC_GREGS div 8 + i];
  end;
  if uc <> 0 then NbSys(NB_SETCONTEXT, uc, 0, 0, 0, 0, 0);
end;

function NbRtSigaction(sig, act, oact: Int64): Int64;
var na, no: array[0..3] of Int64;     { NetBSD struct sigaction: handler, mask[16], flags }
    ns, h, oldh, r: Int64;
begin
  ns := NbSig(sig);
  if (ns < 1) or (ns > 127) then begin Result := -LX_EINVAL; Exit; end;
  oldh := NbLxHandler[Integer(ns)];
  na[0] := 0; na[1] := 0; na[2] := 0; na[3] := 0;
  no[0] := 0; no[1] := 0; no[2] := 0; no[3] := 0;
  if act <> 0 then
  begin
    h := PInt64(act)^;
    PInteger(Int64(@na[0]) + 24)^ := Integer(SaFlagsToNb(PInt64(act + 8)^));
    MaskToNb(PInt64(act + 24)^, Int64(@na[0]) + 8);
    if (h = 0) or (h = 1) then na[0] := h                 { SIG_DFL / SIG_IGN }
    else
    begin
      NbLxHandler[Integer(ns)] := h;
      na[0] := Int64(@NbSigEntry);
      PInteger(Int64(@na[0]) + 24)^ := PInteger(Int64(@na[0]) + 24)^ or NB_SA_SIGINFO;
    end;
    r := NbSys(NB_SIGACTION, ns, Int64(@na[0]), Int64(@no[0]), Int64(@NbSigTramp), NB_SIGTRAMP_VERSION, 0);
    if r <> 0 then NbLxHandler[Integer(ns)] := oldh
    else if (h = 0) or (h = 1) then NbLxHandler[Integer(ns)] := 0;
  end
  else
    r := NbSys(NB_SIGACTION, ns, 0, Int64(@no[0]), 0, 0, 0);
  if (r = 0) and (oact <> 0) then
  begin
    if no[0] = Int64(@NbSigEntry) then PInt64(oact)^ := oldh
    else PInt64(oact)^ := no[0];
    PInt64(oact + 8)^ := SaFlagsToLx(PInteger(Int64(@no[0]) + 24)^);
    PInt64(oact + 16)^ := 0;
    PInt64(oact + 24)^ := MaskToLx(Int64(@no[0]) + 8);
  end;
  Result := Lx(r);
end;

function NbRtSigprocmask(how, nset, oset: Int64): Int64;
var nn, no: array[0..1] of Int64;
    r: Int64;
begin
  if (how < 0) or (how > 2) then begin Result := -LX_EINVAL; Exit; end;
  no[0] := 0; no[1] := 0;
  if nset <> 0 then
  begin
    MaskToNb(PInt64(nset)^, Int64(@nn[0]));
    r := NbSys(NB_SIGPROCMASK, how + 1, Int64(@nn[0]), Int64(@no[0]), 0, 0, 0);
  end
  else
    r := NbSys(NB_SIGPROCMASK, how + 1, 0, Int64(@no[0]), 0, 0, 0);
  if (r = 0) and (oset <> 0) then PInt64(oset)^ := MaskToLx(Int64(@no[0]));
  Result := Lx(r);
end;

{ rt_sigtimedwait(set, info, timeout): answers the LINUX signal number. }
function NbRtSigtimedwait(nset, info, ts: Int64): Int64;
var ns: array[0..1] of Int64;
    ni: array[0..15] of Int64;                                { NetBSD siginfo_t, 128 B }
    r: Int64;
begin
  MaskToNb(PInt64(nset)^, Int64(@ns[0]));
  r := NbSys(NB_SIGTIMEDWAIT, Int64(@ns[0]), Int64(@ni[0]), ts, 0, 0, 0);
  if r > 0 then
  begin
    if info <> 0 then SiginfoToLx(Int64(@ni[0]), info);
    Result := LxSig(r);
  end
  else Result := Lx(r);
end;

{ Wait statuses carry signal numbers; "continued" is 0xffff on both. }
function WaitStatusToLx(st: Int64): Int64;
var lo: Int64;
begin
  st := st and $FFFF;
  lo := st and $7F;
  if st = $FFFF then Result := $FFFF
  else if lo = $7F then Result := (LxSig((st shr 8) and $FF) shl 8) or $7F
  else if lo <> 0 then Result := (st and not Int64($7F)) or LxSig(lo)
  else Result := st;
end;

function NbWait4(pid, status, options, rusage: Int64): Int64;
var o, st, r: Int64;
begin
  o := options and 3;                                         { WNOHANG, WUNTRACED agree }
  if (options and 8) <> 0 then o := o or 16;                  { WCONTINUED }
  st := 0;
  r := NbSys(NB_WAIT4, pid, Int64(@st), o, rusage, 0, 0);
  if (r > 0) and (status <> 0) then PInteger(status)^ := Integer(WaitStatusToLx(st));
  Result := Lx(r);
end;

{ times(): no syscall. struct tms in USER_HZ (100) from getrusage. }
function NbTimes(buf: Int64): Int64;
var ru: array[0..17] of Int64;     { struct rusage, 144 B on both }
    ts: array[0..1] of Int64;
begin
  if buf <> 0 then
  begin
    NbSys(NB_GETRUSAGE, 0, Int64(@ru[0]), 0, 0, 0, 0);
    PInt64(buf)^ := ru[0] * 100 + ru[1] div 10000;
    PInt64(buf + 8)^ := ru[2] * 100 + ru[3] div 10000;
    NbSys(NB_GETRUSAGE, -1, Int64(@ru[0]), 0, 0, 0, 0);
    PInt64(buf + 16)^ := ru[0] * 100 + ru[1] div 10000;
    PInt64(buf + 24)^ := ru[2] * 100 + ru[3] div 10000;
  end;
  NbSys(NB_CLOCK_GETTIME, 3, Int64(@ts[0]), 0, 0, 0, 0);
  Result := ts[0] * 100 + ts[1] div 10000000;
end;

{ alarm(): no syscall; ITIMER_REAL, answering the seconds left. }
function NbAlarm(secs: Int64): Int64;
var nv, ov: array[0..3] of Int64;
begin
  nv[0] := 0; nv[1] := 0; nv[2] := secs; nv[3] := 0;
  ov[2] := 0; ov[3] := 0;
  NbSys(NB_SETITIMER, 0, Int64(@nv[0]), Int64(@ov[0]), 0, 0, 0);
  Result := ov[2];
  if ov[3] >= 500000 then Inc(Result);
  if (Result = 0) and ((ov[2] <> 0) or (ov[3] <> 0)) then Result := 1;
end;

{ NetBSD struct statvfs (3296 B) -> Linux struct statfs (120 B). }
function NbStatfs(isFd: Boolean; arg, lx: Int64): Int64;
var fs: array[0..411] of Int64;
    r, fl, ty, i: Int64;
    nm: Int64;
begin
  if isFd then r := NbSys(NB_FSTATVFS, arg, Int64(@fs[0]), 1, 0, 0, 0)   { ST_WAIT }
  else r := NbSys(NB_STATVFS, arg, Int64(@fs[0]), 1, 0, 0, 0);
  if r < 0 then begin Result := Lx(r); Exit; end;
  for i := 0 to 14 do PInt64(lx + i * 8)^ := 0;
  nm := Int64(@fs[0]) + 192;                                  { f_fstypename }
  ty := 0;
  case PByte(nm)^ of                                          { Linux f_type magics }
    102: ty := $00011954;                                     { ffs }
    116: ty := $01021994;                                     { tmpfs }
    112: if PByte(nm + 1)^ = 114 then ty := $9FA0;            { procfs }
    110: ty := $6969;                                         { nfs }
    109: ty := $4D44;                                         { msdos }
    99:  ty := $9660;                                         { cd9660 }
    122: ty := $2FC12FC1;                                     { zfs }
  end;
  PInt64(lx)^ := ty;
  PInt64(lx + 8)^ := fs[2];                                   { f_bsize = f_frsize: the blocks' unit }
  for i := 0 to 2 do PInt64(lx + 16 + i * 8)^ := fs[4 + i];   { blocks bfree bavail }
  PInt64(lx + 40)^ := fs[8];                                  { files }
  PInt64(lx + 48)^ := fs[9];                                  { ffree }
  PInt64(lx + 56)^ := fs[17];                                 { f_fsid }
  PInt64(lx + 64)^ := fs[18];                                 { f_namelen }
  PInt64(lx + 72)^ := fs[2];                                  { f_frsize }
  fl := fs[0];
  r := 0;
  if (fl and $1) <> 0 then r := r or 1;                       { ST_RDONLY }
  if (fl and $8) <> 0 then r := r or 2;                       { ST_NOSUID }
  if (fl and $4) <> 0 then r := r or 8;                       { ST_NOEXEC }
  if (fl and $2) <> 0 then r := r or 16;                      { ST_SYNCHRONOUS }
  if (fl and $4000000) <> 0 then r := r or 1024;              { ST_NOATIME }
  PInt64(lx + 80)^ := r;
  Result := 0;
end;

{ poll: the low bits agree; Linux's WRNORM ($100) and WRBAND ($200) are
  NetBSD's $4 and $100, and RDHUP has no twin. Rewritten in place. }
function PollBitsToNb(e: Integer): Integer;
begin
  Result := e and $FF;
  if (e and $100) <> 0 then Result := Result or $4;
  if (e and $200) <> 0 then Result := Result or $100;
end;

function PollBitsToLx(e, asked: Integer): Integer;
begin
  Result := e and $FF;
  if ((e and $4) <> 0) and ((asked and $100) <> 0) then Result := Result or $100;
  if (e and $100) <> 0 then Result := Result or $200;
end;

function NbPoll(fds, n, ts, mask: Int64; isPpoll: Boolean): Int64;
var i, r: Int64;
    m: array[0..1] of Int64;
    tv: array[0..1] of Int64;
    orig: array[0..63] of Integer;
    asked: Integer;
begin
  for i := 0 to n - 1 do
  begin
    asked := PSmallInt(fds + i * 8 + 4)^ and $FFFF;
    if i < 64 then orig[i] := asked;
    PSmallInt(fds + i * 8 + 4)^ := SmallInt(PollBitsToNb(asked));
  end;
  if not isPpoll then r := NbSys(NB_POLL, fds, n, ts, 0, 0, 0)
  else
  begin
    if ts <> 0 then begin tv[0] := PInt64(ts)^; tv[1] := PInt64(ts + 8)^; ts := Int64(@tv[0]); end;
    if mask <> 0 then
    begin
      MaskToNb(PInt64(mask)^, Int64(@m[0]));
      r := NbSys(NB_POLLTS, fds, n, ts, Int64(@m[0]), 0, 0);
    end
    else r := NbSys(NB_POLLTS, fds, n, ts, 0, 0, 0);
  end;
  for i := 0 to n - 1 do
  begin
    if i < 64 then asked := orig[i]
    else asked := PollBitsToLx(PSmallInt(fds + i * 8 + 4)^ and $FFFF, $FFFF);
    PSmallInt(fds + i * 8 + 4)^ := SmallInt(asked);
    PSmallInt(fds + i * 8 + 6)^ := SmallInt(PollBitsToLx(PSmallInt(fds + i * 8 + 6)^ and $FFFF, asked));
  end;
  Result := Lx(r);
end;

{ ---- epoll, timerfd, eventfd: native, with Linux's flag values -----------
  Only the epoll_event layout differs: Linux's is packed (u32 events, u64
  data at 4: 12 B), NetBSD's kernel struct is natural (data at 8: 16 B). }
const
  EP_MAX = 64;

function NbFdFlags(f: Int64): Int64;   { EFD_/TFD_/EPOLL_ NONBLOCK, CLOEXEC are O_* }
begin
  Result := 0;
  if (f and $800) <> 0 then Result := Result or NB_O_NONBLOCK;
  if (f and $80000) <> 0 then Result := Result or NB_O_CLOEXEC;
end;

function NbEpollCtl(ep, op, fd, ev: Int64): Int64;
var e: array[0..1] of Int64;
begin
  if ev = 0 then
    Result := Lx(NbSys(NB_EPOLL_CTL, ep, op, fd, 0, 0, 0))
  else
  begin
    e[0] := PInteger(ev)^ and $FFFFFFFF;
    e[1] := PInt64(ev + 4)^;
    Result := Lx(NbSys(NB_EPOLL_CTL, ep, op, fd, Int64(@e[0]), 0, 0));
  end;
end;

function NbEpollWait(ep, evs, maxev, ms, mask: Int64): Int64;
var ne: array[0..EP_MAX * 2 - 1] of Int64;
    ts, m: array[0..1] of Int64;
    tp, mp, r, i: Int64;
begin
  if maxev <= 0 then begin Result := -LX_EINVAL; Exit; end;
  if maxev > EP_MAX then maxev := EP_MAX;
  tp := 0;
  if ms >= 0 then
  begin
    ts[0] := ms div 1000; ts[1] := (ms mod 1000) * 1000000;
    tp := Int64(@ts[0]);
  end;
  mp := 0;
  if mask <> 0 then begin MaskToNb(PInt64(mask)^, Int64(@m[0])); mp := Int64(@m[0]); end;
  r := NbSys(NB_EPOLL_PWAIT2, ep, Int64(@ne[0]), maxev, tp, mp, 0);
  if r < 0 then begin Result := Lx(r); Exit; end;
  for i := 0 to r - 1 do
  begin
    PInteger(evs + i * 12)^ := Integer(ne[i * 2]);
    PInt64(evs + i * 12 + 4)^ := ne[i * 2 + 1];
  end;
  Result := r;
end;

{ ---- Sockets -----------------------------------------------------------------
  FreeBSD's shape (sockaddr length byte, 48-byte msghdr, 32-bit cmsg_len),
  with NetBSD's numbers: AF_INET6 24, MSG_NOSIGNAL $400, SO_RCVTIMEO $100C,
  TCP_KEEPIDLE 3, accept4 as paccept. }
const
  NB_CONNECT = 98; NB_ACCEPT = 30; NB_SENDTO = 133;
  NB_RECVFROM = 29; NB_SENDMSG = 28; NB_RECVMSG = 27; NB_SHUTDOWN = 134;
  NB_BIND = 104; NB_LISTEN = 106; NB_GETSOCKNAME = 32; NB_GETPEERNAME = 31;
  NB_SOCKETPAIR = 135; NB_SETSOCKOPT = 105; NB_GETSOCKOPT = 118;
  LX_EAFNOSUPPORT = 97; LX_ENOPROTOOPT = 92;

function NbAf(a: Int64): Int64;
begin
  case a of
    0, 1, 2: Result := a;
    10: Result := 24;
  else Result := -1;
  end;
end;

function LxAf(a: Int64): Int64;
begin
  if a = 24 then Result := 10 else Result := a;
end;

function NbSockType(t: Int64): Int64;
begin
  Result := t and $FF;
  if (t and $800) <> 0 then Result := Result or $20000000;
  if (t and $80000) <> 0 then Result := Result or $10000000;
end;

function NbMsgFlags(f: Int64): Int64;
begin
  Result := f and $7;                                          { OOB PEEK DONTROUTE }
  if (f and $8) <> 0 then Result := Result or $20;             { CTRUNC }
  if (f and $20) <> 0 then Result := Result or $10;            { TRUNC }
  if (f and $40) <> 0 then Result := Result or $80;            { DONTWAIT }
  if (f and $80) <> 0 then Result := Result or $8;             { EOR }
  if (f and $100) <> 0 then Result := Result or $40;           { WAITALL }
  if (f and $4000) <> 0 then Result := Result or $400;         { NOSIGNAL }
  if (f and $40000000) <> 0 then Result := Result or $800;     { CMSG_CLOEXEC }
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

function SaToNb(src, len, dst: Int64): Int64;
var i, af: Int64;
begin
  if (src = 0) or (len < 2) then begin Result := -LX_EINVAL; Exit; end;
  if len > 128 then len := 128;
  for i := 0 to len - 1 do PByte(dst + i)^ := PByte(src + i)^;
  af := NbAf(PWord(src)^);
  if af < 0 then begin Result := -LX_EAFNOSUPPORT; Exit; end;
  if (af = 1) and (len > 106) then len := 106;                  { sun_path 108 -> 104 }
  PByte(dst)^ := Byte(len);
  PByte(dst + 1)^ := Byte(af);
  Result := len;
end;

procedure SaToLx(p, lenp: Int64);
begin
  if (p = 0) or (lenp = 0) or (PInteger(lenp)^ < 2) then Exit;
  PWord(p)^ := Word(LxAf(PByte(p + 1)^));
end;

procedure SockOptToNb(var level, name: Int64);
begin
  case level of
    1: begin                                                    { SOL_SOCKET }
         level := $FFFF;
         case name of
           1: name := $1; 2: name := $4; 3: name := $1008; 4: name := $1007;
           5: name := $10; 6: name := $20; 7: name := $1001; 8: name := $1002;
           9: name := $8; 10: name := $100; 13: name := $80; 15: name := $200;
           18: name := $1004; 19: name := $1003; 20: name := $100C; 21: name := $100B;
           30: name := $2;
         else level := -1;
         end;
       end;
    6: case name of                                             { IPPROTO_TCP }
         1, 2, 5, 6: ;
         4: name := 3;
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
    if level <> 17 then level := -1;
  end;
end;

function NbSockopt(isGet: Boolean; fd, level, name, val, lenp: Int64): Int64;
var lv, nm, r, e: Int64;
begin
  lv := level; nm := name;
  SockOptToNb(lv, nm);
  if lv < 0 then begin Result := -LX_ENOPROTOOPT; Exit; end;
  if not isGet then
  begin
    Result := Lx(NbSys(NB_SETSOCKOPT, fd, lv, nm, val, lenp, 0));
    Exit;
  end;
  r := NbSys(NB_GETSOCKOPT, fd, lv, nm, val, lenp, 0);
  if (r = 0) and (lv = $FFFF) and (nm = $1007) and (val <> 0) then
  begin
    e := PInteger(val)^;
    if (e >= 35) and (e <= 98) then PInteger(val)^ := ErrMap[Integer(e)];
  end;
  Result := Lx(r);
end;

function NbSockAddrCall(nr, fd, sa, len: Int64): Int64;
var b: array[0..15] of Int64; n: Int64;
begin
  n := SaToNb(sa, len, Int64(@b[0]));
  if n < 0 then Result := n
  else Result := Lx(NbSys(nr, fd, Int64(@b[0]), n, 0, 0, 0));
end;

function NbAccept4(fd, sa, lenp, flags: Int64): Int64;
var r: Int64;
begin
  r := NbSys(NB_PACCEPT, fd, sa, lenp, 0, NbSockType(flags) and not Int64($FF), 0);
  if r >= 0 then SaToLx(sa, lenp);
  Result := Lx(r);
end;

function NbSockName(nr, fd, sa, lenp: Int64): Int64;
var r: Int64;
begin
  r := NbSys(nr, fd, sa, lenp, 0, 0, 0);
  if r >= 0 then SaToLx(sa, lenp);
  Result := Lx(r);
end;

function NbSendto(fd, buf, len, flags, sa, salen: Int64): Int64;
var b: array[0..15] of Int64; n: Int64;
begin
  if sa = 0 then
  begin
    Result := Lx(NbSys(NB_SENDTO, fd, buf, len, NbMsgFlags(flags), 0, 0));
    Exit;
  end;
  n := SaToNb(sa, salen, Int64(@b[0]));
  if n < 0 then Result := n
  else Result := Lx(NbSys(NB_SENDTO, fd, buf, len, NbMsgFlags(flags), Int64(@b[0]), n));
end;

function NbRecvfrom(fd, buf, len, flags, sa, lenp: Int64): Int64;
var r: Int64;
begin
  r := NbSys(NB_RECVFROM, fd, buf, len, NbMsgFlags(flags), sa, lenp);
  if r >= 0 then SaToLx(sa, lenp);
  Result := Lx(r);
end;

procedure CmsgToNb(ctl, clen: Int64);
var p, l: Int64;
begin
  p := ctl;
  while (ctl <> 0) and (p + 16 <= ctl + clen) do
  begin
    l := PInt64(p)^;
    if l < 16 then Exit;
    PInteger(p)^ := Integer(l);
    PInteger(p + 4)^ := PInteger(p + 8)^;
    if PInteger(p + 4)^ = 1 then PInteger(p + 4)^ := $FFFF;
    PInteger(p + 8)^ := PInteger(p + 12)^;
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
    PInt64(p)^ := l;
    PInteger(p + 8)^ := Integer(lv);
    PInteger(p + 12)^ := Integer(ty);
    p := p + ((l + 7) and not Int64(7));
  end;
end;

function NbMsg(isSend: Boolean; fd, lm, flags: Int64): Int64;
var nm: array[0..5] of Int64;
    nb: array[0..15] of Int64;
    r, n: Int64;
begin
  nm[0] := PInt64(lm)^;
  nm[1] := PInteger(lm + 8)^;
  nm[2] := PInt64(lm + 16)^;
  nm[3] := PInt64(lm + 24)^ and $FFFFFFFF;
  nm[4] := PInt64(lm + 32)^;
  nm[5] := PInt64(lm + 40)^ and $FFFFFFFF;
  if isSend then
  begin
    if nm[0] <> 0 then
    begin
      n := SaToNb(nm[0], nm[1], Int64(@nb[0]));
      if n < 0 then begin Result := n; Exit; end;
      nm[0] := Int64(@nb[0]); nm[1] := n;
    end;
    CmsgToNb(nm[4], nm[5]);
    r := NbSys(NB_SENDMSG, fd, Int64(@nm[0]), NbMsgFlags(flags), 0, 0, 0);
    CmsgToLx(nm[4], nm[5]);
  end
  else
  begin
    r := NbSys(NB_RECVMSG, fd, Int64(@nm[0]), NbMsgFlags(flags), 0, 0, 0);
    if r >= 0 then
    begin
      if nm[0] <> 0 then
      begin
        PWord(nm[0])^ := Word(LxAf(PByte(nm[0] + 1)^));
        PInteger(lm + 8)^ := PInteger(Int64(@nm[1]))^;
      end;
      n := PInteger(Int64(@nm[5]))^ and $FFFFFFFF;
      CmsgToLx(nm[4], n);
      PInt64(lm + 40)^ := n;
      PInteger(lm + 48)^ := Integer(LxMsgFlags(PInteger(Int64(@nm[5]) + 4)^));
    end;
  end;
  Result := Lx(r);
end;

{ ---- termios: FreeBSD's tables (NetBSD's bits and c_cc indices are the same)
  except CRTSCTS $10000, and no IUTF8 (0: never mapped). }
const
  TIflLx: array[0..13] of Int64 = ($1,$2,$4,$8,$10,$20,$40,$80,$100,$400,$1000,$800,$2000,$4000);
  TIflNb: array[0..13] of Int64 = ($1,$2,$4,$8,$10,$20,$40,$80,$100,$200,$400,$800,$2000,0);
  TOflLx: array[0..5] of Int64 = ($1,$4,$1800,$8,$10,$20);
  TOflNb: array[0..5] of Int64 = ($1,$2,$4,$10,$20,$40);
  TCflLx: array[0..6] of Int64 = ($40,$80,$100,$200,$400,$800,$80000000);
  TCflNb: array[0..6] of Int64 = ($400,$800,$1000,$2000,$4000,$8000,$10000);
  TLflLx: array[0..13] of Int64 = ($1,$2,$8,$10,$20,$40,$80,$100,$200,$400,$800,$1000,$4000,$8000);
  TLflNb: array[0..13] of Int64 = ($80,$100,$8,$2,$4,$10,$80000000,$400000,$40,$20,$1,$800000,$20000000,$400);
  TCcMap: array[0..16] of Integer = (8,9,3,5,0,17,16,-1,12,13,10,1,6,15,4,14,2);
  TBaudLo: array[0..15] of Integer = (0,50,75,110,134,150,200,300,600,1200,1800,2400,4800,9600,19200,38400);
  TBaudHi: array[1..15] of Integer = (57600,115200,230400,460800,500000,576000,921600,
                                      1000000,1152000,1500000,2000000,2500000,3000000,3500000,4000000);

function MapBits(v: Int64; const src, dst: array of Int64): Int64;
var i: Integer;
begin
  Result := 0;
  for i := 0 to High(src) do
    if (src[i] <> 0) and (dst[i] <> 0) and ((v and src[i]) = src[i]) then Result := Result or dst[i];
end;

function SpeedToLx(n: Int64): Int64;
var i: Integer;
begin
  for i := 0 to 15 do if TBaudLo[i] = n then begin Result := i; Exit; end;
  for i := 1 to 15 do if TBaudHi[i] = n then begin Result := $1000 or i; Exit; end;
  Result := 15;
end;

function SpeedToNb(c: Int64): Int64;
begin
  c := c and $100F;
  if c <= 15 then Result := TBaudLo[Integer(c)]
  else if (c and $F) >= 1 then Result := TBaudHi[Integer(c and $F)]
  else Result := 38400;
end;

procedure TermiosToLx(nb, lx: Int64);
var i, ix: Integer; c: Byte; cf: Int64;
begin
  for i := 0 to 35 do PByte(lx + i)^ := 0;
  PInteger(lx)^ := Integer(MapBits(PInteger(nb)^, TIflNb, TIflLx));
  PInteger(lx + 4)^ := Integer(MapBits(PInteger(nb + 4)^, TOflNb, TOflLx));
  cf := MapBits(PInteger(nb + 8)^ and $FFFFFFFF, TCflNb, TCflLx);
  cf := cf or (((PInteger(nb + 8)^ shr 8) and 3) shl 4);        { CSIZE }
  cf := cf or SpeedToLx(PInteger(nb + 40)^);
  PInteger(lx + 8)^ := Integer(cf);
  PInteger(lx + 12)^ := Integer(MapBits(PInteger(nb + 12)^ and $FFFFFFFF, TLflNb, TLflLx));
  for i := 0 to 16 do
  begin
    ix := TCcMap[i];
    if ix < 0 then Continue;
    c := PByte(nb + 16 + ix)^;
    if (c = $FF) and (i <> 5) and (i <> 6) then c := 0;
    PByte(lx + 17 + i)^ := c;
  end;
end;

procedure TermiosToNb(lx, nb: Int64);
var i, ix: Integer; c: Byte; cf, sp: Int64;
begin
  for i := 0 to 43 do PByte(nb + i)^ := 0;
  for i := 0 to 19 do PByte(nb + 16 + i)^ := $FF;
  PInteger(nb)^ := Integer(MapBits(PInteger(lx)^, TIflLx, TIflNb));
  PInteger(nb + 4)^ := Integer(MapBits(PInteger(lx + 4)^, TOflLx, TOflNb));
  cf := PInteger(lx + 8)^ and $FFFFFFFF;
  PInteger(nb + 8)^ := Integer(MapBits(cf, TCflLx, TCflNb) or (((cf shr 4) and 3) shl 8));
  PInteger(nb + 12)^ := Integer(MapBits(PInteger(lx + 12)^, TLflLx, TLflNb));
  for i := 0 to 16 do
  begin
    ix := TCcMap[i];
    if ix < 0 then Continue;
    c := PByte(lx + 17 + i)^;
    if (c = 0) and (i <> 5) and (i <> 6) then c := $FF;
    PByte(nb + 16 + ix)^ := c;
  end;
  sp := SpeedToNb(cf);
  PInteger(nb + 36)^ := Integer(sp);
  PInteger(nb + 40)^ := Integer(sp);
end;

{ TIOCGPTN: TIOCPTSNAME fills struct ptmget (cfd, sfd, cn[1024], sn[1024]);
  sn is "/dev/pts/N". }
function NbPtyNum(fd, out: Int64): Int64;
var pg: array[0..257] of Int64;
    r, n, i: Int64;
    p: Int64;
begin
  r := NbSys(NB_IOCTL, fd, $48087448, Int64(@pg[0]), 0, 0, 0);
  if r < 0 then begin Result := Lx(r); Exit; end;
  p := Int64(@pg[0]) + 8 + 1024;
  n := 0; i := 9;                                               { past "/dev/pts/" }
  while (PByte(p + i)^ >= 48) and (PByte(p + i)^ <= 57) do
  begin
    n := n * 10 + PByte(p + i)^ - 48;
    Inc(i);
  end;
  PInteger(out)^ := Integer(n);
  Result := 0;
end;

{ fcntl record locks: Linux struct flock (type 0, whence 2, start 8, len 16,
  pid 24; F_RDLCK 0 / WRLCK 1 / UNLCK 2) <-> NetBSD (start 0, len 8, pid 16,
  type 20, whence 22; RDLCK 1 / UNLCK 2 / WRLCK 3). }
function NbLock(fd, cmd, lf: Int64): Int64;
var nf: array[0..2] of Int64;
    t, r: Int64;
begin
  t := PSmallInt(lf)^;
  case t of 0: t := 1; 1: t := 3; 2: t := 2; else begin Result := -LX_EINVAL; Exit; end; end;
  nf[0] := PInt64(lf + 8)^;
  nf[1] := PInt64(lf + 16)^;
  nf[2] := 0;
  PInteger(Int64(@nf[0]) + 16)^ := PInteger(lf + 24)^;
  PSmallInt(Int64(@nf[0]) + 20)^ := SmallInt(t);
  PSmallInt(Int64(@nf[0]) + 22)^ := PSmallInt(lf + 2)^;
  r := NbSys(NB_FCNTL, fd, cmd, Int64(@nf[0]), 0, 0, 0);
  if (r >= 0) and (cmd = 7) then
  begin
    t := PSmallInt(Int64(@nf[0]) + 20)^;
    case t of 1: t := 0; 3: t := 1; else t := 2; end;
    PSmallInt(lf)^ := SmallInt(t);
    PSmallInt(lf + 2)^ := PSmallInt(Int64(@nf[0]) + 22)^;
    PInt64(lf + 8)^ := nf[0];
    PInt64(lf + 16)^ := nf[1];
    PInteger(lf + 24)^ := PInteger(Int64(@nf[0]) + 16)^;
  end;
  Result := Lx(r);
end;

{ sched_getaffinity: report every online CPU (hw.ncpuonline), as an
  unrestricted Linux process sees. }
function NbGetAffinity(len, mask: Int64): Int64;
var mib: array[0..1] of Integer; n, sz, i: Int64; nc: Integer;
begin
  if len < 8 then begin Result := -LX_EINVAL; Exit; end;
  if len > 128 then len := 128;
  mib[0] := 6; mib[1] := 16;                                  { hw.ncpuonline }
  nc := 1; sz := 4;
  if NbSys(NB_SYSCTL, Int64(@mib[0]), 2, Int64(@nc), Int64(@sz), 0, 0) < 0 then nc := 1;
  for i := 0 to len - 1 do PByte(mask + i)^ := 0;
  n := nc;
  if n > len * 8 then n := len * 8;
  for i := 0 to n - 1 do
    PByte(mask + i div 8)^ := PByte(mask + i div 8)^ or (1 shl (i mod 8));
  Result := len;
end;

var
  NbPersona: Int64;

{ prctl: PR_SET_NAME / PR_GET_NAME through _lwp_setname / _lwp_getname. }
function NbPrctl(op, arg: Int64): Int64;
var b: array[0..15] of Byte; i: Integer; lid: Int64;
begin
  lid := NbSys(NB_LWP_SELF, 0, 0, 0, 0, 0, 0);
  case op of
    15: begin
          for i := 0 to 15 do b[i] := 0;
          i := 0;
          while (i < 15) and (PByte(arg + i)^ <> 0) do begin b[i] := PByte(arg + i)^; i := i + 1; end;
          Result := Lx(NbSys(NB_LWP_SETNAME, lid, Int64(@b[0]), 0, 0, 0, 0));
        end;
    16: begin
          for i := 0 to 15 do PByte(arg + i)^ := 0;
          Result := Lx(NbSys(NB_LWP_GETNAME, lid, arg, 16, 0, 0, 0));
          PByte(arg + 15)^ := 0;
        end;
  else
    Result := -LX_EINVAL;
  end;
end;

{ mmap with Linux's MAP_FIXED_NOREPLACE: NetBSD has no such flag. Map at the
  hint without FIXED and refuse (EEXIST) if the kernel put it elsewhere. }
function NbMmap(addr, len, prot, flags, fd, off: Int64): Int64;
var r: Int64;
begin
  if (flags and $100000) <> 0 then
  begin
    r := NbSys7(NB_MMAP, addr, len, prot, NbMmapFlags(flags and not Int64($10)), fd, 0, off);
    if (r >= 0) and (r <> addr) then
    begin
      NbSys(NB_MUNMAP, r, len, 0, 0, 0, 0);
      r := -LX_EEXIST;
    end;
    Result := Lx(r);
  end
  else
    Result := Lx(NbSys7(NB_MMAP, addr, len, prot, NbMmapFlags(flags), fd, 0, off));
end;

function NbOpenAt(dirfd, path, flags, mode: Int64): Int64;
begin
  if PathIs(path, ProcEnviron) then Result := NbProcEnviron
  else if PathIs(path, ProcHostname) then Result := NbProcHostname
  else
  begin
    Result := NbSys(NB_OPENAT, dirfd, path, NbOpenFlags(flags), mode, 0, 0);
    if (Result = -79) and ((flags and $20000) <> 0) then Result := -40    { O_NOFOLLOW on a symlink: EFTYPE -> ELOOP }
    else Result := Lx(Result);
  end;
end;

{ A NetBSD answer that is an error NUMBER returned as the value (clock_nanosleep,
  posix_fallocate) rather than through CF. }
function ValErr(r: Int64): Int64;
begin
  if r > 0 then Result := Lx(-r) else Result := Lx(r);
end;

{ ---- Threads -----------------------------------------------------------------
  clone(flags, stack, ptid, ctid, tls) with the stub's child entry in r9.
  The child is an LWP started from a ucontext: getcontext gives this thread's
  segment selectors, signal mask and FPU state (a Linux clone child inherits
  the last two); rip = the stub's child entry, rsp = the stage area, and
  _UC_TLSBASE sets the child's fs base to the TLS block the stub carved at
  stage+16, so it is right from the first instruction. LWP_DETACHED: nobody
  reaps a pxx thread, as on Linux. CHILD_CLEARTID: the ctid pointer is parked
  in the child's TLS block and acted on by its exit. }
function NbClone(flags, stack, ptid, ctid, cont: Int64): Int64;
var uc: array[0..97] of Int64;          { ucontext_t, 784 B }
    lid, r, mc: Int64;
begin
  if ((flags and $100) = 0) or (stack = 0) or (cont = 0) then
  begin
    Result := -LX_EINVAL; Exit;                           { only CLONE_VM threads }
  end;
  r := NbSys(NB_GETCONTEXT, Int64(@uc[0]), 0, 0, 0, 0, 0);
  if r < 0 then begin Result := Lx(r); Exit; end;
  if (flags and $00200000) <> 0 then                      { CLONE_CHILD_CLEARTID }
    PInt64(stack + 16 + 8 * NB_TLS_SLOT_CTID)^ := ctid
  else
    PInt64(stack + 16 + 8 * NB_TLS_SLOT_CTID)^ := 0;
  mc := Int64(@uc[0]) + NB_UC_MCONTEXT;
  PInt64(mc + 21 * 8)^ := cont;                           { _REG_RIP }
  PInt64(mc + 24 * 8)^ := stack;                          { _REG_RSP }
  PInt64(mc + 14 * 8)^ := 0;                              { _REG_RAX }
  PInt64(mc + 208)^ := stack + 16;                        { _mc_tlsbase }
  PInteger(@uc[0])^ := PInteger(@uc[0])^ or NB_UC_TLSBASE;
  uc[1] := 0;                                             { uc_link }
  lid := 0;
  r := NbSys(NB_LWP_CREATE, Int64(@uc[0]), NB_LWP_DETACHED, Int64(@lid), 0, 0, 0);
  if r < 0 then begin Result := Lx(r); Exit; end;
  lid := lid and $FFFFFFFF;
  if ((flags and $00100000) <> 0) and (ptid <> 0) then    { CLONE_PARENT_SETTID }
    PInteger(ptid)^ := Integer(lid);
  Result := lid;
end;

{ exit(2): this thread. The main LWP (always 1 on NetBSD) ends the process, as
  pxx's runtime expects. Another thread waits until its parent has stored the
  tid (it may get here first, and the store would resurrect a dead thread for
  its joiner), blocks every signal (a signal frame on a stack the joiner may
  be unmapping would kill the process), then clears and wakes. }
procedure NbExitThread(code: Int64);
var ctid: Int64;
    m: array[0..1] of Int64;
begin
  if NbSys(NB_LWP_SELF, 0, 0, 0, 0, 0, 0) = 1 then NbSys(NB_EXIT, code, 0, 0, 0, 0, 0);
  ctid := PInt64(Int64(__pxxTlsBase) + 8 * NB_TLS_SLOT_CTID)^;
  m[0] := -1; m[1] := -1;
  NbSys(NB_SIGPROCMASK, 1, Int64(@m[0]), 0, 0, 0, 0);    { SIG_BLOCK everything }
  if ctid <> 0 then
  begin
    while PInteger(ctid)^ = 0 do NbSys(NB_SCHED_YIELD, 0, 0, 0, 0, 0, 0);
    NbClearTidExitA(ctid, Int64(@NbExitArea[4]));
  end;
  NbSys(NB_LWP_EXIT, 0, 0, 0, 0, 0, 0);
end;

{ ---- the dispatcher ------------------------------------------------------- }

function PXXNbsdSyscall(nr, a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl;
var sb: array[0..18] of Int64;
    t: array[0..5] of Int64;
    r, f: Int64;
begin
  case Integer(nr) of
    0: begin
         { a 0-byte read of a directory is EISDIR on Linux and 0 here }
         if (a2 = 0) and (NbSys(NB_FSTAT, a0, Int64(@sb[0]), 0, 0, 0, 0) = 0) and
            ((PLongWord(Int64(@sb[0]) + 8)^ and $F000) = $4000) then Result := -21
         else Result := Lx(NbSys(NB_READ, a0, a1, a2, 0, 0, 0));
       end;
    1: Result := Lx(NbSys(NB_WRITE, a0, a1, a2, 0, 0, 0));
    2: Result := NbOpenAt(NB_AT_FDCWD, a0, a1, a2);
    257: Result := NbOpenAt(a0, a1, a2, a3);
    3: Result := Lx(NbSys(NB_CLOSE, a0, 0, 0, 0, 0, 0));
    4: Result := NbStatAt(NB_AT_FDCWD, a0, a1, 0);
    5: begin
         r := NbSys(NB_FSTAT, a0, Int64(@sb[0]), 0, 0, 0, 0);
         if r = 0 then StatToLinux(@sb[0], Pointer(a1));
         Result := Lx(r);
       end;
    6: Result := NbStatAt(NB_AT_FDCWD, a0, a1, $100);
    262: Result := NbStatAt(a0, a1, a2, a3);
    332: begin                                                  { statx }
           r := NbStatRaw(a0, a1, Int64(@sb[0]), a2);
           if r = 0 then StatToStatx(@sb[0], Pointer(a4));
           Result := Lx(r);
         end;
    7: Result := NbPoll(a0, a1, a2, 0, False);
    271: Result := NbPoll(a0, a1, a2, a3, True);
    8: Result := Lx(NbSys(NB_LSEEK, a0, 0, a1, a2, 0, 0));
    9: Result := NbMmap(a0, a1, a2, a3, a4, a5);
    10: Result := Lx(NbSys(NB_MPROTECT, a0, a1, a2, 0, 0, 0));
    11: Result := Lx(NbSys(NB_MUNMAP, a0, a1, 0, 0, 0, 0));
    12: Result := NbBrk(a0);
    13: Result := NbRtSigaction(a0, a1, a2);
    14: Result := NbRtSigprocmask(a0, a1, a2);
    127: begin                                                  { rt_sigpending }
           t[0] := 0; t[1] := 0;
           r := NbSys(NB_SIGPENDING, Int64(@t[0]), 0, 0, 0, 0, 0);
           if r = 0 then PInt64(a0)^ := MaskToLx(Int64(@t[0]));
           Result := Lx(r);
         end;
    128: Result := NbRtSigtimedwait(a0, a1, a2);
    130: begin                                                  { rt_sigsuspend }
           MaskToNb(PInt64(a0)^, Int64(@t[0]));
           Result := Lx(NbSys(NB_SIGSUSPEND, Int64(@t[0]), 0, 0, 0, 0, 0));
         end;
    34: begin                                                   { pause }
          t[0] := 0; t[1] := 0;
          NbSys(NB_SIGPROCMASK, 1, 0, Int64(@t[0]), 0, 0, 0);
          Result := Lx(NbSys(NB_SIGSUSPEND, Int64(@t[0]), 0, 0, 0, 0, 0));
        end;
    131: begin                                                  { sigaltstack: ss_size and ss_flags swap places }
           if a0 <> 0 then
           begin
             t[0] := PInt64(a0)^;
             t[1] := PInt64(a0 + 16)^;
             f := PInteger(a0 + 8)^;
             t[2] := 0;
             if (f and 1) <> 0 then t[2] := t[2] or 1;          { SS_ONSTACK }
             if (f and 2) <> 0 then t[2] := t[2] or 4;          { SS_DISABLE }
           end;
           r := 0;
           if a0 <> 0 then r := Int64(@t[0]);
           f := 0;
           if a1 <> 0 then f := Int64(@t[3]);
           r := NbSys(NB_SIGALTSTACK, r, f, 0, 0, 0, 0);
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
    16: case Integer(a1) of                                              { ioctl }
          $5401: begin                                          { TCGETS -> TIOCGETA }
                   r := NbSys(NB_IOCTL, a0, $402C7413, Int64(@sb[0]), 0, 0, 0);
                   if (r = 0) and (a2 <> 0) then TermiosToLx(Int64(@sb[0]), a2);
                   Result := Lx(r);
                 end;
          $5402, $5403, $5404: begin                            { TCSETS/W/F -> TIOCSETA/W/F }
                   TermiosToNb(a2, Int64(@sb[0]));
                   Result := Lx(NbSys(NB_IOCTL, a0, $802C7414 + (a1 - $5402), Int64(@sb[0]), 0, 0, 0));
                 end;
          $540B: begin                                          { TCFLSH -> TIOCFLUSH(FREAD/FWRITE) }
                   if (a2 < 0) or (a2 > 2) then Result := -LX_EINVAL
                   else
                   begin
                     t[0] := a2 + 1;
                     Result := Lx(NbSys(NB_IOCTL, a0, $80047410, Int64(@t[0]), 0, 0, 0));
                   end;
                 end;
          $5409: if a2 <> 0 then Result := Lx(NbSys(NB_IOCTL, a0, $2000745E, 0, 0, 0, 0))  { TCSBRK: drain }
                 else Result := 0;
          $540A: case Integer(a2) of                            { TCXONC }
                   0: Result := Lx(NbSys(NB_IOCTL, a0, $2000746F, 0, 0, 0, 0));
                   1: Result := Lx(NbSys(NB_IOCTL, a0, $2000746E, 0, 0, 0, 0));
                 else Result := 0;
                 end;
          $5427: Result := Lx(NbSys(NB_IOCTL, a0, $2000747B, 0, 0, 0, 0));   { TIOCSBRK }
          $5428: Result := Lx(NbSys(NB_IOCTL, a0, $2000747A, 0, 0, 0, 0));   { TIOCCBRK }
          -2147199952: Result := NbPtyNum(a0, a2);              { $80045430 TIOCGPTN }
          $40045431: begin                                      { TIOCSPTLCK: no lock; grant the slave }
                   r := NbSys(NB_IOCTL, a0, $20007447, 0, 0, 0, 0);   { TIOCGRANTPT }
                   if r < 0 then Result := Lx(r) else Result := 0;
                 end;
          $5413: Result := Lx(NbSys(NB_IOCTL, a0, $40087468, a2, 0, 0, 0));  { TIOCGWINSZ }
          $5414: Result := Lx(NbSys(NB_IOCTL, a0, $80087467, a2, 0, 0, 0));  { TIOCSWINSZ }
          $541B: Result := Lx(NbSys(NB_IOCTL, a0, $4004667F, a2, 0, 0, 0));  { FIONREAD }
          $540E: Result := Lx(NbSys(NB_IOCTL, a0, $20007461, 0, 0, 0, 0));   { TIOCSCTTY }
          $540F, $5410: begin                                   { TIOCGPGRP / TIOCSPGRP: ttys only }
                   r := NbSys(NB_IOCTL, a0, $402C7413, Int64(@sb[0]), 0, 0, 0);
                   if r = -25 then Result := -LX_ENOTTY
                   else if r < 0 then Result := Lx(r)
                   else if a1 = $540F then Result := Lx(NbSys(NB_IOCTL, a0, $40047477, a2, 0, 0, 0))
                   else Result := Lx(NbSys(NB_IOCTL, a0, $80047476, a2, 0, 0, 0));
                 end;
          $5411: Result := Lx(NbSys(NB_IOCTL, a0, $40047473, a2, 0, 0, 0));  { TIOCOUTQ }
          $5421: Result := Lx(NbSys(NB_IOCTL, a0, $8004667E, a2, 0, 0, 0));  { FIONBIO }
          $5422: Result := Lx(NbSys(NB_IOCTL, a0, $20007471, 0, 0, 0, 0));   { TIOCNOTTY }
          $5429: Result := Lx(NbSys(NB_IOCTL, a0, $40047463, a2, 0, 0, 0));  { TIOCGSID }
          $5450: Result := Lx(NbSys(NB_IOCTL, a0, $20006602, 0, 0, 0, 0));   { FIONCLEX }
          $5451: Result := Lx(NbSys(NB_IOCTL, a0, $20006601, 0, 0, 0, 0));   { FIOCLEX }
          $5452: Result := Lx(NbSys(NB_IOCTL, a0, $8004667D, a2, 0, 0, 0));  { FIOASYNC }
        else
          if NbSys(NB_FCNTL, a0, 1, 0, 0, 0, 0) < 0 then Result := -9
          else Result := -LX_ENOTTY;
        end;
    17: Result := Lx(NbSys(NB_PREAD, a0, a1, a2, 0, a3, 0));
    18: Result := Lx(NbSys(NB_PWRITE, a0, a1, a2, 0, a3, 0));
    19: Result := Lx(NbSys(NB_READV, a0, a1, a2, 0, 0, 0));
    20: Result := Lx(NbSys(NB_WRITEV, a0, a1, a2, 0, 0, 0));
    295: Result := Lx(NbSys(NB_PREADV, a0, a1, a2, 0, a3, 0));
    296: Result := Lx(NbSys(NB_PWRITEV, a0, a1, a2, 0, a3, 0));
    21: Result := Lx(NbSys(NB_ACCESS, a0, a1, 0, 0, 0, 0));
    22: Result := Lx(NbSys(NB_PIPE2, a0, 0, 0, 0, 0, 0));
    293: Result := Lx(NbSys(NB_PIPE2, a0, NbOpenFlags(a1), 0, 0, 0, 0));
    23: Result := Lx(NbSys(NB_SELECT, a0, a1, a2, a3, a4, 0));
    270: begin                                                  { pselect6: a5 -> (sigset*, size) }
           f := 0;
           if (a5 <> 0) and (PInt64(a5)^ <> 0) then
           begin
             MaskToNb(PInt64(PInt64(a5)^)^, Int64(@t[0]));
             f := Int64(@t[0]);
           end;
           Result := Lx(NbSys(NB_PSELECT, a0, a1, a2, a3, a4, f));
         end;
    24: Result := Lx(NbSys(NB_SCHED_YIELD, 0, 0, 0, 0, 0, 0));
    28: begin                                                   { madvise: advice is a hint }
          f := a2;
          if f = 8 then f := 6;                                 { MADV_FREE }
          if f > 6 then Result := 0
          else Result := Lx(NbSys(NB_MADVISE, a0, a1, f, 0, 0, 0));
        end;
    32: Result := Lx(NbSys(NB_DUP, a0, 0, 0, 0, 0, 0));
    33: Result := Lx(NbSys(NB_DUP2, a0, a1, 0, 0, 0, 0));
    292: if a0 = a1 then Result := -LX_EINVAL
         else Result := Lx(NbSys(NB_DUP3, a0, a1, NbOpenFlags(a2), 0, 0, 0));
    35: Result := Lx(NbSys(NB_NANOSLEEP, a0, a1, 0, 0, 0, 0));
    230: Result := ValErr(NbSys(NB_CLOCK_NANOSLEEP, NbClock(a0), a1, a2, a3, 0, 0));
    36: Result := Lx(NbSys(NB_GETITIMER, a0, a1, 0, 0, 0, 0));
    37: Result := NbAlarm(a0);
    38: Result := Lx(NbSys(NB_SETITIMER, a0, a1, a2, 0, 0, 0));
    39: Result := NbSys(NB_GETPID, 0, 0, 0, 0, 0, 0);
    57, 58: begin                                               { fork; vfork as fork }
          r := NbSys(NB_FORK, 0, 0, 0, 0, 0, 0);
          if (r >= 0) and (NbRdx <> 0) then r := 0;
          Result := Lx(r);
        end;
    59: Result := Lx(NbSys(NB_EXECVE, a0, a1, a2, 0, 0, 0));
    60: begin NbExitThread(a0); Result := 0; end;
    231: begin NbSys(NB_EXIT, a0, 0, 0, 0, 0, 0); Result := 0; end;      { exit_group }
    56: Result := NbClone(a0, a1, a2, a3, a5);
    61: Result := NbWait4(a0, a1, a2, a3);
    62: Result := Lx(NbSys(NB_KILL, a0, NbSig(a1), 0, 0, 0, 0));
    200: Result := Lx(NbSys(NB_LWP_KILL, a0, NbSig(a1), 0, 0, 0, 0));      { tkill }
    234: Result := Lx(NbSys(NB_LWP_KILL, a1, NbSig(a2), 0, 0, 0, 0));      { tgkill }
    63: Result := NbUname(a0);
    72: case Integer(a1) of                                              { fcntl }
          3: begin
               r := NbSys(NB_FCNTL, a0, 3, 0, 0, 0, 0);
               if r >= 0 then r := LxOpenFlags(r);
               Result := Lx(r);
             end;
          4: Result := Lx(NbSys(NB_FCNTL, a0, 4, NbOpenFlags(a2), 0, 0, 0));
          0, 1, 2: Result := Lx(NbSys(NB_FCNTL, a0, a1, a2, 0, 0, 0));
          5, 6, 7: Result := NbLock(a0, a1 + 2, a2);                    { F_GETLK/SETLK/SETLKW }
          8: Result := Lx(NbSys(NB_FCNTL, a0, 6, a2, 0, 0, 0));         { F_SETOWN }
          9: Result := Lx(NbSys(NB_FCNTL, a0, 5, 0, 0, 0, 0));          { F_GETOWN }
          1030: Result := Lx(NbSys(NB_FCNTL, a0, 12, a2, 0, 0, 0));     { F_DUPFD_CLOEXEC }
        else
          Result := -LX_EINVAL;
        end;
    73: Result := Lx(NbSys(NB_FLOCK, a0, a1, 0, 0, 0, 0));
    74: Result := Lx(NbSys(NB_FSYNC, a0, 0, 0, 0, 0, 0));
    75: Result := Lx(NbSys(NB_FDATASYNC, a0, 0, 0, 0, 0, 0));
    76: Result := Lx(NbSys(NB_TRUNCATE, a0, 0, a1, 0, 0, 0));
    77: Result := Lx(NbSys(NB_FTRUNCATE, a0, 0, a1, 0, 0, 0));
    79: begin                                                   { getcwd: Linux returns the length }
          r := NbSys(NB_GETCWD, a0, a1, 0, 0, 0, 0);
          if r >= 0 then r := StrLen0(a0) + 1;
          Result := Lx(r);
        end;
    80: Result := Lx(NbSys(NB_CHDIR, a0, 0, 0, 0, 0, 0));
    81: Result := Lx(NbSys(NB_FCHDIR, a0, 0, 0, 0, 0, 0));
    82: Result := Lx(NbSys(NB_RENAME, a0, a1, 0, 0, 0, 0));
    83: Result := Lx(NbSys(NB_MKDIR, a0, a1, 0, 0, 0, 0));
    84: Result := Lx(NbSys(NB_RMDIR, a0, 0, 0, 0, 0, 0));
    86: Result := Lx(NbSys(NB_LINK, a0, a1, 0, 0, 0, 0));
    87: Result := Lx(NbSys(NB_UNLINK, a0, 0, 0, 0, 0, 0));
    88: Result := Lx(NbSys(NB_SYMLINK, a0, a1, 0, 0, 0, 0));
    89: if PathIs(a0, ProcExe) then Result := NbProcExe(a1, a2)
        else if ProcFdNum(a0) >= 0 then Result := NbProcFd(ProcFdNum(a0), a1, a2)
        else Result := Lx(NbSys(NB_READLINK, a0, a1, a2, 0, 0, 0));
    267: if PathIs(a1, ProcExe) then Result := NbProcExe(a2, a3)
         else if ProcFdNum(a1) >= 0 then Result := NbProcFd(ProcFdNum(a1), a2, a3)
         else Result := Lx(NbSys(NB_READLINKAT, a0, a1, a2, a3, 0, 0));
    90: Result := Lx(NbSys(NB_CHMOD, a0, a1, 0, 0, 0, 0));
    91: Result := Lx(NbSys(NB_FCHMOD, a0, a1, 0, 0, 0, 0));
    92: Result := Lx(NbSys(NB_CHOWN, a0, a1, a2, 0, 0, 0));
    93: Result := Lx(NbSys(NB_FCHOWN, a0, a1, a2, 0, 0, 0));
    94: Result := Lx(NbSys(NB_LCHOWN, a0, a1, a2, 0, 0, 0));
    95: Result := NbSys(NB_UMASK, a0, 0, 0, 0, 0, 0);
    96: Result := Lx(NbSys(NB_GETTIMEOFDAY, a0, a1, 0, 0, 0, 0));
    97: Result := NbGetRlimit(a0, a1);
    160: Result := NbSetRlimit(a0, a1);
    302: begin                                                  { prlimit64, self only }
           if a0 <> 0 then begin Result := -LX_EINVAL; Exit; end;
           r := 0;
           if a3 <> 0 then r := NbGetRlimit(a1, a3);
           if (r = 0) and (a2 <> 0) then r := NbSetRlimit(a1, a2);
           Result := r;
         end;
    98: Result := Lx(NbSys(NB_GETRUSAGE, a0, a1, 0, 0, 0, 0));
    100: Result := NbTimes(a0);
    102: Result := NbSys(NB_GETUID, 0, 0, 0, 0, 0, 0);
    104: Result := NbSys(NB_GETGID, 0, 0, 0, 0, 0, 0);
    107: Result := NbSys(NB_GETEUID, 0, 0, 0, 0, 0, 0);
    108: Result := NbSys(NB_GETEGID, 0, 0, 0, 0, 0, 0);
    110: Result := NbSys(NB_GETPPID, 0, 0, 0, 0, 0, 0);
    105: Result := Lx(NbSys(NB_SETUID, a0, 0, 0, 0, 0, 0));
    106: Result := Lx(NbSys(NB_SETGID, a0, 0, 0, 0, 0, 0));
    109: Result := Lx(NbSys(NB_SETPGID, a0, a1, 0, 0, 0, 0));
    111: Result := NbSys(NB_GETPGRP, 0, 0, 0, 0, 0, 0);
    112: Result := Lx(NbSys(NB_SETSID, 0, 0, 0, 0, 0, 0));
    113: Result := Lx(NbSys(NB_SETREUID, a0, a1, 0, 0, 0, 0));
    114: Result := Lx(NbSys(NB_SETREGID, a0, a1, 0, 0, 0, 0));
    115: Result := Lx(NbSys(NB_GETGROUPS, a0, a1, 0, 0, 0, 0));
    116: Result := Lx(NbSys(NB_SETGROUPS, a0, a1, 0, 0, 0, 0));
    121: Result := Lx(NbSys(NB_GETPGID, a0, 0, 0, 0, 0, 0));
    124: Result := Lx(NbSys(NB_GETSID, a0, 0, 0, 0, 0, 0));
    140: begin                                                  { getpriority: Linux answers 20 - nice }
           r := NbSys(NB_GETPRIORITY, a0, a1, 0, 0, 0, 0);
           if NbErr then Result := Lx(r) else Result := 20 - r;
         end;
    141: Result := Lx(NbSys(NB_SETPRIORITY, a0, a1, a2, 0, 0, 0));
    158: case Integer(a0) of                                    { arch_prctl: pxx's TLS lives in fs here }
           $1001, $1002: Result := Lx(NbSys(NB_LWP_SETPRIVATE, a1, 0, 0, 0, 0, 0));
           $1003, $1004: begin
                           PInt64(a1)^ := NbSys(NB_LWP_GETPRIVATE, 0, 0, 0, 0, 0, 0);
                           Result := 0;
                         end;
         else
           Result := -LX_EINVAL;
         end;
    162: begin NbSys(NB_SYNC, 0, 0, 0, 0, 0, 0); Result := 0; end;
    186, 218: Result := NbSys(NB_LWP_SELF, 0, 0, 0, 0, 0, 0);   { gettid, set_tid_address }
    201: begin                                                  { time }
           NbSys(NB_CLOCK_GETTIME, 0, Int64(@t[0]), 0, 0, 0, 0);
           if a0 <> 0 then PInt64(a0)^ := t[0];
           Result := t[0];
         end;
    202: begin                                                  { futex: Linux's ops; val2 rides in timeout's slot }
           f := a1 and 127;
           if (f = 3) or (f = 4) or (f = 5) then
             Result := Lx(NbSys7(NB_FUTEX, a0, a1, a2, 0, a4, a3, a5))
           else
             Result := Lx(NbSys7(NB_FUTEX, a0, a1, a2, a3, a4, 0, a5));
         end;
    217: Result := NbGetdents(a0, a1, a2);
    227: Result := Lx(NbSys(NB_CLOCK_SETTIME, NbClock(a0), a1, 0, 0, 0, 0));
    228: Result := Lx(NbSys(NB_CLOCK_GETTIME, NbClock(a0), a1, 0, 0, 0, 0));
    229: Result := Lx(NbSys(NB_CLOCK_GETRES, NbClock(a0), a1, 0, 0, 0, 0));
    235: Result := Lx(NbSys(NB_UTIMES, a0, a1, 0, 0, 0, 0));
    280: if a1 = 0 then Result := Lx(NbSys(NB_FUTIMENS, a0, a2, 0, 0, 0, 0))   { UTIME_NOW/OMIT agree }
         else Result := Lx(NbSys(NB_UTIMENSAT, a0, a1, a2, NbAtFlags(a3), 0, 0));
    258: Result := Lx(NbSys(NB_MKDIRAT, a0, a1, a2, 0, 0, 0));
    259: Result := Lx(NbSys(NB_MKNODAT, a0, a1, a2, 0, a3, 0));
    260: Result := Lx(NbSys(NB_FCHOWNAT, a0, a1, a2, a3, NbAtFlags(a4), 0));
    263: begin                                                  { unlinkat }
           f := 0;
           if (a2 and $200) <> 0 then f := NB_AT_REMOVEDIR;
           Result := Lx(NbSys(NB_UNLINKAT, a0, a1, f, 0, 0, 0));
         end;
    264: Result := Lx(NbSys(NB_RENAMEAT, a0, a1, a2, a3, 0, 0));
    265: Result := Lx(NbSys(NB_LINKAT, a0, a1, a2, a3, NbAtFlags(a4), 0));
    266: Result := Lx(NbSys(NB_SYMLINKAT, a0, a1, a2, 0, 0, 0));
    268: Result := Lx(NbSys(NB_FCHMODAT, a0, a1, a2, NbAtFlags(a3), 0, 0));
    269: begin                                                  { faccessat }
           f := 0;
           if (a3 and $200) <> 0 then f := NB_AT_EACCESS;
           Result := Lx(NbSys(NB_FACCESSAT, a0, a1, a2, f, 0, 0));
         end;
    318: Result := Lx(NbSys(NB_GETRANDOM, a0, a1, a2, 0, 0, 0));   { GRND_* agree }
    41, 53: begin                                               { socket, socketpair }
          f := NbAf(a0);
          if (a1 and not Int64($8080F)) <> 0 then Result := -LX_EINVAL
          else if f < 0 then Result := -LX_EAFNOSUPPORT
          else if (a1 and $F) >= 11 then Result := -LX_EINVAL
          else if nr = 41 then Result := Lx(NbSys(NB_SOCKET, f, NbSockType(a1), a2, 0, 0, 0))
          else Result := Lx(NbSys(NB_SOCKETPAIR, f, NbSockType(a1), a2, a3, 0, 0));
        end;
    42: Result := NbSockAddrCall(NB_CONNECT, a0, a1, a2);
    49: Result := NbSockAddrCall(NB_BIND, a0, a1, a2);
    43: Result := NbAccept4(a0, a1, a2, 0);
    288: Result := NbAccept4(a0, a1, a2, a3);
    44: Result := NbSendto(a0, a1, a2, a3, a4, a5);
    45: Result := NbRecvfrom(a0, a1, a2, a3, a4, a5);
    46: Result := NbMsg(True, a0, a1, a2);
    47: Result := NbMsg(False, a0, a1, a2);
    48: Result := Lx(NbSys(NB_SHUTDOWN, a0, a1, 0, 0, 0, 0));
    50: Result := Lx(NbSys(NB_LISTEN, a0, a1, 0, 0, 0, 0));
    51: Result := NbSockName(NB_GETSOCKNAME, a0, a1, a2);
    52: Result := NbSockName(NB_GETPEERNAME, a0, a1, a2);
    54: Result := NbSockopt(False, a0, a1, a2, a3, a4);
    55: Result := NbSockopt(True, a0, a1, a2, a3, a4);
    213: Result := Lx(NbSys(NB_EPOLL_CREATE1, 0, 0, 0, 0, 0, 0));
    291: Result := Lx(NbSys(NB_EPOLL_CREATE1, NbFdFlags(a0), 0, 0, 0, 0, 0));
    233: Result := NbEpollCtl(a0, a1, a2, a3);
    232: Result := NbEpollWait(a0, a1, a2, a3, 0);
    281: Result := NbEpollWait(a0, a1, a2, a3, a4);
    283: Result := Lx(NbSys(NB_TIMERFD_CREATE, NbClock(a0), NbFdFlags(a1), 0, 0, 0, 0));
    286: Result := Lx(NbSys(NB_TIMERFD_SETTIME, a0, a1 and 1, a2, a3, 0, 0));
    287: Result := Lx(NbSys(NB_TIMERFD_GETTIME, a0, a1, 0, 0, 0, 0));
    284: Result := Lx(NbSys(NB_EVENTFD, a0, 0, 0, 0, 0, 0));
    290: begin                                                  { eventfd2: EFD_SEMAPHORE 1 -> 2 }
           f := NbFdFlags(a1);
           if (a1 and 1) <> 0 then f := f or 2;
           Result := Lx(NbSys(NB_EVENTFD, a0, f, 0, 0, 0, 0));
         end;
    137: Result := NbStatfs(False, a0, a1);
    138: Result := NbStatfs(True, a0, a1);
    135: begin                                                  { personality }
           Result := NbPersona;
           if a0 <> $FFFFFFFF then NbPersona := a0 and $FFFFFFFF;
         end;
    { sched_*: answered as Linux does for a SCHED_OTHER process. }
    142: if (a1 = 0) or (PInteger(a1)^ <> 0) then Result := -LX_EINVAL else Result := 0;
    143: if a1 = 0 then Result := -LX_EINVAL
         else begin PInteger(a1)^ := 0; Result := 0; end;
    144: case a1 and $3FFFFFFF of
           0, 3, 5: if (a2 = 0) or (PInteger(a2)^ <> 0) then Result := -LX_EINVAL else Result := 0;
           1, 2: Result := -1;                                  { EPERM }
         else Result := -LX_EINVAL;
         end;
    145: Result := 0;
    146: case a0 of 1, 2: Result := 99; 0, 3, 5: Result := 0; else Result := -LX_EINVAL; end;
    147: case a0 of 1, 2: Result := 1; 0, 3, 5: Result := 0; else Result := -LX_EINVAL; end;
    148: begin PInt64(a1)^ := 0; PInt64(a1 + 8)^ := 100000000; Result := 0; end;
    203: Result := 0;
    204: Result := NbGetAffinity(a1, a2);
    149: Result := Lx(NbSys(NB_MLOCK, a0, a1, 0, 0, 0, 0));
    150: Result := Lx(NbSys(NB_MUNLOCK, a0, a1, 0, 0, 0, 0));
    151: Result := Lx(NbSys(NB_MLOCKALL, a0 and 3, 0, 0, 0, 0, 0));
    152: Result := Lx(NbSys(NB_MUNLOCKALL, 0, 0, 0, 0, 0, 0));
    157: Result := NbPrctl(a0, a1);
    272: if a0 = 0 then Result := 0 else Result := -LX_EINVAL;  { unshare }
    285: if a1 <> 0 then Result := -95                          { fallocate: mode 0 only }
         else Result := ValErr(NbSys(NB_POSIX_FALLOCATE, a0, 0, a2, a3, 0, 0));
  else
    Result := -LX_ENOSYS;
  end;
end;

end.
