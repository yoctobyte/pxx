program test_cross_trunc_round_saturate;
{ Trunc/Round of a value that does not fit an Int64.

  x86's cvttsd2si/cvtsd2si (and x87's fisttp/fistp on i386) write the "integer
  indefinite" value, INT64_MIN, when the conversion is invalid — the SAME value
  for a huge positive, a huge negative and a NaN. So Trunc(1e30) came back
  -9223372036854775808: an out-of-range magnitude became a legal-looking
  number, and a caller narrowing it to Integer got 0, its low 32 bits, so a
  range guard like `if Trunc(x) > limit` PASSED.

  aarch64, arm32 and riscv32 already produced the IEEE 754-2008 answer, because
  fcvtzs and the softfloat kernels saturate. Three targets agreeing is the
  specification, and it is also the decided policy for this family
  (decide-may-uses-math-cost-the-heap-and-exception-runtime: pxx keeps IEEE
  masked semantics and saturates; FPC's EInvalidOp goes behind an opt-in flag).
  So x86 is what moved.

    +overflow -> High(Int64)    -overflow -> Low(Int64)    NaN -> 0

  Runs as a differential against the x86-64 oracle on every cross target, which
  is the point: a fix verified on one target only would have read as green and
  stayed wrong on the others, in BOTH directions.
  bug-a-trunc-and-round-of-an-out-of-range-double-return-int64-min-silently }
var d, z: Double; q: Int64;
begin
  z := 0.0;
  d := 1e30;   WriteLn('t+1e30=', Trunc(d), ' r=', Round(d));
  d := -1e30;  WriteLn('t-1e30=', Trunc(d), ' r=', Round(d));
  d := 1.0/z;  WriteLn('t+inf =', Trunc(d), ' r=', Round(d));
  d := -1.0/z; WriteLn('t-inf =', Trunc(d), ' r=', Round(d));
  d := z/z;    WriteLn('tnan  =', Trunc(d), ' r=', Round(d));

  { the EXACT boundary: -9223372036854775808.0 is representable and its Trunc is
    legitimately INT64_MIN, which is also the indefinite sentinel — so the fixup
    fires on it and must recompute the same answer }
  d := -9223372036854775808.0;
  WriteLn('exactmin=', Trunc(d), ' r=', Round(d));
  { ...and 2^63 itself, one ulp past representable, must saturate }
  d := 9223372036854775808.0;
  WriteLn('two63 =', Trunc(d), ' r=', Round(d));

  { ordinary values must be untouched, including the round-half-to-even cases }
  d := 3.7;   WriteLn('t3.7  =', Trunc(d), ' r=', Round(d));
  d := -3.7;  WriteLn('t-3.7 =', Trunc(d), ' r=', Round(d));
  d := 0.5;   WriteLn('t0.5  =', Trunc(d), ' r=', Round(d));
  d := 2.5;   WriteLn('t2.5  =', Trunc(d), ' r=', Round(d));
  d := -0.5;  WriteLn('t-0.5 =', Trunc(d), ' r=', Round(d));
  d := 0.0;   WriteLn('tzero =', Trunc(d), ' r=', Round(d));
  q := 12345; WriteLn('tint  =', Trunc(q), ' r=', Round(q));
end.
