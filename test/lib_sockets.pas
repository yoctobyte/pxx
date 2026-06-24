program lib_sockets;
{ Smoke for the FPC-compat sockets unit (feature-synapse-compile-check): byte
  order + a full IPv4 loopback round-trip through the fp* BSD calls over PAL. }
uses sockets;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

const PORT = 28744;

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
end.
