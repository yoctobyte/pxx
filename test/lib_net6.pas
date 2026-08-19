program lib_net6;
{ IPv6 through the net.pas surface (feature-networking).

  Asserts both directions of the change: a v6 listen/connect/accept round trip
  works, AND the existing IPv4 path is unchanged — TNetAddress grew a Family
  field, so "did v4 still work" is the more important half of this test.

  SKIPs when the host has no AF_INET6, same as lib_ipv6: a kernel with IPv6
  disabled is not a code defect. }
uses net, platform;
var srv, cli, conn: TNetSocket; a, p: TNetAddress; buf: array[0..31] of Byte; n: Int64; i: Integer; got: AnsiString;
    us, uc: TNetSocket; src, dst: TNetAddress;

{ ::1 — the address a loopback peer must report }
function IsV6Loopback(const addr: TNetAddress): Boolean;
var k: Integer; ok: Boolean;
begin
  ok := addr.V6.Bytes[15] = 1;
  for k := 0 to 14 do if addr.V6.Bytes[k] <> 0 then ok := False;
  IsV6Loopback := ok;
end;

begin
  a := NetAny6(28850);
  srv := NetTcpListen(a, 4);
  if srv < 0 then
  begin
    writeln('NET6 SKIP (no AF_INET6 on this host, listen = ', srv, ')');
    Halt(0);
  end;
  cli := NetTcpConnect(NetLoopback6(28850));
  if cli < 0 then begin writeln('FAIL v6 connect -> ', cli); Halt(1); end;
  conn := NetTcpAccept6(srv, p);
  if conn < 0 then begin writeln('FAIL v6 accept -> ', conn); Halt(1); end;
  if p.Family <> PAL_NET_AF_INET6 then begin writeln('FAIL peer family ', p.Family); Halt(1); end;
  { the peer address itself, not just the family: a client on ::1 must come
    back as ::1 with the ephemeral port it actually used }
  if not IsV6Loopback(p) then begin writeln('FAIL peer address is not ::1'); Halt(1); end;
  if p.Port <= 0 then begin writeln('FAIL peer port ', p.Port); Halt(1); end;
  n := NetSend(cli, PChar('v6 via net'), 10);
  n := NetRecv(conn, @buf[0], 32);
  got := '';
  for i := 0 to Integer(n) - 1 do got := got + Chr(buf[i]);
  if got <> 'v6 via net' then begin writeln('FAIL payload [', got, ']'); Halt(1); end;
  NetClose(conn); NetClose(cli); NetClose(srv);
  { IPv4 must still work unchanged }
  { The listen/connect checks come BEFORE the accept, not after. It does not hang
    either way — accept on an invalid descriptor errors immediately — but reading
    `srv` only after using it is the shape that let
    bug-b-lib-tls-hangs-forever-when-its-hardcoded-port-is-unavailable sit for
    months, so it should not be left here looking like one. }
  srv := NetTcpListen(NetLoopback(28851), 4);
  if srv < 0 then begin writeln('FAIL ipv4 listen -> ', srv); Halt(1); end;
  cli := NetTcpConnect(NetLoopback(28851));
  if cli < 0 then begin writeln('FAIL ipv4 connect -> ', cli); Halt(1); end;
  conn := NetTcpAccept(srv, p);
  if conn < 0 then begin writeln('FAIL ipv4 accept -> ', conn); Halt(1); end;
  if p.Family <> PAL_NET_AF_INET then begin writeln('FAIL v4 peer family'); Halt(1); end;
  NetClose(conn); NetClose(cli); NetClose(srv);

  { UDP over v6: bind a receiver on ::1, send it a datagram from another v6
    socket, and read back BOTH the payload and the sender's address. }
  us := NetUdpBind(NetLoopback6(28852));
  if us < 0 then begin writeln('FAIL v6 udp bind -> ', us); Halt(1); end;
  uc := NetUdpBind(NetLoopback6(28853));
  if uc < 0 then begin writeln('FAIL v6 udp bind (sender) -> ', uc); Halt(1); end;
  dst := NetLoopback6(28852);
  n := NetUdpSendTo(uc, PChar('v6 datagram'), 11, dst);
  if n <> 11 then begin writeln('FAIL v6 udp sendto -> ', n); Halt(1); end;
  { src carries the FAMILY in, and the sender's address out }
  src := NetAny6(0);
  n := NetUdpRecvFrom(us, @buf[0], 32, src);
  if n <> 11 then begin writeln('FAIL v6 udp recvfrom -> ', n); Halt(1); end;
  got := '';
  for i := 0 to Integer(n) - 1 do got := got + Chr(buf[i]);
  if got <> 'v6 datagram' then begin writeln('FAIL v6 udp payload [', got, ']'); Halt(1); end;
  if not IsV6Loopback(src) then begin writeln('FAIL v6 udp sender is not ::1'); Halt(1); end;
  if src.Port <> 28853 then begin writeln('FAIL v6 udp sender port ', src.Port); Halt(1); end;
  NetClose(uc); NetClose(us);

  { and UDP over v4 is unchanged }
  us := NetUdpBind(NetLoopback(28854));
  uc := NetUdpBind(NetLoopback(28855));
  if (us < 0) or (uc < 0) then begin writeln('FAIL v4 udp regressed'); Halt(1); end;
  n := NetUdpSendTo(uc, PChar('v4 datagram'), 11, NetLoopback(28854));
  src := NetAddress(0, 0);
  n := NetUdpRecvFrom(us, @buf[0], 32, src);
  got := '';
  for i := 0 to Integer(n) - 1 do got := got + Chr(buf[i]);
  if got <> 'v4 datagram' then begin writeln('FAIL v4 udp payload [', got, ']'); Halt(1); end;
  if src.Port <> 28855 then begin writeln('FAIL v4 udp sender port ', src.Port); Halt(1); end;
  NetClose(uc); NetClose(us);

  { NetTcpConnectTimeout must honour the address family too. It used to
    hard-code AF_INET/PalConnectIpv4 — missed when IPv6 landed in net.pas — so a
    v6 address silently built a v4 socket and connected to addr.Host, which is 0
    for a v6 address: a connect to 0.0.0.0 rather than an error. The plain
    NetTcpConnect always branched correctly, which is exactly why this hid: the
    v6 tests above all use NetTcpConnect. }
  srv := NetTcpListen(NetLoopback6(28856), 4);
  if srv < 0 then begin writeln('FAIL v6 listen for connect-timeout ', srv); Halt(1); end;
  cli := NetTcpConnectTimeout(NetLoopback6(28856), 2000);
  if cli < 0 then
  begin
    writeln('FAIL v6 NetTcpConnectTimeout -> ', cli);
    Halt(1);
  end;
  conn := NetTcpAccept6(srv, p);
  if conn < 0 then begin writeln('FAIL v6 accept after connect-timeout ', conn); Halt(1); end;
  if not IsV6Loopback(p) then begin writeln('FAIL v6 connect-timeout peer is not ::1'); Halt(1); end;
  NetClose(conn); NetClose(cli); NetClose(srv);

  { and the v4 path through the SAME call is unchanged }
  srv := NetTcpListen(NetLoopback(28857), 4);
  cli := NetTcpConnectTimeout(NetLoopback(28857), 2000);
  if (srv < 0) or (cli < 0) then begin writeln('FAIL v4 connect-timeout regressed'); Halt(1); end;
  conn := NetTcpAccept(srv, p);
  if conn < 0 then begin writeln('FAIL v4 accept after connect-timeout ', conn); Halt(1); end;
  NetClose(conn); NetClose(cli); NetClose(srv);

  writeln('NET6 OK');
end.
