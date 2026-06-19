unit strutils;
{ Minimal string / conversion helpers, grown on demand by the demo apps. Pure
  Pascal, FPC-compatible names. Track B (libraries); built only with the pinned
  stable compiler. See docs/dev/parallel-tracks.md.

  NOTE: in FPC, IntToStr lives in SysUtils. The compiler currently hard-skips
  `uses sysutils` (parser.inc treats it as a no-op), so a real lib/rtl/sysutils
  cannot load yet -- see ticket bug-sysutils-unit-hard-skipped. Until that lands,
  these conversion helpers live here in strutils (also a real FPC unit). }

interface

{ Integer -> decimal string. Handles negatives. }
function IntToStr(value: Integer): AnsiString;

{ 1-based substring. count is clamped to the string end; out-of-range index
  yields ''. Classic Turbo/FPC Copy semantics for AnsiString. }
function Copy(const s: AnsiString; index, count: Integer): AnsiString;

{ Strip leading/trailing characters <= ' ' (spaces, tabs, control). }
function Trim(const s: AnsiString): AnsiString;

implementation

function IntToStr(value: Integer): AnsiString;
var s: AnsiString; neg: Boolean; d: Integer;
begin
  if value = 0 then
  begin
    Result := '0';
    Exit;
  end;
  neg := value < 0;
  if neg then value := -value;
  s := '';
  while value > 0 do
  begin
    d := value mod 10;
    s := Chr(Ord('0') + d) + s;
    value := value div 10;
  end;
  if neg then s := '-' + s;
  Result := s;
end;

function Copy(const s: AnsiString; index, count: Integer): AnsiString;
var i, n, last: Integer; r: AnsiString;
begin
  n := Length(s);
  if index < 1 then index := 1;
  if count < 0 then count := 0;
  last := index + count - 1;
  if last > n then last := n;
  r := '';
  i := index;
  while i <= last do
  begin
    r := r + s[i];
    i := i + 1;
  end;
  Result := r;
end;

function Trim(const s: AnsiString): AnsiString;
var a, b: Integer;
begin
  a := 1;
  b := Length(s);
  while (a <= b) and (s[a] <= ' ') do a := a + 1;
  while (b >= a) and (s[b] <= ' ') do b := b - 1;
  Result := Copy(s, a, b - a + 1);
end;

end.
