{$mode objfpc}
program test_shr_width;

{ Shifts happen at NATIVE width and their result is not truncated back to the
  operand's declared width — decide-shift-operator-promotion-width (user,
  2026-08-10): "pxx truncating to 32-bit is wrong", and copying FPC's own
  inconsistency (it widens the operand for `shr` but masks the count for `shl`,
  and its constant folder contradicts its runtime path) is left to --strict-fpc.

  So this file's ORIGINAL expectations — the operand-width ones — are no longer
  the dialect's answers, and two rows now deliberately differ from FPC:

    i shr 1   (i: Integer = -8)   FPC 2147483644     pxx 9223372036854775804
    i shl 31  (i: Integer = 1)    FPC -2147483648    pxx 2147483648

  Both are the 64-bit answer for the same bit pattern; pxx keeps the bits FPC
  discards. What the file still guards is that the SHIFTS THEMSELVES are right:
  a logical `shr` is logical (an unsigned operand still zero-extends, row 2),
  a signed one sign-extends before shifting rather than leaking a half-extended
  pattern, and 64-bit operands are untouched (rows 3, 4, 9, 10).
  bug-shr-signed-integer-width / bug-shl-signed-integer-width laid this out
  originally; bug-a-shr-on-a-32-bit-operand-does-not-promote-like-fpc changed
  the width it happens at. }

var
  i: Integer;
  c: Cardinal;
  q: Int64;
begin
  i := -8;          writeln(i shr 1);          { 9223372036854775804 (native width; FPC 2147483644) }
  c := $FFFFFFF8;   writeln(c shr 1);          { 2147483644 }
  q := -8;          writeln(q shr 1);          { 9223372036854775804 }
  writeln(UInt64(1) shl 40);                    { 1099511627776 }
  i := 1024;        writeln(i shr 2);          { 256 }
  i := 1;           writeln(i shl 31);         { 2147483648 (no wrap; FPC -2147483648) }
  i := -1;          writeln(i shl 4);          { -16 }
  c := 1;           writeln(c shl 31);         { 2147483648 (unsigned, positive) }
  writeln(UInt64(1) shl 40);                    { 1099511627776 (64-bit unchanged) }
  writeln(Int64(1) shl 52);                     { 4503599627370496 }
end.
