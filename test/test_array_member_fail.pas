{ %FAIL-style negative: .member on an array variable (tarrconstr8). }
program test_array_member_fail;
type TLongIntArray = array of LongInt;
var arr: TLongIntArray;
begin
  arr := arr.Create(1, 2);
end.
