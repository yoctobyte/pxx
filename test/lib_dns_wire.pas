program lib_dns_wire;
{ Offline test for dns_wire_core: encode an A query and check the RFC 1035 wire
  bytes, then parse a canned 2-answer response (with a compressed answer name)
  and check the extracted IPv4 addresses. No network. }

uses dns_wire_core;

var
  q: array[0..511] of Byte;
  resp: array[0..60] of Byte;
  ips: TDnsIpv4Array;
  qlen, count, outId, rc, i: Integer;

procedure Show(const tag: string; pass: Boolean);
begin
  if pass then writeln(tag, '=ok') else writeln(tag, '=bad');
end;

begin
  { ---- encode: A query for example.com, id 0x1234 ---- }
  qlen := DnsBuildQueryA('example.com', $1234, @q[0]);
  writeln('qlen=', qlen);
  Show('qhdr', (q[0] = $12) and (q[1] = $34) and (q[2] = $01) and
    (q[3] = $00) and (q[4] = $00) and (q[5] = $01));
  Show('qname', (q[12] = 7) and (q[13] = Ord('e')) and (q[20] = 3) and
    (q[21] = Ord('c')) and (q[24] = 0) and (q[26] = 1) and (q[28] = 1));

  { ---- decode: canned response for example.com, two A records ---- }
  for i := 0 to 60 do resp[i] := 0;
  { header: id 0x1234, flags 0x8180, qd=1, an=2 }
  resp[0] := $12; resp[1] := $34; resp[2] := $81; resp[3] := $80;
  resp[5] := 1; resp[7] := 2;
  { question: 07 example 03 com 00, qtype A, qclass IN }
  resp[12] := 7;
  resp[13] := Ord('e'); resp[14] := Ord('x'); resp[15] := Ord('a');
  resp[16] := Ord('m'); resp[17] := Ord('p'); resp[18] := Ord('l');
  resp[19] := Ord('e');
  resp[20] := 3; resp[21] := Ord('c'); resp[22] := Ord('o'); resp[23] := Ord('m');
  resp[24] := 0;
  resp[26] := 1; resp[28] := 1;
  { answer 1: name ptr -> 12, A/IN, ttl 60, rdlen 4, 93.184.216.34 }
  resp[29] := $C0; resp[30] := $0C;
  resp[32] := 1; resp[34] := 1;
  resp[38] := 60;
  resp[40] := 4;
  resp[41] := 93; resp[42] := 184; resp[43] := 216; resp[44] := 34;
  { answer 2: name ptr -> 12, A/IN, ttl 60, rdlen 4, 93.184.216.35 }
  resp[45] := $C0; resp[46] := $0C;
  resp[48] := 1; resp[50] := 1;
  resp[54] := 60;
  resp[56] := 4;
  resp[57] := 93; resp[58] := 184; resp[59] := 216; resp[60] := 35;

  for i := 0 to DNS_MAX_IPS - 1 do ips[i] := 0;
  rc := DnsParseResponseA(@resp[0], 61, ips, count, outId);
  writeln('rcode=', rc);
  Show('id', outId = $1234);
  writeln('count=', count);
  Show('ip0', ips[0] = LongWord($5DB8D822));
  Show('ip1', ips[1] = LongWord($5DB8D823));
end.
