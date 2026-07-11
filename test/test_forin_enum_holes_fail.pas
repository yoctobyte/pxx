{ %FAIL-style negative: for-in over an enum with explicit ordinal jumps (tforin20). }
program test_forin_enum_holes_fail;
type T = (a1, b1=5);
var ch: T;
begin
  for ch in T do writeln(Ord(ch));
end.
