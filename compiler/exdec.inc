{ ---- exact decimal <-> double, a COPY of lib/rtl/sysutils.pas -------------

  Byte-for-byte the exact-decimal core of lib/rtl/sysutils.pas, with ONE edit:
  StrToFloatDef is spelled ExDecStrToDouble, because the FPC-seeded bootstrap
  has real SysUtils in scope and would collide on that name. Everything else is
  identical on purpose — this file should diff cleanly against its origin.

  Why a copy and not a uses clause: the compiler must not drag a user RTL unit
  into its own build (see the FPC-only uses clause in compiler.pas — under
  self-host `uses sysutils` resolves to the real lib/rtl/sysutils.pas). The same
  constraint produced the same answer for compiler/builtin/pylib.pas
  (decide-nilpy-where-the-exact-decimal-float-core-lives): copy proven code,
  never reimplement, because a second exact-decimal implementation is this
  repo's recurring failure mode in its most numeric form.

  What it replaced: StrToDoubleBits' own rational N/D scaling, which used
  round-to-odd halvings to stay inside Int64. Round-to-odd composes safely for
  ONE final rounding of an exactly-known value; here every halving introduced
  fresh error, and over the ~300 steps a 1e-292-scale literal needs, ~7 guard
  bits were not enough. 23 of 490 sampled literals came out 1 ULP off
  (bug-a-float-literal-lexer-is-not-correctly-rounded).

  CHANGE ONE, CHANGE ALL THREE: this file, lib/rtl/sysutils.pas, and the copy in
  compiler/builtin/pylib.pas. test/lib_floattostr.pas and
  test/test_nilpy_float_repr.npy pin the other two; test/lex_float_literal.pas
  pins this one, by asserting that a literal equals the parser reading its own
  text. }


{ ---- exact decimal expansion of a Double ---------------------------------

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

{ The ONE substitution the copy needs beyond the ExDecStrToDouble rename:
  IntToStr is not in the compiler's own RTL (pylib's copy substitutes its own
  StrInt for the same reason). Local, so the rest of the file stays identical
  to lib/rtl/sysutils.pas. Values here are single limbs, always non-negative. }
function ExDecIntToStr(v: Int64): AnsiString;
var d: array[0..23] of Char; c: Integer; m: Int64; r: AnsiString;
begin
  if v <= 0 then begin Result := '0'; Exit; end;
  c := 0; m := v;
  while m > 0 do begin d[c] := Chr(Ord('0') + Integer(m mod 10)); Inc(c); m := m div 10; end;
  r := '';
  while c > 0 do begin Dec(c); r := r + d[c]; end;
  Result := r;
end;

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
  n, i, k, fracDigits: Integer;
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
  { top limb unpadded (that is what drops the leading zeros), the rest padded
    to the full nine so limb boundaries do not swallow interior zeros }
  ds := ExDecIntToStr(buf[n - 1]);
  for i := n - 2 downto 0 do
  begin
    lp := ExDecIntToStr(buf[i]);
    while Length(lp) < 9 do lp := '0' + lp;
    ds := ds + lp;
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

{ Round an exact digit string to sig digits, half-to-EVEN on the exact
  remainder (glibc's %.*g rule — and the remainder here really is exact, so
  the tie case is a genuine tie rather than an artifact of scaling). A carry
  out of the leading digit (999 -> 100) moves the decimal exponent. }
procedure ExDecRound(var ds: AnsiString; var decExp: Integer; sig: Integer);
var i, c: Integer; up, rest: Boolean;
begin
  if Length(ds) <= sig then Exit;
  up := False;
  if ds[sig + 1] > '5' then up := True
  else if ds[sig + 1] = '5' then
  begin
    rest := False;
    for i := sig + 2 to Length(ds) do
      if ds[i] <> '0' then begin rest := True; break; end;
    if rest then up := True
    else up := ((Ord(ds[sig]) - Ord('0')) mod 2) = 1;
  end;
  ds := Copy(ds, 1, sig);
  if up then
  begin
    i := sig;
    while i >= 1 do
    begin
      c := Ord(ds[i]) - Ord('0') + 1;
      if c < 10 then begin ds[i] := Chr(Ord('0') + c); break; end;
      ds[i] := '0';
      i := i - 1;
    end;
    if i = 0 then
    begin
      ds := '1' + Copy(ds, 1, sig - 1);
      decExp := decExp + 1;
    end;
  end;
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

function ExDecStrToDouble(const s: AnsiString; def: Double): Double;
const
  { every digit past this is beyond any midpoint's ~1080, so it can only break
    a tie — which the sticky digit below does, without unbounded strings }
  EXDEC_INMAX = 1200;
var i, digit, e, k: Integer; c: Char; neg, eneg: Boolean;
    w, p: Double; in_frac, started, estarted, sticky: Boolean;
    ds: AnsiString; fracCount, nd, expo, lead: Integer; sig: Int64;
begin
  Result := def;
  i := 1; neg := False; w := 0.0; in_frac := False; started := False;
  ds := ''; fracCount := 0; sticky := False;
  while (i <= Length(s)) and (s[i] = ' ') do i := i + 1;
  if (i <= Length(s)) and ((s[i] = '-') or (s[i] = '+')) then
  begin
    if s[i] = '-' then neg := True;
    i := i + 1;
  end;
  e := 0; eneg := False; estarted := True;
  while i <= Length(s) do
  begin
    c := s[i];
    if (c >= '0') and (c <= '9') then
    begin
      digit := Ord(c) - Ord('0');
      if in_frac then fracCount := fracCount + 1;
      { keep the digits themselves; the value is reconstructed exactly below }
      if Length(ds) < EXDEC_INMAX then
      begin
        if (ds <> '') or (digit <> 0) then ds := ds + c;   { drop leading zeros }
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
      if (i <= Length(s)) and ((s[i] = '-') or (s[i] = '+')) then
      begin
        if s[i] = '-' then eneg := True;
        i := i + 1;
      end;
      estarted := False;
      while i <= Length(s) do
      begin
        c := s[i];
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
  if sticky then ds := ds + '1';

  if ds = '' then                       { all digits were zero }
  begin
    w := 0.0;
    if neg then w := -w;                { preserves -0.0 }
    Result := w;
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
    Result := w;
    Exit;
  end;

  { Slow path: exact reconstruction. decExp is the power of ten the first digit
    stands for. }
  lead := nd - 1 + expo;
  w := ExDecNearest(ds, lead, nd, expo);
  if neg then w := -w;
  Result := w;
end;
