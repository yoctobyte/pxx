{ The Pascal half of test/c_pascal_unit_init_runs.c.
  bug-c-a-pascal-units-initialization-never-runs-under-a-c-main }
unit c_pascal_unit_init_unit;
interface
var Ready: Integer;
function GetReady: Integer;
implementation
function GetReady: Integer;
begin
  Result := Ready;
end;
initialization
  Ready := 42;
  WriteLn('unit init ran');
end.
