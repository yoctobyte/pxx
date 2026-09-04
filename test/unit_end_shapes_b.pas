unit unit_end_shapes_b;
{ The classic Turbo-Pascal `begin ... end.` unit initialization form, whose
  closing `end.` doubles as the unit terminator -- the one legitimate shape
  that reaches the tkEnd arm by a different route than a plain `end.` does.
  Separate unit because a unit cannot carry both this and `initialization`.
  bug-p-a-stray-end-at-unit-implementation-top-level-is-silently-skipped }
interface

function ShapesBValue: Integer;

implementation

var gB: Integer;

function ShapesBValue: Integer;
begin
  ShapesBValue := gB;
end;

begin
  gB := 32;
end.
