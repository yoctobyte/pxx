program lib_platform_net_sockopt;
{ Socket introspection smoke for the POSIX PAL: ephemeral bind + getsockname,
  peer-reporting accept, and SO_ERROR readback after a non-blocking connect.
  These are the readiness/error primitives a blocking net.pas needs to tell a
  completed connect from a failed one. }

uses platform;

var
  srv, cli, acc: Integer;
  rc, tries: Integer;
  pr: Integer;
  localAddr, peerAddr: LongWord;
  localPort, peerPort: Integer;
  sockErr: Integer;

begin
  srv := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0);
  if srv < 0 then
  begin
    writeln('sockopt=socket-fail');
    Halt(1);
  end;
  rc := PalSetSocketReuseAddr(srv, 1);
  { Bind to port 0 -> kernel assigns an ephemeral port. }
  rc := PalBindIpv4(srv, PAL_NET_IP_LOOPBACK, 0);
  if rc < 0 then
  begin
    writeln('sockopt=bind-fail');
    Halt(1);
  end;

  localAddr := 0;
  localPort := 0;
  rc := PalGetSockNameIpv4(srv, localAddr, localPort);
  if (rc = 0) and (localAddr = PAL_NET_IP_LOOPBACK) and (localPort > 0) then
    writeln('name=ok')
  else
    writeln('name=bad');

  rc := PalListen(srv, 4);
  rc := PalSetSocketNonBlocking(srv, 1);

  cli := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0);
  rc := PalSetSocketNonBlocking(cli, 1);
  rc := PalConnectIpv4(cli, PAL_NET_IP_LOOPBACK, localPort);
  { Non-blocking connect: expect 0 (immediate, loopback) or EINPROGRESS. }
  if (rc <> 0) and (rc <> PAL_NET_EINPROGRESS) then
  begin
    writeln('sockopt=connect-bad rc=', rc);
    Halt(1);
  end;

  { Server side: wait readable, then accept reporting the peer address. }
  pr := PalPoll(srv, PAL_POLL_IN, 1000);
  if (pr and PAL_POLL_IN) = 0 then
  begin
    writeln('sockopt=accept-poll-fail');
    Halt(1);
  end;
  peerAddr := 0;
  peerPort := 0;
  acc := PalAcceptIpv4(srv, peerAddr, peerPort);
  if acc < 0 then
  begin
    writeln('sockopt=accept-fail');
    Halt(1);
  end;
  if (peerAddr = PAL_NET_IP_LOOPBACK) and (peerPort > 0) then
    writeln('accept-peer=ok')
  else
    writeln('accept-peer=bad');

  { Client side: wait writable, then SO_ERROR must be 0 (connect succeeded). }
  pr := PalPoll(cli, PAL_POLL_OUT, 1000);
  if (pr and PAL_POLL_OUT) = 0 then
  begin
    writeln('sockopt=connect-poll-fail');
    Halt(1);
  end;
  sockErr := PalGetSockError(cli);
  if sockErr = 0 then
    writeln('sockerr=ok')
  else
    writeln('sockerr=bad');

  rc := PalSocketClose(acc);
  rc := PalSocketClose(cli);
  rc := PalSocketClose(srv);
  writeln('unsupported=', PalUnsupported);
end.
