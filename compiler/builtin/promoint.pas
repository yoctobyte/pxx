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

procedure PXXPromoFromInt(dst: Pointer; v: Int64);
procedure PXXPromoFromStr(dst: Pointer; const s: AnsiString);
procedure PXXPromoCopy(dst, src: Pointer);
procedure PXXPromoClear(dst: Pointer);
procedure PXXPromoInit(dst: Pointer);
procedure PXXPromoAdd(dst, a, b: Pointer);
procedure PXXPromoSub(dst, a, b: Pointer);
procedure PXXPromoMul(dst, a, b: Pointer);
procedure PXXPromoDiv(dst, a, b: Pointer);
procedure PXXPromoMod(dst, a, b: Pointer);
function  PXXPromoCmp(a, b: Pointer): Integer;
function  PXXPromoToStr(a: Pointer): AnsiString;
procedure PXXPromoToVariant(dstVar, src: Pointer);
procedure PXXPromoFromVariant(dst, srcVar: Pointer);
function  PXXPromoVarArithTry(dst, a, b: Pointer; op: Integer): Integer;
function  PXXPromoVarCmpTry(a, b: Pointer; op: Integer): Integer;
function  PXXPromoFitsInt64(a: Pointer): Boolean;
function  PXXPromoToInt64(a: Pointer): Int64;

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
    StoreBig(dst, BFromInt(v));
    Exit;
  end;
  PXXPromoClear(dst);
  w := PPromoWord(SlotPayloadAddr(dst));
  w^ := NativeInt(v);
end;

{ Store a bignum result, demoting back to the inline tier whenever it fits.
  Demotion is not an optimization detail — without it a value that grew and then
  shrank would stay boxed forever, and every later op would pay the unpack. }
procedure StoreBig(dst: Pointer; const r: TBig);
var sp: PPromoStr;
    w: PPromoWord;
    txt: AnsiString;
    small: Int64;
    code: Integer;
begin
  txt := BToStr(r);
  Val(txt, small, code);
  if (code = 0) and (BCmp(r, BFromInt(small)) = 0) then
  begin
    PXXPromoFromInt(dst, small);
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
    if not (s[i] in ['0'..'9']) then Break;
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
var tagW, payW: PPromoWord;
    sp: PPromoStr;
begin
  tagW := PPromoWord(dstVar);
  if (tagW^ = VT_STRING_TAG) or (tagW^ = VT_PROMO_INT64_TAG) then
  begin
    sp := PPromoStr(SlotPayloadAddr(dstVar));
    sp^ := '';                       { managed release }
  end;
  payW := PPromoWord(SlotPayloadAddr(dstVar));
  payW^ := 0;
  tagW^ := VT_EMPTY_TAG;
end;

procedure PXXPromoToVariant(dstVar, src: Pointer);
var tagW, payW: PPromoWord;
    sp: PPromoStr;
    txt: AnsiString;
begin
  { render BEFORE clearing: src and dstVar may be the same slot }
  if SlotTag(src) <> PROMO_TAG_INLINE then txt := BToStr(SlotBig(src)) else txt := '';
  ClearVariantSlot(dstVar);
  tagW := PPromoWord(dstVar);
  if SlotTag(src) = PROMO_TAG_INLINE then
  begin
    payW := PPromoWord(SlotPayloadAddr(dstVar));
    tagW^ := VT_INT64_TAG;
    payW^ := NativeInt(SlotInt(src));
    Exit;
  end;
  tagW^ := VT_PROMO_INT64_TAG;
  sp := PPromoStr(SlotPayloadAddr(dstVar));
  sp^ := txt;
end;

procedure PXXPromoFromVariant(dst, srcVar: Pointer);
var tag: NativeInt;
    sp: PPromoStr;
    w: PPromoWord;
begin
  tag := SlotTag(srcVar);
  if tag = VT_PROMO_INT64_TAG then
  begin
    sp := PPromoStr(SlotPayloadAddr(srcVar));
    PXXPromoFromStr(dst, sp^);
    Exit;
  end;
  if (tag = VT_INT_TAG) or (tag = VT_INT64_TAG) or (tag = VT_BOOL_TAG) then
  begin
    w := PPromoWord(SlotPayloadAddr(srcVar));
    PXXPromoFromInt(dst, Int64(w^));
    Exit;
  end;
  if tag = VT_STRING_TAG then
  begin
    sp := PPromoStr(SlotPayloadAddr(srcVar));
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

function EitherPromoTagged(a, b: Pointer): Boolean;
begin
  EitherPromoTagged := (SlotTag(a) = VT_PROMO_INT64_TAG) or
                       (SlotTag(b) = VT_PROMO_INT64_TAG);
end;

function PXXPromoVarArithTry(dst, a, b: Pointer; op: Integer): Integer;
var pa, pb, pr: array[0..1] of NativeInt;   { three promo slots }
begin
  PXXPromoVarArithTry := 0;
  if not EitherPromoTagged(a, b) then Exit;
  PXXPromoInit(@pa); PXXPromoInit(@pb); PXXPromoInit(@pr);
  PXXPromoFromVariant(@pa, a);
  PXXPromoFromVariant(@pb, b);
  if op = 1 then PXXPromoAdd(@pr, @pa, @pb)
  else if op = 2 then PXXPromoSub(@pr, @pa, @pb)
  else if op = 3 then PXXPromoMul(@pr, @pa, @pb)
  else if op = 4 then PXXPromoDiv(@pr, @pa, @pb)
  else if op = 5 then PXXPromoMod(@pr, @pa, @pb)
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

end.
