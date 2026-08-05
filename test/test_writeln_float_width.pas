program test_writeln_float_width;
{ Regression: the field WIDTH in writeln(d:w:n) must be honoured on every
  target, and counted AFTER rounding.

  PXXWriteFloatFixed took no width parameter, so i386/arm32/aarch64/riscv32 —
  every target that routes through it — printed `3.1416` where FPC prints
  `    3.1416`. Only x86-64 padded, via a hand-written emitter that in turn
  saturated the integer part at Int64 (writeln(1e20:0:2) ->
  9223372036854775809.00). Giving the helper a width let x86-64 become a shim
  too, so there is now ONE fixed-decimals formatter and no hand-written float
  formatter left on any target.

  The carry case is the one that makes the ordering matter: 9.96:6:1 rounds to
  10.0, gaining an integer digit, so padding counted before rounding would emit
  one column too many.
  bug-a-aarch64-float-field-width-ignored,
  bug-a-x86-64-writeln-fixed-saturates-at-int64 }
var d: Double;
begin
  d := 3.14159;  writeln('[', d:12:4, ']');
  d := -3.14159; writeln('[', d:12:4, ']');
  d := 9.96;     writeln('[', d:6:1, ']');    { rounding carry adds a digit }
  d := 0.5;      writeln('[', d:5:0, ']');
  d := -0.5;     writeln('[', d:5:0, ']');
  d := 123456.0; writeln('[', d:3:1, ']');    { width smaller than content }
  d := 0.0;      writeln('[', d:8:2, ']');
  d := 1e20;     writeln('[', d:30:2, ']');   { past 2^63 }
  d := -1e20;    writeln('[', d:30:2, ']');
  d := 3.14159;  writeln('[', d:0:2, ']');    { no width }
  writeln('OK');
end.
