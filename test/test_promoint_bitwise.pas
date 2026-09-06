{ Promotable-int bitwise ops with Python two's-complement semantics.
  Drives the uforth DO/LOOP unsigned-mask idiom that motivated them.

  AND IT IS HALF OF A TWO-FILE GUARD ON THE LITERAL TAG. `mask` below is a
  decimal in [2^63, 2^64), the one band where a literal's tag has two defensible
  readings: unsigned-QWord (right for arithmetic) and exact-digits (right for a
  promo slot). One predicate decides both, and MOVING IT EITHER WAY BREAKS
  EXACTLY ONE OF THESE TWO FILES:

    narrowed  -> this file. 10e670503 retagged the band to tyUInt64, which took
                 it out of IsWideIntLit, so PromoInt read the WRAPPED value and
                 `mask` became -1. Rows 1 and 3 went red. Fixed 2026-09-06 by
                 splitting the predicate (WideLitHasDigits, ast_arena.inc).
    widened   -> test_a_decimal_literal_above_high_int64_is_a_qword.pas, which
                 declares NO PromoInt and therefore does not load promocore, so
                 a widened predicate routes an ordinary QWord program into the
                 promo runtime and it FAILS TO COMPILE.

  THE ABSENCE OF PromoInt IN THAT SIBLING IS THE LOAD-BEARING PART and it is
  invisible from here. A guard for the widening direction cannot live in THIS
  file: declaring PromoInt loads promocore, the promo route silently starts
  working, and the broken predicate reads as correct. Measured 2026-09-06 —
  that is exactly how a wrong fix got past a band probe that declared one.
  regression-test-core-test-promoint-bitwise }
program test_promoint_bitwise;
var mask, a, b: PromoInt;
begin
  mask := 18446744073709551615;   { 2^64-1 }

  { AND with an all-ones mask reinterprets a negative as unsigned 64-bit }
  a := 4; a := a - 5;             { -1 }
  a := a and mask;
  writeln(a);                     { 18446744073709551615 }

  b := 5; b := b - 5;            { 0 }
  b := b and mask;
  writeln(b);                     { 0 }

  { unsigned compare after masking (uforth _loop_crossed) }
  if a > b then writeln('crossed') else writeln('not');   { crossed }

  { shift-left past 64 bits (Pascal `shr` lexes as an identifier, so the shift
    RIGHT path is exercised by the NilPy `>>` tests instead) }
  a := 1; a := a shl 64;
  writeln(a);                     { 18446744073709551616 }

  { OR / XOR }
  a := 240; b := 15;
  writeln(a or b);                { 255 }
  writeln(a xor b);               { 255 }
  a := 255; b := 15;
  writeln(a and b);               { 15 }
end.
