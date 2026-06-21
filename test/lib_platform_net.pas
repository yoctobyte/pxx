program lib_platform_net;

uses platform;

const
  PORT = 48691;

var
  srv, cli, acc: Integer;
  rc, tries: Integer;
  msg: array[0..2] of Byte;
  buf: array[0..2] of Byte;
  n: Int64;

begin
  srv := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0);
  if srv < 0 then
  begin
    writeln('tcp=socket-fail');
    Halt(1);
  end;
  rc := PalSetSocketReuseAddr(srv, 1);
  rc := PalBindIpv4(srv, PAL_NET_IP_LOOPBACK, PORT);
  if rc < 0 then
  begin
    writeln('tcp=bind-fail');
    Halt(1);
  end;
  rc := PalListen(srv, 4);
  rc := PalSetSocketNonBlocking(srv, 1);

  cli := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0);
  rc := PalSetSocketNonBlocking(cli, 1);
  rc := PalConnectIpv4(cli, PAL_NET_IP_LOOPBACK, PORT);

  acc := -1;
  tries := 0;
  while acc < 0 do
  begin
    acc := PalAccept(srv);
    tries := tries + 1;
    if tries > 100000 then
    begin
      writeln('tcp=accept-timeout');
      Halt(1);
    end;
  end;

  msg[0] := Ord('n');
  msg[1] := Ord('e');
  msg[2] := Ord('t');
  n := -1;
  tries := 0;
  while n < 0 do
  begin
    n := PalSend(cli, @msg[0], 3);
    tries := tries + 1;
    if tries > 100000 then
    begin
      writeln('tcp=send-timeout');
      Halt(1);
    end;
  end;

  n := -1;
  tries := 0;
  while n < 0 do
  begin
    n := PalRecv(acc, @buf[0], 3);
    tries := tries + 1;
    if tries > 100000 then
    begin
      writeln('tcp=recv-timeout');
      Halt(1);
    end;
  end;

  if (n = 3) and (buf[0] = msg[0]) and (buf[1] = msg[1]) and (buf[2] = msg[2]) then
    writeln('tcp=ok')
  else
    writeln('tcp=mismatch');

  rc := PalShutdown(cli, PAL_SHUT_RDWR);
  rc := PalSocketClose(acc);
  rc := PalSocketClose(cli);
  rc := PalSocketClose(srv);
  writeln('unsupported=', PalUnsupported);
end.
