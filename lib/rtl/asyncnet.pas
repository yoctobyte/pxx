{ SPDX-License-Identifier: Zlib }
unit asyncnet;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Async TCP sockets over PAL sockets plus the coroutine scheduler's reactor.
  Every call is non-blocking: on EAGAIN the coroutine parks on the reactor
  (WaitReadable/WaitWritable) and yields, so one OS thread serves many
  connections. Minimal on purpose: listen and connect-by-port are LOOPBACK,
  IPv4 and IPv6 both.

  TcpListen(port)   -> a listening fd            TcpListen6(port)
  TcpLocalPort(fd)  -> the port it actually bound (the point of listening on 0)
  TcpAccept(lfd)    -> a connected fd (blocks the coroutine, not the thread)
  TcpConnect(port)  -> a connected fd            TcpConnect6(port)
  TcpConnectAddr(host, port)                     TcpConnectAddr6(addr, port, scopeId)
  TcpRecv/TcpSend   -> byte counts (0 = peer closed); -1 on error
  TcpClose(fd)
  TcpListenAddr(host, port) -> listen on a given IPv4 address (host byte
                       order; PAL_NET_IP_ANY = every interface), e.g. a
                       soft-AP's 192.168.4.1 or all of them
  UdpBind(host, port)       -> a non-blocking UDP fd bound there
  UdpRecvFrom(fd, buf, len, var host, var port) / UdpSendTo(fd, buf, len,
                       host, port) -> one datagram; park on EAGAIN like Tcp*

  TcpAccept, TcpRecv, TcpSend and TcpClose are family-agnostic — they take an
  fd, and the family was decided when it was created. Only the four that build
  a socket come in pairs. }

interface

uses scheduler, platform, platform_types;

function TcpListen(port: Integer): Integer;
{ TcpListen on an explicit IPv4 address (host byte order). TcpListen(port) is
  TcpListenAddr(PAL_NET_IP_LOOPBACK, port). A device serving clients, such as
  a captive portal on a soft-AP, listens on PAL_NET_IP_ANY or its own address. }
function TcpListenAddr(host: LongWord; port: Integer): Integer;
{ UDP, IPv4, on the same reactor. UdpBind answers a non-blocking fd bound to
  host:port (PAL_NET_IP_ANY for every interface, port 0 for any), or <0.
  UdpRecvFrom parks until a datagram arrives and answers its length (a
  datagram longer than len is truncated, as recvfrom does) with the sender's
  address; UdpSendTo sends one datagram, parking while the socket is full.
  Both answer <0 on an error. }
function UdpBind(host: LongWord; port: Integer): Integer;
function UdpRecvFrom(fd: Integer; buf: Pointer; len: Integer;
                     var host: LongWord; var port: Integer): Int64;
function UdpSendTo(fd: Integer; buf: Pointer; len: Integer;
                   host: LongWord; port: Integer): Int64;
{ The port `fd` is actually bound to, or <0 if it cannot be read. Exists so a
  caller can listen on port 0 and then tell its client where to dial: a
  HARDCODED port is a shared global, and two copies of the same test on one box
  fight over it — which is exactly what Track T's watcher host does by design
  (bug-b-lib-tls-hangs-forever-when-its-hardcoded-port-is-unavailable). Port 0
  makes that collision unrepresentable rather than merely rare, but only if the
  chosen port can be read back, so the two belong together. }
function TcpLocalPort(fd: Integer): Integer;
function TcpAccept(lfd: Integer): Integer;
function TcpConnect(port: Integer): Integer;
{ Async connect to an arbitrary IPv4 host (host byte order) + port. Same
  non-blocking-connect/park-on-writable pattern as TcpConnect (which is the
  loopback special case). }
function TcpConnectAddr(host: LongWord; port: Integer): Integer;
{ The IPv6 halves. Same reactor, same parking; only the address family and the
  bind/connect primitive differ. }
function TcpListen6(port: Integer): Integer;
function TcpConnect6(port: Integer): Integer;
function TcpConnectAddr6(const addr: TPalIn6Addr; port, scopeId: Integer): Integer;
function TcpRecv(fd: Integer; buf: Pointer; len: Integer): Int64;
function TcpSend(fd: Integer; buf: Pointer; len: Integer): Int64;
procedure TcpClose(fd: Integer);

implementation

const
  TCP_BACKLOG = 16;

function TcpListen(port: Integer): Integer;
begin
  Result := TcpListenAddr(PAL_NET_IP_LOOPBACK, port);
end;

function TcpListenAddr(host: LongWord; port: Integer): Integer;
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
  rc := PalBindIpv4(fd, host, port);
  if rc >= 0 then rc := PalListen(fd, TCP_BACKLOG);
  if rc < 0 then
  begin
    TcpClose(fd);
    Result := rc;
    Exit;
  end;
  Result := fd;
end;

function TcpLocalPort(fd: Integer): Integer;
var host: LongWord; port, rc: Integer;
begin
  host := 0;
  port := 0;
  rc := PalGetSockNameIpv4(fd, host, port);
  if rc < 0 then Result := rc else Result := port;
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

function TcpListen6(port: Integer): Integer;
var fd: Integer; rc: Integer;
begin
  fd := PalSocket(PAL_NET_AF_INET6, PAL_NET_SOCK_STREAM, 0);
  if fd < 0 then
  begin
    Result := fd;
    Exit;
  end;
  rc := PalSetSocketNonBlocking(fd, 1);
  rc := PalSetSocketReuseAddr(fd, 1);
  rc := PalBindIpv6(fd, PalIn6Loopback, port, 0);
  if rc >= 0 then rc := PalListen(fd, TCP_BACKLOG);
  if rc < 0 then
  begin
    TcpClose(fd);
    Result := rc;
    Exit;
  end;
  Result := fd;
end;

function TcpConnect6(port: Integer): Integer;
begin
  Result := TcpConnectAddr6(PalIn6Loopback, port, 0);
end;

function TcpConnectAddr6(const addr: TPalIn6Addr; port, scopeId: Integer): Integer;
var fd: Integer; rc: Integer;
begin
  fd := PalSocket(PAL_NET_AF_INET6, PAL_NET_SOCK_STREAM, 0);
  if fd < 0 then begin Result := fd; Exit; end;
  rc := PalSetSocketNonBlocking(fd, 1);
  rc := PalConnectIpv6(fd, addr, port, scopeId);
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

function UdpBind(host: LongWord; port: Integer): Integer;
var fd, rc: Integer;
begin
  fd := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_DGRAM, 0);
  if fd < 0 then
  begin
    Result := fd;
    Exit;
  end;
  rc := PalSetSocketNonBlocking(fd, 1);
  rc := PalSetSocketReuseAddr(fd, 1);
  rc := PalBindIpv4(fd, host, port);
  if rc < 0 then
  begin
    TcpClose(fd);
    Result := rc;
    Exit;
  end;
  Result := fd;
end;

function UdpRecvFrom(fd: Integer; buf: Pointer; len: Integer;
                     var host: LongWord; var port: Integer): Int64;
var n: Int64;
begin
  repeat
    n := PalRecvFromIpv4(fd, buf, len, host, port);
    if n = PAL_NET_EAGAIN then WaitReadable(fd);
  until n <> PAL_NET_EAGAIN;
  Result := n;
end;

function UdpSendTo(fd: Integer; buf: Pointer; len: Integer;
                   host: LongWord; port: Integer): Int64;
var n: Int64;
begin
  repeat
    n := PalSendToIpv4(fd, buf, len, host, port);
    if n = PAL_NET_EAGAIN then WaitWritable(fd);
  until n <> PAL_NET_EAGAIN;
  Result := n;
end;

end.
