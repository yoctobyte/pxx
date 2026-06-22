program lib_dns_parsefuzz;
{ Adversarial parser test: feed DnsParseResponseA malformed / hostile packets
  (exact-sized buffers, so any out-of-bounds read would be caught) and require a
  sane negative error or a safe bounded result — never a crash, hang, or buffer
  overrun. The answer-count-cap case checks the ips array is not overflowed. }

uses dns_wire_core;

var
  b: array[0..255] of Byte;
  ips: TDnsIpv4Array;
  count, outId, rc, i, p: Integer;

procedure Show(const tag: string; pass: Boolean);
begin
  if pass then writeln(tag, '=ok') else writeln(tag, '=bad');
end;

procedure Clear;
var k: Integer;
begin
  for k := 0 to 255 do b[k] := 0;
  count := 0; outId := 0;
end;

begin
  { 1: empty packet. }
  Clear;
  rc := DnsParseResponseA(@b[0], 0, ips, count, outId);
  Show('empty', rc < 0);

  { 2: shorter than a header. }
  Clear;
  rc := DnsParseResponseA(@b[0], 11, ips, count, outId);
  Show('short-header', rc < 0);

  { 3: qd=1, a question name that never terminates (labels run off the end). }
  Clear;
  b[5] := 1;                 { qd=1 }
  for i := 12 to 60 do b[i] := 1;   { label-len 1, no zero terminator }
  rc := DnsParseResponseA(@b[0], 61, ips, count, outId);
  Show('runaway-name', rc < 0);

  { 4: an=1, answer name is a pointer but the RR is truncated before type. }
  Clear;
  b[7] := 1;                 { an=1 }
  b[12] := $C0; b[13] := $0C;   { compression pointer, then nothing }
  rc := DnsParseResponseA(@b[0], 14, ips, count, outId);
  Show('truncated-rr', rc < 0);

  { 5: an lies large, packet minimal. }
  Clear;
  b[6] := 0; b[7] := 100;    { an=100 }
  rc := DnsParseResponseA(@b[0], 12, ips, count, outId);
  Show('an-lie', rc < 0);

  { 6: an=1, A record claims a huge rdlen. }
  Clear;
  b[7] := 1;
  b[12] := $C0; b[13] := $0C;          { name ptr }
  b[14] := 0; b[15] := 1;              { type A }
  b[16] := 0; b[17] := 1;              { class IN }
  b[22] := $FF; b[23] := $FF;          { rdlen = 65535 }
  rc := DnsParseResponseA(@b[0], 24, ips, count, outId);
  Show('huge-rdlen', rc < 0);

  { 7: reserved label-length bits (0x40) in a question name. }
  Clear;
  b[5] := 1;
  b[12] := $40;              { neither a normal label, nor a 0xC0 pointer }
  rc := DnsParseResponseA(@b[0], 20, ips, count, outId);
  Show('reserved-label', rc < 0);

  { 8: many A records — count must cap at DNS_MAX_IPS, no array overrun. }
  Clear;
  b[7] := 20;                { an=20 }
  p := 12;
  for i := 1 to 20 do
  begin
    b[p] := $C0; b[p+1] := $0C;        { name ptr }
    b[p+2] := 0; b[p+3] := 1;          { type A }
    b[p+4] := 0; b[p+5] := 1;          { class IN }
    b[p+6] := 0; b[p+7] := 0; b[p+8] := 0; b[p+9] := 0;   { ttl }
    b[p+10] := 0; b[p+11] := 4;        { rdlen 4 }
    b[p+12] := 10; b[p+13] := 0; b[p+14] := 0; b[p+15] := i;  { 10.0.0.i }
    p := p + 16;
  end;
  rc := DnsParseResponseA(@b[0], p, ips, count, outId);
  Show('many-a-rcode', rc = 0);
  Show('many-a-cap', count = DNS_MAX_IPS);

  writeln('done');
end.
