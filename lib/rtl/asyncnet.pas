{ SPDX-License-Identifier: Zlib }
unit asyncnet;
{ Async TCP sockets over PAL sockets plus the coroutine scheduler's reactor.
  Every call is non-blocking: on EAGAIN the coroutine parks on the reactor
  (WaitReadable/WaitWritable) and yields, so one OS thread serves many
  connections. Loopback IPv4 only; minimal on purpose.

  TcpListen(port)  -> a listening fd
  TcpAccept(lfd)   -> a connected fd (blocks the coroutine, not the thread)
  TcpConnect(port) -> a connected fd
  TcpRecv/TcpSend  -> byte counts (0 = peer closed); -1 on error
  TcpClose(fd) }

interface

uses scheduler, platform;

function TcpListen(port: Integer): Integer;
function TcpAccept(lfd: Integer): Integer;
function TcpConnect(port: Integer): Integer;
{ Async connect to an arbitrary IPv4 host (host byte order) + port. Same
  non-blocking-connect/park-on-writable pattern as TcpConnect (which is the
  loopback special case). }
function TcpConnectAddr(host: LongWord; port: Integer): Integer;
function TcpRecv(fd: Integer; buf: Pointer; len: Integer): Int64;
function TcpSend(fd: Integer; buf: Pointer; len: Integer): Int64;
procedure TcpClose(fd: Integer);

implementation

const
  TCP_BACKLOG = 16;

function TcpListen(port: Integer): Integer;
var fd: Integer; rc: Integer;
begin
  fd := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0);
  if fd < 0 then
  begin
    Result := fd;
    Exit;
  end;
  rc := PalSetSocketNonBlocking(fd, 1);
  rc := PalSetSocketReuseAddr(fd, 1);
  rc := PalBindIpv4(fd, PAL_NET_IP_LOOPBACK, port);
  if rc >= 0 then rc := PalListen(fd, TCP_BACKLOG);
  if rc < 0 then
  begin
    TcpClose(fd);
    Result := rc;
    Exit;
  end;
  Result := fd;
end;

function TcpAccept(lfd: Integer): Integer;
var cfd: Int64;
begin
  repeat
    cfd := PalAccept(lfd);
    if cfd = PAL_NET_EAGAIN then WaitReadable(lfd);
  until cfd <> PAL_NET_EAGAIN;
  if cfd >= 0 then
    PalSetSocketNonBlocking(Integer(cfd), 1);
  Result := Integer(cfd);
end;

function TcpConnect(port: Integer): Integer;
var fd: Integer; rc: Integer;
begin
  fd := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0);
  if fd < 0 then
  begin
    Result := fd;
    Exit;
  end;
  rc := PalSetSocketNonBlocking(fd, 1);
  rc := PalConnectIpv4(fd, PAL_NET_IP_LOOPBACK, port);
  if rc = PAL_NET_EINPROGRESS then
    WaitWritable(fd);   { connection completes asynchronously }
  Result := fd;
end;

function TcpConnectAddr(host: LongWord; port: Integer): Integer;
var fd: Integer; rc: Integer;
begin
  fd := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0);
  if fd < 0 then begin Result := fd; Exit; end;
  rc := PalSetSocketNonBlocking(fd, 1);
  rc := PalConnectIpv4(fd, host, port);
  if rc = PAL_NET_EINPROGRESS then
    WaitWritable(fd);
  Result := fd;
end;

function TcpRecv(fd: Integer; buf: Pointer; len: Integer): Int64;
var n: Int64;
begin
  repeat
    n := PalRecv(fd, buf, len);
    if n = PAL_NET_EAGAIN then WaitReadable(fd);
  until n <> PAL_NET_EAGAIN;
  Result := n;
end;

function TcpSend(fd: Integer; buf: Pointer; len: Integer): Int64;
var n, off: Int64;
begin
  off := 0;
  while off < len do
  begin
    n := PalSend(fd, Pointer(Int64(buf) + off), len - off);
    if n = PAL_NET_EAGAIN then
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
var rc: Integer;
begin
  rc := PalSocketClose(fd);
end;

end.
