{$mode objfpc}
program test_abs_sqr;

{ System intrinsics Abs / Sqr (integer + float), lowered to builtin helpers so
  the argument is evaluated once. FPC oracle: 5 7 / 49 / 3.50 / 6.25 / 43. }

var
  x: Integer;
begin
  writeln(Abs(-5), ' ', Abs(7));     { 5 7 }
  writeln(Sqr(7));                    { 49 }
  writeln(Abs(-3.5):0:2);            { 3.50 }
  writeln(Sqr(2.5):0:2);            { 6.25 }
  x := -42;
  writeln(Abs(x) + 1);               { 43 }
end.
