{$mode objfpc}
{ On ESP (xtensa / riscv32) Single is first-class: a float-producing operator
  whose operands are both floats keeps their depth, so two Singles make a
  Single and no soft-double tax is paid by code that never asked for one.

  But an ORDINAL/ORDINAL operator — `1 / 3` — has no operand to take a depth
  from, and it used to take the target's NATIVE depth, which is Single there. A
  declared `Double` then quietly held float32's 1/3 (7 significant digits), and
  the same source printed different numbers on ESP than on every other target.
  It stayed invisible until write(v:w:d) became exact enough to show the digits.

  So when the operands supply no depth, the REQUESTED TARGET TYPE decides
  (user, 2026-08-11, decide-esp-single-depth-division-into-a-declared-double).

  Rows 2 and 3 are the controls that say this is not "always widen": a Single
  target still gets a single divide, and an expression that already HAS a float
  operand is left entirely alone.

  Every row must read identically on all six targets; the file is checked
  against x86-64's answers, which are the ordinary Double ones.
  decide-esp-single-depth-division-into-a-declared-double }
program test_esp_float_depth_from_target;
var d: Double; s: Single; a, b: Double;
begin
  a := 1; b := 3;
  d := 1 / 3;        WriteLn(d:0:20);   { target Double -> double depth }
  s := 1 / 3;        WriteLn(s:0:20);   { target Single -> single, unchanged }
  d := a / b;        WriteLn(d:0:20);   { an operand already decided }
  d := 2 / 4;        WriteLn(d:0:20);   { exact in either depth }
  d := 1 / 3 + 0.5;  WriteLn(d:0:20);   { NESTED: the outer + has a float
                                          operand, the inner / has none }
  d := (1 / 3) * (1 / 3);
  WriteLn(d:0:20);
  WriteLn('ESP FLOAT DEPTH OK');
end.
