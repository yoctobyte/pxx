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
  basics, TLS, and the two /proc files the runtime reads (environ, exe). NOT YET: signal handler installation (rt_sigaction is accepted
  and ignored, so a hardware fault kills the process instead of raising), the
  signal mask, threads (clone -> ENOSYS), futex, sockets, file locks, and
  termios beyond isatty. Anything unmapped answers -ENOSYS. }

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

{ The kernel entry. args -> [nr, a0..a5, rdx-out]. FreeBSD reports an error
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
  xor rax, rcx
  sub rax, rcx
  pop r12
end;

var
  FbRdx: Int64;

function FbSys(nr, a0, a1, a2, a3, a4, a5: Int64): Int64;
var a: array[0..7] of Int64;
begin
  a[0] := nr; a[1] := a0; a[2] := a1; a[3] := a2;
  a[4] := a3; a[5] := a4; a[6] := a5; a[7] := 0;
  Result := FbRawA(@a[0]);
  FbRdx := a[7];
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
  else Result := s;                                   { realtime range: pass through }
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

{ An anonymous shared-memory fd holding kern.proc.env, rewound: reads see
  what /proc/self/environ would hold. The buffer is a scratch mapping, not
  the heap -- this can run before the heap exists. }
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
  fd := FbSys(FB_SHM_OPEN2, 1, 2 or $100000, 384, 0, 0, 0);   { SHM_ANON, O_RDWR|O_CLOEXEC, 0600 }
  if (r >= 0) and (fd >= 0) and (len > 0) then
  begin
    FbSys(FB_FTRUNCATE, fd, len, 0, 0, 0, 0);   { a shm object does not grow on write }
    FbSys(FB_WRITE, fd, buf, len, 0, 0, 0);
    FbSys(FB_LSEEK, fd, 0, 0, 0, 0, 0);
  end;
  FbSys(FB_MUNMAP, buf, size, 0, 0, 0, 0);
  if fd < 0 then Result := Lx(fd) else Result := fd;
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

function PXXFbsdSyscall(nr, a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl;
var sb: array[0..27] of Int64;
    t: array[0..5] of Int64;
    r, f: Int64;
    i: Integer;
begin
  case Integer(nr) of
    0: Result := Lx(FbSys(FB_READ, a0, a1, a2, 0, 0, 0));
    1: Result := Lx(FbSys(FB_WRITE, a0, a1, a2, 0, 0, 0));
    2: if PathIs(a0, ProcEnviron) then Result := FbProcEnviron
       else Result := Lx(FbSys(FB_OPENAT, FB_AT_FDCWD, a0, FbOpenFlags(a1), a2, 0, 0));
    3: Result := Lx(FbSys(FB_CLOSE, a0, 0, 0, 0, 0, 0));
    4: Result := FbStatAt(FB_AT_FDCWD, a0, a1, 0);              { stat }
    5: begin                                                    { fstat }
         r := FbSys(FB_FSTAT, a0, Int64(@sb[0]), 0, 0, 0, 0);
         if r = 0 then StatToLinux(@sb[0], Pointer(a1));
         Result := Lx(r);
       end;
    6: Result := FbStatAt(FB_AT_FDCWD, a0, a1, $100);           { lstat }
    7: Result := Lx(FbSys(FB_POLL, a0, a1, a2, 0, 0, 0));
    8: Result := Lx(FbSys(FB_LSEEK, a0, a1, a2, 0, 0, 0));
    9: Result := Lx(FbSys(FB_MMAP, a0, a1, a2, FbMmapFlags(a3), a4, a5));
    10: Result := Lx(FbSys(FB_MPROTECT, a0, a1, a2, 0, 0, 0));
    11: Result := Lx(FbSys(FB_MUNMAP, a0, a1, 0, 0, 0, 0));
    12: Result := FbBrk(a0);
    13: begin                                                   { rt_sigaction: phase 1 ignores }
          if a2 <> 0 then begin PInt64(a2)^ := 0; PInt64(a2 + 8)^ := 0; PInt64(a2 + 16)^ := 0; PInt64(a2 + 24)^ := 0; end;
          Result := 0;
        end;
    14: begin                                                   { rt_sigprocmask: phase 1 ignores }
          if a2 <> 0 then PInt64(a2)^ := 0;
          Result := 0;
        end;
    16: case Integer(a1) of                                              { ioctl }
          $5401: begin                                          { TCGETS: isatty only }
                   r := FbSys(FB_IOCTL, a0, $402C7413, Int64(@sb[0]), 0, 0, 0);
                   if (r = 0) and (a2 <> 0) then for i := 0 to 59 do PByte(a2 + i)^ := 0;
                   Result := Lx(r);
                 end;
          $5402, $5403, $5404: Result := 0;                     { TCSETS*: not yet }
          $5413: Result := Lx(FbSys(FB_IOCTL, a0, $40087468, a2, 0, 0, 0));  { TIOCGWINSZ }
          $541B: Result := Lx(FbSys(FB_IOCTL, a0, $4004667F, a2, 0, 0, 0));  { FIONREAD }
        else
          Result := -LX_ENOTTY;
        end;
    17: Result := Lx(FbSys(FB_PREAD, a0, a1, a2, a3, 0, 0));
    18: Result := Lx(FbSys(FB_PWRITE, a0, a1, a2, a3, 0, 0));
    19: Result := Lx(FbSys(FB_READV, a0, a1, a2, 0, 0, 0));
    20: Result := Lx(FbSys(FB_WRITEV, a0, a1, a2, 0, 0, 0));
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
    60, 231: begin FbSys(FB_EXIT, a0, 0, 0, 0, 0, 0); Result := 0; end;
    61: Result := Lx(FbSys(FB_WAIT4, a0, a1, a2, a3, 0, 0));
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
         else Result := Lx(FbSys(FB_OPENAT, a0, a1, FbOpenFlags(a2), a3, 0, 0));
    258: Result := Lx(FbSys(FB_MKDIRAT, a0, a1, a2, 0, 0, 0));
    262: Result := FbStatAt(a0, a1, a2, a3);                    { newfstatat }
    263: begin                                                  { unlinkat }
           f := 0;
           if (a2 and $200) <> 0 then f := FB_AT_REMOVEDIR;
           Result := Lx(FbSys(FB_UNLINKAT, a0, a1, f, 0, 0, 0));
         end;
    264: Result := Lx(FbSys(FB_RENAMEAT, a0, a1, a2, a3, 0, 0));
    267: if PathIs(a1, ProcExe) then Result := FbProcExe(a2, a3)
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
    332: begin                                                  { statx }
           r := FbSys(FB_FSTATAT, a0, a1, Int64(@sb[0]), FbAtFlags(a2), 0, 0);
           if r = 0 then StatToStatx(@sb[0], Pointer(a4));
           Result := Lx(r);
         end;
  else
    Result := -LX_ENOSYS;
  end;
end;

end.
