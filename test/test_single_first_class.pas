program test_single_first_class;
{ Single (32-bit float) as a first-class type on the internal PXX-ABI call:
  Single var/literal/Double-narrow as argument, Single param read + arith,
  Single function return, mixed with Integer. Output-equality vs the
  Double-precision expectation (the values are exact in single precision).
  feature-single-first-class. }

function ScaleS(s: Single; k: Integer): Single;
begin ScaleS := s * k; end;

function AddS(a, b: Single): Single;
begin AddS := a + b; end;

function HalfS(x: Single): Single;
begin HalfS := x / 2.0; end;

function FromIntS(n: Integer): Single;
begin FromIntS := n; end;

var
  s: Single;
  d: Double;
begin
  { Single literal narrowed from a Double float-literal as argument. }
  writeln(ScaleS(1.5, 3):0:4);        { 4.5000 }
  { Single variable passed to a Single parameter. }
  s := 2.25;
  writeln(ScaleS(s, 4):0:4);          { 9.0000 }
  { Two Single params + arith. }
  writeln(AddS(1.25, 2.5):0:4);       { 3.7500 }
  { Single function return fed straight into another call. }
  writeln(HalfS(AddS(3.0, 5.0)):0:4); { 4.0000 }
  { int -> Single. }
  writeln(FromIntS(7):0:4);           { 7.0000 }
  { Double value narrowed into a Single arg. }
  d := 6.5;
  writeln(ScaleS(d, 2):0:4);          { 13.0000 }
  { Single result stored back into a Single var, then reused. }
  s := AddS(0.5, 0.25);
  writeln(s:0:4);                     { 0.7500 }
end.
