unit net;
{ Target-neutral blocking IPv4 networking over the PAL socket surface.

  This is the normal (blocking) networking face; `asyncnet.pas` is the
  coroutine-backed face. Both sit on the same scheduler-free PAL primitives
  (`platform.pas`) — net.pas adds no platform conditionals of its own. IPv4
  only for now; IPv6 waits on a PAL sockaddr_in6 layout.

  TNetAddress carries a host-order IPv4 address + port; the PAL converts to
  network byte order internally. A TNetSocket is just the PAL handle (<0 is
  invalid / -errno). Calls return PAL results unchanged, so the negative
  values are -errno and the PAL_NET_E* / PAL_POLL_* constants apply. }

interface

uses platform;

type
  TNetSocket = Integer;
  TNetAddress = record
    Host: LongWord;   { IPv4 address, host byte order (e.g. PAL_NET_IP_LOOPBACK) }
    Port: Integer;
  end;

const
  NET_INVALID_SOCKET = -1;

function NetAddress(host: LongWord; port: Integer): TNetAddress;
function NetLoopback(port: Integer): TNetAddress;

{ TCP (blocking). On loopback a blocking connect to a listening socket
  completes via the kernel backlog before Accept is called, so a single
  thread can drive both sides. }
function NetTcpListen(const addr: TNetAddress; backlog: Integer): TNetSocket;
function NetTcpAccept(listener: TNetSocket; var peer: TNetAddress): TNetSocket;
function NetTcpConnect(const addr: TNetAddress): TNetSocket;
function NetSend(sock: TNetSocket; buf: Pointer; len: Integer): Int64;
function NetRecv(sock: TNetSocket; buf: Pointer; len: Integer): Int64;

{ UDP (blocking). }
function NetUdpBind(const addr: TNetAddress): TNetSocket;
function NetUdpSendTo(sock: TNetSocket; buf: Pointer; len: Integer; const dst: TNetAddress): Int64;
function NetUdpRecvFrom(sock: TNetSocket; buf: Pointer; len: Integer; var src: TNetAddress): Int64;

{ Introspection / lifecycle. }
function NetGetSockName(sock: TNetSocket; var addr: TNetAddress): Integer;
function NetGetSockError(sock: TNetSocket): Integer;
function NetShutdown(sock: TNetSocket; how: Integer): Integer;
function NetClose(sock: TNetSocket): Integer;

implementation

function NetAddress(host: LongWord; port: Integer): TNetAddress;
begin
  Result.Host := host;
  Result.Port := port;
end;

function NetLoopback(port: Integer): TNetAddress;
begin
  Result.Host := PAL_NET_IP_LOOPBACK;
  Result.Port := port;
end;

function NetTcpListen(const addr: TNetAddress; backlog: Integer): TNetSocket;
var fd, rc: Integer;
begin
  fd := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0);
  if fd < 0 then
  begin
    Result := fd;
    Exit;
  end;
  rc := PalSetSocketReuseAddr(fd, 1);
  rc := PalBindIpv4(fd, addr.Host, addr.Port);
  if rc < 0 then
  begin
    PalSocketClose(fd);
    Result := rc;
    Exit;
  end;
  rc := PalListen(fd, backlog);
  if rc < 0 then
  begin
    PalSocketClose(fd);
    Result := rc;
    Exit;
  end;
  Result := fd;
end;

function NetTcpAccept(listener: TNetSocket; var peer: TNetAddress): TNetSocket;
begin
  Result := PalAcceptIpv4(listener, peer.Host, peer.Port);
end;

function NetTcpConnect(const addr: TNetAddress): TNetSocket;
var fd, rc: Integer;
begin
  fd := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0);
  if fd < 0 then
  begin
    Result := fd;
    Exit;
  end;
  rc := PalConnectIpv4(fd, addr.Host, addr.Port);
  if rc < 0 then
  begin
    PalSocketClose(fd);
    Result := rc;
    Exit;
  end;
  Result := fd;
end;

function NetSend(sock: TNetSocket; buf: Pointer; len: Integer): Int64;
begin
  Result := PalSend(sock, buf, len);
end;

function NetRecv(sock: TNetSocket; buf: Pointer; len: Integer): Int64;
begin
  Result := PalRecv(sock, buf, len);
end;

function NetUdpBind(const addr: TNetAddress): TNetSocket;
var fd, rc: Integer;
begin
  fd := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_DGRAM, 0);
  if fd < 0 then
  begin
    Result := fd;
    Exit;
  end;
  rc := PalSetSocketReuseAddr(fd, 1);
  rc := PalBindIpv4(fd, addr.Host, addr.Port);
  if rc < 0 then
  begin
    PalSocketClose(fd);
    Result := rc;
    Exit;
  end;
  Result := fd;
end;

function NetUdpSendTo(sock: TNetSocket; buf: Pointer; len: Integer; const dst: TNetAddress): Int64;
begin
  Result := PalSendToIpv4(sock, buf, len, dst.Host, dst.Port);
end;

function NetUdpRecvFrom(sock: TNetSocket; buf: Pointer; len: Integer; var src: TNetAddress): Int64;
begin
  Result := PalRecvFromIpv4(sock, buf, len, src.Host, src.Port);
end;

function NetGetSockName(sock: TNetSocket; var addr: TNetAddress): Integer;
begin
  Result := PalGetSockNameIpv4(sock, addr.Host, addr.Port);
end;

function NetGetSockError(sock: TNetSocket): Integer;
begin
  Result := PalGetSockError(sock);
end;

function NetShutdown(sock: TNetSocket; how: Integer): Integer;
begin
  Result := PalShutdown(sock, how);
end;

function NetClose(sock: TNetSocket): Integer;
begin
  Result := PalSocketClose(sock);
end;

end.
