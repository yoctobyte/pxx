program test_const_before_ctor;
uses const_before_ctor_unit;
var t: TThing;
begin
  t := TThing.Create;
  writeln(t.V);      { 7 + 5 = 12 }
  t.Bump;
  writeln(t.V);      { 12 + 100 = 112 }
end.
