program test_pal_signal;
{ PalIgnoreSignal(SIGPIPE): after ignoring, writing to a socket whose peer has
  closed returns an error instead of killing the process with SIGPIPE (exit 141).
  Without the ignore this program would die on the write; reaching the final line
  proves the ignore took. }
uses sysutils, platform;

const PORT = 36100;
var
  srv, cli, conn: Integer;
  buf: array[0..255] of Byte;
  i, pr: Integer;
  n: Int64;
  survived: Boolean;
begin
  if PalIgnoreSignal(PAL_SIGPIPE) <> 0 then begin WriteLn('FAIL: PalIgnoreSignal'); Halt(2); end;

  srv := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0);
  PalSetSocketReuseAddr(srv, 1);
  if PalBindIpv4(srv, PAL_NET_IP_LOOPBACK, PORT) < 0 then begin WriteLn('FAIL bind'); Halt(3); end;
  PalListen(srv, 4);
  PalSetSocketNonBlocking(srv, 1);

  cli := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0);
  PalSetSocketNonBlocking(cli, 1);
  PalConnectIpv4(cli, PAL_NET_IP_LOOPBACK, PORT);

  conn := -1;
  for i := 1 to 200 do
  begin
    pr := PalPoll(srv, PAL_POLL_IN, 20);
    if (pr and PAL_POLL_IN) <> 0 then begin conn := PalAccept(srv); if conn >= 0 then Break; end;
  end;
  if conn < 0 then begin WriteLn('FAIL accept'); Halt(4); end;

  PalPoll(cli, PAL_POLL_OUT, 1000);   { client connected }
  PalClose(conn);                     { peer closes -> client's next writes will SIGPIPE }

  for i := 0 to 255 do buf[i] := 65;
  survived := True;
  { hammer writes; one of them hits EPIPE. With SIGPIPE ignored we get -1, not death. }
  for i := 1 to 2000 do
  begin
    n := PalSend(cli, @buf[0], 256);
    if n < 0 then Break;   { EPIPE reported as error — the whole point }
  end;

  PalClose(cli); PalClose(srv);
  if survived then WriteLn('wrote to closed peer, survived (SIGPIPE ignored)');
  WriteLn('PAL SIGNAL OK');
end.
