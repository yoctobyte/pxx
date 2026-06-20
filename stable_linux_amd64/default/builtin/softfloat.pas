unit softfloat;

{ Software IEEE-754 floating-point kernels for targets without (full) hardware
  floating point (riscv32 = no FPU; xtensa = single-only HW, soft double).

  Everything here operates on the *integer bit pattern* of the float, never on a
  Pascal float type:
    - single (binary32): a LongWord holding the 32-bit IEEE encoding
    - double (binary64): an Int64 holding the 64-bit IEEE encoding   (added next)
  The IR codegen on no-FPU targets will hold the float bits in core registers and
  emit calls to these helpers (mirroring how arm32 spills d0->r0:r1). Keeping the
  ABI integer-only is what lets the lib compile + run with no float instructions.

  Properties:
    - allocation-free, syscall-free (runs bare-metal on ESP);
    - no `div`/`mod` operator (xtensa LX6 has no HW divide) — division is an
      explicit restoring shift-subtract loop, like __pxx_udivsi3 in builtinheap;
    - round-to-nearest-even; inf / NaN / signed-zero handled;
    - subnormals flush to zero (documented follow-up — mul/div *rounding* of
      normal results is still correct, which is what decimal output depends on).

  Validate STANDALONE on x86-64: a test program calls these directly and diffs
  the result bit patterns against native arithmetic over a value grid. }

interface

{ ---- soft single (binary32), operands/results are the 32-bit encodings ---- }
function __pxx_sadd(a: LongWord; b: LongWord): LongWord;
function __pxx_ssub(a: LongWord; b: LongWord): LongWord;
function __pxx_smul(a: LongWord; b: LongWord): LongWord;
function __pxx_sdiv(a: LongWord; b: LongWord): LongWord;
{ ordered, NaN-aware compare: -1 a<b, 0 a=b, 1 a>b, 2 unordered (a or b NaN). }
function __pxx_scmp(a: LongWord; b: LongWord): Integer;
{ conversions }
function __pxx_i2s(v: Integer): LongWord;     { signed int -> single }
function __pxx_s2i(a: LongWord): Integer;      { single -> signed int, trunc to 0 }

{ ---- soft double (binary64), operands/results are the 64-bit encodings ---- }
function __pxx_dadd(a: Int64; b: Int64): Int64;
function __pxx_dsub(a: Int64; b: Int64): Int64;
function __pxx_dmul(a: Int64; b: Int64): Int64;
function __pxx_ddiv(a: Int64; b: Int64): Int64;
function __pxx_dcmp(a: Int64; b: Int64): Integer;
{ conversions }
function __pxx_i2d(v: Integer): Int64;         { signed int -> double }
function __pxx_d2i(a: Int64): Integer;          { double -> signed int, trunc to 0 }
function __pxx_s2d(a: LongWord): Int64;         { single -> double (exact repack) }
function __pxx_d2s(a: Int64): LongWord;         { double -> single (round-near-even) }

implementation

const
  S_SIGN = $80000000;   { single sign bit }
  S_INF  = $7F800000;   { single +Inf encoding }
  S_QNAN = $7FC00000;   { single canonical quiet NaN }

{ Shift m right by n bits, OR-ing 1 into bit 0 if any 1 bit was shifted out
  (sticky). m is always non-negative here, so shr is a logical shift. }
function sShiftRightSticky(m: Int64; n: Integer): Int64;
var lost, mask: Int64;
begin
  if n <= 0 then begin Result := m; Exit; end;
  if n >= 63 then
  begin
    if m <> 0 then Result := 1 else Result := 0;
    Exit;
  end;
  mask := (Int64(1) shl n) - 1;
  lost := m and mask;
  Result := m shr n;
  if lost <> 0 then Result := Result or 1;
end;

{ Normalize + round-to-nearest-even + repack a single result.
  Caller supplies: sign (0/1), exp (biased exponent of the 24-bit significand
  that sits at bits 26..3 of m), and m whose low 3 bits are guard/round/sticky
  (leading significand bit nominally at position 26). The normalize loops make it
  robust to addition carry (m >= 2^27) and cancellation (m < 2^26). }
function sRoundPack(sign: Integer; exp: Integer; m: Int64): LongWord;
var roundBit, sticky, lsb: Int64;
begin
  if m = 0 then begin Result := LongWord(sign) shl 31; Exit; end;  { signed zero }
  while m >= (Int64(1) shl 27) do begin m := sShiftRightSticky(m, 1); exp := exp + 1; end;
  while m < (Int64(1) shl 26) do begin m := m shl 1; exp := exp - 1; end;
  roundBit := (m shr 2) and 1;
  sticky := m and 3;
  m := m shr 3;                 { drop the 3 guard bits -> 24-bit significand }
  lsb := m and 1;
  if (roundBit = 1) and ((sticky <> 0) or (lsb = 1)) then m := m + 1;
  if m >= (Int64(1) shl 24) then begin m := m shr 1; exp := exp + 1; end;  { round carry }
  if exp >= 255 then begin Result := (LongWord(sign) shl 31) or S_INF; Exit; end;  { overflow }
  if exp <= 0 then begin Result := LongWord(sign) shl 31; Exit; end;  { underflow -> signed 0 }
  Result := (LongWord(sign) shl 31) or (LongWord(exp) shl 23) or (LongWord(m) and $7FFFFF);
end;

function sIsNaN(a: LongWord): Boolean;
begin
  Result := ((a and $7F800000) = $7F800000) and ((a and $7FFFFF) <> 0);
end;

function sIsInf(a: LongWord): Boolean;
begin
  Result := ((a and $7F800000) = $7F800000) and ((a and $7FFFFF) = 0);
end;

function __pxx_sadd(a: LongWord; b: LongWord): LongWord;
var
  sa, sb, ea, eb, resSign, resExp: Integer;
  ma, mb, m: Int64;
begin
  if sIsNaN(a) or sIsNaN(b) then begin Result := S_QNAN; Exit; end;
  if sIsInf(a) then
  begin
    { inf + (-inf) = NaN; otherwise the infinity wins }
    if sIsInf(b) and ((a and S_SIGN) <> (b and S_SIGN)) then Result := S_QNAN
    else Result := a;
    Exit;
  end;
  if sIsInf(b) then begin Result := b; Exit; end;

  sa := (a shr 31) and 1;
  sb := (b shr 31) and 1;
  ea := (a shr 23) and $FF;
  eb := (b shr 23) and $FF;
  if ea = 0 then begin ma := 0; ea := 1; end else ma := (Int64(1) shl 23) or (a and $7FFFFF);
  if eb = 0 then begin mb := 0; eb := 1; end else mb := (Int64(1) shl 23) or (b and $7FFFFF);

  ma := ma shl 3;               { make room for guard/round/sticky }
  mb := mb shl 3;
  if ea >= eb then begin resExp := ea; mb := sShiftRightSticky(mb, ea - eb); end
  else begin resExp := eb; ma := sShiftRightSticky(ma, eb - ea); end;

  if sa = sb then begin m := ma + mb; resSign := sa; end
  else
  begin
    if ma >= mb then begin m := ma - mb; resSign := sa; end
    else begin m := mb - ma; resSign := sb; end;
  end;
  if m = 0 then
  begin
    { same-sign sum of zeros keeps the sign; opposite-sign cancellation -> +0
      (round-to-nearest) }
    if sa = sb then Result := LongWord(resSign) shl 31 else Result := 0;
    Exit;
  end;
  Result := sRoundPack(resSign, resExp, m);
end;

function __pxx_ssub(a: LongWord; b: LongWord): LongWord;
begin
  Result := __pxx_sadd(a, b xor S_SIGN);
end;

function __pxx_smul(a: LongWord; b: LongWord): LongWord;
var
  ea, eb, resSign, resExp, shift: Integer;
  ma, mb, prod, m: Int64;
begin
  resSign := ((a xor b) shr 31) and 1;
  if sIsNaN(a) or sIsNaN(b) then begin Result := S_QNAN; Exit; end;
  if sIsInf(a) then
  begin
    if (b and $7FFFFFFF) = 0 then Result := S_QNAN            { inf * 0 }
    else Result := (LongWord(resSign) shl 31) or S_INF;
    Exit;
  end;
  if sIsInf(b) then
  begin
    if (a and $7FFFFFFF) = 0 then Result := S_QNAN
    else Result := (LongWord(resSign) shl 31) or S_INF;
    Exit;
  end;
  ea := (a shr 23) and $FF;
  eb := (b shr 23) and $FF;
  if (ea = 0) or (eb = 0) then begin Result := LongWord(resSign) shl 31; Exit; end;  { 0/subn -> signed 0 }
  ma := (Int64(1) shl 23) or (a and $7FFFFF);
  mb := (Int64(1) shl 23) or (b and $7FFFFF);
  prod := ma * mb;              { in [2^46, 2^48) }
  resExp := ea + eb - 127;
  if prod >= (Int64(1) shl 47) then begin resExp := resExp + 1; shift := 47 - 26; end
  else shift := 46 - 26;
  m := sShiftRightSticky(prod, shift);
  Result := sRoundPack(resSign, resExp, m);
end;

function __pxx_sdiv(a: LongWord; b: LongWord): LongWord;
var
  resSign, ea, eb, resExp, i: Integer;
  ma, mb, q, rem: Int64;
begin
  resSign := ((a xor b) shr 31) and 1;
  if sIsNaN(a) or sIsNaN(b) then begin Result := S_QNAN; Exit; end;
  if sIsInf(a) then
  begin
    if sIsInf(b) then Result := S_QNAN                        { inf / inf }
    else Result := (LongWord(resSign) shl 31) or S_INF;
    Exit;
  end;
  if sIsInf(b) then begin Result := LongWord(resSign) shl 31; Exit; end;  { finite/inf -> 0 }
  ea := (a shr 23) and $FF;
  eb := (b shr 23) and $FF;
  if eb = 0 then               { divisor is +-0 (subnormal flushed) }
  begin
    if ea = 0 then Result := S_QNAN                           { 0 / 0 }
    else Result := (LongWord(resSign) shl 31) or S_INF;       { x / 0 -> inf }
    Exit;
  end;
  if ea = 0 then begin Result := LongWord(resSign) shl 31; Exit; end;     { 0 / x -> 0 }
  ma := (Int64(1) shl 23) or (a and $7FFFFF);
  mb := (Int64(1) shl 23) or (b and $7FFFFF);
  resExp := ea - eb + 126;
  { Restoring shift-subtract needs the partial remainder < divisor each step, so
    the dividend must start below the divisor. Both significands have their
    leading bit at position 23 (ratio in [0.5, 2)); when ma >= mb (ratio >= 1)
    double the divisor and bump the exponent to bring the ratio back into
    [0.5, 1). Then every quotient digit is 0/1 and a single subtract suffices. }
  if ma >= mb then begin mb := mb shl 1; resExp := resExp + 1; end;
  { 27 quotient bits (24 significand + guard/round/sticky); no div operator. }
  rem := ma;
  q := 0;
  i := 0;
  while i < 27 do
  begin
    rem := rem shl 1;
    q := q shl 1;
    if rem >= mb then begin rem := rem - mb; q := q or 1; end;
    i := i + 1;
  end;
  if rem <> 0 then q := q or 1;            { remaining remainder -> sticky }
  Result := sRoundPack(resSign, resExp, q);
end;

function __pxx_scmp(a: LongWord; b: LongWord): Integer;
var ua, ub: LongWord; sa, sb: Integer;
begin
  if sIsNaN(a) or sIsNaN(b) then begin Result := 2; Exit; end;
  ua := a and $7FFFFFFF;
  ub := b and $7FFFFFFF;
  if (ua = 0) and (ub = 0) then begin Result := 0; Exit; end;   { +0 = -0 }
  sa := (a shr 31) and 1;
  sb := (b shr 31) and 1;
  if sa <> sb then begin if sa = 1 then Result := -1 else Result := 1; Exit; end;
  if ua = ub then begin Result := 0; Exit; end;
  if ua > ub then begin if sa = 1 then Result := -1 else Result := 1; end
  else begin if sa = 1 then Result := 1 else Result := -1; end;
end;

function __pxx_i2s(v: Integer): LongWord;
var sign: Integer; uv: Int64;
begin
  if v = 0 then begin Result := 0; Exit; end;
  if v < 0 then begin sign := 1; uv := -Int64(v); end
  else begin sign := 0; uv := Int64(v); end;
  { Feed the magnitude as the significand with exp chosen so that, after
    sRoundPack normalizes the leading bit to position 26, the value reads back
    as the integer (derivation: exp_final = p + 127 where p = leading bit of uv;
    sRoundPack shifts exp by p-26, so the seed exp is 153). }
  Result := sRoundPack(sign, 153, uv);
end;

function __pxx_s2i(a: LongWord): Integer;
var sign, exp, shift: Integer; m, r: Int64;
begin
  exp := (a shr 23) and $FF;
  if exp = 0 then begin Result := 0; Exit; end;          { |x| < 1 (incl subnormal) }
  sign := (a shr 31) and 1;
  if exp = 255 then                                       { inf / NaN -> saturate }
  begin
    if (a and $7FFFFF) <> 0 then begin Result := 0; Exit; end;  { NaN -> 0 }
    if sign = 1 then Result := Integer($80000000) else Result := $7FFFFFFF;
    Exit;
  end;
  m := (Int64(1) shl 23) or (a and $7FFFFF);              { value = m * 2^(exp-150) }
  shift := exp - 150;
  if shift >= 8 then                                      { |x| >= 2^31 -> saturate }
  begin
    if sign = 1 then Result := Integer($80000000) else Result := $7FFFFFFF;
    Exit;
  end;
  if shift > 0 then r := m shl shift
  else r := m shr (-shift);                               { truncate toward zero }
  if sign = 1 then r := -r;
  Result := Integer(r);
end;

{ =================== soft double (binary64) =================== }
{ Same shape as the single kernels but with 53-bit significands. Everything is
  kept in non-negative Int64 (significands < 2^53, aligned/summed values < 2^58),
  so signed Int64 behaves as unsigned; only the final packed result and the input
  encodings set bit 63, and field extraction masks that off. The 53x53 product in
  __pxx_dmul is the one place that needs >64 bits — it is assembled from 26-bit
  limbs whose partial products all stay below 2^54, then split into a (phi,plo)
  128-bit value (each half non-negative). }

{ Int64 masks as functions — a const initializer can't fold the Int64() cast. }
function D_MANT: Int64;                 { 52-bit mantissa mask }
begin
  Result := (Int64(1) shl 52) - 1;
end;

function D_EXPF: Int64;                  { exponent field all-ones (Inf encoding) }
begin
  Result := Int64($7FF) shl 52;
end;

function dQNAN: Int64;
begin
  Result := D_EXPF or (Int64(1) shl 51);
end;

function dIsNaN(a: Int64): Boolean;
begin
  Result := (((a shr 52) and $7FF) = $7FF) and ((a and D_MANT) <> 0);
end;

function dIsInf(a: Int64): Boolean;
begin
  Result := (((a shr 52) and $7FF) = $7FF) and ((a and D_MANT) = 0);
end;

{ Normalize + round-to-nearest-even + repack a double result. m holds the 53-bit
  significand at bits 55..3 with 3 guard bits below; exp is its biased exponent. }
function dRoundPack(sign: Integer; exp: Integer; m: Int64): Int64;
var roundBit, sticky, lsb: Int64;
begin
  if m = 0 then begin Result := Int64(sign) shl 63; Exit; end;
  while m >= (Int64(1) shl 56) do begin m := sShiftRightSticky(m, 1); exp := exp + 1; end;
  while m < (Int64(1) shl 55) do begin m := m shl 1; exp := exp - 1; end;
  roundBit := (m shr 2) and 1;
  sticky := m and 3;
  m := m shr 3;
  lsb := m and 1;
  if (roundBit = 1) and ((sticky <> 0) or (lsb = 1)) then m := m + 1;
  if m >= (Int64(1) shl 53) then begin m := m shr 1; exp := exp + 1; end;
  if exp >= 2047 then begin Result := (Int64(sign) shl 63) or D_EXPF; Exit; end;
  if exp <= 0 then begin Result := Int64(sign) shl 63; Exit; end;
  Result := (Int64(sign) shl 63) or (Int64(exp) shl 52) or (m and D_MANT);
end;

function __pxx_dadd(a: Int64; b: Int64): Int64;
var
  sa, sb, ea, eb, resSign, resExp: Integer;
  ma, mb, m: Int64;
begin
  if dIsNaN(a) or dIsNaN(b) then begin Result := dQNAN; Exit; end;
  if dIsInf(a) then
  begin
    if dIsInf(b) and (((a shr 63) and 1) <> ((b shr 63) and 1)) then Result := dQNAN
    else Result := a;
    Exit;
  end;
  if dIsInf(b) then begin Result := b; Exit; end;

  sa := (a shr 63) and 1;
  sb := (b shr 63) and 1;
  ea := (a shr 52) and $7FF;
  eb := (b shr 52) and $7FF;
  if ea = 0 then begin ma := 0; ea := 1; end else ma := (Int64(1) shl 52) or (a and D_MANT);
  if eb = 0 then begin mb := 0; eb := 1; end else mb := (Int64(1) shl 52) or (b and D_MANT);

  ma := ma shl 3;
  mb := mb shl 3;
  if ea >= eb then begin resExp := ea; mb := sShiftRightSticky(mb, ea - eb); end
  else begin resExp := eb; ma := sShiftRightSticky(ma, eb - ea); end;

  if sa = sb then begin m := ma + mb; resSign := sa; end
  else
  begin
    if ma >= mb then begin m := ma - mb; resSign := sa; end
    else begin m := mb - ma; resSign := sb; end;
  end;
  if m = 0 then
  begin
    if sa = sb then Result := Int64(resSign) shl 63 else Result := 0;
    Exit;
  end;
  Result := dRoundPack(resSign, resExp, m);
end;

function __pxx_dsub(a: Int64; b: Int64): Int64;
begin
  Result := __pxx_dadd(a, b xor (Int64(1) shl 63));
end;

function __pxx_dmul(a: Int64; b: Int64): Int64;
var
  ea, eb, resSign, resExp: Integer;
  ma, mb, a1, a0, b1, b0, c0, c1, c2, c1L, c1H, lowpart, plo, phi, m, stk: Int64;
  M26: Int64;
begin
  resSign := ((a xor b) shr 63) and 1;
  if dIsNaN(a) or dIsNaN(b) then begin Result := dQNAN; Exit; end;
  if dIsInf(a) then
  begin
    if (b and ((Int64(1) shl 63) - 1)) = 0 then Result := dQNAN     { inf * 0 }
    else Result := (Int64(resSign) shl 63) or D_EXPF;
    Exit;
  end;
  if dIsInf(b) then
  begin
    if (a and ((Int64(1) shl 63) - 1)) = 0 then Result := dQNAN
    else Result := (Int64(resSign) shl 63) or D_EXPF;
    Exit;
  end;
  ea := (a shr 52) and $7FF;
  eb := (b shr 52) and $7FF;
  if (ea = 0) or (eb = 0) then begin Result := Int64(resSign) shl 63; Exit; end;
  ma := (Int64(1) shl 52) or (a and D_MANT);
  mb := (Int64(1) shl 52) or (b and D_MANT);
  M26 := (Int64(1) shl 26) - 1;
  a1 := ma shr 26; a0 := ma and M26;
  b1 := mb shr 26; b0 := mb and M26;
  c0 := a0 * b0;                 { < 2^52 }
  c1 := a1 * b0 + a0 * b1;       { < 2^54 }
  c2 := a1 * b1;                 { < 2^54 }
  c1L := c1 and M26;
  c1H := c1 shr 26;
  { P = c2*2^52 + c1*2^26 + c0 = (c2 + c1H)*2^52 + (c1L*2^26 + c0) }
  lowpart := c1L * (Int64(1) shl 26) + c0;        { < 2^53 }
  plo := lowpart and D_MANT;                       { low 52 bits }
  phi := c2 + c1H + (lowpart shr 52);              { P = phi*2^52 + plo }
  { 56-bit window (P >> 49) + sticky; dRoundPack normalizes leading 55/56 }
  stk := plo and ((Int64(1) shl 49) - 1);
  m := (phi shl 3) or (plo shr 49);
  if stk <> 0 then m := m or 1;
  resExp := ea + eb - 1023;
  Result := dRoundPack(resSign, resExp, m);
end;

function __pxx_ddiv(a: Int64; b: Int64): Int64;
var
  resSign, ea, eb, resExp, i: Integer;
  ma, mb, q, rem: Int64;
begin
  resSign := ((a xor b) shr 63) and 1;
  if dIsNaN(a) or dIsNaN(b) then begin Result := dQNAN; Exit; end;
  if dIsInf(a) then
  begin
    if dIsInf(b) then Result := dQNAN
    else Result := (Int64(resSign) shl 63) or D_EXPF;
    Exit;
  end;
  if dIsInf(b) then begin Result := Int64(resSign) shl 63; Exit; end;
  ea := (a shr 52) and $7FF;
  eb := (b shr 52) and $7FF;
  if eb = 0 then
  begin
    if ea = 0 then Result := dQNAN
    else Result := (Int64(resSign) shl 63) or D_EXPF;
    Exit;
  end;
  if ea = 0 then begin Result := Int64(resSign) shl 63; Exit; end;
  ma := (Int64(1) shl 52) or (a and D_MANT);
  mb := (Int64(1) shl 52) or (b and D_MANT);
  resExp := ea - eb + 1022;
  if ma >= mb then begin mb := mb shl 1; resExp := resExp + 1; end;
  { 56 quotient bits (53 significand + guard/round/sticky); no div operator }
  rem := ma;
  q := 0;
  i := 0;
  while i < 56 do
  begin
    rem := rem shl 1;
    q := q shl 1;
    if rem >= mb then begin rem := rem - mb; q := q or 1; end;
    i := i + 1;
  end;
  if rem <> 0 then q := q or 1;
  Result := dRoundPack(resSign, resExp, q);
end;

function __pxx_dcmp(a: Int64; b: Int64): Integer;
var ua, ub: Int64; sa, sb: Integer;
begin
  if dIsNaN(a) or dIsNaN(b) then begin Result := 2; Exit; end;
  ua := a and ((Int64(1) shl 63) - 1);
  ub := b and ((Int64(1) shl 63) - 1);
  if (ua = 0) and (ub = 0) then begin Result := 0; Exit; end;   { +0 = -0 }
  sa := (a shr 63) and 1;
  sb := (b shr 63) and 1;
  if sa <> sb then begin if sa = 1 then Result := -1 else Result := 1; Exit; end;
  if ua = ub then begin Result := 0; Exit; end;
  if ua > ub then begin if sa = 1 then Result := -1 else Result := 1; end
  else begin if sa = 1 then Result := 1 else Result := -1; end;
end;

function __pxx_i2d(v: Integer): Int64;
var sign: Integer; uv: Int64;
begin
  if v = 0 then begin Result := 0; Exit; end;
  if v < 0 then begin sign := 1; uv := -Int64(v); end
  else begin sign := 0; uv := Int64(v); end;
  { 32-bit ints are exact in double; seed exp = bias + mantbits + 3 = 1078 }
  Result := dRoundPack(sign, 1078, uv);
end;

function __pxx_d2i(a: Int64): Integer;
var sign, exp, shift: Integer; m, r: Int64;
begin
  exp := (a shr 52) and $7FF;
  if exp < 1023 then begin Result := 0; Exit; end;       { |x| < 1 }
  sign := (a shr 63) and 1;
  if exp = 2047 then                                      { inf / NaN }
  begin
    if (a and D_MANT) <> 0 then begin Result := 0; Exit; end;
    if sign = 1 then Result := Integer($80000000) else Result := $7FFFFFFF;
    Exit;
  end;
  if exp >= 1054 then                                     { |x| >= 2^31 -> saturate }
  begin
    if sign = 1 then Result := Integer($80000000) else Result := $7FFFFFFF;
    Exit;
  end;
  m := (Int64(1) shl 52) or (a and D_MANT);               { value = m * 2^(exp-1075) }
  shift := exp - 1075;
  if shift > 0 then r := m shl shift
  else r := m shr (-shift);                               { truncate toward zero }
  if sign = 1 then r := -r;
  Result := Integer(r);
end;

function __pxx_s2d(a: LongWord): Int64;
var sign, exp: Integer; frac: LongWord; dexp: Integer;
begin
  sign := (a shr 31) and 1;
  exp := (a shr 23) and $FF;
  frac := a and $7FFFFF;
  if exp = 0 then begin Result := Int64(sign) shl 63; Exit; end;   { zero / subnormal flush }
  if exp = 255 then
  begin
    if frac <> 0 then Result := dQNAN                              { NaN }
    else Result := (Int64(sign) shl 63) or D_EXPF;                 { Inf }
    Exit;
  end;
  dexp := exp - 127 + 1023;          { rebias }
  Result := (Int64(sign) shl 63) or (Int64(dexp) shl 52) or (Int64(frac) shl 29);
end;

function __pxx_d2s(a: Int64): LongWord;
var sign, exp, sExp: Integer; m: Int64;
begin
  sign := (a shr 63) and 1;
  exp := (a shr 52) and $7FF;
  if exp = 0 then begin Result := LongWord(sign) shl 31; Exit; end;   { zero / subnormal flush }
  if exp = 2047 then
  begin
    if (a and D_MANT) <> 0 then Result := S_QNAN                      { NaN }
    else Result := (LongWord(sign) shl 31) or S_INF;                  { Inf }
    Exit;
  end;
  m := (Int64(1) shl 52) or (a and D_MANT);    { 53-bit significand }
  sExp := exp - 896;                            { = (exp - 1023) + 127 }
  m := sShiftRightSticky(m, 26);                { 53 -> 27 bits (24 + 3 guard) }
  Result := sRoundPack(sign, sExp, m);          { rounds, handles over/underflow }
end;

end.
