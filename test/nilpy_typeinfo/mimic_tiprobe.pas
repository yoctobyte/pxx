unit mimic_tiprobe;
{$MODE PXX}
interface
uses pylib, typinfo, sysutils;
function tiname(q: Pointer): AnsiString;
implementation
function tiname(q: Pointer): AnsiString;
var p: PTypeInfo;
begin
  p := PTypeInfo(q);
  Result := IntToStr(Ord(p^.Kind)) + ' ' + p^.NamePtr^;
end;
end.
