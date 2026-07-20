program test_promoint;
{ Promotable int: arbitrary precision. Values promote to a heap bignum on
  overflow and demote back when they fit again, so results are EXACT — every
  expectation here is CPython's answer for the same expression. }
var a, b, c: PromoInt;
    i: Integer;
    s: Int64;
    vv: Variant;
begin
  { zero-init: an untouched promo variable reads as inline 0 }
  Writeln(a);

  a := 5;
  b := a + 7;
  Writeln(b);
  Writeln(a * b);
  Writeln(b - a);
  Writeln(b div a);
  Writeln(b mod a);

  { negatives print signed }
  b := -5;
  Writeln(b);
  Writeln(b * b);

  { mixing with an ordinary integer stays promotable }
  s := 3;
  a := s + 4;
  Writeln(a);

  { comparisons go through the runtime, not the slot address }
  a := 5; b := 7;
  if a < b then Writeln('lt');
  if b > a then Writeln('gt');
  if a = 5 then Writeln('eq');
  a := 1; b := 1;
  if a = b then Writeln('same');

  { past Int64: 30! is exact, not wrapped }
  a := 1;
  for i := 1 to 30 do a := a * i;
  Writeln(a);
  b := a;
  Writeln(a - b);
  Writeln(a div 1000000);
  Writeln(a mod 1000000007);

  { negative bignum, and crossing back through zero }
  a := -1;
  for i := 1 to 25 do a := a * i;
  Writeln(a);
  c := 0;
  Writeln(c - a);

  { the Int64 boundary itself }
  a := 9223372036854775807;
  Writeln(a + 1);
  Writeln(a * 2);

  { WIDE LITERALS: a value past Int64 can be written down, not just computed.
    The lexer folds every literal to 64 bits, so these arrive as digit text. }
  a := 18446744073709551616;
  Writeln(a);
  a := -18446744073709551616;
  Writeln(a);
  Writeln(-a);
  a := 99999999999999999999999999999999;
  b := 100000000000000000000000000000000;
  Writeln(b - a);

  { VARIANT round trip. An inline value boxes as an ordinary VT_INT64; only a
    heap value takes the reserved VT_PROMO_INT64 tag, carrying its exact
    decimal as a managed string. }
  a := 42;
  vv := a;
  Writeln(vv);
  a := 1;
  for i := 1 to 30 do a := a * i;
  vv := a;
  Writeln(vv);
  c := 0;
  c := vv;
  Writeln(c);

  { DEMOTION: a value that grew and shrank is usable as an ordinary int again }
  a := 1;
  for i := 1 to 30 do a := a * i;
  for i := 1 to 30 do a := a div i;
  Writeln(a);
end.
