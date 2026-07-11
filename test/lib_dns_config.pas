program lib_dns_config;
{ Offline test for dns_config: dotted-quad IPv4 parsing and resolv.conf
  nameserver extraction (leading whitespace, comments, missing final newline,
  invalid lines). No network. }

uses dns_wire_core, dns_config;

var
  ip: LongWord;
  ip6: TDnsIpv6;
  ns: TDnsIpv4Array;
  search: TDnsSearchArray;
  count, searchCount, ndots, i: Integer;
  cfg, hosts, cand: string;

procedure Show(const tag: string; pass: Boolean);
begin
  if pass then writeln(tag, '=ok') else writeln(tag, '=bad');
end;

{ ip6 equals the 8 given 16-bit groups? }
function G6(const a: TDnsIpv6; g0, g1, g2, g3, g4, g5, g6v, g7: Integer): Boolean;
var
  g: array[0..7] of Integer;
  k: Integer;
begin
  g[0] := g0; g[1] := g1; g[2] := g2; g[3] := g3;
  g[4] := g4; g[5] := g5; g[6] := g6v; g[7] := g7;
  G6 := True;
  for k := 0 to 7 do
    if (Integer(a[k * 2]) shl 8) or Integer(a[k * 2 + 1]) <> g[k] then
    begin
      G6 := False;
      Exit;
    end;
end;

begin
  { ---- IPv4 parsing ---- }
  Show('ip-ok', DnsParseIpv4('8.8.8.8', 1, 7, ip) and (ip = LongWord($08080808)));
  Show('ip-val', DnsParseIpv4('93.184.216.34', 1, 13, ip) and (ip = LongWord($5DB8D822)));
  ip := 0;
  Show('ip-oversize', not DnsParseIpv4('256.0.0.1', 1, 9, ip));
  Show('ip-short', not DnsParseIpv4('1.2.3', 1, 5, ip));
  Show('ip-empty', not DnsParseIpv4('a.b.c.d', 1, 7, ip));

  { ---- resolv.conf ---- }
  cfg := '# a comment'#10 +
         'nameserver 8.8.8.8'#10 +
         '   nameserver 1.1.1.1'#10 +
         'search example.com lan'#10 +
         'options ndots:2'#10 +
         'nameserver 9.9.9.9   # trailing comment';   { no final newline }
  for i := 0 to DNS_MAX_IPS - 1 do ns[i] := 0;
  count := DnsParseResolvConf(cfg, ns, count);
  writeln('count=', count);
  Show('ns0', ns[0] = LongWord($08080808));
  Show('ns1', ns[1] = LongWord($01010101));
  Show('ns2', ns[2] = LongWord($09090909));

  { ---- /etc/hosts lookup ---- }
  hosts := '127.0.0.1   localhost'#10 +
           '192.168.1.10  myhost.local myhost'#10 +
           '# 10.0.0.1 commented.host'#10 +
           '93.184.216.34  example.com';
  ip := 0;
  Show('h-local', DnsLookupHosts(hosts, 'localhost', ip) and (ip = LongWord($7F000001)));
  ip := 0;
  Show('h-alias', DnsLookupHosts(hosts, 'myhost', ip) and (ip = LongWord($C0A8010A)));
  ip := 0;
  Show('h-ci', DnsLookupHosts(hosts, 'MYHOST.LOCAL', ip) and (ip = LongWord($C0A8010A)));
  ip := 0;
  Show('h-nofinalnl', DnsLookupHosts(hosts, 'example.com', ip) and (ip = LongWord($5DB8D822)));
  ip := 0;
  Show('h-comment', not DnsLookupHosts(hosts, 'commented.host', ip));
  ip := 0;
  Show('h-miss', not DnsLookupHosts(hosts, 'nope', ip));

  { ---- resolv.conf: search list + ndots ---- }
  count := DnsParseResolvConfEx(cfg, ns, count, search, searchCount, ndots);
  writeln('ex-count=', count);
  writeln('ex-search=', searchCount);
  Show('ex-s0', search[0] = 'example.com');
  Show('ex-s1', search[1] = 'lan');
  writeln('ex-ndots=', ndots);
  { `domain` replaces an earlier search list (last one wins) }
  count := DnsParseResolvConfEx('search a.example b.example'#10'domain only.example'#10,
    ns, count, search, searchCount, ndots);
  Show('ex-domain', (searchCount = 1) and (search[0] = 'only.example') and (ndots = 1));

  { ---- candidate ordering ---- }
  searchCount := 2;
  search[0] := 'example.com';
  search[1] := 'lan';
  ndots := 1;
  { bare single-label name (0 dots < ndots): search-qualified first, bare last }
  cand := '';
  Show('c-rel0', DnsQueryCandidate('myhost', search, searchCount, ndots, 0, cand) and (cand = 'myhost.example.com'));
  Show('c-rel1', DnsQueryCandidate('myhost', search, searchCount, ndots, 1, cand) and (cand = 'myhost.lan'));
  Show('c-rel2', DnsQueryCandidate('myhost', search, searchCount, ndots, 2, cand) and (cand = 'myhost'));
  Show('c-rel3', not DnsQueryCandidate('myhost', search, searchCount, ndots, 3, cand));
  { dotted name (>= ndots): as-is first, then qualified }
  Show('c-abs0', DnsQueryCandidate('a.b', search, searchCount, ndots, 0, cand) and (cand = 'a.b'));
  Show('c-abs1', DnsQueryCandidate('a.b', search, searchCount, ndots, 1, cand) and (cand = 'a.b.example.com'));
  { trailing dot = absolute, exactly one candidate }
  Show('c-root0', DnsQueryCandidate('a.b.', search, searchCount, ndots, 0, cand) and (cand = 'a.b'));
  Show('c-root1', not DnsQueryCandidate('a.b.', search, searchCount, ndots, 1, cand));

  { ---- IPv6 literal parsing ---- }
  Show('ip6-full', DnsParseIpv6('2001:0db8:0000:0000:0000:0000:0000:0001', 1, 39, ip6)
    and G6(ip6, $2001, $0DB8, 0, 0, 0, 0, 0, 1));
  Show('ip6-comp', DnsParseIpv6('2001:db8::1', 1, 11, ip6)
    and G6(ip6, $2001, $0DB8, 0, 0, 0, 0, 0, 1));
  Show('ip6-loop', DnsParseIpv6('::1', 1, 3, ip6) and G6(ip6, 0, 0, 0, 0, 0, 0, 0, 1));
  Show('ip6-any', DnsParseIpv6('::', 1, 2, ip6) and G6(ip6, 0, 0, 0, 0, 0, 0, 0, 0));
  Show('ip6-tail', DnsParseIpv6('1:2:3:4:5:6::', 1, 13, ip6) and G6(ip6, 1, 2, 3, 4, 5, 6, 0, 0));
  Show('ip6-v4', DnsParseIpv6('::ffff:192.168.1.10', 1, 19, ip6)
    and G6(ip6, 0, 0, 0, 0, 0, $FFFF, $C0A8, $010A));
  Show('ip6-caps', DnsParseIpv6('FE80::AbCd', 1, 10, ip6)
    and G6(ip6, $FE80, 0, 0, 0, 0, 0, 0, $ABCD));
  Show('ip6-badgap', not DnsParseIpv6('1::2::3', 1, 7, ip6));
  Show('ip6-badlen', not DnsParseIpv6('1:2:3:4:5:6:7', 1, 13, ip6));
  Show('ip6-badlong', not DnsParseIpv6('1:2:3:4:5:6:7:8:9', 1, 17, ip6));
  Show('ip6-badgrp', not DnsParseIpv6('12345::1', 1, 8, ip6));
  Show('ip6-badzone', not DnsParseIpv6('fe80::1%eth0', 1, 12, ip6));
  Show('ip6-badcolon', not DnsParseIpv6('1:2:3:4:5:6:7:', 1, 14, ip6));
  Show('ip6-gapfull', not DnsParseIpv6('1:2:3:4:5:6:7:8::', 1, 17, ip6));
  Show('ip6-notv4', not DnsParseIpv6('1.2.3.4', 1, 7, ip6));

  { ---- /etc/hosts IPv6 lines ---- }
  hosts := '127.0.0.1 localhost'#10 +
           '::1 localhost ip6-localhost'#10 +
           '2001:db8::42 six.example alias6'#10 +
           '192.168.1.10 myhost myhost.local';
  Show('h6-loop', DnsLookupHosts6(hosts, 'ip6-localhost', ip6) and G6(ip6, 0, 0, 0, 0, 0, 0, 0, 1));
  Show('h6-host', DnsLookupHosts6(hosts, 'SIX.example', ip6)
    and G6(ip6, $2001, $0DB8, 0, 0, 0, 0, 0, $42));
  Show('h6-skip4', not DnsLookupHosts6(hosts, 'myhost', ip6));
  Show('h6-miss', not DnsLookupHosts6(hosts, 'nope', ip6));

  { ---- /etc/services lookup ---- }
  hosts := '# comment line'#10 +
           'ftp 21/tcp'#10 +
           'ssh             22/tcp'#10 +
           'domain 53/tcp nameserver'#10 +
           'domain 53/udp nameserver'#10 +
           'http 80/tcp www www-http # WorldWideWeb'#10 +
           'https 443/tcp';   { no final newline }
  i := 0;
  Show('sv-basic', DnsLookupServices(hosts, 'ssh', 'tcp', i) and (i = 22));
  Show('sv-ci', DnsLookupServices(hosts, 'HTTP', 'tcp', i) and (i = 80));
  Show('sv-alias', DnsLookupServices(hosts, 'www', 'tcp', i) and (i = 80));
  Show('sv-anyproto', DnsLookupServices(hosts, 'domain', '', i) and (i = 53));
  Show('sv-udp', DnsLookupServices(hosts, 'domain', 'udp', i) and (i = 53));
  Show('sv-nofinalnl', DnsLookupServices(hosts, 'https', 'tcp', i) and (i = 443));
  Show('sv-protomiss', not DnsLookupServices(hosts, 'ssh', 'udp', i));
  Show('sv-miss', not DnsLookupServices(hosts, 'gopher', 'tcp', i));
  Show('sv-comment-alias', not DnsLookupServices(hosts, 'WorldWideWeb', 'tcp', i));
end.
