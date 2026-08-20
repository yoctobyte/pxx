{ Deliberately the SAME unit name as test/cpasunit/mymod.pas, with a different
  body, so that a C file including both is refused. A unit's identity here is
  its NAME, so without the refusal the second include is a silent no-op and
  every mymod_pas_* would resolve to the first file. }
unit mymod;
interface
function Twice(x: Integer): Integer;
implementation
function Twice(x: Integer): Integer;
begin
  Twice := x * 3;
end;
end.
