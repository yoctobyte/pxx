unit dns_config;
{ POSIX resolver configuration parsing for the dns_wire path
  (feature-dns-resolver-library): dotted-quad IPv4 parsing and `/etc/resolv.conf`
  nameserver extraction. Pure string -> data, no PAL/network dependency, so it
  is tested offline; a caller reads the file via PAL and hands the text in.

  First slice: `nameserver` lines only. `search`/`domain`/`options ndots` and
  `/etc/hosts` are later slices. Public DNS is never assumed — an empty result
  means "no configured resolver", which the resolver must treat as a hard error
  unless the caller explicitly opts into a fallback. }

interface

uses dns_wire_core;   { TDnsIpv4Array, DNS_MAX_IPS }

{ Parse s[startIdx..endIdx] (1-based, inclusive) as a dotted-quad IPv4 literal
  into ip (host byte order). Returns False on any malformed input. }
function DnsParseIpv4(const s: string; startIdx, endIdx: Integer; var ip: LongWord): Boolean;

{ Extract `nameserver <ipv4>` entries from resolv.conf text into ns[0..count-1]
  (host byte order, up to DNS_MAX_IPS). Lines may have leading whitespace; `#`
  and `;` start comments. Returns the nameserver count (also via count). }
function DnsParseResolvConf(const text: string; var ns: TDnsIpv4Array; var count: Integer): Integer;

{ Look up `name` in /etc/hosts text (the "files" half of "files dns"). Each line
  is `<ipv4> <hostname> [aliases...]`; hostname match is case-insensitive; `#`
  starts a comment. Returns True with ip set (host byte order) on the first
  match. IPv6 host lines are skipped (A/IPv4 slice only). }
function DnsLookupHosts(const text: string; const name: string; var ip: LongWord): Boolean;

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

function IsSpace(c: Char): Boolean;
begin
  IsSpace := (c = ' ') or (c = #9) or (c = #13);
end;

{ If text[ls..le] is a `nameserver <ipv4>` line, parse the address into ip and
  return True. Leading whitespace and trailing comment/whitespace are tolerated. }
function ParseNameserverLine(const text: string; ls, le: Integer; var ip: LongWord): Boolean;
var
  p, k, tokStart, tokEnd: Integer;
  kw: string;
begin
  ParseNameserverLine := False;
  kw := 'nameserver';
  p := ls;
  while (p <= le) and IsSpace(text[p]) do p := p + 1;
  { match the keyword }
  if (le - p + 1) < Length(kw) then Exit;
  for k := 1 to Length(kw) do
    if text[p + k - 1] <> kw[k] then Exit;
  p := p + Length(kw);
  { at least one separator must follow }
  if (p > le) or (not IsSpace(text[p])) then Exit;
  while (p <= le) and IsSpace(text[p]) do p := p + 1;
  if p > le then Exit;
  { the address token runs to the next space or comment }
  tokStart := p;
  tokEnd := p;
  while (tokEnd <= le) and (not IsSpace(text[tokEnd])) and
        (text[tokEnd] <> '#') and (text[tokEnd] <> ';') do
    tokEnd := tokEnd + 1;
  ParseNameserverLine := DnsParseIpv4(text, tokStart, tokEnd - 1, ip);
end;

function DnsParseResolvConf(const text: string; var ns: TDnsIpv4Array; var count: Integer): Integer;
var
  i, ls, n: Integer;
  ip: LongWord;
begin
  count := 0;
  n := Length(text);
  ls := 1;
  for i := 1 to n do
  begin
    if text[i] = #10 then
    begin
      if (i - 1 >= ls) and ParseNameserverLine(text, ls, i - 1, ip) then
      begin
        if count < DNS_MAX_IPS then
        begin
          ns[count] := ip;
          count := count + 1;
        end;
      end;
      ls := i + 1;
    end;
  end;
  { trailing line with no final newline }
  if (ls <= n) and ParseNameserverLine(text, ls, n, ip) then
  begin
    if count < DNS_MAX_IPS then
    begin
      ns[count] := ip;
      count := count + 1;
    end;
  end;
  DnsParseResolvConf := count;
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

end.
