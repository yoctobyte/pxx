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

end.
