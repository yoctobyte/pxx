program lib_wideint;
{ MulHiU64: high 64 bits of the unsigned 128-bit product.

  Runs on EVERY target -- that is the point. On CPU64 it exercises the
  __pxxmulhi_u64 intrinsic (x86-64 `mul` / aarch64 `umulh`); on the 32-bit
  targets it exercises the Pascal 32-bit-halves fallback. Both must agree with
  the same known answers, so cross-running this is what proves the fallback
  matches the hardware. }
uses wideint;

var
  fails, i: Integer;
  x, y, hi, lo: UInt64;

procedure Check(a, b, want: UInt64; const what: AnsiString);
var got: UInt64;
begin
  got := MulHiU64(a, b);
  if got <> want then
  begin
    WriteLn('FAIL ', what, ': got ', got, ' want ', want);
    Inc(fails);
  end;
end;

begin
  fails := 0;

  Check(0, 0, 0, 'zero');
  Check(1, 1, 0, 'one');
  Check(123456789, 987654321, 0, 'product fits in 64 bits');
  Check(UInt64($8000000000000000), 2, 1, '2^63 * 2');
  Check(UInt64($100000000), UInt64($100000000), 1, '2^32 * 2^32');
  Check(UInt64($FFFFFFFFFFFFFFFF), 1, 0, 'max * 1');

  { max * 2 = 2^65-2. A SIGNED widening multiply would read max as -1 and give
    $FFFFFFFFFFFFFFFF here -- this case is the unsignedness gate. }
  Check(UInt64($FFFFFFFFFFFFFFFF), 2, 1, 'max * 2 (unsigned)');

  { (2^64-1)^2 = 2^128 - 2^65 + 1 -> high = 2^64 - 2 }
  Check(UInt64($FFFFFFFFFFFFFFFF), UInt64($FFFFFFFFFFFFFFFF),
        UInt64($FFFFFFFFFFFFFFFE), 'max * max');

  { A 128-bit identity that pins hi AND lo together: for a = b = 2^32 + 1,
    a*b = 2^64 + 2^33 + 1, so hi = 1 and lo = 2^33 + 1. }
  x := UInt64($100000001);
  hi := MulHiU64(x, x);
  lo := x * x;
  if (hi <> 1) or (lo <> UInt64($200000001)) then
  begin
    WriteLn('FAIL hi/lo pair: hi=', hi, ' lo=', lo);
    Inc(fails);
  end;

  { Sweep: hi must never exceed what the operands can produce, and the
    hi=0 boundary must hold exactly where the product stops fitting in 64 bits.
    2^32 * 2^32 is the smallest product that overflows. }
  x := UInt64($FFFFFFFF);
  Check(x, x, 0, 'max32 * max32 (largest product still fitting)');
  Check(x + 1, x + 1, 1, 'just over the 64-bit boundary');

  { Deterministic stirred sweep -- self-consistency of the active
    implementation across many bit patterns. Every product's high half must
    equal the schoolbook the reference in the unit computes, which on CPU64
    means intrinsic-vs-nothing; the real cross-check is running this same
    binary on a 32-bit target and getting the same output line. }
  x := UInt64($9E3779B97F4A7C15);
  y := UInt64($BF58476D1CE4E5B9);
  hi := 0;
  for i := 1 to 500 do
  begin
    x := x + UInt64($9E3779B97F4A7C15);
    x := (x xor (x shr 30)) * UInt64($BF58476D1CE4E5B9);
    y := (y xor (y shr 27)) * UInt64($94D049BB133111EB);
    hi := hi xor MulHiU64(x, y);
  end;

  { Fingerprint of the whole sweep. Identical on every target if and only if
    the fallback and the intrinsic agree bit for bit. }
  WriteLn('sweep=', hi);

  if fails = 0 then WriteLn('WIDEINT OK')
  else WriteLn('WIDEINT FAIL (', fails, ')');
end.
