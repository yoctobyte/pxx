program lib_platform_net_udp;
{ UDP datagram + readiness-poll smoke for the POSIX PAL. Sends a loopback
  datagram, polls the server socket for readability, recvfrom's it with peer
  address reporting, then echoes back to the reported peer. }

uses platform;

const
  PORT = 48733;

var
  srv, cli: Integer;
  rc: Integer;
  msg, buf: array[0..2] of Byte;
  n: Int64;
  pr: Integer;
  peerAddr: LongWord;
  peerPort: Integer;

begin
  srv := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_DGRAM, 0);
  if srv < 0 then
  begin
    writeln('udp=socket-fail');
    Halt(1);
  end;
  rc := PalSetSocketReuseAddr(srv, 1);
  rc := PalBindIpv4(srv, PAL_NET_IP_LOOPBACK, PORT);
  if rc < 0 then
  begin
    writeln('udp=bind-fail');
    Halt(1);
  end;

  cli := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_DGRAM, 0);
  if cli < 0 then
  begin
    writeln('udp=client-fail');
    Halt(1);
  end;

  msg[0] := Ord('u');
  msg[1] := Ord('d');
  msg[2] := Ord('p');
  n := PalSendToIpv4(cli, @msg[0], 3, PAL_NET_IP_LOOPBACK, PORT);
  if n <> 3 then
  begin
    writeln('udp=send-fail');
    Halt(1);
  end;

  pr := PalPoll(srv, PAL_POLL_IN, 1000);
  if (pr and PAL_POLL_IN) = 0 then
  begin
    writeln('udp=poll-fail');
    Halt(1);
  end;
  writeln('poll=ok');

  peerAddr := 0;
  peerPort := 0;
  n := PalRecvFromIpv4(srv, @buf[0], 3, peerAddr, peerPort);
  if (n = 3) and (buf[0] = msg[0]) and (buf[1] = msg[1]) and (buf[2] = msg[2]) then
    writeln('recv=ok')
  else
    writeln('recv=mismatch');
  if peerAddr = PAL_NET_IP_LOOPBACK then
    writeln('peer=ok')
  else
    writeln('peer=bad');

  { Echo the datagram back to the reported peer address/port. }
  n := PalSendToIpv4(srv, @buf[0], 3, peerAddr, peerPort);
  pr := PalPoll(cli, PAL_POLL_IN, 1000);
  if (pr and PAL_POLL_IN) = 0 then
  begin
    writeln('udp=echo-poll-fail');
    Halt(1);
  end;
  n := PalRecvFromIpv4(cli, @buf[0], 3, peerAddr, peerPort);
  if (n = 3) and (buf[0] = msg[0]) and (buf[1] = msg[1]) and (buf[2] = msg[2]) then
    writeln('echo=ok')
  else
    writeln('echo=fail');

  rc := PalSocketClose(cli);
  rc := PalSocketClose(srv);
  writeln('unsupported=', PalUnsupported);
end.
