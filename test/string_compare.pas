program StringCompare;

function IsDataOff(const field: AnsiString): Boolean;
begin
  IsDataOff := field = 'DataOff';
end;

function IsAnsiString(const name: AnsiString): Boolean;
var
  lo: AnsiString;
begin
  lo := name;
  IsAnsiString := lo = 'ansistring';
end;

var
  a: AnsiString;

begin
  a := 'DataOff';
  if IsDataOff(a) then writeln(1) else writeln(0);
  a := 'CodePos';
  if IsDataOff(a) then writeln(0) else writeln(1);
  a := 'TFixup';
  if IsAnsiString(a) then writeln(0) else writeln(1);
end.
