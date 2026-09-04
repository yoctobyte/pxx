unit unit_uses_in_bare;
{ Named by a BARE file name -- `uses unit_uses_in_bare in 'unit_uses_in_bare.pas'` --
  which is the shape every generated .dpr writes and the one that did not parse
  at all. It lives beside the test rather than in the units subdirectory
  precisely because the bare form resolves against the DIRECTORY OF THE FILE
  HOLDING THE CLAUSE. feature-p-uses-a-unit-in-an-explicit-file }
interface
function BareTwice(x: Integer): Integer;
implementation
function BareTwice(x: Integer): Integer;
begin
  BareTwice := x * 2;
end;
end.
