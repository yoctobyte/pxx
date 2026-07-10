{ SPDX-License-Identifier: Zlib }
unit platform_backend;
{ POSIX PAL backend selected by -Fulib/rtl/platform/posix. }

interface

uses platform_types;

function PalBackendPlatform: Integer;
function PalBackendHasFiles: Boolean;
function PalBackendHasSockets: Boolean;
function PalBackendHasThreads: Boolean;
function PalBackendHasDynlib: Boolean;

function PalBackendOpen(path: PChar; flags, mode: Integer): Integer;
function PalBackendRead(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalBackendWrite(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalBackendSeek(handle: Integer; offset: Int64; whence: Integer): Int64;
function PalBackendFlush(handle: Integer): Integer;
function PalBackendClose(handle: Integer): Integer;
function PalBackendDelete(path: PChar): Integer;
function PalBackendRename(oldPath, newPath: PChar): Integer;
function PalBackendMkdir(path: PChar; mode: Integer): Integer;
function PalBackendRmdir(path: PChar): Integer;
function PalBackendGetDents64(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalBackendStat(path: PChar; var info: TPalFileStat): Integer;
function PalBackendStatAt(dirHandle: Integer; path: PChar; var info: TPalFileStat): Integer;
function PalBackendFstat(handle: Integer; var info: TPalFileStat): Integer;
function PalBackendLstat(path: PChar; var info: TPalFileStat): Integer;
function PalBackendFcntl(handle, cmd: Integer; arg: Int64): Integer;
function PalBackendFsync(handle: Integer): Integer;
function PalBackendFchmod(handle, mode: Integer): Integer;
function PalBackendFtruncate(handle: Integer; length: Int64): Integer;
function PalBackendAccess(path: PChar; mode: Integer): Integer;
function PalBackendFchown(handle, owner, group: Integer): Integer;
function PalBackendGeteuid: Integer;
function PalBackendReadlink(path: PChar; buf: Pointer; bufsz: Integer): Integer;
function PalBackendGetpid: Integer;
function PalBackendGetcwd(buf: PChar; size: Integer): Integer;
function PalBackendNanosleep(sec, nsec: Int64): Integer;
function PalBackendRealtime(var sec, nsec: Int64): Integer;
function PalBackendUtimes(path: PChar; atimeSec, mtimeSec: Int64): Integer;
function PalBackendMmapAnon(len: Int64): Pointer;
function PalBackendMunmap(addr: Pointer; len: Int64): Integer;

function PalBackendSocket(domain, kind, proto: Integer): Integer;
function PalBackendSetSocketReuseAddr(handle, enabled: Integer): Integer;
function PalBackendSetSockOpt(handle, level, optname: Integer; valPtr: Pointer; valLen: Integer): Integer;
function PalBackendSetSocketNonBlocking(handle, enabled: Integer): Integer;
function PalBackendBindIpv4(handle: Integer; hostAddr: LongWord; port: Integer): Integer;
function PalBackendConnectIpv4(handle: Integer; hostAddr: LongWord; port: Integer): Integer;
function PalBackendListen(handle, backlog: Integer): Integer;
function PalBackendAccept(handle: Integer): Integer;
function PalBackendRecv(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalBackendSend(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalBackendShutdown(handle, how: Integer): Integer;
function PalBackendSocketClose(handle: Integer): Integer;
function PalBackendSendToIpv4(handle: Integer; buf: Pointer; len: Integer; hostAddr: LongWord; port: Integer): Int64;
function PalBackendRecvFromIpv4(handle: Integer; buf: Pointer; len: Integer; var outAddr: LongWord; var outPort: Integer): Int64;
function PalBackendPoll(handle, events, timeoutMs: Integer): Integer;
function PalBackendGetSockError(handle: Integer): Integer;
function PalBackendGetSockNameIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;
function PalBackendAcceptIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;

function PalBackendMonotonicMillis: Int64;
procedure PalBackendYield;

function PalBackendVfork: Integer;
function PalBackendExecve(path: PChar; argv, envp: Pointer): Integer;
function PalBackendPipe2(var pipefd: array of Integer; flags: Integer): Integer;
function PalBackendDup2(oldFd, newFd: Integer): Integer;
function PalBackendWait4(pid: Integer; wstatus: Pointer; options: Integer; rusage: Pointer): Integer;
function PalBackendKill(pid, sig: Integer): Integer;
function PalBackendVforkAndExec(path: PChar; argv, envp: Pointer; stdinReadFd, stdinWriteFd, stdoutReadFd, stdoutWriteFd: Integer): Integer;

implementation

{$ifdef CPU_AARCH64}{$define PAL_GENERIC_SYSCALLS}{$endif}
{$ifdef CPU_RISCV32}{$define PAL_GENERIC_SYSCALLS}{$endif}

const
  PAL_PLATFORM_POSIX = 1;

{$ifdef CPUX86_64}
  SYS_read = 0; SYS_write = 1; SYS_close = 3; SYS_lseek = 8;
  SYS_fsync = 74; SYS_openat = 257; SYS_mkdirat = 258; SYS_getdents64 = 217; SYS_statx = 332;
  SYS_unlinkat = 263; SYS_renameat = 264;
  SYS_socket=41; SYS_connect=42; SYS_accept4=288; SYS_bind=49; SYS_listen=50;
  SYS_setsockopt=54; SYS_shutdown=48; SYS_fcntl=72;
  SYS_getsockopt=55; SYS_getsockname=51;
  SYS_sendto=44; SYS_recvfrom=45; SYS_ppoll=271;
  SYS_vfork = 58; SYS_fork = 57; SYS_execve = 59; SYS_pipe2 = 293; SYS_dup2 = 33; SYS_wait4 = 61; SYS_kill = 62;
  SYS_clock_gettime = 228;
  SYS_mmap = 9; SYS_munmap = 11; SYS_fchmod = 91; SYS_getpid = 39; SYS_nanosleep = 35; SYS_utimensat = 280;
  SYS_getcwd = 79;
  SYS_ftruncate = 77; SYS_faccessat = 269; SYS_geteuid = 107; SYS_fchown = 93; SYS_readlinkat = 267;
{$endif}
{$ifdef CPU_I386}
  SYS_read = 3; SYS_write = 4; SYS_close = 6; SYS_lseek = 19;
  SYS_fsync = 118; SYS_openat = 295; SYS_mkdirat = 296; SYS_getdents64 = 220; SYS_statx = 383;
  SYS_unlinkat = 301; SYS_renameat = 302;
  SYS_socketcall=102; SYS_fcntl=55;
  SC_SOCKET=1; SC_BIND=2; SC_CONNECT=3; SC_LISTEN=4; SC_ACCEPT4=18;
  SC_SETSOCKOPT=14; SC_SHUTDOWN=13; SC_SENDTO=11; SC_RECVFROM=12;
  SC_GETSOCKNAME=6; SC_GETSOCKOPT=15;
  SYS_ppoll=309;
  SYS_vfork = 190; SYS_fork = 2; SYS_execve = 11; SYS_pipe2 = 331; SYS_dup2 = 63; SYS_wait4 = 114; SYS_kill = 37;
  SYS_clock_gettime = 265;
  SYS_mmap = 192; SYS_munmap = 91; SYS_fchmod = 94; SYS_getpid = 20; SYS_nanosleep = 162; SYS_utimensat = 320;
  SYS_getcwd = 183;
  SYS_ftruncate = 93; SYS_faccessat = 307; SYS_geteuid = 201; SYS_fchown = 207; SYS_readlinkat = 305;
{$endif}
{$ifdef CPU_AARCH64}
  SYS_read = 63; SYS_write = 64; SYS_close = 57; SYS_lseek = 62;
  SYS_fsync = 82; SYS_openat = 56; SYS_mkdirat = 34; SYS_getdents64 = 61; SYS_statx = 291;
  SYS_unlinkat = 35; SYS_renameat = 38;
  SYS_socket=198; SYS_connect=203; SYS_accept4=242; SYS_bind=200; SYS_listen=201;
  SYS_setsockopt=208; SYS_shutdown=210; SYS_fcntl=25;
  SYS_getsockopt=209; SYS_getsockname=204;
  SYS_sendto=206; SYS_recvfrom=207; SYS_ppoll=73;
  SYS_clone = 220; SYS_execve = 221; SYS_pipe2 = 59; SYS_dup3 = 24; SYS_wait4 = 260; SYS_kill = 129;
  SYS_clock_gettime = 113;
  SYS_mmap = 222; SYS_munmap = 215; SYS_fchmod = 52; SYS_getpid = 172; SYS_nanosleep = 101; SYS_utimensat = 88;
  SYS_getcwd = 17;
  SYS_ftruncate = 46; SYS_faccessat = 48; SYS_geteuid = 175; SYS_fchown = 55; SYS_readlinkat = 78;
{$endif}
{$ifdef CPU_ARM32}
  SYS_read = 3; SYS_write = 4; SYS_close = 6; SYS_lseek = 19;
  SYS_fsync = 118; SYS_openat = 322; SYS_mkdirat = 323; SYS_getdents64 = 217; SYS_statx = 397;
  SYS_unlinkat = 328; SYS_renameat = 329;
  SYS_socket=281; SYS_connect=283; SYS_accept4=366; SYS_bind=282; SYS_listen=284;
  SYS_setsockopt=294; SYS_shutdown=293; SYS_fcntl=55;
  SYS_getsockopt=295; SYS_getsockname=286;
  SYS_sendto=290; SYS_recvfrom=292; SYS_ppoll=336;
  SYS_vfork = 190; SYS_fork = 2; SYS_execve = 11; SYS_pipe2 = 359; SYS_dup2 = 63; SYS_wait4 = 114; SYS_kill = 37;
  SYS_clock_gettime = 263;
  SYS_mmap = 192; SYS_munmap = 91; SYS_fchmod = 94; SYS_getpid = 20; SYS_nanosleep = 162; SYS_utimensat = 348;
  SYS_getcwd = 183;
  SYS_ftruncate = 93; SYS_faccessat = 334; SYS_geteuid = 201; SYS_fchown = 207; SYS_readlinkat = 332;
{$endif}
{$ifdef CPU_RISCV32}
  { rv32 linux = asm-generic table (same slots as aarch64). 32-bit quirks:
    lseek is llseek(62) with a split 64-bit offset — PalSeek below only passes
    small offsets, and qemu-user tolerates the plain form for them; the
    time-related calls keep the legacy generic numbers qemu implements. }
  SYS_read = 63; SYS_write = 64; SYS_close = 57; SYS_lseek = 62;
  SYS_fsync = 82; SYS_openat = 56; SYS_mkdirat = 34; SYS_getdents64 = 61; SYS_statx = 291;
  SYS_unlinkat = 35; SYS_renameat = 38;
  SYS_socket=198; SYS_connect=203; SYS_accept4=242; SYS_bind=200; SYS_listen=201;
  SYS_setsockopt=208; SYS_shutdown=210; SYS_fcntl=25;
  SYS_getsockopt=209; SYS_getsockname=204;
  SYS_sendto=206; SYS_recvfrom=207; SYS_ppoll=73;
  SYS_clone = 220; SYS_execve = 221; SYS_pipe2 = 59; SYS_dup3 = 24; SYS_wait4 = 260; SYS_kill = 129;
  SYS_clock_gettime = 113;
  SYS_mmap = 222; SYS_munmap = 215; SYS_fchmod = 52; SYS_getpid = 172; SYS_nanosleep = 101; SYS_utimensat = 88;
  SYS_getcwd = 17;
  SYS_ftruncate = 46; SYS_faccessat = 48; SYS_geteuid = 175; SYS_fchown = 55; SYS_readlinkat = 78;
{$endif}
  PAL_AT_FDCWD = -100;
  PAL_AT_EMPTY_PATH = $1000;
  PAL_AT_SYMLINK_NOFOLLOW = $100;
  PAL_AT_REMOVEDIR = $200;
  PAL_STATX_BASIC_STATS = $000007FF;
  PAL_S_IFMT = $F000;
  PAL_S_IFDIR = $4000;
  PAL_S_IFREG = $8000;
  PAL_NET_AF_INET = 2;
  SOL_SOCKET = 1;
  SO_REUSEADDR = 2;
  SO_ERROR = 4;
  F_SETFL = 4;
  O_NONBLOCK = $800;

type
  PB = ^Byte;

{$ifdef CPU_I386}
function SockCall(callnr: Integer; a0, a1, a2, a3, a4: Int64): Int64;
var a: array[0..4] of NativeInt;
begin
  a[0] := a0; a[1] := a1; a[2] := a2; a[3] := a3; a[4] := a4;
  Result := __pxxrawsyscall(SYS_socketcall, callnr, Int64(@a[0]), 0, 0, 0, 0);
end;

function SockCall6(callnr: Integer; a0, a1, a2, a3, a4, a5: Int64): Int64;
var a: array[0..5] of NativeInt;
begin
  a[0] := a0; a[1] := a1; a[2] := a2; a[3] := a3; a[4] := a4; a[5] := a5;
  Result := __pxxrawsyscall(SYS_socketcall, callnr, Int64(@a[0]), 0, 0, 0, 0);
end;
{$endif}

procedure FillSockAddrIpv4(sa: Pointer; hostAddr: LongWord; port: Integer);
var i: Integer;
begin
  for i := 0 to 15 do PB(Pointer(Int64(sa) + i))^ := 0;
  PB(Pointer(Int64(sa) + 0))^ := PAL_NET_AF_INET;
  PB(Pointer(Int64(sa) + 2))^ := (port shr 8) and $FF;
  PB(Pointer(Int64(sa) + 3))^ := port and $FF;
  PB(Pointer(Int64(sa) + 4))^ := (hostAddr shr 24) and $FF;
  PB(Pointer(Int64(sa) + 5))^ := (hostAddr shr 16) and $FF;
  PB(Pointer(Int64(sa) + 6))^ := (hostAddr shr 8) and $FF;
  PB(Pointer(Int64(sa) + 7))^ := hostAddr and $FF;
end;

procedure ParseSockAddrIpv4(sa: Pointer; var hostAddr: LongWord; var port: Integer);
begin
  port := (Integer(PB(Pointer(Int64(sa) + 2))^) shl 8) or Integer(PB(Pointer(Int64(sa) + 3))^);
  hostAddr := (LongWord(PB(Pointer(Int64(sa) + 4))^) shl 24)
           or (LongWord(PB(Pointer(Int64(sa) + 5))^) shl 16)
           or (LongWord(PB(Pointer(Int64(sa) + 6))^) shl 8)
           or  LongWord(PB(Pointer(Int64(sa) + 7))^);
end;

function PalBackendPlatform: Integer;
begin
  Result := PAL_PLATFORM_POSIX;
end;

function PalBackendHasFiles: Boolean;
begin
  Result := True;
end;

function PalBackendHasSockets: Boolean;
begin
  Result := True;
end;

function PalBackendHasThreads: Boolean;
begin
  Result := True;
end;

function PalBackendHasDynlib: Boolean;
begin
  Result := True;
end;

function PalBackendOpen(path: PChar; flags, mode: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_openat, PAL_AT_FDCWD, Int64(path), flags, mode, 0, 0));
end;

function PalBackendRead(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := __pxxrawsyscall(SYS_read, handle, Int64(buf), len, 0, 0, 0);
end;

function PalBackendWrite(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := __pxxrawsyscall(SYS_write, handle, Int64(buf), len, 0, 0, 0);
end;

function PalBackendSeek(handle: Integer; offset: Int64; whence: Integer): Int64;
{$ifdef CPU_RISCV32}
var res: Int64; r: Int64;
{$endif}
begin
{$ifdef CPU_RISCV32}
  { rv32 syscall 62 is _llseek(fd, off_hi, off_lo, loff_t *result, whence), NOT
    plain lseek — the 3-arg form left the result pointer NULL and the kernel
    faulted (EFAULT). Split the 64-bit offset and pass the address of a local to
    receive the new position. }
  res := 0;
  r := __pxxrawsyscall(SYS_lseek, handle, (offset shr 32) and $FFFFFFFF,
                       offset and $FFFFFFFF, Int64(@res), whence);
  if r < 0 then Result := r else Result := res;
{$else}
  Result := __pxxrawsyscall(SYS_lseek, handle, offset, whence, 0, 0, 0);
{$endif}
end;

function PalBackendFlush(handle: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_fsync, handle, 0, 0, 0, 0, 0));
end;

function PalBackendClose(handle: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_close, handle, 0, 0, 0, 0, 0));
end;

function PalBackendDelete(path: PChar): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_unlinkat, PAL_AT_FDCWD, Int64(path), 0, 0, 0, 0));
end;

function PalBackendRename(oldPath, newPath: PChar): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_renameat, PAL_AT_FDCWD, Int64(oldPath),
    PAL_AT_FDCWD, Int64(newPath), 0));
end;

function PalBackendMkdir(path: PChar; mode: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_mkdirat, PAL_AT_FDCWD, Int64(path), mode, 0, 0, 0));
end;

function PalBackendRmdir(path: PChar): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_unlinkat, PAL_AT_FDCWD, Int64(path),
    PAL_AT_REMOVEDIR, 0, 0, 0));
end;

function PalBackendFtruncate(handle: Integer; length: Int64): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_ftruncate, handle, length, 0, 0, 0, 0));
end;

function PalBackendAccess(path: PChar; mode: Integer): Integer;
begin
  { access(path,mode) = faccessat(AT_FDCWD, path, mode, 0) — the plain access
    syscall is absent on the asm-generic table (aarch64/rv32). }
  Result := Integer(__pxxrawsyscall(SYS_faccessat, PAL_AT_FDCWD, Int64(path), mode, 0, 0, 0));
end;

function PalBackendFchown(handle, owner, group: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_fchown, handle, owner, group, 0, 0, 0));
end;

function PalBackendGeteuid: Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_geteuid, 0, 0, 0, 0, 0, 0));
end;

function PalBackendReadlink(path: PChar; buf: Pointer; bufsz: Integer): Integer;
begin
  { readlink(path,buf,n) = readlinkat(AT_FDCWD, path, buf, n). }
  Result := Integer(__pxxrawsyscall(SYS_readlinkat, PAL_AT_FDCWD, Int64(path),
    Int64(buf), bufsz, 0, 0));
end;

function PalBackendGetDents64(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := __pxxrawsyscall(SYS_getdents64, handle, Int64(buf), len, 0, 0, 0);
end;

function StatxByte(buf: Pointer; off: Integer): Byte;
begin
  Result := PB(Pointer(Int64(buf) + off))^;
end;

function StatxWordLE(buf: Pointer; off: Integer): Integer;
begin
  Result := Integer(StatxByte(buf, off)) + Integer(StatxByte(buf, off + 1)) * 256;
end;

function StatxDwordLE(buf: Pointer; off: Integer): Int64;
begin
  Result := Int64(StatxByte(buf, off)) + Int64(StatxByte(buf, off + 1)) * 256 +
            Int64(StatxByte(buf, off + 2)) * 65536 + Int64(StatxByte(buf, off + 3)) * 16777216;
end;

function StatxInt64LE(buf: Pointer; off: Integer): Int64;
var
  i: Integer;
  mul: Int64;
begin
  Result := 0;
  mul := 1;
  for i := 0 to 7 do
  begin
    Result := Result + Int64(StatxByte(buf, off + i)) * mul;
    mul := mul * 256;
  end;
end;

procedure ClearPalFileStat(var info: TPalFileStat);
begin
  info.Size := -1;
  info.MTimeSec := 0;
  info.Mode := 0;
  info.IsDir := False;
  info.IsFile := False;
  info.Ino := 0;
  info.Dev := 0;
  info.Blocks := 0;
  info.BlkSize := 4096;
end;

{ statx(2) — arch-neutral stat with a uniform struct layout on every target, so
  one field-offset map works for x86-64/i386/aarch64/arm32/riscv32 alike. }
function DoStatx(dirHandle: Integer; path: PChar; flags: Integer; var info: TPalFileStat): Integer;
var
  sx: array[0..255] of Byte;
  mode, major, minor: Integer;
begin
  ClearPalFileStat(info);
  Result := Integer(__pxxrawsyscall(SYS_statx, dirHandle, Int64(path), flags,
    PAL_STATX_BASIC_STATS, Int64(@sx[0]), 0));
  if Result < 0 then Exit;

  mode := StatxWordLE(@sx[0], $1C);
  info.Mode := mode;
  info.BlkSize := Integer(StatxDwordLE(@sx[0], $04));
  info.Ino := StatxInt64LE(@sx[0], $20);
  info.Size := StatxInt64LE(@sx[0], $28);
  info.Blocks := StatxInt64LE(@sx[0], $30);
  info.MTimeSec := StatxInt64LE(@sx[0], $70);
  major := Integer(StatxDwordLE(@sx[0], $88));
  minor := Integer(StatxDwordLE(@sx[0], $8C));
  info.Dev := (Int64(major) shl 20) or Int64(minor and $FFFFF);  { stable (dev,ino) key for sqlite locks }
  info.IsDir := (mode and PAL_S_IFMT) = PAL_S_IFDIR;
  info.IsFile := (mode and PAL_S_IFMT) = PAL_S_IFREG;
end;

function PalBackendStatAt(dirHandle: Integer; path: PChar; var info: TPalFileStat): Integer;
begin
  Result := DoStatx(dirHandle, path, 0, info);
end;

function PalBackendStat(path: PChar; var info: TPalFileStat): Integer;
begin
  Result := DoStatx(PAL_AT_FDCWD, path, 0, info);
end;

function PalBackendLstat(path: PChar; var info: TPalFileStat): Integer;
begin
  Result := DoStatx(PAL_AT_FDCWD, path, PAL_AT_SYMLINK_NOFOLLOW, info);
end;

function PalBackendFstat(handle: Integer; var info: TPalFileStat): Integer;
var empty: array[0..0] of Byte;
begin
  empty[0] := 0;   { statx(fd, "", AT_EMPTY_PATH) = fstat }
  Result := DoStatx(handle, PChar(@empty[0]), PAL_AT_EMPTY_PATH, info);
end;

function PalBackendFcntl(handle, cmd: Integer; arg: Int64): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_fcntl, handle, cmd, arg, 0, 0, 0));
end;

function PalBackendFsync(handle: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_fsync, handle, 0, 0, 0, 0, 0));
end;

function PalBackendFchmod(handle, mode: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_fchmod, handle, mode, 0, 0, 0, 0));
end;

function PalBackendGetpid: Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_getpid, 0, 0, 0, 0, 0, 0));
end;

{ Returns the path length INCLUDING the trailing NUL, or -errno. }
function PalBackendGetcwd(buf: PChar; size: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_getcwd, Int64(buf), size, 0, 0, 0, 0));
end;

function PalBackendNanosleep(sec, nsec: Int64): Integer;
var ts: array[0..1] of NativeInt;   { struct timespec {tv_sec; tv_nsec}, native-word fields per arch }
begin
  ts[0] := NativeInt(sec); ts[1] := NativeInt(nsec);
  Result := Integer(__pxxrawsyscall(SYS_nanosleep, Int64(@ts[0]), 0, 0, 0, 0, 0));
end;

function PalBackendRealtime(var sec, nsec: Int64): Integer;
var ts: array[0..1] of NativeInt;
begin
  ts[0] := 0; ts[1] := 0;
  Result := Integer(__pxxrawsyscall(SYS_clock_gettime, 0, Int64(@ts[0]), 0, 0, 0, 0)); { 0 = CLOCK_REALTIME }
  sec := ts[0]; nsec := ts[1];
end;

function PalBackendUtimes(path: PChar; atimeSec, mtimeSec: Int64): Integer;
var ts: array[0..3] of NativeInt;  { struct timespec[2] {atime, mtime} }
begin
  ts[0] := NativeInt(atimeSec); ts[1] := 0;
  ts[2] := NativeInt(mtimeSec); ts[3] := 0;
  Result := Integer(__pxxrawsyscall(SYS_utimensat, PAL_AT_FDCWD, Int64(path), Int64(@ts[0]), 0, 0, 0));
end;

function PalBackendMmapAnon(len: Int64): Pointer;
begin
  { mmap(NULL, len, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0); 32-bit = mmap2, page-offset 0 }
  Result := Pointer(__pxxrawsyscall(SYS_mmap, 0, len, 3, 34, -1, 0));
end;

function PalBackendMunmap(addr: Pointer; len: Int64): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_munmap, Int64(addr), len, 0, 0, 0, 0));
end;

function PalBackendSocket(domain, kind, proto: Integer): Integer;
begin
{$ifdef CPU_I386}
  Result := Integer(SockCall(SC_SOCKET, domain, kind, proto, 0, 0));
{$else}
  Result := Integer(__pxxrawsyscall(SYS_socket, domain, kind, proto, 0, 0, 0));
{$endif}
end;

function PalBackendSetSocketReuseAddr(handle, enabled: Integer): Integer;
var one: Integer;
begin
  one := enabled;
{$ifdef CPU_I386}
  Result := Integer(SockCall(SC_SETSOCKOPT, handle, SOL_SOCKET, SO_REUSEADDR, Int64(@one), 4));
{$else}
  Result := Integer(__pxxrawsyscall(SYS_setsockopt, handle, SOL_SOCKET, SO_REUSEADDR,
    Int64(@one), 4, 0));
{$endif}
end;

function PalBackendSetSockOpt(handle, level, optname: Integer; valPtr: Pointer; valLen: Integer): Integer;
begin
{$ifdef CPU_I386}
  Result := Integer(SockCall(SC_SETSOCKOPT, handle, level, optname, Int64(valPtr), valLen));
{$else}
  Result := Integer(__pxxrawsyscall(SYS_setsockopt, handle, level, optname,
    Int64(valPtr), valLen, 0));
{$endif}
end;

function PalBackendSetSocketNonBlocking(handle, enabled: Integer): Integer;
var flags: Integer;
begin
  if enabled <> 0 then flags := O_NONBLOCK else flags := 0;
  Result := Integer(__pxxrawsyscall(SYS_fcntl, handle, F_SETFL, flags, 0, 0, 0));
end;

function PalBackendBindIpv4(handle: Integer; hostAddr: LongWord; port: Integer): Integer;
var sa: array[0..15] of Byte;
begin
  FillSockAddrIpv4(@sa[0], hostAddr, port);
{$ifdef CPU_I386}
  Result := Integer(SockCall(SC_BIND, handle, Int64(@sa[0]), 16, 0, 0));
{$else}
  Result := Integer(__pxxrawsyscall(SYS_bind, handle, Int64(@sa[0]), 16, 0, 0, 0));
{$endif}
end;

function PalBackendConnectIpv4(handle: Integer; hostAddr: LongWord; port: Integer): Integer;
var sa: array[0..15] of Byte;
begin
  FillSockAddrIpv4(@sa[0], hostAddr, port);
{$ifdef CPU_I386}
  Result := Integer(SockCall(SC_CONNECT, handle, Int64(@sa[0]), 16, 0, 0));
{$else}
  Result := Integer(__pxxrawsyscall(SYS_connect, handle, Int64(@sa[0]), 16, 0, 0, 0));
{$endif}
end;

function PalBackendListen(handle, backlog: Integer): Integer;
begin
{$ifdef CPU_I386}
  Result := Integer(SockCall(SC_LISTEN, handle, backlog, 0, 0, 0));
{$else}
  Result := Integer(__pxxrawsyscall(SYS_listen, handle, backlog, 0, 0, 0, 0));
{$endif}
end;

function PalBackendAccept(handle: Integer): Integer;
begin
{$ifdef CPU_I386}
  Result := Integer(SockCall(SC_ACCEPT4, handle, 0, 0, 0, 0));
{$else}
  Result := Integer(__pxxrawsyscall(SYS_accept4, handle, 0, 0, 0, 0, 0));
{$endif}
end;

function PalBackendRecv(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := __pxxrawsyscall(SYS_read, handle, Int64(buf), len, 0, 0, 0);
end;

function PalBackendSend(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := __pxxrawsyscall(SYS_write, handle, Int64(buf), len, 0, 0, 0);
end;

function PalBackendShutdown(handle, how: Integer): Integer;
begin
{$ifdef CPU_I386}
  Result := Integer(SockCall(SC_SHUTDOWN, handle, how, 0, 0, 0));
{$else}
  Result := Integer(__pxxrawsyscall(SYS_shutdown, handle, how, 0, 0, 0, 0));
{$endif}
end;

function PalBackendSocketClose(handle: Integer): Integer;
begin
  Result := PalBackendClose(handle);
end;

function PalBackendSendToIpv4(handle: Integer; buf: Pointer; len: Integer; hostAddr: LongWord; port: Integer): Int64;
var sa: array[0..15] of Byte;
begin
  FillSockAddrIpv4(@sa[0], hostAddr, port);
{$ifdef CPU_I386}
  Result := SockCall6(SC_SENDTO, handle, Int64(buf), len, 0, Int64(@sa[0]), 16);
{$else}
  Result := __pxxrawsyscall(SYS_sendto, handle, Int64(buf), len, 0, Int64(@sa[0]), 16);
{$endif}
end;

function PalBackendRecvFromIpv4(handle: Integer; buf: Pointer; len: Integer; var outAddr: LongWord; var outPort: Integer): Int64;
var
  sa: array[0..15] of Byte;
  addrlen: Integer;
  i: Integer;
begin
  for i := 0 to 15 do sa[i] := 0;
  addrlen := 16;
{$ifdef CPU_I386}
  Result := SockCall6(SC_RECVFROM, handle, Int64(buf), len, 0, Int64(@sa[0]), Int64(@addrlen));
{$else}
  Result := __pxxrawsyscall(SYS_recvfrom, handle, Int64(buf), len, 0, Int64(@sa[0]), Int64(@addrlen));
{$endif}
  outAddr := 0;
  outPort := 0;
  if Result >= 0 then
    ParseSockAddrIpv4(@sa[0], outAddr, outPort);
end;

type
  TTimeSpec = record
    Sec: NativeInt;
    Nsec: NativeInt;
  end;

{ Readiness poll via ppoll (available on every PAL arch; aarch64 lacks legacy
  poll). pollfd is int fd then short events then short revents; we pack the
  second word as events or revents-shifted-16 on little-endian targets. Returns
  the revents bitmask when positive, 0 on timeout, or -errno. }
function PalBackendPoll(handle, events, timeoutMs: Integer): Integer;
var
  pfd: array[0..1] of Integer;
  ts: TTimeSpec;
  tsp: Pointer;
  res: Int64;
begin
  pfd[0] := handle;
  pfd[1] := events and $FFFF;
  if timeoutMs < 0 then
    tsp := nil
  else
  begin
    ts.Sec := timeoutMs div 1000;
    ts.Nsec := (timeoutMs mod 1000) * 1000000;
    tsp := @ts;
  end;
  res := __pxxrawsyscall(SYS_ppoll, Int64(@pfd[0]), 1, Int64(tsp), 0, 0, 0);
  if res < 0 then
    Result := Integer(res)
  else if res = 0 then
    Result := 0
  else
    Result := (pfd[1] shr 16) and $FFFF;
end;

{ Pending socket error via getsockopt(SO_ERROR): the canonical way to read the
  result of a non-blocking connect after poll reports writable. SO_ERROR is a
  positive errno that is cleared on read; we report 0 (clean) or -errno. If the
  getsockopt call itself fails, its own -errno is returned. }
function PalBackendGetSockError(handle: Integer): Integer;
var
  err, optlen: Integer;
  rc: Int64;
begin
  err := 0;
  optlen := 4;
{$ifdef CPU_I386}
  rc := SockCall(SC_GETSOCKOPT, handle, SOL_SOCKET, SO_ERROR, Int64(@err), Int64(@optlen));
{$else}
  rc := __pxxrawsyscall(SYS_getsockopt, handle, SOL_SOCKET, SO_ERROR, Int64(@err), Int64(@optlen), 0);
{$endif}
  if rc < 0 then
    Result := Integer(rc)
  else
    Result := -err;
end;

function PalBackendGetSockNameIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;
var
  sa: array[0..15] of Byte;
  addrlen: Integer;
  i: Integer;
  rc: Int64;
begin
  for i := 0 to 15 do sa[i] := 0;
  addrlen := 16;
{$ifdef CPU_I386}
  rc := SockCall(SC_GETSOCKNAME, handle, Int64(@sa[0]), Int64(@addrlen), 0, 0);
{$else}
  rc := __pxxrawsyscall(SYS_getsockname, handle, Int64(@sa[0]), Int64(@addrlen), 0, 0, 0);
{$endif}
  outAddr := 0;
  outPort := 0;
  if rc >= 0 then
    ParseSockAddrIpv4(@sa[0], outAddr, outPort);
  Result := Integer(rc);
end;

function PalBackendAcceptIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;
var
  sa: array[0..15] of Byte;
  addrlen: Integer;
  i: Integer;
  rc: Int64;
begin
  for i := 0 to 15 do sa[i] := 0;
  addrlen := 16;
{$ifdef CPU_I386}
  rc := SockCall(SC_ACCEPT4, handle, Int64(@sa[0]), Int64(@addrlen), 0, 0);
{$else}
  rc := __pxxrawsyscall(SYS_accept4, handle, Int64(@sa[0]), Int64(@addrlen), 0, 0, 0);
{$endif}
  outAddr := 0;
  outPort := 0;
  if rc >= 0 then
    ParseSockAddrIpv4(@sa[0], outAddr, outPort);
  Result := Integer(rc);
end;

function PalBackendMonotonicMillis: Int64;
var
  ts: TTimeSpec;
  res: Int64;
begin
  res := __pxxrawsyscall(SYS_clock_gettime, 1, Int64(@ts), 0, 0, 0, 0); { CLOCK_MONOTONIC = 1 }
  if res = 0 then
    Result := (Int64(ts.Sec) * 1000) + (Int64(ts.Nsec) div 1000000)
  else
    Result := 0;
end;

procedure PalBackendYield;
begin
end;

function PalBackendVfork: Integer;
begin
{$ifdef PAL_GENERIC_SYSCALLS}
  Result := Integer(__pxxrawsyscall(SYS_clone, $11, 0, 0, 0, 0, 0)); { SIGCHLD only -> fork (own COW address space) }
{$else}
  Result := Integer(__pxxrawsyscall(SYS_fork, 0, 0, 0, 0, 0, 0));
{$endif}
end;

function PalBackendExecve(path: PChar; argv, envp: Pointer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_execve, Int64(path), Int64(argv), Int64(envp), 0, 0, 0));
end;

function PalBackendPipe2(var pipefd: array of Integer; flags: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_pipe2, Int64(@pipefd[0]), flags, 0, 0, 0, 0));
end;

function PalBackendDup2(oldFd, newFd: Integer): Integer;
begin
{$ifdef PAL_GENERIC_SYSCALLS}
  Result := Integer(__pxxrawsyscall(SYS_dup3, oldFd, newFd, 0, 0, 0, 0));
{$else}
  Result := Integer(__pxxrawsyscall(SYS_dup2, oldFd, newFd, 0, 0, 0, 0));
{$endif}
end;

function PalBackendWait4(pid: Integer; wstatus: Pointer; options: Integer; rusage: Pointer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_wait4, pid, Int64(wstatus), options, Int64(rusage), 0, 0));
end;

function PalBackendKill(pid, sig: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_kill, pid, sig, 0, 0, 0, 0));
end;

function PalBackendVforkAndExec(path: PChar; argv, envp: Pointer; stdinReadFd, stdinWriteFd, stdoutReadFd, stdoutWriteFd: Integer): Integer;
var
  pid: Integer;
  res: Integer;
begin
{ Real fork (not vfork): the child gets its own copy-on-write address space, so
  it can safely run this Pascal child path (dup2/close/execve) without clobbering
  the parent's stack -- the shared-VM vfork hazard the ticket warned about. }
{$ifdef PAL_GENERIC_SYSCALLS}
  pid := Integer(__pxxrawsyscall(SYS_clone, $11, 0, 0, 0, 0, 0)); { SIGCHLD only -> fork }
{$else}
  pid := Integer(__pxxrawsyscall(SYS_fork, 0, 0, 0, 0, 0, 0));
{$endif}

  if pid = 0 then
  begin
    { Child process }
    if stdinReadFd <> -1 then
    begin
{$ifdef PAL_GENERIC_SYSCALLS}
      res := Integer(__pxxrawsyscall(SYS_dup3, stdinReadFd, 0, 0, 0, 0, 0));
{$else}
      res := Integer(__pxxrawsyscall(SYS_dup2, stdinReadFd, 0, 0, 0, 0, 0));
{$endif}
      res := Integer(__pxxrawsyscall(SYS_close, stdinReadFd, 0, 0, 0, 0, 0));
      res := Integer(__pxxrawsyscall(SYS_close, stdinWriteFd, 0, 0, 0, 0, 0));
    end;

    if stdoutWriteFd <> -1 then
    begin
{$ifdef PAL_GENERIC_SYSCALLS}
      res := Integer(__pxxrawsyscall(SYS_dup3, stdoutWriteFd, 1, 0, 0, 0, 0));
{$else}
      res := Integer(__pxxrawsyscall(SYS_dup2, stdoutWriteFd, 1, 0, 0, 0, 0));
{$endif}
      res := Integer(__pxxrawsyscall(SYS_close, stdoutReadFd, 0, 0, 0, 0, 0));
      res := Integer(__pxxrawsyscall(SYS_close, stdoutWriteFd, 0, 0, 0, 0, 0));
    end;

    res := Integer(__pxxrawsyscall(SYS_execve, Int64(path), Int64(argv), Int64(envp), 0, 0, 0));

    { If execve fails, exit }
{$ifdef CPUX86_64}
    res := Integer(__pxxrawsyscall(60, 127, 0, 0, 0, 0, 0));
{$endif}
{$ifdef CPU_I386}
    res := Integer(__pxxrawsyscall(1, 127, 0, 0, 0, 0, 0));
{$endif}
{$ifdef PAL_GENERIC_SYSCALLS}
    res := Integer(__pxxrawsyscall(93, 127, 0, 0, 0, 0, 0));
{$endif}
{$ifdef CPU_ARM32}
    res := Integer(__pxxrawsyscall(1, 127, 0, 0, 0, 0, 0));
{$endif}
  end;

  Result := pid;
end;

end.
