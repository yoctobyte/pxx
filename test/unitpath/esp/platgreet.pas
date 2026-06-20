unit platgreet;
{ PAL backend-selection demo: the esp implementation of platgreet, chosen by
  putting test/unitpath/esp/ on the unit search path (-Fu / -I). Same unit name
  as the posix backend — only the search path differs. }
interface
function PlatName: AnsiString;

implementation

function PlatName: AnsiString;
begin
  Result := 'esp';
end;

end.
