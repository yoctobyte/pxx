program test_open_array_of_variant;
{ Open `array of Variant` parameters (bug-a-open-array-of-variant-silent-
  miscompile): the call-boundary scalar->Variant BOXING branch keyed on the
  param's TypeKind — which for an array param is the ELEMENT type — and boxed
  the whole array handle into a variant temp, so the callee's Length read
  stack garbage and every element aliased the temp. Covers a dynamic and a
  fixed array argument, Length inside the callee, and per-element reads. }
type
  PVRec = ^TVRec;
  TVRec = record VType, Payload: Int64; end;

function mkv(n: Int64): Variant;
begin
  PVRec(@Result)^.VType := 2;
  PVRec(@Result)^.Payload := n;
end;

function vpay(const v: Variant): Int64;
begin
  vpay := PVRec(@v)^.Payload;
end;

function sum(const a: array of Variant): Int64;
var i: Integer;
begin
  sum := 0;
  for i := 0 to High(a) do sum := sum + vpay(a[i]);
end;

var
  d: array of Variant;
  f: array[0..2] of Variant;
  solo: Variant;
begin
  SetLength(d, 3);
  d[0] := mkv(10); d[1] := mkv(20); d[2] := mkv(5);
  writeln(sum(d));                 { 35 }
  f[0] := mkv(1); f[1] := mkv(2); f[2] := mkv(4);
  writeln(sum(f));                 { 7 }
  { plain (non-array) Variant param still boxes a scalar }
  solo := mkv(9);
  writeln(vpay(solo));           { 9 }
end.
