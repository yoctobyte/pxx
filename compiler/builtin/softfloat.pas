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

end.
