unit platgreet;
{ PAL backend-selection demo: the posix implementation of platgreet, chosen by
  putting test/unitpath/posix/ on the unit search path (-Fu / -I). }
interface
function PlatName: AnsiString;

implementation

function PlatName: AnsiString;
begin
  Result := 'posix';
end;

end.
