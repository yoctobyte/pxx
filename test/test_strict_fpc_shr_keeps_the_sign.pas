{ --strict-fpc reproduces FPC's shift widths: `shr` on a narrow operand happens
  at the operand's declared width, and its RESULT keeps the operand's type — so
  a signed operand yields a signed result. pxx zero-extended for the shift and
  never read the answer back as signed, which only a count of ZERO can show
  (any count >= 1 clears bit 31, making the sign-extend a no-op there):
  `Integer(-16) shr 0` answered 4294967280 instead of -16.

  This file is compiled TWICE by the test-core row, once per dialect, because
  the two modes must give DIFFERENT answers for counts >= 1 — the default
  dialect shifts at native width by decide-shift-operator-promotion-width — and
  the same answer for count 0. A single-mode test would lock in one and let the
  other rot. bug-a-strict-fpc-shr-by-zero-drops-the-sign }
program test_strict_fpc_shr_keeps_the_sign;

var
  i: Integer;
  n: Integer;
  i64: Int64;
  si: SmallInt;
  sb: ShortInt;
begin
  { count 0 is identity in BOTH dialects and in FPC — a shift by nothing cannot
    change the value, whatever width the shift notionally happens at }
  i := -16;
  WriteLn('c0 ', i shr 0);
  n := 0;
  WriteLn('v0 ', i shr n);          { via a variable count, not a literal }
  WriteLn('l0 ', i shl 0);

  { narrower signed operands take the same path }
  si := -16;
  WriteLn('s0 ', si shr 0);
  sb := -16;
  WriteLn('b0 ', sb shr 0);

  { a genuine 64-bit operand never narrowed, so it was always right }
  i64 := -16;
  WriteLn('q0 ', i64 shr 0);

  { positive operands are unaffected either way }
  i := 16;
  WriteLn('p0 ', i shr 0, ' ', i shr 2);

  { ...and the rows where the two dialects MUST disagree, so this file pins both
    behaviours rather than one. Default: native width, so the operand is
    sign-extended to 64 bits and the logical shift sees the real two's
    complement. --strict-fpc: the operand's declared 32-bit width, matching FPC.
    decide-shift-operator-promotion-width }
  i := -16;
  WriteLn('d1 ', i shr 1);
  WriteLn('d4 ', i shr 4);
  i := 1;
  WriteLn('d31 ', i shl 31);
  WriteLn('d33 ', i shl 33);
end.
