program test_float_write;
{ Float Write/WriteLn. Fixed form (:w:n) is exact; bare writeln uses
  scientific notation. All values here are exactly representable, so the
  printed digits are deterministic. Rounding is IEEE round-to-nearest-even. }
begin
  { fixed-decimal }
  writeln(3.5:0:2);       { 3.50 }
  writeln(3.5:0:0);       { 4   (round half to even) }
  writeln(-2.75:0:3);     { -2.750 }
  writeln(1.0:0:1);       { 1.0 }
  writeln(0.0:0:2);       { 0.00 }
  writeln(10.5:0:1);      { 10.5 }
  { scientific (bare) }
  writeln(1.0);           {  1.000000000000000E+000 }
  writeln(-2.0);          { -2.000000000000000E+000 }
  writeln(0.0);           {  0.000000000000000E+000 }
  writeln(3.5);           {  3.500000000000000E+000 }
  writeln(1234.5);        {  1.234500000000000E+003 }
end.
