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

end.
