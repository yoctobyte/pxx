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

  DONE: files, directories, memory, time, process basics, TLS, uname,
  rlimits, /proc/self/environ and /proc/self/exe, isatty, signals (handlers,
  masks, the alt stack, kill/tgkill, itimers), threads (clone -> __tfork,
  thread exit, futex). NOT YET: sockets, termios beyond TCGETS, epoll.
  Anything unmapped answers -ENOSYS. }

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
  OB_SIGACTION = 46; OB_SIGPROCMASK = 48; OB_SIGPENDING = 52;
  OB_GETITIMER = 70; OB_SETITIMER = 69; OB_SIGSUSPEND = 111; OB_THRKILL = 119;
  OB_SIGALTSTACK = 288;
  OB_TFORK = 8; OB_FUTEX = 83; OB_THREXIT = 302;

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
  ObMainTid: Int64;          { the thread that first called clone; 0 = no threads yet }
  ObExitStack: Int64;        { the shared thread-exit stack (MAP_STACK) }
  ObExitLock: Integer;       { its lock; __threxit's notdead clears it }

const
  OB_EXIT_STACK_SIZE = 16384;
  { The TLS slot the clone stub leaves free for the child's ctid pointer on
    x86-64: defs.inc's TLS_SLOT_FS_ENTRY (14), i386's fs entry slot, never
    written on x86-64. fbsdabi uses the same slot for the same purpose. }
  OB_TLS_SLOT_CTID = 14;

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

{ __tfork(param, psize), with the child sent to cont. This is the one other
  syscall site the pin table names (SYS___tfork only, see ObsdPinVA): the
  child resumes after the instruction like a clone child, on its new stack,
  so it cannot come back through ObRawA's frame. r8 survives the syscall into
  the child (the kernel copies the parent's registers), and the child jumps
  to cont -- the clone stub's child entry -- with rsp = tf_stack. The parent
  gets the tid, or -errno. }
function ObTforkA(param, psize, cont: Int64): Int64; assembler;
{$asmMode intel}
asm
  mov r8, cont
  mov rdi, param
  mov rsi, psize
  mov eax, 8
  syscall
  jb obtf_fail
  test eax, eax
  jz obtf_child
  jmp obtf_done
obtf_child:
  push r8                 { jmp r8: the assembler takes label targets only }
  ret
obtf_fail:
  neg rax
obtf_done:
end;

{ The last steps of a non-main thread's exit: the CLONE_CHILD_CLEARTID work
  Linux's kernel does, which OpenBSD's does not (its __threxit clears a word
  but wakes nobody). The moment the tid word is zero a joiner may unmap this
  thread's stack, so the clear and the wakes run on a shared exit stack
  (MAP_STACK, mapped by the translator) taken under a spin lock -- and the
  lock word is __threxit's `notdead`, so the KERNEL releases it once this
  thread is past using that stack. Wakes go to both futex queues (a joiner may
  wait private or shared), through ObRawA called by address: registers and
  the exit stack only. Does not return. }
procedure ObThreadExitA(ctid, lock, top, raw: Int64); assembler;
{$asmMode intel}
asm
  mov r12, ctid
  mov r13, lock
  mov r14, top
  mov r15, raw
  jmp obte_spin
obte_raw:                 { call r15: the assembler takes label targets only }
  push r15
  ret
obte_spin:
  mov eax, 1
  xchg [r13], eax
  test eax, eax
  jz obte_got
  pause
  jmp obte_spin
obte_got:
  mov rsp, r14
  xor eax, eax
  mov [r12], eax
  sub rsp, 80
  mov qword [rsp], 83
  mov [rsp+8], r12
  mov qword [rsp+16], 2
  mov qword [rsp+24], $7FFFFFFF
  mov qword [rsp+32], 0
  mov qword [rsp+40], 0
  mov qword [rsp+48], 0
  mov rdi, rsp
  call obte_raw
  mov qword [rsp], 83
  mov [rsp+8], r12
  mov qword [rsp+16], 130
  mov qword [rsp+24], $7FFFFFFF
  mov qword [rsp+32], 0
  mov qword [rsp+40], 0
  mov qword [rsp+48], 0
  mov rdi, rsp
  call obte_raw
  mov qword [rsp], 302
  mov [rsp+8], r13
  mov rdi, rsp
  call obte_raw
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

{ ---- Signals ----------------------------------------------------------------
  fbsdabi's design (read its Signals header): the program's handler speaks
  the Linux SA_SIGINFO ABI and may REWRITE the saved RIP/RSP in the Linux
  ucontext it is given (the fault-to-raise path), so rt_sigaction installs
  ObSigEntry instead. ObSigEntry builds a Linux siginfo/ucontext, calls the
  program's handler, copies the registers back into OpenBSD's struct
  sigcontext (the handler's third argument on amd64; ucontext_t IS
  sigcontext there), and returns to the kernel's sigcode, which does
  sigreturn. The sigcontext's sc_cookie is never touched.

  What differs from FreeBSD:
  - sigset_t is ONE 32-bit word, and sigprocmask/sigpending/sigsuspend pass
    it by value in a register (the old mask comes back in rax).
  - siginfo is signo, CODE, errno (Linux: signo, errno, code). si_code values
    agree with Linux for faults (FPE_INTDIV 1, FPE_INTOVF 2 -- no FreeBSD
    swap); the user codes are 0, -1 (LWP), -2 (QUEUE), -3 (TIMER).
  - OpenBSD kills a process that makes a syscall with rsp outside a
    MAP_STACK mapping. pxx's alt stack is 32 KiB of BSS, but sigaltstack
    converts what it registers (see ObSigaltstack), so it passes through.
  Offsets measured with offsetof() on OpenBSD 8.0 (2026-11-12). }

const
  OB_SA_ONSTACK = $1; OB_SA_RESTART = $2; OB_SA_RESETHAND = $4;
  OB_SA_NOCLDSTOP = $8; OB_SA_NODEFER = $10; OB_SA_NOCLDWAIT = $20;
  OB_SA_SIGINFO = $40;
  LX_SA_NOCLDSTOP = $1; LX_SA_NOCLDWAIT = $2; LX_SA_SIGINFO = $4;
  LX_SA_ONSTACK = $08000000; LX_SA_RESTART = $10000000;
  LX_SA_NODEFER = $40000000; LX_SA_RESETHAND = $80000000;
  { Linux gregs[0..17] (R8 R9 R10 R11 R12 R13 R14 R15 RDI RSI RBP RBX RDX RAX
    RCX RSP RIP EFL) -> offset in OpenBSD struct sigcontext. }
  ObGregOff: array[0..17] of Integer = (
    32, 40, 48, 56, 64, 72, 80, 88, 0, 8, 96, 104, 16, 112, 24, 192, 168, 184);
  OB_SC_TRAPNO = 152; OB_SC_ERR = 160; OB_SC_FPSTATE = 208; OB_SC_MASK = 220;
  LX_UC_GREGS = 40;
  LX_UC_SIGMASK = 296;

var
  ObLxHandler: array[0..32] of Int64;   { by OpenBSD signal number }

function LxSig(s: Int64): Int64;
var i: Integer;
begin
  for i := 1 to 31 do
    if SigMap[i] = s then begin Result := i; Exit; end;
  Result := s;
end;

{ Linux 64-bit mask -> OpenBSD 32-bit mask. Signals with no OpenBSD
  equivalent (16, 30, the real-time range) drop out. }
function MaskToOb(lx: Int64): Int64;
var s, b: Int64;
begin
  Result := 0;
  for s := 1 to 31 do
    if ((lx shr (s - 1)) and 1) <> 0 then
    begin
      b := SigMap[Integer(s)];
      if (b >= 1) and (b <= 32) then Result := Result or (Int64(1) shl (b - 1));
    end;
end;

function MaskToLx(ob: Int64): Int64;
var b, s: Int64;
begin
  Result := 0;
  for b := 1 to 32 do
    if ((ob shr (b - 1)) and 1) <> 0 then
    begin
      s := LxSig(b);
      if (s >= 1) and (s <= 64) then Result := Result or (Int64(1) shl (s - 1));
    end;
end;

function SaFlagsToOb(f: Int64): Int64;
begin
  Result := 0;
  if (f and LX_SA_NOCLDSTOP) <> 0 then Result := Result or OB_SA_NOCLDSTOP;
  if (f and LX_SA_NOCLDWAIT) <> 0 then Result := Result or OB_SA_NOCLDWAIT;
  if (f and LX_SA_SIGINFO) <> 0 then Result := Result or OB_SA_SIGINFO;
  if (f and LX_SA_ONSTACK) <> 0 then Result := Result or OB_SA_ONSTACK;
  if (f and LX_SA_RESTART) <> 0 then Result := Result or OB_SA_RESTART;
  if (f and LX_SA_NODEFER) <> 0 then Result := Result or OB_SA_NODEFER;
  if (f and LX_SA_RESETHAND) <> 0 then Result := Result or OB_SA_RESETHAND;
end;

function SaFlagsToLx(f: Int64): Int64;
begin
  Result := 0;
  if (f and OB_SA_NOCLDSTOP) <> 0 then Result := Result or LX_SA_NOCLDSTOP;
  if (f and OB_SA_NOCLDWAIT) <> 0 then Result := Result or LX_SA_NOCLDWAIT;
  if (f and OB_SA_SIGINFO) <> 0 then Result := Result or LX_SA_SIGINFO;
  if (f and OB_SA_ONSTACK) <> 0 then Result := Result or LX_SA_ONSTACK;
  if (f and OB_SA_RESTART) <> 0 then Result := Result or LX_SA_RESTART;
  if (f and OB_SA_NODEFER) <> 0 then Result := Result or LX_SA_NODEFER;
  if (f and OB_SA_RESETHAND) <> 0 then Result := Result or LX_SA_RESETHAND;
end;

{ OpenBSD si_code -> Linux si_code. Fault codes (> 0) agree. }
function LxSiCode(c: Int64): Int64;
begin
  case c of
    -1: Result := -6;          { SI_LWP -> SI_TKILL }
    -2: Result := -1;          { SI_QUEUE }
    -3: Result := -2;          { SI_TIMER }
  else
    Result := c;
  end;
end;

{ OpenBSD siginfo_t (ob) -> Linux siginfo_t (lx, 128 bytes). }
procedure SiginfoToLx(ob, lx: Int64);
var i: Integer; c: Int64;
begin
  for i := 0 to 15 do PInt64(lx + i * 8)^ := 0;
  PInteger(lx)^ := Integer(LxSig(PInteger(ob)^));             { si_signo }
  PInteger(lx + 4)^ := PInteger(ob + 8)^;                     { si_errno }
  c := PInteger(ob + 4)^;
  PInteger(lx + 8)^ := Integer(LxSiCode(c));                  { si_code }
  if c <= 0 then
  begin
    PInteger(lx + 16)^ := PInteger(ob + 16)^;                 { si_pid }
    PInteger(lx + 20)^ := PInteger(ob + 20)^;                 { si_uid }
  end
  else
    PInt64(lx + 16)^ := PInt64(ob + 16)^;                     { si_addr }
end;

type
  TObLxHandler = procedure(sig, info, uc: Int64); cdecl;

{ The handler OpenBSD actually calls (SA_SIGINFO: rdi, rsi, rdx = sigcontext). }
procedure ObSigEntry(sig, info, sc: Int64); cdecl;
var li: array[0..15] of Int64;        { Linux siginfo_t, 128 B }
    lu: array[0..63] of Int64;        { Linux ucontext_t through uc_sigmask }
    i: Integer;
    h, ls: Int64;
begin
  if (sig < 1) or (sig > 32) then Exit;
  h := ObLxHandler[Integer(sig)];
  if h = 0 then Exit;
  ls := LxSig(sig);
  for i := 0 to 63 do lu[i] := 0;
  if info <> 0 then SiginfoToLx(info, Int64(@li[0]))
  else
  begin
    for i := 0 to 15 do li[i] := 0;
    PInteger(@li[0])^ := Integer(ls);
  end;
  if sc <> 0 then
  begin
    for i := 0 to 17 do
      lu[LX_UC_GREGS div 8 + i] := PInt64(sc + ObGregOff[i])^;
    lu[LX_UC_GREGS div 8 + 19] := PInt64(sc + OB_SC_ERR)^;              { ERR }
    lu[LX_UC_GREGS div 8 + 20] := PInt64(sc + OB_SC_TRAPNO)^;           { TRAPNO }
    if (info <> 0) and (PInteger(info + 4)^ > 0) then
      lu[LX_UC_GREGS div 8 + 22] := PInt64(info + 16)^;                 { CR2 = fault address }
    lu[LX_UC_SIGMASK div 8] := MaskToLx(PLongWord(sc + OB_SC_MASK)^);
    { An SSE floating-point trap: OpenBSD 8.0 reports FPE_FLTINV whatever the
      cause, and leaves sc_trapno 0 (both measured with
      test_float_exception_mask). Linux names the cause from the saved MXCSR,
      the flags that are set AND unmasked, in this priority order -- and
      FPC-style runtime errors depend on it. So a FLTINV with a saved FPU
      state is re-derived the Linux way; no set-and-unmasked flag leaves it. }
    if (sig = 8) and (info <> 0) and (PInteger(info + 4)^ = 7)
       and (PInt64(sc + OB_SC_FPSTATE)^ <> 0) then
    begin
      h := PLongWord(PInt64(sc + OB_SC_FPSTATE)^ + 24)^;          { fx_mxcsr }
      h := h and (not (h shr 7)) and $3F;
      if (h and $01) <> 0 then PInteger(Int64(@li[0]) + 8)^ := 7          { FPE_FLTINV }
      else if (h and $04) <> 0 then PInteger(Int64(@li[0]) + 8)^ := 3     { FPE_FLTDIV }
      else if (h and $08) <> 0 then PInteger(Int64(@li[0]) + 8)^ := 4     { FPE_FLTOVF }
      else if (h and $12) <> 0 then PInteger(Int64(@li[0]) + 8)^ := 5     { FPE_FLTUND }
      else if (h and $20) <> 0 then PInteger(Int64(@li[0]) + 8)^ := 6;    { FPE_FLTRES }
      h := ObLxHandler[Integer(sig)];
    end;
  end;
  if info <> 0 then TObLxHandler(h)(ls, Int64(@li[0]), Int64(@lu[0]))
  else TObLxHandler(h)(ls, 0, Int64(@lu[0]));
  if sc <> 0 then
    for i := 0 to 17 do
      PInt64(sc + ObGregOff[i])^ := lu[LX_UC_GREGS div 8 + i];
end;

function ObRtSigaction(sig, act, oact: Int64): Int64;
var oa, oo: array[0..1] of Int64;     { OpenBSD struct sigaction, 16 B }
    os, h, oldh, r: Int64;
begin
  os := ObSig(sig);
  if (os < 1) or (os > 32) then begin Result := -LX_EINVAL; Exit; end;
  oldh := ObLxHandler[Integer(os)];
  oa[0] := 0; oa[1] := 0; oo[0] := 0; oo[1] := 0;
  if act <> 0 then
  begin
    h := PInt64(act)^;
    PLongWord(Int64(@oa[0]) + 8)^ := LongWord(MaskToOb(PInt64(act + 24)^));
    PInteger(Int64(@oa[0]) + 12)^ := Integer(SaFlagsToOb(PInt64(act + 8)^));
    if (h = 0) or (h = 1) then oa[0] := h                 { SIG_DFL / SIG_IGN }
    else
    begin
      ObLxHandler[Integer(os)] := h;
      oa[0] := Int64(@ObSigEntry);
      PInteger(Int64(@oa[0]) + 12)^ := PInteger(Int64(@oa[0]) + 12)^ or OB_SA_SIGINFO;
    end;
    r := ObSys(OB_SIGACTION, os, Int64(@oa[0]), Int64(@oo[0]), 0, 0, 0);
    if r <> 0 then ObLxHandler[Integer(os)] := oldh
    else if (h = 0) or (h = 1) then ObLxHandler[Integer(os)] := 0;
  end
  else
    r := ObSys(OB_SIGACTION, os, 0, Int64(@oo[0]), 0, 0, 0);
  if (r = 0) and (oact <> 0) then
  begin
    if oo[0] = Int64(@ObSigEntry) then PInt64(oact)^ := oldh
    else PInt64(oact)^ := oo[0];
    PInt64(oact + 8)^ := SaFlagsToLx(PInteger(Int64(@oo[0]) + 12)^);
    PInt64(oact + 16)^ := 0;
    PInt64(oact + 24)^ := MaskToLx(PLongWord(Int64(@oo[0]) + 8)^);
  end;
  Result := Lx(r);
end;

{ The current mask, without changing it: SIG_BLOCK with an empty set. }
function ObCurMask: Int64;
begin
  Result := ObSys(OB_SIGPROCMASK, 1, 0, 0, 0, 0, 0) and $FFFFFFFF;
end;

function ObRtSigprocmask(how, nset, oset: Int64): Int64;
var r: Int64;
begin
  if (how < 0) or (how > 2) then begin Result := -LX_EINVAL; Exit; end;
  if nset <> 0 then r := ObSys(OB_SIGPROCMASK, how + 1, MaskToOb(PInt64(nset)^), 0, 0, 0, 0)
  else r := ObSys(OB_SIGPROCMASK, 1, 0, 0, 0, 0, 0);
  if r < 0 then begin Result := Lx(r); Exit; end;
  if oset <> 0 then PInt64(oset)^ := MaskToLx(r and $FFFFFFFF);
  Result := 0;
end;

{ sigaltstack: Linux stack_t is sp, flags(int), size; OpenBSD's is sp, size,
  flags; SS_DISABLE is 2 on Linux and 4 on OpenBSD. The program's buffer is
  registered as it is, BSS or not: OpenBSD converts a registered alt stack to
  MAP_STACK itself (measured 2026-11-12: a handler on pxx's BSS alt stack
  makes syscalls and lives, where any other non-MAP_STACK rsp is killed). }
function ObSigaltstack(ss, oss: Int64): Int64;
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
  r := ObSys(OB_SIGALTSTACK, pt, po, 0, 0, 0, 0);
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

function ObThrKill(tid, sig: Int64): Int64;
var os: Int64;
begin
  os := ObSig(sig);
  if (os = 0) and (sig <> 0) then begin Result := -LX_EINVAL; Exit; end;
  if tid = ObSys(OB_GETTHRID, 0, 0, 0, 0, 0, 0) then tid := 0;   { 0 = this thread }
  Result := Lx(ObSys(OB_THRKILL, tid, os, 0, 0, 0, 0));
end;

{ ---- Threads -----------------------------------------------------------------
  The clone stub's OpenBSD leg (thread_emit.inc) calls clone through the
  thunk, with the child's resume address in r9. Linux flags are honoured as
  far as pxx uses them: the stack, PARENT_SETTID (tf_tid), CHILD_CLEARTID
  (the ctid pointer is parked in the child's TLS block, which the stub has
  already carved at stage+16, and acted on by the thread's exit), and the
  TLS block itself (tf_tcb = the same block, so fs is right from the first
  instruction). }

function ObClone(flags, stack, ptid, ctid, cont: Int64): Int64;
var p: array[0..2] of Int64;
begin
  if ((flags and $100) = 0) or (stack = 0) or (cont = 0) then
  begin
    Result := -LX_EINVAL; Exit;                           { only CLONE_VM threads }
  end;
  if ObMainTid = 0 then ObMainTid := ObSys(OB_GETTHRID, 0, 0, 0, 0, 0, 0);
  if ObExitStack = 0 then
  begin
    Result := ObSys(OB_MMAP, 0, OB_EXIT_STACK_SIZE, 3, 2 or OB_MAP_ANON or OB_MAP_STACK, -1, 0);
    if Result < 0 then begin Result := -LX_ENOMEM; Exit; end;
    ObExitStack := Result;
  end;
  if (flags and $00200000) <> 0 then                      { CLONE_CHILD_CLEARTID }
    PInt64(stack + 16 + 8 * OB_TLS_SLOT_CTID)^ := ctid
  else
    PInt64(stack + 16 + 8 * OB_TLS_SLOT_CTID)^ := 0;
  p[0] := stack + 16;                                     { tf_tcb = the TLS block }
  if (flags and $00100000) <> 0 then p[1] := ptid         { CLONE_PARENT_SETTID }
  else p[1] := 0;
  p[2] := stack;                                          { tf_stack }
  Result := Lx(ObTforkA(Int64(@p[0]), 24, cont));
end;

{ exit(2): this thread. The main thread (or a program that never made one)
  ends the process, as pxx's runtime expects. }
procedure ObExitThread(code: Int64);
var ctid: Int64;
begin
  if (ObMainTid = 0) or (ObSys(OB_GETTHRID, 0, 0, 0, 0, 0, 0) = ObMainTid) then
    ObSys(OB_EXIT, code, 0, 0, 0, 0, 0);
  ctid := PInt64(Int64(__pxxTlsBase) + 8 * OB_TLS_SLOT_CTID)^;
  if ctid = 0 then ObSys(OB_THREXIT, 0, 0, 0, 0, 0, 0);
  { The kernel stores the tid through tf_tid; wait until it has, or the
    clear below would be undone and the joiner would wait for a dead thread. }
  while PInteger(ctid)^ = 0 do ObSys(OB_SCHED_YIELD, 0, 0, 0, 0, 0, 0);
  ObThreadExitA(ctid, Int64(@ObExitLock), ObExitStack + OB_EXIT_STACK_SIZE, Int64(@ObRawA));
end;

{ futex: Linux WAIT 0, WAKE 1, REQUEUE 3, WAIT_BITSET 9, WAKE_BITSET 10;
  OpenBSD WAIT 1, WAKE 2, REQUEUE 3; FUTEX_PRIVATE_FLAG is 128 on both.
  A bitset op with a full mask is the plain op. Timeouts are relative on
  both for WAIT (a BITSET wait's absolute timeout is refused). }
function ObFutex(uaddr, op, val, ts, uaddr2, val3: Int64): Int64;
var o, pf: Int64;
begin
  pf := op and 128;
  case op and 127 of
    0: o := 1;
    1: o := 2;
    3: o := 3;
    9: begin
         if (val3 and $FFFFFFFF) <> $FFFFFFFF then begin Result := -LX_EINVAL; Exit; end;
         if ts <> 0 then begin Result := -LX_EINVAL; Exit; end;
         o := 1;
       end;
    10: begin
          if (val3 and $FFFFFFFF) <> $FFFFFFFF then begin Result := -LX_EINVAL; Exit; end;
          o := 2;
        end;
  else
    Result := -LX_ENOSYS; Exit;
  end;
  if o = 3 then
    Result := Lx(ObSys(OB_FUTEX, uaddr, o or pf, val, ts, uaddr2, 0))   { ts = the requeue count }
  else
    Result := Lx(ObSys(OB_FUTEX, uaddr, o or pf, val, ts, 0, 0));
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
    60: begin ObExitThread(a0); Result := 0; end;
    231: begin ObSys(OB_EXIT, a0, 0, 0, 0, 0, 0); Result := 0; end;
    56: Result := ObClone(a0, a1, a2, a3, a5);
    202: Result := ObFutex(a0, a1, a2, a3, a4, a5);
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
    13: Result := ObRtSigaction(a0, a1, a2);
    14: Result := ObRtSigprocmask(a0, a1, a2);
    127: begin                                                  { rt_sigpending }
           r := ObSys(OB_SIGPENDING, 0, 0, 0, 0, 0, 0);
           if r < 0 then Result := Lx(r)
           else begin PInt64(a0)^ := MaskToLx(r and $FFFFFFFF); Result := 0; end;
         end;
    130: Result := Lx(ObSys(OB_SIGSUSPEND, MaskToOb(PInt64(a0)^), 0, 0, 0, 0, 0));
    34: Result := Lx(ObSys(OB_SIGSUSPEND, ObCurMask, 0, 0, 0, 0, 0));   { pause }
    131: Result := ObSigaltstack(a0, a1);
    200: Result := ObThrKill(a0, a1);                           { tkill }
    234: if (a0 <> ObSys(OB_GETPID, 0, 0, 0, 0, 0, 0)) and (a0 > 0) then
           Result := -3                                         { ESRCH: not our process }
         else Result := ObThrKill(a1, a2);                      { tgkill }
    36: Result := Lx(ObSys(OB_GETITIMER, a0, a1, 0, 0, 0, 0)); { struct itimerval: same }
    38: Result := Lx(ObSys(OB_SETITIMER, a0, a1, a2, 0, 0, 0));
    37: begin                                                   { alarm }
          for i := 0 to 3 do t[i] := 0;
          t[2] := a0;
          for i := 0 to 3 do sb[i] := 0;
          r := ObSys(OB_SETITIMER, 0, Int64(@t[0]), Int64(@sb[0]), 0, 0, 0);
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
