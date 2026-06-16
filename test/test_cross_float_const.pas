program test_cross_float_const;
{ Float constant and variable initializers: scalar and array of Double. Were
  rejected (ConstEval is integer-only). Byte-identical on every target. }
const
  Pi: Double = 3.14159;
  Coef: array[0..3] of Double = (1.5, 2.5, 0.25, 4.0);
var
  Scale: Double = 2.0;
  Tab: array[0..2] of Double = (10.5, 20.25, 5.0);
  i: Integer; s: Double;
begin
  writeln('pi=', Pi:0:5, ' scale=', Scale:0:2);
  s := 0; for i := 0 to 3 do s := s + Coef[i];
  writeln('coef=', s:0:2);
  s := 0; for i := 0 to 2 do s := s + Tab[i];
  writeln('tab=', s:0:2, ' c2=', Coef[2]:0:2);
end.
