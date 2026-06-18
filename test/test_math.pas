program TestMath;
uses math;
var x: Double;
begin
  writeln(Pi:0:8);
  writeln(Sqrt(2.0):0:8);
  writeln(Sqrt(16.0):0:8);
  writeln(Sqrt(2.25):0:8);
  writeln(Exp(1.0):0:8);
  writeln(Exp(0.0):0:8);
  writeln(Exp(2.5):0:8);
  writeln(Ln(2.0):0:8);
  writeln(Ln(10.0):0:8);
  writeln(Ln(2.718281828459045):0:8);
  writeln(Sin(0.0):0:8);
  writeln(Sin(1.0):0:8);
  writeln(Sin(3.14159265358979):0:8);
  writeln(Cos(0.0):0:8);
  writeln(Cos(1.0):0:8);
  writeln(ArcTan(1.0):0:8);
  writeln(ArcTan(0.5):0:8);
  writeln(Power(2.0, 10.0):0:8);
  writeln(Power(2.0, 0.5):0:8);
  writeln(Abs(-3.5):0:8);
  x := Sin(0.7) * Sin(0.7) + Cos(0.7) * Cos(0.7);
  writeln(x:0:8);
end.
