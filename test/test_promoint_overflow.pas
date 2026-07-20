program test_promoint_overflow;
{ A promotable int TRAPS on overflow — it never wraps. Exits with runtime error
  215 (EIntOverflow); the Makefile asserts that exit code. Without the trap this
  prints 25! mod 2^64 and exits 0. }
var a: PromoInt;
    i: Integer;
begin
  a := 1;
  for i := 1 to 25 do
    a := a * i;
  Writeln(a);
end.
