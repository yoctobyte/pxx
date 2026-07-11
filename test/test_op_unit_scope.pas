program test_op_unit_scope;

{ Operators declared in a used unit resolve at the program's use sites. }

uses uopfrac;

var
  x, y, s: TFrac;
begin
  CheckInsideUnit;               { in:5/6 }

  x.Num := 1; x.Den := 2;
  y.Num := 1; y.Den := 3;

  s := x + y;                    { 5/6 }
  writeln(s.Num, '/', s.Den);

  s := x / y;                    { 3/2 }
  writeln(s.Num, '/', s.Den);

  s := x * y;                    { 1/6 }
  writeln(s.Num, '/', s.Den);
end.
