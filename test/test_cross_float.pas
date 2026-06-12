program test_cross_float;

var
  s1, s2: Single;
  d1, d2: Double;
  i: Integer;
begin
  s1 := 1.5;
  s2 := 2.0;
  writeln(s1 + s2);
  writeln(s1 - s2);
  writeln(s1 * s2);
  writeln(s1 / s2);

  d1 := 5.5;
  d2 := 2.0;
  writeln(d1 + d2);
  writeln(d1 - d2);
  writeln(d1 * d2);
  writeln(d1 / d2);

  { Mixed type operations }
  i := 3;
  writeln(d1 + i);
  writeln(i * s1);
  writeln(d1 / i);
  writeln(i / 2);

  { Comparisons }
  writeln(d1 > d2);
  writeln(d1 < d2);
  writeln(d1 = 5.5);
  writeln(d1 <> 5.5);
  writeln(d1 >= d2);
  writeln(d1 <= d2);

  { Intrinsics }
  writeln(Trunc(d1));
  writeln(Round(d1));
  writeln(Frac(d1));
  writeln(Int(d1));

  { Floating point formatting }
  writeln(d1:0:2);
  writeln(d1:0:6);
  writeln(0.123456:0:4);
end.
