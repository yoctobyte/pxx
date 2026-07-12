{ SPDX-License-Identifier: Zlib }
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

uses platform, sysutils;

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

  { IPv6 address (declared for compat; not wired into fp*). Union of the
    byte/word/dword views, matching FPC's in6_addr (Synapse's IN6_IS_ADDR_*
    helpers read u6_addr16/u6_addr32). }
  Tin6_addr = packed record
    case Byte of
      0: (u6_addr8:  array[0..15] of Byte);
      1: (u6_addr16: array[0..7] of Word);
      2: (u6_addr32: array[0..3] of cuint32);
      3: (s6_addr8:  array[0..15] of Byte);
      4: (s6_addr:   array[0..15] of Byte);
      5: (s6_addr16: array[0..7] of Word);
      6: (s6_addr32: array[0..3] of cuint32);
  end;
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
{ FPC Sockets aliases over in_addr (netdb callers: HostToNet(he.Addr)). }
function HostToNet(Host: in_addr): in_addr;
function NetToHost(Net: in_addr): in_addr;

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
function fpGetPeerName(s: cint; name: PInetSockAddr; namelen: pTSocklen): cint;
function fpSetSockOpt(s: cint; level: cint; optname: cint; optval: Pointer; optlen: TSocklen): cint;
function fpGetSockOpt(s: cint; level: cint; optname: cint; optval: Pointer; optlen: pTSocklen): cint;
function fpIoctl(s: cint; cmd: cint; data: Pointer): cint;
function CloseSocket(s: cint): cint;
function fpGetErrno: cint;

{ Address <-> string conversions (FPC Sockets surface; Synapse's GetSinIP /
  SetVarSin). in_addr/Tin6_addr are network byte order throughout. }
function NetAddrToStr(Entry: in_addr): string;
function StrToNetAddr(IP: string): in_addr;
function NetAddrToStr6(Entry: Tin6_addr): string;
function StrToNetAddr6(IP: string): Tin6_addr;
function HostAddrToStr(Entry: in_addr): string;
function StrToHostAddr(IP: string): in_addr;

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

function HostToNet(Host: in_addr): in_addr;
begin
  Result.s_addr := htonl(Host.s_addr);
end;

function NetToHost(Net: in_addr): in_addr;
begin
  Result.s_addr := ntohl(Net.s_addr);
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

function NetAddrToStr(Entry: in_addr): string;
var
  x: cuint32;
  i: Integer;
begin
  { network order in LE memory: first octet = low byte }
  x := Entry.s_addr;
  Result := '';
  for i := 0 to 3 do
  begin
    if i > 0 then Result := Result + '.';
    Result := Result + IntToStr((x shr (i * 8)) and $FF);
  end;
end;

function StrToNetAddr(IP: string): in_addr;
var
  i, p, oct, shift: Integer;
  x: cuint32;
begin
  Result.s_addr := 0;
  x := 0;
  oct := 0; shift := 0; p := 0;
  for i := 1 to Length(IP) do
  begin
    if IP[i] = '.' then
    begin
      if (p > 3) or (oct > 255) then Exit;
      x := x or (cuint32(oct) shl shift);
      shift := shift + 8; Inc(p); oct := 0;
    end
    else if (IP[i] >= '0') and (IP[i] <= '9') then
      oct := oct * 10 + (Ord(IP[i]) - Ord('0'))
    else
      Exit;
  end;
  if (p <> 3) or (oct > 255) then Exit;
  x := x or (cuint32(oct) shl shift);
  Result.s_addr := x;
end;

function NetAddrToStr6(Entry: Tin6_addr): string;
var
  g: array[0..7] of Integer;
  i, zStart, zLen, bStart, bLen: Integer;
  hex: string;
begin
  for i := 0 to 7 do
    g[i] := (Integer(Entry.u6_addr8[i * 2]) shl 8) or Entry.u6_addr8[i * 2 + 1];
  { longest zero-group run (>= 2) compresses to '::' }
  bStart := -1; bLen := 0; zStart := -1; zLen := 0;
  for i := 0 to 7 do
    if g[i] = 0 then
    begin
      if zStart < 0 then begin zStart := i; zLen := 0; end;
      Inc(zLen);
      if zLen > bLen then begin bStart := zStart; bLen := zLen; end;
    end
    else
      zStart := -1;
  if bLen < 2 then bStart := -1;
  Result := '';
  i := 0;
  while i <= 7 do
  begin
    if i = bStart then
    begin
      Result := Result + '::';
      i := i + bLen;
      continue;
    end;
    if (Length(Result) > 0) and (Result[Length(Result)] <> ':') then
      Result := Result + ':';
    hex := LowerCase(IntToHex(g[i], 1));
    Result := Result + hex;
    Inc(i);
  end;
  if Result = '' then Result := '::';
end;

function StrToNetAddr6(IP: string): Tin6_addr;
var
  i, gi, v, dcolon, n: Integer;
  groups: array[0..7] of Integer;
  tail: array[0..7] of Integer;
  tn: Integer;
  c: Char;
  cur: Integer; curSet: Boolean;

  procedure FlushGroup(var arr: array of Integer; var cnt: Integer);
  begin
    if not curSet then Exit;
    if cnt < 8 then begin arr[cnt] := cur; Inc(cnt); end;
    cur := 0; curSet := False;
  end;

begin
  for i := 0 to 15 do Result.u6_addr8[i] := 0;
  for i := 0 to 7 do begin groups[i] := 0; tail[i] := 0; end;
  gi := 0; tn := 0; dcolon := -1;
  cur := 0; curSet := False;
  i := 1;
  while i <= Length(IP) do
  begin
    c := IP[i];
    if c = ':' then
    begin
      if (i < Length(IP)) and (IP[i + 1] = ':') then
      begin
        if dcolon >= 0 then Exit;   { two '::' — invalid }
        if dcolon < 0 then
        begin
          FlushGroup(groups, gi);
          dcolon := gi;
        end;
        Inc(i);
      end
      else if dcolon < 0 then
        FlushGroup(groups, gi)
      else
        FlushGroup(tail, tn);
    end
    else
    begin
      v := -1;
      if (c >= '0') and (c <= '9') then v := Ord(c) - Ord('0')
      else if (c >= 'a') and (c <= 'f') then v := Ord(c) - Ord('a') + 10
      else if (c >= 'A') and (c <= 'F') then v := Ord(c) - Ord('A') + 10
      else Exit;   { '%zone' / '.' embedded v4 unsupported }
      if curSet then cur := cur * 16 + v else cur := v;
      curSet := True;
      if cur > $FFFF then Exit;
    end;
    Inc(i);
  end;
  if dcolon < 0 then FlushGroup(groups, gi) else FlushGroup(tail, tn);
  if dcolon < 0 then
  begin
    if gi <> 8 then Exit;
  end
  else
  begin
    { expand: groups[0..gi-1] :: tail[0..tn-1] }
    if gi + tn > 7 then Exit;
    n := 8 - tn;
    for i := 0 to tn - 1 do groups[n + i] := tail[i];
    for i := gi to n - 1 do groups[i] := 0;
    gi := 8;
  end;
  for i := 0 to 7 do
  begin
    Result.u6_addr8[i * 2] := (groups[i] shr 8) and $FF;
    Result.u6_addr8[i * 2 + 1] := groups[i] and $FF;
  end;
end;

function HostAddrToStr(Entry: in_addr): string;
var host: in_addr;
begin
  host.s_addr := htonl(Entry.s_addr);
  Result := NetAddrToStr(host);
end;

function StrToHostAddr(IP: string): in_addr;
begin
  Result := StrToNetAddr(IP);
  Result.s_addr := ntohl(Result.s_addr);
end;

function fpGetPeerName(s: cint; name: PInetSockAddr; namelen: pTSocklen): cint;
var host: LongWord; port: Integer;
begin
  Result := cint(PalGetPeerNameIpv4(s, host, port));
  if Result >= 0 then
  begin
    FillAddr(name, host, port);
    if namelen <> nil then namelen^ := SizeOf(TInetSockAddr);
  end;
end;

function fpSetSockOpt(s: cint; level: cint; optname: cint; optval: Pointer; optlen: TSocklen): cint;
begin
  Result := cint(PalSetSockOpt(s, level, optname, optval, optlen));
end;

function fpGetSockOpt(s: cint; level: cint; optname: cint; optval: Pointer; optlen: pTSocklen): cint;
begin
  Result := cint(PalGetSockOpt(s, level, optname, optval, optlen));
end;

function fpIoctl(s: cint; cmd: cint; data: Pointer): cint;
begin
  Result := cint(PalIoctl(s, cmd, data));
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
