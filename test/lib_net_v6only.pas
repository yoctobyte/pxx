{ IPV6_V6ONLY on a `::` listener — the escape hatch half of
  decide-ipv6-dualstack-and-aaaa-ordering (user, 2026-08-01).

  The DECIDED DEFAULT is "do nothing": a `::` listener inherits the host's
  /proc/sys/net/ipv6/bindv6only, exactly as a plain BSD `bind()` does. This
  test does not assert what that inherited value IS — that is the host's
  business and the whole point of the decision — only that a caller who asks
  explicitly gets what they asked for either way.

  The assertions are behavioural, not "setsockopt returned 0": bind `::`, then
  try to reach it from an IPv4 client on 127.0.0.1.

    v6Only = ON   -> the v4 client must be REFUSED
    v6Only = OFF  -> the v4 client must CONNECT (arriving v4-mapped)

  That is the only check that distinguishes the option actually taking effect
  from the call being accepted and ignored.

  WHICH HALF CATCHES A REGRESSION DEPENDS ON THE HOST, so both are here.
  Verified by rebuilding against an RTL with the setsockopt disabled: on a box
  with bindv6only=0 (dual-stack inherited) only `strict_refuses_v4` fails,
  because the OFF case is what the host was going to do anyway. On a
  bindv6only=1 host it is the other way round. Neither assertion alone is
  sufficient on every machine; together one of them always is.

  SKIPs where IPv6 is unavailable in the kernel, which is a host configuration
  and not a code defect. }
program lib_net_v6only;
uses net, platform, sysutils;

var fails: Integer;

procedure Chk(const what: AnsiString; got, want: Boolean);
begin
  if got = want then WriteLn(what, '=ok')
  else begin WriteLn(what, ' FAIL got=', got, ' want=', want); fails := fails + 1; end;
end;

{ Listen on :: with the given v6Only, then attempt an IPv4 loopback connect to
  the port it landed on. True when the v4 client got through. }
function V4ReachesV6Listener(v6Only: Integer; var listenOk: Boolean): Boolean;
var listener, client, rc: Integer; bound: TNetAddress;
begin
  V4ReachesV6Listener := False;
  listenOk := False;
  listener := NetTcpListen(NetAny6(0), 4, v6Only);
  if listener < 0 then Exit;
  listenOk := True;
  bound := NetAddress(0, 0);
  rc := NetGetSockName(listener, bound);
  if (rc < 0) or (bound.Port <= 0) then
  begin
    NetClose(listener);
    listenOk := False;
    Exit;
  end;
  { a short timeout: a refused connect returns at once, and this must not hang
    the suite if the kernel behaves unexpectedly }
  client := NetTcpConnectTimeout(NetLoopback(bound.Port), 2000);
  if client >= 0 then
  begin
    V4ReachesV6Listener := True;
    NetClose(client);
  end;
  NetClose(listener);
end;

var
  probe: Integer;
  reached, listenOk: Boolean;
begin
  fails := 0;

  { is IPv6 usable at all here? }
  probe := PalSocket(PAL_NET_AF_INET6, PAL_NET_SOCK_STREAM, 0);
  if probe < 0 then
  begin
    WriteLn('v6only_skip=ok (no AF_INET6 on this host)');
    WriteLn('NETV6ONLY OK');
    Halt(0);
  end;
  PalSocketClose(probe);

  { explicit strict v6: an IPv4 client must NOT get through }
  reached := V4ReachesV6Listener(NET_V6ONLY_ON, listenOk);
  Chk('strict_listen_ok', listenOk, True);
  Chk('strict_refuses_v4', reached, False);

  { explicit dual-stack: an IPv4 client MUST get through }
  reached := V4ReachesV6Listener(NET_V6ONLY_OFF, listenOk);
  Chk('dual_listen_ok', listenOk, True);
  Chk('dual_accepts_v4', reached, True);

  { the default must still bind and listen — its v4 reachability is the host's
    inherited setting and is deliberately NOT asserted }
  reached := V4ReachesV6Listener(NET_V6ONLY_INHERIT, listenOk);
  Chk('default_listen_ok', listenOk, True);

  { and the v4 path is untouched by any of this }
  reached := False;
  probe := NetTcpListen(NetLoopback(0), 4);
  Chk('v4_listen_unaffected', probe >= 0, True);
  if probe >= 0 then NetClose(probe);

  if fails = 0 then WriteLn('NETV6ONLY OK')
  else WriteLn('NETV6ONLY FAILED ', fails);
end.
