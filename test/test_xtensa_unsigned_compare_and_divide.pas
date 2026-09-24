program test_xtensa_unsigned_compare_and_divide;
{ The Pascal half of test_xtensa_unsigned_compare_and_divide.c: a LongWord
  compare took the same SIGNED xtensa arm, so `1 < $FFFFFFFF` was FALSE. }
var a, b, one: LongWord; c: Cardinal;
begin
  a := $FFFFFFFF; b := $80000000; one := 1; c := 3000000000;
  WriteLn(one < a, ' ', a > one, ' ', b >= one, ' ', one <= b, ' ', a < b);
  WriteLn(a div 2, ' ', a mod 7, ' ', c div 1000, ' ', b div one);
end.
