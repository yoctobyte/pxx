{ SPDX-License-Identifier: Zlib }
unit dns_wire_core;
{ Pure-Pascal DNS wire codec (RFC 1035), transport-free — the shared packet
  core for the future dns_wire_blocking / dns_wire_async resolvers
  (feature-dns-resolver-library). Encodes a standard recursive A-record query
  and parses A-record answers, including compressed names. No PAL / network
  dependency; runs and is tested entirely offline.

  Covers A and AAAA queries/answers plus CNAME-target extraction for chain
  chasing; /etc/hosts, resolv.conf and search/ndots policy live in dns_config,
  transports in dns_wire_blocking. }

interface

const
  DNS_TYPE_A     = 1;
  DNS_TYPE_CNAME = 5;
  DNS_TYPE_SOA   = 6;
  DNS_TYPE_AAAA  = 28;
  DNS_CLASS_IN  = 1;
  DNS_FLAG_RD   = $0100;   { recursion desired }
  DNS_MAX_IPS   = 16;

  { Negative parse results (distinct from a DNS RCODE, which is 0..15). }
  DNS_ERR_SHORT     = -1;   { packet truncated / ran off the end }
  DNS_ERR_MALFORMED = -2;   { bad label / pointer }
  DNS_ERR_TOOLONG   = -6;   { encoded query would not fit in bufLen }

type
  TDnsIpv4Array = array[0..DNS_MAX_IPS - 1] of LongWord;
  TDnsIpv6 = array[0..15] of Byte;   { one AAAA address, network byte order }
  TDnsIpv6Array = array[0..DNS_MAX_IPS - 1] of TDnsIpv6;

{ Encode a recursive query of `qtype` (DNS_TYPE_A / DNS_TYPE_AAAA / ...) for
  `name` into buf[0..bufLen-1]. Returns the packet length, DNS_ERR_MALFORMED if
  a label is empty or > 63 bytes, or DNS_ERR_TOOLONG if the encoding would
  exceed bufLen (the write is bounded — it never runs past bufLen). }
function DnsBuildQuery(const name: string; qtype, queryId: Integer; buf: Pointer; bufLen: Integer): Integer;

{ Encode a recursive A query — DnsBuildQuery with qtype DNS_TYPE_A. }
function DnsBuildQueryA(const name: string; queryId: Integer; buf: Pointer; bufLen: Integer): Integer;

{ Parse a DNS response in buf[0..len-1]. On success returns the DNS RCODE
  (0 = NOERROR) and fills ips[0..count-1] with the A addresses (host byte
  order); outId is the response transaction id. Returns a negative DNS_ERR_*
  on a malformed packet. RCODE 0 with count 0 means no A records. }
function DnsParseResponseA(buf: Pointer; len: Integer; var ips: TDnsIpv4Array;
  var count: Integer; var outId: Integer): Integer;

{ Parse a DNS response as for DnsParseResponseA, but extracting AAAA (IPv6)
  answers into ips (each 16 bytes, network byte order). }
function DnsParseResponseAAAA(buf: Pointer; len: Integer; var ips: TDnsIpv6Array;
  var count: Integer; var outId: Integer): Integer;

{ Extract the first CNAME answer's target name (dotted, lower-noise: bytes are
  copied verbatim) from a response. Used to chase a CNAME chain across queries
  when a response carries the alias but no address records. Returns False if no
  CNAME answer is present or the packet is malformed. }
function DnsExtractCname(buf: Pointer; len: Integer; var target: string): Boolean;

{ Minimum TTL (seconds) across the A/AAAA answer records — the lifetime a
  positive answer may be cached (a record set expires when its shortest TTL
  does). Returns -1 when there is no address answer or the packet is malformed. }
function DnsAnswerMinTTL(buf: Pointer; len: Integer): Integer;

{ Minimum TTL (seconds) across the CNAME answer records — the lifetime an
  alias mapping may be cached. Returns -1 when there is no CNAME answer or the
  packet is malformed. }
function DnsCnameTTL(buf: Pointer; len: Integer): Integer;

{ Negative-caching TTL (seconds) per RFC 2308: the SOA MINIMUM field of the SOA
  record in the authority section, capped by that SOA record's own TTL. Returns
  -1 when there is no SOA in the authority section or the packet is malformed. }
function DnsNegativeTTL(buf: Pointer; len: Integer): Integer;

{ True if the response has the TC (truncated) header bit set, meaning the answer
  did not fit in the UDP datagram and the query must be retried over TCP. }
function DnsTruncated(buf: Pointer; len: Integer): Boolean;

implementation

type
  PB = ^Byte;

function ByteAt(buf: Pointer; pos: Integer): Integer;
begin
  ByteAt := Integer(PB(Pointer(Int64(buf) + pos))^);
end;

procedure SetByteAt(buf: Pointer; pos, val: Integer);
begin
  PB(Pointer(Int64(buf) + pos))^ := Byte(val and $FF);
end;

function ReadU16(buf: Pointer; pos: Integer): Integer;
begin
  ReadU16 := (ByteAt(buf, pos) shl 8) or ByteAt(buf, pos + 1);
end;

{ 32-bit big-endian read as Int64 (TTLs are unsigned 32-bit; Int64 avoids the
  sign trap on a >= 2^31 TTL, which the callers then clamp to Integer range). }
function ReadU32(buf: Pointer; pos: Integer): Int64;
begin
  ReadU32 := (Int64(ByteAt(buf, pos)) shl 24) or (Int64(ByteAt(buf, pos + 1)) shl 16)
          or (Int64(ByteAt(buf, pos + 2)) shl 8) or Int64(ByteAt(buf, pos + 3));
end;

{ Advance past a domain name starting at pos. A compression pointer (top two
  bits set) is a 2-byte terminator. Returns the position after the name, or a
  negative DNS_ERR_* on error. }
function SkipName(buf: Pointer; len, pos: Integer): Integer;
var b: Integer;
begin
  while pos < len do
  begin
    b := ByteAt(buf, pos);
    if b = 0 then
    begin
      SkipName := pos + 1;
      Exit;
    end;
    if (b and $C0) = $C0 then
    begin
      SkipName := pos + 2;
      Exit;
    end;
    if (b and $C0) <> 0 then
    begin
      SkipName := DNS_ERR_MALFORMED;
      Exit;
    end;
    pos := pos + 1 + b;
  end;
  SkipName := DNS_ERR_SHORT;
end;

{ Write the label s[a..b] (1-based, inclusive) at pos, never past bufLen.
  Returns the new position, DNS_ERR_MALFORMED on an empty / over-long label, or
  DNS_ERR_TOOLONG if it would not fit. Top-level (not nested) so it does not
  reach into an enclosing scope. }
function WriteLabel(buf: Pointer; pos, bufLen: Integer; const s: string; a, b: Integer): Integer;
var len2, j: Integer;
begin
  len2 := b - a + 1;
  if (len2 <= 0) or (len2 > 63) then
  begin
    WriteLabel := DNS_ERR_MALFORMED;
    Exit;
  end;
  if pos + 1 + len2 > bufLen then
  begin
    WriteLabel := DNS_ERR_TOOLONG;
    Exit;
  end;
  SetByteAt(buf, pos, len2);
  pos := pos + 1;
  for j := a to b do
  begin
    SetByteAt(buf, pos, Ord(s[j]));
    pos := pos + 1;
  end;
  WriteLabel := pos;
end;

function DnsBuildQuery(const name: string; qtype, queryId: Integer; buf: Pointer; bufLen: Integer): Integer;
var
  pos, i, labelStart: Integer;
begin
  { 12-byte header + at least the root label + QTYPE/QCLASS (5). }
  if bufLen < 17 then
  begin
    DnsBuildQuery := DNS_ERR_TOOLONG;
    Exit;
  end;
  { Header: ID, flags (RD), QDCOUNT=1, AN/NS/AR = 0. }
  SetByteAt(buf, 0, (queryId shr 8) and $FF);
  SetByteAt(buf, 1, queryId and $FF);
  SetByteAt(buf, 2, (DNS_FLAG_RD shr 8) and $FF);
  SetByteAt(buf, 3, DNS_FLAG_RD and $FF);
  SetByteAt(buf, 4, 0);
  SetByteAt(buf, 5, 1);
  for i := 6 to 11 do SetByteAt(buf, i, 0);
  pos := 12;

  { QNAME: dotted name -> length-prefixed labels, root terminator. }
  labelStart := 1;
  for i := 1 to Length(name) do
  begin
    if name[i] = '.' then
    begin
      pos := WriteLabel(buf, pos, bufLen, name, labelStart, i - 1);
      if pos < 0 then
      begin
        DnsBuildQuery := pos;   { propagate MALFORMED / TOOLONG }
        Exit;
      end;
      labelStart := i + 1;
    end;
  end;
  if labelStart <= Length(name) then
  begin
    pos := WriteLabel(buf, pos, bufLen, name, labelStart, Length(name));
    if pos < 0 then
    begin
      DnsBuildQuery := pos;
      Exit;
    end;
  end;
  { root terminator + QTYPE + QCLASS = 5 bytes. }
  if pos + 5 > bufLen then
  begin
    DnsBuildQuery := DNS_ERR_TOOLONG;
    Exit;
  end;
  SetByteAt(buf, pos, 0);
  pos := pos + 1;

  { QTYPE + QCLASS = IN. }
  SetByteAt(buf, pos, (qtype shr 8) and $FF);  pos := pos + 1;
  SetByteAt(buf, pos, qtype and $FF);          pos := pos + 1;
  SetByteAt(buf, pos, 0);                      pos := pos + 1;
  SetByteAt(buf, pos, DNS_CLASS_IN);           pos := pos + 1;

  DnsBuildQuery := pos;
end;

function DnsBuildQueryA(const name: string; queryId: Integer; buf: Pointer; bufLen: Integer): Integer;
begin
  DnsBuildQueryA := DnsBuildQuery(name, DNS_TYPE_A, queryId, buf, bufLen);
end;

function DnsParseResponseA(buf: Pointer; len: Integer; var ips: TDnsIpv4Array;
  var count: Integer; var outId: Integer): Integer;
var
  qd, an, rcode, pos, i: Integer;
  atype, aclass, rdlen: Integer;
begin
  count := 0;
  outId := 0;
  if len < 12 then
  begin
    DnsParseResponseA := DNS_ERR_SHORT;
    Exit;
  end;
  outId := ReadU16(buf, 0);
  rcode := ByteAt(buf, 3) and $0F;
  qd := ReadU16(buf, 4);
  an := ReadU16(buf, 6);
  pos := 12;

  { Skip the question section: QDCOUNT names, each followed by QTYPE+QCLASS. }
  for i := 1 to qd do
  begin
    pos := SkipName(buf, len, pos);
    if pos < 0 then
    begin
      DnsParseResponseA := pos;
      Exit;
    end;
    pos := pos + 4;
    if pos > len then
    begin
      DnsParseResponseA := DNS_ERR_SHORT;
      Exit;
    end;
  end;

  { Answer RRs. }
  for i := 1 to an do
  begin
    pos := SkipName(buf, len, pos);
    if pos < 0 then
    begin
      DnsParseResponseA := pos;
      Exit;
    end;
    if pos + 10 > len then
    begin
      DnsParseResponseA := DNS_ERR_SHORT;
      Exit;
    end;
    atype  := ReadU16(buf, pos);
    aclass := ReadU16(buf, pos + 2);
    { skip TTL (4) }
    rdlen  := ReadU16(buf, pos + 8);
    pos := pos + 10;
    if pos + rdlen > len then
    begin
      DnsParseResponseA := DNS_ERR_SHORT;
      Exit;
    end;
    if (atype = DNS_TYPE_A) and (aclass = DNS_CLASS_IN) and (rdlen = 4) then
    begin
      if count < DNS_MAX_IPS then
      begin
        ips[count] := (LongWord(ByteAt(buf, pos)) shl 24)
                   or (LongWord(ByteAt(buf, pos + 1)) shl 16)
                   or (LongWord(ByteAt(buf, pos + 2)) shl 8)
                   or  LongWord(ByteAt(buf, pos + 3));
        count := count + 1;
      end;
    end;
    pos := pos + rdlen;
  end;

  DnsParseResponseA := rcode;
end;

function DnsParseResponseAAAA(buf: Pointer; len: Integer; var ips: TDnsIpv6Array;
  var count: Integer; var outId: Integer): Integer;
var
  qd, an, rcode, pos, i, j: Integer;
  atype, aclass, rdlen: Integer;
begin
  count := 0;
  outId := 0;
  if len < 12 then
  begin
    DnsParseResponseAAAA := DNS_ERR_SHORT;
    Exit;
  end;
  outId := ReadU16(buf, 0);
  rcode := ByteAt(buf, 3) and $0F;
  qd := ReadU16(buf, 4);
  an := ReadU16(buf, 6);
  pos := 12;

  for i := 1 to qd do
  begin
    pos := SkipName(buf, len, pos);
    if pos < 0 then
    begin
      DnsParseResponseAAAA := pos;
      Exit;
    end;
    pos := pos + 4;
    if pos > len then
    begin
      DnsParseResponseAAAA := DNS_ERR_SHORT;
      Exit;
    end;
  end;

  for i := 1 to an do
  begin
    pos := SkipName(buf, len, pos);
    if pos < 0 then
    begin
      DnsParseResponseAAAA := pos;
      Exit;
    end;
    if pos + 10 > len then
    begin
      DnsParseResponseAAAA := DNS_ERR_SHORT;
      Exit;
    end;
    atype  := ReadU16(buf, pos);
    aclass := ReadU16(buf, pos + 2);
    rdlen  := ReadU16(buf, pos + 8);
    pos := pos + 10;
    if pos + rdlen > len then
    begin
      DnsParseResponseAAAA := DNS_ERR_SHORT;
      Exit;
    end;
    if (atype = DNS_TYPE_AAAA) and (aclass = DNS_CLASS_IN) and (rdlen = 16) then
    begin
      if count < DNS_MAX_IPS then
      begin
        for j := 0 to 15 do
          ips[count][j] := Byte(ByteAt(buf, pos + j));
        count := count + 1;
      end;
    end;
    pos := pos + rdlen;
  end;

  DnsParseResponseAAAA := rcode;
end;

{ Decode the domain name at pos into a dotted string, following compression
  pointers (hop-bounded so a pointer loop cannot hang). Returns True on a
  well-formed name. }
function ReadNameAt(buf: Pointer; len, pos: Integer; var s: string): Boolean;
var
  b, j, hops: Integer;
  first: Boolean;
begin
  ReadNameAt := False;
  s := '';
  hops := 0;
  first := True;
  while True do
  begin
    if (pos < 0) or (pos >= len) then Exit;
    b := ByteAt(buf, pos);
    if b = 0 then
    begin
      ReadNameAt := True;
      Exit;
    end;
    if (b and $C0) = $C0 then
    begin
      if pos + 1 >= len then Exit;
      hops := hops + 1;
      if hops > 16 then Exit;   { pointer loop }
      pos := ((b and $3F) shl 8) or ByteAt(buf, pos + 1);
    end
    else if (b and $C0) <> 0 then
      Exit
    else
    begin
      if pos + 1 + b > len then Exit;
      if not first then s := s + '.';
      for j := 1 to b do
        s := s + Chr(ByteAt(buf, pos + j));
      first := False;
      pos := pos + 1 + b;
      if Length(s) > 255 then Exit;   { RFC 1035 name bound }
    end;
  end;
end;

function DnsExtractCname(buf: Pointer; len: Integer; var target: string): Boolean;
var
  qd, an, pos, i: Integer;
  atype, aclass, rdlen: Integer;
  nameOut: string;
begin
  DnsExtractCname := False;
  target := '';
  if len < 12 then Exit;
  qd := ReadU16(buf, 4);
  an := ReadU16(buf, 6);
  pos := 12;

  for i := 1 to qd do
  begin
    pos := SkipName(buf, len, pos);
    if pos < 0 then Exit;
    pos := pos + 4;
    if pos > len then Exit;
  end;

  for i := 1 to an do
  begin
    pos := SkipName(buf, len, pos);
    if pos < 0 then Exit;
    if pos + 10 > len then Exit;
    atype  := ReadU16(buf, pos);
    aclass := ReadU16(buf, pos + 2);
    rdlen  := ReadU16(buf, pos + 8);
    pos := pos + 10;
    if pos + rdlen > len then Exit;
    if (atype = DNS_TYPE_CNAME) and (aclass = DNS_CLASS_IN) then
    begin
      nameOut := '';
      if ReadNameAt(buf, len, pos, nameOut) then
      begin
        target := nameOut;
        DnsExtractCname := True;
      end;
      Exit;
    end;
    pos := pos + rdlen;
  end;
end;

{ Clamp an unsigned-32 TTL (seconds) to a non-negative Integer. TTLs above
  ~68 years are pinned to MaxLongInt — no cache keeps them anyway. }
function ClampTTL(v: Int64): Integer;
begin
  if v < 0 then v := 0;
  if v > 2147483647 then v := 2147483647;
  ClampTTL := Integer(v);
end;

function DnsAnswerMinTTL(buf: Pointer; len: Integer): Integer;
var
  qd, an, pos, i: Integer;
  atype, aclass, rdlen, found: Integer;
  minTtl, ttl: Int64;
begin
  DnsAnswerMinTTL := -1;
  if len < 12 then Exit;
  qd := ReadU16(buf, 4);
  an := ReadU16(buf, 6);
  pos := 12;

  for i := 1 to qd do
  begin
    pos := SkipName(buf, len, pos);
    if pos < 0 then Exit;
    pos := pos + 4;
    if pos > len then Exit;
  end;

  found := 0;
  minTtl := 0;
  for i := 1 to an do
  begin
    pos := SkipName(buf, len, pos);
    if pos < 0 then Exit;
    if pos + 10 > len then Exit;
    atype  := ReadU16(buf, pos);
    aclass := ReadU16(buf, pos + 2);
    ttl    := ReadU32(buf, pos + 4);
    rdlen  := ReadU16(buf, pos + 8);
    pos := pos + 10;
    if pos + rdlen > len then Exit;
    if ((atype = DNS_TYPE_A) or (atype = DNS_TYPE_AAAA)) and (aclass = DNS_CLASS_IN) then
    begin
      if (found = 0) or (ttl < minTtl) then minTtl := ttl;
      found := 1;
    end;
    pos := pos + rdlen;
  end;

  if found = 1 then
    DnsAnswerMinTTL := ClampTTL(minTtl);
end;

function DnsCnameTTL(buf: Pointer; len: Integer): Integer;
var
  qd, an, pos, i: Integer;
  atype, aclass, rdlen, found: Integer;
  minTtl, ttl: Int64;
begin
  DnsCnameTTL := -1;
  if len < 12 then Exit;
  qd := ReadU16(buf, 4);
  an := ReadU16(buf, 6);
  pos := 12;

  for i := 1 to qd do
  begin
    pos := SkipName(buf, len, pos);
    if pos < 0 then Exit;
    pos := pos + 4;
    if pos > len then Exit;
  end;

  found := 0;
  minTtl := 0;
  for i := 1 to an do
  begin
    pos := SkipName(buf, len, pos);
    if pos < 0 then Exit;
    if pos + 10 > len then Exit;
    atype  := ReadU16(buf, pos);
    aclass := ReadU16(buf, pos + 2);
    ttl    := ReadU32(buf, pos + 4);
    rdlen  := ReadU16(buf, pos + 8);
    pos := pos + 10;
    if pos + rdlen > len then Exit;
    if (atype = DNS_TYPE_CNAME) and (aclass = DNS_CLASS_IN) then
    begin
      if (found = 0) or (ttl < minTtl) then minTtl := ttl;
      found := 1;
    end;
    pos := pos + rdlen;
  end;

  if found = 1 then
    DnsCnameTTL := ClampTTL(minTtl);
end;

function DnsNegativeTTL(buf: Pointer; len: Integer): Integer;
var
  qd, an, ns, pos, i: Integer;
  atype, aclass, rdlen, rdstart: Integer;
  recTtl, soaMin, useTtl: Int64;
  namePos: Integer;
begin
  DnsNegativeTTL := -1;
  if len < 12 then Exit;
  qd := ReadU16(buf, 4);
  an := ReadU16(buf, 6);
  ns := ReadU16(buf, 8);   { authority (NSCOUNT) — where the SOA lives }
  pos := 12;

  for i := 1 to qd do
  begin
    pos := SkipName(buf, len, pos);
    if pos < 0 then Exit;
    pos := pos + 4;
    if pos > len then Exit;
  end;
  { skip the answer section wholesale }
  for i := 1 to an do
  begin
    pos := SkipName(buf, len, pos);
    if pos < 0 then Exit;
    if pos + 10 > len then Exit;
    rdlen := ReadU16(buf, pos + 8);
    pos := pos + 10 + rdlen;
    if pos > len then Exit;
  end;

  { authority section: find the SOA record }
  for i := 1 to ns do
  begin
    pos := SkipName(buf, len, pos);
    if pos < 0 then Exit;
    if pos + 10 > len then Exit;
    atype  := ReadU16(buf, pos);
    aclass := ReadU16(buf, pos + 2);
    recTtl := ReadU32(buf, pos + 4);
    rdlen  := ReadU16(buf, pos + 8);
    rdstart := pos + 10;
    if rdstart + rdlen > len then Exit;
    if (atype = DNS_TYPE_SOA) and (aclass = DNS_CLASS_IN) then
    begin
      { SOA rdata: MNAME, RNAME (two names), then 5 x u32 (serial, refresh,
        retry, expire, minimum). Skip the two names, read the last u32. }
      namePos := SkipName(buf, len, rdstart);
      if namePos < 0 then Exit;
      namePos := SkipName(buf, len, namePos);
      if namePos < 0 then Exit;
      if namePos + 20 > len then Exit;      { 5 x u32 = 20 bytes }
      soaMin := ReadU32(buf, namePos + 16); { the MINIMUM field }
      { RFC 2308: negative TTL = min(SOA.MINIMUM, SOA record TTL). }
      if recTtl < soaMin then useTtl := recTtl else useTtl := soaMin;
      DnsNegativeTTL := ClampTTL(useTtl);
      Exit;
    end;
    pos := rdstart + rdlen;
  end;
end;

function DnsTruncated(buf: Pointer; len: Integer): Boolean;
begin
  if len < 3 then
    DnsTruncated := False
  else
    DnsTruncated := (ByteAt(buf, 2) and $02) <> 0;   { flags byte 2, TC bit }
end;

end.
