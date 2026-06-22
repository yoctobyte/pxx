program lib_net;
{ End-to-end smoke for the blocking net.pas API over the PAL socket surface.
  Single-threaded loopback: a blocking TCP connect to a listening socket
  completes via the kernel backlog, so the same thread can connect then accept.
  Exercises ephemeral bind + getsockname, peer-reporting accept, TCP send/recv,
  and UDP sendto/recvfrom with peer address. }

uses net, platform;

var
  srv, cli, acc: TNetSocket;
  udpSrv, udpCli: TNetSocket;
  bound, peer, udpPeer: TNetAddress;
  msg, buf: array[0..4] of Byte;
  n: Int64;
  rc: Integer;
  i: Integer;

procedure SetMsg;
begin
  msg[0] := Ord('h');
  msg[1] := Ord('e');
  msg[2] := Ord('l');
  msg[3] := Ord('l');
  msg[4] := Ord('o');
end;

function Match: Boolean;
var k: Integer;
begin
  Match := True;
  for k := 0 to 4 do
    if buf[k] <> msg[k] then Match := False;
end;

begin
  SetMsg;

  { ---- TCP ---- }
  srv := NetTcpListen(NetLoopback(0), 4);
  if srv < 0 then
  begin
    writeln('tcp=listen-fail');
    Halt(1);
  end;
  rc := NetGetSockName(srv, bound);
  if (rc = 0) and (bound.Host = PAL_NET_IP_LOOPBACK) and (bound.Port > 0) then
    writeln('bound=ok')
  else
    writeln('bound=bad');

  cli := NetTcpConnect(NetLoopback(bound.Port));
  if cli < 0 then
  begin
    writeln('tcp=connect-fail');
    Halt(1);
  end;

  peer.Host := 0;
  peer.Port := 0;
  acc := NetTcpAccept(srv, peer);
  if acc < 0 then
  begin
    writeln('tcp=accept-fail');
    Halt(1);
  end;
  if (peer.Host = PAL_NET_IP_LOOPBACK) and (peer.Port > 0) then
    writeln('peer=ok')
  else
    writeln('peer=bad');

  n := NetSend(cli, @msg[0], 5);
  if n <> 5 then
  begin
    writeln('tcp=send-fail');
    Halt(1);
  end;
  for i := 0 to 4 do buf[i] := 0;
  n := NetRecv(acc, @buf[0], 5);
  if (n = 5) and Match then
    writeln('tcp=ok')
  else
    writeln('tcp=mismatch');

  rc := NetShutdown(cli, PAL_SHUT_RDWR);
  rc := NetClose(acc);
  rc := NetClose(cli);
  rc := NetClose(srv);

  { ---- UDP ---- }
  udpSrv := NetUdpBind(NetLoopback(0));
  if udpSrv < 0 then
  begin
    writeln('udp=bind-fail');
    Halt(1);
  end;
  rc := NetGetSockName(udpSrv, bound);
  udpCli := NetUdpBind(NetLoopback(0));
  if udpCli < 0 then
  begin
    writeln('udp=client-fail');
    Halt(1);
  end;

  n := NetUdpSendTo(udpCli, @msg[0], 5, NetLoopback(bound.Port));
  if n <> 5 then
  begin
    writeln('udp=send-fail');
    Halt(1);
  end;
  for i := 0 to 4 do buf[i] := 0;
  udpPeer.Host := 0;
  udpPeer.Port := 0;
  n := NetUdpRecvFrom(udpSrv, @buf[0], 5, udpPeer);
  if (n = 5) and Match and (udpPeer.Host = PAL_NET_IP_LOOPBACK) then
    writeln('udp=ok')
  else
    writeln('udp=bad');

  rc := NetClose(udpCli);
  rc := NetClose(udpSrv);
end.
