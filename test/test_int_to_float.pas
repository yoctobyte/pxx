program test_int_to_float;
{ Regression for feature-int-to-float-assign: a pure-integer RHS assigned into a
  float LHS (variable, record field, array element) must be CONVERTED (cvtsi2sd),
  not bit-copied. Float-typed RHS (n * 1.0) keeps the existing bit-copy path. }
type TR = record d: Double; end;
var
  d: Double; n: Integer; i: Integer;
  r: TR; a: array[0..2] of Double;
begin
  d := 1;        writeln(d:0:4);     { 1.0000  (literal int -> float) }
  n := 7; d := n; writeln(d:0:4);    { 7.0000  (int var -> float) }
  d := n * 1.0;  writeln(d:0:4);     { 7.0000  (float RHS, unchanged path) }
  n := 5;
  r.d := 3;      writeln(r.d:0:4);   { 3.0000  (int -> float field) }
  r.d := n;      writeln(r.d:0:4);   { 5.0000 }
  for i := 0 to 2 do a[i] := i;      { int -> float element }
  writeln(a[0]:0:4); writeln(a[1]:0:4); writeln(a[2]:0:4);  { 0/1/2 }
  a[1] := n;     writeln(a[1]:0:4);  { 5.0000 }
end.
