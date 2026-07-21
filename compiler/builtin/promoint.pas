{ SPDX-License-Identifier: Zlib }
unit promoint;

{ Promotable-int runtime (feature-a-promotable-int stage 3).

  A promotable int is one semantic type — arbitrary precision — stored in a slot
  of two NATIVE machine words:

      [0] tag      PROMO_TAG_INLINE (0) or PROMO_TAG_HEAP (1)
      [1] payload  the machine integer when INLINE,
                   a managed AnsiString ref when HEAP

  The HEAP payload is an AnsiString holding the bignum's BINARY serialization
  (sign byte, then base-1e9 limbs as 8-byte little-endian words). Using a
  managed string rather than a bare heap block is deliberate: it is what makes
  lifetime free. The AnsiString refcount path already exists, is already
  --threadsafe-aware, and already releases at scope exit, so a promotable int
  that spills to the heap needs no new reclamation machinery — which matters
  because it is CREATION that is rare here, not lifetime: a factorial or crypto
  loop churns bignums and would leak without it.

  Serialization (rather than pointing at a live TBig) costs a pack/unpack per
  operation. That is the stage-3 correctness tier; stage 4's check elision and
  range analysis are what restore native speed for values that never leave the
  inline tier.

  Every routine takes slot ADDRESSES: once a value may be a bignum, an rvalue
  cannot be a machine int, so the compiler passes slots (decide-promoint-rvalue-
  representation, Option A — the tyVariant model). }

interface

const
  PROMO_TAG_INLINE = 0;
  PROMO_TAG_HEAP   = 1;

  { Variant tags. Mirrors defs.inc's VT_* (not visible from a builtin unit);
    the promo block is deliberately contiguous so VarClear can range-test it. }
  VT_EMPTY_TAG       = 0;
  VT_INT_TAG         = 1;
  VT_INT64_TAG       = 2;
  VT_BOOL_TAG        = 4;
  VT_STRING_TAG      = 6;
  VT_PROMO_INT64_TAG = 8193;

type
  PPromoWord = ^NativeInt;
  PPromoStr  = ^AnsiString;
  { A VARIANT slot is 8-byte tag + 8-byte payload on EVERY target, including
    32-bit ones — unlike a promo slot, which is two NATIVE words. Reading a
    variant through PPromoWord worked on x86-64 by coincidence and read the
    wrong halves on i386. }
  PVarWord = ^Int64;

procedure PXXPromoFromInt(dst: Pointer; v: Int64);
procedure PXXPromoFromStr(dst: Pointer; const s: AnsiString);
procedure PXXPromoCopy(dst, src: Pointer);
procedure PXXPromoClear(dst: Pointer);
procedure PXXPromoInit(dst: Pointer);
procedure PXXPromoAdd(dst, a, b: Pointer);
procedure PXXPromoSub(dst, a, b: Pointer);
procedure PXXPromoMul(dst, a, b: Pointer);
procedure PXXPromoAddInt(dst, a: Pointer; b: Int64);
procedure PXXPromoSubInt(dst, a: Pointer; b: Int64);
procedure PXXPromoMulInt(dst, a: Pointer; b: Int64);
procedure PXXPromoDiv(dst, a, b: Pointer);
procedure PXXPromoMod(dst, a, b: Pointer);
procedure PXXPromoAnd(dst, a, b: Pointer);
procedure PXXPromoOr(dst, a, b: Pointer);
procedure PXXPromoXor(dst, a, b: Pointer);
procedure PXXPromoShl(dst, a, b: Pointer);
procedure PXXPromoShr(dst, a, b: Pointer);
function  PXXPromoCmp(a, b: Pointer): Integer;
function  PXXPromoToStr(a: Pointer): AnsiString;
procedure PXXPromoToVariant(dstVar, src: Pointer);
procedure PXXPromoFromVariant(dst, srcVar: Pointer);
function  PXXPromoVarArithTry(dst, a, b: Pointer; op: Integer): Integer;
function  PXXPromoVarCmpTry(a, b: Pointer; op: Integer): Integer;
function  PXXPromoFitsInt64(a: Pointer): Boolean;
function  PXXPromoToInt64(a: Pointer): Int64;
function  PXXPromoToInt64Wrap(a: Pointer): Int64;

implementation

{ ---- internal bignum core ----------------------------------------------

  Self-contained on purpose. lib/rtl/bignum.pas exists and is good, but it
  `uses sysutils`, and a builtin unit that drags sysutils in would defeat the
  feature's own "a program that never names the type shows no size growth"
  gate — and invert the layering, since builtin units sit below the Track B
  libraries. Only the operations the promotable int actually needs are here;
  keeping the set small is what lets DCE drop all of it.

  Magnitude is base-1e9, little-endian, no trailing zero limbs. }

const
  BIG_BASE = 1000000000;

type
  TBig = record
    neg:   Boolean;
    limbs: array of Int64;
  end;
  TByteDynArray = array of Byte;

procedure BNorm(var a: TBig);
var n: Integer;
begin
  n := Length(a.limbs);
  while (n > 0) and (a.limbs[n - 1] = 0) do Dec(n);
  SetLength(a.limbs, n);
  if n = 0 then a.neg := False;
end;

function BIsZero(const a: TBig): Boolean;
begin
  BIsZero := Length(a.limbs) = 0;
end;

function BFromInt(v: Int64): TBig;
var r: TBig;
    n: Integer;
    u: Int64;
    tmp: array[0..3] of Int64;
begin
  r.neg := v < 0;
  { Low(Int64) has no positive counterpart — peel one unit off before negating
    so the magnitude loop never overflows. }
  if v = Low(Int64) then
  begin
    u := High(Int64);
    Inc(u);            { wraps to |Low(Int64)| conceptually; handled below }
    u := High(Int64);
    n := 0;
    { |Low(Int64)| = High(Int64) + 1; build it as such }
    tmp[0] := (u mod BIG_BASE) + 1;
    tmp[1] := (u div BIG_BASE) mod BIG_BASE;
    tmp[2] := (u div BIG_BASE) div BIG_BASE;
    if tmp[0] >= BIG_BASE then
    begin
      tmp[0] := tmp[0] - BIG_BASE;
      tmp[1] := tmp[1] + 1;
    end;
    n := 3;
    SetLength(r.limbs, n);
    r.limbs[0] := tmp[0]; r.limbs[1] := tmp[1]; r.limbs[2] := tmp[2];
    BNorm(r);
    BFromInt := r;
    Exit;
  end;
  if v < 0 then u := -v else u := v;
  n := 0;
  while u > 0 do
  begin
    tmp[n] := u mod BIG_BASE;
    u := u div BIG_BASE;
    Inc(n);
  end;
  SetLength(r.limbs, n);
  while n > 0 do
  begin
    Dec(n);
    r.limbs[n] := tmp[n];
  end;
  BNorm(r);
  BFromInt := r;
end;

function BCmpMag(const a, b: TBig): Integer;
var i: Integer;
begin
  if Length(a.limbs) <> Length(b.limbs) then
  begin
    if Length(a.limbs) < Length(b.limbs) then BCmpMag := -1 else BCmpMag := 1;
    Exit;
  end;
  i := Length(a.limbs) - 1;
  while i >= 0 do
  begin
    if a.limbs[i] <> b.limbs[i] then
    begin
      if a.limbs[i] < b.limbs[i] then BCmpMag := -1 else BCmpMag := 1;
      Exit;
    end;
    Dec(i);
  end;
  BCmpMag := 0;
end;

function BCmp(const a, b: TBig): Integer;
var m: Integer;
begin
  if a.neg <> b.neg then
  begin
    if a.neg then BCmp := -1 else BCmp := 1;
    Exit;
  end;
  m := BCmpMag(a, b);
  if a.neg then BCmp := -m else BCmp := m;
end;

{ |a| + |b| }
function BAddMag(const a, b: TBig): TBig;
var r: TBig;
    i, n: Integer;
    carry, av, bv, sv: Int64;
begin
  n := Length(a.limbs);
  if Length(b.limbs) > n then n := Length(b.limbs);
  SetLength(r.limbs, n + 1);
  carry := 0;
  for i := 0 to n do
  begin
    av := 0; bv := 0;
    if i < Length(a.limbs) then av := a.limbs[i];
    if i < Length(b.limbs) then bv := b.limbs[i];
    sv := av + bv + carry;
    if sv >= BIG_BASE then
    begin
      r.limbs[i] := sv - BIG_BASE;
      carry := 1;
    end
    else
    begin
      r.limbs[i] := sv;
      carry := 0;
    end;
  end;
  r.neg := False;
  BNorm(r);
  BAddMag := r;
end;

{ |a| - |b|, requires |a| >= |b| }
function BSubMag(const a, b: TBig): TBig;
var r: TBig;
    i: Integer;
    borrow, av, bv, sv: Int64;
begin
  SetLength(r.limbs, Length(a.limbs));
  borrow := 0;
  for i := 0 to Length(a.limbs) - 1 do
  begin
    av := a.limbs[i];
    bv := 0;
    if i < Length(b.limbs) then bv := b.limbs[i];
    sv := av - bv - borrow;
    if sv < 0 then
    begin
      sv := sv + BIG_BASE;
      borrow := 1;
    end
    else
      borrow := 0;
    r.limbs[i] := sv;
  end;
  r.neg := False;
  BNorm(r);
  BSubMag := r;
end;

function BAddSigned(const a, b: TBig): TBig;
var r: TBig;
    c: Integer;
begin
  if a.neg = b.neg then
  begin
    r := BAddMag(a, b);
    r.neg := a.neg;
    BNorm(r);
    BAddSigned := r;
    Exit;
  end;
  c := BCmpMag(a, b);
  if c = 0 then
  begin
    SetLength(r.limbs, 0);
    r.neg := False;
    BAddSigned := r;
    Exit;
  end;
  if c > 0 then
  begin
    r := BSubMag(a, b);
    r.neg := a.neg;
  end
  else
  begin
    r := BSubMag(b, a);
    r.neg := b.neg;
  end;
  BNorm(r);
  BAddSigned := r;
end;

function BNeg(const a: TBig): TBig;
var r: TBig;
begin
  r := a;
  if not BIsZero(r) then r.neg := not r.neg;
  BNeg := r;
end;

function BSubSigned(const a, b: TBig): TBig;
begin
  BSubSigned := BAddSigned(a, BNeg(b));
end;

function BMul(const a, b: TBig): TBig;
var r: TBig;
    i, j, na, nb: Integer;
    carry, cur: Int64;
begin
  na := Length(a.limbs);
  nb := Length(b.limbs);
  if (na = 0) or (nb = 0) then
  begin
    SetLength(r.limbs, 0);
    r.neg := False;
    BMul := r;
    Exit;
  end;
  SetLength(r.limbs, na + nb);
  for i := 0 to na + nb - 1 do r.limbs[i] := 0;
  for i := 0 to na - 1 do
  begin
    carry := 0;
    for j := 0 to nb - 1 do
    begin
      { each limb < 1e9, so the product < 1e18 and the running sum stays
        inside Int64 with room for the carry }
      cur := r.limbs[i + j] + a.limbs[i] * b.limbs[j] + carry;
      r.limbs[i + j] := cur mod BIG_BASE;
      carry := cur div BIG_BASE;
    end;
    j := nb;
    while carry > 0 do
    begin
      cur := r.limbs[i + j] + carry;
      r.limbs[i + j] := cur mod BIG_BASE;
      carry := cur div BIG_BASE;
      Inc(j);
    end;
  end;
  r.neg := a.neg <> b.neg;
  BNorm(r);
  BMul := r;
end;

{ |a| * m, m a small non-negative Int64 below BIG_BASE }
function BMulSmall(const a: TBig; m: Int64): TBig;
var r: TBig;
    i: Integer;
    carry, cur: Int64;
begin
  if (m = 0) or BIsZero(a) then
  begin
    SetLength(r.limbs, 0);
    r.neg := False;
    BMulSmall := r;
    Exit;
  end;
  SetLength(r.limbs, Length(a.limbs) + 2);
  for i := 0 to Length(r.limbs) - 1 do r.limbs[i] := 0;
  carry := 0;
  for i := 0 to Length(a.limbs) - 1 do
  begin
    cur := a.limbs[i] * m + carry;
    r.limbs[i] := cur mod BIG_BASE;
    carry := cur div BIG_BASE;
  end;
  i := Length(a.limbs);
  while carry > 0 do
  begin
    r.limbs[i] := carry mod BIG_BASE;
    carry := carry div BIG_BASE;
    Inc(i);
  end;
  r.neg := False;
  BNorm(r);
  BMulSmall := r;
end;

{ Shift the magnitude up by one base-1e9 limb and add `d` as the new low limb. }
function BShiftAdd(const a: TBig; d: Int64): TBig;
var r: TBig;
    i: Integer;
begin
  if BIsZero(a) and (d = 0) then
  begin
    SetLength(r.limbs, 0);
    r.neg := False;
    BShiftAdd := r;
    Exit;
  end;
  SetLength(r.limbs, Length(a.limbs) + 1);
  r.limbs[0] := d;
  for i := 0 to Length(a.limbs) - 1 do
    r.limbs[i + 1] := a.limbs[i];
  r.neg := False;
  BNorm(r);
  BShiftAdd := r;
end;

{ Schoolbook long division in base 1e9. Each quotient digit is found by binary
  search over 0..BIG_BASE-1 using BMulSmall+BCmpMag — about 30 magnitude
  compares per digit, which is ample for the correctness tier.
  Truncates toward zero, sign(r) = sign(a), matching Pascal div/mod. }
procedure BDivMod(const a, b: TBig; var q, r: TBig);
var cur, trial: TBig;
    qd: array of Int64;
    i: Integer;
    lo, hi, mid: Int64;
begin
  SetLength(q.limbs, 0); q.neg := False;
  SetLength(r.limbs, 0); r.neg := False;
  if BIsZero(b) then RunError(200);          { division by zero }
  if BCmpMag(a, b) < 0 then
  begin
    r := a;
    BNorm(r);
    Exit;
  end;
  SetLength(qd, Length(a.limbs));
  SetLength(cur.limbs, 0); cur.neg := False;
  i := Length(a.limbs) - 1;
  while i >= 0 do
  begin
    cur := BShiftAdd(cur, a.limbs[i]);
    lo := 0;
    hi := BIG_BASE - 1;
    while lo < hi do
    begin
      mid := (lo + hi + 1) div 2;
      trial := BMulSmall(b, mid);
      if BCmpMag(trial, cur) <= 0 then lo := mid else hi := mid - 1;
    end;
    qd[i] := lo;
    if lo > 0 then
      cur := BSubMag(cur, BMulSmall(b, lo));
    Dec(i);
  end;
  SetLength(q.limbs, Length(qd));
  for i := 0 to Length(qd) - 1 do q.limbs[i] := qd[i];
  q.neg := a.neg <> b.neg;
  BNorm(q);
  r := cur;
  r.neg := a.neg;
  BNorm(r);
end;

function BToStr(const a: TBig): AnsiString;
var s, part: AnsiString;
    i, k: Integer;
    v: Int64;
begin
  if BIsZero(a) then
  begin
    BToStr := '0';
    Exit;
  end;
  s := '';
  i := Length(a.limbs) - 1;
  { top limb without padding, the rest zero-padded to 9 digits }
  Str(a.limbs[i], part);
  s := part;
  Dec(i);
  while i >= 0 do
  begin
    v := a.limbs[i];
    Str(v, part);
    for k := Length(part) to 8 do s := s + '0';
    s := s + part;
    Dec(i);
  end;
  if a.neg then s := '-' + s;
  BToStr := s;
end;

{ ---- bitwise (Python two's-complement semantics) -----------------------

  Bignums here are sign-magnitude base-1e9, which has no bit view, so a bitwise
  op converts BOTH operands to a fixed-width two's-complement BYTE array, applies
  the op byte-wise, and reads the result back as a signed two's-complement value.
  Python's ints are infinite-width two's complement; a width one byte wider than
  the larger operand's magnitude reproduces the sign-extension exactly (the extra
  byte carries the sign bit so `-1 & big` keeps big's high bits). }

{ Bitwise works over fixed byte buffers rather than dynamic arrays: pxx's
  dynamic-array-return codegen has a history of miscompiles, and the operands
  here are bounded (uforth's widest is a 128-bit composite), so a fixed cap is
  both safe and simpler. }
const PROMO_BITBYTES = 512;   { supports up to a ~4096-bit value }
type TBitBuf = array[0..PROMO_BITBYTES - 1] of Byte;

{ magnitude of `a` as little-endian base-256 bytes; returns the byte count }
function BMagToBuf(const a: TBig; var buf: TBitBuf): Integer;
var cur, q: TBig; rem: Int64; n, i: Integer;
begin
  if BIsZero(a) then begin BMagToBuf := 0; Exit; end;
  cur := a; cur.neg := False;
  n := 0;
  while not BIsZero(cur) do
  begin
    SetLength(q.limbs, Length(cur.limbs)); q.neg := False;
    rem := 0;
    for i := Length(cur.limbs) - 1 downto 0 do
    begin
      rem := rem * BIG_BASE + cur.limbs[i];
      q.limbs[i] := rem div 256;
      rem := rem mod 256;
    end;
    BNorm(q);
    if n < PROMO_BITBYTES then buf[n] := Byte(rem);
    Inc(n);
    cur := q;
  end;
  BMagToBuf := n;
end;

{ signed two's-complement of `a` into `w` bytes of `buf` (w >= mag length + 1) }
procedure BTwosToBuf(const a: TBig; w: Integer; var buf: TBitBuf);
var mag: TBitBuf; mn, i, carry, v: Integer;
begin
  mn := BMagToBuf(a, mag);
  for i := 0 to w - 1 do
    if i < mn then buf[i] := mag[i] else buf[i] := 0;
  if a.neg then
  begin
    carry := 1;
    for i := 0 to w - 1 do
    begin
      v := (buf[i] xor $FF) + carry;
      buf[i] := Byte(v and $FF);
      carry := v shr 8;
    end;
  end;
end;

{ read `w` little-endian two's-complement bytes of `buf` as a signed TBig }
function BFromBuf(const buf: TBitBuf; w: Integer): TBig;
var mag: TBitBuf; i, carry, v, k: Integer; neg: Boolean; r: TBig;
begin
  neg := (w > 0) and ((buf[w - 1] and $80) <> 0);
  if neg then
  begin
    carry := 1;
    for i := 0 to w - 1 do
    begin
      v := (buf[i] xor $FF) + carry;
      mag[i] := Byte(v and $FF);
      carry := v shr 8;
    end;
  end
  else
    for i := 0 to w - 1 do mag[i] := buf[i];
  SetLength(r.limbs, 0); r.neg := False;
  for k := w - 1 downto 0 do
    r := BAddMag(BMulSmall(r, 256), BFromInt(mag[k]));
  r.neg := neg and not BIsZero(r);
  BNorm(r);
  BFromBuf := r;
end;

{ op: 0=AND 1=OR 2=XOR (Python two's-complement) }
function BBitwise(const a, b: TBig; op: Integer): TBig;
var wa, wb, w, i: Integer; ta, tb, tmp: TBitBuf;
begin
  wa := BMagToBuf(a, tmp); wb := BMagToBuf(b, tmp);
  w := wa; if wb > w then w := wb; Inc(w);   { +1 sign byte }
  if w > PROMO_BITBYTES then w := PROMO_BITBYTES;
  BTwosToBuf(a, w, ta); BTwosToBuf(b, w, tb);
  for i := 0 to w - 1 do
    case op of
      0: ta[i] := ta[i] and tb[i];
      1: ta[i] := ta[i] or tb[i];
      else ta[i] := ta[i] xor tb[i];
    end;
  BBitwise := BFromBuf(ta, w);
end;

{ a * 2^k (magnitude doubling preserves the sign, matching Python `<<`) }
function BShl(const a: TBig; k: Int64): TBig;
var r: TBig; i: Int64; wasNeg: Boolean;
begin
  if k <= 0 then begin BShl := a; Exit; end;
  wasNeg := a.neg;
  r := a; r.neg := False;
  for i := 1 to k do r := BMulSmall(r, 2);
  r.neg := wasNeg and not BIsZero(r);
  BShl := r;
end;

{ floor(a / 2^k) — Python arithmetic shift right }
function BShr(const a: TBig; k: Int64): TBig;
var q, rem, p2: TBig; i: Int64;
begin
  if k <= 0 then begin BShr := a; Exit; end;
  p2 := BFromInt(1);
  for i := 1 to k do p2 := BMulSmall(p2, 2);
  BDivMod(a, p2, q, rem);
  { BDivMod truncates toward zero; Python `>>` FLOORS. For a negative dividend
    with a nonzero remainder, floor is one MORE in magnitude (more negative). }
  if a.neg and not BIsZero(rem) then
  begin
    q.neg := False;
    q := BAddMag(q, BFromInt(1));
    q.neg := not BIsZero(q);
  end;
  BShr := q;
end;


{ ---- slot accessors ---------------------------------------------------- }

function SlotTag(p: Pointer): NativeInt;
var w: PPromoWord;
begin
  w := PPromoWord(p);
  SlotTag := w^;
end;

function SlotPayloadAddr(p: Pointer): Pointer;
begin
  SlotPayloadAddr := Pointer(NativeInt(p) + SizeOf(NativeInt));
end;

function SlotInt(p: Pointer): Int64;
var w: PPromoWord;
begin
  w := PPromoWord(SlotPayloadAddr(p));
  SlotInt := Int64(w^);
end;

{ ---- bignum <-> managed-string serialization --------------------------- }

{ Pack a TBig into an AnsiString: one sign byte, then each base-1e9 limb as
  8 little-endian bytes. Binary rather than decimal so no base conversion
  happens on the round trip. }
function PackBig(const a: TBig): AnsiString;
var s: AnsiString;
    i, k: Integer;
    v: Int64;
begin
  s := '';
  if a.neg then s := s + #1 else s := s + #0;
  for i := 0 to Length(a.limbs) - 1 do
  begin
    v := a.limbs[i];
    for k := 0 to 7 do
    begin
      s := s + Chr(Byte(v and 255));
      v := v shr 8;
    end;
  end;
  PackBig := s;
end;

function UnpackBig(const s: AnsiString): TBig;
var r: TBig;
    n, i, k: Integer;
    v: Int64;
begin
  n := (Length(s) - 1) div 8;
  r.neg := (Length(s) >= 1) and (Ord(s[1]) = 1);
  SetLength(r.limbs, n);
  for i := 0 to n - 1 do
  begin
    v := 0;
    for k := 7 downto 0 do
      v := (v shl 8) or Int64(Ord(s[1 + i * 8 + k + 1]));
    r.limbs[i] := v;
  end;
  UnpackBig := r;
end;

{ Read a slot as a bignum, whichever tier it is in. }
function SlotBig(p: Pointer): TBig;
var sp: PPromoStr;
begin
  if SlotTag(p) = PROMO_TAG_HEAP then
  begin
    sp := PPromoStr(SlotPayloadAddr(p));
    SlotBig := UnpackBig(sp^);
  end
  else
    SlotBig := BFromInt(SlotInt(p));
end;

{ ---- stores ------------------------------------------------------------ }

procedure StoreBig(dst: Pointer; const r: TBig); forward;

{ Does this Int64 fit the target's native inline word? Always on a 64-bit
  target; on a 32-bit one it gates the mixed fast forms below. }
function NativeFits(v: Int64): Boolean;
begin
  if SizeOf(NativeInt) >= 8 then NativeFits := True
  else NativeFits := (v <= 2147483647) and (v >= -2147483648);
end;

procedure PXXPromoClear(dst: Pointer);
var sp: PPromoStr;
    w: PPromoWord;
begin
  if SlotTag(dst) = PROMO_TAG_HEAP then
  begin
    sp := PPromoStr(SlotPayloadAddr(dst));
    sp^ := '';                       { managed release }
  end;
  w := PPromoWord(dst);
  w^ := PROMO_TAG_INLINE;
  w := PPromoWord(SlotPayloadAddr(dst));
  w^ := 0;
end;

{ Blind initialisation of a FRESH slot: writes tag and payload without reading
  either. PXXPromoClear cannot be used on uninitialised memory because it tests
  the old tag and would release a garbage payload. Used for compiler temps,
  which is also why promo needs no IR_ZERO_SYM — an op several backends do not
  implement. }
procedure PXXPromoInit(dst: Pointer);
var w: PPromoWord;
begin
  w := PPromoWord(dst);
  w^ := PROMO_TAG_INLINE;
  w := PPromoWord(SlotPayloadAddr(dst));
  w^ := 0;
end;

{ The spill half of PXXPromoFromInt, kept in its OWN routine on purpose.

  A function that so much as mentions a TBig pays managed prologue/epilogue on
  EVERY call — the record holds a dynamic array, so its temps are zero-inited
  and finalized whether or not the branch that uses them runs. Measured: with
  the slow path inline, one PXXPromoAddInt cost ~344 ns; split out, the fast
  path is a handful of instructions. Keep every hot routine free of TBig. }
procedure FromIntSpill(dst: Pointer; v: Int64);
begin
  StoreBig(dst, BFromInt(v));
end;

procedure PXXPromoFromInt(dst: Pointer; v: Int64);
var w: PPromoWord;
begin
  { The inline tier is ONE NATIVE WORD. On a 32-bit target that is narrower than
    the Int64 this routine accepts, so a value that does not fit must spill to
    the heap rather than truncate — which is also what makes the 32-bit inline
    tier correct for free, since every arithmetic fast path funnels its result
    through here. }
  if (SizeOf(NativeInt) < 8) and ((v > 2147483647) or (v < -2147483648)) then
  begin
    FromIntSpill(dst, v);
    Exit;
  end;
  if SlotTag(dst) <> PROMO_TAG_INLINE then PXXPromoClear(dst);
  w := PPromoWord(dst);
  w^ := PROMO_TAG_INLINE;
  w := PPromoWord(SlotPayloadAddr(dst));
  w^ := NativeInt(v);
end;

{ Store a bignum result, demoting back to the inline tier whenever it fits.
  Demotion is not an optimization detail — without it a value that grew and then
  shrank would stay boxed forever, and every later op would pay the unpack. }
{ Can this bignum live in the INLINE tier — i.e. does it fit one NATIVE word?
  Not "does it fit an Int64": on a 32-bit target the inline payload is 32 bits,
  and demoting an Int64-sized value there sent StoreBig back into
  PXXPromoFromInt, which had called StoreBig precisely because the value did not
  fit — infinite recursion, stack overflow, segfault. It could not happen on
  x86-64, where NativeInt is already 8 bytes, which is why it only ever showed
  up on i386. }
function BToNative(const r: TBig; var v: Int64): Boolean;
var i: Integer;
    acc: Int64;
begin
  BToNative := False;
  if Length(r.limbs) > 3 then Exit;         { >= 1e27, far past any native word }
  acc := 0;
  for i := Length(r.limbs) - 1 downto 0 do
  begin
    if acc > (High(Int64) - r.limbs[i]) div BIG_BASE then Exit;
    acc := acc * BIG_BASE + r.limbs[i];
  end;
  if r.neg then acc := -acc;
  if SizeOf(NativeInt) < 8 then
    if (acc > 2147483647) or (acc < -2147483648) then Exit;
  v := acc;
  BToNative := True;
end;

procedure StoreBig(dst: Pointer; const r: TBig);
var sp: PPromoStr;
    w: PPromoWord;
    small: Int64;
begin
  { Demote whenever the value fits the inline tier. Writing the payload DIRECTLY
    rather than calling PXXPromoFromInt keeps this free of the recursion above
    by construction, and skips a decimal round trip that used to cost a
    BToStr + Val on every stored result. }
  if BToNative(r, small) then
  begin
    PXXPromoClear(dst);
    w := PPromoWord(SlotPayloadAddr(dst));
    w^ := NativeInt(small);
    Exit;
  end;
  PXXPromoClear(dst);
  w := PPromoWord(dst);
  w^ := PROMO_TAG_HEAP;
  sp := PPromoStr(SlotPayloadAddr(dst));
  sp^ := PackBig(r);
end;

{ Exact decimal -> promotable int. The inverse of PXXPromoToStr, and what lets
  a literal wider than Int64 be written down at all: the lexer folds every
  literal to 64 bits, so a wide one has to arrive here as TEXT. }
procedure PXXPromoFromStr(dst: Pointer; const s: AnsiString);
var r, ten: TBig;
    i: Integer;
    neg: Boolean;
begin
  SetLength(r.limbs, 0);
  r.neg := False;
  ten := BFromInt(10);
  neg := False;
  i := 1;
  if (Length(s) >= 1) and ((s[1] = '-') or (s[1] = '+')) then
  begin
    neg := s[1] = '-';
    i := 2;
  end;
  while i <= Length(s) do
  begin
    { explicit range rather than `in ['0'..'9']`: set membership is a standard
      builtin the riscv32 bare-metal path cannot lower, and this unit has to
      build on every target }
    if (s[i] < '0') or (s[i] > '9') then Break;
    r := BAddSigned(BMul(r, ten), BFromInt(Ord(s[i]) - 48));
    Inc(i);
  end;
  if neg and not BIsZero(r) then r.neg := True;
  StoreBig(dst, r);
end;

procedure PXXPromoCopy(dst, src: Pointer);
var sp, dp: PPromoStr;
    w: PPromoWord;
begin
  if dst = src then Exit;
  if SlotTag(src) = PROMO_TAG_HEAP then
  begin
    PXXPromoClear(dst);
    w := PPromoWord(dst);
    w^ := PROMO_TAG_HEAP;
    sp := PPromoStr(SlotPayloadAddr(src));
    dp := PPromoStr(SlotPayloadAddr(dst));
    dp^ := sp^;                      { managed retain }
  end
  else
    PXXPromoFromInt(dst, SlotInt(src));
end;

{ ---- arithmetic -------------------------------------------------------- }

{ The inline fast path is tried first and only falls back to the bignum tier on
  overflow, so a value that never leaves int64 never touches the heap. }

procedure PXXPromoAdd(dst, a, b: Pointer);
var x, y, r: Int64;
begin
  if (SlotTag(a) = PROMO_TAG_INLINE) and (SlotTag(b) = PROMO_TAG_INLINE) then
  begin
    x := SlotInt(a); y := SlotInt(b);
    r := x + y;
    { signed overflow: the result's sign disagrees with both operands' }
    if ((x >= 0) = (y >= 0)) and ((r >= 0) <> (x >= 0)) then
      StoreBig(dst, BAddSigned(BFromInt(x), BFromInt(y)))
    else
      PXXPromoFromInt(dst, r);
    Exit;
  end;
  StoreBig(dst, BAddSigned(SlotBig(a), SlotBig(b)));
end;

procedure PXXPromoSub(dst, a, b: Pointer);
var x, y, r: Int64;
begin
  if (SlotTag(a) = PROMO_TAG_INLINE) and (SlotTag(b) = PROMO_TAG_INLINE) then
  begin
    x := SlotInt(a); y := SlotInt(b);
    r := x - y;
    if ((x >= 0) <> (y >= 0)) and ((r >= 0) <> (x >= 0)) then
      StoreBig(dst, BSubSigned(BFromInt(x), BFromInt(y)))
    else
      PXXPromoFromInt(dst, r);
    Exit;
  end;
  StoreBig(dst, BSubSigned(SlotBig(a), SlotBig(b)));
end;

procedure PXXPromoMul(dst, a, b: Pointer);
var x, y, r: Int64;
begin
  if (SlotTag(a) = PROMO_TAG_INLINE) and (SlotTag(b) = PROMO_TAG_INLINE) then
  begin
    x := SlotInt(a); y := SlotInt(b);
    if (x = 0) or (y = 0) then
    begin
      PXXPromoFromInt(dst, 0);
      Exit;
    end;
    r := x * y;
    { division is the portable overflow oracle: no {$Q+} dependency, and it is
      correct on every target including the 32-bit cores }
    if (r div y = x) and not ((x = -1) and (y = Low(Int64)))
                    and not ((y = -1) and (x = Low(Int64))) then
      PXXPromoFromInt(dst, r)
    else
      StoreBig(dst, BMul(BFromInt(x), BFromInt(y)));
    Exit;
  end;
  StoreBig(dst, BMul(SlotBig(a), SlotBig(b)));
end;

{ ---- mixed promo-with-machine-int fast forms ----------------------------

  `p + n` where n is an ordinary integer used to cost FIVE runtime calls: init a
  temp, box n into it, init a result temp, add, copy back. These collapse it to
  one by taking the machine int directly — the common shape in real code (loop
  accumulators, counters, small constants).

  Aliasing dst = a is safe and intended (`p := p + n` writes straight into p):
  every operand is read into a local before anything is stored. }

procedure AddIntSlow(dst, a: Pointer; b: Int64);
begin
  StoreBig(dst, BAddSigned(SlotBig(a), BFromInt(b)));
end;

procedure PXXPromoAddInt(dst, a: Pointer; b: Int64);
var x, r: Int64;
begin
  if (SlotTag(a) = PROMO_TAG_INLINE) and NativeFits(b) then
  begin
    x := SlotInt(a);
    r := x + b;
    if ((x >= 0) = (b >= 0)) and ((r >= 0) <> (x >= 0)) then
      AddIntSlow(dst, a, b)
    else
      PXXPromoFromInt(dst, r);
    Exit;
  end;
  AddIntSlow(dst, a, b);
end;

procedure SubIntSlow(dst, a: Pointer; b: Int64);
begin
  StoreBig(dst, BSubSigned(SlotBig(a), BFromInt(b)));
end;

procedure PXXPromoSubInt(dst, a: Pointer; b: Int64);
var x, r: Int64;
begin
  if (SlotTag(a) = PROMO_TAG_INLINE) and NativeFits(b) then
  begin
    x := SlotInt(a);
    r := x - b;
    if ((x >= 0) <> (b >= 0)) and ((r >= 0) <> (x >= 0)) then
      SubIntSlow(dst, a, b)
    else
      PXXPromoFromInt(dst, r);
    Exit;
  end;
  SubIntSlow(dst, a, b);
end;

procedure MulIntSlow(dst, a: Pointer; b: Int64);
begin
  StoreBig(dst, BMul(SlotBig(a), BFromInt(b)));
end;

procedure PXXPromoMulInt(dst, a: Pointer; b: Int64);
var x, r: Int64;
begin
  if (SlotTag(a) = PROMO_TAG_INLINE) and NativeFits(b) then
  begin
    x := SlotInt(a);
    if (x = 0) or (b = 0) then
    begin
      PXXPromoFromInt(dst, 0);
      Exit;
    end;
    r := x * b;
    if (r div b = x) and not ((x = -1) and (b = Low(Int64)))
                    and not ((b = -1) and (x = Low(Int64))) then
      PXXPromoFromInt(dst, r)
    else
      MulIntSlow(dst, a, b);
    Exit;
  end;
  MulIntSlow(dst, a, b);
end;

procedure PXXPromoDiv(dst, a, b: Pointer);
var q, r: TBig;
begin
  if (SlotTag(a) = PROMO_TAG_INLINE) and (SlotTag(b) = PROMO_TAG_INLINE) then
  begin
    PXXPromoFromInt(dst, SlotInt(a) div SlotInt(b));
    Exit;
  end;
  BDivMod(SlotBig(a), SlotBig(b), q, r);
  StoreBig(dst, q);
end;

procedure PXXPromoMod(dst, a, b: Pointer);
var q, r: TBig;
begin
  if (SlotTag(a) = PROMO_TAG_INLINE) and (SlotTag(b) = PROMO_TAG_INLINE) then
  begin
    PXXPromoFromInt(dst, SlotInt(a) mod SlotInt(b));
    Exit;
  end;
  BDivMod(SlotBig(a), SlotBig(b), q, r);
  StoreBig(dst, r);
end;

function PXXPromoCmp(a, b: Pointer): Integer;
var x, y: Int64;
begin
  if (SlotTag(a) = PROMO_TAG_INLINE) and (SlotTag(b) = PROMO_TAG_INLINE) then
  begin
    x := SlotInt(a); y := SlotInt(b);
    if x < y then PXXPromoCmp := -1
    else if x > y then PXXPromoCmp := 1
    else PXXPromoCmp := 0;
    Exit;
  end;
  PXXPromoCmp := BCmp(SlotBig(a), SlotBig(b));
end;

{ A shift count as an Int64. Always small in practice; an inline slot is the
  common case, a heap slot is read from its low limbs. }
function PromoShiftCount(b: Pointer): Int64;
var bg: TBig; r: Int64; i: Integer;
begin
  if SlotTag(b) = PROMO_TAG_INLINE then begin PromoShiftCount := SlotInt(b); Exit; end;
  bg := SlotBig(b);
  r := 0;
  for i := Length(bg.limbs) - 1 downto 0 do r := r * BIG_BASE + bg.limbs[i];
  if bg.neg then r := -r;
  PromoShiftCount := r;
end;

{ ---- bitwise: Python two's-complement semantics ---- }
procedure PXXPromoAnd(dst, a, b: Pointer);
begin
  if (SlotTag(a) = PROMO_TAG_INLINE) and (SlotTag(b) = PROMO_TAG_INLINE) then
    PXXPromoFromInt(dst, SlotInt(a) and SlotInt(b))   { Int64 AND is two's complement }
  else
    StoreBig(dst, BBitwise(SlotBig(a), SlotBig(b), 0));
end;

procedure PXXPromoOr(dst, a, b: Pointer);
begin
  if (SlotTag(a) = PROMO_TAG_INLINE) and (SlotTag(b) = PROMO_TAG_INLINE) then
    PXXPromoFromInt(dst, SlotInt(a) or SlotInt(b))
  else
    StoreBig(dst, BBitwise(SlotBig(a), SlotBig(b), 1));
end;

procedure PXXPromoXor(dst, a, b: Pointer);
begin
  if (SlotTag(a) = PROMO_TAG_INLINE) and (SlotTag(b) = PROMO_TAG_INLINE) then
    PXXPromoFromInt(dst, SlotInt(a) xor SlotInt(b))
  else
    StoreBig(dst, BBitwise(SlotBig(a), SlotBig(b), 2));
end;

procedure PXXPromoShl(dst, a, b: Pointer);
begin
  { shift count b is small in practice; a<<k always risks Int64 overflow so it
    goes through the bignum path unconditionally. }
  StoreBig(dst, BShl(SlotBig(a), PromoShiftCount(b)));
end;

procedure PXXPromoShr(dst, a, b: Pointer);
begin
  StoreBig(dst, BShr(SlotBig(a), PromoShiftCount(b)));
end;

function PXXPromoToStr(a: Pointer): AnsiString;
var s: AnsiString;
begin
  if SlotTag(a) = PROMO_TAG_INLINE then
  begin
    Str(SlotInt(a), s);
    PXXPromoToStr := s;
    Exit;
  end;
  PXXPromoToStr := BToStr(SlotBig(a));
end;

{ ---- Variant interop ---------------------------------------------------

  A promotable int inside a Variant is stored in whichever tier keeps the
  variant machinery unchanged:

    INLINE value -> an ordinary VT_INT64 variant. The common case therefore
                    needs NO new handling anywhere downstream.
    HEAP value   -> VT_PROMO_INT64, payload = a managed AnsiString holding the
                    exact decimal.

  Making the heap payload a managed string (rather than, say, a raw block) is
  what keeps VarClear/VarCopy a RANGE TEST over the reserved tag block instead
  of a growing switch in six hand-written emitters. }

{ Release whatever the destination variant currently holds, leaving the payload
  word ZERO. Writing a managed string straight over the old payload would treat
  whatever was there — an integer, say — as an AnsiString ref and release
  garbage, which is exactly how the first version segfaulted. }
procedure ClearVariantSlot(dstVar: Pointer);
var tagW, payW: PVarWord;
    sp: PPromoStr;
begin
  tagW := PVarWord(dstVar);
  if (tagW^ = VT_STRING_TAG) or (tagW^ = VT_PROMO_INT64_TAG) then
  begin
    sp := PPromoStr(VarPayloadAddr(dstVar));
    sp^ := '';                       { managed release }
  end;
  payW := PVarWord(VarPayloadAddr(dstVar));
  payW^ := 0;
  tagW^ := VT_EMPTY_TAG;
end;

procedure PXXPromoToVariant(dstVar, src: Pointer);
var tagW, payW: PVarWord;
    sp: PPromoStr;
    txt: AnsiString;
    inlineVal: Int64;
    wasInline: Boolean;
begin
  { render/read BEFORE clearing: src and dstVar may be the same slot }
  wasInline := SlotTag(src) = PROMO_TAG_INLINE;
  inlineVal := 0;
  txt := '';
  if wasInline then inlineVal := SlotInt(src) else txt := BToStr(SlotBig(src));
  ClearVariantSlot(dstVar);
  tagW := PVarWord(dstVar);
  if wasInline then
  begin
    payW := PVarWord(VarPayloadAddr(dstVar));
    tagW^ := VT_INT64_TAG;
    payW^ := inlineVal;
    Exit;
  end;
  tagW^ := VT_PROMO_INT64_TAG;
  sp := PPromoStr(VarPayloadAddr(dstVar));
  sp^ := txt;
end;

procedure PXXPromoFromVariant(dst, srcVar: Pointer);
var tag: Int64;
    sp: PPromoStr;
    w: PVarWord;
begin
  tag := VarTag(srcVar);
  if tag = VT_PROMO_INT64_TAG then
  begin
    sp := PPromoStr(VarPayloadAddr(srcVar));
    PXXPromoFromStr(dst, sp^);
    Exit;
  end;
  if (tag = VT_INT_TAG) or (tag = VT_INT64_TAG) or (tag = VT_BOOL_TAG) then
  begin
    w := PVarWord(VarPayloadAddr(srcVar));
    PXXPromoFromInt(dst, w^);
    Exit;
  end;
  if tag = VT_STRING_TAG then
  begin
    sp := PPromoStr(VarPayloadAddr(srcVar));
    PXXPromoFromStr(dst, sp^);
    Exit;
  end;
  if tag = VT_EMPTY_TAG then
  begin
    PXXPromoFromInt(dst, 0);
    Exit;
  end;
  RunError(219);   { EVariantError: not convertible to an integer }
end;

{ ---- Variant ARITHMETIC ------------------------------------------------

  A variant holding a HEAP promo has an AnsiString payload; the ordinary variant
  binop treats a payload as an integer, so `v + w` returned the string POINTER
  arithmetic — a silent wrong answer, which is the one failure mode this type
  exists to remove.

  These are "try" helpers: they return 0 when neither operand is promo-tagged,
  and the compiler then falls through to the existing variant binop. That keeps
  ordinary variant semantics exactly where they already live (hand-written
  per-backend codegen) instead of reimplementing them here and risking drift.

  `op` is a small normalised code, not a token ordinal — TTokenKind is a
  compiler type and is not visible from a builtin unit. }

function VarTag(v: Pointer): Int64;
var w: PVarWord;
begin
  w := PVarWord(v);
  VarTag := w^;
end;

function VarPayloadAddr(v: Pointer): Pointer;
begin
  VarPayloadAddr := Pointer(NativeInt(v) + 8);
end;

function EitherPromoTagged(a, b: Pointer): Boolean;
begin
  EitherPromoTagged := (VarTag(a) = VT_PROMO_INT64_TAG) or
                       (VarTag(b) = VT_PROMO_INT64_TAG);
end;

function PXXPromoVarArithTry(dst, a, b: Pointer; op: Integer): Integer;
var pa, pb, pr: array[0..1] of NativeInt;   { three promo slots }
begin
  PXXPromoVarArithTry := 0;
  { shl/shr (9/10) are handled UNCONDITIONALLY: an int64 shl can overflow into
    the bignum range (Python `1 << 64` = 2^64) and the native variant shr is a
    LOGICAL shift while Python's >> is arithmetic floor division — so even two
    plain VT_INT64 operands must route through the promo runtime here. The
    other operators keep the promo-tag gate so ordinary variant semantics stay
    in the per-backend codegen. }
  if (op < 9) and not EitherPromoTagged(a, b) then Exit;
  PXXPromoInit(@pa); PXXPromoInit(@pb); PXXPromoInit(@pr);
  PXXPromoFromVariant(@pa, a);
  PXXPromoFromVariant(@pb, b);
  if op = 1 then PXXPromoAdd(@pr, @pa, @pb)
  else if op = 2 then PXXPromoSub(@pr, @pa, @pb)
  else if op = 3 then PXXPromoMul(@pr, @pa, @pb)
  else if op = 4 then PXXPromoDiv(@pr, @pa, @pb)
  else if op = 5 then PXXPromoMod(@pr, @pa, @pb)
  else if op = 6 then PXXPromoAnd(@pr, @pa, @pb)
  else if op = 7 then PXXPromoOr(@pr, @pa, @pb)
  else if op = 8 then PXXPromoXor(@pr, @pa, @pb)
  else if op = 9 then PXXPromoShl(@pr, @pa, @pb)
  else if op = 10 then PXXPromoShr(@pr, @pa, @pb)
  else
  begin
    { an operator with no promotable-int meaning (e.g. `/`): leave it to the
      ordinary variant path rather than inventing semantics }
    PXXPromoClear(@pa); PXXPromoClear(@pb); PXXPromoClear(@pr);
    Exit;
  end;
  PXXPromoToVariant(dst, @pr);
  { these slots are raw arrays, not compiler-managed locals, so their heap
    payloads must be released by hand }
  PXXPromoClear(@pa); PXXPromoClear(@pb); PXXPromoClear(@pr);
  PXXPromoVarArithTry := 1;
end;

{ 0 = not handled, 1 = False, 2 = True. Encoded in one return value so the
  caller needs a single call and one branch. }
function PXXPromoVarCmpTry(a, b: Pointer; op: Integer): Integer;
var pa, pb: array[0..1] of NativeInt;
    c: Integer;
    res: Boolean;
begin
  PXXPromoVarCmpTry := 0;
  if not EitherPromoTagged(a, b) then Exit;
  PXXPromoInit(@pa); PXXPromoInit(@pb);
  PXXPromoFromVariant(@pa, a);
  PXXPromoFromVariant(@pb, b);
  c := PXXPromoCmp(@pa, @pb);
  PXXPromoClear(@pa); PXXPromoClear(@pb);
  res := False;
  if op = 1 then res := c = 0
  else if op = 2 then res := c <> 0
  else if op = 3 then res := c < 0
  else if op = 4 then res := c <= 0
  else if op = 5 then res := c > 0
  else if op = 6 then res := c >= 0
  else
  begin
    PXXPromoVarCmpTry := 0;
    Exit;
  end;
  if res then PXXPromoVarCmpTry := 2 else PXXPromoVarCmpTry := 1;
end;

function PXXPromoFitsInt64(a: Pointer): Boolean;
begin
  PXXPromoFitsInt64 := SlotTag(a) = PROMO_TAG_INLINE;
end;

{ Narrowing to a machine int is a CHECKED conversion: a value that spilled to
  the heap cannot be delivered as an Int64, and silently truncating it is the
  defect this whole type exists to remove. }
function PXXPromoToInt64(a: Pointer): Int64;
begin
  if SlotTag(a) <> PROMO_TAG_INLINE then
    RunError(215);
  PXXPromoToInt64 := SlotInt(a);
end;

{ Slow path split out so the fast one never names TBig (a routine that mentions
  a dynarray record pays managed prologue on every call). }
function PromoWrapHeap(a: Pointer): Int64;
var bg: TBig; r: Int64; i: Integer;
begin
  bg := SlotBig(a);
  r := 0;
  for i := Length(bg.limbs) - 1 downto 0 do
    r := r * BIG_BASE + bg.limbs[i];   { wrapping is the point: value mod 2^64 }
  if bg.neg then r := -r;
  PromoWrapHeap := r;
end;

{ Narrowing WITH two's-complement wrap (value mod 2^64), the C/machine reading.
  Used where a promo value lands in a concrete int slot (a NilPy `int`-annotated
  variable): NilPy's documented narrowing of Python's arbitrary precision is
  64-bit congruence, and the masked-cell idiom (`n & 0xFFF... ; if n >= 2^63:
  n -= 2^64`) is only an identity under exactly this rule — the checked
  PXXPromoToInt64 would trap on the intermediate. }
function PXXPromoToInt64Wrap(a: Pointer): Int64;
begin
  if SlotTag(a) = PROMO_TAG_INLINE then
    PXXPromoToInt64Wrap := SlotInt(a)
  else
    PXXPromoToInt64Wrap := PromoWrapHeap(a);
end;

end.
