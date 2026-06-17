unit asyncnet;
{ Async TCP sockets over the coroutine scheduler's epoll reactor (PXX-only,
  all four hosted targets). Every call is non-blocking: on EAGAIN the coroutine parks on the
  reactor (WaitReadable/WaitWritable) and yields, so one OS thread serves many
  connections. Loopback IPv4 only; minimal on purpose.

  TcpListen(port)  -> a listening fd
  TcpAccept(lfd)   -> a connected fd (blocks the coroutine, not the thread)
  TcpConnect(port) -> a connected fd
  TcpRecv/TcpSend  -> byte counts (0 = peer closed); -1 on error
  TcpClose(fd) }

interface

uses scheduler;

function TcpListen(port: Integer): Integer;
function TcpAccept(lfd: Integer): Integer;
function TcpConnect(port: Integer): Integer;
function TcpRecv(fd: Integer; buf: Pointer; len: Integer): Int64;
function TcpSend(fd: Integer; buf: Pointer; len: Integer): Int64;
procedure TcpClose(fd: Integer);

implementation

const
  AF_INET        = 2;
  SOCK_STREAM    = 1;
  SOCK_NONBLOCK  = $800;
  SOL_SOCKET     = 1;
  SO_REUSEADDR   = 2;
  EAGAIN         = -11;
  EINPROGRESS    = -115;

{ Per-arch Linux syscall numbers (verified against the FPC RTL sysnr tables).
  read/write/close are direct on every target. The socket family is direct on
  x86-64/aarch64/arm32; i386 has no direct socket syscalls and multiplexes them
  through socketcall(callnr, &args). }
{$ifdef CPUX86_64}
const
  SYS_socket=41; SYS_connect=42; SYS_accept4=288; SYS_bind=49; SYS_listen=50;
  SYS_setsockopt=54; SYS_close=3; SYS_read=0; SYS_write=1;
{$endif}
{$ifdef CPU_AARCH64}
const
  SYS_socket=198; SYS_connect=203; SYS_accept4=242; SYS_bind=200; SYS_listen=201;
  SYS_setsockopt=208; SYS_close=57; SYS_read=63; SYS_write=64;
{$endif}
{$ifdef CPU_ARM32}
const
  SYS_socket=281; SYS_connect=283; SYS_accept4=366; SYS_bind=282; SYS_listen=284;
  SYS_setsockopt=294; SYS_close=6; SYS_read=3; SYS_write=4;
{$endif}
{$ifdef CPU_I386}
const
  SYS_socketcall=102; SYS_close=6; SYS_read=3; SYS_write=4;
  SC_SOCKET=1; SC_BIND=2; SC_CONNECT=3; SC_LISTEN=4; SC_ACCEPT4=18; SC_SETSOCKOPT=14;
{$endif}

type
  PB = ^Byte;

{$ifdef CPU_I386}
{ i386 socketcall(callnr, &args): the original socket-call arguments are packed
  into a longword array; the kernel reads them by call number. }
function SockCall(callnr: Integer; a0, a1, a2, a3, a4: Int64): Int64;
var a: array[0..4] of NativeInt;
begin
  a[0] := a0; a[1] := a1; a[2] := a2; a[3] := a3; a[4] := a4;
  Result := __pxxrawsyscall(SYS_socketcall, callnr, Int64(@a[0]), 0, 0, 0, 0);
end;
{$endif}

{ Socket primitives: direct syscalls on x86-64/aarch64/arm32, socketcall on i386. }
function SockSocket(domain, typ, proto: Integer): Int64;
begin
{$ifdef CPU_I386}
  Result := SockCall(SC_SOCKET, domain, typ, proto, 0, 0);
{$else}
  Result := __pxxrawsyscall(SYS_socket, domain, typ, proto, 0, 0, 0);
{$endif}
end;

function SockSetReuse(fd: Integer; one: Pointer): Int64;
begin
{$ifdef CPU_I386}
  Result := SockCall(SC_SETSOCKOPT, fd, SOL_SOCKET, SO_REUSEADDR, Int64(one), 4);
{$else}
  Result := __pxxrawsyscall(SYS_setsockopt, fd, SOL_SOCKET, SO_REUSEADDR, Int64(one), 4, 0);
{$endif}
end;

function SockBind(fd: Integer; sa: Pointer): Int64;
begin
{$ifdef CPU_I386}
  Result := SockCall(SC_BIND, fd, Int64(sa), 16, 0, 0);
{$else}
  Result := __pxxrawsyscall(SYS_bind, fd, Int64(sa), 16, 0, 0, 0);
{$endif}
end;

function SockListen(fd, backlog: Integer): Int64;
begin
{$ifdef CPU_I386}
  Result := SockCall(SC_LISTEN, fd, backlog, 0, 0, 0);
{$else}
  Result := __pxxrawsyscall(SYS_listen, fd, backlog, 0, 0, 0, 0);
{$endif}
end;

function SockAccept4(fd, flags: Integer): Int64;
begin
{$ifdef CPU_I386}
  Result := SockCall(SC_ACCEPT4, fd, 0, 0, flags, 0);
{$else}
  Result := __pxxrawsyscall(SYS_accept4, fd, 0, 0, flags, 0, 0);
{$endif}
end;

function SockConnect(fd: Integer; sa: Pointer): Int64;
begin
{$ifdef CPU_I386}
  Result := SockCall(SC_CONNECT, fd, Int64(sa), 16, 0, 0);
{$else}
  Result := __pxxrawsyscall(SYS_connect, fd, Int64(sa), 16, 0, 0, 0);
{$endif}
end;

{ Fill a 16-byte sockaddr_in at sa: family AF_INET, the port in network order,
  address 127.0.0.1 (also network order). }
procedure FillSockAddr(sa: Pointer; port: Integer);
var i: Integer;
begin
  for i := 0 to 15 do PB(Pointer(Int64(sa) + i))^ := 0;
  PB(Pointer(Int64(sa) + 0))^ := AF_INET;            { sin_family low byte }
  PB(Pointer(Int64(sa) + 2))^ := (port shr 8) and $FF;  { sin_port hi (network order) }
  PB(Pointer(Int64(sa) + 3))^ := port and $FF;          { sin_port lo }
  PB(Pointer(Int64(sa) + 4))^ := 127;                { 127.0.0.1 }
  PB(Pointer(Int64(sa) + 5))^ := 0;
  PB(Pointer(Int64(sa) + 6))^ := 0;
  PB(Pointer(Int64(sa) + 7))^ := 1;
end;

function TcpListen(port: Integer): Integer;
var fd: Integer; rc: Int64; one: Integer; sa: array[0..15] of Byte;
begin
  fd := Integer(SockSocket(AF_INET, SOCK_STREAM or SOCK_NONBLOCK, 0));
  one := 1;
  rc := SockSetReuse(fd, @one);
  FillSockAddr(@sa[0], port);
  rc := SockBind(fd, @sa[0]);
  rc := SockListen(fd, 16);
  Result := fd;
end;

function TcpAccept(lfd: Integer): Integer;
var cfd: Int64;
begin
  repeat
    cfd := SockAccept4(lfd, SOCK_NONBLOCK);
    if cfd = EAGAIN then WaitReadable(lfd);
  until cfd <> EAGAIN;
  Result := Integer(cfd);
end;

function TcpConnect(port: Integer): Integer;
var fd: Integer; rc: Int64; sa: array[0..15] of Byte;
begin
  fd := Integer(SockSocket(AF_INET, SOCK_STREAM or SOCK_NONBLOCK, 0));
  FillSockAddr(@sa[0], port);
  rc := SockConnect(fd, @sa[0]);
  if rc = EINPROGRESS then
    WaitWritable(fd);   { connection completes asynchronously }
  Result := fd;
end;

function TcpRecv(fd: Integer; buf: Pointer; len: Integer): Int64;
var n: Int64;
begin
  repeat
    n := __pxxrawsyscall(SYS_read, fd, Int64(buf), len, 0, 0, 0);
    if n = EAGAIN then WaitReadable(fd);
  until n <> EAGAIN;
  Result := n;
end;

function TcpSend(fd: Integer; buf: Pointer; len: Integer): Int64;
var n, off: Int64;
begin
  off := 0;
  while off < len do
  begin
    n := __pxxrawsyscall(SYS_write, fd, Int64(buf) + off, len - off, 0, 0, 0);
    if n = EAGAIN then
      WaitWritable(fd)
    else if n < 0 then
    begin
      Result := n;   { error }
      Exit;
    end
    else
      off := off + n;
  end;
  Result := off;
end;

procedure TcpClose(fd: Integer);
var rc: Int64;
begin
  rc := __pxxrawsyscall(SYS_close, fd, 0, 0, 0, 0, 0);
end;

end.
