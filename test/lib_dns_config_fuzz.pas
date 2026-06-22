program lib_dns_config_fuzz;
{ Adversarial test for dns_config. Hostile IPv4 strings, a resolv.conf with more
  nameservers than the array holds (must cap, not overrun), and malformed hosts
  lines (hostname in the address column, IPv6 lines) — all must stay safe. }

uses dns_wire_core, dns_config;

var
  ip: LongWord;
  ns: TDnsIpv4Array;
  count, i: Integer;
  cfg, hosts: string;

procedure Show(const tag: string; pass: Boolean);
begin
  if pass then writeln(tag, '=ok') else writeln(tag, '=bad');
end;

begin
  { ---- IPv4 hostile inputs ---- }
  Show('all-255', not DnsParseIpv4('256.256.256.256', 1, 15, ip));
  Show('dots-only', not DnsParseIpv4('...', 1, 3, ip));
  Show('trailing-dot', not DnsParseIpv4('1.2.3.4.', 1, 8, ip));
  Show('trailing-sp', not DnsParseIpv4('1.2.3.4 ', 1, 8, ip));
  Show('five-octets', not DnsParseIpv4('1.2.3.4.5', 1, 9, ip));
  Show('huge-octet', not DnsParseIpv4('99999.1.1.1', 1, 11, ip));
  Show('valid-max', DnsParseIpv4('255.255.255.255', 1, 15, ip) and (ip = LongWord($FFFFFFFF)));

  { ---- resolv.conf with 20 nameservers (array holds DNS_MAX_IPS=16) ---- }
  cfg := '';
  for i := 1 to 20 do
    cfg := cfg + 'nameserver 10.0.0.' + Chr(Ord('0') + (i mod 10)) + #10;
  count := 999;
  count := DnsParseResolvConf(cfg, ns, count);
  Show('ns-cap', count = DNS_MAX_IPS);

  { ---- malformed hosts ---- }
  hosts := 'localhost 127.0.0.1'#10 +     { hostname in the address column }
           '::1 ip6host'#10 +             { IPv6 line }
           '10.0.0.5 realhost';
  { a lookup that hits the bogus first line's hostname column must not match }
  Show('bogus-nomatch', not DnsLookupHosts(hosts, '127.0.0.1', ip));
  { IPv6 host line is skipped (A-only) }
  Show('ip6-skip', not DnsLookupHosts(hosts, 'ip6host', ip));
  { the good line still resolves }
  Show('good-line', DnsLookupHosts(hosts, 'realhost', ip) and (ip = LongWord($0A000005)));

  writeln('done');
end.
