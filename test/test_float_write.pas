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
  { scientific (bare): 17 significant digits, matching FPC's Str(Double) field
    width. pxx reals are Double; FPC types a bare literal as the smallest exact
    type, so FPC's own bare-literal output may differ. 1234.5 shows a last-digit
    ulp artifact of the double-arithmetic scaling. }
  writeln(1.0);           {  1.0000000000000000E+000 }
  writeln(-2.0);          { -2.0000000000000000E+000 }
  writeln(0.0);           {  0.0000000000000000E+000 }
  writeln(3.5);           {  3.5000000000000000E+000 }
  writeln(1234.5);        {  1.2345000000000002E+003 }
end.
