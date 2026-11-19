{ SPDX-License-Identifier: Zlib }
unit decfloat;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Exact decimal <-> binary64: the ONE correctly rounded decimal -> double
  parser, and the exact double -> decimal expansion it is built on.

  It was the body of sysutils (StrToFloat and friends). It is its own unit so
  that `Val(s, d, code)` -- a language statement lowered to builtin's ValFloat,
  which cannot `uses sysutils` -- reaches the same routine instead of a second
  parser. That second parser rounded once per digit and once per decade and
  returned a nearby double for 1574 of 6000 repr() strings while StrToFloat
  got all 6000 right.
  bug-b-val-of-a-float-is-not-correctly-rounded-while-strtofloat-of-the-same-string-is

  DEPENDENCIES: wideint only (MulHiU64). Not sysutils, and not builtin --
  builtin uses this unit, so anything here that pulled builtin back in would be
  a cycle. That is why the two spots that called IntToStr and Trim spell them
  out. Track B. }

interface

{ Parse s (surrounding chars <= ' ' ignored, as FPC's StrToFloat does) into the
  nearest double, ties to even. False on malformed input, value then 0. }
function ParseFloatCore(const s: AnsiString; var value: Double): Boolean;

{ The exact decimal digits of |value|: value = 0.ds * 10^(decExp+1), i.e. the
  first digit stands for 10^decExp. No rounding; up to ~767 digits. }
procedure ExDecDigits(value: Double; var ds: AnsiString; var decExp: Integer);

implementation

uses wideint;

{ ---- exact decimal expansion of a Double ---------------------------------

  THIS CORE IS COPIED. `compiler/builtin/pylib.pas` carries a renamed copy of
  everything from here down to ExDecRound, and of the correctly-rounded parser
  closure below (ExDecCmp .. StrToFloatDef), because a builtin unit may not
  `uses sysutils` — NilPy's unit scope is flat, so every name here would
  collide in every NilPy program. Moving the core down into a shared builtin
  unit was considered and rejected: library source has to stay STEPPABLE, and
  stepping into FloatToStr should not walk you out of this file
  (decide-nilpy-where-the-exact-decimal-float-core-lives).

  CHANGE ONE, CHANGE BOTH. `test/lib_floattostr.pas` pins this copy and
  `test/test_nilpy_float_repr.npy` pins the other, over a shared value table
  with CPython as the oracle, so a drift between them fails a test.

  Every finite double IS a finite decimal, exactly. value = mant * 2^exp2 with
  mant a 53-bit integer, and 2^-k = 5^k * 10^-k, so the exact decimal form is
  the integer mant*5^k with the point pushed k places left (k = -exp2). For
  exp2 >= 0 it is the plain integer mant*2^exp2. No approximation enters, so
  every digit produced is a real digit of the value — which is exactly what the
  normalise-in-doubles path in FloatToStrSig cannot do past 15, and why that
  routine caps there.

  Worst case is a denormal at exp2 = -1074: 5^1074 is 751 digits, times a
  16-digit mantissa, so 767 digits. Those live little-endian in limbs of nine
  decimal digits (base 10^9), grown by repeated multiply-by-small. Two chunk
  sizes do the scaling: 5^13 and 2^30, the largest powers whose per-limb
  product stays inside Int64 (10^9 * 5^13 is 1.2e18, well under 9.2e18). That
  turns the worst case into ~83 passes over ~86 limbs instead of 1074 passes
  over 767 single digits.

  Base 10^9 rather than one digit per byte is a ~9x cut in the inner loop, and
  it is the reason the exact path is affordable on BOTH sides: the decimal ->
  double search below expands a candidate per comparison, so expansion cost is
  multiplied by the search, not paid once. }
const
  PXX_EXDEC_LIMBS = 96;           { 9 digits each; 767 digits needs 86 }
  PXX_EXDEC_BASE  = 1000000000;   { 10^9 }
  PXX_EXDEC_P5_13 = 1220703125;   { 5^13 }
  PXX_EXDEC_P2_30 = 1073741824;   { 2^30 }
type
  TExDecBuf   = array[0..PXX_EXDEC_LIMBS - 1] of Int64;
  PExDecInt64 = ^Int64;

{ buf := buf * f. f is small enough that limb*f + carry cannot leave Int64. }
procedure ExDecMul(var buf: TExDecBuf; var n: Integer; f: Int64);
var i: Integer; t, carry: Int64;
begin
  carry := 0;
  for i := 0 to n - 1 do
  begin
    t := buf[i] * f + carry;
    buf[i] := t mod PXX_EXDEC_BASE;
    carry := t div PXX_EXDEC_BASE;
  end;
  while (carry > 0) and (n < PXX_EXDEC_LIMBS) do
  begin
    buf[n] := carry mod PXX_EXDEC_BASE;
    carry := carry div PXX_EXDEC_BASE;
    n := n + 1;
  end;
end;

{ Split a finite value into mant * 2^exp2 with mant an integer. Reads the
  IEEE-754 fields directly; a denormal carries no implicit leading bit. }
procedure ExDecSplit(value: Double; var mant: Int64; var exp2: Integer);
var bits, frac: Int64; be: Integer;
begin
  bits := PExDecInt64(@value)^;
  be   := Integer((bits shr 52) and $7FF);
  frac := bits and ((Int64(1) shl 52) - 1);
  if be = 0 then
  begin
    mant := frac;
    exp2 := -1074;
  end
  else
  begin
    mant := frac or (Int64(1) shl 52);
    exp2 := be - 1075;
  end;
end;

{ Exact digits of mant * 2^exp2: ds holds them most significant first with no
  leading zero, and decExp is the power of ten the first digit stands for (so
  267.5 gives '2675' and decExp = 2). Taking mant/exp2 rather than a Double is
  deliberate — the decimal->double side needs the exact expansion of MIDPOINTS
  between adjacent doubles, and a midpoint needs 54 bits, so it is not a
  Double. mant = 0 yields '0'. }
procedure ExDecOfMant(mant: Int64; exp2: Integer;
                      var ds: AnsiString; var decExp: Integer);
var
  buf: TExDecBuf;
  n, i, j, k, at, fracDigits: Integer;
  v: Int64;
  lp: AnsiString;
begin
  n := 0;
  while mant > 0 do
  begin
    buf[n] := mant mod PXX_EXDEC_BASE;
    mant := mant div PXX_EXDEC_BASE;
    n := n + 1;
  end;
  if n = 0 then begin buf[0] := 0; n := 1; end;
  fracDigits := 0;
  if exp2 >= 0 then
  begin
    k := exp2;
    while k >= 30 do begin ExDecMul(buf, n, PXX_EXDEC_P2_30); k := k - 30; end;
    while k > 0 do begin ExDecMul(buf, n, 2); k := k - 1; end;
  end
  else
  begin
    k := -exp2;
    fracDigits := k;
    while k >= 13 do begin ExDecMul(buf, n, PXX_EXDEC_P5_13); k := k - 13; end;
    while k > 0 do begin ExDecMul(buf, n, 5); k := k - 1; end;
  end;
  while (n > 1) and (buf[n - 1] = 0) do n := n - 1;
  { Top limb unpadded (that is what drops the leading zeros), the rest padded
    to the full nine so limb boundaries do not swallow interior zeros.

    Built into a string sized ONCE and filled by index. The obvious spelling —
    `ds := ds + lp` per limb, each limb zero-padded by `lp := '0' + lp` — is
    quadratic: it reallocates and recopies the whole accumulated prefix every
    limb, and a subnormal expands to ~765 digits (85 limbs). That was measured
    as the single largest cost in StrToFloat's exact path, which calls this
    about four times per parse: removing it took the mid-range case from 99 to
    30 us per value and subnormals from 2.78 ms to 1.22 ms
    (bug-b-strtofloat-is-3600x-slower-than-cpython-for-small-exponents).

    Digits are emitted low-to-high within each limb, which is why the inner
    loop walks j downwards into a slot whose base is already known. }
  { the top limb, without IntToStr: this unit may use nothing that pulls
    sysutils or builtin back in (builtin uses THIS unit). 0 <= limb < 10^9. }
  v := buf[n - 1];
  lp := '';
  repeat
    lp := Chr(Ord('0') + Integer(v mod 10)) + lp;
    v := v div 10;
  until v = 0;
  SetLength(ds, Length(lp) + 9 * (n - 1));
  for i := 1 to Length(lp) do ds[i] := lp[i];
  at := Length(lp);
  for i := n - 2 downto 0 do
  begin
    v := buf[i];
    for j := 9 downto 1 do
    begin
      ds[at + j] := Chr(Ord('0') + Integer(v mod 10));
      v := v div 10;
    end;
    at := at + 9;
  end;
  decExp := Length(ds) - 1 - fracDigits;
end;

{ Exact digits of a finite Double, sign ignored. }
procedure ExDecDigits(value: Double; var ds: AnsiString; var decExp: Integer);
var mant: Int64; exp2: Integer;
begin
  ExDecSplit(value, mant, exp2);
  ExDecOfMant(mant, exp2, ds, decExp);
end;

{ ---- decimal -> double, correctly rounded --------------------------------

  The old parser accumulated in doubles: one rounding per fractional digit, and
  10^e built by e successive multiplies (e up to 308, so the power itself was
  tens of ULP off). That is at most an approximation of the nearest double, and
  it is why exact 17-digit forms of 1/3, 1e-300, DBL_MAX and the denormals did
  not read back. Correct rounding means landing on the nearest double every
  time, so the value is reconstructed with the exact expansion above rather
  than with float arithmetic. }

{ Compare two exact decimals held as (digits, decExp) — digits most significant
  first with no leading zero, decExp the power of ten the first digit stands
  for. Both must be positive and nonzero. Shorter operands read as zero-padded,
  so '25'/1 and '250'/1 compare equal (both are 25). }
function ExDecCmp(const a: AnsiString; ae: Integer;
                  const b: AnsiString; be: Integer): Integer;
var i, n: Integer; ca, cb: Char;
begin
  if ae <> be then
  begin
    if ae < be then Result := -1 else Result := 1;
    Exit;
  end;
  n := Length(a);
  if Length(b) > n then n := Length(b);
  for i := 1 to n do
  begin
    if i <= Length(a) then ca := a[i] else ca := '0';
    if i <= Length(b) then cb := b[i] else cb := '0';
    if ca <> cb then
    begin
      if ca < cb then Result := -1 else Result := 1;
      Exit;
    end;
  end;
  Result := 0;
end;

function ExDecBitsToDouble(b: Int64): Double;
type PExDecDouble = ^Double;
begin
  Result := PExDecDouble(@b)^;
end;

function ExDecDoubleToBits(d: Double): Int64;
begin
  Result := PExDecInt64(@d)^;
end;

{ A cheap approximation of int(ds) * 10^expo. This is float arithmetic and is
  therefore wrong by some ULP — it is NEVER trusted, only used to seed the
  bracket for the exact search, which then proves the answer. Getting it close
  is purely a speed matter: the search costs one exact expansion per step, and
  seeding turns a 63-step search over the whole bit range into a handful of
  steps around the right answer. Powers of ten are applied by binary splitting
  (at most nine multiplies) rather than one per decade. }
function ExDecEstimate(const ds: AnsiString; nd, expo: Integer): Double;
var
  sig: Int64;
  i, k, e: Integer;
  w: Double;
  p10: array[0..8] of Double;
begin
  k := nd;
  if k > 17 then k := 17;
  sig := 0;
  for i := 1 to k do sig := sig * 10 + Int64(Ord(ds[i]) - Ord('0'));
  { digits we did not take are absorbed into the exponent }
  e := expo + (nd - k);
  w := sig * 1.0;
  p10[0] := 1.0e1;   p10[1] := 1.0e2;   p10[2] := 1.0e4;   p10[3] := 1.0e8;
  p10[4] := 1.0e16;  p10[5] := 1.0e32;  p10[6] := 1.0e64;  p10[7] := 1.0e128;
  p10[8] := 1.0e256;
  { the table spans 2^9-1 = 511 decades; anything past that is far outside the
    double range and only has to land on the correct side of it }
  if e > 511 then e := 511;
  if e < -511 then e := -511;
  if e > 0 then
  begin
    for i := 0 to 8 do
      if (e and (1 shl i)) <> 0 then w := w * p10[i];
  end
  else if e < 0 then
  begin
    k := -e;
    { divide rather than multiply by a negative power: keeps the intermediate
      from overflowing on the way down }
    for i := 0 to 8 do
      if (k and (1 shl i)) <> 0 then w := w / p10[i];
  end;
  Result := w;
end;

{ The double nearest to the positive decimal (ds, decExp), correctly rounded,
  ties to even.

  For positive doubles the IEEE bit pattern increases monotonically with the
  value, so "largest double <= D" is a plain ordered search over the bit
  pattern — 63 steps, each comparing D against the candidate's EXACT decimal
  expansion. There is no estimate here that could be wrong by an unknown number
  of ULP; the search cannot land anywhere but the right pair of neighbours.

  Then one decision between that double c and the next one up. Their midpoint is
  exactly (2*mant + 1) * 2^(exp2 - 1) — one formula that holds everywhere,
  including across a power-of-two boundary (where c = (2^53-1)*2^e and the next
  is 2^52*2^(e+1)) and across the denormal/normal boundary, because incrementing
  the bit pattern is exactly what both of those transitions are. The midpoint
  needs 54 bits, which is why the expansion above takes a mantissa rather than a
  Double.

  Out-of-range inputs fall out correctly rather than needing a guard: below the
  smallest denormal the search settles on bits 0 and the midpoint test rounds to
  zero, and above DBL_MAX it settles on DBL_MAX whose "next up" bit pattern is
  +Inf. }
function ExDecNearest(const ds: AnsiString; decExp, nd, expo: Integer): Double;
var
  lo, hi, mid, mant, maxbits, step, eb: Int64;
  exp2, cmp: Integer;
  cds, mds: AnsiString;
  cexp, mexp: Integer;
  c, est: Double;

  { sign of exact(bits) - D }
  function CmpBits(b: Int64): Integer;
  var d: Double; xs: AnsiString; xe: Integer;
  begin
    d := ExDecBitsToDouble(b);
    if b = 0 then begin CmpBits := -1; Exit; end;   { 0 < D, D is positive }
    ExDecDigits(d, xs, xe);
    CmpBits := ExDecCmp(xs, xe, ds, decExp);
  end;

begin
  { DBL_MAX = biased exponent 2046, mantissa all ones }
  maxbits := (Int64(2046) shl 52) or ((Int64(1) shl 52) - 1);

  { Seed from the float estimate, then widen by doubling steps until the
    bracket provably straddles D. The estimate's error is never assumed —
    if it is wildly wrong the doubling simply runs until it reaches the ends,
    which is the unseeded search and still correct. }
  est := ExDecEstimate(ds, nd, expo);
  if (est <> est) or (est >= 1.7976931348623157e308) then eb := maxbits
  else if est <= 0.0 then eb := 0
  else
  begin
    eb := ExDecDoubleToBits(est);
    if eb < 0 then eb := 0;
    if eb > maxbits then eb := maxbits;
  end;

  lo := eb;
  step := 1;
  while (lo > 0) and (CmpBits(lo) > 0) do
  begin
    lo := lo - step;
    if lo < 0 then lo := 0;
    step := step * 2;
  end;

  hi := eb;
  step := 1;
  while (hi < maxbits) and (CmpBits(hi) < 0) do
  begin
    hi := hi + step;
    if hi > maxbits then hi := maxbits;
    step := step * 2;
  end;

  { largest bit pattern whose exact value is <= D }
  while lo < hi do
  begin
    mid := lo + (hi - lo + 1) div 2;
    if CmpBits(mid) <= 0 then lo := mid else hi := mid - 1;
  end;

  c := ExDecBitsToDouble(lo);
  if lo <> 0 then
  begin
    ExDecDigits(c, cds, cexp);
    if ExDecCmp(cds, cexp, ds, decExp) = 0 then begin Result := c; Exit; end;
  end;

  ExDecSplit(c, mant, exp2);
  ExDecOfMant(2 * mant + 1, exp2 - 1, mds, mexp);
  cmp := ExDecCmp(ds, decExp, mds, mexp);
  if cmp > 0 then Result := ExDecBitsToDouble(lo + 1)
  else if cmp < 0 then Result := c
  else if (mant mod 2) = 0 then Result := c          { exact tie -> even }
  else Result := ExDecBitsToDouble(lo + 1);
end;

{ ---- decimal -> double, correctly rounded, compared in BINARY --------------

  The same question ExDecNearest answers, with the same guarantee — correctly
  rounded by construction, never an estimate that could be off by an unknown
  number of ULP — but comparing in binary big-integer arithmetic instead of
  expanding every candidate to its exact DECIMAL.

  WHY, AND WHY IT SITS BESIDE ExDecNearest RATHER THAN REPLACING IT.
  ExDecNearest's cost is not the number of comparisons (measured at ~4 per
  parse, not the 63 its header's worst case suggests) — it is the price of ONE.
  Each comparison expands a candidate double to its exact decimal, which for a
  subnormal is ~765 digits reached by ~82 rounds of big-decimal multiply, every
  round two 64-bit DIVISIONS per limb. Eisel-Lemire removed that cost for
  normal values but declines below the normal floor by construction, as Go and
  Rust do, so the subnormal rows of
  bug-b-strtofloat-is-3600x-slower-than-cpython-for-small-exponents never moved.

  In binary the same comparison is

      m * 2^k   ?   d * 10^expo

  and 10^expo = 2^expo * 5^expo, so every power of two becomes a SHIFT and only
  the power of five is a multiply. Better: d and expo are fixed for the whole
  search while only the candidate's m and k move, so 5^|expo| is built ONCE per
  parse instead of once per comparison.

  It DECLINES rather than guesses — the same composition as EiselLemire above.
  Every capacity check returns False and falls through to ExDecNearest, which is
  untouched and has no size limit. A buffer that turned out too small is
  therefore a slower answer, never a wrong one.

  Base 2^64 in UInt64 limbs. The carry out of a limb multiply is the HIGH half
  of the 128-bit product, which MulHiU64 (lib/rtl/wideint.pas) supplies —
  intrinsic via IR_MULHI on 64-bit targets, Pascal fallback on 32-bit — and
  which EiselLemire already uses in this same unit. Nothing here needs a
  128-bit type: the low half wraps naturally and a carry is detected by the
  sum coming out smaller than an addend, which is why every limb is UNSIGNED.
  That last point is load-bearing rather than stylistic — the same code over
  Int64 limbs would compare and shift signed, and a limb with its top bit set
  is the common case, not the corner. }
const
  PXX_BIGF_LIMBS = 112;              { 7168 bits — see the bound in ExBinNearest }
  PXX_BIGF_P5_27 = UInt64(7450580596923828125);
                                     { 5^27, the largest power of five under 2^64 }
type
  TBigF = array[0..PXX_BIGF_LIMBS - 1] of UInt64;

procedure BigFNorm(var a: TBigF; var n: Integer);
begin
  while (n > 1) and (a[n - 1] = 0) do n := n - 1;
end;

procedure BigFCopy(const src: TBigF; sn: Integer; var dst: TBigF; var dn: Integer);
var i: Integer;
begin
  for i := 0 to sn - 1 do dst[i] := src[i];
  dn := sn;
end;

{ a := a * f, for any f. An n-limb number times one limb is at most n+1 limbs,
  so the carry out of the loop is a single limb and needs no loop of its own —
  hi <= 2^64-2 always, since (2^64-1)^2 + (2^64-1) = (2^64-1)*2^64. }
function BigFMulSmall(var a: TBigF; var n: Integer; f: UInt64): Boolean;
var i: Integer; lo, t, carry: UInt64;
begin
  carry := 0;
  for i := 0 to n - 1 do
  begin
    lo := a[i] * f;
    t := lo + carry;
    carry := MulHiU64(a[i], f);
    if t < lo then carry := carry + 1;
    a[i] := t;
  end;
  if carry <> 0 then
  begin
    if n >= PXX_BIGF_LIMBS then begin BigFMulSmall := False; Exit; end;
    a[n] := carry;
    n := n + 1;
  end;
  BigFNorm(a, n);                     { f = 0 leaves every limb zero }
  BigFMulSmall := True;
end;

function BigFAddSmall(var a: TBigF; var n: Integer; v: UInt64): Boolean;
var i: Integer; t: UInt64;
begin
  i := 0;
  while v <> 0 do
  begin
    if i >= PXX_BIGF_LIMBS then begin BigFAddSmall := False; Exit; end;
    if i >= n then begin a[i] := 0; n := i + 1; end;
    t := a[i] + v;
    if t < v then v := 1 else v := 0;   { wrapped == carry out }
    a[i] := t;
    i := i + 1;
  end;
  BigFAddSmall := True;
end;

{ The `b > 0` guard is not an optimisation: `x shr (64 - b)` with b = 0 is a
  shift by the full width, which is undefined rather than zero, so the carry
  must be read out of the original limb only when there is one. }
function BigFShl(var a: TBigF; var n: Integer; bits: Integer): Boolean;
var words, b, i: Integer; cur, carry: UInt64;
begin
  BigFShl := False;
  if bits < 0 then Exit;
  if (n = 1) and (a[0] = 0) then begin BigFShl := True; Exit; end;
  b := bits mod 64;
  words := bits div 64;
  if b > 0 then
  begin
    carry := 0;
    for i := 0 to n - 1 do
    begin
      cur := a[i];
      a[i] := (cur shl b) or carry;
      carry := cur shr (64 - b);
    end;
    if carry > 0 then
    begin
      if n >= PXX_BIGF_LIMBS then Exit;
      a[n] := carry; n := n + 1;
    end;
  end;
  if words > 0 then
  begin
    if n + words > PXX_BIGF_LIMBS then Exit;
    for i := n - 1 downto 0 do a[i + words] := a[i];
    for i := 0 to words - 1 do a[i] := 0;
    n := n + words;
  end;
  BigFShl := True;
end;

{ a := a * v. Base 2^64 leaves nothing for this to do beyond BigFMulSmall —
  the split-into-two-halves-and-add dance it used to perform was entirely an
  artifact of the sub-2^31 cap on a base-2^32 multiplier. Kept as a named
  routine so the call sites still read as "multiply by a full-width value". }
function BigFMulU64(var a: TBigF; var n: Integer; v: UInt64): Boolean;
begin
  BigFMulU64 := BigFMulSmall(a, n, v);
end;

{ a := a * 5^k, in place. Twenty-seven at a time: 5^27 is the largest power of
  five under 2^64, and any multiplier fits now, so this is simply the biggest
  chunk the base allows. }
function BigFMulPow5(var a: TBigF; var n: Integer; k: Integer): Boolean;
begin
  BigFMulPow5 := False;
  if k < 0 then Exit;
  while k >= 27 do
  begin
    if not BigFMulSmall(a, n, PXX_BIGF_P5_27) then Exit;
    k := k - 27;
  end;
  while k > 0 do
  begin
    if not BigFMulSmall(a, n, 5) then Exit;
    k := k - 1;
  end;
  BigFMulPow5 := True;
end;

function BigFPow5(k: Integer; var a: TBigF; var n: Integer): Boolean;
begin
  a[0] := 1; n := 1;
  BigFPow5 := BigFMulPow5(a, n, k);
end;

{ Eighteen digits at a time: 10^18 is the largest power of ten under 2^64. }
function BigFFromDigits(const ds: AnsiString; nd: Integer;
                        var a: TBigF; var n: Integer): Boolean;
var i, j, chunk: Integer; v, p: UInt64;
begin
  BigFFromDigits := False;
  a[0] := 0; n := 1;
  i := 1;
  while i <= nd do
  begin
    chunk := nd - i + 1;
    if chunk > 18 then chunk := 18;
    v := 0; p := 1;
    for j := 0 to chunk - 1 do
    begin
      v := v * 10 + UInt64(Ord(ds[i + j]) - Ord('0'));
      p := p * 10;
    end;
    if not BigFMulSmall(a, n, p) then Exit;
    if not BigFAddSmall(a, n, v) then Exit;
    i := i + chunk;
  end;
  BigFFromDigits := True;
end;

function BigFCmp(const a: TBigF; na: Integer; const b: TBigF; nb: Integer): Integer;
var i: Integer;
begin
  if na <> nb then
  begin
    if na < nb then BigFCmp := -1 else BigFCmp := 1;
    Exit;
  end;
  for i := na - 1 downto 0 do
    if a[i] <> b[i] then
    begin
      if a[i] < b[i] then BigFCmp := -1 else BigFCmp := 1;
      Exit;
    end;
  BigFCmp := 0;
end;

{ Sign of (mv * 2^ev) - D, where D = int(ds) * 10^expo is carried in the two
  candidate-independent operands the caller built once:

    p5ta    = 5^ta                with ta = max(0, -expo)
    rhsBase = int(ds) * 5^tb      with tb = max(0,  expo)

  so the comparison is

      mv * 5^ta * 2^(SB+ta)   ?   int(ds) * 5^tb * 2^(SA+tb)

  with SA = max(0,-ev), SB = max(0,ev), after cancelling 2^min from both sides —
  free, and worth about a third of a subnormal's operand size, since its ev is
  -1074 and that shift alone is 1074 bits.

  `ok` is cleared if either operand would not fit, and the caller then declines
  to ExDecNearest. Top-level rather than nested inside ExBinNearest because a
  nested routine cannot capture a fixed-size array yet
  (feature-nested-routine-fixed-array-capture) — and both callers wanted the
  same body regardless. }
function BigFCmpValue(const p5ta: TBigF; p5n: Integer;
                      const rhsBase: TBigF; rhsn: Integer;
                      ta, tb: Integer; mv: Int64; ev: Integer;
                      var ok: Boolean): Integer;
var
  lhs, rhs: TBigF;
  ln, rn, sa, sb, e2l, e2r, cc: Integer;
begin
  BigFCmpValue := 0;
  if ev >= 0 then begin sa := 0; sb := ev; end
  else begin sa := -ev; sb := 0; end;
  e2l := sb + ta;
  e2r := sa + tb;
  if e2l < e2r then cc := e2l else cc := e2r;
  e2l := e2l - cc;
  e2r := e2r - cc;
  BigFCopy(p5ta, p5n, lhs, ln);
  if not BigFMulU64(lhs, ln, mv) then begin ok := False; Exit; end;
  if not BigFShl(lhs, ln, e2l) then begin ok := False; Exit; end;
  BigFCopy(rhsBase, rhsn, rhs, rn);
  if not BigFShl(rhs, rn, e2r) then begin ok := False; Exit; end;
  BigFCmpValue := BigFCmp(lhs, ln, rhs, rn);
end;

{ Sign of exact(bits) - D for a positive-double bit pattern. }
function BigFCmpBits(const p5ta: TBigF; p5n: Integer;
                     const rhsBase: TBigF; rhsn: Integer;
                     ta, tb: Integer; b: Int64; var ok: Boolean): Integer;
var mm: Int64; ex2: Integer;
begin
  if b = 0 then begin BigFCmpBits := -1; Exit; end;   { 0 < D, D is positive }
  ExDecSplit(ExDecBitsToDouble(b), mm, ex2);
  if mm = 0 then begin BigFCmpBits := -1; Exit; end;
  BigFCmpBits := BigFCmpValue(p5ta, p5n, rhsBase, rhsn, ta, tb, mm, ex2, ok);
end;

{ The double nearest the positive decimal int(ds) * 10^expo, correctly rounded,
  ties to even. False = declined; the caller must fall back to ExDecNearest.

  The search is ExDecNearest's, unchanged and for the same reason: for positive
  doubles the IEEE bit pattern rises monotonically with the value, so "largest
  double <= D" is an ordered search, seeded by a float estimate that is never
  trusted — only used to start the bracket, which then proves itself. What is
  different is the comparator, and only the comparator.

  The midpoint between a double and the next one up is exactly
  (2*mant + 1) * 2^(exp2 - 1) — one formula that holds across a power-of-two
  boundary and across the denormal/normal boundary alike, because incrementing
  the bit pattern is exactly what both of those transitions are.

  Out-of-range inputs fall out rather than needing a guard: below the smallest
  denormal the search settles on bits 0 and the midpoint test rounds to zero;
  above DBL_MAX it settles on DBL_MAX, whose next-up bit pattern is +Inf. }
function ExBinNearest(const ds: AnsiString; decExp, nd, expo: Integer;
                      var value: Double): Boolean;
var
  lo, hi, mid, mant, maxbits, step, eb: Int64;
  exp2, cmp, ta, tb: Integer;
  p5ta, rhsBase: TBigF;
  p5n, rhsn: Integer;
  cd, est: Double;
  ok: Boolean;
begin
  ExBinNearest := False;

  { Decline outside a few decades of the double range. Not a correctness guard
    — ExDecNearest answers those — but a SIZE one: an exponent like 1e-999999
    would ask for 5^999999, while the old path settles such a value in one or
    two comparisons anyway, because its estimate clamps straight to 0 or DBL_MAX
    and the bracket closes immediately. With decExp bounded here and nd bounded
    by the parser's 1200-digit cap, the largest operand either side can reach is
    about 6500 bits, inside the 7168 the limb array holds. Every routine above
    still range-checks, so an error in that bound costs a decline, not a wrong
    answer. }
  if (decExp > 400) or (decExp < -450) then Exit;
  if (nd < 1) or (nd > 1201) then Exit;

  if expo >= 0 then begin ta := 0; tb := expo; end
  else begin ta := -expo; tb := 0; end;

  { The two candidate-independent operands, built once for the whole search.
    int(ds) * 5^tb needs no big-by-big multiply — 5^tb is applied to the digits
    in place in sub-2^31 chunks, which is why only BigFMulSmall exists here. }
  if not BigFFromDigits(ds, nd, rhsBase, rhsn) then Exit;
  if not BigFMulPow5(rhsBase, rhsn, tb) then Exit;
  if not BigFPow5(ta, p5ta, p5n) then Exit;

  ok := True;
  { DBL_MAX = biased exponent 2046, mantissa all ones }
  maxbits := (Int64(2046) shl 52) or ((Int64(1) shl 52) - 1);

  est := ExDecEstimate(ds, nd, expo);
  if (est <> est) or (est >= 1.7976931348623157e308) then eb := maxbits
  else if est <= 0.0 then
  begin
    { The float estimate underflowed to zero — which happens for EVERY value
      below ~1e-308, i.e. exactly the subnormals this path exists for, so
      seeding at zero would be the common case and not the rare one. From zero
      the doubling walk climbs to the answer one power of two at a time (about
      44 steps for 1e-310) and the binary search then comes back down: ~90
      comparisons where a good seed needs a handful. Measured, before and after:
      1e-310 went 11.5 us -> 1.5 us on this line alone.

      So estimate it SCALED. A subnormal's bit pattern IS value * 2^1074, and
      2^1074 / 10^350 is itself an ordinary double (~2.02e-27), so

          bits ~ (d * 10^(expo+350)) * (2^1074 / 10^350)

      keeps both factors in the normal range. Still only a seed — nothing below
      trusts it, the bracket proves itself either way — so a value genuinely
      below the smallest subnormal simply underflows again and seeds 0, which is
      then correct rather than merely close. }
    est := ExDecEstimate(ds, nd, expo + 350) * 2.0240225330731063e-27;
    if (est <> est) or (est <= 0.0) then eb := 0
    else if est >= 4.5035996273704960e15 then eb := maxbits   { 2^52, past subnormal }
    else eb := Trunc(est);
  end
  else
  begin
    eb := ExDecDoubleToBits(est);
    if eb < 0 then eb := 0;
    if eb > maxbits then eb := maxbits;
  end;

  lo := eb;
  step := 1;
  while (lo > 0) and
        (BigFCmpBits(p5ta, p5n, rhsBase, rhsn, ta, tb, lo, ok) > 0) do
  begin
    if not ok then Exit;
    lo := lo - step;
    if lo < 0 then lo := 0;
    step := step * 2;
  end;
  if not ok then Exit;

  hi := eb;
  step := 1;
  while (hi < maxbits) and
        (BigFCmpBits(p5ta, p5n, rhsBase, rhsn, ta, tb, hi, ok) < 0) do
  begin
    if not ok then Exit;
    hi := hi + step;
    if hi > maxbits then hi := maxbits;
    step := step * 2;
  end;
  if not ok then Exit;

  { largest bit pattern whose exact value is <= D }
  while lo < hi do
  begin
    mid := lo + (hi - lo + 1) div 2;
    if BigFCmpBits(p5ta, p5n, rhsBase, rhsn, ta, tb, mid, ok) <= 0 then lo := mid
    else hi := mid - 1;
    if not ok then Exit;
  end;

  cd := ExDecBitsToDouble(lo);
  if lo <> 0 then
  begin
    cmp := BigFCmpBits(p5ta, p5n, rhsBase, rhsn, ta, tb, lo, ok);
    if not ok then Exit;
    if cmp = 0 then
    begin
      value := cd;
      ExBinNearest := True;
      Exit;
    end;
  end;

  ExDecSplit(cd, mant, exp2);
  { BigFCmpValue gives midpoint - D; the decision below wants D - midpoint }
  cmp := -BigFCmpValue(p5ta, p5n, rhsBase, rhsn, ta, tb, 2 * mant + 1, exp2 - 1, ok);
  if not ok then Exit;
  if cmp > 0 then value := ExDecBitsToDouble(lo + 1)
  else if cmp < 0 then value := cd
  else if (mant mod 2) = 0 then value := cd          { exact tie -> even }
  else value := ExDecBitsToDouble(lo + 1);
  ExBinNearest := True;
end;

{ The one parser. StrToFloatDef, TryStrToFloat and StrToFloat are all thin
  wrappers over it -- there is exactly one scan per call, and failure is a
  returned flag rather than an answer that has to be probed for. }

{ ---- Eisel-Lemire: the fast path for everything Clinger cannot reach ------

  Clinger's exact-multiply path above needs BOTH the significand and 10^|expo|
  to be exactly representable, which caps it at 15 digits and |expo| <= 22.
  Everything past that fell to ExDecNearest, whose every comparison expands a
  candidate double to its EXACT decimal (~765 digits for a subnormal). That is
  correct by construction and priced accordingly — 17 us at expo=23, half a
  millisecond at expo=-300.

  Eisel-Lemire (what CPython, Go, Rust and Abseil use) answers with ONE 128-bit
  multiply against a table of truncated powers of ten. The property that makes
  it safe to bolt in front of an exact parser rather than replace it: it
  DETECTS the cases where the truncated product cannot decide the rounding and
  DECLINES, rather than guessing. So the composition is fast-path, Lemire, then
  ExDecNearest for the residue — and the residue is still correctly rounded by
  construction, because nothing about ExDecNearest changed.

  WHAT IT DECLINES, all of which fall through to ExDecNearest and are therefore
  still exactly right, just not fast:
    * a SUBNORMAL result. This is the reference algorithm's own boundary, not a
      shortcut taken here: below the normal floor there are fewer than 53 bits
      of significand and the truncated 128-bit product no longer carries enough
      to settle the rounding. Declining is the whole reason this can be trusted.
      It also means the two rows this ticket named "small" (1e-310, 1e-320) are
      NOT sped up by this — both are subnormal. Measured, stated, not papered over.
    * overflow to infinity, and any |q| outside the table.
    * more than 19 significant digits (would not fit the u64 significand).
    * the handful of genuinely ambiguous products the two checks below catch.

  The 128-bit multiply itself is MulHiU64 from lib/rtl/wideint.pas — an
  intrinsic (one instruction) on 64-bit targets, a schoolbook fallback on
  32-bit. The low half of a 128-bit product is just the wrapping a*b.

  Table: floor(10^q * 2^k) normalised so the top bit is set, q = -348..347, the
  same range Go's strconv uses. Generated, then checked against a published
  reference entry before it was trusted (q=-348 is FA8FD5A0081C0288 /
  1732C869CD60E453). These are INTEGER literals, so nothing here re-enters the
  float parser this code is part of.

  WHAT THE TABLE COSTS, since it is paid by every binary that links sysutils
  and not only by ones that parse floats: **+11 KB of DATA**, which is the
  table's own bytes, and nothing else.

  It used to cost +42 KB of CODE and +11 KB of bss and ~22 us of startup,
  because the compiler emitted a typed const array as fill-it-at-startup code
  (~29 bytes of machine code per element) instead of as initialised data.
  Encoding the table as a string blob would have dodged that and was
  deliberately NOT done — it would have hidden the compiler bug and made the
  table unauditable, which the platonic-code rule forbids. The bug was fixed
  instead (2026-08-21,
  [[bug-a-a-typed-const-array-is-built-by-startup-code-not-stored-as-data]])
  and this unit lost **40.7 KB of code and 11 KB of bss with no edit here** —
  which is the whole argument for not working around a compiler bug, written
  out as a measurement.

  It also costs about 5% on the Clinger fast path above — measured, interleaved
  A/B, and attributable to code layout rather than to any added work on that
  path (adding the same local to the old parser without the table changed
  nothing). That is the trade: ~5% on the common case to take everything
  outside Clinger's window from 18-526 us down to well under 1 us.

  [[bug-b-strtofloat-is-3600x-slower-than-cpython-for-small-exponents]] }

const
  EL_MIN_Q = -348;
  EL_MAX_Q = 347;

  P10Hi: array[0..695] of UInt64 = (
    $FA8FD5A0081C0288, $9C99E58405118195, $C3C05EE50655E1FA, $F4B0769E47EB5A78,
    $98EE4A22ECF3188B, $BF29DCABA82FDEAE, $EEF453D6923BD65A, $9558B4661B6565F8,
    $BAAEE17FA23EBF76, $E95A99DF8ACE6F53, $91D8A02BB6C10594, $B64EC836A47146F9,
    $E3E27A444D8D98B7, $8E6D8C6AB0787F72, $B208EF855C969F4F, $DE8B2B66B3BC4723,
    $8B16FB203055AC76, $ADDCB9E83C6B1793, $D953E8624B85DD78, $87D4713D6F33AA6B,
    $A9C98D8CCB009506, $D43BF0EFFDC0BA48, $84A57695FE98746D, $A5CED43B7E3E9188,
    $CF42894A5DCE35EA, $818995CE7AA0E1B2, $A1EBFB4219491A1F, $CA66FA129F9B60A6,
    $FD00B897478238D0, $9E20735E8CB16382, $C5A890362FDDBC62, $F712B443BBD52B7B,
    $9A6BB0AA55653B2D, $C1069CD4EABE89F8, $F148440A256E2C76, $96CD2A865764DBCA,
    $BC807527ED3E12BC, $EBA09271E88D976B, $93445B8731587EA3, $B8157268FDAE9E4C,
    $E61ACF033D1A45DF, $8FD0C16206306BAB, $B3C4F1BA87BC8696, $E0B62E2929ABA83C,
    $8C71DCD9BA0B4925, $AF8E5410288E1B6F, $DB71E91432B1A24A, $892731AC9FAF056E,
    $AB70FE17C79AC6CA, $D64D3D9DB981787D, $85F0468293F0EB4E, $A76C582338ED2621,
    $D1476E2C07286FAA, $82CCA4DB847945CA, $A37FCE126597973C, $CC5FC196FEFD7D0C,
    $FF77B1FCBEBCDC4F, $9FAACF3DF73609B1, $C795830D75038C1D, $F97AE3D0D2446F25,
    $9BECCE62836AC577, $C2E801FB244576D5, $F3A20279ED56D48A, $9845418C345644D6,
    $BE5691EF416BD60C, $EDEC366B11C6CB8F, $94B3A202EB1C3F39, $B9E08A83A5E34F07,
    $E858AD248F5C22C9, $91376C36D99995BE, $B58547448FFFFB2D, $E2E69915B3FFF9F9,
    $8DD01FAD907FFC3B, $B1442798F49FFB4A, $DD95317F31C7FA1D, $8A7D3EEF7F1CFC52,
    $AD1C8EAB5EE43B66, $D863B256369D4A40, $873E4F75E2224E68, $A90DE3535AAAE202,
    $D3515C2831559A83, $8412D9991ED58091, $A5178FFF668AE0B6, $CE5D73FF402D98E3,
    $80FA687F881C7F8E, $A139029F6A239F72, $C987434744AC874E, $FBE9141915D7A922,
    $9D71AC8FADA6C9B5, $C4CE17B399107C22, $F6019DA07F549B2B, $99C102844F94E0FB,
    $C0314325637A1939, $F03D93EEBC589F88, $96267C7535B763B5, $BBB01B9283253CA2,
    $EA9C227723EE8BCB, $92A1958A7675175F, $B749FAED14125D36, $E51C79A85916F484,
    $8F31CC0937AE58D2, $B2FE3F0B8599EF07, $DFBDCECE67006AC9, $8BD6A141006042BD,
    $AECC49914078536D, $DA7F5BF590966848, $888F99797A5E012D, $AAB37FD7D8F58178,
    $D5605FCDCF32E1D6, $855C3BE0A17FCD26, $A6B34AD8C9DFC06F, $D0601D8EFC57B08B,
    $823C12795DB6CE57, $A2CB1717B52481ED, $CB7DDCDDA26DA268, $FE5D54150B090B02,
    $9EFA548D26E5A6E1, $C6B8E9B0709F109A, $F867241C8CC6D4C0, $9B407691D7FC44F8,
    $C21094364DFB5636, $F294B943E17A2BC4, $979CF3CA6CEC5B5A, $BD8430BD08277231,
    $ECE53CEC4A314EBD, $940F4613AE5ED136, $B913179899F68584, $E757DD7EC07426E5,
    $9096EA6F3848984F, $B4BCA50B065ABE63, $E1EBCE4DC7F16DFB, $8D3360F09CF6E4BD,
    $B080392CC4349DEC, $DCA04777F541C567, $89E42CAAF9491B60, $AC5D37D5B79B6239,
    $D77485CB25823AC7, $86A8D39EF77164BC, $A8530886B54DBDEB, $D267CAA862A12D66,
    $8380DEA93DA4BC60, $A46116538D0DEB78, $CD795BE870516656, $806BD9714632DFF6,
    $A086CFCD97BF97F3, $C8A883C0FDAF7DF0, $FAD2A4B13D1B5D6C, $9CC3A6EEC6311A63,
    $C3F490AA77BD60FC, $F4F1B4D515ACB93B, $991711052D8BF3C5, $BF5CD54678EEF0B6,
    $EF340A98172AACE4, $9580869F0E7AAC0E, $BAE0A846D2195712, $E998D258869FACD7,
    $91FF83775423CC06, $B67F6455292CBF08, $E41F3D6A7377EECA, $8E938662882AF53E,
    $B23867FB2A35B28D, $DEC681F9F4C31F31, $8B3C113C38F9F37E, $AE0B158B4738705E,
    $D98DDAEE19068C76, $87F8A8D4CFA417C9, $A9F6D30A038D1DBC, $D47487CC8470652B,
    $84C8D4DFD2C63F3B, $A5FB0A17C777CF09, $CF79CC9DB955C2CC, $81AC1FE293D599BF,
    $A21727DB38CB002F, $CA9CF1D206FDC03B, $FD442E4688BD304A, $9E4A9CEC15763E2E,
    $C5DD44271AD3CDBA, $F7549530E188C128, $9A94DD3E8CF578B9, $C13A148E3032D6E7,
    $F18899B1BC3F8CA1, $96F5600F15A7B7E5, $BCB2B812DB11A5DE, $EBDF661791D60F56,
    $936B9FCEBB25C995, $B84687C269EF3BFB, $E65829B3046B0AFA, $8FF71A0FE2C2E6DC,
    $B3F4E093DB73A093, $E0F218B8D25088B8, $8C974F7383725573, $AFBD2350644EEACF,
    $DBAC6C247D62A583, $894BC396CE5DA772, $AB9EB47C81F5114F, $D686619BA27255A2,
    $8613FD0145877585, $A798FC4196E952E7, $D17F3B51FCA3A7A0, $82EF85133DE648C4,
    $A3AB66580D5FDAF5, $CC963FEE10B7D1B3, $FFBBCFE994E5C61F, $9FD561F1FD0F9BD3,
    $C7CABA6E7C5382C8, $F9BD690A1B68637B, $9C1661A651213E2D, $C31BFA0FE5698DB8,
    $F3E2F893DEC3F126, $986DDB5C6B3A76B7, $BE89523386091465, $EE2BA6C0678B597F,
    $94DB483840B717EF, $BA121A4650E4DDEB, $E896A0D7E51E1566, $915E2486EF32CD60,
    $B5B5ADA8AAFF80B8, $E3231912D5BF60E6, $8DF5EFABC5979C8F, $B1736B96B6FD83B3,
    $DDD0467C64BCE4A0, $8AA22C0DBEF60EE4, $AD4AB7112EB3929D, $D89D64D57A607744,
    $87625F056C7C4A8B, $A93AF6C6C79B5D2D, $D389B47879823479, $843610CB4BF160CB,
    $A54394FE1EEDB8FE, $CE947A3DA6A9273E, $811CCC668829B887, $A163FF802A3426A8,
    $C9BCFF6034C13052, $FC2C3F3841F17C67, $9D9BA7832936EDC0, $C5029163F384A931,
    $F64335BCF065D37D, $99EA0196163FA42E, $C06481FB9BCF8D39, $F07DA27A82C37088,
    $964E858C91BA2655, $BBE226EFB628AFEA, $EADAB0ABA3B2DBE5, $92C8AE6B464FC96F,
    $B77ADA0617E3BBCB, $E55990879DDCAABD, $8F57FA54C2A9EAB6, $B32DF8E9F3546564,
    $DFF9772470297EBD, $8BFBEA76C619EF36, $AEFAE51477A06B03, $DAB99E59958885C4,
    $88B402F7FD75539B, $AAE103B5FCD2A881, $D59944A37C0752A2, $857FCAE62D8493A5,
    $A6DFBD9FB8E5B88E, $D097AD07A71F26B2, $825ECC24C873782F, $A2F67F2DFA90563B,
    $CBB41EF979346BCA, $FEA126B7D78186BC, $9F24B832E6B0F436, $C6EDE63FA05D3143,
    $F8A95FCF88747D94, $9B69DBE1B548CE7C, $C24452DA229B021B, $F2D56790AB41C2A2,
    $97C560BA6B0919A5, $BDB6B8E905CB600F, $ED246723473E3813, $9436C0760C86E30B,
    $B94470938FA89BCE, $E7958CB87392C2C2, $90BD77F3483BB9B9, $B4ECD5F01A4AA828,
    $E2280B6C20DD5232, $8D590723948A535F, $B0AF48EC79ACE837, $DCDB1B2798182244,
    $8A08F0F8BF0F156B, $AC8B2D36EED2DAC5, $D7ADF884AA879177, $86CCBB52EA94BAEA,
    $A87FEA27A539E9A5, $D29FE4B18E88640E, $83A3EEEEF9153E89, $A48CEAAAB75A8E2B,
    $CDB02555653131B6, $808E17555F3EBF11, $A0B19D2AB70E6ED6, $C8DE047564D20A8B,
    $FB158592BE068D2E, $9CED737BB6C4183D, $C428D05AA4751E4C, $F53304714D9265DF,
    $993FE2C6D07B7FAB, $BF8FDB78849A5F96, $EF73D256A5C0F77C, $95A8637627989AAD,
    $BB127C53B17EC159, $E9D71B689DDE71AF, $9226712162AB070D, $B6B00D69BB55C8D1,
    $E45C10C42A2B3B05, $8EB98A7A9A5B04E3, $B267ED1940F1C61C, $DF01E85F912E37A3,
    $8B61313BBABCE2C6, $AE397D8AA96C1B77, $D9C7DCED53C72255, $881CEA14545C7575,
    $AA242499697392D2, $D4AD2DBFC3D07787, $84EC3C97DA624AB4, $A6274BBDD0FADD61,
    $CFB11EAD453994BA, $81CEB32C4B43FCF4, $A2425FF75E14FC31, $CAD2F7F5359A3B3E,
    $FD87B5F28300CA0D, $9E74D1B791E07E48, $C612062576589DDA, $F79687AED3EEC551,
    $9ABE14CD44753B52, $C16D9A0095928A27, $F1C90080BAF72CB1, $971DA05074DA7BEE,
    $BCE5086492111AEA, $EC1E4A7DB69561A5, $9392EE8E921D5D07, $B877AA3236A4B449,
    $E69594BEC44DE15B, $901D7CF73AB0ACD9, $B424DC35095CD80F, $E12E13424BB40E13,
    $8CBCCC096F5088CB, $AFEBFF0BCB24AAFE, $DBE6FECEBDEDD5BE, $89705F4136B4A597,
    $ABCC77118461CEFC, $D6BF94D5E57A42BC, $8637BD05AF6C69B5, $A7C5AC471B478423,
    $D1B71758E219652B, $83126E978D4FDF3B, $A3D70A3D70A3D70A, $CCCCCCCCCCCCCCCC,
    $8000000000000000, $A000000000000000, $C800000000000000, $FA00000000000000,
    $9C40000000000000, $C350000000000000, $F424000000000000, $9896800000000000,
    $BEBC200000000000, $EE6B280000000000, $9502F90000000000, $BA43B74000000000,
    $E8D4A51000000000, $9184E72A00000000, $B5E620F480000000, $E35FA931A0000000,
    $8E1BC9BF04000000, $B1A2BC2EC5000000, $DE0B6B3A76400000, $8AC7230489E80000,
    $AD78EBC5AC620000, $D8D726B7177A8000, $878678326EAC9000, $A968163F0A57B400,
    $D3C21BCECCEDA100, $84595161401484A0, $A56FA5B99019A5C8, $CECB8F27F4200F3A,
    $813F3978F8940984, $A18F07D736B90BE5, $C9F2C9CD04674EDE, $FC6F7C4045812296,
    $9DC5ADA82B70B59D, $C5371912364CE305, $F684DF56C3E01BC6, $9A130B963A6C115C,
    $C097CE7BC90715B3, $F0BDC21ABB48DB20, $96769950B50D88F4, $BC143FA4E250EB31,
    $EB194F8E1AE525FD, $92EFD1B8D0CF37BE, $B7ABC627050305AD, $E596B7B0C643C719,
    $8F7E32CE7BEA5C6F, $B35DBF821AE4F38B, $E0352F62A19E306E, $8C213D9DA502DE45,
    $AF298D050E4395D6, $DAF3F04651D47B4C, $88D8762BF324CD0F, $AB0E93B6EFEE0053,
    $D5D238A4ABE98068, $85A36366EB71F041, $A70C3C40A64E6C51, $D0CF4B50CFE20765,
    $82818F1281ED449F, $A321F2D7226895C7, $CBEA6F8CEB02BB39, $FEE50B7025C36A08,
    $9F4F2726179A2245, $C722F0EF9D80AAD6, $F8EBAD2B84E0D58B, $9B934C3B330C8577,
    $C2781F49FFCFA6D5, $F316271C7FC3908A, $97EDD871CFDA3A56, $BDE94E8E43D0C8EC,
    $ED63A231D4C4FB27, $945E455F24FB1CF8, $B975D6B6EE39E436, $E7D34C64A9C85D44,
    $90E40FBEEA1D3A4A, $B51D13AEA4A488DD, $E264589A4DCDAB14, $8D7EB76070A08AEC,
    $B0DE65388CC8ADA8, $DD15FE86AFFAD912, $8A2DBF142DFCC7AB, $ACB92ED9397BF996,
    $D7E77A8F87DAF7FB, $86F0AC99B4E8DAFD, $A8ACD7C0222311BC, $D2D80DB02AABD62B,
    $83C7088E1AAB65DB, $A4B8CAB1A1563F52, $CDE6FD5E09ABCF26, $80B05E5AC60B6178,
    $A0DC75F1778E39D6, $C913936DD571C84C, $FB5878494ACE3A5F, $9D174B2DCEC0E47B,
    $C45D1DF942711D9A, $F5746577930D6500, $9968BF6ABBE85F20, $BFC2EF456AE276E8,
    $EFB3AB16C59B14A2, $95D04AEE3B80ECE5, $BB445DA9CA61281F, $EA1575143CF97226,
    $924D692CA61BE758, $B6E0C377CFA2E12E, $E498F455C38B997A, $8EDF98B59A373FEC,
    $B2977EE300C50FE7, $DF3D5E9BC0F653E1, $8B865B215899F46C, $AE67F1E9AEC07187,
    $DA01EE641A708DE9, $884134FE908658B2, $AA51823E34A7EEDE, $D4E5E2CDC1D1EA96,
    $850FADC09923329E, $A6539930BF6BFF45, $CFE87F7CEF46FF16, $81F14FAE158C5F6E,
    $A26DA3999AEF7749, $CB090C8001AB551C, $FDCB4FA002162A63, $9E9F11C4014DDA7E,
    $C646D63501A1511D, $F7D88BC24209A565, $9AE757596946075F, $C1A12D2FC3978937,
    $F209787BB47D6B84, $9745EB4D50CE6332, $BD176620A501FBFF, $EC5D3FA8CE427AFF,
    $93BA47C980E98CDF, $B8A8D9BBE123F017, $E6D3102AD96CEC1D, $9043EA1AC7E41392,
    $B454E4A179DD1877, $E16A1DC9D8545E94, $8CE2529E2734BB1D, $B01AE745B101E9E4,
    $DC21A1171D42645D, $899504AE72497EBA, $ABFA45DA0EDBDE69, $D6F8D7509292D603,
    $865B86925B9BC5C2, $A7F26836F282B732, $D1EF0244AF2364FF, $8335616AED761F1F,
    $A402B9C5A8D3A6E7, $CD036837130890A1, $802221226BE55A64, $A02AA96B06DEB0FD,
    $C83553C5C8965D3D, $FA42A8B73ABBF48C, $9C69A97284B578D7, $C38413CF25E2D70D,
    $F46518C2EF5B8CD1, $98BF2F79D5993802, $BEEEFB584AFF8603, $EEAABA2E5DBF6784,
    $952AB45CFA97A0B2, $BA756174393D88DF, $E912B9D1478CEB17, $91ABB422CCB812EE,
    $B616A12B7FE617AA, $E39C49765FDF9D94, $8E41ADE9FBEBC27D, $B1D219647AE6B31C,
    $DE469FBD99A05FE3, $8AEC23D680043BEE, $ADA72CCC20054AE9, $D910F7FF28069DA4,
    $87AA9AFF79042286, $A99541BF57452B28, $D3FA922F2D1675F2, $847C9B5D7C2E09B7,
    $A59BC234DB398C25, $CF02B2C21207EF2E, $8161AFB94B44F57D, $A1BA1BA79E1632DC,
    $CA28A291859BBF93, $FCB2CB35E702AF78, $9DEFBF01B061ADAB, $C56BAEC21C7A1916,
    $F6C69A72A3989F5B, $9A3C2087A63F6399, $C0CB28A98FCF3C7F, $F0FDF2D3F3C30B9F,
    $969EB7C47859E743, $BC4665B596706114, $EB57FF22FC0C7959, $9316FF75DD87CBD8,
    $B7DCBF5354E9BECE, $E5D3EF282A242E81, $8FA475791A569D10, $B38D92D760EC4455,
    $E070F78D3927556A, $8C469AB843B89562, $AF58416654A6BABB, $DB2E51BFE9D0696A,
    $88FCF317F22241E2, $AB3C2FDDEEAAD25A, $D60B3BD56A5586F1, $85C7056562757456,
    $A738C6BEBB12D16C, $D106F86E69D785C7, $82A45B450226B39C, $A34D721642B06084,
    $CC20CE9BD35C78A5, $FF290242C83396CE, $9F79A169BD203E41, $C75809C42C684DD1,
    $F92E0C3537826145, $9BBCC7A142B17CCB, $C2ABF989935DDBFE, $F356F7EBF83552FE,
    $98165AF37B2153DE, $BE1BF1B059E9A8D6, $EDA2EE1C7064130C, $9485D4D1C63E8BE7,
    $B9A74A0637CE2EE1, $E8111C87C5C1BA99, $910AB1D4DB9914A0, $B54D5E4A127F59C8,
    $E2A0B5DC971F303A, $8DA471A9DE737E24, $B10D8E1456105DAD, $DD50F1996B947518,
    $8A5296FFE33CC92F, $ACE73CBFDC0BFB7B, $D8210BEFD30EFA5A, $8714A775E3E95C78,
    $A8D9D1535CE3B396, $D31045A8341CA07C, $83EA2B892091E44D, $A4E4B66B68B65D60,
    $CE1DE40642E3F4B9, $80D2AE83E9CE78F3, $A1075A24E4421730, $C94930AE1D529CFC,
    $FB9B7CD9A4A7443C, $9D412E0806E88AA5, $C491798A08A2AD4E, $F5B5D7EC8ACB58A2,
    $9991A6F3D6BF1765, $BFF610B0CC6EDD3F, $EFF394DCFF8A948E, $95F83D0A1FB69CD9,
    $BB764C4CA7A4440F, $EA53DF5FD18D5513, $92746B9BE2F8552C, $B7118682DBB66A77,
    $E4D5E82392A40515, $8F05B1163BA6832D, $B2C71D5BCA9023F8, $DF78E4B2BD342CF6,
    $8BAB8EEFB6409C1A, $AE9672ABA3D0C320, $DA3C0F568CC4F3E8, $8865899617FB1871,
    $AA7EEBFB9DF9DE8D, $D51EA6FA85785631, $8533285C936B35DE, $A67FF273B8460356,
    $D01FEF10A657842C, $8213F56A67F6B29B, $A298F2C501F45F42, $CB3F2F7642717713,
    $FE0EFB53D30DD4D7, $9EC95D1463E8A506, $C67BB4597CE2CE48, $F81AA16FDC1B81DA,
    $9B10A4E5E9913128, $C1D4CE1F63F57D72, $F24A01A73CF2DCCF, $976E41088617CA01,
    $BD49D14AA79DBC82, $EC9C459D51852BA2, $93E1AB8252F33B45, $B8DA1662E7B00A17,
    $E7109BFBA19C0C9D, $906A617D450187E2, $B484F9DC9641E9DA, $E1A63853BBD26451,
    $8D07E33455637EB2, $B049DC016ABC5E5F, $DC5C5301C56B75F7, $89B9B3E11B6329BA,
    $AC2820D9623BF429, $D732290FBACAF133, $867F59A9D4BED6C0, $A81F301449EE8C70,
    $D226FC195C6A2F8C, $83585D8FD9C25DB7, $A42E74F3D032F525, $CD3A1230C43FB26F,
    $80444B5E7AA7CF85, $A0555E361951C366, $C86AB5C39FA63440, $FA856334878FC150,
    $9C935E00D4B9D8D2, $C3B8358109E84F07, $F4A642E14C6262C8, $98E7E9CCCFBD7DBD,
    $BF21E44003ACDD2C, $EEEA5D5004981478, $95527A5202DF0CCB, $BAA718E68396CFFD,
    $E950DF20247C83FD, $91D28B7416CDD27E, $B6472E511C81471D, $E3D8F9E563A198E5,
    $8E679C2F5E44FF8F, $B201833B35D63F73, $DE81E40A034BCF4F, $8B112E86420F6191,
    $ADD57A27D29339F6, $D94AD8B1C7380874, $87CEC76F1C830548, $A9C2794AE3A3C69A,
    $D433179D9C8CB841, $849FEEC281D7F328, $A5C7EA73224DEFF3, $CF39E50FEAE16BEF,
    $81842F29F2CCE375, $A1E53AF46F801C53, $CA5E89B18B602368, $FCF62C1DEE382C42,
    $9E19DB92B4E31BA9, $C5A05277621BE293, $F70867153AA2DB38, $9A65406D44A5C903,
    $C0FE908895CF3B44, $F13E34AABB430A15, $96C6E0EAB509E64D, $BC789925624C5FE0,
    $EB96BF6EBADF77D8, $933E37A534CBAAE7, $B80DC58E81FE95A1, $E61136F2227E3B09,
    $8FCAC257558EE4E6, $B3BD72ED2AF29E1F, $E0ACCFA875AF45A7, $8C6C01C9498D8B88,
    $AF87023B9BF0EE6A, $DB68C2CA82ED2A05, $892179BE91D43A43, $AB69D82E364948D4,
    $D6444E39C3DB9B09, $85EAB0E41A6940E5, $A7655D1D2103911F, $D13EB46469447567);

  P10Lo: array[0..695] of UInt64 = (
    $1732C869CD60E453, $0E7FBD42205C8EB4, $521FAC92A873B261, $E6A797B752909EF9,
    $9028BED2939A635C, $7432EE873880FC33, $113FAA2906A13B3F, $4AC7CA59A424C507,
    $5D79BCF00D2DF649, $F4D82C2C107973DC, $79071B9B8A4BE869, $9748E2826CDEE284,
    $FD1B1B2308169B25, $FE30F0F5E50E20F7, $BDBD2D335E51A935, $AD2C788035E61382,
    $4C3BCB5021AFCC31, $DF4ABE242A1BBF3D, $D71D6DAD34A2AF0D, $8672648C40E5AD68,
    $680EFDAF511F18C2, $0212BD1B2566DEF2, $014BB630F7604B57, $419EA3BD35385E2D,
    $52064CAC828675B9, $7343EFEBD1940993, $1014EBE6C5F90BF8, $D41A26E077774EF6,
    $8920B098955522B4, $55B46E5F5D5535B0, $EB2189F734AA831D, $A5E9EC7501D523E4,
    $47B233C92125366E, $999EC0BB696E840A, $C00670EA43CA250D, $380406926A5E5728,
    $C605083704F5ECF2, $F7864A44C633682E, $7AB3EE6AFBE0211D, $5960EA05BAD82964,
    $6FB92487298E33BD, $A5D3B6D479F8E056, $8F48A4899877186C, $331ACDABFE94DE87,
    $9FF0C08B7F1D0B14, $07ECF0AE5EE44DD9, $C9E82CD9F69D6150, $BE311C083A225CD2,
    $6DBD630A48AAF406, $092CBBCCDAD5B108, $25BBF56008C58EA5, $AF2AF2B80AF6F24E,
    $1AF5AF660DB4AEE1, $50D98D9FC890ED4D, $E50FF107BAB528A0, $1E53ED49A96272C8,
    $25E8E89C13BB0F7A, $77B191618C54E9AC, $D59DF5B9EF6A2417, $4B0573286B44AD1D,
    $4EE367F9430AEC32, $229C41F793CDA73F, $6B43527578C1110F, $830A13896B78AAA9,
    $23CC986BC656D553, $2CBFBE86B7EC8AA8, $7BF7D71432F3D6A9, $DAF5CCD93FB0CC53,
    $D1B3400F8F9CFF68, $23100809B9C21FA1, $ABD40A0C2832A78A, $16C90C8F323F516C,
    $AE3DA7D97F6792E3, $99CD11CFDF41779C, $40405643D711D583, $482835EA666B2572,
    $DA3243650005EECF, $90BED43E40076A82, $5A7744A6E804A291, $711515D0A205CB36,
    $0D5A5B44CA873E03, $E858790AFE9486C2, $626E974DBE39A872, $FB0A3D212DC8128F,
    $7CE66634BC9D0B99, $1C1FFFC1EBC44E80, $A327FFB266B56220, $4BF1FF9F0062BAA8,
    $6F773FC3603DB4A9, $CB550FB4384D21D3, $7E2A53A146606A48, $2EDA7444CBFC426D,
    $FA911155FEFB5308, $793555AB7EBA27CA, $4BC1558B2F3458DE, $9EB1AAEDFB016F16,
    $465E15A979C1CADC, $0BFACD89EC191EC9, $CEF980EC671F667B, $82B7E12780E7401A,
    $D1B2ECB8B0908810, $861FA7E6DCB4AA15, $67A791E093E1D49A, $E0C8BB2C5C6D24E0,
    $58FAE9F773886E18, $AF39A475506A899E, $6D8406C952429603, $C8E5087BA6D33B83,
    $FB1E4A9A90880A64, $5CF2EEA09A55067F, $F42FAA48C0EA481E, $F13B94DAF124DA26,
    $76C53D08D6B70858, $54768C4B0C64CA6E, $A9942F5DCF7DFD09, $D3F93B35435D7C4C,
    $C47BC5014A1A6DAF, $359AB6419CA1091B, $C30163D203C94B62, $79E0DE63425DCF1D,
    $985915FC12F542E4, $3E6F5B7B17B2939D, $A705992CEECF9C42, $50C6FF782A838353,
    $A4F8BF5635246428, $871B7795E136BE99, $28E2557B59846E3F, $331AEADA2FE589CF,
    $3FF0D2C85DEF7621, $0FED077A756B53A9, $D3E8495912C62894, $64712DD7ABBBD95C,
    $BD8D794D96AACFB3, $ECF0D7A0FC5583A0, $F41686C49DB57244, $311C2875C522CED5,
    $7D633293366B828B, $AE5DFF9C02033197, $D9F57F830283FDFC, $D072DF63C324FD7B,
    $4247CB9E59F71E6D, $52D9BE85F074E608, $67902E276C921F8B, $00BA1CD8A3DB53B6,
    $80E8A40ECCD228A4, $6122CD128006B2CD, $796B805720085F81, $CBE3303674053BB0,
    $BEDBFC4411068A9C, $EE92FB5515482D44, $751BDD152D4D1C4A, $D262D45A78A0635D,
    $86FB897116C87C34, $D45D35E6AE3D4DA0, $8974836059CCA109, $2BD1A438703FC94B,
    $7B6306A34627DDCF, $1A3BC84C17B1D542, $20CABA5F1D9E4A93, $547EB47B7282EE9C,
    $E99E619A4F23AA43, $6405FA00E2EC94D4, $DE83BC408DD3DD04, $9624AB50B148D445,
    $3BADD624DD9B0957, $E54CA5D70A80E5D6, $5E9FCF4CCD211F4C, $7647C3200069671F,
    $29ECD9F40041E073, $F468107100525890, $7182148D4066EEB4, $C6F14CD848405530,
    $B8ADA00E5A506A7C, $A6D90811F0E4851C, $908F4A166D1DA663, $9A598E4E043287FE,
    $40EFF1E1853F29FD, $D12BEE59E68EF47C, $82BB74F8301958CE, $E36A52363C1FAF01,
    $DC44E6C3CB279AC1, $29AB103A5EF8C0B9, $7415D448F6B6F0E7, $111B495B3464AD21,
    $CAB10DD900BEEC34, $3D5D514F40EEA742, $0CB4A5A3112A5112, $47F0E785EABA72AB,
    $59ED216765690F56, $306869C13EC3532C, $1E414218C73A13FB, $E5D1929EF90898FA,
    $DF45F746B74ABF39, $6B8BBA8C328EB783, $066EA92F3F326564, $C80A537B0EFEFEBD,
    $BD06742CE95F5F36, $2C48113823B73704, $F75A15862CA504C5, $9A984D73DBE722FB,
    $C13E60D0D2E0EBBA, $318DF905079926A8, $FDF17746497F7052, $FEB6EA8BEDEFA633,
    $FE64A52EE96B8FC0, $3DFDCE7AA3C673B0, $06BEA10CA65C084E, $486E494FCFF30A62,
    $5A89DBA3C3EFCCFA, $F89629465A75E01C, $F6BBB397F1135823, $746AA07DED582E2C,
    $A8C2A44EB4571CDC, $92F34D62616CE413, $77B020BAF9C81D17, $0ACE1474DC1D122E,
    $0D819992132456BA, $10E1FFF697ED6C69, $CA8D3FFA1EF463C1, $BD308FF8A6B17CB2,
    $AC7CB3F6D05DDBDE, $6BCDF07A423AA96B, $86C16C98D2C953C6, $E871C7BF077BA8B7,
    $11471CD764AD4972, $D598E40D3DD89BCF, $4AFF1D108D4EC2C3, $CEDF722A585139BA,
    $C2974EB4EE658828, $733D226229FEEA32, $0806357D5A3F525F, $CA07C2DCB0CF26F7,
    $FC89B393DD02F0B5, $BBAC2078D443ACE2, $D54B944B84AA4C0D, $0A9E795E65D4DF11,
    $4D4617B5FF4A16D5, $504BCED1BF8E4E45, $E45EC2862F71E1D6, $5D767327BB4E5A4C,
    $3A6A07F8D510F86F, $890489F70A55368B, $2B45AC74CCEA842E, $3B0B8BC90012929D,
    $09CE6EBB40173744, $CC420A6A101D0515, $9FA946824A12232D, $47939822DC96ABF9,
    $59787E2B93BC56F7, $57EB4EDB3C55B65A, $EDE622920B6B23F1, $E95FAB368E45ECED,
    $11DBCB0218EBB414, $D652BDC29F26A119, $4BE76D3346F0495F, $6F70A4400C562DDB,
    $CB4CCD500F6BB952, $7E2000A41346A7A7, $8ED400668C0C28C8, $728900802F0F32FA,
    $4F2B40A03AD2FFB9, $E2F610C84987BFA8, $0DD9CA7D2DF4D7C9, $91503D1C79720DBB,
    $75A44C6397CE912A, $C986AFBE3EE11ABA, $FBE85BADCE996168, $FAE27299423FB9C3,
    $DCCD879FC967D41A, $5400E987BBC1C920, $290123E9AAB23B68, $F9A0B6720AAF6521,
    $F808E40E8D5B3E69, $B60B1D1230B20E04, $B1C6F22B5E6F48C2, $1E38AEB6360B1AF3,
    $25C6DA63C38DE1B0, $579C487E5A38AD0E, $2D835A9DF0C6D851, $F8E431456CF88E65,
    $1B8E9ECB641B58FF, $E272467E3D222F3F, $5B0ED81DCC6ABB0F, $98E947129FC2B4E9,
    $3F2398D747B36224, $8EEC7F0D19A03AAD, $1953CF68300424AC, $5FA8C3423C052DD7,
    $3792F412CB06794D, $E2BBD88BBEE40BD0, $5B6ACEAEAE9D0EC4, $F245825A5A445275,
    $EED6E2F0F0D56712, $55464DD69685606B, $AA97E14C3C26B886, $D53DD99F4B3066A8,
    $E546A8038EFE4029, $DE98520472BDD033, $963E66858F6D4440, $DDE7001379A44AA8,
    $5560C018580D5D52, $AAB8F01E6E10B4A6, $CAB3961304CA70E8, $3D607B97C5FD0D22,
    $8CB89A7DB77C506A, $77F3608E92ADB242, $55F038B237591ED3, $6B6C46DEC52F6688,
    $2323AC4B3B3DA015, $ABEC975E0A0D081A, $96E7BD358C904A21, $7E50D64177DA2E54,
    $DDE50BD1D5D0B9E9, $955E4EC64B44E864, $BD5AF13BEF0B113E, $ECB1AD8AEACDD58E,
    $67DE18EDA5814AF2, $80EACF948770CED7, $A1258379A94D028D, $096EE45813A04330,
    $8BCA9D6E188853FC, $775EA264CF55347D, $95364AFE032A819D, $3A83DDBD83F52204,
    $C4926A9672793542, $75B7053C0F178293, $5324C68B12DD6338, $D3F6FC16EBCA5E03,
    $88F4BB1CA6BCF584, $2B31E9E3D06C32E5, $3AFF322E62439FCF, $09BEFEB9FAD487C2,
    $4C2EBE687989A9B3, $0F9D37014BF60A10, $538484C19EF38C94, $2865A5F206B06FB9,
    $F93F87B7442E45D3, $F78F69A51539D748, $B573440E5A884D1B, $31680A88F8953030,
    $FDC20D2B36BA7C3D, $3D32907604691B4C, $A63F9A49C2C1B10F, $0FCF80DC33721D53,
    $D3C36113404EA4A8, $645A1CAC083126E9, $3D70A3D70A3D70A3, $CCCCCCCCCCCCCCCC,
    $0000000000000000, $0000000000000000, $0000000000000000, $0000000000000000,
    $0000000000000000, $0000000000000000, $0000000000000000, $0000000000000000,
    $0000000000000000, $0000000000000000, $0000000000000000, $0000000000000000,
    $0000000000000000, $0000000000000000, $0000000000000000, $0000000000000000,
    $0000000000000000, $0000000000000000, $0000000000000000, $0000000000000000,
    $0000000000000000, $0000000000000000, $0000000000000000, $0000000000000000,
    $0000000000000000, $0000000000000000, $0000000000000000, $0000000000000000,
    $4000000000000000, $5000000000000000, $A400000000000000, $4D00000000000000,
    $F020000000000000, $6C28000000000000, $C732000000000000, $3C7F400000000000,
    $4B9F100000000000, $1E86D40000000000, $1314448000000000, $17D955A000000000,
    $5DCFAB0800000000, $5AA1CAE500000000, $F14A3D9E40000000, $6D9CCD05D0000000,
    $E4820023A2000000, $DDA2802C8A800000, $D50B2037AD200000, $4526F422CC340000,
    $9670B12B7F410000, $3C0CDD765F114000, $A5880A69FB6AC800, $8EEA0D047A457A00,
    $72A4904598D6D880, $47A6DA2B7F864750, $999090B65F67D924, $FFF4B4E3F741CF6D,
    $BFF8F10E7A8921A4, $AFF72D52192B6A0D, $9BF4F8A69F764490, $02F236D04753D5B4,
    $01D762422C946590, $424D3AD2B7B97EF5, $D2E0898765A7DEB2, $63CC55F49F88EB2F,
    $3CBF6B71C76B25FB, $8BEF464E3945EF7A, $97758BF0E3CBB5AC, $3D52EEED1CBEA317,
    $4CA7AAA863EE4BDD, $8FE8CAA93E74EF6A, $B3E2FD538E122B44, $60DBBCA87196B616,
    $BC8955E946FE31CD, $6BABAB6398BDBE41, $C696963C7EED2DD1, $FC1E1DE5CF543CA2,
    $3B25A55F43294BCB, $49EF0EB713F39EBE, $6E3569326C784337, $49C2C37F07965404,
    $DC33745EC97BE906, $69A028BB3DED71A3, $C40832EA0D68CE0C, $F50A3FA490C30190,
    $792667C6DA79E0FA, $577001B891185938, $ED4C0226B55E6F86, $544F8158315B05B4,
    $696361AE3DB1C721, $03BC3A19CD1E38E9, $04AB48A04065C723, $62EB0D64283F9C76,
    $3BA5D0BD324F8394, $CA8F44EC7EE36479, $7E998B13CF4E1ECB, $9E3FEDD8C321A67E,
    $C5CFE94EF3EA101E, $BBA1F1D158724A12, $2A8A6E45AE8EDC97, $F52D09D71A3293BD,
    $593C2626705F9C56, $6F8B2FB00C77836C, $0B6DFB9C0F956447, $4724BD4189BD5EAC,
    $58EDEC91EC2CB657, $2F2967B66737E3ED, $BD79E0D20082EE74, $ECD8590680A3AA11,
    $E80E6F4820CC9495, $3109058D147FDCDD, $BD4B46F0599FD415, $6C9E18AC7007C91A,
    $03E2CF6BC604DDB0, $84DB8346B786151C, $E612641865679A63, $4FCB7E8F3F60C07E,
    $E3BE5E330F38F09D, $5CADF5BFD3072CC5, $73D9732FC7C8F7F6, $2867E7FDDCDD9AFA,
    $B281E1FD541501B8, $1F225A7CA91A4226, $3375788DE9B06958, $0052D6B1641C83AE,
    $C0678C5DBD23A49A, $F840B7BA963646E0, $B650E5A93BC3D898, $A3E51F138AB4CEBE,
    $C66F336C36B10137, $B80B0047445D4184, $A60DC059157491E5, $87C89837AD68DB2F,
    $29BABE4598C311FB, $F4296DD6FEF3D67A, $1899E4A65F58660C, $5EC05DCFF72E7F8F,
    $76707543F4FA1F73, $6A06494A791C53A8, $0487DB9D17636892, $45A9D2845D3C42B6,
    $0B8A2392BA45A9B2, $8E6CAC7768D7141E, $3207D795430CD926, $7F44E6BD49E807B8,
    $5F16206C9C6209A6, $36DBA887C37A8C0F, $C2494954DA2C9789, $F2DB9BAA10B7BD6C,
    $6F92829494E5ACC7, $CB772339BA1F17F9, $FF2A760414536EFB, $FEF5138519684ABA,
    $7EB258665FC25D69, $EF2F773FFBD97A61, $AAFB550FFACFD8FA, $95BA2A53F983CF38,
    $DD945A747BF26183, $94F971119AEEF9E4, $7A37CD5601AAB85D, $AC62E055C10AB33A,
    $577B986B314D6009, $ED5A7E85FDA0B80B, $14588F13BE847307, $596EB2D8AE258FC8,
    $6FCA5F8ED9AEF3BB, $25DE7BB9480D5854, $AF561AA79A10AE6A, $1B2BA1518094DA04,
    $90FB44D2F05D0842, $353A1607AC744A53, $42889B8997915CE8, $69956135FEBADA11,
    $43FAB9837E699095, $94F967E45E03F4BB, $1D1BE0EEBAC278F5, $6462D92A69731732,
    $7D7B8F7503CFDCFE, $5CDA735244C3D43E, $3A0888136AFA64A7, $088AAA1845B8FDD0,
    $8AAD549E57273D45, $36AC54E2F678864B, $84576A1BB416A7DD, $656D44A2A11C51D5,
    $9F644AE5A4B1B325, $873D5D9F0DDE1FEE, $A90CB506D155A7EA, $09A7F12442D588F2,
    $0C11ED6D538AEB2F, $8F1668C8A86DA5FA, $F96E017D694487BC, $37C981DCC395A9AC,
    $85BBE253F47B1417, $93956D7478CCEC8E, $387AC8D1970027B2, $06997B05FCC0319E,
    $441FECE3BDF81F03, $D527E81CAD7626C3, $8A71E223D8D3B074, $F6872D5667844E49,
    $B428F8AC016561DB, $E13336D701BEBA52, $ECC0024661173473, $27F002D7F95D0190,
    $31EC038DF7B441F4, $7E67047175A15271, $0F0062C6E984D386, $52C07B78A3E60868,
    $A7709A56CCDF8A82, $88A66076400BB691, $6ACFF893D00EA435, $0583F6B8C4124D43,
    $C3727A337A8B704A, $744F18C0592E4C5C, $1162DEF06F79DF73, $8ADDCB5645AC2BA8,
    $6D953E2BD7173692, $C8FA8DB6CCDD0437, $1D9C9892400A22A2, $2503BEB6D00CAB4B,
    $2E44AE64840FD61D, $5CEAECFED289E5D2, $7425A83E872C5F47, $D12F124E28F77719,
    $82BD6B70D99AAA6F, $636CC64D1001550B, $3C47F7E05401AA4E, $65ACFAEC34810A71,
    $7F1839A741A14D0D, $1EDE48111209A050, $934AED0AAB460432, $F81DA84D5617853F,
    $36251260AB9D668E, $C1D72B7C6B426019, $B24CF65B8612F81F, $DEE033F26797B627,
    $169840EF017DA3B1, $8E1F289560EE864E, $F1A6F2BAB92A27E2, $AE10AF696774B1DB,
    $ACCA6DA1E0A8EF29, $17FD090A58D32AF3, $DDFC4B4CEF07F5B0, $4ABDAF101564F98E,
    $9D6D1AD41ABE37F1, $84C86189216DC5ED, $32FD3CF5B4E49BB4, $3FBC8C33221DC2A1,
    $0FABAF3FEAA5334A, $29CB4D87F2A7400E, $743E20E9EF511012, $914DA9246B255416,
    $1AD089B6C2F7548E, $A184AC2473B529B1, $C9E5D72D90A2741E, $7E2FA67C7A658892,
    $DDBB901B98FEEAB7, $552A74227F3EA565, $D53A88958F87275F, $8A892ABAF368F137,
    $2D2B7569B0432D85, $9C3B29620E29FC73, $8349F3BA91B47B8F, $241C70A936219A73,
    $ED238CD383AA0110, $F4363804324A40AA, $B143C6053EDCD0D5, $DD94B7868E94050A,
    $CA7CF2B4191C8326, $FD1C2F611F63A3F0, $BC633B39673C8CEC, $D5BE0503E085D813,
    $4B2D8644D8A74E18, $DDF8E7D60ED1219E, $CABB90E5C942B503, $3D6A751F3B936243,
    $0CC512670A783AD4, $27FB2B80668B24C5, $B1F9F660802DEDF6, $5E7873F8A0396973,
    $DB0B487B6423E1E8, $91CE1A9A3D2CDA62, $7641A140CC7810FB, $A9E904C87FCB0A9D,
    $546345FA9FBDCD44, $A97C177947AD4095, $49ED8EABCCCC485D, $5C68F256BFFF5A74,
    $73832EEC6FFF3111, $C831FD53C5FF7EAB, $BA3E7CA8B77F5E55, $28CE1BD2E55F35EB,
    $7980D163CF5B81B3, $D7E105BCC332621F, $8DD9472BF3FEFAA7, $B14F98F6F0FEB951,
    $6ED1BF9A569F33D3, $0A862F80EC4700C8, $CD27BB612758C0FA, $8038D51CB897789C,
    $E0470A63E6BD56C3, $1858CCFCE06CAC74, $0F37801E0C43EBC8, $D30560258F54E6BA,
    $47C6B82EF32A2069, $4CDC331D57FA5441, $E0133FE4ADF8E952, $58180FDDD97723A6,
    $570F09EAA7EA7648, $2CD2CC6551E513DA, $F8077F7EA65E58D1, $FB04AFAF27FAF782,
    $79C5DB9AF1F9B563, $18375281AE7822BC, $8F2293910D0B15B5, $B2EB3875504DDB22,
    $5FA60692A46151EB, $DBC7C41BA6BCD333, $12B9B522906C0800, $D768226B34870A00,
    $E6A1158300D46640, $60495AE3C1097FD0, $385BB19CB14BDFC4, $46729E03DD9ED7B5,
    $6C07A2C26A8346D1, $C7098B7305241885, $B8CBEE4FC66D1EA7, $737F74F1DC043328,
    $505F522E53053FF2, $647726B9E7C68FEF, $5ECA783430DC19F5, $B67D16413D132072,
    $E41C5BD18C57E88F, $8E91B962F7B6F159, $723627BBB5A4ADB0, $CEC3B1AAA30DD91C,
    $213A4F0AA5E8A7B1, $A988E2CD4F62D19D, $93EB1B80A33B8605, $BC72F130660533C3,
    $EB8FAD7C7F8680B4, $A67398DB9F6820E1, $88083F8943A1148C, $6A0A4F6B948959B0,
    $848CE34679ABB01C, $F2D80E0C0C0B4E11, $6F8E118F0F0E2195, $4B7195F2D2D1A9FB);


{ Leading zeros of a NONZERO UInt64. Called once per parse, so a shift loop is
  cheaper than reaching for an intrinsic that not every target has. }
function EL_Clz(x: UInt64): Integer;
var n: Integer;
begin
  n := 0;
  while (x shr 63) = 0 do
  begin
    x := x shl 1;
    n := n + 1;
  end;
  EL_Clz := n;
end;

{ floor(x / 65536) — FLOOR, not truncation, because x is negative for every
  negative exponent and `div` rounds toward zero. Go writes this as an
  arithmetic `>> 16`; spelled out here so the negative half cannot silently
  become truncation and shift the estimate by one. }
function EL_Floor64K(x: Int64): Int64;
begin
  if x >= 0 then EL_Floor64K := x div 65536
  else EL_Floor64K := -(((-x) + 65535) div 65536);
end;

{ mant * 10^q as a correctly rounded Double, or False if it cannot be decided.
  `mant` is the EXACT decimal significand (no truncation) and q the power of
  ten it is multiplied by. False means "ask ExDecNearest", never "wrong". }
function EiselLemire(mant: UInt64; q: Integer; var value: Double): Boolean;
var
  clz, idx, msb: Integer;
  retExp2: Int64;
  xHi, xLo, yHi, yLo, mHi, mLo, retMant: UInt64;
  bits: Int64;
begin
  EiselLemire := False;
  if mant = 0 then Exit;                        { the caller handles zero }
  if (q < EL_MIN_Q) or (q > EL_MAX_Q) then Exit;

  clz := EL_Clz(mant);
  mant := mant shl clz;
  { 217706/65536 is log2(10) to well within the slack this estimate has; the
    +64 is the table's normalisation and +1023 the IEEE bias. }
  retExp2 := EL_Floor64K(217706 * Int64(q)) + 64 + 1023 - clz;

  idx := q - EL_MIN_Q;
  xHi := MulHiU64(mant, P10Hi[idx]);
  { the low half of a 128-bit product IS the wrapping 64-bit product }
  xLo := mant * P10Hi[idx];

  { The truncated table entry may not settle the rounding on its own. When the
    product sits within 2^-9 of a boundary, bring in the table's LOW word and
    redo the comparison at 128 bits of the multiplier. If it is STILL
    undecidable, decline. `a + b < b` is the unsigned overflow test. }
  if ((xHi and $1FF) = $1FF) and ((xLo + mant) < mant) then
  begin
    yHi := MulHiU64(mant, P10Lo[idx]);
    yLo := mant * P10Lo[idx];
    mHi := xHi;
    mLo := xLo + yHi;
    if mLo < xLo then mHi := mHi + 1;
    if ((mHi and $1FF) = $1FF) and ((mLo + 1) = 0) and ((yLo + mant) < mant) then
      Exit;
    xHi := mHi;
    xLo := mLo;
  end;

  msb := Integer(xHi shr 63);
  retMant := xHi shr (msb + 9);
  retExp2 := retExp2 - Int64(1 - msb);

  { An exact halfway product would round to even, and a truncated product
    cannot prove it is exactly halfway — so this shape is declined too. }
  if (xLo = 0) and ((xHi and $1FF) = 0) and ((retMant and 3) = 1) then Exit;

  retMant := retMant + (retMant and 1);
  retMant := retMant shr 1;
  if (retMant shr 53) > 0 then
  begin
    retMant := retMant shr 1;
    retExp2 := retExp2 + 1;
  end;

  { retExp2 < 1 is subnormal-or-zero, > 2046 is infinity. Both DECLINE — see
    the header. This is the check that keeps the algorithm honest. }
  if (retExp2 < 1) or (retExp2 > 2046) then Exit;

  bits := (retExp2 shl 52) or Int64(retMant and $000FFFFFFFFFFFFF);
  value := ExDecBitsToDouble(bits);
  EiselLemire := True;
end;

function ParseFloatCore(const s: AnsiString; var value: Double): Boolean;
const
  { every digit past this is beyond any midpoint's ~1080, so it can only break
    a tie — which the sticky digit below does, without unbounded strings }
  EXDEC_INMAX = 1200;
var i, digit, e, k: Integer; c: Char; neg, eneg: Boolean;
    w, p: Double; in_frac, started, estarted, sticky: Boolean;
    ds, t: AnsiString; fracCount, nd, expo, lead: Integer; sig: Int64;
    dsLen, dsCap: Integer;
    msig: UInt64;

  { Append one digit to ds without reallocating per digit. The old code was
    `ds := ds + c` inside the scan loop, which reallocates and recopies the
    whole accumulated prefix on EVERY digit -- the same quadratic-append shape
    already fixed once in ExDecOfMant, sitting in a second place. Capacity
    doubles, so an ordinary number costs one allocation and a 1200-digit one
    costs six. }
  procedure DsPush(ch: Char);
  begin
    if dsLen = dsCap then
    begin
      { 32 covers all ordinary input in one allocation; a nested
        procedure cannot see the enclosing const block, hence the literal }
      if dsCap = 0 then dsCap := 32 else dsCap := dsCap * 2;
      SetLength(ds, dsCap);
    end;
    dsLen := dsLen + 1;
    ds[dsLen] := ch;
  end;

begin
  Result := False;
  value := 0.0;
  dsLen := 0; dsCap := 0;
  { FPC skips whitespace at BOTH ends before parsing, and its notion of
    whitespace is any char <= ' ' — measured, not assumed: #0, #1, #11 and #12
    around a float are all accepted there, which is exactly Trim's rule. This
    skipped leading SPACES only, so StrToFloat('1.5 ') and StrToFloat(#9'1.5')
    were rejected and returned the default.
    ([[bug-b-strtofloat-returns-0-for-malformed-input-and-rejects-trailing-space]]) }
  { Trim, spelled out for the same reason as the limb above }
  i := 1; k := Length(s);
  while (i <= k) and (s[i] <= ' ') do i := i + 1;
  while (k >= i) and (s[k] <= ' ') do k := k - 1;
  t := Copy(s, i, k - i + 1);
  i := 1; neg := False; w := 0.0; in_frac := False; started := False;
  ds := ''; fracCount := 0; sticky := False;
  if (i <= Length(t)) and ((t[i] = '-') or (t[i] = '+')) then
  begin
    if t[i] = '-' then neg := True;
    i := i + 1;
  end;
  e := 0; eneg := False; estarted := True;
  while i <= Length(t) do
  begin
    c := t[i];
    if (c >= '0') and (c <= '9') then
    begin
      digit := Ord(c) - Ord('0');
      if in_frac then fracCount := fracCount + 1;
      { keep the digits themselves; the value is reconstructed exactly below }
      if dsLen < EXDEC_INMAX then
      begin
        if (dsLen > 0) or (digit <> 0) then DsPush(c);     { drop leading zeros }
      end
      else if digit <> 0 then
        sticky := True;
      started := True;
      i := i + 1;
    end
    else if (c = '.') and (not in_frac) then
    begin
      in_frac := True;
      i := i + 1;
    end
    else if ((c = 'e') or (c = 'E')) and started then
    begin
      { exponent: [+|-]digits to the END of the string ('1e0', '1.2E+003') }
      i := i + 1;
      if (i <= Length(t)) and ((t[i] = '-') or (t[i] = '+')) then
      begin
        if t[i] = '-' then eneg := True;
        i := i + 1;
      end;
      estarted := False;
      while i <= Length(t) do
      begin
        c := t[i];
        if (c < '0') or (c > '9') then Exit;
        e := e * 10 + (Ord(c) - Ord('0'));
        estarted := True;
        i := i + 1;
      end;
      if not estarted then Exit;
    end
    else
      Exit;
  end;
  if not (started and estarted) then Exit;

  { a dropped nonzero digit past the cap makes the value strictly greater than
    the kept prefix — exactly what a sticky bit is for, and enough to settle any
    tie, since a midpoint has far fewer significant digits than the cap }
  if sticky then DsPush('1');
  SetLength(ds, dsLen);                 { trim the buffer to what was written }

  if dsLen = 0 then                     { all digits were zero }
  begin
    w := 0.0;
    if neg then w := -w;                { preserves -0.0 }
    value := w;
    Result := True;
    Exit;
  end;

  if eneg then e := -e;
  { value = int(ds) * 10^expo }
  expo := e - fracCount;
  { trailing zeros move to the exponent — cheaper, and widens the fast path }
  nd := Length(ds);
  while (nd > 1) and (ds[nd] = '0') do begin nd := nd - 1; expo := expo + 1; end;
  ds := Copy(ds, 1, nd);

  { Fast path (Clinger): with the significand under 2^53 and |expo| <= 22, both
    the significand and 10^|expo| are exactly representable, so a single
    multiply or divide is a single rounding and is therefore already the
    correctly rounded result. 10^k is built by repeated multiplication, which
    is exact up to 10^22 — deliberately not a table of literals, since parsing
    those literals is the very thing being fixed here. Covers the overwhelming
    majority of real input (JSON numbers and the like). }
  if (nd <= 15) and (expo >= -22) and (expo <= 22) then
  begin
    sig := 0;
    for k := 1 to nd do sig := sig * 10 + Int64(Ord(ds[k]) - Ord('0'));
    w := sig * 1.0;
    p := 1.0;
    if expo >= 0 then
    begin
      for k := 1 to expo do p := p * 10.0;
      w := w * p;
    end
    else
    begin
      for k := 1 to -expo do p := p * 10.0;
      w := w / p;
    end;
    if neg then w := -w;
    value := w;
    Result := True;
    Exit;
  end;

  { Eisel-Lemire: one 128-bit multiply for everything Clinger could not reach.
    19 digits is the cap because that is what a u64 significand holds exactly
    (10^19 - 1 < 2^64); past it the significand would have to be truncated, and
    a truncated significand is precisely what this algorithm may not be given.
    A decline falls through to the exact search below and is still right. }
  if nd <= 19 then
  begin
    msig := 0;
    for k := 1 to nd do msig := msig * 10 + UInt64(Ord(ds[k]) - Ord('0'));
    if EiselLemire(msig, expo, w) then
    begin
      if neg then w := -w;
      value := w;
      Result := True;
      Exit;
    end;
  end;

  { Exact reconstruction. decExp is the power of ten the first digit stands for.

    Two implementations of the same correctly-rounded answer. ExBinNearest
    compares in binary big integers and is what Eisel-Lemire's declines land on
    — chiefly the subnormals, which Lemire refuses by construction. It declines
    in turn for anything whose operands would not fit its limb array, and
    ExDecNearest — which compares by expanding each candidate to its exact
    decimal, and has no size limit — answers those. Each layer declines rather
    than guesses, so the composition cannot produce a wrong value, only a slower
    right one. }
  lead := nd - 1 + expo;
  if not ExBinNearest(ds, lead, nd, expo, w) then
    w := ExDecNearest(ds, lead, nd, expo);
  if neg then w := -w;
  value := w;
  Result := True;
end;

end.
