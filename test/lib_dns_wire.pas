program lib_dns_wire;
{ Offline test for dns_wire_core: encode A/AAAA queries and check the RFC 1035
  wire bytes, parse canned A and AAAA responses (with compressed answer names),
  and extract a compressed CNAME target. No network. }

uses dns_wire_core;

var
  q: array[0..511] of Byte;
  resp: array[0..60] of Byte;
  r6: array[0..56] of Byte;
  rc6: array[0..50] of Byte;
  soa: array[0..63] of Byte;
  ips: TDnsIpv4Array;
  ips6: TDnsIpv6Array;
  cname: string;
  qlen, count, outId, rc, i: Integer;

procedure Show(const tag: string; pass: Boolean);
begin
  if pass then writeln(tag, '=ok') else writeln(tag, '=bad');
end;

begin
  { ---- encode: A query for example.com, id 0x1234 ---- }
  qlen := DnsBuildQueryA('example.com', $1234, @q[0], 512);
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
  { answer 2: name ptr -> 12, A/IN, ttl 30, rdlen 4, 93.184.216.35 }
  resp[45] := $C0; resp[46] := $0C;
  resp[48] := 1; resp[50] := 1;
  resp[54] := 30;
  resp[56] := 4;
  resp[57] := 93; resp[58] := 184; resp[59] := 216; resp[60] := 35;

  for i := 0 to DNS_MAX_IPS - 1 do ips[i] := 0;
  rc := DnsParseResponseA(@resp[0], 61, ips, count, outId);
  writeln('rcode=', rc);
  Show('id', outId = $1234);
  writeln('count=', count);
  Show('ip0', ips[0] = LongWord($5DB8D822));
  Show('ip1', ips[1] = LongWord($5DB8D823));
  { min TTL across the two answers = min(60, 30) = 30 }
  Show('minttl', DnsAnswerMinTTL(@resp[0], 61) = 30);

  { ---- encode: AAAA query carries qtype 28 ---- }
  qlen := DnsBuildQuery('example.com', DNS_TYPE_AAAA, $4321, @q[0], 512);
  Show('q6type', (qlen = 29) and (q[25] = 0) and (q[26] = 28));

  { ---- decode: canned AAAA response, one answer (2001:db8::1) ---- }
  for i := 0 to 56 do r6[i] := 0;
  r6[0] := $43; r6[1] := $21; r6[2] := $81; r6[3] := $80;
  r6[5] := 1; r6[7] := 1;
  { question: 07 example 03 com 00, qtype AAAA, qclass IN }
  r6[12] := 7;
  r6[13] := Ord('e'); r6[14] := Ord('x'); r6[15] := Ord('a');
  r6[16] := Ord('m'); r6[17] := Ord('p'); r6[18] := Ord('l'); r6[19] := Ord('e');
  r6[20] := 3; r6[21] := Ord('c'); r6[22] := Ord('o'); r6[23] := Ord('m');
  r6[24] := 0; r6[26] := 28; r6[28] := 1;
  { answer: name ptr -> 12, AAAA/IN, ttl 60, rdlen 16 }
  r6[29] := $C0; r6[30] := $0C;
  r6[32] := 28; r6[34] := 1;
  r6[38] := 60; r6[40] := 16;
  r6[41] := $20; r6[42] := $01; r6[43] := $0D; r6[44] := $B8;
  r6[56] := 1;
  rc := DnsParseResponseAAAA(@r6[0], 57, ips6, count, outId);
  writeln('rcode6=', rc);
  Show('id6', outId = $4321);
  writeln('count6=', count);
  Show('ip6', (ips6[0][0] = $20) and (ips6[0][1] = $01) and (ips6[0][2] = $0D) and
    (ips6[0][3] = $B8) and (ips6[0][4] = 0) and (ips6[0][15] = 1));

  { ---- CNAME target extraction, compressed tail ---- }
  { question: www.alias.test A/IN; answer: CNAME rdata "real" + ptr to "test",
    so the decoded target must be real.test (pointer followed correctly). }
  for i := 0 to 50 do rc6[i] := 0;
  rc6[0] := $BE; rc6[1] := $EF; rc6[2] := $81; rc6[3] := $80;
  rc6[5] := 1; rc6[7] := 1;
  rc6[12] := 3; rc6[13] := Ord('w'); rc6[14] := Ord('w'); rc6[15] := Ord('w');
  rc6[16] := 5; rc6[17] := Ord('a'); rc6[18] := Ord('l'); rc6[19] := Ord('i');
  rc6[20] := Ord('a'); rc6[21] := Ord('s');
  rc6[22] := 4; rc6[23] := Ord('t'); rc6[24] := Ord('e'); rc6[25] := Ord('s'); rc6[26] := Ord('t');
  rc6[27] := 0; rc6[29] := 1; rc6[31] := 1;
  rc6[32] := $C0; rc6[33] := $0C;                 { answer name -> question }
  rc6[35] := DNS_TYPE_CNAME; rc6[37] := 1;        { type CNAME, class IN }
  rc6[43] := 7;                                    { rdlen }
  rc6[44] := 4; rc6[45] := Ord('r'); rc6[46] := Ord('e');
  rc6[47] := Ord('a'); rc6[48] := Ord('l');
  rc6[49] := $C0; rc6[50] := 22;                   { ptr -> "test" label }
  cname := '';
  Show('cname', DnsExtractCname(@rc6[0], 51, cname) and (cname = 'real.test'));

  { ---- negative TTL: NXDOMAIN with an SOA in the authority section ----
    header: id, flags rcode=3, qd=1 an=0 ns=1 ar=0; question 'x'; authority SOA
    with record TTL=500 and MINIMUM=200 => negative TTL = min(500,200) = 200. }
  for i := 0 to 63 do soa[i] := 0;
  soa[0] := $AB; soa[1] := $CD;
  soa[2] := $81; soa[3] := $83;      { QR RD RA, rcode 3 (NXDOMAIN) }
  soa[5] := 1;                        { qd=1 }
  soa[9] := 1;                        { ns=1 (authority) }
  { question: 01 'x' 00, qtype A, qclass IN }
  soa[12] := 1; soa[13] := Ord('x'); soa[14] := 0;
  soa[16] := 1; soa[18] := 1;         { qtype A (15-16), qclass IN (17-18) }
  { authority RR at pos 19 }
  soa[19] := $C0; soa[20] := $0C;     { name -> question }
  soa[22] := DNS_TYPE_SOA;            { type SOA (21-22) }
  soa[24] := 1;                       { class IN (23-24) }
  { TTL (25-28) = 500 = 0x000001F4 }
  soa[27] := 1; soa[28] := $F4;
  soa[30] := 22;                      { rdlen (29-30) = 22 }
  { rdata at 31: mname root(31)=0, rname root(32)=0, then 5 x u32 (33..52) }
  { minimum is the 5th u32 -> bytes 49..52 = 200 = 0x000000C8 }
  soa[52] := 200;
  Show('negttl', DnsNegativeTTL(@soa[0], 53) = 200);
  Show('negttl-none', DnsNegativeTTL(@resp[0], 61) = -1);   { no SOA in the A resp }
end.
