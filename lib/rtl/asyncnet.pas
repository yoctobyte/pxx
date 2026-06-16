unit asyncnet;
{ Async TCP sockets over the coroutine scheduler's epoll reactor (PXX-only,
  x86-64). Every call is non-blocking: on EAGAIN the coroutine parks on the
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
  SYS_socket     = 41;
  SYS_connect    = 42;
  SYS_accept4    = 288;
  SYS_bind       = 49;
  SYS_listen     = 50;
  SYS_setsockopt = 54;
  SYS_close      = 3;
  SYS_read       = 0;
  SYS_write      = 1;

  AF_INET        = 2;
  SOCK_STREAM    = 1;
  SOCK_NONBLOCK  = $800;
  SOL_SOCKET     = 1;
  SO_REUSEADDR   = 2;
  EAGAIN         = -11;
  EINPROGRESS    = -115;

type
  PB = ^Byte;

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
  fd := Integer(__pxxrawsyscall(SYS_socket, AF_INET, SOCK_STREAM or SOCK_NONBLOCK, 0, 0, 0, 0));
  one := 1;
  rc := __pxxrawsyscall(SYS_setsockopt, fd, SOL_SOCKET, SO_REUSEADDR, Int64(@one), 4, 0);
  FillSockAddr(@sa[0], port);
  rc := __pxxrawsyscall(SYS_bind, fd, Int64(@sa[0]), 16, 0, 0, 0);
  rc := __pxxrawsyscall(SYS_listen, fd, 16, 0, 0, 0, 0);
  Result := fd;
end;

function TcpAccept(lfd: Integer): Integer;
var cfd: Int64;
begin
  repeat
    cfd := __pxxrawsyscall(SYS_accept4, lfd, 0, 0, SOCK_NONBLOCK, 0, 0);
    if cfd = EAGAIN then WaitReadable(lfd);
  until cfd <> EAGAIN;
  Result := Integer(cfd);
end;

function TcpConnect(port: Integer): Integer;
var fd: Integer; rc: Int64; sa: array[0..15] of Byte;
begin
  fd := Integer(__pxxrawsyscall(SYS_socket, AF_INET, SOCK_STREAM or SOCK_NONBLOCK, 0, 0, 0, 0));
  FillSockAddr(@sa[0], port);
  rc := __pxxrawsyscall(SYS_connect, fd, Int64(@sa[0]), 16, 0, 0, 0);
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
