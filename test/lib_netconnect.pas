{ Connect-by-name, and the A-first ordering policy
  (feature-net-a-first-connect-by-name, decided 2026-08-01).

  THE ORDER IS THE POINT, and "it connected" passes under either ordering — so
  every ordering assertion here checks `used.Family`, not merely success.

  `localhost` is the whole test bed: it has both an A (127.0.0.1) and an AAAA
  (::1) record in /etc/hosts on every sane system, which is exactly the
  both-families case the decision is about, and it needs no network.

  Where IPv6 is unavailable the ordering assertions still hold (v4 is tried
  first regardless); only the AAAA-fallback case is skipped, since it cannot be
  distinguished from "v6 does not work here". }
program lib_netconnect;
uses netconnect, net, platform, dns, dns_wire_core, sysutils, platform_types;

var fails: Integer;

procedure Chk(const what: AnsiString; got, want: Boolean);
begin
  if got = want then WriteLn(what, '=ok')
  else begin WriteLn(what, ' FAIL got=', got, ' want=', want); fails := fails + 1; end;
end;

{ A listener on the given family, returning the port it landed on. }
function Listen(v6: Boolean; var port: Integer): Integer;
var s, rc: Integer; bound: TNetAddress;
begin
  port := 0;
  { STRICT v6, not the inherited default. On a bindv6only=0 host a `::` listener
    is dual-stack and happily accepts the IPv4 attempt, so the A-first try would
    SUCCEED and the fallback would never run — the test would pass while proving
    nothing. Pinning V6ONLY is what makes "v4 must fail here" true. }
  if v6 then s := NetTcpListen(NetAny6(0), 4, NET_V6ONLY_ON)
  else s := NetTcpListen(NetLoopback(0), 4);
  if s < 0 then begin Listen := s; Exit; end;
  bound := NetAddress(0, 0);
  rc := NetGetSockName(s, bound);
  if (rc < 0) or (bound.Port <= 0) then
  begin
    NetClose(s);
    Listen := -1;
    Exit;
  end;
  port := bound.Port;
  Listen := s;
end;

var
  listener, sock, port, probe, n: Integer;
  used: TNetAddress;
  hasV6: Boolean;
  ip6: TDnsIpv6Array;
begin
  fails := 0;

  probe := PalSocket(PAL_NET_AF_INET6, PAL_NET_SOCK_STREAM, 0);
  hasV6 := probe >= 0;
  if hasV6 then PalSocketClose(probe);

  { ---- an IP literal connects without any resolution ---- }
  listener := Listen(False, port);
  Chk('v4_listener', listener >= 0, True);
  if listener >= 0 then
  begin
    sock := NetConnectHostEx('127.0.0.1', port, 2000, used);
    Chk('literal_connects', sock >= 0, True);
    Chk('literal_family_v4', used.Family = PAL_NET_AF_INET, True);
    if sock >= 0 then NetClose(sock);
    NetClose(listener);
  end;

  { ---- A-FIRST: localhost has both families, and a v4 listener must win ----
    This is the decided policy's observable consequence. }
  listener := Listen(False, port);
  if listener >= 0 then
  begin
    sock := NetConnectHostEx('localhost', port, 2000, used);
    Chk('name_connects', sock >= 0, True);
    Chk('name_prefers_v4', used.Family = PAL_NET_AF_INET, True);
    if sock >= 0 then NetClose(sock);
    NetClose(listener);
  end;

  { ---- AAAA FALLBACK: with only a v6 listener, the v4 attempt must fail and
    the v6 one must be tried and win. Proves the fallback runs at all — without
    it this case returns an error rather than connecting. ---- }
  if hasV6 then
  begin
    { does localhost actually have an AAAA here? if not, nothing to fall back to }
    n := 0;
    if (DnsResolveHost6('localhost', ip6, n) = 0) and (n > 0) then
    begin
      listener := Listen(True, port);
      if listener >= 0 then
      begin
        sock := NetConnectHostEx('localhost', port, 2000, used);
        Chk('fallback_connects', sock >= 0, True);
        Chk('fallback_family_v6', used.Family = PAL_NET_AF_INET6, True);
        if sock >= 0 then NetClose(sock);
        NetClose(listener);
      end;
    end
    else
      WriteLn('fallback_skip=ok (localhost has no AAAA on this host)');
  end
  else
    WriteLn('fallback_skip=ok (no AF_INET6 on this host)');

  { ---- a name that cannot resolve fails cleanly rather than hanging ---- }
  sock := NetConnectHostEx('nonexistent-zzz-qqq.invalid', 9, 2000, used);
  Chk('noresolve_fails', sock < 0, True);
  Chk('noresolve_code', sock = NETCONNECT_ERR_NORESOLVE, True);

  { ---- resolved but refused reports the real errno, not a generic failure ----
    port 1 on loopback has nothing listening. }
  sock := NetConnectHostEx('127.0.0.1', 1, 2000, used);
  Chk('refused_fails', sock < 0, True);
  Chk('refused_not_noresolve', sock <> NETCONNECT_ERR_NORESOLVE, True);

  if fails = 0 then WriteLn('NETCONNECT OK')
  else WriteLn('NETCONNECT FAILED ', fails);
end.
