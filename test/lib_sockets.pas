program lib_sockets;
{ Smoke for the FPC-compat sockets unit (feature-synapse-compile-check): byte
  order + a full IPv4 loopback round-trip through the fp* BSD calls over PAL. }
uses sockets;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

{ Bind port 0 and read back what the kernel gave us, exactly as
  test/lib_net_v6only.pas does. A FIXED port made two concurrent runs collide
  — a gate and a cross-sweep overlapping was enough
  ([[bug-b-two-lib-tests-are-environment-dependent-by-construction]]). }
const
  PORT = 0;
  { Linux errno numbers, spelled out because FPC keeps them in baseunix/errno
    rather than in Sockets. The values below are what an FPC 3.2.2 build of the
    same three calls actually reported, not what a header says. }
  ECONNREFUSED = 111;
  EINVAL       = 22;
  EBADF        = 9;

var
  srv, cli, conn: cint;
  a: TInetSockAddr;
  alen: TSocklen;
  sbuf: array[0..15] of Byte;
  rbuf: array[0..15] of Byte;
  i, got: Integer;
  ok: Boolean;
begin
  { Byte order. }
  SayBool('htons', htons(80) = $5000);
  SayBool('htonl', htonl($7F000001) = $0100007F);
  SayBool('roundtrip', ntohs(htons(443)) = 443);

  { Loopback listener. }
  srv := fpSocket(AF_INET, SOCK_STREAM, 0);
  SayBool('socket', srv >= 0);

  a.sin_family := AF_INET;
  a.sin_port := htons(PORT);
  a.sin_addr.s_addr := htonl(INADDR_LOOPBACK);
  SayBool('bind', fpBind(srv, @a, SizeOf(TInetSockAddr)) = 0);
  SayBool('listen', fpListen(srv, 4) = 0);

  { What port did we actually land on? The client below must aim at that, not
    at the 0 we asked for. Also asserts fpGetSockName, which nothing else did. }
  alen := SizeOf(TInetSockAddr);
  SayBool('sockname', (fpGetSockName(srv, @a, @alen) = 0) and (ntohs(a.sin_port) > 0));

  { Client connects to our own listener (kernel completes loopback SYN). }
  cli := fpSocket(AF_INET, SOCK_STREAM, 0);
  SayBool('connect', fpConnect(cli, @a, SizeOf(TInetSockAddr)) = 0);

  alen := SizeOf(TInetSockAddr);
  conn := fpAccept(srv, @a, @alen);
  SayBool('accept', conn >= 0);

  { Client -> server. }
  for i := 0 to 5 do sbuf[i] := i + 65;          { 'ABCDEF' }
  SayBool('send', fpSend(cli, @sbuf[0], 6, 0) = 6);
  got := fpRecv(conn, @rbuf[0], 16, 0);
  ok := got = 6;
  for i := 0 to 5 do ok := ok and (rbuf[i] = i + 65);
  SayBool('recv', ok);

  SayBool('close-conn', CloseSocket(conn) = 0);
  SayBool('close-cli',  CloseSocket(cli) = 0);
  SayBool('close-srv',  CloseSocket(srv) = 0);

  { FAILURE rows. Everything above only exercises success, which is how
    lib/rtl/sockets.pas shipped for months returning the PAL's raw -errno
    (-111, -22) where FPC returns -1, with fpGetErrno hardcoded to EIO. The
    consequence was silent: `if r = -1` — SOCKET_ERROR, and the idiom every
    FPC/Synapse caller writes — simply never fired on a failed call, so a
    failure was read as a success. Both columns below are FPC 3.2.2's answers
    to the same source
    ([[bug-b-sockets-fp-wrappers-return-raw-negative-errno-and-fpgeterrno-is-a-constant]]). }

  { connect to a port nothing listens on: -1 / ECONNREFUSED, not -111 }
  cli := fpSocket(AF_INET, SOCK_STREAM, 0);
  FillChar(a, SizeOf(a), 0);
  a.sin_family := AF_INET;
  a.sin_port := htons(1);
  a.sin_addr.s_addr := htonl($7F000001);
  SayBool('fail-connect-ret', fpConnect(cli, @a, SizeOf(TInetSockAddr)) = -1);
  SayBool('fail-connect-errno', fpGetErrno = ECONNREFUSED);
  CloseSocket(cli);

  { an invalid socket() call: -1 / EINVAL }
  SayBool('fail-socket-ret', fpSocket(-1, -1, -1) = -1);
  SayBool('fail-socket-errno', fpGetErrno = EINVAL);

  { errno is NOT cleared by a success — FPC's is only meaningful after a
    failure, and clearing it here would be its own divergence }
  cli := fpSocket(AF_INET, SOCK_STREAM, 0);
  SayBool('errno-survives-success', fpGetErrno = EINVAL);
  CloseSocket(cli);

  { operating on a closed fd: -1 / EBADF }
  SayBool('fail-send-ret', fpSend(cli, @sbuf[0], 1, 0) = -1);
  SayBool('fail-send-errno', fpGetErrno = EBADF);
end.
