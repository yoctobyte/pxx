unit platform_backend;
{ POSIX PAL backend selected by -Fulib/rtl/platform/posix. }

interface

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

function PalBackendSocket(domain, kind, proto: Integer): Integer;
function PalBackendSetSocketReuseAddr(handle, enabled: Integer): Integer;
function PalBackendSetSocketNonBlocking(handle, enabled: Integer): Integer;
function PalBackendBindIpv4(handle: Integer; hostAddr: LongWord; port: Integer): Integer;
function PalBackendConnectIpv4(handle: Integer; hostAddr: LongWord; port: Integer): Integer;
function PalBackendListen(handle, backlog: Integer): Integer;
function PalBackendAccept(handle: Integer): Integer;
function PalBackendRecv(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalBackendSend(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalBackendShutdown(handle, how: Integer): Integer;
function PalBackendSocketClose(handle: Integer): Integer;

function PalBackendMonotonicMillis: Int64;
procedure PalBackendYield;

function PalBackendVfork: Integer;
function PalBackendExecve(path: PChar; argv, envp: Pointer): Integer;
function PalBackendPipe2(var pipefd: array of Integer; flags: Integer): Integer;
function PalBackendDup2(oldFd, newFd: Integer): Integer;
function PalBackendWait4(pid: Integer; wstatus: Pointer; options: Integer; rusage: Pointer): Integer;
function PalBackendVforkAndExec(path: PChar; argv, envp: Pointer; stdinReadFd, stdinWriteFd, stdoutReadFd, stdoutWriteFd: Integer): Integer;

implementation

const
  PAL_PLATFORM_POSIX = 1;

{$ifdef CPUX86_64}
  SYS_read = 0; SYS_write = 1; SYS_close = 3; SYS_lseek = 8;
  SYS_fsync = 74; SYS_openat = 257; SYS_mkdirat = 258;
  SYS_unlinkat = 263; SYS_renameat = 264;
  SYS_socket=41; SYS_connect=42; SYS_accept4=288; SYS_bind=49; SYS_listen=50;
  SYS_setsockopt=54; SYS_shutdown=48; SYS_fcntl=72;
  SYS_vfork = 58; SYS_execve = 59; SYS_pipe2 = 293; SYS_dup2 = 33; SYS_wait4 = 61;
  SYS_clock_gettime = 228;
{$endif}
{$ifdef CPU_I386}
  SYS_read = 3; SYS_write = 4; SYS_close = 6; SYS_lseek = 19;
  SYS_fsync = 118; SYS_openat = 295; SYS_mkdirat = 296;
  SYS_unlinkat = 301; SYS_renameat = 302;
  SYS_socketcall=102; SYS_fcntl=55;
  SC_SOCKET=1; SC_BIND=2; SC_CONNECT=3; SC_LISTEN=4; SC_ACCEPT4=18;
  SC_SETSOCKOPT=14; SC_SHUTDOWN=13;
  SYS_vfork = 190; SYS_execve = 11; SYS_pipe2 = 331; SYS_dup2 = 63; SYS_wait4 = 114;
  SYS_clock_gettime = 265;
{$endif}
{$ifdef CPU_AARCH64}
  SYS_read = 63; SYS_write = 64; SYS_close = 57; SYS_lseek = 62;
  SYS_fsync = 82; SYS_openat = 56; SYS_mkdirat = 34;
  SYS_unlinkat = 35; SYS_renameat = 38;
  SYS_socket=198; SYS_connect=203; SYS_accept4=242; SYS_bind=200; SYS_listen=201;
  SYS_setsockopt=208; SYS_shutdown=210; SYS_fcntl=25;
  SYS_clone = 220; SYS_execve = 221; SYS_pipe2 = 59; SYS_dup3 = 24; SYS_wait4 = 260;
  SYS_clock_gettime = 113;
{$endif}
{$ifdef CPU_ARM32}
  SYS_read = 3; SYS_write = 4; SYS_close = 6; SYS_lseek = 19;
  SYS_fsync = 118; SYS_openat = 322; SYS_mkdirat = 323;
  SYS_unlinkat = 328; SYS_renameat = 329;
  SYS_socket=281; SYS_connect=283; SYS_accept4=366; SYS_bind=282; SYS_listen=284;
  SYS_setsockopt=294; SYS_shutdown=293; SYS_fcntl=55;
  SYS_vfork = 190; SYS_execve = 11; SYS_pipe2 = 359; SYS_dup2 = 63; SYS_wait4 = 114;
  SYS_clock_gettime = 263;
{$endif}
  PAL_AT_FDCWD = -100;
  PAL_AT_REMOVEDIR = $200;
  PAL_NET_AF_INET = 2;
  SOL_SOCKET = 1;
  SO_REUSEADDR = 2;
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
begin
  Result := __pxxrawsyscall(SYS_lseek, handle, offset, whence, 0, 0, 0);
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

type
  TTimeSpec = record
    Sec: NativeInt;
    Nsec: NativeInt;
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
{$ifdef CPU_AARCH64}
  Result := Integer(__pxxrawsyscall(SYS_clone, $4111, 0, 0, 0, 0, 0)); { CLONE_VM | CLONE_VFORK | SIGCHLD }
{$else}
  Result := Integer(__pxxrawsyscall(SYS_vfork, 0, 0, 0, 0, 0, 0));
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
{$ifdef CPU_AARCH64}
  Result := Integer(__pxxrawsyscall(SYS_dup3, oldFd, newFd, 0, 0, 0, 0));
{$else}
  Result := Integer(__pxxrawsyscall(SYS_dup2, oldFd, newFd, 0, 0, 0, 0));
{$endif}
end;

function PalBackendWait4(pid: Integer; wstatus: Pointer; options: Integer; rusage: Pointer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_wait4, pid, Int64(wstatus), options, Int64(rusage), 0, 0));
end;

function PalBackendVforkAndExec(path: PChar; argv, envp: Pointer; stdinReadFd, stdinWriteFd, stdoutReadFd, stdoutWriteFd: Integer): Integer;
var
  pid: Integer;
  res: Integer;
begin
{$ifdef CPU_AARCH64}
  pid := Integer(__pxxrawsyscall(SYS_clone, $4111, 0, 0, 0, 0, 0)); { CLONE_VM | CLONE_VFORK | SIGCHLD }
{$else}
  pid := Integer(__pxxrawsyscall(SYS_vfork, 0, 0, 0, 0, 0, 0));
{$endif}

  if pid = 0 then
  begin
    { Child process }
    if stdinReadFd <> -1 then
    begin
{$ifdef CPU_AARCH64}
      res := Integer(__pxxrawsyscall(SYS_dup3, stdinReadFd, 0, 0, 0, 0, 0));
{$else}
      res := Integer(__pxxrawsyscall(SYS_dup2, stdinReadFd, 0, 0, 0, 0, 0));
{$endif}
      res := Integer(__pxxrawsyscall(SYS_close, stdinReadFd, 0, 0, 0, 0, 0));
      res := Integer(__pxxrawsyscall(SYS_close, stdinWriteFd, 0, 0, 0, 0, 0));
    end;

    if stdoutWriteFd <> -1 then
    begin
{$ifdef CPU_AARCH64}
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
{$ifdef CPU_AARCH64}
    res := Integer(__pxxrawsyscall(93, 127, 0, 0, 0, 0, 0));
{$endif}
{$ifdef CPU_ARM32}
    res := Integer(__pxxrawsyscall(1, 127, 0, 0, 0, 0, 0));
{$endif}
  end;

  Result := pid;
end;

end.
