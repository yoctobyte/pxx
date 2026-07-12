program test_mulhi;
{ __pxxmulhi_u64(a, b): high 64 bits of the UNSIGNED 128-bit product.
  Checked against known answers and against an independent 32-bit-halves
  schoolbook computation, over both fixed vectors and a pseudorandom sweep.
  64-bit targets only (x86-64 `mul`, aarch64 `umulh`) -- lowering rejects the
  32-bit ones, where lib/rtl's MulHiU64 wrapper takes a Pascal fallback. }

var
  fails, i: Integer;
  x, y: UInt64;

{ Reference: split into 32-bit halves, schoolbook, keep the carries.
  a*b = al*bl + ((ah*bl + al*bh) << 32) + ((ah*bh) << 64); the high word is
  ah*bh plus the carries out of bit 63. }
function MulHiRef(a, b: UInt64): UInt64;
var al, ah, bl, bh, lo, mid1, mid2, carry: UInt64;
begin
  al := a and $FFFFFFFF;  ah := a shr 32;
  bl := b and $FFFFFFFF;  bh := b shr 32;

  lo := al * bl;
  mid1 := ah * bl;
  mid2 := al * bh;

  { carry out of the low 64 bits: (lo>>32) + low32(mid1) + low32(mid2) }
  carry := (lo shr 32) + (mid1 and $FFFFFFFF) + (mid2 and $FFFFFFFF);

  MulHiRef := (ah * bh) + (mid1 shr 32) + (mid2 shr 32) + (carry shr 32);
end;

procedure Check(a, b, want: UInt64; const label_: AnsiString);
var got: UInt64;
begin
  got := __pxxmulhi_u64(a, b);
  if got <> want then
  begin
    WriteLn('FAIL ', label_, ': got ', got, ' want ', want);
    Inc(fails);
  end;
end;

begin
  fails := 0;

  { --- known answers --- }
  Check(0, 0, 0, 'zero');
  Check(123456789, 987654321, 0, 'small (product fits in 64 bits)');

  { 2^63 * 2 = 2^64 -> high = 1 }
  Check(UInt64($8000000000000000), 2, 1, '2^63 * 2');

  { 2^32 * 2^32 = 2^64 -> high = 1 }
  Check(UInt64($100000000), UInt64($100000000), 1, '2^32 * 2^32');

  { (2^64-1)^2 = 2^128 - 2^65 + 1 -> high = 2^64 - 2 = $FFFFFFFFFFFFFFFE }
  Check(UInt64($FFFFFFFFFFFFFFFF), UInt64($FFFFFFFFFFFFFFFF),
        UInt64($FFFFFFFFFFFFFFFE), 'max * max');

  { (2^64-1) * 1 -> product fits, high = 0. Proves it is UNSIGNED:
    a signed 64x64 high would read both operands as -1 and give high = 0 too,
    so pair it with the asymmetric case below. }
  Check(UInt64($FFFFFFFFFFFFFFFF), 1, 0, 'max * 1');

  { max * 2 = 2^65 - 2 -> high = 1. A SIGNED widening multiply reads max as -1
    and would yield high = $FFFFFFFFFFFFFFFF here. This is the unsignedness gate. }
  Check(UInt64($FFFFFFFFFFFFFFFF), 2, 1, 'max * 2 (unsigned, not signed)');

  { --- differential sweep against the schoolbook reference --- }
  x := UInt64($9E3779B97F4A7C15);
  y := UInt64($BF58476D1CE4E5B9);
  for i := 1 to 2000 do
  begin
    { SplitMix-ish stirring; the exact stream does not matter, only coverage }
    x := x + UInt64($9E3779B97F4A7C15);
    x := (x xor (x shr 30)) * UInt64($BF58476D1CE4E5B9);
    y := y + UInt64($D1B54A32D192ED03);
    y := (y xor (y shr 27)) * UInt64($94D049BB133111EB);
    Check(x, y, MulHiRef(x, y), 'sweep');
  end;

  if fails = 0 then WriteLn('MULHI OK')
  else WriteLn('MULHI FAIL (', fails, ')');
end.
