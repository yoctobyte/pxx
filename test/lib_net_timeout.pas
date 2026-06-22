program lib_net_timeout;
{ Exercises NetTcpConnectTimeout: the non-blocking connect -> poll-writable ->
  SO_ERROR sequence (PalGetSockError / PalPoll). On loopback the success and
  refused outcomes are deterministic; the pure-timeout path can't be triggered
  reliably without an unreachable network, so it is covered by logic only. }

uses net, platform;

var
  srv, cli: TNetSocket;
  bound: TNetAddress;
  rc: Integer;

begin
  { Success: a live listener accepts the connect. }
  srv := NetTcpListen(NetLoopback(0), 4);
  if srv < 0 then
  begin
    writeln('listen-fail');
    Halt(1);
  end;
  rc := NetGetSockName(srv, bound);
  cli := NetTcpConnectTimeout(NetLoopback(bound.Port), 1000);
  if cli >= 0 then
    writeln('connect=ok')
  else
    writeln('connect=fail');
  rc := NetClose(cli);
  rc := NetClose(srv);

  { Refused: nothing listens on port 1, so the connect fails (RST/ECONNREFUSED)
    rather than hanging or succeeding. }
  cli := NetTcpConnectTimeout(NetLoopback(1), 1000);
  if cli < 0 then
    writeln('refused=ok')
  else
  begin
    writeln('refused=bad');
    NetClose(cli);
  end;
end.
