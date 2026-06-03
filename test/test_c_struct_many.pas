{ Exercises the raised record-table cap: 40 C structs (more than the old
  MAX_UCLASS=32) are all laid out, so a high-index struct is usable. Hazard
  structs (bitfield, anonymous union) sit in the same header and must fall back
  to opaque pointers without disturbing the POD structs' layout. }
program test_c_struct_many;
uses cmany;
var a: S1; z: S40;
begin
  a.a := 10; a.b := 20;
  z.a := 300; z.b := 4000;
  writeln(a.a + a.b);    { 30 }
  writeln(z.a + z.b);    { 4300 }
end.
