program test_float_width;
{ Fixed-format float field width `:w:d` right-justifies in w columns, padding
  with leading spaces (FPC parity). Regression for bug-writeln-real-width.
  Over-width values are not truncated; rounding that carries a new integer digit
  is counted in the width. }
begin
  writeln('[', 3.14159:8:3, ']');   { [   3.142] }
  writeln('[', 1.5:10:2, ']');      { [      1.50] }
  writeln('[', -2.5:6:1, ']');      { [  -2.5] }
  writeln('[', 123.456:9:2, ']');   { [   123.46] }
  writeln('[', 9.999:7:2, ']');     { [  10.00] (rounds up, carried digit) }
  writeln('[', 3.14:2:1, ']');      { [3.1] (value wider than field) }
  writeln('[', 0.0:5:2, ']');       { [ 0.00] }
  writeln('[', 1000.0:3:0, ']');    { [1000] }
end.
