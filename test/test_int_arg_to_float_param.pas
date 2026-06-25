program test_int_arg_to_float_param;
{ Regression: an integer argument passed to a float (Double) parameter must be
  converted to float at the call site — the ABI carries a float as its IEEE bits,
  so passing raw integer bits made the callee read ~0. This silently zeroed e.g.
  `V(1,1,1)` with Double params, breaking all record/vector math built on it.
  (root cause behind bug-float-field-record-function-return for Double records.) }
type Vec3 = record x, y, z: Double end;
function Scl(x: Double): Double;
begin Scl := x * 10; end;
function V(x, y, z: Double): Vec3;
begin V.x := x; V.y := y; V.z := z; end;
function VScale(a: Vec3; s: Double): Vec3;
begin VScale.x := a.x * s; VScale.y := a.y * s; VScale.z := a.z * s; end;
function VAdd(a, b: Vec3): Vec3;
begin VAdd.x := a.x + b.x; VAdd.y := a.y + b.y; VAdd.z := a.z + b.z; end;
var d: Double; n: Integer; z: Vec3;
begin
  d := Scl(8);            writeln(d:0:1);        { 80.0  int literal -> Double }
  n := 5; d := Scl(n);    writeln(d:0:1);        { 50.0  int var -> Double }
  z := V(1, 2, 3);        writeln(z.x:0:1, ' ', z.y:0:1, ' ', z.z:0:1);   { 1.0 2.0 3.0 }
  z := VAdd(VScale(V(1, 1, 1), 0.5), V(2, 2, 2));
  writeln(z.x:0:3, ' ', z.y:0:3, ' ', z.z:0:3);  { 2.500 2.500 2.500 }
end.
