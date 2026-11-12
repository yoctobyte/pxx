unit obsdabi;

{ The Linux syscall ABI on an OpenBSD kernel -- EXPERIMENTAL (--os=openbsd).
  The same design as fbsdabi.pas (read its header first): every kernel entry
  pxx emits is written against Linux, funnels through the shared thunk, and
  arrives here with the Linux number and arguments; this unit maps the
  number, rewrites what differs, makes the real OpenBSD call from ObRawA, and
  maps OpenBSD's errno back to Linux's.

  WHAT IS OpenBSD-SPECIFIC
  - pinsyscalls: OpenBSD kills a syscall made from an address its
    PT_OPENBSD_SYSCALLS table does not pin for that number. The ELF writer
    (ObsdPinVA) pins EVERY number to the one `syscall` in ObRawA, so all
    kernel entry must come through here -- a raw `syscall` anywhere else dies
    with SIGABRT and a "PINS" line in ktrace.
  - TLS: OpenBSD userland cannot set the GS base; __set_tcb sets FS. Under
    --os=openbsd the compiler emits pxx's TLS accesses as fs: (TlsSegPrefix),
    and arch_prctl(ARCH_SET_GS) arrives here and becomes __set_tcb.
  - System call numbers are not a stable ABI across OpenBSD releases; these
    are 8.0's, and a binary is tied to the release it was built against.

  CONSTANTS ARE MEASURED: syscall numbers, errno, flags and clocks from
  OpenBSD 8.0 amd64's /usr/include; struct offsets from offsetof() compiled
  on that system (2026-11-12).

  CONTEXT RULES are fbsdabi's: no managed types, no heap, no exceptions, no
  RTL calls; ObRawA is the only kernel entry.

  PHASE 1: files, directories, memory, time, process basics, TLS, uname,
  rlimits, /proc/self/environ and /proc/self/exe, isatty. NOT YET: signals
  (rt_sigaction answers -ENOSYS, so a crash is not turned into an
  exception), sockets, termios beyond TCGETS, epoll, threads (the compiler
  refuses --threadsafe). Anything unmapped answers -ENOSYS. }

interface

function PXXObsdSyscall(nr, a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl;

implementation

const
  LX_ENOENT = 2;
  LX_EINVAL = 22;
  LX_ENOMEM = 12;
  LX_ENOTTY = 25;
  LX_ENOSYS = 38;

  { OpenBSD 8.0 amd64 syscall numbers (sys/syscall.h) }
  OB_EXIT = 1; OB_FORK = 2; OB_READ = 3; OB_WRITE = 4; OB_CLOSE = 6;
  OB_GETENTROPY = 7; OB_LINK = 9; OB_UNLINK = 10; OB_WAIT4 = 11; OB_CHDIR = 12;
  OB_FCHDIR = 13; OB_CHMOD = 15; OB_CHOWN = 16; OB_GETRUSAGE = 19;
  OB_GETPID = 20; OB_SETUID = 23; OB_GETUID = 24; OB_GETEUID = 25;
  OB_GETPPID = 39; OB_DUP = 41; OB_FSTATAT = 42; OB_GETEGID = 43;
  OB_GETGID = 47; OB_MMAP = 49; OB_FSTAT = 53; OB_IOCTL = 54; OB_SYMLINK = 57;
  OB_READLINK = 58; OB_EXECVE = 59; OB_UMASK = 60; OB_GETTIMEOFDAY = 67;
  OB_SELECT = 71; OB_MUNMAP = 73; OB_MPROTECT = 74; OB_MADVISE = 75;
  OB_GETPGRP = 81; OB_SETPGID = 82; OB_UTIMENSAT = 84; OB_CLOCK_GETTIME = 87;
  OB_CLOCK_GETRES = 89; OB_DUP2 = 90; OB_NANOSLEEP = 91; OB_FCNTL = 92;
  OB_FSYNC = 95; OB_SETPRIORITY = 96; OB_GETDENTS = 99; OB_GETPRIORITY = 100;
  OB_PIPE2 = 101; OB_DUP3 = 102; OB_KILL = 122; OB_FCHOWN = 123;
  OB_FCHMOD = 124; OB_READV = 120; OB_WRITEV = 121; OB_RENAME = 128;
  OB_FLOCK = 131; OB_MKDIR = 136; OB_RMDIR = 137; OB_SETSID = 147;
  OB_LSEEK = 166; OB_TRUNCATE = 167; OB_FTRUNCATE = 168; OB_PREAD = 169;
  OB_PWRITE = 170; OB_PREADV = 171; OB_PWRITEV = 172; OB_SETGID = 181;
  OB_GETRLIMIT = 194; OB_SETRLIMIT = 195; OB_SYSCTL = 202; OB_GETPGID = 207;
  OB_POLL = 252; OB_LCHOWN = 254; OB_GETSID = 255; OB_SCHED_YIELD = 298;
  OB_GETTHRID = 299; OB_GETCWD = 304; OB_FACCESSAT = 313; OB_FCHMODAT = 314;
  OB_FCHOWNAT = 315; OB_LINKAT = 317; OB_MKDIRAT = 318; OB_OPENAT = 321;
  OB_READLINKAT = 322; OB_RENAMEAT = 323; OB_SYMLINKAT = 324; OB_UNLINKAT = 325;
  OB_SET_TCB = 329; OB_GET_TCB = 330;

  OB_AT_FDCWD = -100;             { same value as Linux }
  OB_AT_EACCESS = $01; OB_AT_SYMLINK_NOFOLLOW = $02; OB_AT_SYMLINK_FOLLOW = $04;
  OB_AT_REMOVEDIR = $08;

  OB_MAP_FIXED = $10; OB_MAP_ANON = $1000; OB_MAP_STACK = $4000;
  OB_RLIM_INFINITY = $7FFFFFFFFFFFFFFF;

  OB_TIOCGETA = $402C7413; OB_TIOCGWINSZ = $40087468;
  OB_FIONREAD = $4004667F; OB_FIONBIO = $8004667E;

  { OpenBSD errno 35..95 -> Linux errno. 1..34 are the same on both. }
  ErrMap: array[35..95] of Integer = (
    11, 115, 114, 88, 89, 90, 91, 92, 93, 94,      { 35 EAGAIN .. 44 ESOCKTNOSUPPORT }
    95, 96, 97, 98, 99, 100, 101, 102, 103, 104,   { 45 EOPNOTSUPP .. 54 ECONNRESET }
    105, 106, 107, 108, 109, 110, 111, 40, 36, 112, { 55 ENOBUFS .. 64 EHOSTDOWN }
    113, 39, 11, 87, 122, 116, 66, 22, 22, 22,     { 65 EHOSTUNREACH .. 74 EPROGUNAVAIL }
    22, 22, 37, 38, 22, 13, 13, 22, 61, 84,        { 75 EPROGMISMATCH .. 84 EILSEQ }
    123, 124, 75, 125, 43, 42, 95, 74, 131, 130,   { 85 ENOMEDIUM .. 94 EOWNERDEAD }
    71);                                           { 95 EPROTO }

  { Linux signal 0..31 -> OpenBSD. 0 = no OpenBSD equivalent. }
  SigMap: array[0..31] of Integer = (
    0, 1, 2, 3, 4, 5, 6, 10, 8, 9, 30, 11, 31, 13, 14, 15,
    0, 20, 19, 17, 18, 21, 22, 16, 24, 25, 26, 27, 28, 23, 0, 12);

  { Linux RLIMIT_* 0..9 (CPU FSIZE DATA STACK CORE RSS NPROC NOFILE MEMLOCK AS)
    -> OpenBSD; -1 = none (RLIMIT_AS). }
  RlimMap: array[0..9] of Integer = (0, 1, 2, 3, 4, 5, 7, 8, 6, -1);

  BRK_RESERVE = Int64(1024) * 1024 * 1024;   { PROT_NONE address space, grown by mprotect }

var
  ObBrkBase, ObBrkCur, ObBrkTop: Int64;
  ObTmpSeq: Int64;

{ The ONE kernel entry, and the one address the pin table names. args ->
  [nr, a0..a5, rdx-out, cf-out]. OpenBSD reports an error with CF set and the
  positive errno in rax; the sbb/xor/sub trio negates rax exactly then. }
function ObRawA(args: Pointer): Int64; assembler;
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

var
  ObRdx: Int64;

function ObSys(nr, a0, a1, a2, a3, a4, a5: Int64): Int64;
var a: array[0..8] of Int64;
begin
  a[0] := nr; a[1] := a0; a[2] := a1; a[3] := a2;
  a[4] := a3; a[5] := a4; a[6] := a5; a[7] := 0; a[8] := 0;
  Result := ObRawA(@a[0]);
  ObRdx := a[7];
end;

{ -OpenBSD errno -> -Linux errno; anything else unchanged. }
function Lx(r: Int64): Int64;
begin
  if (r < -34) and (r >= -95) then Result := -ErrMap[Integer(-r)]
  else Result := r;
end;

function ObOpenFlags(f: Int64): Int64;
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
  if (f and $10000) <> 0 then r := r or $20000;       { O_DIRECTORY }
  if (f and $20000) <> 0 then r := r or $100;         { O_NOFOLLOW }
  if (f and $80000) <> 0 then r := r or $10000;       { O_CLOEXEC }
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
  if (f and $20000) <> 0 then r := r or $10000;
  if (f and $100) <> 0 then r := r or $20000;
  if (f and $10000) <> 0 then r := r or $80000;
  Result := r;
end;

{ Linux MAP_* -> OpenBSD. NOT a pass-through: Linux MAP_NORESERVE ($4000)
  is OpenBSD's MAP_STACK and Linux MAP_POPULATE ($8000) is MAP_CONCEAL. }
function ObMmapFlags(f: Int64): Int64;
var r: Int64;
begin
  r := f and $13;                                     { SHARED, PRIVATE, FIXED: same }
  if (f and $20) <> 0 then r := r or OB_MAP_ANON;
  if (f and $20000) <> 0 then r := r or OB_MAP_STACK;
  Result := r;
end;

function ObAtFlags(f: Int64): Int64;
var r: Int64;
begin
  r := 0;
  if (f and $100) <> 0 then r := r or OB_AT_SYMLINK_NOFOLLOW;
  if (f and $400) <> 0 then r := r or OB_AT_SYMLINK_FOLLOW;
  Result := r;
end;

{ Linux clocks: REALTIME 0, MONOTONIC 1, PROCESS_CPUTIME 2, THREAD_CPUTIME 3,
  MONOTONIC_RAW 4, REALTIME_COARSE 5, MONOTONIC_COARSE 6, BOOTTIME 7.
  OpenBSD: REALTIME 0, PROCESS_CPUTIME 2, MONOTONIC 3, THREAD_CPUTIME 4,
  UPTIME 5, BOOTTIME 6. }
function ObClock(id: Int64): Int64;
begin
  case Integer(id) of
    0: Result := 0;
    1: Result := 3;
    2: Result := 2;
    3: Result := 4;
    4: Result := 3;
    5: Result := 0;
    6: Result := 3;
    7: Result := 6;
  else
    Result := id;
  end;
end;

function ObSig(s: Int64): Int64;
begin
  if (s >= 0) and (s <= 31) then Result := SigMap[Integer(s)]
  else Result := s;
end;

{ OpenBSD struct stat (128 B) at ob -> Linux x86-64 struct stat (144 B). }
procedure StatToLinux(ob, lx: Pointer);
var i: Integer;
begin
  for i := 0 to 17 do PInt64(Int64(lx) + i * 8)^ := 0;
  PInt64(Int64(lx) + 0)^ := PLongWord(Int64(ob) + 4)^;              { st_dev }
  PInt64(Int64(lx) + 8)^ := PInt64(Int64(ob) + 8)^;                 { st_ino }
  PInt64(Int64(lx) + 16)^ := PLongWord(Int64(ob) + 16)^;            { st_nlink }
  PLongWord(Int64(lx) + 24)^ := PLongWord(Int64(ob) + 0)^;          { st_mode }
  PLongWord(Int64(lx) + 28)^ := PLongWord(Int64(ob) + 20)^;         { st_uid }
  PLongWord(Int64(lx) + 32)^ := PLongWord(Int64(ob) + 24)^;         { st_gid }
  PInt64(Int64(lx) + 40)^ := PLongWord(Int64(ob) + 28)^;            { st_rdev }
  PInt64(Int64(lx) + 48)^ := PInt64(Int64(ob) + 80)^;               { st_size }
  PInt64(Int64(lx) + 56)^ := PInteger(Int64(ob) + 96)^;             { st_blksize }
  PInt64(Int64(lx) + 64)^ := PInt64(Int64(ob) + 88)^;               { st_blocks }
  PInt64(Int64(lx) + 72)^ := PInt64(Int64(ob) + 32)^;               { st_atim }
  PInt64(Int64(lx) + 80)^ := PInt64(Int64(ob) + 40)^;
  PInt64(Int64(lx) + 88)^ := PInt64(Int64(ob) + 48)^;               { st_mtim }
  PInt64(Int64(lx) + 96)^ := PInt64(Int64(ob) + 56)^;
  PInt64(Int64(lx) + 104)^ := PInt64(Int64(ob) + 64)^;              { st_ctim }
  PInt64(Int64(lx) + 112)^ := PInt64(Int64(ob) + 72)^;
end;

{ OpenBSD struct stat -> Linux struct statx (256 B). }
procedure StatToStatx(ob, sx: Pointer);
var i: Integer;
procedure Ts(lxOff, obOff: Integer);
begin
  PInt64(Int64(sx) + lxOff)^ := PInt64(Int64(ob) + obOff)^;
  PLongWord(Int64(sx) + lxOff + 8)^ := LongWord(PInt64(Int64(ob) + obOff + 8)^);
end;
begin
  for i := 0 to 31 do PInt64(Int64(sx) + i * 8)^ := 0;
  PLongWord(Int64(sx) + 0)^ := $FFF;                                { BASIC_STATS | BTIME }
  PLongWord(Int64(sx) + 4)^ := LongWord(PInteger(Int64(ob) + 96)^); { blksize }
  PLongWord(Int64(sx) + 16)^ := PLongWord(Int64(ob) + 16)^;         { nlink }
  PLongWord(Int64(sx) + 20)^ := PLongWord(Int64(ob) + 20)^;         { uid }
  PLongWord(Int64(sx) + 24)^ := PLongWord(Int64(ob) + 24)^;         { gid }
  PWord(Int64(sx) + 28)^ := PWord(Int64(ob) + 0)^;                  { mode }
  PInt64(Int64(sx) + 32)^ := PInt64(Int64(ob) + 8)^;                { ino }
  PInt64(Int64(sx) + 40)^ := PInt64(Int64(ob) + 80)^;               { size }
  PInt64(Int64(sx) + 48)^ := PInt64(Int64(ob) + 88)^;               { blocks }
  Ts(64, 32);                                                       { atime }
  Ts(80, 112);                                                      { btime }
  Ts(96, 64);                                                       { ctime }
  Ts(112, 48);                                                      { mtime }
  PLongWord(Int64(sx) + 128)^ := (PLongWord(Int64(ob) + 28)^ shr 8) and $FF;  { rdev major }
  PLongWord(Int64(sx) + 132)^ := PLongWord(Int64(ob) + 28)^ and $FF;          { rdev minor }
  PLongWord(Int64(sx) + 136)^ := (PLongWord(Int64(ob) + 4)^ shr 8) and $FF;   { dev major }
  PLongWord(Int64(sx) + 140)^ := PLongWord(Int64(ob) + 4)^ and $FF;           { dev minor }
end;

{ OpenBSD dirents -> Linux dirent64, in place. The name moves from offset 24
  to 19 -- over d_namlen, so the length is read first. Each record keeps its
  d_reclen, which is still large enough. }
procedure DirentsToLinux(buf: Pointer; n: Int64);
var p, recLen, nameLen, i: Int64;
begin
  p := 0;
  while p < n do
  begin
    recLen := PWord(Int64(buf) + p + 16)^;
    nameLen := PByte(Int64(buf) + p + 19)^;
    if recLen = 0 then Exit;
    for i := 0 to nameLen do        { includes the NUL }
      PByte(Int64(buf) + p + 19 + i)^ := PByte(Int64(buf) + p + 24 + i)^;
    p := p + recLen;
  end;
end;

{ Linux brk on a PROT_NONE reservation grown with mprotect. OpenBSD has no
  brk syscall at all. Linux semantics: the new break on success, the old one
  on failure, never an error code. }
function ObBrk(want: Int64): Int64;
var top, r: Int64;
begin
  if ObBrkBase = 0 then
  begin
    r := ObSys(OB_MMAP, 0, BRK_RESERVE, 0, 2 or OB_MAP_ANON, -1, 0);   { PROT_NONE, PRIVATE|ANON }
    if r < 0 then begin Result := 0; Exit; end;
    ObBrkBase := r; ObBrkCur := r; ObBrkTop := r;
  end;
  Result := ObBrkCur;
  if (want < ObBrkBase) or (want > ObBrkBase + BRK_RESERVE) then Exit;
  if want > ObBrkTop then
  begin
    top := (want + $FFFF) and (not Int64($FFFF));
    if top > ObBrkBase + BRK_RESERVE then top := ObBrkBase + BRK_RESERVE;
    r := ObSys(OB_MPROTECT, ObBrkTop, top - ObBrkTop, 3, 0, 0, 0);
    if r < 0 then Exit;
    ObBrkTop := top;
  end;
  ObBrkCur := want;
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
  if ObSys(OB_SYSCTL, Int64(@mib[0]), 2, dst, Int64(@len), 0, 0) < 0 then len := 0;
  if len > cap - 1 then len := cap - 1;
  PByte(dst + len)^ := 0;
end;

{ Linux struct utsname: six 65-byte fields, built from sysctl as libc does. }
function ObUname(u: Int64): Int64;
var i: Integer;
const
  SysName: array[0..6] of Byte = (79, 112, 101, 110, 66, 83, 68);   { OpenBSD }
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

function ObGetRlimit(res, lim: Int64): Int64;
var r: Int64;
begin
  if (res < 0) or (res > 9) then begin Result := -LX_EINVAL; Exit; end;
  if RlimMap[Integer(res)] < 0 then
  begin
    PInt64(lim)^ := -1; PInt64(lim + 8)^ := -1;      { RLIMIT_AS: unlimited }
    Result := 0; Exit;
  end;
  r := ObSys(OB_GETRLIMIT, RlimMap[Integer(res)], lim, 0, 0, 0, 0);
  if r = 0 then
  begin
    if PInt64(lim)^ = OB_RLIM_INFINITY then PInt64(lim)^ := -1;
    if PInt64(lim + 8)^ = OB_RLIM_INFINITY then PInt64(lim + 8)^ := -1;
  end;
  Result := Lx(r);
end;

function ObSetRlimit(res, lim: Int64): Int64;
var v: array[0..1] of Int64;
begin
  if (res < 0) or (res > 9) then begin Result := -LX_EINVAL; Exit; end;
  if RlimMap[Integer(res)] < 0 then begin Result := 0; Exit; end;
  v[0] := PInt64(lim)^; v[1] := PInt64(lim + 8)^;
  if v[0] = -1 then v[0] := OB_RLIM_INFINITY;
  if v[1] = -1 then v[1] := OB_RLIM_INFINITY;
  Result := Lx(ObSys(OB_SETRLIMIT, RlimMap[Integer(res)], Int64(@v[0]), 0, 0, 0, 0));
end;

{ fstatat with Linux flags; AT_EMPTY_PATH ($1000) with "" is fstat(dirfd). }
function ObStatAt(dirfd, path, buf, flags: Int64): Int64;
var sb: array[0..15] of Int64; r: Int64;
begin
  if ((flags and $1000) <> 0) and ((path = 0) or (PByte(path)^ = 0)) then
    r := ObSys(OB_FSTAT, dirfd, Int64(@sb[0]), 0, 0, 0, 0)
  else
    r := ObSys(OB_FSTATAT, dirfd, path, Int64(@sb[0]), ObAtFlags(flags), 0, 0);
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

{ An fd that reads back len bytes from buf. OpenBSD has no anonymous shm and
  no memfd, so: a pipe when the bytes fit its buffer (16 KiB, no file system
  touched), else an unlinked file in /tmp. }
function ObDataFd(buf, len: Int64): Int64;
var fds: array[0..1] of Integer; name: array[0..47] of Byte;
    fd, v, i, k: Int64;
const Pre: array[0..10] of Byte = (47,116,109,112,47,46,112,120,120,101,110);   { /tmp/.pxxen }
begin
  if len <= 16384 then
  begin
    fds[0] := -1; fds[1] := -1;
    Result := ObSys(OB_PIPE2, Int64(@fds[0]), $10000, 0, 0, 0, 0);    { O_CLOEXEC }
    if Result < 0 then begin Result := Lx(Result); Exit; end;
    if len > 0 then ObSys(OB_WRITE, fds[1], buf, len, 0, 0, 0);
    ObSys(OB_CLOSE, fds[1], 0, 0, 0, 0, 0);
    Result := fds[0];
    Exit;
  end;
  for i := 0 to 10 do name[i] := Pre[i];
  k := 11;
  ObTmpSeq := ObTmpSeq + 1;
  v := ObSys(OB_GETPID, 0, 0, 0, 0, 0, 0) * 1000 + ObTmpSeq;
  while v > 0 do begin name[k] := 48 + (v mod 10); v := v div 10; k := k + 1; end;
  name[k] := 0;
  fd := ObSys(OB_OPENAT, OB_AT_FDCWD, Int64(@name[0]), 2 or $200 or $800 or $10000, 384, 0, 0);
  if fd < 0 then begin Result := Lx(fd); Exit; end;
  ObSys(OB_UNLINK, Int64(@name[0]), 0, 0, 0, 0, 0);
  ObSys(OB_WRITE, fd, buf, len, 0, 0, 0);
  ObSys(OB_LSEEK, fd, 0, 0, 0, 0, 0);
  Result := fd;
end;

{ kern.proc.args.<pid>.{argv,env}: a NULL-terminated pointer array (pointers
  into the same buffer) followed by the strings. Returns the mapping (size in
  sz) or a negative errno. }
function ObProcArgs(what: Integer; var sz: Int64): Int64;
var mib: array[0..3] of Integer; len, buf, r: Int64;
begin
  mib[0] := 1; mib[1] := 55;
  mib[2] := Integer(ObSys(OB_GETPID, 0, 0, 0, 0, 0, 0)); mib[3] := what;
  sz := 256 * 1024;
  buf := ObSys(OB_MMAP, 0, sz, 3, 2 or OB_MAP_ANON, -1, 0);
  if buf < 0 then begin Result := -LX_ENOMEM; Exit; end;
  len := sz;
  r := ObSys(OB_SYSCTL, Int64(@mib[0]), 4, buf, Int64(@len), 0, 0);
  if r < 0 then
  begin
    ObSys(OB_MUNMAP, buf, sz, 0, 0, 0, 0);
    Result := Lx(r); Exit;
  end;
  Result := buf;
end;

{ /proc/self/environ: "k=v\0k=v\0", from kern.proc.args.env. }
function ObProcEnviron: Int64;
var buf, sz, outp, n, p, s, i: Int64;
begin
  buf := ObProcArgs(3, sz);
  if buf < 0 then begin Result := buf; Exit; end;
  outp := ObSys(OB_MMAP, 0, sz, 3, 2 or OB_MAP_ANON, -1, 0);
  if outp < 0 then begin ObSys(OB_MUNMAP, buf, sz, 0, 0, 0, 0); Result := -LX_ENOMEM; Exit; end;
  n := 0; p := buf;
  while PInt64(p)^ <> 0 do
  begin
    s := PInt64(p)^;
    i := 0;
    while (PByte(s + i)^ <> 0) and (n < sz - 1) do
    begin
      PByte(outp + n)^ := PByte(s + i)^; n := n + 1; i := i + 1;
    end;
    PByte(outp + n)^ := 0; n := n + 1;
    p := p + 8;
  end;
  Result := ObDataFd(outp, n);
  ObSys(OB_MUNMAP, outp, sz, 0, 0, 0, 0);
  ObSys(OB_MUNMAP, buf, sz, 0, 0, 0, 0);
end;

{ readlink("/proc/self/exe"). OpenBSD keeps no path for a running image, so
  this is argv[0] made absolute with the cwd -- right whenever the program
  was started by a path (./x, /usr/bin/x), -ENOENT when it came from a PATH
  search. Linux semantics: no NUL, truncated, byte count returned. }
function ObProcExe(buf, cap: Int64): Int64;
var a, sz, s, n, m, i: Int64; tmp: array[0..1023] of Byte; hasSlash: Boolean;
begin
  a := ObProcArgs(1, sz);
  if a < 0 then begin Result := a; Exit; end;
  s := PInt64(a)^;
  hasSlash := False;
  if s <> 0 then
  begin
    i := 0;
    while PByte(s + i)^ <> 0 do begin if PByte(s + i)^ = 47 then hasSlash := True; i := i + 1; end;
  end;
  if (s = 0) or not hasSlash then
  begin
    ObSys(OB_MUNMAP, a, sz, 0, 0, 0, 0);
    Result := -LX_ENOENT; Exit;
  end;
  n := 0;
  if PByte(s)^ <> 47 then
  begin
    if ObSys(OB_GETCWD, Int64(@tmp[0]), 900, 0, 0, 0, 0) >= 0 then
    begin
      n := StrLen0(Int64(@tmp[0]));
      if (n > 0) and (tmp[n - 1] <> 47) then begin tmp[n] := 47; n := n + 1; end;
    end;
    if (PByte(s)^ = 46) and (PByte(s + 1)^ = 47) then s := s + 2;   { "./x" -> "x" }
  end;
  m := StrLen0(s);
  i := 0;
  while (i < m) and (n < 1023) do begin tmp[n] := PByte(s + i)^; n := n + 1; i := i + 1; end;
  ObSys(OB_MUNMAP, a, sz, 0, 0, 0, 0);
  if n > cap then n := cap;
  for i := 0 to n - 1 do PByte(buf + i)^ := tmp[i];
  Result := n;
end;

{ ---- the dispatcher ------------------------------------------------------- }

function PXXObsdSyscall(nr, a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl;
var sb: array[0..15] of Int64; t: array[0..3] of Int64; r, f, i, n: Int64;
begin
  case nr of
    0: Result := Lx(ObSys(OB_READ, a0, a1, a2, 0, 0, 0));
    1: Result := Lx(ObSys(OB_WRITE, a0, a1, a2, 0, 0, 0));
    2: if PathIs(a0, ProcEnviron) then Result := ObProcEnviron
       else Result := Lx(ObSys(OB_OPENAT, OB_AT_FDCWD, a0, ObOpenFlags(a1), a2, 0, 0));
    257: if PathIs(a1, ProcEnviron) then Result := ObProcEnviron
         else Result := Lx(ObSys(OB_OPENAT, a0, a1, ObOpenFlags(a2), a3, 0, 0));
    3: Result := Lx(ObSys(OB_CLOSE, a0, 0, 0, 0, 0, 0));
    4: Result := ObStatAt(OB_AT_FDCWD, a0, a1, 0);              { stat }
    5: begin                                                    { fstat }
         r := ObSys(OB_FSTAT, a0, Int64(@sb[0]), 0, 0, 0, 0);
         if r = 0 then StatToLinux(@sb[0], Pointer(a1));
         Result := Lx(r);
       end;
    6: Result := ObStatAt(OB_AT_FDCWD, a0, a1, $100);           { lstat }
    262: Result := ObStatAt(a0, a1, a2, a3);                    { newfstatat }
    332: begin                                                  { statx }
           if ((a2 and $1000) <> 0) and ((a1 = 0) or (PByte(a1)^ = 0)) then
             r := ObSys(OB_FSTAT, a0, Int64(@sb[0]), 0, 0, 0, 0)
           else
             r := ObSys(OB_FSTATAT, a0, a1, Int64(@sb[0]), ObAtFlags(a2), 0, 0);
           if r = 0 then StatToStatx(@sb[0], Pointer(a4));
           Result := Lx(r);
         end;
    7: Result := Lx(ObSys(OB_POLL, a0, a1, a2, 0, 0, 0));       { POLLIN..POLLNVAL bits are the same }
    8: Result := Lx(ObSys(OB_LSEEK, a0, a1, a2, 0, 0, 0));
    9: Result := Lx(ObSys(OB_MMAP, a0, a1, a2, ObMmapFlags(a3), a4, a5));
    10: Result := Lx(ObSys(OB_MPROTECT, a0, a1, a2, 0, 0, 0));
    11: Result := Lx(ObSys(OB_MUNMAP, a0, a1, 0, 0, 0, 0));
    12: Result := ObBrk(a0);
    16: begin                                                   { ioctl }
          case a1 of
            $5401: begin                                        { TCGETS: isatty and a plain struct }
                     r := ObSys(OB_IOCTL, a0, OB_TIOCGETA, Int64(@sb[0]), 0, 0, 0);
                     if r = 0 then
                       for i := 0 to 59 do PByte(a2 + i)^ := 0;
                     Result := Lx(r);
                   end;
            $5413: Result := Lx(ObSys(OB_IOCTL, a0, OB_TIOCGWINSZ, a2, 0, 0, 0));
            $541B: Result := Lx(ObSys(OB_IOCTL, a0, OB_FIONREAD, a2, 0, 0, 0));
            $5421: Result := Lx(ObSys(OB_IOCTL, a0, OB_FIONBIO, a2, 0, 0, 0));
          else
            Result := -LX_ENOTTY;
          end;
        end;
    17: Result := Lx(ObSys(OB_PREAD, a0, a1, a2, a3, 0, 0));
    18: Result := Lx(ObSys(OB_PWRITE, a0, a1, a2, a3, 0, 0));
    19: Result := Lx(ObSys(OB_READV, a0, a1, a2, 0, 0, 0));
    20: Result := Lx(ObSys(OB_WRITEV, a0, a1, a2, 0, 0, 0));
    21: Result := Lx(ObSys(OB_FACCESSAT, OB_AT_FDCWD, a0, a1, 0, 0, 0));
    269: begin                                                  { faccessat(2) }
           f := 0;
           if (a3 and $200) <> 0 then f := f or OB_AT_EACCESS;
           if (a3 and $100) <> 0 then f := f or OB_AT_SYMLINK_NOFOLLOW;
           Result := Lx(ObSys(OB_FACCESSAT, a0, a1, a2, f, 0, 0));
         end;
    439: begin
           f := 0;
           if (a3 and $200) <> 0 then f := f or OB_AT_EACCESS;
           if (a3 and $100) <> 0 then f := f or OB_AT_SYMLINK_NOFOLLOW;
           Result := Lx(ObSys(OB_FACCESSAT, a0, a1, a2, f, 0, 0));
         end;
    22: Result := Lx(ObSys(OB_PIPE2, a0, 0, 0, 0, 0, 0));
    293: Result := Lx(ObSys(OB_PIPE2, a0, ObOpenFlags(a1) and ($10000 or $4), 0, 0, 0, 0));
    23: Result := Lx(ObSys(OB_SELECT, a0, a1, a2, a3, a4, 0));
    24: Result := Lx(ObSys(OB_SCHED_YIELD, 0, 0, 0, 0, 0, 0));
    28: Result := Lx(ObSys(OB_MADVISE, a0, a1, a2, 0, 0, 0));
    32: Result := Lx(ObSys(OB_DUP, a0, 0, 0, 0, 0, 0));
    33: Result := Lx(ObSys(OB_DUP2, a0, a1, 0, 0, 0, 0));
    292: Result := Lx(ObSys(OB_DUP3, a0, a1, ObOpenFlags(a2) and $10000, 0, 0, 0));
    35: Result := Lx(ObSys(OB_NANOSLEEP, a0, a1, 0, 0, 0, 0));
    39: Result := ObSys(OB_GETPID, 0, 0, 0, 0, 0, 0);
    186: Result := ObSys(OB_GETTHRID, 0, 0, 0, 0, 0, 0);         { gettid }
    57, 58: begin                                               { fork, vfork }
              r := ObSys(OB_FORK, 0, 0, 0, 0, 0, 0);
              if (r >= 0) and (ObRdx <> 0) then r := 0;        { the child: rdx = 1 }
              Result := Lx(r);
            end;
    59: Result := Lx(ObSys(OB_EXECVE, a0, a1, a2, 0, 0, 0));
    60, 231: begin ObSys(OB_EXIT, a0, 0, 0, 0, 0, 0); Result := 0; end;
    61: Result := Lx(ObSys(OB_WAIT4, a0, a1, a2 and 3, a3, 0, 0));   { WNOHANG/WUNTRACED same; status words agree }
    62: begin
          f := ObSig(a1);
          if (f = 0) and (a1 <> 0) then Result := -LX_EINVAL
          else Result := Lx(ObSys(OB_KILL, a0, f, 0, 0, 0, 0));
        end;
    63: Result := ObUname(a0);
    72: begin                                                   { fcntl }
          case a1 of
            0, 1, 2: Result := Lx(ObSys(OB_FCNTL, a0, a1, a2, 0, 0, 0));
            3: begin
                 r := ObSys(OB_FCNTL, a0, 3, 0, 0, 0, 0);
                 if r < 0 then Result := Lx(r) else Result := LxOpenFlags(r);
               end;
            4: Result := Lx(ObSys(OB_FCNTL, a0, 4, ObOpenFlags(a2), 0, 0, 0));
            1030: Result := Lx(ObSys(OB_FCNTL, a0, 10, a2, 0, 0, 0));   { F_DUPFD_CLOEXEC }
          else
            Result := -LX_EINVAL;
          end;
        end;
    73: Result := Lx(ObSys(OB_FLOCK, a0, a1, 0, 0, 0, 0));
    74, 75: Result := Lx(ObSys(OB_FSYNC, a0, 0, 0, 0, 0, 0));
    76: Result := Lx(ObSys(OB_TRUNCATE, a0, a1, 0, 0, 0, 0));
    77: Result := Lx(ObSys(OB_FTRUNCATE, a0, a1, 0, 0, 0, 0));
    217: begin                                                  { getdents64 }
           r := ObSys(OB_GETDENTS, a0, a1, a2, 0, 0, 0);
           if r > 0 then DirentsToLinux(Pointer(a1), r);
           Result := Lx(r);
         end;
    79: begin                                                   { getcwd: Linux returns the length with the NUL }
          r := ObSys(OB_GETCWD, a0, a1, 0, 0, 0, 0);
          if r < 0 then Result := Lx(r) else Result := StrLen0(a0) + 1;
        end;
    80: Result := Lx(ObSys(OB_CHDIR, a0, 0, 0, 0, 0, 0));
    81: Result := Lx(ObSys(OB_FCHDIR, a0, 0, 0, 0, 0, 0));
    82: Result := Lx(ObSys(OB_RENAME, a0, a1, 0, 0, 0, 0));
    264: Result := Lx(ObSys(OB_RENAMEAT, a0, a1, a2, a3, 0, 0));
    316: if a4 <> 0 then Result := -LX_EINVAL
         else Result := Lx(ObSys(OB_RENAMEAT, a0, a1, a2, a3, 0, 0));
    83: Result := Lx(ObSys(OB_MKDIR, a0, a1, 0, 0, 0, 0));
    258: Result := Lx(ObSys(OB_MKDIRAT, a0, a1, a2, 0, 0, 0));
    84: Result := Lx(ObSys(OB_RMDIR, a0, 0, 0, 0, 0, 0));
    86: Result := Lx(ObSys(OB_LINK, a0, a1, 0, 0, 0, 0));
    265: Result := Lx(ObSys(OB_LINKAT, a0, a1, a2, a3, ObAtFlags(a4), 0));
    87: Result := Lx(ObSys(OB_UNLINK, a0, 0, 0, 0, 0, 0));
    263: begin                                                  { unlinkat }
           f := 0;
           if (a2 and $200) <> 0 then f := OB_AT_REMOVEDIR;
           Result := Lx(ObSys(OB_UNLINKAT, a0, a1, f, 0, 0, 0));
         end;
    88: Result := Lx(ObSys(OB_SYMLINK, a0, a1, 0, 0, 0, 0));
    266: Result := Lx(ObSys(OB_SYMLINKAT, a0, a1, a2, 0, 0, 0));
    89: if PathIs(a0, ProcExe) then Result := ObProcExe(a1, a2)
        else Result := Lx(ObSys(OB_READLINK, a0, a1, a2, 0, 0, 0));
    267: if PathIs(a1, ProcExe) then Result := ObProcExe(a2, a3)
         else Result := Lx(ObSys(OB_READLINKAT, a0, a1, a2, a3, 0, 0));
    90: Result := Lx(ObSys(OB_CHMOD, a0, a1, 0, 0, 0, 0));
    91: Result := Lx(ObSys(OB_FCHMOD, a0, a1, 0, 0, 0, 0));
    268: Result := Lx(ObSys(OB_FCHMODAT, a0, a1, a2, 0, 0, 0));
    92: Result := Lx(ObSys(OB_CHOWN, a0, a1, a2, 0, 0, 0));
    93: Result := Lx(ObSys(OB_FCHOWN, a0, a1, a2, 0, 0, 0));
    94: Result := Lx(ObSys(OB_LCHOWN, a0, a1, a2, 0, 0, 0));
    260: Result := Lx(ObSys(OB_FCHOWNAT, a0, a1, a2, a3, ObAtFlags(a4), 0));
    95: Result := ObSys(OB_UMASK, a0, 0, 0, 0, 0, 0);
    96: Result := Lx(ObSys(OB_GETTIMEOFDAY, a0, a1, 0, 0, 0, 0));
    97: Result := ObGetRlimit(a0, a1);
    160: Result := ObSetRlimit(a0, a1);
    302: begin                                                  { prlimit64(0, res, new, old) }
           if (a0 <> 0) and (a0 <> ObSys(OB_GETPID, 0, 0, 0, 0, 0, 0)) then
             Result := -LX_EINVAL
           else
           begin
             Result := 0;
             if a3 <> 0 then Result := ObGetRlimit(a1, a3);
             if (Result = 0) and (a2 <> 0) then Result := ObSetRlimit(a1, a2);
           end;
         end;
    98: Result := Lx(ObSys(OB_GETRUSAGE, a0, a1, 0, 0, 0, 0));  { struct rusage: same 144 B }
    102: Result := ObSys(OB_GETUID, 0, 0, 0, 0, 0, 0);
    104: Result := ObSys(OB_GETGID, 0, 0, 0, 0, 0, 0);
    107: Result := ObSys(OB_GETEUID, 0, 0, 0, 0, 0, 0);
    108: Result := ObSys(OB_GETEGID, 0, 0, 0, 0, 0, 0);
    105: Result := Lx(ObSys(OB_SETUID, a0, 0, 0, 0, 0, 0));
    106: Result := Lx(ObSys(OB_SETGID, a0, 0, 0, 0, 0, 0));
    109: Result := Lx(ObSys(OB_SETPGID, a0, a1, 0, 0, 0, 0));
    110: Result := ObSys(OB_GETPPID, 0, 0, 0, 0, 0, 0);
    111: Result := ObSys(OB_GETPGRP, 0, 0, 0, 0, 0, 0);
    112: Result := Lx(ObSys(OB_SETSID, 0, 0, 0, 0, 0, 0));
    121: Result := Lx(ObSys(OB_GETPGID, a0, 0, 0, 0, 0, 0));
    124: Result := Lx(ObSys(OB_GETSID, a0, 0, 0, 0, 0, 0));
    140: begin                                                  { getpriority: Linux returns 20 - nice }
           r := ObSys(OB_GETPRIORITY, a0, a1, 0, 0, 0, 0);
           if (r < 0) and (r >= -95) and (r <> -1) then Result := Lx(r)
           else Result := 20 - r;
         end;
    141: Result := Lx(ObSys(OB_SETPRIORITY, a0, a1, a2, 0, 0, 0));
    158: begin                                                  { arch_prctl }
           case a0 of
             $1001, $1002: Result := Lx(ObSys(OB_SET_TCB, a1, 0, 0, 0, 0, 0));   { SET_GS / SET_FS -> FS }
             $1003, $1004: begin                                { GET_FS / GET_GS }
                             PInt64(a1)^ := ObSys(OB_GET_TCB, 0, 0, 0, 0, 0, 0);
                             Result := 0;
                           end;
           else
             Result := -LX_EINVAL;
           end;
         end;
    201: begin                                                  { time }
           r := ObSys(OB_CLOCK_GETTIME, 0, Int64(@t[0]), 0, 0, 0, 0);
           if r < 0 then Result := Lx(r)
           else begin
             if a0 <> 0 then PInt64(a0)^ := t[0];
             Result := t[0];
           end;
         end;
    228: Result := Lx(ObSys(OB_CLOCK_GETTIME, ObClock(a0), a1, 0, 0, 0, 0));
    229: Result := Lx(ObSys(OB_CLOCK_GETRES, ObClock(a0), a1, 0, 0, 0, 0));
    230: if a1 = 0 then                                         { clock_nanosleep, relative }
           Result := Lx(ObSys(OB_NANOSLEEP, a2, a3, 0, 0, 0, 0))
         else
           Result := -LX_EINVAL;                                { TIMER_ABSTIME: not yet }
    280: begin                                                  { utimensat: UTIME_NOW/OMIT differ }
           if a2 <> 0 then
           begin
             for i := 0 to 3 do t[i] := PInt64(a2 + i * 8)^;
             for i := 0 to 1 do
               if t[i * 2 + 1] = $3FFFFFFF then t[i * 2 + 1] := -2      { UTIME_NOW }
               else if t[i * 2 + 1] = $3FFFFFFE then t[i * 2 + 1] := -1; { UTIME_OMIT }
             r := Int64(@t[0]);
           end
           else r := 0;
           Result := Lx(ObSys(OB_UTIMENSAT, a0, a1, r, ObAtFlags(a3), 0, 0));
         end;
    295: Result := Lx(ObSys(OB_PREADV, a0, a1, a2, a3, 0, 0));
    296: Result := Lx(ObSys(OB_PWRITEV, a0, a1, a2, a3, 0, 0));
    318: begin                                                  { getrandom: getentropy, 256 B per call }
           n := 0;
           while n < a1 do
           begin
             f := a1 - n;
             if f > 256 then f := 256;
             r := ObSys(OB_GETENTROPY, a0 + n, f, 0, 0, 0, 0);
             if r < 0 then begin n := Lx(r); Break; end;
             n := n + f;
           end;
           Result := n;
         end;
  else
    Result := -LX_ENOSYS;
  end;
end;

end.
