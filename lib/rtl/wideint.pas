{ SPDX-License-Identifier: Zlib }
unit wideint;
{ Widening 64x64 -> 128 unsigned multiply: the high half.

  The low half of a 128-bit product is just `a * b` (it wraps, which is exactly
  the low 64 bits). The HIGH half needs hardware help, so this unit is the one
  portable seam for it:

    - 64-bit targets (CPU64: x86-64, aarch64) use the __pxxmulhi_u64 intrinsic,
      which lowers to a single instruction (x86-64 `mul`, aarch64 `umulh`).
    - Everything else falls back to a 32-bit-halves schoolbook, in plain Pascal.
      Correct, just ~10x the work. The 32-bit targets have no widening multiply
      to lower to, so the compiler REJECTS the intrinsic there — hence the
      {$IFDEF}, and hence why callers must come through here rather than reach
      for the intrinsic directly.

  This is the primitive that lets multi-precision code carry SATURATED 64-bit
  limbs (full 2^64 radix) instead of a reduced radix like bignum's 1e9-per-limb,
  which exists precisely because it had no way to see a product's high bits.

  Track B; pinned stable. }

interface

{ High 64 bits of the unsigned 128-bit product a*b. Low half = a * b. }
function MulHiU64(a, b: UInt64): UInt64;

implementation

{$IFDEF CPU64}

function MulHiU64(a, b: UInt64): UInt64;
begin
  MulHiU64 := __pxxmulhi_u64(a, b);
end;

{$ELSE}

{ Split both operands into 32-bit halves and add up the partial products,
  keeping the carries that cross bit 63:

    a*b = al*bl + ((ah*bl + al*bh) << 32) + ((ah*bh) << 64)

  The high word is ah*bh, plus the top halves of the two middle products, plus
  whatever carried out of the low 64 bits. }
function MulHiU64(a, b: UInt64): UInt64;
var
  al, ah, bl, bh, lo, mid1, mid2, carry: UInt64;
begin
  al := a and $FFFFFFFF;  ah := a shr 32;
  bl := b and $FFFFFFFF;  bh := b shr 32;

  lo   := al * bl;
  mid1 := ah * bl;
  mid2 := al * bh;

  { carry out of the low 64 bits }
  carry := (lo shr 32) + (mid1 and $FFFFFFFF) + (mid2 and $FFFFFFFF);

  MulHiU64 := (ah * bh) + (mid1 shr 32) + (mid2 shr 32) + (carry shr 32);
end;

{$ENDIF}

end.
