program lib_net6;
{ IPv6 through the net.pas surface (feature-networking).

  Asserts both directions of the change: a v6 listen/connect/accept round trip
  works, AND the existing IPv4 path is unchanged — TNetAddress grew a Family
  field, so "did v4 still work" is the more important half of this test.

  SKIPs when the host has no AF_INET6, same as lib_ipv6: a kernel with IPv6
  disabled is not a code defect. }
uses net, platform;
var srv, cli, conn: TNetSocket; a, p: TNetAddress; buf: array[0..31] of Byte; n: Int64; i: Integer; got: AnsiString;
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
  n := NetSend(cli, PChar('v6 via net'), 10);
  n := NetRecv(conn, @buf[0], 32);
  got := '';
  for i := 0 to Integer(n) - 1 do got := got + Chr(buf[i]);
  if got <> 'v6 via net' then begin writeln('FAIL payload [', got, ']'); Halt(1); end;
  NetClose(conn); NetClose(cli); NetClose(srv);
  { IPv4 must still work unchanged }
  srv := NetTcpListen(NetLoopback(28851), 4);
  cli := NetTcpConnect(NetLoopback(28851));
  conn := NetTcpAccept(srv, p);
  if (srv < 0) or (cli < 0) or (conn < 0) then
  begin writeln('FAIL ipv4 path regressed'); Halt(1); end;
  if p.Family <> PAL_NET_AF_INET then begin writeln('FAIL v4 peer family'); Halt(1); end;
  NetClose(conn); NetClose(cli); NetClose(srv);
  writeln('NET6 OK');
end.
