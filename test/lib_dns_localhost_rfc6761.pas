{ RFC 6761 section 6.3: `localhost` always means loopback, and must never be
  sent to a nameserver.

  Before the fix this file gates, our resolver had no localhost special-case at
  all. On a stock Debian/Ubuntu box `/etc/hosts` carries `127.0.0.1 localhost`
  but spells the v6 loopback `ip6-localhost`, so the A lookup hit files and
  looked fine while the AAAA lookup MISSED files, fell through to the wire, and
  queried `localhost.<search>` against the configured nameserver — meaning a
  wildcard, misconfigured or hostile resolver could answer `localhost` with a
  non-loopback address. The v4 path was never correct either, only masked by a
  hosts line almost every box happens to ship.

  THE PREDICATE ROWS ARE THE GATE; THE RESOLUTION ROWS ARE ONLY SMOKE. That
  distinction was learned the hard way: the first version of this file asserted
  only end-to-end resolution, and reverting the fix DID NOT FAIL IT. The reason
  is that this box's stub resolver (systemd-resolved) is itself RFC 6761
  compliant and synthesises the whole localhost subtree, so the broken code path
  returned the right answer — it just emitted 20 DNS queries to get it, against
  0 with the fix. On such a box the observable difference is TRAFFIC, not the
  value, and a value assertion therefore tests the resolver rather than us.

  So `DnsIsLocalhostName` is exported and asserted directly. It is where the
  logic that can regress lives — case folding, the optional root dot, and the
  label boundary that must stop `notlocalhost` from matching — and it is
  deterministic, hermetic, and independent of whatever the local resolver does.
  The resolution rows are kept because they are still worth having and cost
  nothing, but they are documented as smoke, not as the regression gate.

  Every row here is hermetic: no packet to port 53 (verified with strace during
  development; a suite cannot assert the absence of traffic from inside). }
program lib_dns_localhost_rfc6761;

uses dns;

var
  ip4: array[0..7] of LongWord;
  ip6: array[0..7] of array[0..15] of Byte;
  n, rc, i: Integer;
  allok: Boolean;

procedure ChkV4(const nm: string);
var j: Integer;
begin
  rc := DnsResolveHost(nm, ip4, n);
  if (rc = 0) and (n > 0) and (ip4[0] = $7F000001) then
    WriteLn('v4 ', nm, '=ok')
  else
  begin
    WriteLn('v4 ', nm, '=FAIL rc=', rc, ' n=', n);
    allok := False;
  end;
end;

procedure ChkV6(const nm: string);
var j: Integer; ok: Boolean;
begin
  rc := DnsResolveHost6(nm, ip6, n);
  ok := (rc = 0) and (n > 0);
  if ok then
  begin
    for j := 0 to 14 do if ip6[0][j] <> 0 then ok := False;
    if ip6[0][15] <> 1 then ok := False;
  end;
  if ok then WriteLn('v6 ', nm, '=ok')
  else
  begin
    WriteLn('v6 ', nm, '=FAIL rc=', rc, ' n=', n);
    allok := False;
  end;
end;

procedure ChkPred(const nm: string; want: Boolean);
begin
  if DnsIsLocalhostName(nm) = want then
    WriteLn('pred ', nm, '=ok')
  else
  begin
    WriteLn('pred ', nm, '=FAIL wanted ', want);
    allok := False;
  end;
end;

begin
  allok := True;

  { --- the gate: the predicate, asserted directly --- }
  ChkPred('localhost', True);
  ChkPred('LocalHost', True);
  ChkPred('LOCALHOST.', True);
  ChkPred('foo.localhost', True);
  ChkPred('a.b.localhost.', True);
  { the label boundary: these must NOT match, and end-to-end resolution cannot
    check them without letting the name reach the wire }
  ChkPred('notlocalhost', False);
  ChkPred('xlocalhost', False);
  ChkPred('localhost.com', False);
  ChkPred('localhos', False);
  ChkPred('', False);

  { --- smoke: resolution still answers loopback (passes with or without the
        special-case on a box whose own resolver is compliant) --- }
  ChkV4('localhost');
  ChkV6('localhost');

  { case-insensitive: DNS names compare without regard to case }
  ChkV4('LocalHost');
  ChkV6('LOCALHOST');

  { the trailing root dot is optional }
  ChkV4('localhost.');
  ChkV6('localhost.');

  { 6.3 covers the subdomains too }
  ChkV4('foo.localhost');
  ChkV6('foo.bar.localhost');

  if allok then WriteLn('DNSLOCALHOST OK')
  else begin WriteLn('DNSLOCALHOST FAIL'); Halt(1); end;
end.
