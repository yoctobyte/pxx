unit minixabi;

{ The Linux i386 syscall ABI on a Minix 3.4 system -- EXPERIMENTAL
  (--os=minix). The design of fbsdabi.pas (read its header first): every
  kernel entry pxx emits is written against Linux, and under this --os each
  int $0x80 is a call to the shared thunk (EmitInt80, EmitLibcSyscallThunk),
  which hands this unit the Linux number and arguments.

  What is Minix's own: there are no system calls. A Minix process talks to
  servers -- PM (processes, signals, time), VFS (files), VM (memory) -- by
  sending each a 64-byte message and waiting for the answer in the same
  buffer: int $0x21 with eax = the server's endpoint, ebx = the message,
  ecx = SENDREC (MxIpc below, the only kernel entry). A message is m_source
  at 0, m_type at 4 (the call number going out; the result, or -errno,
  coming back) and a per-call payload from 8. So each Linux call is mapped
  to a server, a call number and a payload layout.

  CONSTANTS ARE MEASURED: call numbers and message layouts from the Minix
  3.4.0rc6 sources (minix/include/minix/callnr.h, com.h, ipc.h) and the libc
  wrappers that fill them; errno, flags and struct offsets from the installed
  system's /usr/include and offsetof() compiled on it (2026-11-13). errno
  numbers are NetBSD's.

  CONTEXT RULES are fbsdabi's: no managed types, no heap, no exceptions, no
  RTL calls (no Int64 division either: i386 would call a helper). MxIpc is
  the only kernel entry.

  PHASE 1 SCOPE: files, directories, memory, time, process basics, the
  environment. No threads (--threadsafe is refused), no signal delivery (the
  runtime's handler installs answer 0 and are not made), no sockets.
  Anything unmapped answers -ENOSYS. }

interface

function PXXMinixSyscall(nr, a0, a1, a2, a3, a4, a5: LongInt): LongInt; cdecl;

implementation

const
  LX_ENOENT = 2;
  LX_EBADF = 9;
  LX_EFAULT = 14;
  LX_ENOMEM = 12;
  LX_EINVAL = 22;
  LX_ENOTTY = 25;
  LX_ERANGE = 34;
  LX_ENOSYS = 38;
  LX_EOVERFLOW = 75;

  LX_AT_FDCWD = -100;
  LX_AT_REMOVEDIR = $200;

  { endpoints (minix/com.h) }
  MX_PM = 0; MX_VFS = 1; MX_VM = 8;
  MX_SELF = 31742;            { SELF, measured: _ENDPOINT_SLOT_TOP - 3 }
  MX_SENDREC = 3;

  { PM calls (callnr.h, PM_BASE 0) }
  PM_EXIT = 1; PM_GETPID = 4; PM_GETUID = 6; PM_KILL = 11; PM_GETGID = 13;
  PM_CLOCK_GETRES = 33; PM_CLOCK_GETTIME = 34;
  { VFS calls (VFS_BASE $100) }
  VFS_READ = $100; VFS_WRITE = $101; VFS_LSEEK = $102; VFS_OPEN = $103;
  VFS_CREAT = $104; VFS_CLOSE = $105; VFS_UNLINK = $107; VFS_CHDIR = $108;
  VFS_MKDIR = $109; VFS_CHMOD = $10B; VFS_ACCESS = $10F; VFS_SYNC = $110;
  VFS_RENAME = $111; VFS_RMDIR = $112; VFS_STAT = $115; VFS_FSTAT = $116;
  VFS_LSTAT = $117; VFS_IOCTL = $118; VFS_FCNTL = $119; VFS_UMASK = $11B;
  VFS_GETDENTS = $11D; VFS_FCHDIR = $11F; VFS_FSYNC = $120;
  VFS_FTRUNCATE = $122; VFS_SELECT = $11E; VFS_UTIMENS = $125;
  VFS_STATVFS1 = $128; VFS_FSTATVFS1 = $129;
  PM_GETPRIORITY = 26; PM_SETPRIORITY = 27; PM_GETSID = 32; VFS_SYMLINK = $113; VFS_READLINK = $114;
  VFS_PIPE2 = $11A;
  PM_FORK = 2; PM_WAIT4 = 3; PM_EXEC = 14;
  MX_MIB = 7; MIB_SYSCTL = $1800;
  MX_USER_SP = $F0000000;     { minix_get_user_sp(), measured: the new image's stack top }
  { minix/lib/libc/sys/stack_utils.c STACK_MIN_SZ: argc, the two NULLs,
    PMEF_AUXVECTORS (20) AuxInfo pairs, PMEF_EXECNAMELEN1 (PATH_MAX 1024),
    struct ps_strings (16). VFS fills the auxv and the name in. }
  MX_STACK_MIN = 4 + 8 + 8 * 20 + 1024 + 16;
  { VM calls (VM_RQ_BASE $C00) }
  VM_MMAP = $C0A; VM_MUNMAP = $C11;

  M_PATH_STRING_MAX = 40;     { ipc.h: the in-message copy of a short path }

  MX_TIOCGETA = $402C7413; MX_TIOCGWINSZ = $40087468;

  { Minix errno 35..96 -> Linux errno (the NetBSD numbers; 1..34 are the
    same on both). Minix's own (200 and up) arrive as EIO. }
  ErrMap: array[35..96] of Integer = (
    11, 115, 114, 88, 89, 90, 91, 92, 93, 94,      { 35 EAGAIN .. 44 ESOCKTNOSUPPORT }
    95, 96, 97, 98, 99, 100, 101, 102, 103, 104,   { 45 EOPNOTSUPP .. 54 ECONNRESET }
    105, 106, 107, 108, 109, 110, 111, 40, 36, 112, { 55 ENOBUFS .. 64 EHOSTDOWN }
    113, 39, 11, 87, 122, 116, 66, 22, 22, 22,     { 65 EHOSTUNREACH .. 74 EPROGUNAVAIL }
    22, 22, 37, 38, 22, 13, 13, 43, 42, 75,        { 75 EPROGMISMATCH .. 84 EOVERFLOW }
    84, 95, 125, 74, 61, 63, 60, 62, 61, 72,       { 85 EILSEQ .. 94 EMULTIHOP }
    67, 71);                                       { 95 ENOLINK, 96 EPROTO }

  { Linux signal 0..31 -> Minix (NetBSD's numbers). 0 = none. }
  SigMap: array[0..31] of Integer = (
    0, 1, 2, 3, 4, 5, 6, 10, 8, 9, 30, 11, 31, 13, 14, 15,
    0, 20, 19, 17, 18, 21, 22, 16, 24, 25, 26, 27, 28, 23, 32, 12);

type
  TMxMsg = array[0..15] of LongInt;   { 64 bytes; [0] m_source, [1] m_type, payload from [2] }

var
  MxInitSp: LongInt;          { the initial stack pointer (argc), from the entry stub }
  MxTmpSeq: LongInt;

{ The ONE kernel entry: SENDREC msg to endpt. 0, or the IPC layer's own
  negative error (the call's answer is in the message's m_type). }
function MxIpc(endpt: LongInt; msg: Pointer): LongInt; assembler;
asm
  push ebx
  mov eax, endpt
  mov ebx, msg
  mov ecx, 3
  int 33
  pop ebx
end;

procedure MxClear(var m: TMxMsg);
var i: Integer;
begin
  for i := 0 to 15 do m[i] := 0;
end;

{ Send m to endpt as call typ; the answer: m_type (>= 0), or -Minix-errno. }
function MxCall(endpt, typ: LongInt; var m: TMxMsg): LongInt;
var r: LongInt;
begin
  m[1] := typ;
  r := MxIpc(endpt, @m[0]);
  if r <> 0 then Result := r
  else Result := m[1];
end;

{ Minix's answer -> Linux's: -errno remapped where the numbers differ. }
function Lx(r: LongInt): LongInt;
begin
  if (r < -34) and (r >= -96) then Result := -ErrMap[Integer(-r)]
  else if r < -96 then Result := -5                   { Minix-only codes: EIO }
  else Result := r;
end;

function StrLen0(p: LongInt): LongInt;
begin
  Result := 0;
  while PByte(p + Result)^ <> 0 do Result := Result + 1;
end;

{ ---- paths -----------------------------------------------------------------
  Minix has no *at calls. A Linux *at with AT_FDCWD, or with an absolute
  path, is the plain call; any other directory fd is refused (EBADF would
  mislead, so ENOSYS: "this translator cannot"). }
function DirOk(dirfd, path: LongInt): Boolean;
begin
  Result := (dirfd = LX_AT_FDCWD) or ((path <> 0) and (PByte(path)^ = 47));
end;

{ mess_lc_vfs_path: name at 8, len at 12, flags at 16, mode at 20, and a copy
  of a short name (with its NUL) at 24 -- VFS reads that copy when len fits. }
procedure LoadName(var m: TMxMsg; path: LongInt);
var n, i: LongInt;
begin
  n := StrLen0(path) + 1;
  m[2] := path;
  m[3] := n;
  if n <= M_PATH_STRING_MAX then
    for i := 0 to n - 1 do PByte(LongInt(@m[6]) + i)^ := PByte(path + i)^;
end;

function PathCall(typ, path, flags, mode: LongInt): LongInt;
var m: TMxMsg;
begin
  if path = 0 then begin Result := -LX_EFAULT; Exit; end;
  MxClear(m);
  LoadName(m, path);
  m[4] := flags;
  m[5] := mode;
  Result := Lx(MxCall(MX_VFS, typ, m));
end;

{ ---- files ------------------------------------------------------------------ }

function MxOpen0(path, flags, mode: LongInt): LongInt; forward;
function MxRw(typ, fd, buf, len: LongInt): LongInt; forward;

function MxOpenFlags(f: LongInt): LongInt;
var r: LongInt;
begin
  r := f and 3;                                       { O_ACCMODE, same }
  if (f and $40) <> 0 then r := r or $200;            { O_CREAT }
  if (f and $80) <> 0 then r := r or $800;            { O_EXCL }
  if (f and $100) <> 0 then r := r or $8000;          { O_NOCTTY }
  if (f and $200) <> 0 then r := r or $400;           { O_TRUNC }
  if (f and $400) <> 0 then r := r or $8;             { O_APPEND }
  if (f and $800) <> 0 then r := r or $4;             { O_NONBLOCK }
  if (f and $10000) <> 0 then r := r or $200000;      { O_DIRECTORY }
  if (f and $20000) <> 0 then r := r or $100;         { O_NOFOLLOW }
  if (f and $80000) <> 0 then r := r or $400000;      { O_CLOEXEC }
  Result := r;
end;

function MxOpen(path, flags, mode: LongInt): LongInt;
var m: TMxMsg; mf: LongInt; st: array[0..31] of LongInt;
begin
  { Minix's VFS takes O_NOFOLLOW and O_DIRECTORY and ignores both: test the
    path's last component before, and the opened file after. }
  if (flags and $20000) <> 0 then
  begin
    MxClear(m);
    m[2] := StrLen0(path) + 1; m[3] := path; m[4] := LongInt(@st[0]);
    if (MxCall(MX_VFS, VFS_LSTAT, m) >= 0) and ((st[2] and $F000) = $A000) then
    begin Result := -40; Exit; end;                    { ELOOP }
  end;
  Result := MxOpen0(path, flags, mode);
  if (Result >= 0) and ((flags and $10000) <> 0) then
  begin
    MxClear(m);
    m[2] := Result; m[3] := LongInt(@st[0]);
    if (MxCall(MX_VFS, VFS_FSTAT, m) >= 0) and ((st[2] and $F000) <> $4000) then
    begin
      MxClear(m); m[2] := Result;
      MxCall(MX_VFS, VFS_CLOSE, m);
      Result := -20;                                    { ENOTDIR }
    end;
  end;
end;

{ A 0-byte read: Linux answers EISDIR on a directory (the runtime's probe
  for "this open() named a directory"); Minix answers 0. }
function MxRead(fd, buf, len: LongInt): LongInt;
var m: TMxMsg; st: array[0..31] of LongInt;
begin
  if len = 0 then
  begin
    MxClear(m);
    m[2] := fd; m[3] := LongInt(@st[0]);
    if (MxCall(MX_VFS, VFS_FSTAT, m) >= 0) and ((st[2] and $F000) = $4000) then
    begin Result := -21; Exit; end;                    { EISDIR }
  end;
  Result := MxRw(VFS_READ, fd, buf, len);
end;

function MxOpen0(path, flags, mode: LongInt): LongInt;
var m: TMxMsg; mf: LongInt;
begin
  mf := MxOpenFlags(flags);
  MxClear(m);
  if (mf and $200) <> 0 then
  begin
    { mess_lc_vfs_creat: name, len, flags, mode -- no in-message copy }
    m[2] := path;
    m[3] := StrLen0(path) + 1;
    m[4] := mf;
    m[5] := mode;
    Result := Lx(MxCall(MX_VFS, VFS_CREAT, m));
  end
  else
  begin
    LoadName(m, path);
    m[4] := mf;
    Result := Lx(MxCall(MX_VFS, VFS_OPEN, m));
  end;
end;

function MxRw(typ, fd, buf, len: LongInt): LongInt;
var m: TMxMsg;
begin
  MxClear(m);
  m[2] := fd; m[3] := buf; m[4] := len;               { mess_lc_vfs_readwrite }
  Result := Lx(MxCall(MX_VFS, typ, m));
end;

function MxFdCall(typ, fd: LongInt): LongInt;
var m: TMxMsg;
begin
  MxClear(m);
  m[2] := fd;
  Result := Lx(MxCall(MX_VFS, typ, m));
end;

{ lseek with a 64-bit offset (mess_lc_vfs_lseek: offset 8, fd 16, whence
  20); the new position comes back at 8. }
function MxLseek(fd: LongInt; offLo, offHi: LongInt; whence: LongInt; var res: Int64): LongInt;
var m: TMxMsg;
begin
  MxClear(m);
  m[2] := offLo; m[3] := offHi; m[4] := fd; m[5] := whence;
  Result := Lx(MxCall(MX_VFS, VFS_LSEEK, m));
  if Result >= 0 then
  begin
    res := PInt64(@m[2])^;
    Result := 0;
  end;
end;

{ Minix struct stat (i386, 124 B; measured): dev 0/8, mode 8/4, ino 12/8,
  nlink 20/4, uid 24, gid 28, rdev 32/8, atim 40, mtim 52, ctim 64, btim 76
  (each 8-byte sec + 4-byte nsec), size 88/8, blocks 96/8, blksize 104/4. }
procedure StatToStatx(st, sx: LongInt);
var i: Integer;
procedure Ts(lxOff, mxOff: Integer);
begin
  PInt64(sx + lxOff)^ := PInt64(st + mxOff)^;
  PLongInt(sx + lxOff + 8)^ := PLongInt(st + mxOff + 8)^;
end;
begin
  for i := 0 to 63 do PLongInt(sx + i * 4)^ := 0;
  PLongInt(sx + 0)^ := $FFF;                          { BASIC_STATS | BTIME }
  PLongInt(sx + 4)^ := PLongInt(st + 104)^;           { blksize }
  PLongInt(sx + 16)^ := PLongInt(st + 20)^;           { nlink }
  PLongInt(sx + 20)^ := PLongInt(st + 24)^;           { uid }
  PLongInt(sx + 24)^ := PLongInt(st + 28)^;           { gid }
  PWord(sx + 28)^ := PWord(st + 8)^;                  { mode }
  PInt64(sx + 32)^ := PInt64(st + 12)^;               { ino }
  PInt64(sx + 40)^ := PInt64(st + 88)^;               { size }
  PInt64(sx + 48)^ := PInt64(st + 96)^;               { blocks }
  Ts(64, 40);                                         { atime }
  Ts(80, 76);                                         { btime }
  Ts(96, 64);                                         { ctime }
  Ts(112, 52);                                        { mtime }
  { rdev and dev as major/minor: Minix packs (major << 8) | minor }
  PLongInt(sx + 128)^ := (PLongInt(st + 32)^ shr 8) and $FF;
  PLongInt(sx + 132)^ := PLongInt(st + 32)^ and $FF;
  PLongInt(sx + 136)^ := (PLongInt(st + 0)^ shr 8) and $FF;
  PLongInt(sx + 140)^ := PLongInt(st + 0)^ and $FF;
end;

{ statx(dirfd, path, flags, mask, buf). AT_EMPTY_PATH ($1000) with an empty
  path is fstat(dirfd); AT_SYMLINK_NOFOLLOW ($100) is lstat. }
function MxStatx(dirfd, path, flags, buf: LongInt): LongInt;
var m: TMxMsg; st: array[0..31] of LongInt;
begin
  MxClear(m);
  if ((flags and $1000) <> 0) and ((path = 0) or (PByte(path)^ = 0)) then
  begin
    m[2] := dirfd; m[3] := LongInt(@st[0]);           { mess_lc_vfs_fstat }
    Result := MxCall(MX_VFS, VFS_FSTAT, m);
  end
  else
  begin
    if path = 0 then begin Result := -LX_EFAULT; Exit; end;
    if not DirOk(dirfd, path) then begin Result := -LX_ENOSYS; Exit; end;
    m[2] := StrLen0(path) + 1;                        { mess_lc_vfs_stat: len, name, buf }
    m[3] := path;
    m[4] := LongInt(@st[0]);
    if (flags and $100) <> 0 then Result := MxCall(MX_VFS, VFS_LSTAT, m)
    else Result := MxCall(MX_VFS, VFS_STAT, m);
  end;
  if Result >= 0 then
  begin
    StatToStatx(LongInt(@st[0]), buf);
    Result := 0;
  end
  else Result := Lx(Result);
end;

{ getdents64: Minix's records (ino 0/8, reclen 8/2, namlen 10/2, type 12,
  name 13) are rewritten as Linux's (ino 0/8, off 8/8, reclen 16/2, type 18,
  name 19), 8-aligned. A Linux record is at most 8 bytes longer, so Minix is
  asked for no more than it can be grown into: half the buffer, at least 600
  bytes (one maximal entry). The offsets past what fits are rewound. }
function MxGetdents(fd, buf, cap: LongInt): LongInt;
var m: TMxMsg; tmp: array[0..4095] of Byte; ask, n, i, o, rl, nl, need, k: LongInt;
    p: LongInt; pos: Int64;
begin
  ask := cap div 2;
  if ask > 4096 then ask := 4096;
  if ask < 600 then ask := cap;
  if ask > 4096 then ask := 4096;
  MxClear(m);
  m[2] := fd; m[3] := LongInt(@tmp[0]); m[4] := ask;
  n := MxCall(MX_VFS, VFS_GETDENTS, m);
  if n < 0 then begin Result := Lx(n); Exit; end;
  i := 0; o := 0;
  while i < n do
  begin
    p := LongInt(@tmp[0]) + i;
    rl := PWord(p + 8)^;
    nl := PWord(p + 10)^;
    if rl = 0 then Break;
    need := (19 + nl + 1 + 7) and (not 7);
    if o + need > cap then
    begin
      { no room: put the directory back to this entry }
      if o = 0 then begin Result := -LX_EINVAL; Exit; end;
      MxLseek(fd, 0, 0, 1, pos);                       { current = past what Minix sent }
      pos := pos - (n - i);
      MxLseek(fd, LongInt(pos), 0, 0, pos);
      Break;
    end;
    PInt64(buf + o)^ := PInt64(p)^;
    PInt64(buf + o + 8)^ := 0;
    PWord(buf + o + 16)^ := need;
    PByte(buf + o + 18)^ := PByte(p + 12)^;
    for k := 0 to nl - 1 do PByte(buf + o + 19 + k)^ := PByte(p + 13 + k)^;
    for k := 19 + nl to need - 1 do PByte(buf + o + k)^ := 0;
    o := o + need;
    i := i + rl;
  end;
  Result := o;
end;

function MxFcntlRaw(fd, cmd, arg: LongInt): LongInt; forward;

function MxIoctl(fd, req, arg: LongInt): LongInt;
var m: TMxMsg; t: array[0..15] of LongInt; i: Integer;
begin
  MxClear(m);
  m[2] := fd;
  if req = $5401 then                                 { TCGETS: isatty and little else }
  begin
    m[3] := MX_TIOCGETA; m[4] := LongInt(@t[0]);
    Result := Lx(MxCall(MX_VFS, VFS_IOCTL, m));
    if (Result >= 0) and (arg <> 0) then
      for i := 0 to 14 do PLongInt(arg + i * 4)^ := 0;
  end
  else if req = $5413 then                            { TIOCGWINSZ: same struct }
  begin
    m[3] := MX_TIOCGWINSZ; m[4] := arg;
    Result := Lx(MxCall(MX_VFS, VFS_IOCTL, m));
  end
  else if (req = $540F) or (req = $5410) then          { TIOCGPGRP / TIOCSPGRP: an int both ways }
  begin
    if req = $540F then m[3] := $40047477 else m[3] := $80047476;
    m[4] := arg;
    Result := Lx(MxCall(MX_VFS, VFS_IOCTL, m));
  end
  else if MxFcntlRaw(fd, 3, 0) < 0 then Result := -LX_EBADF   { a bad fd says so first }
  else Result := -LX_ENOTTY;
end;

{ ---- memory ----------------------------------------------------------------- }

{ mess_mmap: offset 8/8, addr 16, len 20, prot 24, flags 28, fd 32,
  forwhom 36, retaddr 40 (the answer). }
function MxMmap(addr, len, prot, flags, fd, pgoff: LongInt): LongInt;
var m: TMxMsg; mf, r: LongInt;
begin
  mf := flags and $13;                                { SHARED, PRIVATE, FIXED: same bits }
  if (flags and $20) <> 0 then mf := mf or $1000;     { MAP_ANONYMOUS }
  MxClear(m);
  m[2] := pgoff shl 12; m[3] := (pgoff shr 20) and $FFF;
  m[4] := addr; m[5] := len; m[6] := prot; m[7] := mf; m[8] := fd;
  m[9] := MX_SELF;
  r := MxCall(MX_VM, VM_MMAP, m);
  if r < 0 then Result := Lx(r)
  else Result := m[10];
end;

function MxMunmap(addr, len: LongInt): LongInt;
var m: TMxMsg;
begin
  MxClear(m);
  m[4] := addr; m[5] := len;
  Result := Lx(MxCall(MX_VM, VM_MUNMAP, m));
end;

{ ---- time -------------------------------------------------------------------- }

{ clock_gettime(id, ts): mess_lc_pm_time (sec 8/8, clk_id 16, now 20) out,
  mess_pm_lc_time (sec 8/8, nsec 16) back. Linux CLOCK_MONOTONIC (1) and its
  variants are Minix's 3. A Linux i386 timespec is two 32-bit words. }
function MxClockGettime(id, ts: LongInt; typ: LongInt): LongInt;
var m: TMxMsg; r: LongInt;
begin
  MxClear(m);
  if id = 0 then m[4] := 0 else m[4] := 3;
  m[5] := 1;
  r := MxCall(MX_PM, typ, m);
  if r < 0 then begin Result := Lx(r); Exit; end;
  if ts <> 0 then
  begin
    PLongInt(ts)^ := m[2];
    PLongInt(ts + 4)^ := m[4];
  end;
  Result := 0;
end;



function SigToLinux(n: LongInt): LongInt; forward;

{ ---- signals ---------------------------------------------------------------------
  The program's handlers speak Linux i386's SA_SIGINFO ABI (sig, siginfo*,
  ucontext*) and may rewrite the saved eip/esp (the fault-to-raise path).
  Minix calls a handler as handler(signum, code, struct sigcontext *) on
  the CURRENT stack (no sigaltstack), with the return address set to the
  `ret` routine given at sigaction time. So rt_sigaction installs
  MxSigEntry, which builds Linux's siginfo/ucontext from the sigcontext,
  calls the program's handler and copies the registers back; it returns to
  MxSigRet, which sends PM_SIGRETURN for that sigcontext, as Minix's libc
  __sigreturn does. Measured with offsetof() on Minix 3.4 (2026-11-13):
  struct sigcontext (620 B) gs 0 fs 4 es 8 ds 12 edi 16 esi 20 ebp 24 ebx 28
  edx 32 ecx 36 eax 40 eip 44 cs 48 eflags 52 esp 56 ss 60, sc_mask 80
  (sigset_t, 16 B); struct sigaction handler 0, mask 4, flags 20; SA_ONSTACK
  1, SA_RESTART 2, SA_RESETHAND 4, SA_NODEFER $10; no SA_SIGINFO. }

const
  PM_SIGACTION = 20; PM_SIGSUSPEND = 21; PM_SIGPENDING = 22;
  PM_SIGPROCMASK = 23; PM_SIGRETURN = 24;
  MX_SIG_INQUIRE = 10;
  MX_SC_MASK = 80;
  LX_SA_RESTART = $10000000; LX_SA_NODEFER = $40000000; LX_SA_RESETHAND = $80000000;
  LX_UC_GREGS = 20;           { Linux i386 ucontext: uc_mcontext.gregs[19] }
  LX_UC_SIGMASK = 108;
  { Linux gregs (GS FS ES DS EDI ESI EBP ESP EBX EDX ECX EAX TRAPNO ERR EIP CS
    EFL UESP SS) -> offset in Minix's sigcontext; -1 = none. }
  MxGregOff: array[0..18] of Integer = (
    0, 4, 8, 12, 16, 20, 24, 56, 28, 32, 36, 40, -1, -1, 44, 48, 52, 56, 60);
  MX_SIG_NEST = 16;

type
  TMxLxHandler = procedure(sig, info, uc: LongInt); cdecl;

var
  MxLxHandler: array[0..31] of LongInt;   { by Linux signal number }
  MxScStack: array[0..15] of LongInt;     { the sigcontexts of the handlers running }
  MxScDepth: LongInt;
  MxSigMsg: TMxMsg;                       { NOT on the stack: see MxSigRet }

{ Linux 64-bit mask (two words) <-> Minix's first sigset word. }
function MaskToMx(lo, hi: LongInt): LongInt;
var s, b: Integer;
begin
  Result := 0;
  for s := 1 to 31 do
    if ((lo shr (s - 1)) and 1) <> 0 then
    begin
      b := SigMap[s];
      if (b >= 1) and (b <= 32) then Result := Result or (1 shl (b - 1));
    end;
end;

function MaskToLx(mx: LongInt): LongInt;
var b, s: Integer;
begin
  Result := 0;
  for b := 1 to 32 do
    if ((mx shr (b - 1)) and 1) <> 0 then
    begin
      s := SigToLinux(b);
      if (s >= 1) and (s <= 31) then Result := Result or (1 shl (s - 1));
    end;
end;

{ Where Minix sends a handler back: PM_SIGRETURN restores the sigcontext
  MxSigEntry was given (the innermost running one). Entered by `ret`, never
  returns; the message is a global because this stack is about to go. }
procedure MxSigRet;
var sc, i: LongInt;
begin
  MxScDepth := MxScDepth - 1;
  sc := MxScStack[MxScDepth];
  for i := 0 to 15 do MxSigMsg[i] := 0;
  MxSigMsg[2] := 3;                                   { how: SIG_SETMASK }
  MxSigMsg[3] := sc;                                  { ctx }
  for i := 0 to 3 do MxSigMsg[4 + i] := PLongInt(sc + MX_SC_MASK + 4 * i)^;   { set }
  MxSigMsg[1] := PM_SIGRETURN;
  MxIpc(MX_PM, @MxSigMsg[0]);
end;

{ The handler Minix calls. }
procedure MxSigEntry(signum, code, sc: LongInt); cdecl;
var li: array[0..31] of LongInt;      { Linux siginfo_t, 128 B }
    lu: array[0..63] of LongInt;      { Linux ucontext_t through uc_sigmask }
    i, ls, h: LongInt;
begin
  ls := SigToLinux(signum);
  if (ls < 1) or (ls > 31) then h := 0 else h := MxLxHandler[ls];
  if MxScDepth < MX_SIG_NEST then
  begin
    MxScStack[MxScDepth] := sc;
    MxScDepth := MxScDepth + 1;
  end;
  if h = 0 then Exit;
  for i := 0 to 31 do li[i] := 0;
  for i := 0 to 63 do lu[i] := 0;
  li[0] := ls;
  for i := 0 to 18 do
    if MxGregOff[i] >= 0 then lu[LX_UC_GREGS div 4 + i] := PLongInt(sc + MxGregOff[i])^;
  lu[LX_UC_SIGMASK div 4] := MaskToLx(PLongInt(sc + MX_SC_MASK)^);
  TMxLxHandler(h)(ls, LongInt(@li[0]), LongInt(@lu[0]));
  for i := 0 to 18 do
    if (MxGregOff[i] >= 0) and (i <> 17) then
      PLongInt(sc + MxGregOff[i])^ := lu[LX_UC_GREGS div 4 + i];
end;

{ rt_sigaction(sig, act, oact): Linux i386's kernel struct is handler 0,
  flags 4, restorer 8, mask 12 (8 B). }
function MxRtSigaction(sig, act, oact: LongInt): LongInt;
var m: TMxMsg; na, oa: array[0..5] of LongInt; ms, h, oldh, f, i: LongInt;
begin
  if (sig < 1) or (sig > 31) then begin Result := -LX_EINVAL; Exit; end;
  ms := SigMap[sig];
  if ms = 0 then
  begin
    { no Minix equivalent: accept, as nothing can send it }
    if oact <> 0 then for i := 0 to 4 do PLongInt(oact + 4 * i)^ := 0;
    Result := 0; Exit;
  end;
  oldh := MxLxHandler[sig];
  for i := 0 to 5 do begin na[i] := 0; oa[i] := 0; end;
  MxClear(m);
  m[3] := ms;                                         { mess_lc_pm_sig: pid 8, nr 12, act 16, oact 20, ret 24 }
  m[5] := LongInt(@oa[0]);
  m[6] := LongInt(@MxSigRet);
  h := 0;
  if act <> 0 then
  begin
    h := PLongInt(act)^;
    f := PLongInt(act + 4)^;
    na[1] := MaskToMx(PLongInt(act + 12)^, PLongInt(act + 16)^);
    if (f and LX_SA_RESTART) <> 0 then na[5] := na[5] or 2;
    if (f and LX_SA_RESETHAND) <> 0 then na[5] := na[5] or 4;
    if (f and LX_SA_NODEFER) <> 0 then na[5] := na[5] or $10;
    if (h = 0) or (h = 1) then na[0] := h               { SIG_DFL / SIG_IGN }
    else na[0] := LongInt(@MxSigEntry);
    m[4] := LongInt(@na[0]);
    MxLxHandler[sig] := h;
  end;
  Result := Lx(MxCall(MX_PM, PM_SIGACTION, m));
  if Result < 0 then begin MxLxHandler[sig] := oldh; Exit; end;
  if (act <> 0) and ((h = 0) or (h = 1)) then MxLxHandler[sig] := 0;
  if oact <> 0 then
  begin
    if oa[0] = LongInt(@MxSigEntry) then PLongInt(oact)^ := oldh
    else PLongInt(oact)^ := oa[0];
    f := $04000004;                                   { SA_RESTORER | SA_SIGINFO, as set }
    if (oa[5] and 2) <> 0 then f := f or LX_SA_RESTART;
    if (oa[5] and 4) <> 0 then f := f or LX_SA_RESETHAND;
    if (oa[5] and $10) <> 0 then f := f or LX_SA_NODEFER;
    if (oa[0] = 0) or (oa[0] = 1) then f := 0;
    PLongInt(oact + 4)^ := f;
    PLongInt(oact + 8)^ := 0;
    PLongInt(oact + 12)^ := MaskToLx(oa[1]);
    PLongInt(oact + 16)^ := 0;
  end;
  Result := 0;
end;

{ rt_sigprocmask(how, set, oset): mess_lc_pm_sigset how 8, ctx 12, set 16;
  the old mask comes back at 8 (mess_pm_lc_sigset). }
function MxRtSigprocmask(how, nset, oset: LongInt): LongInt;
var m: TMxMsg;
begin
  if (how < 0) or (how > 2) then begin Result := -LX_EINVAL; Exit; end;
  MxClear(m);
  if nset <> 0 then
  begin
    m[2] := how + 1;
    m[4] := MaskToMx(PLongInt(nset)^, PLongInt(nset + 4)^);
  end
  else m[2] := MX_SIG_INQUIRE;
  Result := Lx(MxCall(MX_PM, PM_SIGPROCMASK, m));
  if Result < 0 then Exit;
  if oset <> 0 then
  begin
    PLongInt(oset)^ := MaskToLx(m[2]);
    PLongInt(oset + 4)^ := 0;
  end;
  Result := 0;
end;

function MxRtSigpending(set_: LongInt): LongInt;
var m: TMxMsg;
begin
  MxClear(m);
  Result := Lx(MxCall(MX_PM, PM_SIGPENDING, m));
  if Result < 0 then Exit;
  PLongInt(set_)^ := MaskToLx(m[2]);
  PLongInt(set_ + 4)^ := 0;
  Result := 0;
end;

function MxRtSigsuspend(set_: LongInt): LongInt;
var m: TMxMsg;
begin
  MxClear(m);
  m[4] := MaskToMx(PLongInt(set_)^, PLongInt(set_ + 4)^);
  MxCall(MX_PM, PM_SIGSUSPEND, m);
  Result := -4;                                       { EINTR, always }
end;


{ ---- sleeping and waiting for a signal ---------------------------------------------

  Minix's libc sleeps with select(0, ..., timeout); so does this.
  mess_lc_vfs_select: nfds 8, readfds 12, writefds 16, errorfds 20,
  timeout 24 (struct timeval: tv_sec 0/8, tv_usec 8/4; measured). }
function MxSleepUs(sec, usec: LongInt): LongInt;
var m: TMxMsg; tv: array[0..3] of LongInt;
begin
  tv[0] := sec; tv[1] := 0; tv[2] := usec; tv[3] := 0;
  MxClear(m);
  m[6] := LongInt(@tv[0]);
  Result := Lx(MxCall(MX_VFS, VFS_SELECT, m));
end;

{ nanosleep(req, rem): a Linux i386 timespec is two 32-bit words. }
function MxNanosleep(req, rem: LongInt): LongInt;
var sec, ns: LongInt;
begin
  if req = 0 then begin Result := -LX_EFAULT; Exit; end;
  sec := PLongInt(req)^; ns := PLongInt(req + 4)^;
  if (sec < 0) or (ns < 0) or (ns > 999999999) then begin Result := -LX_EINVAL; Exit; end;
  Result := MxSleepUs(sec, (ns + 999) div 1000);
  if Result > 0 then Result := 0;
  if rem <> 0 then begin PLongInt(rem)^ := 0; PLongInt(rem + 4)^ := 0; end;
end;

{ rt_sigtimedwait(set, info, timeout): Minix has none. A blocked signal stays
  pending, so: look at the pending set; take one that is in `set` by
  setting its action to SIG_IGN (which discards it, POSIX) and putting the
  action back; otherwise sleep 10 ms and look again, until the timeout. }
function MxRtSigtimedwait(set_, info, ts: LongInt): LongInt;
var m: TMxMsg; pend, want, s, waited, limit, i: LongInt;
    na, oa: array[0..5] of LongInt;
begin
  want := PLongInt(set_)^;
  waited := 0;
  if ts <> 0 then limit := PLongInt(ts)^ * 1000 + PLongInt(ts + 4)^ div 1000000
  else limit := -1;
  while True do
  begin
    MxClear(m);
    if MxCall(MX_PM, PM_SIGPENDING, m) < 0 then begin Result := -LX_EINVAL; Exit; end;
    pend := MaskToLx(m[2]) and want;
    if pend <> 0 then
    begin
      s := 1;
      while ((pend shr (s - 1)) and 1) = 0 do s := s + 1;
      for i := 0 to 5 do begin na[i] := 0; oa[i] := 0; end;
      na[0] := 1;                                     { SIG_IGN }
      MxClear(m);
      m[3] := SigMap[s]; m[4] := LongInt(@na[0]); m[5] := LongInt(@oa[0]);
      m[6] := LongInt(@MxSigRet);
      MxCall(MX_PM, PM_SIGACTION, m);
      MxClear(m);
      m[3] := SigMap[s]; m[4] := LongInt(@oa[0]); m[6] := LongInt(@MxSigRet);
      MxCall(MX_PM, PM_SIGACTION, m);
      if info <> 0 then
      begin
        for i := 0 to 31 do PLongInt(info + 4 * i)^ := 0;
        PLongInt(info)^ := s;
      end;
      Result := s;
      Exit;
    end;
    if (limit >= 0) and (waited >= limit) then begin Result := -11; Exit; end;   { EAGAIN }
    MxSleepUs(0, 10000);
    waited := waited + 10;
  end;
end;


{ ---- vectored and positioned I/O ---------------------------------------------------
  Minix has no readv/writev or pread/pwrite calls; its libc loops and
  seeks. So does this (positioned I/O is not atomic against another
  process sharing the descriptor). A Linux iovec is base, len. }

function MxRwv(typ, fd, iov, cnt: LongInt): LongInt;
var i, r, len: LongInt;
begin
  if (cnt < 0) or (cnt > 1024) then begin Result := -LX_EINVAL; Exit; end;
  Result := 0;
  for i := 0 to cnt - 1 do
  begin
    len := PLongInt(iov + 8 * i + 4)^;
    if len = 0 then Continue;
    r := MxRw(typ, fd, PLongInt(iov + 8 * i)^, len);
    if r < 0 then
    begin
      if Result = 0 then Result := r;
      Exit;
    end;
    Result := Result + r;
    if r < len then Exit;
  end;
end;

{ Seek to (lo, hi), run the transfer, put the position back. iov = 0: one
  buffer (buf, len); else cnt iovecs at buf. }
function MxPrw(typ, fd, buf, len, lo, hi: LongInt; vec: Boolean): LongInt;
var save, pos: Int64; r: LongInt;
begin
  r := MxLseek(fd, 0, 0, 1, save);
  if r < 0 then begin Result := r; Exit; end;
  r := MxLseek(fd, lo, hi, 0, pos);
  if r < 0 then begin Result := r; Exit; end;
  if vec then Result := MxRwv(typ, fd, buf, len)
  else Result := MxRw(typ, fd, buf, len);
  MxLseek(fd, LongInt(save), LongInt(save shr 32), 0, pos);
end;

{ ---- select and poll -----------------------------------------------------------------
  Minix's fd_set is 32 bytes (FD_SETSIZE 255; Linux's is 128): the first
  32 bytes are passed and come back, the rest is cleared. poll and ppoll
  are select, as in Minix's libc (no POLLHUP/POLLNVAL). us < 0: no timeout. }

function MxSelectUs(n, rd, wr, ex, sec, usec: LongInt; forever: Boolean): LongInt;
var m: TMxMsg; tv: array[0..3] of LongInt;
    sr, sw, se: array[0..7] of LongInt; i: Integer;
begin
  if (n < 0) or (n > 255) then begin Result := -LX_EINVAL; Exit; end;
  for i := 0 to 7 do
  begin
    if rd <> 0 then sr[i] := PLongInt(rd + 4 * i)^ else sr[i] := 0;
    if wr <> 0 then sw[i] := PLongInt(wr + 4 * i)^ else sw[i] := 0;
    if ex <> 0 then se[i] := PLongInt(ex + 4 * i)^ else se[i] := 0;
  end;
  tv[0] := sec; tv[1] := 0; tv[2] := usec; tv[3] := 0;
  MxClear(m);
  m[2] := n;
  if rd <> 0 then m[3] := LongInt(@sr[0]);
  if wr <> 0 then m[4] := LongInt(@sw[0]);
  if ex <> 0 then m[5] := LongInt(@se[0]);
  if not forever then m[6] := LongInt(@tv[0]);
  Result := Lx(MxCall(MX_VFS, VFS_SELECT, m));
  if Result < 0 then Exit;
  for i := 0 to 31 do
  begin
    if rd <> 0 then if i < 8 then PLongInt(rd + 4 * i)^ := sr[i] else PLongInt(rd + 4 * i)^ := 0;
    if wr <> 0 then if i < 8 then PLongInt(wr + 4 * i)^ := sw[i] else PLongInt(wr + 4 * i)^ := 0;
    if ex <> 0 then if i < 8 then PLongInt(ex + 4 * i)^ := se[i] else PLongInt(ex + 4 * i)^ := 0;
  end;
end;

{ poll(fds, n, ms): pollfd is fd 0/4, events 4/2, revents 6/2. POLLIN 1,
  POLLPRI 2, POLLOUT 4 (Linux's and Minix's). }
function MxPoll(fds, nfds, sec, usec: LongInt; forever: Boolean): LongInt;
var rd, wr, ex: array[0..31] of LongInt; i, fd, ev, rev, hi, r: LongInt;
begin
  for i := 0 to 31 do begin rd[i] := 0; wr[i] := 0; ex[i] := 0; end;
  hi := -1;
  for i := 0 to nfds - 1 do
  begin
    PWord(fds + 8 * i + 6)^ := 0;
    fd := PLongInt(fds + 8 * i)^;
    if fd < 0 then Continue;
    if fd > 254 then begin Result := -LX_EINVAL; Exit; end;
    if fd > hi then hi := fd;
    ev := PWord(fds + 8 * i + 4)^;
    if (ev and $41) <> 0 then rd[fd shr 5] := rd[fd shr 5] or (1 shl (fd and 31));   { POLLIN|POLLRDNORM }
    if (ev and $304) <> 0 then wr[fd shr 5] := wr[fd shr 5] or (1 shl (fd and 31));  { POLLOUT|WRNORM|WRBAND }
    if (ev and $82) <> 0 then ex[fd shr 5] := ex[fd shr 5] or (1 shl (fd and 31));   { POLLPRI|RDBAND }
  end;
  r := MxSelectUs(hi + 1, LongInt(@rd[0]), LongInt(@wr[0]), LongInt(@ex[0]), sec, usec, forever);
  if r <= 0 then begin Result := r; Exit; end;
  Result := 0;
  for i := 0 to nfds - 1 do
  begin
    fd := PLongInt(fds + 8 * i)^;
    if fd < 0 then Continue;
    ev := PWord(fds + 8 * i + 4)^;
    rev := 0;
    if ((rd[fd shr 5] shr (fd and 31)) and 1) <> 0 then rev := rev or (ev and $41);
    if ((wr[fd shr 5] shr (fd and 31)) and 1) <> 0 then rev := rev or (ev and $304);
    if ((ex[fd shr 5] shr (fd and 31)) and 1) <> 0 then rev := rev or (ev and $82);
    PWord(fds + 8 * i + 6)^ := rev;
    if rev <> 0 then Result := Result + 1;
  end;
end;

{ ---- file times, filesystems, priorities ------------------------------------------------ }

{ utimensat(dirfd, path, times, flags): mess_vfs_utimens atime 8/8, mtime
  16/8, ansec 24, mnsec 28, len 32, name 36, fd 40, flags 44. UTIME_NOW and
  UTIME_OMIT are the same numbers on both. path NULL = futimens(dirfd). }
function MxUtimensat(dirfd, path, times, flags: LongInt): LongInt;
var m: TMxMsg;
begin
  MxClear(m);
  if times = 0 then
  begin
    m[6] := $3FFFFFFF; m[7] := $3FFFFFFF;               { UTIME_NOW }
  end
  else
  begin
    m[2] := PLongInt(times)^; if m[2] < 0 then m[3] := -1;
    m[6] := PLongInt(times + 4)^;
    m[4] := PLongInt(times + 8)^; if m[4] < 0 then m[5] := -1;
    m[7] := PLongInt(times + 12)^;
  end;
  if path = 0 then
    m[10] := dirfd
  else
  begin
    if PByte(path)^ = 0 then begin Result := -LX_ENOENT; Exit; end;
    if not DirOk(dirfd, path) then begin Result := -LX_ENOSYS; Exit; end;
    m[8] := StrLen0(path) + 1; m[9] := path;
  end;
  if (flags and $100) <> 0 then m[11] := $200;          { AT_SYMLINK_NOFOLLOW }
  Result := Lx(MxCall(MX_VFS, VFS_UTIMENS, m));
end;

{ statfs/fstatfs (Linux i386 struct statfs, 32-bit counts) and the 64 forms,
  from Minix's statvfs (measured: flag 0, bsize 4, frsize 8, blocks 16/8,
  bfree 24/8, bavail 32/8, files 48/8, ffree 56/8, fsid 120, namemax 124,
  fstypename 148/32; 2228 B). f_type is 0: Minix names a filesystem, it
  has no magic number. mess_lc_vfs_statvfs1: fd 8, flags 12, len 16,
  name 20, buf 24. }
function MxStatfs(fd, path, buf: LongInt; wide: Boolean): LongInt;
var m: TMxMsg; sv: array[0..559] of LongInt; i: Integer; r: LongInt;
begin
  MxClear(m);
  m[3] := 1;                                            { ST_WAIT }
  m[6] := LongInt(@sv[0]);
  if path <> 0 then
  begin
    m[4] := StrLen0(path) + 1; m[5] := path;
    r := MxCall(MX_VFS, VFS_STATVFS1, m);
  end
  else
  begin
    m[2] := fd;
    r := MxCall(MX_VFS, VFS_FSTATVFS1, m);
  end;
  if r < 0 then begin Result := Lx(r); Exit; end;
  if wide then
  begin
    for i := 0 to 20 do PLongInt(buf + 4 * i)^ := 0;
    PLongInt(buf + 4)^ := sv[1];                        { f_bsize }
    PInt64(buf + 8)^ := PInt64(@sv[4])^;                { f_blocks }
    PInt64(buf + 16)^ := PInt64(@sv[6])^;               { f_bfree }
    PInt64(buf + 24)^ := PInt64(@sv[8])^;               { f_bavail }
    PInt64(buf + 32)^ := PInt64(@sv[12])^;              { f_files }
    PInt64(buf + 40)^ := PInt64(@sv[14])^;              { f_ffree }
    PLongInt(buf + 48)^ := sv[30];                      { f_fsid }
    PLongInt(buf + 56)^ := sv[31];                      { f_namelen }
    PLongInt(buf + 60)^ := sv[2];                       { f_frsize }
  end
  else
  begin
    for i := 0 to 15 do PLongInt(buf + 4 * i)^ := 0;
    PLongInt(buf + 4)^ := sv[1];
    PLongInt(buf + 8)^ := sv[4];
    PLongInt(buf + 12)^ := sv[6];
    PLongInt(buf + 16)^ := sv[8];
    PLongInt(buf + 20)^ := sv[12];
    PLongInt(buf + 24)^ := sv[14];
    PLongInt(buf + 28)^ := sv[30];
    PLongInt(buf + 36)^ := sv[31];
    PLongInt(buf + 40)^ := sv[2];
  end;
  Result := 0;
end;

{ fallocate(fd, mode 0, offset, len): Minix has none; grow the file with
  ftruncate when offset+len passes its end (no blocks are reserved). }
function MxFallocate(fd, mode, offLo, offHi, lenLo, lenHi: LongInt): LongInt;
var m: TMxMsg; st: array[0..31] of LongInt; want: Int64;
begin
  if mode <> 0 then begin Result := -95; Exit; end;    { EOPNOTSUPP }
  want := (Int64(offHi) shl 32) + LongWord(offLo) + (Int64(lenHi) shl 32) + LongWord(lenLo);
  if ((lenLo = 0) and (lenHi = 0)) or (lenHi < 0) or (offHi < 0) then begin Result := -LX_EINVAL; Exit; end;
  MxClear(m);
  m[2] := fd; m[3] := LongInt(@st[0]);
  Result := Lx(MxCall(MX_VFS, VFS_FSTAT, m));
  if Result < 0 then Exit;
  if (st[2] and $F000) <> $8000 then begin Result := -19; Exit; end;   { ENODEV: not a file }
  if want <= PInt64(@st[22])^ then begin Result := 0; Exit; end;
  MxClear(m);
  m[2] := LongInt(want); m[3] := LongInt(want shr 32); m[4] := fd;
  Result := Lx(MxCall(MX_VFS, VFS_FTRUNCATE, m));
end;

{ get/setpriority: mess_lc_pm_priority which 8, who 12, prio 16. PM
  answers getpriority with nice + 20 (Minix's libc subtracts PRIO_MAX);
  Linux's system call answers 20 - nice. }
function MxPriority(get: Boolean; which, who, prio: LongInt): LongInt;
var m: TMxMsg;
begin
  MxClear(m);
  m[2] := which; m[3] := who; m[4] := prio;
  if get then
  begin
    Result := Lx(MxCall(MX_PM, PM_GETPRIORITY, m));
    if Result >= 0 then Result := 40 - Result;
  end
  else Result := Lx(MxCall(MX_PM, PM_SETPRIORITY, m));
end;


{ ---- sockets -------------------------------------------------------------------------
  VFS calls since Minix 3.4 (VFS_SOCKET $131 .. VFS_SHUTDOWN $13F), served by
  the lwip/uds services. The numbers are NetBSD's, measured on the VM:
  sockaddr starts with a length byte, AF_INET6 24, SOL_SOCKET $FFFF,
  SOCK_CLOEXEC $10000000, SOCK_NONBLOCK $20000000, MSG_DONTWAIT $80,
  MSG_NOSIGNAL $400, IPV6_V6ONLY 27, TCP_KEEPIDLE 3 -- nbsdabi's tables.
  msghdr and cmsghdr have Linux i386's layout (all 32-bit fields); only
  cmsg_level SOL_SOCKET differs. Linux i386 reaches sockets through
  socketcall(102) and the direct calls 359..373; both arrive here.
  Messages: mess_lc_vfs_socket domain 8, type 12, protocol 16;
  mess_lc_vfs_sockaddr fd 8, addr 12, addr_len 16; mess_lc_vfs_sendrecv fd
  8, buf 12, len 16, flags 20, addr 24, addr_len 28; mess_lc_vfs_sockmsg fd 8,
  msgbuf 12, flags 16; mess_lc_vfs_sockopt fd 8, level 12, name 16, buf 20,
  len 24; listen and shutdown fd 8, arg 12. A length comes back at 8. }

const
  VFS_SOCKET = $131; VFS_SOCKETPAIR = $132; VFS_BIND = $133; VFS_CONNECT = $134;
  VFS_LISTEN = $135; VFS_ACCEPT = $136; VFS_SENDTO = $137; VFS_SENDMSG = $138;
  VFS_RECVFROM = $139; VFS_RECVMSG = $13A; VFS_SETSOCKOPT = $13B;
  VFS_GETSOCKOPT = $13C; VFS_GETSOCKNAME = $13D; VFS_GETPEERNAME = $13E;
  VFS_SHUTDOWN = $13F;
  LX_EAFNOSUPPORT = 97; LX_ENOPROTOOPT = 92;

function MxAf(a: LongInt): LongInt;
begin
  case a of
    0, 1, 2: Result := a;
    10: Result := 24;
  else Result := -1;
  end;
end;

function LxAf(a: LongInt): LongInt;
begin
  if a = 24 then Result := 10 else Result := a;
end;

function MxSockType(t: LongInt): LongInt;
begin
  Result := t and $FF;
  if (t and $800) <> 0 then Result := Result or $20000000;
  if (t and $80000) <> 0 then Result := Result or $10000000;
end;

function MxMsgFlags(f: LongInt): LongInt;
begin
  Result := f and $7;                                          { OOB PEEK DONTROUTE }
  if (f and $8) <> 0 then Result := Result or $20;             { CTRUNC }
  if (f and $20) <> 0 then Result := Result or $10;            { TRUNC }
  if (f and $40) <> 0 then Result := Result or $80;            { DONTWAIT }
  if (f and $80) <> 0 then Result := Result or $8;             { EOR }
  if (f and $100) <> 0 then Result := Result or $40;           { WAITALL }
  if (f and $4000) <> 0 then Result := Result or $400;         { NOSIGNAL }
end;

function LxMsgFlags(f: LongInt): LongInt;
begin
  Result := f and $7;
  if (f and $20) <> 0 then Result := Result or $8;
  if (f and $10) <> 0 then Result := Result or $20;
  if (f and $80) <> 0 then Result := Result or $40;
  if (f and $8) <> 0 then Result := Result or $80;
  if (f and $40) <> 0 then Result := Result or $100;
end;

{ A Linux sockaddr (family word) -> Minix's (length byte, family byte). }
function SaToMx(src, len, dst: LongInt): LongInt;
var i, af: LongInt;
begin
  if (src = 0) or (len < 2) then begin Result := -LX_EINVAL; Exit; end;
  if len > 128 then len := 128;
  for i := 0 to len - 1 do PByte(dst + i)^ := PByte(src + i)^;
  af := MxAf(PWord(src)^);
  if af < 0 then begin Result := -LX_EAFNOSUPPORT; Exit; end;
  if (af = 1) and (len > 106) then len := 106;                  { sun_path 108 -> 104 }
  PByte(dst)^ := len;
  PByte(dst + 1)^ := af;
  Result := len;
end;

procedure SaToLx(p, lenp: LongInt);
begin
  if (p = 0) or (lenp = 0) or (PLongInt(lenp)^ < 2) then Exit;
  PWord(p)^ := LxAf(PByte(p + 1)^);
end;

procedure SockOptToMx(var level, name: LongInt);
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

{ SO_RCVTIMEO/SO_SNDTIMEO carry a timeval: Linux i386's is two words,
  Minix's is a 64-bit second and a 32-bit microsecond (12 B). }
function MxSockopt(isGet: Boolean; fd, level, name, val, lenp: LongInt): LongInt;
var m: TMxMsg; lv, nm, e, len: LongInt; tv: array[0..3] of LongInt; tvo: Boolean;
begin
  lv := level; nm := name;
  SockOptToMx(lv, nm);
  if lv < 0 then begin Result := -LX_ENOPROTOOPT; Exit; end;
  tvo := (lv = $FFFF) and ((nm = $100C) or (nm = $100B));
  MxClear(m);
  m[2] := fd; m[3] := lv; m[4] := nm; m[5] := val;
  if not isGet then
  begin
    m[6] := lenp;                                       { setsockopt: the length itself }
    if tvo and (val <> 0) and (lenp >= 8) then
    begin
      tv[0] := PLongInt(val)^; tv[1] := 0; if tv[0] < 0 then tv[1] := -1;
      tv[2] := PLongInt(val + 4)^; tv[3] := 0;
      m[5] := LongInt(@tv[0]); m[6] := 12;
    end;
    Result := Lx(MxCall(MX_VFS, VFS_SETSOCKOPT, m));
    Exit;
  end;
  if lenp = 0 then begin Result := -LX_EFAULT; Exit; end;
  len := PLongInt(lenp)^;
  if tvo then begin m[5] := LongInt(@tv[0]); m[6] := 12; end
  else m[6] := len;
  Result := Lx(MxCall(MX_VFS, VFS_GETSOCKOPT, m));
  if Result < 0 then Exit;
  if tvo then
  begin
    if (val <> 0) and (len >= 8) then
    begin
      PLongInt(val)^ := tv[0]; PLongInt(val + 4)^ := tv[2];
    end;
    PLongInt(lenp)^ := 8;
  end
  else
  begin
    PLongInt(lenp)^ := m[2];
    if (lv = $FFFF) and (nm = $1007) and (val <> 0) then        { SO_ERROR: an errno }
    begin
      e := PLongInt(val)^;
      if (e >= 35) and (e <= 96) then PLongInt(val)^ := ErrMap[e];
    end;
  end;
  Result := 0;
end;

function MxSocket(dom, typ, proto: LongInt): LongInt;
var m: TMxMsg; d: LongInt;
begin
  if (typ and not ($FF or $800 or $80000)) <> 0 then begin Result := -LX_EINVAL; Exit; end;   { Linux checks the flags first }
  d := MxAf(dom);
  if d < 0 then begin Result := -LX_EAFNOSUPPORT; Exit; end;
  MxClear(m);
  m[2] := d; m[3] := MxSockType(typ); m[4] := proto;
  Result := Lx(MxCall(MX_VFS, VFS_SOCKET, m));
end;

function MxSocketpair(dom, typ, proto, sv: LongInt): LongInt;
var m: TMxMsg; d: LongInt;
begin
  if (typ and not ($FF or $800 or $80000)) <> 0 then begin Result := -LX_EINVAL; Exit; end;   { Linux checks the flags first }
  d := MxAf(dom);
  if d < 0 then begin Result := -LX_EAFNOSUPPORT; Exit; end;
  MxClear(m);
  m[2] := d; m[3] := MxSockType(typ); m[4] := proto;
  Result := Lx(MxCall(MX_VFS, VFS_SOCKETPAIR, m));
  if Result >= 0 then
  begin
    PLongInt(sv)^ := m[2]; PLongInt(sv + 4)^ := m[3];
    Result := 0;
  end;
end;

{ bind, connect: an address in }
function MxSockAddrIn(typ, fd, sa, len: LongInt): LongInt;
var m: TMxMsg; b: array[0..31] of LongInt; n: LongInt;
begin
  n := SaToMx(sa, len, LongInt(@b[0]));
  if n < 0 then begin Result := n; Exit; end;
  MxClear(m);
  m[2] := fd; m[3] := LongInt(@b[0]); m[4] := n;
  Result := Lx(MxCall(MX_VFS, typ, m));
end;

{ accept4, getsockname, getpeername: an address out. accept's flags are
  set afterwards with fcntl (Minix's accept takes none). }
function MxSockAddrOut(typ, fd, sa, lenp, flags: LongInt): LongInt;
var m: TMxMsg;
begin
  MxClear(m);
  m[2] := fd; m[3] := sa;
  if (sa <> 0) and (lenp <> 0) then m[4] := PLongInt(lenp)^;
  Result := Lx(MxCall(MX_VFS, typ, m));
  if Result < 0 then Exit;
  if (sa <> 0) and (lenp <> 0) then
  begin
    PLongInt(lenp)^ := m[2];
    SaToLx(sa, lenp);
  end;
  if typ = VFS_ACCEPT then
  begin
    if (flags and $80000) <> 0 then MxFcntlRaw(Result, 2, 1);          { FD_CLOEXEC }
    if (flags and $800) <> 0 then MxFcntlRaw(Result, 4, $4);           { O_NONBLOCK }
  end
  else Result := 0;
end;

function MxSendto(fd, buf, len, flags, sa, salen: LongInt): LongInt;
var m: TMxMsg; b: array[0..31] of LongInt; n: LongInt;
begin
  MxClear(m);
  m[2] := fd; m[3] := buf; m[4] := len; m[5] := MxMsgFlags(flags);
  if sa <> 0 then
  begin
    n := SaToMx(sa, salen, LongInt(@b[0]));
    if n < 0 then begin Result := n; Exit; end;
    m[6] := LongInt(@b[0]); m[7] := n;
  end;
  Result := Lx(MxCall(MX_VFS, VFS_SENDTO, m));
end;

function MxRecvfrom(fd, buf, len, flags, sa, lenp: LongInt): LongInt;
var m: TMxMsg;
begin
  MxClear(m);
  m[2] := fd; m[3] := buf; m[4] := len; m[5] := MxMsgFlags(flags);
  m[6] := sa;
  if (sa <> 0) and (lenp <> 0) then m[7] := PLongInt(lenp)^;
  Result := Lx(MxCall(MX_VFS, VFS_RECVFROM, m));
  if (Result >= 0) and (sa <> 0) and (lenp <> 0) then
  begin
    PLongInt(lenp)^ := m[2];
    SaToLx(sa, lenp);
  end;
end;

{ cmsg_level SOL_SOCKET 1 <-> $FFFF, in place (headers: len, level, type). }
procedure CmsgLevels(ctl, clen: LongInt; toMx: Boolean);
var p, l: LongInt;
begin
  p := ctl;
  while (ctl <> 0) and (p + 12 <= ctl + clen) do
  begin
    l := PLongInt(p)^;
    if l < 12 then Exit;
    if toMx and (PLongInt(p + 4)^ = 1) then PLongInt(p + 4)^ := $FFFF
    else if (not toMx) and (PLongInt(p + 4)^ = $FFFF) then PLongInt(p + 4)^ := 1;
    p := p + ((l + 3) and (not 3));
  end;
end;

{ sendmsg/recvmsg on a private copy of the msghdr (name, namelen, iov,
  iovlen, control, controllen, flags), so the name can be converted. }
function MxSockMsg(isSend: Boolean; fd, lm, flags: LongInt): LongInt;
var m: TMxMsg; h: array[0..6] of LongInt; b: array[0..31] of LongInt; n, i: LongInt;
begin
  for i := 0 to 6 do h[i] := PLongInt(lm + 4 * i)^;
  if isSend and (h[0] <> 0) then
  begin
    n := SaToMx(h[0], h[1], LongInt(@b[0]));
    if n < 0 then begin Result := n; Exit; end;
    h[0] := LongInt(@b[0]); h[1] := n;
  end;
  if isSend then CmsgLevels(h[4], h[5], True);
  MxClear(m);
  m[2] := fd; m[3] := LongInt(@h[0]); m[4] := MxMsgFlags(flags);
  if isSend then
  begin
    Result := Lx(MxCall(MX_VFS, VFS_SENDMSG, m));
    CmsgLevels(PLongInt(lm + 16)^, PLongInt(lm + 20)^, False);
  end
  else
  begin
    Result := Lx(MxCall(MX_VFS, VFS_RECVMSG, m));
    if Result >= 0 then
    begin
      if h[0] <> 0 then
      begin
        PWord(h[0])^ := LxAf(PByte(h[0] + 1)^);
        PLongInt(lm + 4)^ := h[1];
      end;
      CmsgLevels(h[4], h[5], False);
      PLongInt(lm + 20)^ := h[5];
      PLongInt(lm + 24)^ := LxMsgFlags(h[6]);
    end;
  end;
end;

function MxSockCall(nr, a0, a1, a2, a3, a4, a5: LongInt): LongInt;
var m: TMxMsg;
begin
  case nr of
    1: Result := MxSocket(a0, a1, a2);
    2: Result := MxSockAddrIn(VFS_BIND, a0, a1, a2);
    3: Result := MxSockAddrIn(VFS_CONNECT, a0, a1, a2);
    4: begin MxClear(m); m[2] := a0; m[3] := a1; Result := Lx(MxCall(MX_VFS, VFS_LISTEN, m)); end;
    5: Result := MxSockAddrOut(VFS_ACCEPT, a0, a1, a2, 0);
    6: Result := MxSockAddrOut(VFS_GETSOCKNAME, a0, a1, a2, 0);
    7: Result := MxSockAddrOut(VFS_GETPEERNAME, a0, a1, a2, 0);
    8: Result := MxSocketpair(a0, a1, a2, a3);
    9: Result := MxSendto(a0, a1, a2, a3, 0, 0);         { send }
    10: Result := MxRecvfrom(a0, a1, a2, a3, 0, 0);      { recv }
    11: Result := MxSendto(a0, a1, a2, a3, a4, a5);
    12: Result := MxRecvfrom(a0, a1, a2, a3, a4, a5);
    13: begin MxClear(m); m[2] := a0; m[3] := a1; Result := Lx(MxCall(MX_VFS, VFS_SHUTDOWN, m)); end;
    14: Result := MxSockopt(False, a0, a1, a2, a3, a4);
    15: Result := MxSockopt(True, a0, a1, a2, a3, a4);
    16: Result := MxSockMsg(True, a0, a1, a2);
    17: Result := MxSockMsg(False, a0, a1, a2);
    18: Result := MxSockAddrOut(VFS_ACCEPT, a0, a1, a2, a3);   { accept4 }
  else
    Result := -LX_EINVAL;
  end;
end;

{ socketcall(call, args): the arguments are an array of longs. }
function MxSocketcall(call, args: LongInt): LongInt;
var a: array[0..5] of LongInt; i: Integer;
begin
  if (call < 1) or (call > 20) or (args = 0) then begin Result := -LX_EINVAL; Exit; end;
  for i := 0 to 5 do a[i] := 0;
  for i := 0 to 5 do
    if (call <> 1) or (i < 3) then a[i] := PLongInt(args + 4 * i)^;
  Result := MxSockCall(call, a[0], a[1], a[2], a[3], a[4], a[5]);
end;


{ ---- epoll, timerfd, eventfd ----------------------------------------------------------
  Minix has none of the three. Each is a real descriptor (opened on
  /dev/null, so close/dup/exec behave) whose state lives here, found by fd:
  FdKind 1 = epoll, 2 = timerfd, 3 = eventfd. epoll_wait selects on the real
  descriptors of its interest list, works out the emulated ones itself (a
  timer that has expired, an eventfd with a count), and wakes for the
  nearest timer deadline. Level-triggered only (EPOLLET is taken as level;
  EPOLLONESHOT disarms). close() of a watched fd drops it from every list,
  as closing the last reference does on Linux. The state is per process: a
  fork child gets a copy, which is what Linux gives it for timerfd/eventfd
  counts too. Linux i386's epoll_event is packed: events 0/4, data 4/8. }

const
  FK_EPOLL = 1; FK_TIMER = 2; FK_EVENT = 3;
  EP_N = 8; EP_E = 64; TF_N = 16; EF_N = 16;
  DevNull: array[0..9] of Byte = (47,100,101,118,47,110,117,108,108,0);   { /dev/null }

var
  FdKind, FdSlot, FdNonblock: array[0..255] of Byte;
  EpUsed: array[0..EP_N - 1] of Boolean;
  EpCnt: array[0..EP_N - 1] of LongInt;
  EpFd, EpEv: array[0..EP_N - 1, 0..EP_E - 1] of LongInt;
  EpData: array[0..EP_N - 1, 0..EP_E - 1] of Int64;
  TfUsed: array[0..TF_N - 1] of Boolean;
  TfClock: array[0..TF_N - 1] of LongInt;
  TfDeadline, TfInterval, TfExp: array[0..TF_N - 1] of Int64;   { ns on the monotonic clock; 0 = disarmed }
  EfUsed: array[0..EF_N - 1] of Boolean;
  EfCount: array[0..EF_N - 1] of Int64;
  EfSema: array[0..EF_N - 1] of Boolean;

function ClockNs(id: LongInt): Int64;
var m: TMxMsg;
begin
  MxClear(m);
  if id = 0 then m[4] := 0 else m[4] := 3;
  m[5] := 1;
  if MxCall(MX_PM, PM_CLOCK_GETTIME, m) < 0 then begin Result := 0; Exit; end;
  Result := PInt64(@m[2])^ * 1000000000 + m[4];
end;

{ A descriptor for an emulated object: kind and slot recorded. }
function FakeFd(kind, slot, flags: LongInt): LongInt;
begin
  Result := MxOpen0(LongInt(@DevNull[0]), 2 or (flags and $80000), 0);
  if Result < 0 then Exit;
  if Result > 255 then begin MxFdCall(VFS_CLOSE, Result); Result := -24; Exit; end;   { EMFILE }
  FdKind[Result] := kind; FdSlot[Result] := slot;
  if (flags and $800) <> 0 then FdNonblock[Result] := 1 else FdNonblock[Result] := 0;
end;

function IsKind(fd, kind: LongInt): Boolean;
begin
  Result := (fd >= 0) and (fd <= 255) and (FdKind[fd] = kind);
end;

{ Bring a timer's expiration count up to now. }
procedure TfUpdate(t: LongInt);
var now, late: Int64;
begin
  if TfDeadline[t] = 0 then Exit;
  now := ClockNs(1);
  if now < TfDeadline[t] then Exit;
  late := now - TfDeadline[t];
  if TfInterval[t] > 0 then
  begin
    TfExp[t] := TfExp[t] + 1 + late div TfInterval[t];
    TfDeadline[t] := TfDeadline[t] + (1 + late div TfInterval[t]) * TfInterval[t];
  end
  else
  begin
    TfExp[t] := TfExp[t] + 1;
    TfDeadline[t] := 0;
  end;
end;

{ What an emulated fd is ready for right now (EPOLLIN 1, EPOLLOUT 4). }
function FakeReady(fd: LongInt): LongInt;
begin
  Result := 0;
  case FdKind[fd] of
    FK_TIMER: begin
                TfUpdate(FdSlot[fd]);
                if TfExp[FdSlot[fd]] > 0 then Result := 1;
              end;
    FK_EVENT: begin
                Result := 4;
                if EfCount[FdSlot[fd]] > 0 then Result := Result or 1;
              end;
  end;
end;

procedure DropFd(fd: LongInt);
var i, j, k: LongInt;
begin
  for i := 0 to EP_N - 1 do
    if EpUsed[i] then
    begin
      j := 0;
      while j < EpCnt[i] do
        if EpFd[i, j] = fd then
        begin
          for k := j to EpCnt[i] - 2 do
          begin
            EpFd[i, k] := EpFd[i, k + 1]; EpEv[i, k] := EpEv[i, k + 1]; EpData[i, k] := EpData[i, k + 1];
          end;
          EpCnt[i] := EpCnt[i] - 1;
        end
        else j := j + 1;
    end;
end;

function MxClose(fd: LongInt): LongInt;
begin
  if (fd >= 0) and (fd <= 255) then
  begin
    case FdKind[fd] of
      FK_EPOLL: EpUsed[FdSlot[fd]] := False;
      FK_TIMER: TfUsed[FdSlot[fd]] := False;
      FK_EVENT: EfUsed[FdSlot[fd]] := False;
    end;
    FdKind[fd] := 0;
    DropFd(fd);
  end;
  Result := MxFdCall(VFS_CLOSE, fd);
end;

function MxEpollCreate(flags: LongInt): LongInt;
var i: LongInt;
begin
  for i := 0 to EP_N - 1 do
    if not EpUsed[i] then
    begin
      Result := FakeFd(FK_EPOLL, i, flags);
      if Result >= 0 then begin EpUsed[i] := True; EpCnt[i] := 0; end;
      Exit;
    end;
  Result := -24;                                        { EMFILE }
end;

function MxEpollCtl(ep, op, fd, ev: LongInt): LongInt;
var e, j: LongInt; found: LongInt;
begin
  if not IsKind(ep, FK_EPOLL) then begin Result := -LX_EINVAL; Exit; end;
  if (fd = ep) or (fd < 0) or (fd > 255) then begin Result := -LX_EINVAL; Exit; end;
  if MxFcntlRaw(fd, 3, 0) < 0 then begin Result := -LX_EBADF; Exit; end;
  e := FdSlot[ep];
  found := -1;
  for j := 0 to EpCnt[e] - 1 do if EpFd[e, j] = fd then found := j;
  case op of
    1: begin                                            { EPOLL_CTL_ADD }
         if found >= 0 then begin Result := -17; Exit; end;             { EEXIST }
         if EpCnt[e] >= EP_E then begin Result := -LX_ENOMEM; Exit; end;
         found := EpCnt[e]; EpCnt[e] := EpCnt[e] + 1;
         EpFd[e, found] := fd;
         EpEv[e, found] := PLongInt(ev)^; EpData[e, found] := PInt64(ev + 4)^;
       end;
    2: begin                                            { EPOLL_CTL_DEL }
         if found < 0 then begin Result := -LX_ENOENT; Exit; end;
         for j := found to EpCnt[e] - 2 do
         begin
           EpFd[e, j] := EpFd[e, j + 1]; EpEv[e, j] := EpEv[e, j + 1]; EpData[e, j] := EpData[e, j + 1];
         end;
         EpCnt[e] := EpCnt[e] - 1;
       end;
    3: begin                                            { EPOLL_CTL_MOD }
         if found < 0 then begin Result := -LX_ENOENT; Exit; end;
         EpEv[e, found] := PLongInt(ev)^; EpData[e, found] := PInt64(ev + 4)^;
       end;
  else
    begin Result := -LX_EINVAL; Exit; end;
  end;
  Result := 0;
end;

type
  TFdBits = array[0..31] of LongInt;       { a Linux fd_set: MxSelectUs writes all 128 bytes back }

{ The select sets for epoll instance e's real descriptors; anyFake when an
  emulated one is ready now; next = the nearest timer deadline (0: none). }
function EpPrepare(e: LongInt; var rd, wr, ex: TFdBits; var anyFake: Boolean;
                   var next: Int64): LongInt;
var j, fd, want: LongInt;
begin
  for j := 0 to 31 do begin rd[j] := 0; wr[j] := 0; ex[j] := 0; end;
  Result := -1; anyFake := False; next := 0;
  for j := 0 to EpCnt[e] - 1 do
  begin
    fd := EpFd[e, j]; want := EpEv[e, j];
    if (want and $7) <> 0 then
    begin
      if FdKind[fd] <> 0 then
      begin
        if (FakeReady(fd) and want) <> 0 then anyFake := True;
        if (FdKind[fd] = FK_TIMER) and (TfDeadline[FdSlot[fd]] > 0) then
          if (next = 0) or (TfDeadline[FdSlot[fd]] < next) then next := TfDeadline[FdSlot[fd]];
      end
      else
      begin
        if fd > Result then Result := fd;
        if (want and $1) <> 0 then rd[fd shr 5] := rd[fd shr 5] or (1 shl (fd and 31));
        if (want and $4) <> 0 then wr[fd shr 5] := wr[fd shr 5] or (1 shl (fd and 31));
        if (want and $2) <> 0 then ex[fd shr 5] := ex[fd shr 5] or (1 shl (fd and 31));
      end;
    end;
  end;
end;

{ Fill evs from what select (r > 0) and the emulated fds report. }
function EpCollect(e, evs, maxev, r: LongInt; var rd, wr, ex: TFdBits): LongInt;
var j, fd, want, got: LongInt;
begin
  Result := 0;
  j := 0;
  while (j < EpCnt[e]) and (Result < maxev) do
  begin
    fd := EpFd[e, j]; want := EpEv[e, j];
    got := 0;
    if FdKind[fd] <> 0 then got := FakeReady(fd) and want
    else if r > 0 then
    begin
      if ((rd[fd shr 5] shr (fd and 31)) and 1) <> 0 then got := got or (want and $1);
      if ((wr[fd shr 5] shr (fd and 31)) and 1) <> 0 then got := got or (want and $4);
      if ((ex[fd shr 5] shr (fd and 31)) and 1) <> 0 then got := got or (want and $2);
    end;
    if got <> 0 then
    begin
      PLongInt(evs + 12 * Result)^ := got;
      PInt64(evs + 12 * Result + 4)^ := EpData[e, j];
      Result := Result + 1;
      if (want and $40000000) <> 0 then EpEv[e, j] := 0;   { EPOLLONESHOT }
    end;
    j := j + 1;
  end;
end;

{ How long select may wait, in ms (-1: no limit). }
function EpWaitMs(ms: LongInt; start, next: Int64; anyFake: Boolean): LongInt;
var now, d: Int64;
begin
  if anyFake then begin Result := 0; Exit; end;
  now := ClockNs(1);
  if ms < 0 then Result := -1
  else
  begin
    d := Int64(ms) - (now - start) div 1000000;
    if d < 0 then d := 0;
    Result := LongInt(d);
  end;
  if next > 0 then
  begin
    d := (next - now + 999999) div 1000000;
    if d < 0 then d := 0;
    if (Result < 0) or (d < Result) then Result := LongInt(d);
  end;
end;

function MxEpollWait(ep, evs, maxev, ms: LongInt): LongInt;
var e, hi, r, w: LongInt; rd, wr, ex: TFdBits;
    start, next: Int64; anyFake, done: Boolean;
begin
  if not IsKind(ep, FK_EPOLL) then begin Result := -LX_EINVAL; Exit; end;
  if maxev <= 0 then begin Result := -LX_EINVAL; Exit; end;
  e := FdSlot[ep];
  start := ClockNs(1);
  Result := 0;
  done := False;
  repeat
    hi := EpPrepare(e, rd, wr, ex, anyFake, next);
    w := EpWaitMs(ms, start, next, anyFake);
    if w < 0 then r := MxSelectUs(hi + 1, LongInt(@rd[0]), LongInt(@wr[0]), LongInt(@ex[0]), 0, 0, True)
    else r := MxSelectUs(hi + 1, LongInt(@rd[0]), LongInt(@wr[0]), LongInt(@ex[0]),
                         w div 1000, (w mod 1000) * 1000, False);
    if r < 0 then begin Result := r; done := True; end
    else
    begin
      Result := EpCollect(e, evs, maxev, r, rd, wr, ex);
      if Result > 0 then done := True
      else if (ms >= 0) and ((ClockNs(1) - start) div 1000000 >= ms) then done := True;
    end;
  until done;
end;

function MxTimerfdCreate(clock, flags: LongInt): LongInt;
var i: LongInt;
begin
  if (clock <> 0) and (clock <> 1) and (clock <> 7) then begin Result := -LX_EINVAL; Exit; end;
  for i := 0 to TF_N - 1 do
    if not TfUsed[i] then
    begin
      Result := FakeFd(FK_TIMER, i, flags);
      if Result >= 0 then
      begin
        TfUsed[i] := True; TfClock[i] := clock;
        TfDeadline[i] := 0; TfInterval[i] := 0; TfExp[i] := 0;
      end;
      Exit;
    end;
  Result := -24;
end;

procedure TsPut(p: LongInt; ns: Int64);
begin
  if ns < 0 then ns := 0;
  PLongInt(p)^ := LongInt(ns div 1000000000);
  PLongInt(p + 4)^ := LongInt(ns mod 1000000000);
end;

function TsGet(p: LongInt): Int64;
begin
  Result := Int64(PLongInt(p)^) * 1000000000 + PLongInt(p + 4)^;
end;

procedure TfGet(t, cur: LongInt);
begin
  TfUpdate(t);
  TsPut(cur, TfInterval[t]);
  if TfDeadline[t] = 0 then TsPut(cur + 8, 0)
  else TsPut(cur + 8, TfDeadline[t] - ClockNs(1));
end;

{ timerfd_settime(fd, flags, new, old): itimerspec = interval, value (two
  Linux i386 timespecs). TFD_TIMER_ABSTIME (1): value is on the timer's
  clock; kept as a monotonic deadline. }
function MxTimerfdSettime(fd, flags, nv, ov: LongInt): LongInt;
var t: LongInt; v: Int64;
begin
  if not IsKind(fd, FK_TIMER) then begin Result := -LX_EINVAL; Exit; end;
  t := FdSlot[fd];
  if ov <> 0 then TfGet(t, ov);
  TfExp[t] := 0;
  TfInterval[t] := TsGet(nv);
  v := TsGet(nv + 8);
  if v = 0 then TfDeadline[t] := 0
  else if (flags and 1) <> 0 then
    TfDeadline[t] := ClockNs(1) + (v - ClockNs(TfClock[t]))
  else TfDeadline[t] := ClockNs(1) + v;
  if (TfDeadline[t] <= 0) and (v <> 0) then TfDeadline[t] := 1;   { already passed }
  Result := 0;
end;

function MxEventfd(initval, flags: LongInt): LongInt;
var i: LongInt;
begin
  for i := 0 to EF_N - 1 do
    if not EfUsed[i] then
    begin
      Result := FakeFd(FK_EVENT, i, flags);
      if Result >= 0 then
      begin
        EfUsed[i] := True; EfCount[i] := LongWord(initval);
        EfSema[i] := (flags and 1) <> 0;                 { EFD_SEMAPHORE }
      end;
      Exit;
    end;
  Result := -24;
end;

{ read/write on an emulated fd; kind is known to be non-zero. A blocking
  read of an empty eventfd cannot be woken (no other thread): EAGAIN. }
function FakeRw(isRead: Boolean; fd, buf, len: LongInt): LongInt;
var t: LongInt; d: Int64;
begin
  Result := -LX_EINVAL;
  case FdKind[fd] of
    FK_EPOLL: Exit;
    FK_TIMER:
      begin
        if not isRead then Exit;
        if len < 8 then Exit;
        t := FdSlot[fd];
        while True do
        begin
          TfUpdate(t);
          if TfExp[t] > 0 then Break;
          if (FdNonblock[fd] <> 0) or (TfDeadline[t] = 0) then begin Result := -11; Exit; end;
          d := (TfDeadline[t] - ClockNs(1) + 999) div 1000;
          if d < 0 then d := 0;
          MxSleepUs(LongInt(d div 1000000), LongInt(d mod 1000000));
        end;
        PInt64(buf)^ := TfExp[t];
        TfExp[t] := 0;
        Result := 8;
      end;
    FK_EVENT:
      begin
        if len < 8 then Exit;
        t := FdSlot[fd];
        if isRead then
        begin
          if EfCount[t] = 0 then begin Result := -11; Exit; end;
          if EfSema[t] then begin PInt64(buf)^ := 1; EfCount[t] := EfCount[t] - 1; end
          else begin PInt64(buf)^ := EfCount[t]; EfCount[t] := 0; end;
        end
        else
        begin
          d := PInt64(buf)^;
          if d = -1 then Exit;
          EfCount[t] := EfCount[t] + d;
        end;
        Result := 8;
      end;
  end;
end;

{ ---- links -------------------------------------------------------------------- }

{ mess_lc_vfs_link: name1 8, name2 12, len1 16, len2 20 (rename, symlink) }
function LinkCall(typ, n1, n2: LongInt): LongInt;
var m: TMxMsg;
begin
  if (n1 = 0) or (n2 = 0) then begin Result := -LX_EFAULT; Exit; end;
  MxClear(m);
  m[2] := n1; m[3] := n2; m[4] := StrLen0(n1) + 1; m[5] := StrLen0(n2) + 1;
  Result := Lx(MxCall(MX_VFS, typ, m));
end;

{ mess_lc_vfs_readlink: name 8, namelen 12, buf 16, bufsize 20 }
function MxReadlink(path, buf, cap: LongInt): LongInt;
var m: TMxMsg;
begin
  MxClear(m);
  m[2] := path; m[3] := StrLen0(path) + 1; m[4] := buf; m[5] := cap;
  Result := Lx(MxCall(MX_VFS, VFS_READLINK, m));
end;

{ ---- descriptors --------------------------------------------------------------- }

{ mess_lc_vfs_fcntl: fd 8, cmd 12, arg_int 16, arg_ptr 20 }
function MxFcntlRaw(fd, cmd, arg: LongInt): LongInt;
var m: TMxMsg;
begin
  MxClear(m);
  m[2] := fd; m[3] := cmd; m[4] := arg; m[5] := arg;
  Result := Lx(MxCall(MX_VFS, VFS_FCNTL, m));
end;

{ The status flags F_GETFL/F_SETFL carry, both ways. }
function FlToLinux(f: LongInt): LongInt;
begin
  Result := f and 3;
  if (f and $4) <> 0 then Result := Result or $800;    { O_NONBLOCK }
  if (f and $8) <> 0 then Result := Result or $400;    { O_APPEND }
end;

function MxFcntl(fd, cmd, arg: LongInt): LongInt;
begin
  case cmd of
    0, 1, 2: Result := MxFcntlRaw(fd, cmd, arg);       { F_DUPFD, F_GETFD, F_SETFD: same }
    1030: Result := MxFcntlRaw(fd, 12, arg);            { F_DUPFD_CLOEXEC }
    3: begin                                            { F_GETFL }
         Result := MxFcntlRaw(fd, 3, 0);
         if Result >= 0 then Result := FlToLinux(Result);
       end;
    4: begin                                            { F_SETFL: NONBLOCK, APPEND }
         if (fd >= 0) and (fd <= 255) and (FdKind[fd] <> 0) then
           if (arg and $800) <> 0 then FdNonblock[fd] := 1 else FdNonblock[fd] := 0;
         Result := MxFcntlRaw(fd, 4, MxOpenFlags(arg) and $C);
       end;
  else
    Result := -LX_EINVAL;
  end;
end;

{ dup2/dup3 as Minix's libc has it: check fd, close fd2, F_DUPFD from fd2. }
function MxDup3(fd, fd2, flags: LongInt): LongInt;
begin
  Result := MxFcntlRaw(fd, 3, 0);
  if Result < 0 then Exit;
  if fd = fd2 then begin Result := fd2; Exit; end;
  MxFdCall(VFS_CLOSE, fd2);
  if (flags and $80000) <> 0 then Result := MxFcntlRaw(fd, 12, fd2)
  else Result := MxFcntlRaw(fd, 0, fd2);
end;

{ pipe2(fds, flags): mess_lc_vfs_pipe2.flags at 8; mess_vfs_lc_fdpair back. }
function MxPipe2(fds, flags: LongInt): LongInt;
var m: TMxMsg;
begin
  MxClear(m);
  m[2] := MxOpenFlags(flags) and ($400000 or $4);      { O_CLOEXEC, O_NONBLOCK }
  Result := Lx(MxCall(MX_VFS, VFS_PIPE2, m));
  if Result >= 0 then
  begin
    PLongInt(fds)^ := m[2];
    PLongInt(fds + 4)^ := m[3];
    Result := 0;
  end;
end;

{ ---- processes ------------------------------------------------------------------ }

{ A Minix signal number back to Linux's. }
function SigToLinux(n: LongInt): LongInt;
var i: Integer;
begin
  Result := n;
  for i := 1 to 31 do
    if SigMap[i] = n then begin Result := i; Exit; end;
end;

{ The wait status layout is Linux's; only the signal numbers in it differ. }
function StatusToLinux(st: LongInt): LongInt;
var low: LongInt;
begin
  low := st and $7F;
  if (low = 0) or (st = $FFFF) then Result := st                     { exited, continued }
  else if low = $7F then
    Result := (st and (not $FF00)) or (SigToLinux((st shr 8) and $FF) shl 8)   { stopped }
  else Result := (st and (not $7F)) or SigToLinux(low);              { signalled }
end;

{ wait4(pid, status, options, rusage): mess_lc_pm_wait4 pid 8, options 12,
  addr 16 (Minix's struct rusage; not passed: Linux's differs, and is
  zeroed). The status word is encoded as Linux's. WNOHANG/WUNTRACED: same. }
function MxWait4(pid, status, options, ru: LongInt): LongInt;
var m: TMxMsg; i: Integer;
begin
  MxClear(m);
  m[2] := pid; m[3] := options and 3;
  if (options and 8) <> 0 then m[3] := m[3] or $10;    { WCONTINUED }
  Result := Lx(MxCall(MX_PM, PM_WAIT4, m));
  if Result < 0 then Exit;
  if (status <> 0) and (Result > 0) then PLongInt(status)^ := StatusToLinux(m[2]);
  if ru <> 0 then for i := 0 to 17 do PLongInt(ru + i * 4)^ := 0;
end;

{ execve: Minix builds the new process's stack in the CALLER (stack_utils.c)
  and PM copies it in: argc, argv[] and envp[] as addresses in the new image
  (its stack ends at MX_USER_SP), room for the aux vector and the exec name,
  the strings, then struct ps_strings. Only returns on failure. }
function MxExecve(path, argv, envp: LongInt): LongInt;
var m: TMxMsg; argc, envc, sz, p, frame, vsp, fpw, fp, n, i, k, ps: LongInt;
begin
  if path = 0 then begin Result := -LX_EFAULT; Exit; end;
  argc := 0; envc := 0; sz := MX_STACK_MIN;
  p := argv;
  while (p <> 0) and (PLongInt(p)^ <> 0) do
  begin
    sz := sz + 4 + StrLen0(PLongInt(p)^) + 1; argc := argc + 1; p := p + 4;
  end;
  p := envp;
  while (p <> 0) and (PLongInt(p)^ <> 0) do
  begin
    sz := sz + 4 + StrLen0(PLongInt(p)^) + 1; envc := envc + 1; p := p + 4;
  end;
  sz := (sz + 3) and (not 3);
  if sz > 256 * 1024 then begin Result := -7; Exit; end;          { E2BIG }
  frame := MxMmap(0, (sz + $FFF) and (not $FFF), 3, $22, -1, 0);
  if (frame < 0) and (frame >= -4095) then begin Result := frame; Exit; end;
  vsp := LongInt(LongWord(MX_USER_SP) - LongWord(sz));
  fpw := frame;
  PLongInt(fpw)^ := argc; fpw := fpw + 4;
  fp := frame + (MX_STACK_MIN - 16) + (envc + argc) * 4;
  for i := 0 to 1 do
  begin
    if i = 0 then p := argv else p := envp;
    while (p <> 0) and (PLongInt(p)^ <> 0) do
    begin
      n := StrLen0(PLongInt(p)^) + 1;
      PLongInt(fpw)^ := vsp + (fp - frame); fpw := fpw + 4;
      for k := 0 to n - 1 do PByte(fp + k)^ := PByte(PLongInt(p)^ + k)^;
      fp := fp + n; p := p + 4;
    end;
    PLongInt(fpw)^ := 0; fpw := fpw + 4;
  end;
  while (fp and 3) <> 0 do begin PByte(fp)^ := 0; fp := fp + 1; end;
  ps := fp;
  PLongInt(ps)^ := vsp + 4;                             { ps_argvstr }
  PLongInt(ps + 4)^ := argc;                            { ps_nargvstr }
  PLongInt(ps + 8)^ := vsp + 4 + (argc + 1) * 4;        { ps_envstr }
  PLongInt(ps + 12)^ := envc;                           { ps_nenvstr }
  MxClear(m);                                           { mess_lc_pm_exec }
  m[2] := path; m[3] := StrLen0(path) + 1; m[4] := frame; m[5] := sz;
  m[6] := vsp + (ps - frame);
  Result := Lx(MxCall(MX_PM, PM_EXEC, m));
  if Result >= 0 then Result := -LX_EINVAL;
  MxMunmap(frame, (sz + $FFF) and (not $FFF));
end;

function MxKill(pid, sig: LongInt): LongInt;
var m: TMxMsg;
begin
  if (sig < 0) or (sig > 31) or ((sig <> 0) and (SigMap[sig] = 0)) then
  begin Result := -LX_EINVAL; Exit; end;
  MxClear(m);
  m[2] := pid;
  if sig = 0 then m[3] := 0 else m[3] := SigMap[sig];   { mess_lc_pm_sig: pid, nr }
  Result := Lx(MxCall(MX_PM, PM_KILL, m));
end;

{ ---- sysctl and uname --------------------------------------------------------------- }

{ A string sysctl {a, b} into buf (cap bytes, always NUL-terminated).
  mess_lc_mib_sysctl: oldp 8, oldlen 12, newp 16, newlen 20, namelen 24,
  namep 28, name[8] 32. }
function SysctlStr(a, b, buf, cap: LongInt): LongInt;
var m: TMxMsg; name: array[0..1] of LongInt;
begin
  name[0] := a; name[1] := b;
  MxClear(m);
  m[2] := buf; m[3] := cap - 1; m[6] := 2; m[7] := LongInt(@name[0]);
  m[8] := a; m[9] := b;
  PByte(buf)^ := 0;
  Result := Lx(MxCall(MX_MIB, MIB_SYSCTL, m));
  PByte(buf + cap - 1)^ := 0;
end;

{ uname: struct new_utsname, six 65-byte fields. }
function MxUname(u: LongInt): LongInt;
var i: Integer;
const Sys: array[0..4] of Byte = (77, 105, 110, 105, 120);   { Minix }
begin
  for i := 0 to 6 * 65 - 1 do PByte(u + i)^ := 0;
  for i := 0 to 4 do PByte(u + i)^ := Sys[i];
  SysctlStr(1, 10, u + 65, 65);                         { kern.hostname }
  SysctlStr(1, 2, u + 130, 65);                         { kern.osrelease }
  SysctlStr(1, 4, u + 195, 65);                         { kern.version }
  for i := 195 to 259 do if PByte(u + i)^ = 10 then PByte(u + i)^ := 0;
  SysctlStr(6, 2, u + 260, 65);                         { hw.machine_arch: i386 }
  Result := 0;
end;

{ ---- getcwd: Minix's VFS has none ---------------------------------------------------
  Walk up as Minix's libc does: compare "." with each parent's entries,
  through "..", "../..", ... until the directory is its own parent. }

function StatRaw(path, st: LongInt; typ: LongInt): LongInt;
var m: TMxMsg;
begin
  MxClear(m);
  m[2] := StrLen0(path) + 1; m[3] := path; m[4] := st;
  Result := MxCall(MX_VFS, typ, m);
end;

function MxGetcwd(buf, cap: LongInt): LongInt;
var up: array[0..1099] of Byte; ent: array[0..1099] of Byte;
    out: array[0..1027] of Byte;
    cur, par, est: array[0..31] of LongInt;
    m: TMxMsg; dir: array[0..4095] of Byte;
    ulen, olen, fd, n, i, rl, nl, k, p: LongInt; found: Boolean;
begin
  olen := 0;                                            { out is built from its END }
  up[0] := 46; up[1] := 0; ulen := 1;                   { "." }
  if StatRaw(LongInt(@up[0]), LongInt(@cur[0]), VFS_STAT) < 0 then
  begin Result := -LX_ENOENT; Exit; end;
  while True do
  begin
    { up := up + "/.." (or ".." the first time) }
    if ulen + 4 > 1090 then begin Result := -LX_ERANGE; Exit; end;
    if ulen = 1 then begin up[0] := 46; up[1] := 46; ulen := 2; end
    else begin up[ulen] := 47; up[ulen + 1] := 46; up[ulen + 2] := 46; ulen := ulen + 3; end;
    up[ulen] := 0;
    if StatRaw(LongInt(@up[0]), LongInt(@par[0]), VFS_STAT) < 0 then
    begin Result := -LX_ENOENT; Exit; end;
    { at the root: "." and ".." are the same directory }
    if (PInt64(@par[3])^ = PInt64(@cur[3])^) and (par[0] = cur[0]) and (par[1] = cur[1]) then Break;
    fd := MxOpen(LongInt(@up[0]), $10000, 0);           { O_RDONLY | O_DIRECTORY }
    if fd < 0 then begin Result := fd; Exit; end;
    found := False;
    repeat
      MxClear(m);
      m[2] := fd; m[3] := LongInt(@dir[0]); m[4] := 4096;
      n := MxCall(MX_VFS, VFS_GETDENTS, m);
      if n <= 0 then Break;
      i := 0;
      while (i < n) and not found do
      begin
        p := LongInt(@dir[0]) + i;
        rl := PWord(p + 8)^; nl := PWord(p + 10)^;
        if rl = 0 then Break;
        if not ((nl = 1) and (PByte(p + 13)^ = 46)) and
           not ((nl = 2) and (PByte(p + 13)^ = 46) and (PByte(p + 14)^ = 46)) then
        begin
          { same device: the inode decides; across a mount, stat the entry }
          if (par[0] = cur[0]) and (par[1] = cur[1]) then
            found := PInt64(p)^ = PInt64(@cur[3])^
          else if ulen + 1 + nl < 1090 then
          begin
            for k := 0 to ulen - 1 do ent[k] := up[k];
            ent[ulen] := 47;
            for k := 0 to nl - 1 do ent[ulen + 1 + k] := PByte(p + 13 + k)^;
            ent[ulen + 1 + nl] := 0;
            if StatRaw(LongInt(@ent[0]), LongInt(@est[0]), VFS_LSTAT) >= 0 then
              found := (PInt64(@est[3])^ = PInt64(@cur[3])^) and (est[0] = cur[0]) and (est[1] = cur[1]);
          end;
          if found then
          begin
            if olen + nl + 1 > 1024 then begin MxFdCall(VFS_CLOSE, fd); Result := -LX_ERANGE; Exit; end;
            for k := 0 to nl - 1 do out[1027 - olen - nl + 1 + k] := PByte(p + 13 + k)^;
            olen := olen + nl;
            out[1027 - olen] := 47;
            olen := olen + 1;
          end;
        end;
        i := i + rl;
      end;
    until found;
    MxFdCall(VFS_CLOSE, fd);
    if not found then begin Result := -LX_ENOENT; Exit; end;
    for k := 0 to 31 do cur[k] := par[k];
  end;
  if olen = 0 then begin out[1027] := 47; olen := 1; end;
  if olen + 1 > cap then begin Result := -LX_ERANGE; Exit; end;
  for k := 0 to olen - 1 do PByte(buf + k)^ := out[1028 - olen + k];
  PByte(buf + olen)^ := 0;
  Result := olen + 1;                                   { Linux: the length with the NUL }
end;

{ ---- the start-up environment ------------------------------------------------ }

{ An fd that reads len bytes from buf: a pipe when it fits the pipe buffer,
  else an unlinked file in /tmp. }
function MxDataFd(buf, len: LongInt): LongInt;
var m: TMxMsg; name: array[0..31] of Byte; fd, v, k, i: LongInt;
    fds: array[0..1] of LongInt; pos: Int64;
const Pre: array[0..10] of Byte = (47,116,109,112,47,46,112,120,120,101,110);   { /tmp/.pxxen }
begin
  if len <= 4096 then
  begin
    MxClear(m);
    m[2] := $400000;                                  { mess_lc_vfs_pipe2.flags: O_CLOEXEC }
    Result := MxCall(MX_VFS, $11A, m);                { VFS_PIPE2 }
    if Result >= 0 then
    begin
      fds[0] := m[2]; fds[1] := m[3];                 { mess_vfs_lc_fdpair }
      if len > 0 then MxRw(VFS_WRITE, fds[1], buf, len);
      MxFdCall(VFS_CLOSE, fds[1]);
      Result := fds[0];
      Exit;
    end;
  end;
  for i := 0 to 10 do name[i] := Pre[i];
  k := 11;
  MxTmpSeq := MxTmpSeq + 1;
  MxClear(m);
  v := MxCall(MX_PM, PM_GETPID, m) * 1000 + MxTmpSeq;
  while v > 0 do begin name[k] := 48 + (v mod 10); v := v div 10; k := k + 1; end;
  name[k] := 0;
  fd := MxOpen(LongInt(@name[0]), 2 or $40 or $80 or $80000, 384);
  if fd < 0 then begin Result := fd; Exit; end;
  PathCall(VFS_UNLINK, LongInt(@name[0]), 0, 0);
  MxRw(VFS_WRITE, fd, buf, len);
  MxLseek(fd, 0, 0, 0, pos);
  Result := fd;
end;

{ /proc/self/environ: the envp strings NUL-terminated, from the initial
  stack (argc, argv[], NULL, envp[], NULL), copied into a fresh mapping. }
function MxProcEnviron: LongInt;
var p, sz, outp, n, s, i: LongInt;
begin
  if MxInitSp = 0 then begin Result := -LX_ENOENT; Exit; end;
  p := MxInitSp + 4 + (PLongInt(MxInitSp)^ + 1) * 4;
  sz := 0; s := p;
  while PLongInt(s)^ <> 0 do
  begin
    sz := sz + StrLen0(PLongInt(s)^) + 1;
    s := s + 4;
  end;
  sz := (sz + 1 + $FFF) and (not $FFF);
  outp := MxMmap(0, sz, 3, $22, -1, 0);
  if (outp < 0) and (outp >= -4095) then begin Result := -LX_ENOMEM; Exit; end;   { an address can be "negative" }
  n := 0; s := p;
  while PLongInt(s)^ <> 0 do
  begin
    i := PLongInt(s)^;
    while PByte(i)^ <> 0 do
    begin
      PByte(outp + n)^ := PByte(i)^; n := n + 1; i := i + 1;
    end;
    PByte(outp + n)^ := 0; n := n + 1;
    s := s + 4;
  end;
  Result := MxDataFd(outp, n);
  MxMunmap(outp, sz);
end;

function PathIs(p: LongInt; w: PByte; n: Integer): Boolean;
var i: Integer;
begin
  Result := False;
  if p = 0 then Exit;
  for i := 0 to n - 1 do
    if PByte(p + i)^ <> w[i] then Exit;
  Result := PByte(p + n)^ = 0;
end;

const
  ProcEnviron: array[0..17] of Byte = (47,112,114,111,99,47,115,101,108,102,47,
                                       101,110,118,105,114,111,110);   { /proc/self/environ }

  ProcHostname: array[0..24] of Byte = (47,112,114,111,99,47,115,121,115,47,107,101,114,
                                        110,101,108,47,104,111,115,116,110,97,109,101);  { /proc/sys/kernel/hostname }

{ /proc/sys/kernel/hostname: kern.hostname and a newline. }
function MxProcHostname: LongInt;
var b: array[0..271] of Byte; n: LongInt;
begin
  SysctlStr(1, 10, LongInt(@b[0]), 256);
  n := StrLen0(LongInt(@b[0]));
  b[n] := 10;
  Result := MxDataFd(LongInt(@b[0]), n + 1);
end;

function MxOpenAt(dirfd, path, flags, mode: LongInt): LongInt;
begin
  if path = 0 then Result := -LX_EFAULT
  else if PathIs(path, @ProcEnviron[0], 18) then Result := MxProcEnviron
  else if PathIs(path, @ProcHostname[0], 25) then Result := MxProcHostname
  else if not DirOk(dirfd, path) then Result := -LX_ENOSYS
  else Result := MxOpen(path, flags, mode);
end;


const
  ProcExe: array[0..13] of Byte = (47,112,114,111,99,47,115,101,108,102,47,
                                   101,120,101);                        { /proc/self/exe }
  ProcFd: array[0..13] of Byte = (47,112,114,111,99,47,115,101,108,102,47,102,100,47); { /proc/self/fd/ }

{ readlink("/proc/self/exe"): the AT_SUN_EXECNAME (2014) entry of the aux
  vector VFS put after envp on the initial stack. }
function MxProcExe(buf, cap: LongInt): LongInt;
var p, n, i: LongInt;
begin
  Result := -LX_ENOENT;
  if MxInitSp = 0 then Exit;
  p := MxInitSp + 4 + (PLongInt(MxInitSp)^ + 1) * 4;
  while PLongInt(p)^ <> 0 do p := p + 4;
  p := p + 4;
  while PLongInt(p)^ <> 0 do
  begin
    if PLongInt(p)^ = 2014 then
    begin
      n := StrLen0(PLongInt(p + 4)^);
      if n > cap then n := cap;
      for i := 0 to n - 1 do PByte(buf + i)^ := PByte(PLongInt(p + 4)^ + i)^;
      Result := n;
      Exit;
    end;
    p := p + 8;
  end;
end;

{ readlink("/proc/self/fd/N") for a DIRECTORY fd (what fchdir and the *at
  emulation need): fchdir to it, getcwd, and back. Anything else ENOENT. }
function MxProcFdLink(path, buf, cap: LongInt): LongInt;
var fd, i, c, n: LongInt; save: array[0..1027] of Byte; tmp: array[0..1027] of Byte;
begin
  fd := 0; i := 14;
  while (PByte(path + i)^ >= 48) and (PByte(path + i)^ <= 57) do
  begin fd := fd * 10 + PByte(path + i)^ - 48; i := i + 1; end;
  if (i = 14) or (PByte(path + i)^ <> 0) then begin Result := -LX_ENOENT; Exit; end;
  if MxGetcwd(LongInt(@save[0]), 1028) < 0 then begin Result := -LX_ENOENT; Exit; end;
  if MxFdCall(VFS_FCHDIR, fd) < 0 then begin Result := -LX_ENOENT; Exit; end;
  n := MxGetcwd(LongInt(@tmp[0]), 1028);
  PathCall(VFS_CHDIR, LongInt(@save[0]), 0, 0);
  if n < 0 then begin Result := n; Exit; end;
  n := n - 1;
  if n > cap then n := cap;
  for c := 0 to n - 1 do PByte(buf + c)^ := tmp[c];
  Result := n;
end;

function PrefixIs(p: LongInt; w: PByte; n: Integer): Boolean;
var i: Integer;
begin
  Result := False;
  if p = 0 then Exit;
  for i := 0 to n - 1 do
    if PByte(p + i)^ <> w[i] then Exit;
  Result := True;
end;

function MxReadlinkAny(dirfd, path, buf, cap: LongInt): LongInt;
begin
  if path = 0 then Result := -LX_EFAULT
  else if PathIs(path, @ProcExe[0], 14) then Result := MxProcExe(buf, cap)
  else if PrefixIs(path, @ProcFd[0], 14) then Result := MxProcFdLink(path, buf, cap)
  else if not DirOk(dirfd, path) then Result := -LX_ENOSYS
  else Result := MxReadlink(path, buf, cap);
end;

{ ---- the entry --------------------------------------------------------------- }

function PXXMinixSyscall(nr, a0, a1, a2, a3, a4, a5: LongInt): LongInt; cdecl;
var m: TMxMsg; i: Integer; pos: Int64;
begin
  case nr of
    $7F000001:                                        { MX_PXX_INITSP: the entry stub }
      begin MxInitSp := a0; Result := 0; end;
    1, 252:                                           { exit, exit_group }
      begin
        MxClear(m); m[2] := a0;
        MxCall(MX_PM, PM_EXIT, m);
        Result := 0;
      end;
    3: if (a0 >= 0) and (a0 <= 255) and (FdKind[a0] <> 0) then Result := FakeRw(True, a0, a1, a2)
       else Result := MxRead(a0, a1, a2);
    4: if (a0 >= 0) and (a0 <= 255) and (FdKind[a0] <> 0) then Result := FakeRw(False, a0, a1, a2)
       else Result := MxRw(VFS_WRITE, a0, a1, a2);
    5: Result := MxOpenAt(LX_AT_FDCWD, a0, a1, a2);   { open }
    295: Result := MxOpenAt(a0, a1, a2, a3);          { openat }
    6: Result := MxClose(a0);
    19: begin                                         { lseek }
          if a1 < 0 then i := -1 else i := 0;
          Result := MxLseek(a0, a1, i, a2, pos);
          if Result = 0 then
          begin
            if (pos > $7FFFFFFF) or (pos < 0) then Result := -LX_EOVERFLOW
            else Result := LongInt(pos);
          end;
        end;
    140: begin                                        { _llseek(fd, hi, lo, &result, whence) }
           Result := MxLseek(a0, a2, a1, a4, pos);
           if (Result = 0) and (a3 <> 0) then PInt64(a3)^ := pos;
         end;
    20: begin MxClear(m); Result := Lx(MxCall(MX_PM, PM_GETPID, m)); end;
    64: begin MxClear(m); MxCall(MX_PM, PM_GETPID, m); Result := m[2]; end;  { getppid: m_pm_lc_getpid.parent_pid }
    199, 201: begin MxClear(m); Result := Lx(MxCall(MX_PM, PM_GETUID, m));   { getuid32 / geteuid32 }
                if (nr = 201) and (Result >= 0) then Result := m[2]; end;
    200, 202: begin MxClear(m); Result := Lx(MxCall(MX_PM, PM_GETGID, m));   { getgid32 / getegid32 }
                if (nr = 202) and (Result >= 0) then Result := m[2]; end;
    37: Result := MxKill(a0, a1);
    192: Result := MxMmap(a0, a1, a2, a3, a4, a5);     { mmap2 }
    91: Result := MxMunmap(a0, a1);
    125, 219: Result := 0;                            { mprotect, madvise: no such calls; the pages stay RW }
    45: Result := 0;                                  { brk: the runtime maps its heap; "no break" }
    10: Result := PathCall(VFS_UNLINK, a0, 0, 0);
    301: if not DirOk(a0, a1) then Result := -LX_ENOSYS        { unlinkat }
         else if (a2 and LX_AT_REMOVEDIR) <> 0 then Result := PathCall(VFS_RMDIR, a1, 0, 0)
         else Result := PathCall(VFS_UNLINK, a1, 0, 0);
    40: Result := PathCall(VFS_RMDIR, a0, 0, 0);
    39: Result := PathCall(VFS_MKDIR, a0, 0, a1);
    296: if not DirOk(a0, a1) then Result := -LX_ENOSYS        { mkdirat }
         else Result := PathCall(VFS_MKDIR, a1, 0, a2);
    12: Result := PathCall(VFS_CHDIR, a0, 0, 0);
    133: Result := MxFdCall(VFS_FCHDIR, a0);
    33: Result := PathCall(VFS_ACCESS, a0, 0, a1);
    307: if not DirOk(a0, a1) then Result := -LX_ENOSYS        { faccessat }
         else Result := PathCall(VFS_ACCESS, a1, 0, a2);
    15: Result := PathCall(VFS_CHMOD, a0, 0, a1);
    306: if not DirOk(a0, a1) then Result := -LX_ENOSYS        { fchmodat }
         else Result := PathCall(VFS_CHMOD, a1, 0, a2);
    38, 302: begin                                    { rename, renameat }
           if nr = 302 then
           begin
             if not (DirOk(a0, a1) and DirOk(a2, a3)) then begin Result := -LX_ENOSYS; Exit; end;
             a0 := a1; a1 := a3;
           end;
           MxClear(m);                                { mess_lc_vfs_link: name1, name2, len1, len2 }
           m[2] := a0; m[3] := a1; m[4] := StrLen0(a0) + 1; m[5] := StrLen0(a1) + 1;
           Result := Lx(MxCall(MX_VFS, VFS_RENAME, m));
         end;
    383: Result := MxStatx(a0, a1, a2, a4);            { statx }
    220: Result := MxGetdents(a0, a1, a2);             { getdents64 }
    54: Result := MxIoctl(a0, a1, a2);
    118, 148: Result := MxFdCall(VFS_FSYNC, a0);       { fsync, fdatasync }
    36: begin MxClear(m); Result := Lx(MxCall(MX_VFS, VFS_SYNC, m)); end;
    60: begin MxClear(m); m[2] := a0; Result := Lx(MxCall(MX_VFS, VFS_UMASK, m)); end;
    93: begin MxClear(m); m[2] := a1; if a1 < 0 then m[3] := -1; m[4] := a0;   { ftruncate: offset 8/8, fd 16 }
          Result := Lx(MxCall(MX_VFS, VFS_FTRUNCATE, m)); end;
    265: Result := MxClockGettime(a0, a1, PM_CLOCK_GETTIME);
    266: Result := MxClockGettime(a0, a1, PM_CLOCK_GETRES);
    { processes }
    2: begin MxClear(m); Result := Lx(MxCall(MX_PM, PM_FORK, m)); end;   { fork }
    190: begin MxClear(m); Result := Lx(MxCall(MX_PM, PM_FORK, m)); end; { vfork: a fork }
    114: Result := MxWait4(a0, a1, a2, a3);
    7: Result := MxWait4(a0, a1, a2, 0);                { waitpid }
    11: Result := MxExecve(a0, a1, a2);
    { descriptors }
    41: Result := MxFcntlRaw(a0, 0, 0);                 { dup }
    63: Result := MxDup3(a0, a1, 0);                    { dup2 }
    330: Result := MxDup3(a0, a1, a2);                  { dup3 }
    55, 221: Result := MxFcntl(a0, a1, a2);             { fcntl, fcntl64 }
    42: Result := MxPipe2(a0, 0);                       { pipe }
    331: Result := MxPipe2(a0, a1);                     { pipe2 }
    { links, names }
    83: Result := LinkCall(VFS_SYMLINK, a0, a1);        { symlink(target, linkpath) }
    304: if not DirOk(a1, a2) then Result := -LX_ENOSYS  { symlinkat(target, dirfd, linkpath) }
         else Result := LinkCall(VFS_SYMLINK, a0, a2);
    9: Result := LinkCall($106, a0, a1);                { link (VFS_LINK) }
    303: if not (DirOk(a0, a1) and DirOk(a2, a3)) then Result := -LX_ENOSYS   { linkat }
         else Result := LinkCall($106, a1, a3);
    85: Result := MxReadlinkAny(LX_AT_FDCWD, a0, a1, a2);
    305: Result := MxReadlinkAny(a0, a1, a2, a3);
    183: Result := MxGetcwd(a0, a1);
    122: Result := MxUname(a0);
    174: Result := MxRtSigaction(a0, a1, a2);
    175: Result := MxRtSigprocmask(a0, a1, a2);
    176: Result := MxRtSigpending(a0);
    179: Result := MxRtSigsuspend(a0);
    177: Result := MxRtSigtimedwait(a0, a1, a2);
    254: Result := MxEpollCreate(0);                     { epoll_create }
    329: Result := MxEpollCreate(a0);                    { epoll_create1 }
    255: Result := MxEpollCtl(a0, a1, a2, a3);
    256: Result := MxEpollWait(a0, a1, a2, a3);          { epoll_wait }
    319: Result := MxEpollWait(a0, a1, a2, a3);          { epoll_pwait (mask ignored) }
    322: Result := MxTimerfdCreate(a0, a1);
    325: Result := MxTimerfdSettime(a0, a1, a2, a3);
    326: if IsKind(a0, FK_TIMER) then begin TfGet(FdSlot[a0], a1); Result := 0; end
         else Result := -LX_EINVAL;                      { timerfd_gettime }
    323: Result := MxEventfd(a0, 0);                     { eventfd }
    328: Result := MxEventfd(a0, a1);                    { eventfd2 }
    102: Result := MxSocketcall(a0, a1);
    359: Result := MxSockCall(1, a0, a1, a2, 0, 0, 0);    { socket }
    360: Result := MxSockCall(8, a0, a1, a2, a3, 0, 0);   { socketpair }
    361: Result := MxSockCall(2, a0, a1, a2, 0, 0, 0);    { bind }
    362: Result := MxSockCall(3, a0, a1, a2, 0, 0, 0);    { connect }
    363: Result := MxSockCall(4, a0, a1, 0, 0, 0, 0);     { listen }
    364: Result := MxSockCall(18, a0, a1, a2, a3, 0, 0);  { accept4 }
    365: Result := MxSockCall(15, a0, a1, a2, a3, a4, 0); { getsockopt }
    366: Result := MxSockCall(14, a0, a1, a2, a3, a4, 0); { setsockopt }
    367: Result := MxSockCall(6, a0, a1, a2, 0, 0, 0);    { getsockname }
    368: Result := MxSockCall(7, a0, a1, a2, 0, 0, 0);    { getpeername }
    369: Result := MxSockCall(11, a0, a1, a2, a3, a4, a5);{ sendto }
    370: Result := MxSockCall(16, a0, a1, a2, 0, 0, 0);   { sendmsg }
    371: Result := MxSockCall(12, a0, a1, a2, a3, a4, a5);{ recvfrom }
    372: Result := MxSockCall(17, a0, a1, a2, 0, 0, 0);   { recvmsg }
    373: Result := MxSockCall(13, a0, a1, 0, 0, 0, 0);    { shutdown }
    145: Result := MxRwv(VFS_READ, a0, a1, a2);         { readv }
    146: Result := MxRwv(VFS_WRITE, a0, a1, a2);        { writev }
    180: Result := MxPrw(VFS_READ, a0, a1, a2, a3, a4, False);   { pread64 }
    181: Result := MxPrw(VFS_WRITE, a0, a1, a2, a3, a4, False);  { pwrite64 }
    333: Result := MxPrw(VFS_READ, a0, a1, a2, a3, a4, True);    { preadv }
    334: Result := MxPrw(VFS_WRITE, a0, a1, a2, a3, a4, True);   { pwritev }
    142: if a4 = 0 then Result := MxSelectUs(a0, a1, a2, a3, 0, 0, True)        { _newselect }
         else Result := MxSelectUs(a0, a1, a2, a3, PLongInt(a4)^, PLongInt(a4 + 4)^, False);
    308: if a4 = 0 then Result := MxSelectUs(a0, a1, a2, a3, 0, 0, True)        { pselect6 (mask ignored) }
         else Result := MxSelectUs(a0, a1, a2, a3, PLongInt(a4)^, (PLongInt(a4 + 4)^ + 999) div 1000, False);
    168: if a2 < 0 then Result := MxPoll(a0, a1, 0, 0, True)                   { poll }
         else Result := MxPoll(a0, a1, a2 div 1000, (a2 mod 1000) * 1000, False);
    309: if a2 = 0 then Result := MxPoll(a0, a1, 0, 0, True)                   { ppoll (mask ignored) }
         else Result := MxPoll(a0, a1, PLongInt(a2)^, (PLongInt(a2 + 4)^ + 999) div 1000, False);
    320: Result := MxUtimensat(a0, a1, a2, a3);
    99: Result := MxStatfs(0, a0, a1, False);           { statfs }
    100: Result := MxStatfs(a0, 0, a1, False);          { fstatfs }
    268: Result := MxStatfs(0, a0, a2, True);           { statfs64(path, size, buf) }
    269: Result := MxStatfs(a0, 0, a2, True);           { fstatfs64 }
    324: Result := MxFallocate(a0, a1, a2, a3, a4, a5);
    96: Result := MxPriority(True, a0, a1, 0);
    97: Result := MxPriority(False, a0, a1, a2);
    147: begin MxClear(m); m[2] := a0; Result := Lx(MxCall(MX_PM, PM_GETSID, m)); end;
    158: Result := 0;                                    { sched_yield: the scheduler is PM's }
    159, 160: Result := 0;                              { sched_get_priority_max/min: SCHED_OTHER }
    162: Result := MxNanosleep(a0, a1);
    267: if a1 <> 0 then Result := -LX_EINVAL           { clock_nanosleep: relative only }
         else Result := MxNanosleep(a2, a3);
    224: begin MxClear(m); Result := Lx(MxCall(MX_PM, PM_GETPID, m)); end;   { gettid: one thread }
    238: begin MxClear(m); Result := MxKill(MxCall(MX_PM, PM_GETPID, m), a1); end;   { tkill(tid, sig) }
    270: Result := MxKill(a0, a2);                                           { tgkill(tgid, tid, sig) }
    { sigaltstack: Minix runs every handler on the current stack. A request
      succeeds and changes nothing; the old stack reads as disabled. }
    186: begin if a1 <> 0 then begin PLongInt(a1)^ := 0; PLongInt(a1 + 4)^ := 2; PLongInt(a1 + 8)^ := 0; end;
           Result := 0; end;
    243: Result := -LX_ENOSYS;                        { set_thread_area: never emitted for minix }
  else
    Result := -LX_ENOSYS;
  end;
end;

end.
