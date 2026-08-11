{$mode objfpc}
{ --strict-fpc reproduces FPC's SHIFT widths, asymmetry and all.

  The DEFAULT dialect deliberately diverges: a shift happens at NATIVE width and
  is never truncated, so `1 shl 40` is 2^40 rather than 0
  (decide-shift-operator-promotion-width — the user's call, "pxx truncating to
  32-bit is wrong"). Strict mode is where FPC's own answers live, and FPC's
  answers are not self-consistent:

    * a shift over a VARIABLE wraps at the operand's declared width, and `shl`
      masks its count to 5 bits — `8 shl 40` is 2048, not 0 and not 2^43;
    * its constant FOLDER does neither: `1 shl 40` folds to 2^40 and
      `-8 shr 1` to the full 64-bit 9223372036854775804.

  Copying that contradiction is the whole point of the flag ("in strict_FPC mode
  we _will_ copy their bugs" — the decision). Every row below is `fpc -O1`'s own
  output.

  ONE row is deliberately absent: `-a shr 1` over an Integer variable. FPC gives
  9223372036854775804 there, but not because of `shr` — its UNARY MINUS on an
  Integer yields Int64, so the shift already sees 64 bits. That is a separate
  semantic and it is recorded in
  bug-a-strict-fpc-does-not-reproduce-fpc-shift-widths rather than faked here.

  A 64-BIT-TARGET test, deliberately: "native width" is 32 bits on i386 / arm32
  / riscv32, so the full-width rows cannot hold there and do not under the
  default dialect either. x86-64 and aarch64 agree row for row.

  bug-a-strict-fpc-does-not-reproduce-fpc-shift-widths }
program test_strict_fpc_shift_widths;
var a, b: Integer; q: Int64;
begin
  a := 8; b := 40; q := 8;

  { the constant FOLDER — full width, both operators }
  WriteLn(1 shl 40);          { 1099511627776 }
  WriteLn(-8 shr 1);          { 9223372036854775804 }
  WriteLn(1 shl 31);          { 2147483648 }

  { a VARIABLE operand — the declared width, and shl masks the count }
  WriteLn(a shl b);           { 2048  — 40 mod 32 = 8 }
  WriteLn(a shl 40);          { 2048 }
  WriteLn(a shr 1);           { 4 }
  WriteLn(a shl 2);           { 32 }

  { Int64 operands are 64-bit either way and have never diverged }
  WriteLn(q shl 40);          { 8796093022208 }
  WriteLn(-q shr 1);          { 9223372036854775804 }
  WriteLn('STRICT FPC SHIFT WIDTHS OK');
end.
