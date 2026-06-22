unit dns_wire_core;
{ Pure-Pascal DNS wire codec (RFC 1035), transport-free — the shared packet
  core for the future dns_wire_blocking / dns_wire_async resolvers
  (feature-dns-resolver-library). Encodes a standard recursive A-record query
  and parses A-record answers, including compressed names. No PAL / network
  dependency; runs and is tested entirely offline.

  First slice: A (IPv4) only. AAAA, CNAME-chain following, /etc/hosts and
  resolv.conf, search/ndots and TCP fallback are deliberately later. }

interface

const
  DNS_TYPE_A    = 1;
  DNS_CLASS_IN  = 1;
  DNS_FLAG_RD   = $0100;   { recursion desired }
  DNS_MAX_IPS   = 16;

  { Negative parse results (distinct from a DNS RCODE, which is 0..15). }
  DNS_ERR_SHORT     = -1;   { packet truncated / ran off the end }
  DNS_ERR_MALFORMED = -2;   { bad label / pointer }

type
  TDnsIpv4Array = array[0..DNS_MAX_IPS - 1] of LongWord;

{ Encode a recursive A query for `name` into buf. buf must hold at least
  12 + Length(name) + 2 + 5 bytes (<= 512 for any legal name). Returns the
  packet length, or DNS_ERR_MALFORMED if a label is empty or > 63 bytes. }
function DnsBuildQueryA(const name: string; queryId: Integer; buf: Pointer): Integer;

{ Parse a DNS response in buf[0..len-1]. On success returns the DNS RCODE
  (0 = NOERROR) and fills ips[0..count-1] with the A addresses (host byte
  order); outId is the response transaction id. Returns a negative DNS_ERR_*
  on a malformed packet. RCODE 0 with count 0 means no A records. }
function DnsParseResponseA(buf: Pointer; len: Integer; var ips: TDnsIpv4Array;
  var count: Integer; var outId: Integer): Integer;

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

{ Write the label s[a..b] (1-based, inclusive) at pos; returns the new position,
  or DNS_ERR_MALFORMED on an empty / over-long label. Top-level (not nested) so
  it does not reach into an enclosing scope. }
function WriteLabel(buf: Pointer; pos: Integer; const s: string; a, b: Integer): Integer;
var len2, j: Integer;
begin
  len2 := b - a + 1;
  if (len2 <= 0) or (len2 > 63) then
  begin
    WriteLabel := DNS_ERR_MALFORMED;
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

function DnsBuildQueryA(const name: string; queryId: Integer; buf: Pointer): Integer;
var
  pos, i, labelStart: Integer;
begin
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
      pos := WriteLabel(buf, pos, name, labelStart, i - 1);
      if pos < 0 then
      begin
        DnsBuildQueryA := DNS_ERR_MALFORMED;
        Exit;
      end;
      labelStart := i + 1;
    end;
  end;
  if labelStart <= Length(name) then
  begin
    pos := WriteLabel(buf, pos, name, labelStart, Length(name));
    if pos < 0 then
    begin
      DnsBuildQueryA := DNS_ERR_MALFORMED;
      Exit;
    end;
  end;
  SetByteAt(buf, pos, 0);
  pos := pos + 1;

  { QTYPE = A, QCLASS = IN. }
  SetByteAt(buf, pos, 0);            pos := pos + 1;
  SetByteAt(buf, pos, DNS_TYPE_A);   pos := pos + 1;
  SetByteAt(buf, pos, 0);            pos := pos + 1;
  SetByteAt(buf, pos, DNS_CLASS_IN); pos := pos + 1;

  DnsBuildQueryA := pos;
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

end.
