{ SPDX-License-Identifier: Zlib }
unit dns_config;
{ POSIX resolver configuration parsing for the dns_wire path
  (feature-dns-resolver-library): dotted-quad IPv4 parsing and `/etc/resolv.conf`
  nameserver extraction. Pure string -> data, no PAL/network dependency, so it
  is tested offline; a caller reads the file via PAL and hands the text in.

  Covers `nameserver`, `search`/`domain`, `options ndots:N`, and `/etc/hosts`
  lookup, plus the glibc-style search-list candidate ordering. Public DNS is
  never assumed — an empty result means "no configured resolver", which the
  resolver must treat as a hard error unless the caller explicitly opts into a
  fallback. }

interface

uses dns_wire_core;   { TDnsIpv4Array, DNS_MAX_IPS }

const
  DNS_MAX_SEARCH = 6;      { search-domain list bound (glibc keeps 6) }
  DNS_DEFAULT_NDOTS = 1;

type
  TDnsSearchArray = array[0..DNS_MAX_SEARCH - 1] of string;

{ Parse s[startIdx..endIdx] (1-based, inclusive) as a dotted-quad IPv4 literal
  into ip (host byte order). Returns False on any malformed input. }
function DnsParseIpv4(const s: string; startIdx, endIdx: Integer; var ip: LongWord): Boolean;

{ Extract `nameserver <ipv4>` entries from resolv.conf text into ns[0..count-1]
  (host byte order, up to DNS_MAX_IPS). Lines may have leading whitespace; `#`
  and `;` start comments. Returns the nameserver count (also via count). }
function DnsParseResolvConf(const text: string; var ns: TDnsIpv4Array; var count: Integer): Integer;

{ Full resolv.conf parse: nameservers as above, plus the search list (`search`
  lists domains; `domain` sets a single-entry list; the last of either wins,
  matching glibc) and `options ndots:N`. searchCount / ndots are always set
  (0 / DNS_DEFAULT_NDOTS when absent). Returns the nameserver count. }
function DnsParseResolvConfEx(const text: string; var ns: TDnsIpv4Array; var nsCount: Integer;
  var search: TDnsSearchArray; var searchCount: Integer; var ndots: Integer): Integer;

{ Enumerate the query names to try for `name` under the search policy, glibc
  order: a name with >= ndots dots (or a trailing dot, = absolute) is tried
  as-is first, then with each search domain appended; a name with fewer dots
  tries the search-qualified forms first and the bare name last. idx counts
  from 0; returns False when the candidates are exhausted. }
function DnsQueryCandidate(const name: string; const search: TDnsSearchArray;
  searchCount, ndots, idx: Integer; var cand: string): Boolean;

{ Look up `name` in /etc/hosts text (the "files" half of "files dns"). Each line
  is `<ipv4> <hostname> [aliases...]`; hostname match is case-insensitive; `#`
  starts a comment. Returns True with ip set (host byte order) on the first
  match. IPv6 host lines are skipped (A/IPv4 slice only). }
function DnsLookupHosts(const text: string; const name: string; var ip: LongWord): Boolean;

{ Parse s[startIdx..endIdx] (1-based, inclusive) as an IPv6 text literal into
  ip6 (16 bytes, network byte order). Accepts full and `::`-compressed forms
  and an embedded dotted-quad tail (`::ffff:1.2.3.4`). Rejects zone ids (`%`),
  more than one `::`, oversized groups, and wrong group counts. Returns False
  on any malformed input. }
function DnsParseIpv6(const s: string; startIdx, endIdx: Integer; var ip6: TDnsIpv6): Boolean;

{ IPv6 sibling of DnsLookupHosts: match `name` against `<ipv6> <hostname>
  [aliases...]` lines in /etc/hosts text. IPv4 lines are skipped. Returns True
  with ip6 set (network byte order) on the first match. }
function DnsLookupHosts6(const text: string; const name: string; var ip6: TDnsIpv6): Boolean;

implementation

function DnsParseIpv4(const s: string; startIdx, endIdx: Integer; var ip: LongWord): Boolean;
var
  i, val, octets: Integer;
  c: Char;
  sawDigit: Boolean;
begin
  ip := 0;
  val := 0;
  octets := 0;
  sawDigit := False;
  for i := startIdx to endIdx do
  begin
    c := s[i];
    if (c >= '0') and (c <= '9') then
    begin
      val := val * 10 + (Ord(c) - Ord('0'));
      if val > 255 then
      begin
        DnsParseIpv4 := False;
        Exit;
      end;
      sawDigit := True;
    end
    else if c = '.' then
    begin
      if not sawDigit then
      begin
        DnsParseIpv4 := False;
        Exit;
      end;
      ip := (ip shl 8) or LongWord(val);
      octets := octets + 1;
      val := 0;
      sawDigit := False;
    end
    else
    begin
      DnsParseIpv4 := False;
      Exit;
    end;
  end;
  if not sawDigit then
  begin
    DnsParseIpv4 := False;
    Exit;
  end;
  ip := (ip shl 8) or LongWord(val);
  octets := octets + 1;
  DnsParseIpv4 := (octets = 4);
end;

{ Hex digit value, or -1. }
function HexVal(c: Char): Integer;
begin
  if (c >= '0') and (c <= '9') then
    HexVal := Ord(c) - Ord('0')
  else if (c >= 'a') and (c <= 'f') then
    HexVal := Ord(c) - Ord('a') + 10
  else if (c >= 'A') and (c <= 'F') then
    HexVal := Ord(c) - Ord('A') + 10
  else
    HexVal := -1;
end;

function DnsParseIpv6(const s: string; startIdx, endIdx: Integer; var ip6: TDnsIpv6): Boolean;
var
  g: array[0..7] of Integer;   { 16-bit groups in written order }
  gN: Integer;                 { groups collected }
  gapIdx: Integer;             { index the "::" gap sits before; -1 = no gap }
  isV4: Boolean;
  p, gs, v, digits, hv, i, fill, gi: Integer;
  c: Char;
  ip4: LongWord;
begin
  DnsParseIpv6 := False;
  for i := 0 to 15 do ip6[i] := 0;
  if endIdx < startIdx then Exit;

  gN := 0;
  gapIdx := -1;
  p := startIdx;

  { leading "::" (a single leading ':' is malformed) }
  if s[p] = ':' then
  begin
    if (p + 1 > endIdx) or (s[p + 1] <> ':') then Exit;
    gapIdx := 0;
    p := p + 2;
    if p > endIdx then
    begin
      DnsParseIpv6 := True;   { "::" alone = all zeros }
      Exit;
    end;
  end;

  while p <= endIdx do
  begin
    { one group: 1..4 hex digits, or the start of a dotted-quad tail }
    gs := p;
    v := 0;
    digits := 0;
    isV4 := False;
    while p <= endIdx do
    begin
      c := s[p];
      hv := HexVal(c);
      if hv >= 0 then
      begin
        v := v * 16 + hv;
        digits := digits + 1;
        if digits > 4 then Exit;
        p := p + 1;
      end
      else if c = '.' then
      begin
        isV4 := True;
        Break;
      end
      else
        Break;
    end;
    if isV4 then
    begin
      { embedded IPv4 tail: must run to the end and counts as two groups }
      if not DnsParseIpv4(s, gs, endIdx, ip4) then Exit;
      if gN >= 7 then Exit;
      g[gN] := Integer((ip4 shr 16) and $FFFF);
      g[gN + 1] := Integer(ip4 and $FFFF);
      gN := gN + 2;
      p := endIdx + 1;
      Break;
    end;
    if digits = 0 then Exit;   { empty group / stray character }
    if gN >= 8 then Exit;
    g[gN] := v;
    gN := gN + 1;
    if p > endIdx then Break;
    if s[p] <> ':' then Exit;  { zone id ('%') or other junk }
    if (p + 1 <= endIdx) and (s[p + 1] = ':') then
    begin
      if gapIdx >= 0 then Exit;   { at most one "::" }
      gapIdx := gN;
      p := p + 2;
      if p > endIdx then Break;   { trailing "::" }
    end
    else
    begin
      p := p + 1;
      if p > endIdx then Exit;    { trailing single ':' }
    end;
  end;

  if gapIdx >= 0 then
  begin
    if gN > 7 then Exit;   { "::" must stand for at least one zero group }
  end
  else if gN <> 8 then
    Exit;

  { write out: groups before the gap at their index, groups after shifted right }
  fill := 8 - gN;
  for i := 0 to gN - 1 do
  begin
    gi := i;
    if (gapIdx >= 0) and (i >= gapIdx) then gi := i + fill;
    ip6[gi * 2] := Byte((g[i] shr 8) and $FF);
    ip6[gi * 2 + 1] := Byte(g[i] and $FF);
  end;
  DnsParseIpv6 := True;
end;

function IsSpace(c: Char): Boolean;
begin
  IsSpace := (c = ' ') or (c = #9) or (c = #13);
end;

{ Next whitespace-delimited token in text[p..le]; stops the scan at a comment.
  Returns True with the token at [ts..te] and p advanced past it. }
function NextToken(const text: string; var p: Integer; le: Integer; var ts, te: Integer): Boolean;
begin
  NextToken := False;
  while (p <= le) and IsSpace(text[p]) do p := p + 1;
  if (p > le) or (text[p] = '#') or (text[p] = ';') then Exit;
  ts := p;
  while (p <= le) and (not IsSpace(text[p])) and (text[p] <> '#') and (text[p] <> ';') do
    p := p + 1;
  te := p - 1;
  NextToken := True;
end;

{ True if text[ts..te] equals the keyword kw exactly. }
function TokenIs(const text: string; ts, te: Integer; const kw: string): Boolean;
var k: Integer;
begin
  TokenIs := False;
  if te - ts + 1 <> Length(kw) then Exit;
  for k := 1 to Length(kw) do
    if text[ts + k - 1] <> kw[k] then Exit;
  TokenIs := True;
end;

{ Dispatch one resolv.conf line into the accumulating config. }
procedure ParseResolvLine(const text: string; ls, le: Integer;
  var ns: TDnsIpv4Array; var nsCount: Integer;
  var search: TDnsSearchArray; var searchCount: Integer; var ndots: Integer);
var
  p, ts, te, j, val: Integer;
  ip: LongWord;
  tok: string;
begin
  p := ls;
  if not NextToken(text, p, le, ts, te) then Exit;
  if TokenIs(text, ts, te, 'nameserver') then
  begin
    if NextToken(text, p, le, ts, te) and DnsParseIpv4(text, ts, te, ip) then
      if nsCount < DNS_MAX_IPS then
      begin
        ns[nsCount] := ip;
        nsCount := nsCount + 1;
      end;
  end
  else if TokenIs(text, ts, te, 'search') or TokenIs(text, ts, te, 'domain') then
  begin
    { last search/domain line wins (glibc behavior) }
    searchCount := 0;
    while NextToken(text, p, le, ts, te) do
    begin
      if searchCount < DNS_MAX_SEARCH then
      begin
        tok := '';
        for j := ts to te do tok := tok + text[j];
        search[searchCount] := tok;
        searchCount := searchCount + 1;
      end;
    end;
  end
  else if TokenIs(text, ts, te, 'options') then
  begin
    while NextToken(text, p, le, ts, te) do
    begin
      { ndots:N }
      if (te - ts + 1 > 6) and TokenIs(text, ts, ts + 5, 'ndots:') then
      begin
        val := 0;
        j := ts + 6;
        while (j <= te) and (val >= 0) do
        begin
          if (text[j] < '0') or (text[j] > '9') then
            val := -1   { malformed — ignore the option }
          else
            val := val * 10 + (Ord(text[j]) - Ord('0'));
          j := j + 1;
        end;
        if val >= 0 then
        begin
          if val > 15 then val := 15;   { glibc caps ndots at 15 }
          ndots := val;
        end;
      end;
    end;
  end;
end;

function DnsParseResolvConfEx(const text: string; var ns: TDnsIpv4Array; var nsCount: Integer;
  var search: TDnsSearchArray; var searchCount: Integer; var ndots: Integer): Integer;
var
  i, ls, n: Integer;
begin
  nsCount := 0;
  searchCount := 0;
  ndots := DNS_DEFAULT_NDOTS;
  n := Length(text);
  ls := 1;
  for i := 1 to n do
  begin
    if text[i] = #10 then
    begin
      if i - 1 >= ls then
        ParseResolvLine(text, ls, i - 1, ns, nsCount, search, searchCount, ndots);
      ls := i + 1;
    end;
  end;
  { trailing line with no final newline }
  if ls <= n then
    ParseResolvLine(text, ls, n, ns, nsCount, search, searchCount, ndots);
  DnsParseResolvConfEx := nsCount;
end;

function DnsParseResolvConf(const text: string; var ns: TDnsIpv4Array; var count: Integer): Integer;
var
  search: TDnsSearchArray;
  searchCount, ndots, localCount: Integer;
begin
  { locals, then copy out — never forward a var param into another var param
    (feature-riscv32-var-param-forwarding) }
  localCount := 0;
  DnsParseResolvConf := DnsParseResolvConfEx(text, ns, localCount, search, searchCount, ndots);
  count := localCount;
end;

function DnsCountDots(const name: string): Integer;
var i, n: Integer;
begin
  n := 0;
  for i := 1 to Length(name) do
    if name[i] = '.' then n := n + 1;
  DnsCountDots := n;
end;

function DnsQueryCandidate(const name: string; const search: TDnsSearchArray;
  searchCount, ndots, idx: Integer; var cand: string): Boolean;
var
  bare: string;
  absolute, manyDots: Boolean;
  i: Integer;
begin
  DnsQueryCandidate := False;
  cand := '';
  if Length(name) = 0 then Exit;
  absolute := name[Length(name)] = '.';
  if absolute then
  begin
    { trailing dot = use exactly this name, no search qualification }
    if idx <> 0 then Exit;
    bare := '';
    for i := 1 to Length(name) - 1 do
      bare := bare + name[i];
    cand := bare;
    DnsQueryCandidate := True;
    Exit;
  end;
  manyDots := DnsCountDots(name) >= ndots;
  if manyDots then
  begin
    { as-is first, then search-qualified }
    if idx = 0 then
    begin
      cand := name;
      DnsQueryCandidate := True;
    end
    else if idx <= searchCount then
    begin
      cand := name + '.' + search[idx - 1];
      DnsQueryCandidate := True;
    end;
  end
  else
  begin
    { search-qualified first, bare name last }
    if idx < searchCount then
    begin
      cand := name + '.' + search[idx];
      DnsQueryCandidate := True;
    end
    else if idx = searchCount then
    begin
      cand := name;
      DnsQueryCandidate := True;
    end;
  end;
end;

function LowerCh(c: Char): Char;
begin
  if (c >= 'A') and (c <= 'Z') then
    LowerCh := Chr(Ord(c) + 32)
  else
    LowerCh := c;
end;

{ Case-insensitive compare of text[ts..te] against the whole of name. }
function EqualsCI(const text: string; ts, te: Integer; const name: string): Boolean;
var i, n: Integer;
begin
  n := te - ts + 1;
  if n <> Length(name) then
  begin
    EqualsCI := False;
    Exit;
  end;
  for i := 1 to n do
    if LowerCh(text[ts + i - 1]) <> LowerCh(name[i]) then
    begin
      EqualsCI := False;
      Exit;
    end;
  EqualsCI := True;
end;

{ One /etc/hosts line text[ls..le]: if any hostname token matches name, parse the
  leading address into ip and return True. }
function MatchHostsLine(const text: string; ls, le: Integer; const name: string; var ip: LongWord): Boolean;
var
  p, ts, te, tokIndex: Integer;
  ipStart, ipEnd: Integer;
  tmp: LongWord;
begin
  MatchHostsLine := False;
  ipStart := 0;
  ipEnd := -1;
  tokIndex := 0;
  p := ls;
  while p <= le do
  begin
    { skip whitespace }
    while (p <= le) and IsSpace(text[p]) do p := p + 1;
    if p > le then Exit;
    if text[p] = '#' then Exit;
    { token [ts..te] }
    ts := p;
    while (p <= le) and (not IsSpace(text[p])) and (text[p] <> '#') do p := p + 1;
    te := p - 1;
    if tokIndex = 0 then
    begin
      ipStart := ts;
      ipEnd := te;
    end
    else if EqualsCI(text, ts, te, name) then
    begin
      if DnsParseIpv4(text, ipStart, ipEnd, tmp) then
      begin
        ip := tmp;
        MatchHostsLine := True;
      end;
      Exit;
    end;
    tokIndex := tokIndex + 1;
  end;
end;

function DnsLookupHosts(const text: string; const name: string; var ip: LongWord): Boolean;
var
  i, ls, n: Integer;
  found: LongWord;   { local, not the var param: avoids var->var forwarding }
begin
  DnsLookupHosts := False;
  found := 0;
  n := Length(text);
  ls := 1;
  for i := 1 to n do
  begin
    if text[i] = #10 then
    begin
      if (i - 1 >= ls) and MatchHostsLine(text, ls, i - 1, name, found) then
      begin
        ip := found;
        DnsLookupHosts := True;
        Exit;
      end;
      ls := i + 1;
    end;
  end;
  if (ls <= n) and MatchHostsLine(text, ls, n, name, found) then
  begin
    ip := found;
    DnsLookupHosts := True;
  end;
end;

{ One /etc/hosts line text[ls..le]: if any hostname token matches name and the
  leading address token parses as IPv6, fill ip6 and return True. }
function MatchHostsLine6(const text: string; ls, le: Integer; const name: string; var ip6: TDnsIpv6): Boolean;
var
  p, ts, te, tokIndex, i: Integer;
  ipStart, ipEnd: Integer;
  tmp: TDnsIpv6;
begin
  MatchHostsLine6 := False;
  ipStart := 0;
  ipEnd := -1;
  tokIndex := 0;
  p := ls;
  while p <= le do
  begin
    { skip whitespace }
    while (p <= le) and IsSpace(text[p]) do p := p + 1;
    if p > le then Exit;
    if text[p] = '#' then Exit;
    { token [ts..te] }
    ts := p;
    while (p <= le) and (not IsSpace(text[p])) and (text[p] <> '#') do p := p + 1;
    te := p - 1;
    if tokIndex = 0 then
    begin
      ipStart := ts;
      ipEnd := te;
    end
    else if EqualsCI(text, ts, te, name) then
    begin
      if DnsParseIpv6(text, ipStart, ipEnd, tmp) then
      begin
        for i := 0 to 15 do ip6[i] := tmp[i];
        MatchHostsLine6 := True;
      end;
      Exit;
    end;
    tokIndex := tokIndex + 1;
  end;
end;

function DnsLookupHosts6(const text: string; const name: string; var ip6: TDnsIpv6): Boolean;
var
  i, k, ls, n: Integer;
  found: TDnsIpv6;   { local, not the var param: avoids var->var forwarding }
begin
  DnsLookupHosts6 := False;
  for k := 0 to 15 do found[k] := 0;
  n := Length(text);
  ls := 1;
  for i := 1 to n do
  begin
    if text[i] = #10 then
    begin
      if (i - 1 >= ls) and MatchHostsLine6(text, ls, i - 1, name, found) then
      begin
        for k := 0 to 15 do ip6[k] := found[k];
        DnsLookupHosts6 := True;
        Exit;
      end;
      ls := i + 1;
    end;
  end;
  if (ls <= n) and MatchHostsLine6(text, ls, n, name, found) then
  begin
    for k := 0 to 15 do ip6[k] := found[k];
    DnsLookupHosts6 := True;
  end;
end;

end.
