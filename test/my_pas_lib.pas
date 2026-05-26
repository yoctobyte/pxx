unit my_pas_lib;
interface
function pascal_mul(a: Integer; b: Integer): Integer;
implementation
function pascal_mul(a: Integer; b: Integer): Integer;
begin
  pascal_mul := a * b;
end;
end.
