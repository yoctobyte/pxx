program test_sizeof_real_matches_storage;
{ SizeOf(<type name>) must agree with SizeOf(<variable of that type>).

  `Real` is the only type where those two came from DIFFERENT tables.
  BuiltinScalarTypeKind — the declaration path — was target-keyed, so on
  xtensa and riscv32 `var r: Real` correctly got 4 bytes of storage and
  genuinely single-precision arithmetic, which is the intended dialect
  behaviour there (docs/language/types.md). BuiltinTypeNameTk — the table
  SizeOf, casts and TypeInfo consult — hard-wired Real to Double. So
  SizeOf(Real) answered 8 for a variable occupying 4: a wrong size handed to
  GetMem, Move and FillChar, silently, on the one target class where a
  four-byte overrun is least likely to be noticed.

  This test cannot FAIL on x86-64, where both answers are 8 either way — the
  divergence only ever appeared on the Single targets, which have no host to
  run a binary on. It is here as the portable half of the check: the identity
  SizeOf(T) = SizeOf(var of T) is what regressed, and asserting it on every
  target the suite can execute is what keeps the two tables unified. The
  cross-target half is measured in the ticket by array stride.

  Checked against FPC 3.2.2: identical output.
  bug-a-sizeof-real-disagrees-with-the-storage-real-actually-gets }

var
  r: Real;
  d: Double;
  s: Single;
  ra: array[0..3] of Real;

begin
  { the regression itself: name and variable must agree }
  WriteLn('a ', SizeOf(Real), '|', SizeOf(r));
  WriteLn('b ', SizeOf(Double), '|', SizeOf(d));
  WriteLn('c ', SizeOf(Single), '|', SizeOf(s));

  { an array of Real must stride by exactly that same size — the consumer
    that would have walked off the end when the two disagreed }
  WriteLn('d ', SizeOf(ra) = 4 * SizeOf(r));

  { Real is never anything but one of the two float depths, on any target }
  WriteLn('e ', (SizeOf(Real) = SizeOf(Double)) or (SizeOf(Real) = SizeOf(Single)));

  r := 1.0; d := r; s := r;
  WriteLn('f ', d = 1.0, '|', s = 1.0);
  WriteLn('OK');
end.
