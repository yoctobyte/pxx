program t;
var i: Int64; f: Double;
begin
  i := Trunc(3.78);   writeln(i);    { 3 }
  i := Trunc(-3.78);  writeln(i);    { -3 }
  i := Round(3.78);   writeln(i);    { 4 }
  i := Round(2.5);    writeln(i);    { 2 (banker's) }
  i := Round(3.5);    writeln(i);    { 4 }
  f := Frac(3.75);    writeln(f:0:4);{ 0.7500 }
  f := Int(3.75);     writeln(f:0:1);{ 3.0 }
end.
