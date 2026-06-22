program lib_dns_config;
{ Offline test for dns_config: dotted-quad IPv4 parsing and resolv.conf
  nameserver extraction (leading whitespace, comments, missing final newline,
  invalid lines). No network. }

uses dns_wire_core, dns_config;

var
  ip: LongWord;
  ns: TDnsIpv4Array;
  count, i: Integer;
  cfg: string;

procedure Show(const tag: string; pass: Boolean);
begin
  if pass then writeln(tag, '=ok') else writeln(tag, '=bad');
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
end.
