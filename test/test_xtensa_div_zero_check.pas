program test_xtensa_div_zero_check;
{ Division by zero must raise Runtime error 200 on EVERY target, in all FOUR
  shapes: 32-bit div, 32-bit mod, 64-bit div, 64-bit mod. xtensa was the last
  target without a pre-divide check -- the other five landed 2026-08-23 -- so
  `10 div 0` produced whatever quos or the __pxx_divsi3 soft helper left in the
  register and the program carried on with it.

  SHAPE IS SELECTED BY ARGUMENT COUNT and the Makefile runs this FOUR times, 0
  to 3 args. An earlier version of this file put the other three shapes in an
  `else` that the harness never entered: it passed on every target while
  exercising exactly one path. If you change the selection, check that each
  branch is actually reached rather than that the run is green.

  The divisor is the GLOBAL `zero`, not a literal, and `bump` makes it provably
  non-constant -- a folded `10 div 0` would be a compile-time question and would
  never reach the emitted check at all.

  xtensa also has TWO DIVIDE SHAPES and one run covers one: hardware quos/rems,
  and the software __pxx_divsi3/__pxx_modsi3 path under --xtensa-cpu=lx6. The
  Makefile runs both. bug-a-the-div-by-zero-check-is-still-missing-on-xtensa }
var
  zero: Integer;         { global => BSS => 0, and not foldable }
  a: Integer;
  x, y: Int64;
  sel: Integer;
begin
  sel := ParamCount;
  if sel > 100 then zero := 5;     { never taken; defeats a constant divisor }
  a := 10;
  x := 10;
  y := zero;
  WriteLn('start');
  if sel = 0 then WriteLn(a div zero)
  else if sel = 1 then WriteLn(a mod zero)
  else if sel = 2 then WriteLn(x div y)
  else WriteLn(x mod y);
  WriteLn('unreachable');
end.
