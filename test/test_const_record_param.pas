program test_const_record_param;
{ A const record param larger than 8 bytes must arrive intact (passed by
  reference). Regression for the truncation that dropped all but field 1. }
type
  TPair = record a: Pointer; b: Pointer; end;
procedure Show(const v: TPair);
var x, y: Int64;
begin
  x := v.a; y := v.b;
  writeln(x, ' ', y);
end;
var p: TPair;
begin
  p.a := Pointer(111);
  p.b := Pointer(222);
  Show(p);
end.
