{ Low(Int64) with -1: the one operand pair the inline tier cannot compute.

  Found by sweeping every operator against a Python oracle over 4770 operand
  pairs — it was the ONLY failure, and it is exactly the pair a hand-written
  test never thinks to try.

  x86 raises SIGFPE for `Low(Int64) div -1` rather than wrapping, because the
  true quotient 2^63 does not fit the register. `mod` is the same instruction,
  so it traps too even though its answer (0) fits. And `*` traps in its own
  OVERFLOW ORACLE: that oracle is a division by the right operand, so probing
  Low(Int64) * -1 performed the trapping division while checking whether the
  multiply had overflowed.

  All five inline paths are guarded now — Div, Mod, Mul, and the Python-flavoured
  FloorDiv/FloorMod — each falling through to the bignum tier, which represents
  2^63 exactly. NilPy reaches the floor pair via `//` and `%`; that side is
  covered by test_nilpy_int_promotion_default. }
program t;
uses promocore;
var x, y, z: PromoInt;
begin
  x := -9223372036854775808;
  y := -1;

  z := x * y;    writeln(PXXPromoToStr(@z));   { 2^63, not a SIGFPE }
  z := x div y;  writeln(PXXPromoToStr(@z));   { 2^63 }
  z := x mod y;  writeln(PXXPromoToStr(@z));   { 0 }

  { the neighbours must be untouched by the guard }
  z := x div 1;   writeln(PXXPromoToStr(@z));
  z := x mod 1;   writeln(PXXPromoToStr(@z));
  z := x * 1;     writeln(PXXPromoToStr(@z));
  x := -9223372036854775807;
  z := x div y;   writeln(PXXPromoToStr(@z));
  z := x * y;     writeln(PXXPromoToStr(@z));
  { and a value already on the HEAP tier divided by -1 }
  x := 1; x := x shl 70;
  z := x div y;   writeln(PXXPromoToStr(@z));
end.
