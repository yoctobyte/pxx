{ Regression: general TRec(ptr)^.field reinterpret cast, read and write.
  feature-general-typename-cast (record-name case; PRec/TClass already worked). }
program test_record_typecast;
type TRec = record a, b: Integer; end;
var raw: array[0..1] of Integer; p: Pointer;
begin
  raw[0] := 0; raw[1] := 0;
  p := @raw;
  TRec(p)^.a := 77;          { write through a record reinterpret }
  TRec(p)^.b := 88;
  writeln(raw[0]);           { 77 }
  writeln(raw[1]);           { 88 }
  writeln(TRec(p)^.a);       { 77 read }
  writeln(TRec(p)^.b);       { 88 read }
  writeln(TRec(p)^.a + TRec(p)^.b);  { 165 }
end.
