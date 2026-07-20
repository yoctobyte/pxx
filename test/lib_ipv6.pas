program lib_ipv6;
{ IPv6 over the PAL (feature-networking).

  Hermetic: binds :: on an ephemeral-range port, connects to ::1, and moves a
  byte string over the loopback interface. No external host, no DNS.

  A host with IPv6 disabled in the kernel cannot run this, so socket() failing
  with EAFNOSUPPORT is reported as a SKIP rather than a failure — the point is
  to catch a broken sockaddr_in6 layout, not to assert the CI box's netstack. }
uses platform;

const
  PORT = 28846;

function AddrHex(const a: TPalIn6Addr): AnsiString;
const hx: AnsiString = '0123456789abcdef';
var i: Integer; s: AnsiString;
begin
  s := '';
  for i := 0 to 15 do
    s := s + hx[((a.Bytes[i] shr 4) and 15) + 1] + hx[(a.Bytes[i] and 15) + 1];
  AddrHex := s;
end;

var
  srv, cli, conn, rc, i: Integer;
  a: TPalIn6Addr;
  buf: array[0..63] of Byte;
  n: Int64;
  got: AnsiString;
begin
  { the two well-known addresses must have the documented wire form }
  a := PalIn6Any;
  if AddrHex(a) <> '00000000000000000000000000000000' then
  begin writeln('FAIL :: wrong: ', AddrHex(a)); Halt(1); end;
  a := PalIn6Loopback;
  if AddrHex(a) <> '00000000000000000000000000000001' then
  begin writeln('FAIL ::1 wrong: ', AddrHex(a)); Halt(1); end;

  srv := PalSocket(PAL_NET_AF_INET6, PAL_NET_SOCK_STREAM, 0);
  if srv < 0 then
  begin
    writeln('IPV6 SKIP (no AF_INET6 on this host, socket() = ', srv, ')');
    Halt(0);
  end;
  { without this a previous run's socket in TIME_WAIT makes bind fail EADDRINUSE }
  rc := PalSetSocketReuseAddr(srv, 1);

  a := PalIn6Any;
  rc := PalBindIpv6(srv, a, PORT, 0);
  if rc <> 0 then begin writeln('FAIL bind :: -> ', rc); Halt(1); end;
  rc := PalListen(srv, 4);
  if rc <> 0 then begin writeln('FAIL listen -> ', rc); Halt(1); end;

  cli := PalSocket(PAL_NET_AF_INET6, PAL_NET_SOCK_STREAM, 0);
  if cli < 0 then begin writeln('FAIL client socket -> ', cli); Halt(1); end;
  a := PalIn6Loopback;
  rc := PalConnectIpv6(cli, a, PORT, 0);
  if rc <> 0 then begin writeln('FAIL connect ::1 -> ', rc); Halt(1); end;

  conn := PalAccept(srv);
  if conn < 0 then begin writeln('FAIL accept -> ', conn); Halt(1); end;

  n := PalWrite(cli, PChar('hello v6'), 8);
  if n <> 8 then begin writeln('FAIL write -> ', n); Halt(1); end;
  n := PalRead(conn, @buf[0], 64);
  got := '';
  for i := 0 to Integer(n) - 1 do got := got + Chr(buf[i]);
  if got <> 'hello v6' then begin writeln('FAIL payload -> [', got, ']'); Halt(1); end;

  rc := PalSocketClose(conn);
  rc := PalSocketClose(cli);
  rc := PalSocketClose(srv);
  writeln('IPV6 OK');
end.
