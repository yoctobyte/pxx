unit unit_c_bridge;
{ A Pascal unit whose implementation is a C translation unit. }
interface
function Twice(x: Integer): Integer;
implementation
uses './cbridge_via_unit.c';
function Twice(x: Integer): Integer;
begin
  Twice := cbridge_twice(x);
end;
end.
