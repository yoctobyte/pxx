program test_cross_float_return;
{ Cross float function results (feature-cross-float-returns). Exercises Double
  function returns, Double params, and int->float in a returned value. The cross
  suite compares the target's output to the x86-64 oracle. }

function Half(x: Double): Double;
begin Half := x / 2.0; end;

function Sum(a, b: Double): Double;
begin Sum := a + b; end;

function FromInt(n: Integer): Double;
begin FromInt := n; end;

var d: Double;
begin
  writeln(Half(5.0):0:4);          { 2.5000 }
  writeln(Sum(1.5, 2.25):0:4);     { 3.7500 }
  writeln(FromInt(7):0:4);         { 7.0000 }
  d := Half(10.0) + Sum(0.5, 0.25);
  writeln(d:0:4);                  { 5.7500 }
end.
