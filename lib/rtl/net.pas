{ SPDX-License-Identifier: Zlib }
unit net;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Target-neutral blocking IPv4 networking over the PAL socket surface.

  This is the normal (blocking) networking face; `asyncnet.pas` is the
  coroutine-backed face. Both sit on the same scheduler-free PAL primitives
  (`platform.pas`) — net.pas adds no platform conditionals of its own. TCP and
  UDP speak both IPv4 and IPv6; an address carries its family and the calls
  branch on it.

  TNetAddress carries a host-order IPv4 address + port; the PAL converts to
  network byte order internally. A TNetSocket is just the PAL handle (<0 is
  invalid / -errno). Calls return PAL results unchanged, so the negative
  values are -errno and the PAL_NET_E* / PAL_POLL_* constants apply. }

interface

uses platform, platform_types;

type
  TNetSocket = Integer;

  { An address is IPv4 or IPv6 depending on Family.

    Family is NOT optional: a record built by hand rather than through
    NetAddress/NetAddress6 has an indeterminate Family, and the difference
    decides which socket family gets created. Always construct through the
    helpers below — that is why they exist. NetTcpAccept and NetUdpRecvFrom set
    Family on the peer they fill in, so an out-parameter is always well formed. }
  TNetAddress = record
    Family: Integer;  { PAL_NET_AF_INET or PAL_NET_AF_INET6 }
    Host: LongWord;   { IPv4 address, host byte order (e.g. PAL_NET_IP_LOOPBACK) }
    Port: Integer;
    V6: TPalIn6Addr;  { IPv6 address, wire order; meaningful when Family = INET6 }
    ScopeId: Integer; { interface index for link-local (fe80::/10); 0 otherwise }
  end;

const
  NET_INVALID_SOCKET = -1;

const
  { NetTcpListen's v6Only argument. INHERIT is the decided default (leave the
    host's bindv6only alone); the other two pin it for a caller who cares. }
  NET_V6ONLY_INHERIT = -1;
  NET_V6ONLY_OFF     = 0;   { dual-stack: v4 peers arrive as ::ffff:a.b.c.d }
  NET_V6ONLY_ON      = 1;   { strict v6; serve v4 on a second listener }

function NetAddress(host: LongWord; port: Integer): TNetAddress;
function NetLoopback(port: Integer): TNetAddress;

{ IPv6 counterparts. `addr` is the 16 wire-order bytes; scopeId is the interface
  index a link-local address needs and 0 everywhere else. }
function NetAddress6(const addr: TPalIn6Addr; port, scopeId: Integer): TNetAddress;
function NetLoopback6(port: Integer): TNetAddress;   { ::1 }
function NetAny6(port: Integer): TNetAddress;        { ::, all interfaces }

{ True when the address is IPv6 — for callers that must branch (logging,
  formatting) rather than just pass it along. }
function NetIsV6(const addr: TNetAddress): Boolean;

{ TCP (blocking). On loopback a blocking connect to a listening socket
  completes via the kernel backlog before Accept is called, so a single
  thread can drive both sides. }
{ `v6Only` controls IPV6_V6ONLY on a `::` listener, and is ignored for IPv4.

  The DEFAULT is INHERIT — whatever the host's /proc/sys/net/ipv6/bindv6only
  says. That is the decided policy (decide-ipv6-dualstack-and-aaaa-ordering,
  user, 2026-08-01): plain `bind()` on `::` with no setsockopt is exactly what
  raw BSD sockets do, so it matches the platform rather than second-guessing a
  sysadmin's system-wide setting.

  The explicit values are the other half of that decision — "do nothing" as the
  default must not also mean "no escape hatch" for a caller who does care,
  because the inherited setting is a sysctl an administrator can change under a
  running program. Asking explicitly and being refused is an ERROR here, not a
  silent fallback to the inherited value: a caller who pinned it meant it. }
function NetTcpListen(const addr: TNetAddress; backlog: Integer;
                      v6Only: Integer = NET_V6ONLY_INHERIT): TNetSocket;
function NetTcpAccept(listener: TNetSocket; var peer: TNetAddress): TNetSocket;
{ Accept on an IPv6 listener. The peer address IS filled in — address, port and
  scope id — since PalAcceptIpv6 landed. }
function NetTcpAccept6(listener: TNetSocket; var peer: TNetAddress): TNetSocket;
function NetTcpConnect(const addr: TNetAddress): TNetSocket;
{ Connect with a deadline. Returns a connected (blocking) socket >= 0, or a
  negative PAL error: PAL_NET_ETIMEDOUT on deadline, or the SO_ERROR/connect
  errno (e.g. PAL_NET_ECONNREFUSED) on failure. Drives the non-blocking
  connect -> poll-writable -> SO_ERROR sequence. }
function NetTcpConnectTimeout(const addr: TNetAddress; timeoutMs: Integer): TNetSocket;
function NetSend(sock: TNetSocket; buf: Pointer; len: Integer): Int64;
function NetRecv(sock: TNetSocket; buf: Pointer; len: Integer): Int64;
{ Wait up to timeoutMs for the socket to become readable, then recv once.
  Returns the byte count (>0), 0 on peer close, PAL_NET_ETIMEDOUT on deadline,
  or a negative poll/recv errno. }
function NetRecvTimeout(sock: TNetSocket; buf: Pointer; len: Integer; timeoutMs: Integer): Int64;

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
  Result.Family := PAL_NET_AF_INET;
  Result.Host := host;
  Result.Port := port;
  Result.V6 := PalIn6Any;
  Result.ScopeId := 0;
end;

function NetLoopback(port: Integer): TNetAddress;
begin
  Result := NetAddress(PAL_NET_IP_LOOPBACK, port);
end;

function NetAddress6(const addr: TPalIn6Addr; port, scopeId: Integer): TNetAddress;
begin
  Result.Family := PAL_NET_AF_INET6;
  Result.Host := 0;
  Result.Port := port;
  Result.V6 := addr;
  Result.ScopeId := scopeId;
end;

function NetLoopback6(port: Integer): TNetAddress;
begin
  Result := NetAddress6(PalIn6Loopback, port, 0);
end;

function NetAny6(port: Integer): TNetAddress;
begin
  Result := NetAddress6(PalIn6Any, port, 0);
end;

function NetIsV6(const addr: TNetAddress): Boolean;
begin
  NetIsV6 := addr.Family = PAL_NET_AF_INET6;
end;

function NetTcpListen(const addr: TNetAddress; backlog: Integer;
                      v6Only: Integer): TNetSocket;
var fd, rc, optVal: Integer;
begin
  fd := PalSocket(addr.Family, PAL_NET_SOCK_STREAM, 0);
  if fd < 0 then
  begin
    Result := fd;
    Exit;
  end;
  rc := PalSetSocketReuseAddr(fd, 1);
  { Before bind: IPV6_V6ONLY cannot be changed afterwards. Only when the caller
    asked — the default leaves the host setting untouched, which is the policy. }
  if NetIsV6(addr) and (v6Only <> NET_V6ONLY_INHERIT) then
  begin
    if v6Only <> NET_V6ONLY_OFF then optVal := 1 else optVal := 0;
    rc := PalSetSockOpt(fd, PAL_NET_IPPROTO_IPV6, PAL_NET_IPV6_V6ONLY,
                        @optVal, SizeOf(optVal));
    if rc < 0 then
    begin
      { an explicit request that could not be honoured is an error, not a
        silent fall back to whatever the host happened to be set to }
      PalSocketClose(fd);
      Result := rc;
      Exit;
    end;
  end;
  if NetIsV6(addr) then
    rc := PalBindIpv6(fd, addr.V6, addr.Port, addr.ScopeId)
  else
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
  peer := NetAddress(0, 0);
  Result := PalAcceptIpv4(listener, peer.Host, peer.Port);
end;

{ The v6 peer address is REAL now: PalAcceptIpv6 fills a sockaddr_in6 and the
  scope id comes back with it, which a link-local peer needs to be answerable
  at all. Before this the family was set honestly to INET6 and the address left
  zero, because reporting a zeroed peer as if it were real is worse than
  reporting nothing. }
function NetTcpAccept6(listener: TNetSocket; var peer: TNetAddress): TNetSocket;
begin
  peer := NetAddress6(PalIn6Any, 0, 0);
  Result := PalAcceptIpv6(listener, peer.V6, peer.Port, peer.ScopeId);
end;

function NetTcpConnect(const addr: TNetAddress): TNetSocket;
var fd, rc: Integer;
begin
  fd := PalSocket(addr.Family, PAL_NET_SOCK_STREAM, 0);
  if fd < 0 then
  begin
    Result := fd;
    Exit;
  end;
  if NetIsV6(addr) then
    rc := PalConnectIpv6(fd, addr.V6, addr.Port, addr.ScopeId)
  else
    rc := PalConnectIpv4(fd, addr.Host, addr.Port);
  if rc < 0 then
  begin
    PalSocketClose(fd);
    Result := rc;
    Exit;
  end;
  Result := fd;
end;

function NetTcpConnectTimeout(const addr: TNetAddress; timeoutMs: Integer): TNetSocket;
var fd, rc, pr, soErr: Integer;
begin
  { Branch on the address's family, like NetTcpConnect. This used to hard-code
    AF_INET and PalConnectIpv4 — missed when IPv6 landed in this unit — so a v6
    address silently produced a v4 socket connecting to addr.Host, which is 0
    for a v6 address: a connect to 0.0.0.0 rather than an error. }
  fd := PalSocket(addr.Family, PAL_NET_SOCK_STREAM, 0);
  if fd < 0 then
  begin
    Result := fd;
    Exit;
  end;
  rc := PalSetSocketNonBlocking(fd, 1);
  if NetIsV6(addr) then
    rc := PalConnectIpv6(fd, addr.V6, addr.Port, addr.ScopeId)
  else
    rc := PalConnectIpv4(fd, addr.Host, addr.Port);
  if rc = 0 then
  begin
    { Immediate completion (common on loopback). }
    PalSetSocketNonBlocking(fd, 0);
    Result := fd;
    Exit;
  end;
  if rc <> PAL_NET_EINPROGRESS then
  begin
    { Synchronous failure, e.g. a loopback RST reported as -ECONNREFUSED. }
    PalSocketClose(fd);
    Result := rc;
    Exit;
  end;
  { In progress: the connect completes (or fails) when the socket is writable. }
  pr := PalPoll(fd, PAL_POLL_OUT, timeoutMs);
  if pr <= 0 then
  begin
    PalSocketClose(fd);
    if pr = 0 then Result := PAL_NET_ETIMEDOUT else Result := pr;
    Exit;
  end;
  soErr := PalGetSockError(fd);
  if soErr <> 0 then
  begin
    PalSocketClose(fd);
    Result := soErr;
    Exit;
  end;
  PalSetSocketNonBlocking(fd, 0);
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

function NetRecvTimeout(sock: TNetSocket; buf: Pointer; len: Integer; timeoutMs: Integer): Int64;
var pr: Integer;
begin
  pr := PalPoll(sock, PAL_POLL_IN, timeoutMs);
  if pr < 0 then
  begin
    Result := pr;
    Exit;
  end;
  if pr = 0 then
  begin
    Result := PAL_NET_ETIMEDOUT;
    Exit;
  end;
  Result := PalRecv(sock, buf, len);
end;

{ UDP branches on the bound address's FAMILY, exactly as the TCP path does —
  the socket is created for that family, so a v6 address gets an AF_INET6
  socket and a sockaddr_in6 on every subsequent send. }
function NetUdpBind(const addr: TNetAddress): TNetSocket;
var fd, rc: Integer;
begin
  fd := PalSocket(addr.Family, PAL_NET_SOCK_DGRAM, 0);
  if fd < 0 then
  begin
    Result := fd;
    Exit;
  end;
  rc := PalSetSocketReuseAddr(fd, 1);
  if NetIsV6(addr) then
    rc := PalBindIpv6(fd, addr.V6, addr.Port, addr.ScopeId)
  else
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
  if NetIsV6(dst) then
    Result := PalSendToIpv6(sock, buf, len, dst.V6, dst.Port, dst.ScopeId)
  else
    Result := PalSendToIpv4(sock, buf, len, dst.Host, dst.Port);
end;

{ The CALLER's `src` says which family to read back — a v6 socket's datagrams
  come with a sockaddr_in6 and nothing else fits. Pre-set it (NetAddress6) the
  same way the address you bound with was built. }
function NetUdpRecvFrom(sock: TNetSocket; buf: Pointer; len: Integer; var src: TNetAddress): Int64;
begin
  if NetIsV6(src) then
    Result := PalRecvFromIpv6(sock, buf, len, src.V6, src.Port, src.ScopeId)
  else
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
