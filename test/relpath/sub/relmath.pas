unit relmath;
interface
uses '../relstr';
function AddTwo(a: Integer; b: Integer): Integer;
implementation
function AddTwo(a: Integer; b: Integer): Integer;
begin
  AddTwo := Triple(a) + b;
end;
end.
