program test_promoint;
{ Promotable int stage 2: storage, checked arithmetic, Write.
  The point of the type is that overflow TRAPS instead of wrapping, so the
  overflow cases are exercised in a child process via the exit code. }
var a, b: PromoInt;
    i: Integer;
    s: Int64;
begin
  { zero-init: an untouched promo variable reads as inline 0 }
  Writeln(a);

  a := 5;
  b := a + 7;
  Writeln(a);
  Writeln(b);
  Writeln(a * b);
  Writeln(b - a);
  Writeln(b div a);
  Writeln(b mod a);

  { negatives must print SIGNED (they printed unsigned before the write arm) }
  b := -5;
  Writeln(b);
  Writeln(b * b);

  { mixing with an ordinary integer yields a promotable int }
  s := 3;
  a := s + 4;
  Writeln(a);
  a := 20;
  b := 1;
  for i := 1 to 20 do
    b := b * i;
  Writeln(b);

  { comparisons unbox to the payload }
  if b > a then Writeln('gt');
  if (-1 * a) < 0 then Writeln('neg');

  a := 0;
  Writeln(a);
end.
