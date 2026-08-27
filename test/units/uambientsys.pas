unit uambientsys;
{ A unit that calls the elementary math functions with NO `uses` clause at all
  — FPC declares sqrt/ln/exp/sin/cos/arctan/pi in the System unit, so this is
  the portable spelling and FPC's own compiler sources use it. pxx keeps them
  in the `math` unit and pulls it in ambiently, the same way `textfile` is
  pulled for Text/Assign.
  bug-p-the-system-math-and-thread-surfaces-are-not-ambient-in-units }
interface

function Hypot2(a, b: Double): Double;
function LogSum(x: Double): Double;
function Circle(r: Double): Double;

implementation

function Hypot2(a, b: Double): Double;
begin
  Hypot2 := sqrt(a * a + b * b);
end;

function LogSum(x: Double): Double;
begin
  LogSum := ln(x) + exp(0.0) + sin(0.0) + cos(0.0) + arctan(0.0);
end;

function Circle(r: Double): Double;
begin
  Circle := pi * r * r;
end;

end.
