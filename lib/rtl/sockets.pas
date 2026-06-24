unit sockets;
{ FPC-compatible Sockets unit — IPv4 core (feature-synapse-compile-check + our
  own net stack). Provides the BSD socket surface FPC's Sockets exposes, over the
  PAL IPv4 primitives (lib/rtl/platform). Byte-order helpers (htons/htonl/…) are
  the shared plumbing our own net/http code reuses.

  Scope: IPv4 (AF_INET). IPv6 types/consts are declared for source compat but the
  fp* calls operate on TInetSockAddr (IPv4); IPv6 sockaddr is not wired. fpSelect
  is implemented over PAL's ppoll. Not a port of FPC's Sockets unit — grown to the
  surface Synapse's ssfpc.inc and our net code consume. NetDB / name resolution
  lives elsewhere (lib/rtl/dns). }

interface

uses platform;

type
  cint        = LongInt;
  pcint       = ^cint;
  cuint       = LongWord;
  cushort     = Word;
  cuint32     = LongWord;
  TSocklen    = cuint;
  pTSocklen   = ^TSocklen;
  ssize_t     = Int64;
  sa_family_t = cushort;

  { IPv4 address in network byte order. }
  in_addr  = record s_addr: cuint32; end;
  Tin_addr = in_addr;
  pin_addr = ^in_addr;

  { IPv6 address (declared for compat; not wired into fp*). }
  Tin6_addr = record u6_addr8: array[0..15] of Byte; end;
  pin6_addr = ^Tin6_addr;

  { sockaddr_in — sin_port and sin_addr are network byte order. }
  TInetSockAddr = record
    sin_family: sa_family_t;
    sin_port:   cushort;
    sin_addr:   in_addr;
    sin_zero:   array[0..7] of Byte;
  end;
  PInetSockAddr = ^TInetSockAddr;
  TSockAddr     = TInetSockAddr;
  PSockAddr     = ^TSockAddr;

  TInetSockAddr6 = record
    sin6_family:   sa_family_t;
    sin6_port:     cushort;
    sin6_flowinfo: cuint32;
    sin6_addr:     Tin6_addr;
    sin6_scope_id: cuint32;
  end;
  PInetSockAddr6 = ^TInetSockAddr6;

  { select(2) descriptor set — a fixed bitmask over fd numbers. }
  TFDSet = record bits: array[0..31] of cuint32; end;  { 1024 fds }
  PFDSet = ^TFDSet;

const
  AF_UNSPEC = 0;  AF_INET = 2;  AF_INET6 = 10;
  SOCK_STREAM = 1;  SOCK_DGRAM = 2;  SOCK_RAW = 3;
  IPPROTO_IP = 0;  IPPROTO_TCP = 6;  IPPROTO_UDP = 17;

  INADDR_ANY       = $00000000;
  INADDR_LOOPBACK  = $7F000001;
  INADDR_BROADCAST = $FFFFFFFF;

  SOCKET_ERROR = -1;

  { Linux/x86 socket-option name space (values are the same across our LE targets). }
  SOL_SOCKET = 1;
  SO_DEBUG = 1;  SO_REUSEADDR = 2;  SO_TYPE = 3;  SO_ERROR = 4;
  SO_DONTROUTE = 5;  SO_BROADCAST = 6;  SO_SNDBUF = 7;  SO_RCVBUF = 8;
  SO_KEEPALIVE = 9;  SO_OOBINLINE = 10;  SO_NO_CHECK = 11;  SO_PRIORITY = 12;
  SO_LINGER = 13;  SO_BSDCOMPAT = 14;  SO_REUSEPORT = 15;  SO_PASSCRED = 16;
  SO_PEERCRED = 17;  SO_RCVLOWAT = 18;  SO_SNDLOWAT = 19;  SO_RCVTIMEO = 20;
  SO_SNDTIMEO = 21;
  SO_SECURITY_AUTHENTICATION = 22;
  SO_SECURITY_ENCRYPTION_TRANSPORT = 23;
  SO_SECURITY_ENCRYPTION_NETWORK = 24;
  SO_BINDTODEVICE = 25;  SO_ATTACH_FILTER = 26;  SO_DETACH_FILTER = 27;

  IP_TOS = 1;  IP_TTL = 2;  IP_HDRINCL = 3;  IP_OPTIONS = 4;
  IP_ROUTER_ALERT = 5;  IP_RECVOPTS = 6;  IP_RETOPTS = 7;  IP_PKTINFO = 8;
  IP_PKTOPTIONS = 9;  IP_PMTUDISC = 10;  IP_MTU_DISCOVER = 10;
  IP_RECVERR = 11;  IP_RECVTTL = 12;  IP_RECVTOS = 13;
  IP_MULTICAST_IF = 32;  IP_MULTICAST_TTL = 33;  IP_MULTICAST_LOOP = 34;
  IP_ADD_MEMBERSHIP = 35;  IP_DROP_MEMBERSHIP = 36;

  IPV6_UNICAST_HOPS = 16;  IPV6_MULTICAST_IF = 17;  IPV6_MULTICAST_HOPS = 18;
  IPV6_MULTICAST_LOOP = 19;  IPV6_JOIN_GROUP = 20;  IPV6_LEAVE_GROUP = 21;

  MSG_OOB = 1;  MSG_PEEK = 2;  MSG_NOSIGNAL = $4000;

{ Byte order (LE host -> network big-endian). Shared with our net/http code. }
function htons(host: Word): Word;
function ntohs(net: Word): Word;
function htonl(host: cuint32): cuint32;
function ntohl(net: cuint32): cuint32;

{ BSD socket calls over the PAL IPv4 primitives. fp* take a pointer to a
  TInetSockAddr (and its length) like FPC's Sockets. }
function fpSocket(domain, kind, protocol: cint): cint;
function fpBind(s: cint; addr: PInetSockAddr; addrlen: TSocklen): cint;
function fpConnect(s: cint; addr: PInetSockAddr; addrlen: TSocklen): cint;
function fpListen(s: cint; backlog: cint): cint;
function fpAccept(s: cint; addr: PInetSockAddr; addrlen: pTSocklen): cint;
function fpSend(s: cint; msg: Pointer; len: cint; flags: cint): ssize_t;
function fpRecv(s: cint; buf: Pointer; len: cint; flags: cint): ssize_t;
function fpSendTo(s: cint; msg: Pointer; len: cint; flags: cint; addr: PInetSockAddr; addrlen: TSocklen): ssize_t;
function fpRecvFrom(s: cint; buf: Pointer; len: cint; flags: cint; addr: PInetSockAddr; addrlen: pTSocklen): ssize_t;
function fpShutdown(s: cint; how: cint): cint;
function fpGetSockName(s: cint; name: PInetSockAddr; namelen: pTSocklen): cint;
function CloseSocket(s: cint): cint;
function fpGetErrno: cint;

{ select(2) descriptor-set ops + fpSelect over PAL ppoll. }
procedure fpFD_ZERO(var fdset: TFDSet);
procedure fpFD_SET(fd: cint; var fdset: TFDSet);
procedure fpFD_CLR(fd: cint; var fdset: TFDSet);
function  fpFD_ISSET(fd: cint; var fdset: TFDSet): cint;
function  fpSelect(nfds: cint; readfds, writefds, exceptfds: PFDSet; timeoutMs: cint): cint;

implementation

function htons(host: Word): Word;
begin
  Result := ((host and $00FF) shl 8) or ((host and $FF00) shr 8);
end;

function ntohs(net: Word): Word;
begin
  Result := htons(net);
end;

function htonl(host: cuint32): cuint32;
begin
  Result := ((host and $000000FF) shl 24) or ((host and $0000FF00) shl 8)
         or ((host and $00FF0000) shr 8)  or ((host and $FF000000) shr 24);
end;

function ntohl(net: cuint32): cuint32;
begin
  Result := htonl(net);
end;

function fpSocket(domain, kind, protocol: cint): cint;
begin
  Result := cint(PalSocket(domain, kind, protocol));
end;

function fpBind(s: cint; addr: PInetSockAddr; addrlen: TSocklen): cint;
begin
  if addr = nil then begin Result := SOCKET_ERROR; Exit; end;
  Result := cint(PalBindIpv4(s, ntohl(addr^.sin_addr.s_addr), ntohs(addr^.sin_port)));
end;

function fpConnect(s: cint; addr: PInetSockAddr; addrlen: TSocklen): cint;
begin
  if addr = nil then begin Result := SOCKET_ERROR; Exit; end;
  Result := cint(PalConnectIpv4(s, ntohl(addr^.sin_addr.s_addr), ntohs(addr^.sin_port)));
end;

function fpListen(s: cint; backlog: cint): cint;
begin
  Result := cint(PalListen(s, backlog));
end;

procedure FillAddr(addr: PInetSockAddr; host: cuint32; port: cint);
begin
  if addr = nil then Exit;
  addr^.sin_family := AF_INET;
  addr^.sin_port := htons(Word(port));
  addr^.sin_addr.s_addr := htonl(host);
end;

function fpAccept(s: cint; addr: PInetSockAddr; addrlen: pTSocklen): cint;
var host: LongWord; port: Integer;
begin
  Result := cint(PalAcceptIpv4(s, host, port));
  if Result >= 0 then
  begin
    FillAddr(addr, host, port);
    if addrlen <> nil then addrlen^ := SizeOf(TInetSockAddr);
  end;
end;

function fpSend(s: cint; msg: Pointer; len: cint; flags: cint): ssize_t;
begin
  Result := PalSend(s, msg, len);
end;

function fpRecv(s: cint; buf: Pointer; len: cint; flags: cint): ssize_t;
begin
  Result := PalRecv(s, buf, len);
end;

function fpSendTo(s: cint; msg: Pointer; len: cint; flags: cint; addr: PInetSockAddr; addrlen: TSocklen): ssize_t;
begin
  if addr = nil then begin Result := SOCKET_ERROR; Exit; end;
  Result := PalSendToIpv4(s, msg, len, ntohl(addr^.sin_addr.s_addr), ntohs(addr^.sin_port));
end;

function fpRecvFrom(s: cint; buf: Pointer; len: cint; flags: cint; addr: PInetSockAddr; addrlen: pTSocklen): ssize_t;
var host: LongWord; port: Integer;
begin
  Result := PalRecvFromIpv4(s, buf, len, host, port);
  if (Result >= 0) and (addr <> nil) then
  begin
    FillAddr(addr, host, port);
    if addrlen <> nil then addrlen^ := SizeOf(TInetSockAddr);
  end;
end;

function fpShutdown(s: cint; how: cint): cint;
begin
  Result := cint(PalShutdown(s, how));
end;

function fpGetSockName(s: cint; name: PInetSockAddr; namelen: pTSocklen): cint;
var host: LongWord; port: Integer;
begin
  Result := cint(PalGetSockNameIpv4(s, host, port));
  if Result >= 0 then
  begin
    FillAddr(name, host, port);
    if namelen <> nil then namelen^ := SizeOf(TInetSockAddr);
  end;
end;

function CloseSocket(s: cint): cint;
begin
  Result := cint(PalSocketClose(s));
end;

function fpGetErrno: cint;
begin
  { PAL primitives return negative on error rather than setting a global errno;
    we have no thread-global errno, so report a generic failure. Callers that
    only test "<> 0" (Synapse) are satisfied. }
  Result := 5; { EIO }
end;

procedure fpFD_ZERO(var fdset: TFDSet);
var i: Integer;
begin
  for i := 0 to 31 do fdset.bits[i] := 0;
end;

procedure fpFD_SET(fd: cint; var fdset: TFDSet);
begin
  if (fd >= 0) and (fd < 1024) then
    fdset.bits[fd shr 5] := fdset.bits[fd shr 5] or (cuint32(1) shl (fd and 31));
end;

procedure fpFD_CLR(fd: cint; var fdset: TFDSet);
begin
  if (fd >= 0) and (fd < 1024) then
    fdset.bits[fd shr 5] := fdset.bits[fd shr 5] and (not (cuint32(1) shl (fd and 31)));
end;

function fpFD_ISSET(fd: cint; var fdset: TFDSet): cint;
begin
  if (fd >= 0) and (fd < 1024) and
     ((fdset.bits[fd shr 5] and (cuint32(1) shl (fd and 31))) <> 0) then
    Result := 1
  else
    Result := 0;
end;

function fpSelect(nfds: cint; readfds, writefds, exceptfds: PFDSet; timeoutMs: cint): cint;
var
  fd, n: cint;
  wantR, wantW: Boolean;
  events, got: Integer;
  rOut, wOut: TFDSet;
begin
  { Single-fd-at-a-time readiness over PAL ppoll. Adequate for Synapse's
    blcksock (it selects one socket with a timeout); a true multi-fd select
    would batch a pollfd array. }
  fpFD_ZERO(rOut);
  fpFD_ZERO(wOut);
  n := 0;
  for fd := 0 to nfds - 1 do
  begin
    { Read the request bits straight off the pointer (PXX does not accept a
      pointer-deref as a var argument, so we can't call fpFD_ISSET(.., ptr^);
      reading the field directly is equivalent and idiomatic). }
    wantR := (readfds <> nil) and
             ((readfds^.bits[fd shr 5] and (cuint32(1) shl (fd and 31))) <> 0);
    wantW := (writefds <> nil) and
             ((writefds^.bits[fd shr 5] and (cuint32(1) shl (fd and 31))) <> 0);
    if not (wantR or wantW) then Continue;
    events := 0;
    if wantR then events := events or PAL_POLL_IN;
    if wantW then events := events or PAL_POLL_OUT;
    got := PalPoll(fd, events, timeoutMs);
    if got > 0 then
    begin
      if wantR and ((got and PAL_POLL_IN) <> 0) then begin fpFD_SET(fd, rOut); Inc(n); end;
      if wantW and ((got and PAL_POLL_OUT) <> 0) then begin fpFD_SET(fd, wOut); Inc(n); end;
    end;
  end;
  if readfds <> nil then readfds^ := rOut;
  if writefds <> nil then writefds^ := wOut;
  if exceptfds <> nil then
    for fd := 0 to 31 do exceptfds^.bits[fd] := 0;
  Result := n;
end;

end.
