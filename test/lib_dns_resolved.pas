{ The systemd-resolved DNS backend (feature-dns-backends-selection).

  Built WITHOUT -dPXX_DNS_RESOLVED this exercises nothing but the facade, which
  is itself worth asserting: adding a backend must not disturb the default.
  Built WITH it, the resolved path is compared against the wire path.

  NO NETWORK. Every name here is `localhost`, which /etc/hosts answers on the
  wire side and resolved synthesizes on its own — so this cannot fail because a
  test box is offline, and it cannot pass because some public resolver happened
  to answer.

  SKIPS rather than fails where systemd-resolved is absent. That is not
  politeness: the backend's contract is that a host without the Varlink socket
  falls back to the wire path, so "no resolved here" is a supported
  configuration and the fallback assertion below is what covers it. }
program lib_dns_resolved;
uses dns, dns_wire_core, sysutils
{$ifdef PXX_DNS_RESOLVED}
     , dns_resolved
{$endif}
     ;

var fails: Integer;

procedure Chk(const what: AnsiString; got, want: Boolean);
begin
  if got = want then WriteLn(what, '=ok')
  else begin WriteLn(what, ' FAIL got=', got, ' want=', want); fails := fails + 1; end;
end;

var
  ips, ips2: TDnsIpv4Array;
  ip6: TDnsIpv6Array;
  n, n2, rc: Integer;
{$ifdef PXX_DNS_RESOLVED}
  i, same: Integer;
{$endif}
begin
  fails := 0;

  { An IP literal must resolve to itself WITHOUT network, and must do so
    identically on every backend. dns_wire used to answer NXDOMAIN here while
    dns_resolved, dns_libc and getent all returned the address, so the facade's
    answer changed with the selected backend — the one thing the selection
    design promises it will not do. Asserted in this file (rather than a
    backend-specific one) precisely because it is a CROSS-backend contract:
    lib-test builds this program with and without the define. }
  rc := DnsResolveHost('127.0.0.1', ips, n);
  Chk('literal_v4_rc', rc = 0, True);
  Chk('literal_v4_value', (n = 1) and (ips[0] = $7F000001), True);
  rc := DnsResolveHost6('::1', ip6, n);
  Chk('literal_v6_rc', rc = 0, True);
  Chk('literal_v6_value', (n = 1) and (ip6[0][0] = 0) and (ip6[0][15] = 1), True);

  { the facade still answers, whichever backend is compiled in }
  rc := DnsResolveHost('localhost', ips, n);
  Chk('facade_v4_rc', rc = 0, True);
  Chk('facade_v4_any', n > 0, True);
  Chk('facade_v4_loopback', (n > 0) and (ips[0] = $7F000001), True);

  rc := DnsResolveHost6('localhost', ip6, n);
  Chk('facade_v6_rc', rc = 0, True);
  { ::1 is fifteen zero bytes then 1 }
  Chk('facade_v6_loopback',
      (n > 0) and (ip6[0][0] = 0) and (ip6[0][15] = 1), True);

{$ifdef PXX_DNS_RESOLVED}
  if not DnsResolvedAvailable then
    WriteLn('resolved_skip=ok (no systemd-resolved on this host; ',
            'the facade answers above came from the wire fallback, which is ',
            'the contract)')
  else
  begin
    { the backend answers directly }
    rc := DnsResolvedResolveHost('localhost', ips2, n2);
    Chk('resolved_v4_rc', rc = 0, True);
    Chk('resolved_v4_loopback', (n2 > 0) and (ips2[0] = $7F000001), True);

    { and agrees with the wire path on the same name — the differential check }
    rc := DnsResolveHost('localhost', ips, n);
    same := 0;
    for i := 0 to n - 1 do
      if (n2 > 0) and (ips[i] = ips2[0]) then same := same + 1;
    Chk('resolved_agrees_with_wire', same > 0, True);

    { a name that cannot exist: resolved reports the DNS RCODE, and NXDOMAIN
      is 3. This is the mapping that lets the facade treat a resolved failure
      exactly like a wire failure. }
    rc := DnsResolvedResolveHost('nonexistent-zzz-qqq.invalid', ips2, n2);
    Chk('resolved_nxdomain_rcode', rc = 3, True);
    Chk('resolved_nxdomain_empty', n2 = 0, True);
  end;
{$endif}

  if fails = 0 then WriteLn('DNSRESOLVED OK')
  else WriteLn('DNSRESOLVED FAILED ', fails);
end.
