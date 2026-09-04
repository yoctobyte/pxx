{$mode objfpc}
program test_inline_float_result_narrows;

{ The FLOAT ARM of test_inline_result_narrows, and it must be run at -O3.

  Shape 1 retains the RHS expression and DROPS the assignment, and a conversion
  to the declared result type lives in that store. The ordinal guard added for
  bug-a-function-result-assignment-does-not-narrow-to-the-result-type tests
  TypeIsOrdinal on BOTH sides, so it could not see a conversion into a FLOAT
  result. Admitting tySingle/tyDouble to the inliner (-O3) opened that arm:

    D2S(1/3) returned 0.33333333333333331 -- the full Double -- at -O3,
             where the Single value is 0.33333334326744080
    I2S(16777217) returned 16777217, where Single rounds to 16777216

  Both were correct at -O0/-O2 and correct out-of-line, so ONLY an -O3 arm can
  catch this. Float-result cases whose RHS kind is not already the result kind
  now go to shape 3, which stores through a properly typed Result temp.

  Rows 5-8 must NOT change: they widen, or already match the result kind, so
  they still take shape 1. They are here so a future guard cannot pass by
  disabling float inlining altogether -- the same positive control the ordinal
  test carries.
  feature-opt-inline-float-and-record-returning-leaves }

function D2S(a: Double): Single;      begin D2S := a; end;
function I2S(a: Integer): Single;     begin I2S := a; end;
function ExprS(a, b: Double): Single; begin ExprS := a * b; end;
function I2Sb(a: Int64): Single;      begin I2Sb := a; end;
function S2D(a: Single): Double;      begin S2D := a; end;
function I2D(a: Integer): Double;     begin I2D := a; end;
function SameD(a: Double): Double;    begin SameD := a * 2.0; end;
function SameS(a: Single): Single;    begin SameS := a * 2.0; end;

var d: Double;
begin
  d := D2S(1.0 / 3.0);   writeln(d:0:17);   { 0.33333334326744080 — narrowed }
  d := I2S(16777217);    writeln(d:0:1);    { 16777216.0 — Single cannot hold 16777217 }
  d := ExprS(1.0/3.0, 1.0); writeln(d:0:17);{ 0.33333334326744080 — narrowed }
  d := I2Sb(16777217);   writeln(d:0:1);    { 16777216.0 }
  d := S2D(0.25);        writeln(d:0:17);   { 0.25 — widening, shape 1, unchanged }
  d := I2D(16777217);    writeln(d:0:1);    { 16777217.0 — Double holds it exactly }
  d := SameD(1.5);       writeln(d:0:17);   { 3.0 — same kind, unchanged }
  d := SameS(1.5);       writeln(d:0:17);   { 3.0 — same kind, unchanged }
end.
