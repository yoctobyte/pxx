{ FPC declares the elementary math functions in System, so these compile with
  no `uses` at all. pxx keeps them in the `math` unit (618 lines of
  correctly-rounded numerics, not worth duplicating into builtin) and pulls it
  in on demand when one of the names appears as a call. Values are
  FPC-verified. The `ln` variable is the negative half: a bare identifier that
  is NOT a call must not drag the unit in, and must still shadow cleanly when
  the unit IS pulled by a sibling call. }
program test_math_intrinsics_no_uses;
var ln: Integer;
begin
  writeln(sqrt(16.0):0:1);
  writeln(sin(0.0):0:1);
  writeln(cos(0.0):0:1);
  writeln(exp(0.0):0:1);
  writeln(arctan(0.0):0:1);
  writeln(Pi:0:5);
  ln := 7;
  writeln(ln);
end.
