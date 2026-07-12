{ SPDX-License-Identifier: Zlib }
unit p256field;
{ Arithmetic in GF(p) for the NIST P-256 prime

    p = 2^256 - 2^224 + 2^192 + 2^96 - 1

  on SATURATED 64-bit limbs (four of them, little-endian) rather than the
  generic arbitrary-precision TBigInt.

  Why this unit exists: ecdsa_p256 ran on bignum's TBigInt, where every field
  multiply meant a heap-allocated limb array in base 1e9 plus a full BigDivMod to
  reduce -- an ECDSA verify cost ~480ms, while x25519 in this same RTL does an
  ECDH in ~5ms because it has dedicated fixed-limb field arithmetic. This is that
  same trick, for P-256.

  Representation is MONTGOMERY form: a field element x is stored as x*R mod p,
  with R = 2^256. Multiplication is CIOS (Koc's Coarsely Integrated Operand
  Scanning), which folds the reduction into the multiply and needs no division at
  all. P-256 has the pleasant property that n0' = -p^-1 mod 2^64 = 1, so the
  reduction's per-step multiplier m is just t[0] -- one multiply saved per limb.

  Add/sub are ordinary carry-propagating add/sub with a conditional correction by
  p, and are form-agnostic (Montgomery form is linear, so a*R + b*R = (a+b)*R).

  The 128-bit partial products come from wideint's MulHiU64: the low half of a
  64x64 product is plain a*b (it wraps), the high half is the intrinsic on CPU64
  and a Pascal fallback elsewhere. So this unit is portable -- just slower where
  there is no widening multiply.

  Track B; pinned stable (v211+, which carries __pxxmulhi_u64). }

interface

uses wideint;

type
  { Little-endian: limb 0 is the least significant. Values are kept fully
    reduced (< p) at every public boundary. }
  TFe = array[0..3] of UInt64;

{ --- conversion --- }
procedure FeFromBytes(var r: TFe; const s: AnsiString);  { 32 bytes, big-endian -> Montgomery form }
function  FeToBytes(const a: TFe): AnsiString;           { Montgomery form -> 32 bytes, big-endian }
procedure FeSetInt(var r: TFe; v: UInt64);               { small integer -> Montgomery form }
procedure FeSetZero(var r: TFe);
procedure FeSetOne(var r: TFe);

{ --- field ops (operands and results in Montgomery form) --- }
procedure FeAdd(var r: TFe; const a, b: TFe);
procedure FeSub(var r: TFe; const a, b: TFe);
procedure FeMul(var r: TFe; const a, b: TFe);
procedure FeSqr(var r: TFe; const a: TFe);
procedure FeInv(var r: TFe; const a: TFe);               { a^(p-2); FeInv(0) = 0 }

function  FeIsZero(const a: TFe): Boolean;
function  FeEqual(const a, b: TFe): Boolean;

{ True if the 32 big-endian bytes are a value < p (i.e. a valid field element).
  Does not depend on Montgomery form -- checks the plain integer. }
function  FeBytesInRange(const s: AnsiString): Boolean;

implementation

const
  { p, little-endian limbs }
  P0 = UInt64($FFFFFFFFFFFFFFFF);
  P1 = UInt64($00000000FFFFFFFF);
  P2 = UInt64($0000000000000000);
  P3 = UInt64($FFFFFFFF00000001);

  { R^2 mod p, for converting into Montgomery form: ToMont(a) = CIOS(a, R2) }
  RR0 = UInt64($0000000000000003);
  RR1 = UInt64($FFFFFFFBFFFFFFFF);
  RR2 = UInt64($FFFFFFFFFFFFFFFE);
  RR3 = UInt64($00000004FFFFFFFD);

  { R mod p == 1 in Montgomery form }
  ONE0 = UInt64($0000000000000001);
  ONE1 = UInt64($FFFFFFFF00000000);
  ONE2 = UInt64($FFFFFFFFFFFFFFFF);
  ONE3 = UInt64($00000000FFFFFFFE);

{ s := x + y*z + cin, returning the 128-bit result as (cout, s).
  Cannot overflow: (2^64-1)^2 + 2*(2^64-1) < 2^128. }
procedure MulAdd(x, y, z, cin: UInt64; var s, cout: UInt64);
var lo, hi, t: UInt64;
begin
  lo := y * z;              { low half wraps -- exactly what we want }
  hi := MulHiU64(y, z);

  t := lo + x;
  if t < lo then hi := hi + 1;
  lo := t;

  t := lo + cin;
  if t < lo then hi := hi + 1;

  s := t;
  cout := hi;
end;

{ Montgomery product: r := a*b*R^-1 mod p  (CIOS, 4 limbs, n0' = 1). }
procedure MontMul(var r: TFe; const a, b: TFe);
var
  t: array[0..5] of UInt64;
  i, j: Integer;
  c, s, m, x, borrow, tmp: UInt64;
  pl: array[0..3] of UInt64;
begin
  pl[0] := P0; pl[1] := P1; pl[2] := P2; pl[3] := P3;
  for i := 0 to 5 do t[i] := 0;

  for i := 0 to 3 do
  begin
    { t := t + a*b[i] }
    c := 0;
    for j := 0 to 3 do
    begin
      MulAdd(t[j], a[j], b[i], c, s, c);
      t[j] := s;
    end;
    x := t[4] + c;
    if x < t[4] then t[5] := t[5] + 1;   { carry out of limb 4 }
    t[4] := x;

    { m := t[0] * n0'  (n0' = 1 for P-256) }
    m := t[0];

    { t := (t + m*p) / 2^64  -- the low limb is annihilated by construction }
    c := 0;
    MulAdd(t[0], m, pl[0], 0, s, c);     { s is discarded: it is zero }
    for j := 1 to 3 do
    begin
      MulAdd(t[j], m, pl[j], c, s, c);
      t[j - 1] := s;
    end;
    x := t[4] + c;
    t[3] := x;
    if x < t[4] then t[5] := t[5] + 1;
    t[4] := t[5];
    t[5] := 0;
  end;

  { t (limbs 0..4) is now < 2p; subtract p once if it does not already fit.
    Do the subtract unconditionally into a scratch and pick the right one --
    the borrow tells us which. }
  borrow := 0;
  tmp := t[0] - pl[0]; borrow := Ord(t[0] < pl[0]); r[0] := tmp;
  tmp := t[1] - pl[1];
  if t[1] < pl[1] then
  begin
    r[1] := tmp - borrow; borrow := 1;
  end
  else
  begin
    if (tmp = 0) and (borrow = 1) then begin r[1] := UInt64($FFFFFFFFFFFFFFFF); borrow := 1; end
    else begin r[1] := tmp - borrow; borrow := 0; end;
  end;
  tmp := t[2] - pl[2];
  if t[2] < pl[2] then
  begin
    r[2] := tmp - borrow; borrow := 1;
  end
  else
  begin
    if (tmp = 0) and (borrow = 1) then begin r[2] := UInt64($FFFFFFFFFFFFFFFF); borrow := 1; end
    else begin r[2] := tmp - borrow; borrow := 0; end;
  end;
  tmp := t[3] - pl[3];
  if t[3] < pl[3] then
  begin
    r[3] := tmp - borrow; borrow := 1;
  end
  else
  begin
    if (tmp = 0) and (borrow = 1) then begin r[3] := UInt64($FFFFFFFFFFFFFFFF); borrow := 1; end
    else begin r[3] := tmp - borrow; borrow := 0; end;
  end;

  { If the subtraction borrowed out AND the high word t[4] was zero, then
    t < p and the subtraction was wrong -- keep t. Otherwise keep t - p. }
  if (borrow = 1) and (t[4] = 0) then
  begin
    r[0] := t[0]; r[1] := t[1]; r[2] := t[2]; r[3] := t[3];
  end;
end;

procedure FeMul(var r: TFe; const a, b: TFe);
begin
  MontMul(r, a, b);
end;

procedure FeSqr(var r: TFe; const a: TFe);
begin
  MontMul(r, a, a);
end;

procedure FeSetZero(var r: TFe);
begin
  r[0] := 0; r[1] := 0; r[2] := 0; r[3] := 0;
end;

procedure FeSetOne(var r: TFe);
begin
  r[0] := ONE0; r[1] := ONE1; r[2] := ONE2; r[3] := ONE3;
end;

function FeIsZero(const a: TFe): Boolean;
begin
  FeIsZero := (a[0] = 0) and (a[1] = 0) and (a[2] = 0) and (a[3] = 0);
end;

function FeEqual(const a, b: TFe): Boolean;
begin
  FeEqual := (a[0] = b[0]) and (a[1] = b[1]) and (a[2] = b[2]) and (a[3] = b[3]);
end;

{ r := a + b mod p }
procedure FeAdd(var r: TFe; const a, b: TFe);
var
  t: array[0..3] of UInt64;
  pl: array[0..3] of UInt64;
  i: Integer;
  carry, s, top, borrow, d: UInt64;
  ge: Boolean;
begin
  pl[0] := P0; pl[1] := P1; pl[2] := P2; pl[3] := P3;

  carry := 0;
  for i := 0 to 3 do
  begin
    s := a[i] + b[i];
    top := 0;
    if s < a[i] then top := 1;
    s := s + carry;
    if (s = 0) and (carry = 1) then top := 1;
    t[i] := s;
    carry := top;
  end;

  { subtract p if the sum overflowed (carry) or is >= p }
  ge := carry = 1;
  if not ge then
  begin
    i := 3;
    while i >= 0 do
    begin
      if t[i] <> pl[i] then
      begin
        ge := t[i] > pl[i];
        i := -1;
      end
      else
      begin
        if i = 0 then ge := True;   { all limbs equal -> t = p }
        i := i - 1;
      end;
    end;
  end;

  if ge then
  begin
    borrow := 0;
    for i := 0 to 3 do
    begin
      d := t[i] - pl[i];
      if t[i] < pl[i] then
      begin
        r[i] := d - borrow;
        borrow := 1;
      end
      else
      begin
        if (d = 0) and (borrow = 1) then
        begin
          r[i] := UInt64($FFFFFFFFFFFFFFFF);
          borrow := 1;
        end
        else
        begin
          r[i] := d - borrow;
          borrow := 0;
        end;
      end;
    end;
  end
  else
    for i := 0 to 3 do r[i] := t[i];
end;

{ r := a - b mod p }
procedure FeSub(var r: TFe; const a, b: TFe);
var
  t: array[0..3] of UInt64;
  pl: array[0..3] of UInt64;
  i: Integer;
  borrow, d, carry, s, top: UInt64;
begin
  pl[0] := P0; pl[1] := P1; pl[2] := P2; pl[3] := P3;

  borrow := 0;
  for i := 0 to 3 do
  begin
    d := a[i] - b[i];
    if a[i] < b[i] then
    begin
      t[i] := d - borrow;
      borrow := 1;
    end
    else
    begin
      if (d = 0) and (borrow = 1) then
      begin
        t[i] := UInt64($FFFFFFFFFFFFFFFF);
        borrow := 1;
      end
      else
      begin
        t[i] := d - borrow;
        borrow := 0;
      end;
    end;
  end;

  { went negative -> add p back }
  if borrow = 1 then
  begin
    carry := 0;
    for i := 0 to 3 do
    begin
      s := t[i] + pl[i];
      top := 0;
      if s < t[i] then top := 1;
      s := s + carry;
      if (s = 0) and (carry = 1) then top := 1;
      r[i] := s;
      carry := top;
    end;
  end
  else
    for i := 0 to 3 do r[i] := t[i];
end;

{ a^(p-2) mod p by square-and-multiply over the bits of p-2.
  p-2 is public, so a fixed scan is fine; this is not a secret exponent. }
procedure FeInv(var r: TFe; const a: TFe);
var
  e: array[0..3] of UInt64;
  acc, base: TFe;
  i, bit: Integer;
  w: UInt64;
begin
  if FeIsZero(a) then
  begin
    FeSetZero(r);
    Exit;
  end;

  { p - 2 }
  e[0] := P0 - 2; e[1] := P1; e[2] := P2; e[3] := P3;

  FeSetOne(acc);
  base := a;

  { least-significant-first square-and-multiply }
  for i := 0 to 3 do
  begin
    w := e[i];
    for bit := 0 to 63 do
    begin
      if (w and 1) = 1 then FeMul(acc, acc, base);
      FeSqr(base, base);
      w := w shr 1;
    end;
  end;

  r := acc;
end;

{ --- byte conversion (32 bytes, big-endian, as the curve specs use) --- }

procedure BytesToLimbs(var t: TFe; const s: AnsiString);
var i, j: Integer; w: UInt64;
begin
  for i := 0 to 3 do
  begin
    w := 0;
    { limb i covers bytes [32 - 8*(i+1) .. 32 - 8*i - 1] of the big-endian string }
    for j := 0 to 7 do
      w := (w shl 8) or UInt64(Ord(s[32 - 8 * (i + 1) + j + 1]));
    t[i] := w;
  end;
end;

function FeBytesInRange(const s: AnsiString): Boolean;
var
  t: TFe;
  pl: array[0..3] of UInt64;
  i: Integer;
  res: Boolean;
begin
  if Length(s) <> 32 then
  begin
    FeBytesInRange := False;
    Exit;
  end;
  BytesToLimbs(t, s);
  pl[0] := P0; pl[1] := P1; pl[2] := P2; pl[3] := P3;

  res := False;      { equal all the way down -> t = p -> not in range }
  i := 3;
  while i >= 0 do
  begin
    if t[i] <> pl[i] then
    begin
      res := t[i] < pl[i];
      i := -1;
    end
    else
      i := i - 1;
  end;
  FeBytesInRange := res;
end;

procedure FeFromBytes(var r: TFe; const s: AnsiString);
var t, rr: TFe;
begin
  BytesToLimbs(t, s);
  rr[0] := RR0; rr[1] := RR1; rr[2] := RR2; rr[3] := RR3;
  MontMul(r, t, rr);        { a * R^2 * R^-1 = a*R  -> Montgomery form }
end;

function FeToBytes(const a: TFe): AnsiString;
var
  t, one: TFe;
  s: AnsiString;
  i, j: Integer;
  w: UInt64;
begin
  { MontMul by 1 strips the R factor }
  FeSetZero(one); one[0] := 1;
  MontMul(t, a, one);

  SetLength(s, 32);
  for i := 0 to 3 do
  begin
    w := t[i];
    for j := 0 to 7 do
    begin
      { byte j of limb i, least significant first, placed big-endian }
      s[32 - 8 * i - j] := Chr(Integer(w and $FF));
      w := w shr 8;
    end;
  end;
  FeToBytes := s;
end;

procedure FeSetInt(var r: TFe; v: UInt64);
var t, rr: TFe;
begin
  t[0] := v; t[1] := 0; t[2] := 0; t[3] := 0;
  rr[0] := RR0; rr[1] := RR1; rr[2] := RR2; rr[3] := RR3;
  MontMul(r, t, rr);
end;

end.
