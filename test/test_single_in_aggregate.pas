program test_single_in_aggregate;
{ Regression: a Single (4-byte float) record FIELD or array ELEMENT must store
  and load correctly — the value model carries floats as double bits, so a field
  store needs cvtsd2ss before the 4-byte write and a field load needs cvtss2sd
  after the 4-byte read. Previously the raw 4-byte store/load mishandled the
  double bits and the field read back 0 (bug-single-field-element-in-aggregate). }
type S3 = record a, b, c: Single end;
function Mk(x: Single): S3;
begin Mk.a := x; Mk.b := x * 2; Mk.c := x * 3; end;
var s: S3; arr: array[0..2] of Single; i: Integer;
begin
  s.a := 1.5; s.b := 2.5; s.c := 3.5;
  writeln(s.a:0:1, ' ', s.b:0:1, ' ', s.c:0:1);     { 1.5 2.5 3.5 }
  arr[0] := 9.5; arr[1] := 8.25; arr[2] := 7.125;
  writeln(arr[0]:0:3, ' ', arr[1]:0:3, ' ', arr[2]:0:3);   { 9.500 8.250 7.125 }
  s := Mk(2);                                          { Single-field record result }
  writeln(s.a:0:1, ' ', s.b:0:1, ' ', s.c:0:1);     { 2.0 4.0 6.0 }
  s.a := 10;                                           { int -> Single field }
  writeln(s.a:0:1);                                    { 10.0 }
end.
