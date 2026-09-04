unit mymod_in;
{ Reached by a path WITH a separator, so the bare-name normalisation must not
  touch it. feature-p-uses-a-unit-in-an-explicit-file }
interface
function PathThrice(x: Integer): Integer;
implementation
function PathThrice(x: Integer): Integer;
begin
  PathThrice := x * 3;
end;
end.
