{ pyeval — a real exec()/eval() for the Python subset uforth's PYTHON-bodied
  words are written in (feature-lib-pyexec, engine 1: the reflective
  tree-walker). Correctness reference; a JIT drops in later over the same
  grammar.

  MILESTONE 1 (this unit's initial scope): the 60 "pure-stack" corpus blocks —
  the ones that touch only push/pop/fpush/fpop and NO other vm.* member. That is
  exactly the set of PYTHON-bodied stdlib words (SWAP, OVER, ROT, /, MOD, bit
  ops, ternary min/max, …) that SEGFAULT today because pyexec is a stub.

  Grammar: statements separated by `;`/newline, plus COMPOUND blocks with Python
  indentation — if/elif/else, while (+break), for-in over range()/lists.
  Assignment + augassign, expression statements. Full expression grammar:
  ternary, boolean and/or/not, comparisons (incl. chains), |^& bit ops, <<>>
  shifts, +-*/ // %, unary -/+/~, calls, int/float/hex literals, names,
  True/False/None. Locals live in pyeval's own name/value arrays (LclSet) —
  TPyDict keyed by an AnsiString-boxed Variant is unreliable (see LclSet note).

  Still out of scope (M2/M3, or the bignum tail): attribute access (vm.here),
  subscripts (vm.memory[i]), method calls (vm.define_word), def, arbitrary-
  precision ints (`x & 0xFFFFFFFFFFFFFFFF` as unsigned), f-strings. Rejected with
  a clear error rather than misbehaving.

  Host bridge (M1 convention): a bare call `push(x)` / `pop()` / `fpush(x)` /
  `fpop()` dispatches through PyHostCall(g["vm"], name, args) — the trampoline
  reflects the method on vm's class (case-insensitively) and calls its code
  pointer through a typed proc-pointer cast whose shape matches (RetKind, Arity,
  float-ness). pxx's own codegen supplies each target's ABI; no hand asm. See
  test/test_pyeval_m1.pas for the standalone driver.

  IMPLEMENTATION NOTE — every node evaluator is a PROCEDURE returning through a
  `var res: Variant`, never a Variant-returning function. A Variant function whose
  Result is assigned from another Variant call corrupts the value under the
  current codegen (NRVO/hidden-dest aliasing — see
  project_variant_fn_return_forward_nrvo_corruption / a filed Track A ticket).
  var-out procedures sidestep it entirely. Helpers that BUILD a variant via
  pointer writes (Make*, pyadd_v, …) are safe as functions.

  NOT auto-used by NilPy yet: build + test standalone first so a parse error here
  cannot break every NilPy compile. Wiring exec()->EvalPyStmts is the last step
  of the arc (feature-lib-pyexec build plan step 5). }
unit pyeval;

interface

uses pylib, typinfo, promoint;

{ Run a statement sequence `src` with globals g / locals l (Python's explicit
  exec form; uforth always passes both). Assignments write locals; name reads
  try locals then globals. }
procedure EvalPyStmts(const src: AnsiString; g: TPyDict; l: TPyDict);

{ Reflect `name` on vm's class and call it with the variant args held in the
  TPyList `args` (args.at(0..count-1)); the boxed result comes back in `res`.
  Args ride in a TPyList rather than an `array of Variant`: an OPEN array of
  Variant silently miscompiles (indexing/Length reads only the first element —
  Track A ticket), and a class value is just a pointer that lowers cleanly.
  Public so the eventual bound-method path (M3) and tests can share it. }
procedure PyHostCall(vmobj: Pointer; const name: AnsiString;
                     args: TPyList; var res: Variant);

implementation

const
  { Ord(TTypeKind) codes (defs.inc); the enum itself is compiler-internal and not
    visible to a builtin unit, so the reflection blob's numeric kinds are used raw. }
  TK_DOUBLE  = 19;
  TK_VARIANT = 22;

  { Token kinds — plain integer consts (not an enum) so they are valid `case`
    labels; pxx rejects Ord(enumconst) as a case label. }
  PK_EOF    = 0;
  PK_NAME   = 1;
  PK_INT    = 2;
  PK_FLOAT  = 3;
  PK_STR    = 4;
  PK_OP     = 5;
  PK_NL     = 6;
  PK_INDENT = 7;
  PK_DEDENT = 8;
  PK_BIGINT = 9;   { integer/hex literal that overflows Int64; TkText = its text }

type
  PPyRec = ^TPyRec;
  TPyRec = record
    VType:   Int64;
    Payload: Int64;
  end;

  { pointer types for boxing/unboxing reflected fields by TTypeKind }
  PLongInt = ^LongInt;
  PByte    = ^Byte;
  PSingle  = ^Single;
  PVariant = ^Variant;

  { Trampoline thunk shapes (Self = leading Pointer). fpush/fpop carry a Double;
    everything else uses the all-Variant family below, which covers a
    NilPy-compiled host (every method param/return is a Variant) and the typed
    push/pop shapes alike — a Variant arg is passed by address, a Variant result
    via the hidden destination, both supplied by pxx's own codegen. }
  TFpushFn = procedure(self: Pointer; v: Double);
  TFpopFn  = function(self: Pointer): Double;

  { Variant-return, N Variant args (N = 0..5). }
  TVFn0 = function(self: Pointer): Variant;
  TVFn1 = function(self: Pointer; const a: Variant): Variant;
  TVFn2 = function(self: Pointer; const a, b: Variant): Variant;
  TVFn3 = function(self: Pointer; const a, b, c: Variant): Variant;
  TVFn4 = function(self: Pointer; const a, b, c, d: Variant): Variant;
  TVFn5 = function(self: Pointer; const a, b, c, d, e: Variant): Variant;
  { void (procedure), N Variant args. }
  TVPr0 = procedure(self: Pointer);
  TVPr1 = procedure(self: Pointer; const a: Variant);
  TVPr2 = procedure(self: Pointer; const a, b: Variant);
  TVPr3 = procedure(self: Pointer; const a, b, c: Variant);
  TVPr4 = procedure(self: Pointer; const a, b, c, d: Variant);
  TVPr5 = procedure(self: Pointer; const a, b, c, d, e: Variant);
  { AnsiString-return (e.g. next_token_strict), N Variant args (0..2). }
  TSFn0 = function(self: Pointer): AnsiString;
  TSFn1 = function(self: Pointer; const a: Variant): AnsiString;
  TSFn2 = function(self: Pointer; const a, b: Variant): AnsiString;
  { Int64-return, N Variant args (0..2). }
  TIFn0 = function(self: Pointer): Int64;
  TIFn1 = function(self: Pointer; const a: Variant): Int64;
  TIFn2 = function(self: Pointer; const a, b: Variant): Int64;

{ ---- variant makers (build via pointer writes -> safe as functions) ---- }

function MakeFloat(d: Double): Variant;
var r: PPyRec;
begin
  r := PPyRec(@Result);
  r^.VType := 3;               { VT_DOUBLE }
  PDouble(@r^.Payload)^ := d;
end;

function MakeStr(const s: AnsiString): Variant;
var r: PPyRec;
begin
  r := PPyRec(@Result);
  r^.VType := 6;               { VT_STRING }
  PAnsiString(@r^.Payload)^ := s;
end;

function MakeNone: Variant;
var r: PPyRec;
begin
  r := PPyRec(@Result);
  r^.VType := 0; r^.Payload := 0;
end;

{ box a class/object pointer as a VT_OBJECT variant }
function PyBoxObj(p: Pointer): Variant;
var r: PPyRec;
begin
  r := PPyRec(@Result);
  r^.VType := 7; r^.Payload := Int64(p);
end;

{ ---- promotable-int (bignum) integer layer --------------------------------

  Python ints are arbitrary precision. pyeval keeps them as Int64 while they fit
  and PROMOTES to promoint.pas's bignum on overflow — the value's variant simply
  changes shape (VT_INT64 <-> VT_PROMO_INT64). Bignum is a TRANSIENT intermediate
  (the double-cell MATH words compute a 128-bit product then mask/shift it back
  into two 64-bit cells before push); the Forth stack itself stays 64-bit. Only
  the ~13 MATH words ever trigger it, so the Int64 fast path is untouched.

  Overhead is a non-issue: the tree-walker re-parses per call and dominates; the
  promo path engages only on actual overflow. Bitwise `&`/`<<`/`>>` reduce to
  mod/mul/div by powers of two (the only forms the corpus uses); a general bignum
  bitwise-and with a non-power-of-2 mask is unsupported and errors clearly. }

const VT_PROMO = 8193;   { VT_PROMO_INT64_TAG — a bignum boxed in a variant }

function IsPromoV(const v: Variant): Boolean;
begin IsPromoV := PPyRec(@v)^.VType = VT_PROMO; end;

function IsIntishV(const v: Variant): Boolean;
var t: Int64;
begin
  t := PPyRec(@v)^.VType;
  IsIntishV := (t = 1) or (t = 2) or (t = 4) or (t = VT_PROMO);
end;

{ Int64 value of any int-ish variant, promo included (truncates a promo that
  exceeds Int64 — callers coerce only where a 64-bit cell is expected). }
function PyToI64(const v: Variant): Int64;
var s: array[0..1] of NativeInt;
begin
  if IsPromoV(v) then
  begin
    PXXPromoInit(@s); PXXPromoFromVariant(@s, @v);
    PyToI64 := PXXPromoToInt64(@s);
    PXXPromoClear(@s);
  end
  else PyToI64 := pyvar_to_int(v);
end;

{ NOTE — these return Variant via a `var res` out-param, NEVER as a function
  result. A Variant function whose Result is assigned from another Variant call
  corrupts the value under the current codegen (the NRVO forward bug — see the
  unit header); a var-out procedure sidesteps it. So `res := pyvar_of_int(x)` and
  `PromoOp(a,b,op,res)` are safe here, where `Result := pyvar_of_int(x)` would not
  be. }

{ a op b through promotable-int; the result auto-demotes to VT_INT64 when it
  fits (PXXPromoToVariant), so bignum never lingers once it is back in range.
  op: 1 add, 2 sub, 3 mul, 4 floordiv, 5 mod. }
procedure PromoOp(const a, b: Variant; op: Integer; var res: Variant);
var pa, pb, pr: array[0..1] of NativeInt;
begin
  PXXPromoInit(@pa); PXXPromoInit(@pb); PXXPromoInit(@pr);
  PXXPromoFromVariant(@pa, @a);
  PXXPromoFromVariant(@pb, @b);
  if op = 1 then PXXPromoAdd(@pr, @pa, @pb)
  else if op = 2 then PXXPromoSub(@pr, @pa, @pb)
  else if op = 3 then PXXPromoMul(@pr, @pa, @pb)
  else if op = 4 then PXXPromoDiv(@pr, @pa, @pb)
  else PXXPromoMod(@pr, @pa, @pb);
  PXXPromoToVariant(@res, @pr);
  PXXPromoClear(@pa); PXXPromoClear(@pb); PXXPromoClear(@pr);
end;

function PromoCmp(const a, b: Variant): Int64;
var pa, pb: array[0..1] of NativeInt;
begin
  PXXPromoInit(@pa); PXXPromoInit(@pb);
  PXXPromoFromVariant(@pa, @a); PXXPromoFromVariant(@pb, @b);
  PromoCmp := PXXPromoCmp(@pa, @pb);
  PXXPromoClear(@pa); PXXPromoClear(@pb);
end;

{ 2^k as a variant (Int64 while it fits, else promo). }
procedure Pow2V(k: Int64; var res: Variant);
var s, t: array[0..1] of NativeInt; i: Int64;
begin
  if (k >= 0) and (k < 62) then begin res := pyvar_of_int(Int64(1) shl k); Exit; end;
  PXXPromoInit(@s); PXXPromoInit(@t); PXXPromoFromInt(@s, 1);
  i := 1;
  while i <= k do begin PXXPromoMulInt(@t, @s, 2); PXXPromoCopy(@s, @t); i := i + 1; end;
  PXXPromoToVariant(@res, @s);
  PXXPromoClear(@s); PXXPromoClear(@t);
end;

procedure PyIAdd(const a, b: Variant; var res: Variant);
var ia, ib, s: Int64;
begin
  if IsPromoV(a) or IsPromoV(b) then begin PromoOp(a, b, 1, res); Exit; end;
  ia := pyvar_to_int(a); ib := pyvar_to_int(b); s := ia + ib;
  if ((ib > 0) and (s < ia)) or ((ib < 0) and (s > ia)) then PromoOp(a, b, 1, res)
  else res := pyvar_of_int(s);
end;

procedure PyISub(const a, b: Variant; var res: Variant);
var ia, ib, s: Int64;
begin
  if IsPromoV(a) or IsPromoV(b) then begin PromoOp(a, b, 2, res); Exit; end;
  ia := pyvar_to_int(a); ib := pyvar_to_int(b); s := ia - ib;
  if ((ib < 0) and (s < ia)) or ((ib > 0) and (s > ia)) then PromoOp(a, b, 2, res)
  else res := pyvar_of_int(s);
end;

procedure PyIMul(const a, b: Variant; var res: Variant);
var ia, ib, r: Int64;
begin
  if IsPromoV(a) or IsPromoV(b) then begin PromoOp(a, b, 3, res); Exit; end;
  ia := pyvar_to_int(a); ib := pyvar_to_int(b); r := ia * ib;
  if (ia <> 0) and (r div ia <> ib) then PromoOp(a, b, 3, res)
  else res := pyvar_of_int(r);
end;

procedure PyIFloorDiv(const a, b: Variant; var res: Variant);
begin
  if IsPromoV(a) or IsPromoV(b) then PromoOp(a, b, 4, res)
  else res := pyfloordiv_v(a, b);
end;

procedure PyIMod(const a, b: Variant; var res: Variant);
begin
  if IsPromoV(a) or IsPromoV(b) then PromoOp(a, b, 5, res)
  else res := pymod_v(a, b);
end;

{ `a << n` == a * 2^n; routed through PyIMul so overflow auto-promotes. }
procedure PyIShl(const a, nv: Variant; var res: Variant);
var p: Variant;
begin
  Pow2V(PyToI64(nv), p);
  PyIMul(a, p, res);
end;

{ `a >> n` == floor(a / 2^n) (Python arithmetic shift). Promo -> floordiv;
  Int64 -> the existing sign-propagating shift. }
procedure PyIShr(const a, nv: Variant; var res: Variant);
var p: Variant;
begin
  if IsPromoV(a) then begin Pow2V(PyToI64(nv), p); PromoOp(a, p, 4, res); end
  else res := pyshr_v(a, nv);
end;

{ Is v an all-ones mask 2^k - 1? returns k. Handles the corpus's 0xFFFF...FFFF
  (2^64-1, a promo) and any Int64-fitting all-ones mask. }
function MaskPow2(const v: Variant; var k: Int64): Boolean;
var iv, t: Int64; s: array[0..1] of NativeInt; txt: AnsiString;
begin
  MaskPow2 := False;
  if IsPromoV(v) then
  begin
    PXXPromoInit(@s); PXXPromoFromVariant(@s, @v); txt := PXXPromoToStr(@s);
    PXXPromoClear(@s);
    if txt = '18446744073709551615' then begin k := 64; MaskPow2 := True; end;
    Exit;
  end;
  iv := pyvar_to_int(v);
  if iv <= 0 then Exit;
  if (iv and (iv + 1)) <> 0 then Exit;   { not all-ones }
  k := 0; t := iv;
  while t > 0 do begin t := t shr 1; k := k + 1; end;
  MaskPow2 := True;
end;

{ `a & b`. Both Int64 -> plain and. One side promo -> the other must be an
  all-ones mask (2^k-1), giving `value mod 2^k` (== keep low k bits, Python's
  unsigned masking). A general bignum bitwise-and is not supported. }
procedure PyIBitAnd(const a, b: Variant; var res: Variant);
var k: Int64; p: Variant;
begin
  if (not IsPromoV(a)) and (not IsPromoV(b)) then
  begin res := pyvar_of_int(pyvar_to_int(a) and pyvar_to_int(b)); Exit; end;
  if MaskPow2(b, k) then begin Pow2V(k, p); PromoOp(a, p, 5, res); end
  else if MaskPow2(a, k) then begin Pow2V(k, p); PromoOp(b, p, 5, res); end
  else
  begin
    writeln('pyeval: bignum bitwise-and needs a power-of-2-minus-1 mask');
    Halt(1);
  end;
end;

function PyICmp(const a, b: Variant): Int64;
begin
  if IsPromoV(a) or IsPromoV(b) then PyICmp := PromoCmp(a, b)
  else PyICmp := pycmp_v(a, b);
end;

function PyIEq(const a, b: Variant): Boolean;
begin
  if IsPromoV(a) or IsPromoV(b) then PyIEq := PromoCmp(a, b) = 0
  else PyIEq := pyeq_v(a, b);
end;

{ Parse an integer/hex literal that overflowed Int64 into a promo variant. }
procedure PyBigLit(const text: AnsiString; var res: Variant);
var s, t: array[0..1] of NativeInt; i, n: Integer; c: Char; d, base: Int64; isHex: Boolean;
begin
  PXXPromoInit(@s); PXXPromoInit(@t);
  n := Length(text); i := 1; isHex := False;
  if (n >= 2) and (text[1] = '0') and ((text[2] = 'x') or (text[2] = 'X')) then
  begin isHex := True; i := 3; base := 16; end
  else base := 10;
  PXXPromoFromInt(@s, 0);
  while i <= n do
  begin
    c := text[i];
    if c <> '_' then
    begin
      if isHex then
      begin
        if (c >= '0') and (c <= '9') then d := Ord(c) - Ord('0')
        else if (c >= 'a') and (c <= 'f') then d := Ord(c) - Ord('a') + 10
        else d := Ord(c) - Ord('A') + 10;
      end
      else
        d := Ord(c) - Ord('0');
      { s := s*base + d, via a temp to avoid dst/src aliasing }
      PXXPromoMulInt(@t, @s, base);
      PXXPromoAddInt(@s, @t, d);
    end;
    i := i + 1;
  end;
  PXXPromoToVariant(@res, @s);
  PXXPromoClear(@s); PXXPromoClear(@t);
end;

{ ---- host-call trampoline ---- }

{ Case-insensitive method lookup over the class hierarchy. GetMethInfoByName is
  case-SENSITIVE, but Pascal identifiers are case-insensitive and the Python
  corpus spells calls lowercase (`pop`) against methods RTTI records as declared
  (`Pop`), so the bridge must fold case. }
function PyLowerStr(const s: AnsiString): AnsiString;
var i: Integer; c: Char;
begin
  Result := s;
  for i := 1 to Length(Result) do
  begin
    c := Result[i];
    if (c >= 'A') and (c <= 'Z') then Result[i] := Chr(Ord(c) + 32);
  end;
end;

function PyFindMethCI(cls: PClassRTTI; const name: AnsiString): PMethInfo;
var curr: PClassRTTI; meths: PMethInfo; i: Integer; lname: AnsiString;
begin
  PyFindMethCI := nil;
  lname := PyLowerStr(name);
  curr := cls;
  while curr <> nil do
  begin
    if curr^.MethCount > 0 then
    begin
      meths := curr^.MethsPtr;
      for i := 0 to Integer(curr^.MethCount) - 1 do
        if PyLowerStr(meths[i].NamePtr^) = lname then
        begin
          PyFindMethCI := @meths[i];
          Exit;
        end;
    end;
    curr := PClassRTTI(curr^.ParentRTTI);
  end;
end;

procedure PyHostCall(vmobj: Pointer; const name: AnsiString;
                     args: TPyList; var res: Variant);
var
  cls: PClassRTTI;
  mi:  PMethInfo;
  fpushfn: TFpushFn; fpopfn: TFpopFn;
  n, nargs: Integer;    { n = user args (Arity - 1) }
  a0, a1, a2, a3, a4: Variant;
  pk: PInt64;
  allVariant: Boolean;
  i: Integer;
  rk: Int64;
  code: Pointer;
  vf0: TVFn0; vf1: TVFn1; vf2: TVFn2; vf3: TVFn3; vf4: TVFn4; vf5: TVFn5;
  vp0: TVPr0; vp1: TVPr1; vp2: TVPr2; vp3: TVPr3; vp4: TVPr4; vp5: TVPr5;
  sf0: TSFn0; sf1: TSFn1; sf2: TSFn2;
  if0: TIFn0; if1: TIFn1; if2: TIFn2;
begin
  cls := GetInstanceRTTI(vmobj);
  if cls = nil then begin writeln('pyeval: no RTTI on vm for host call ', name); Halt(1); end;
  mi := PyFindMethCI(cls, name);
  if mi = nil then begin writeln('pyeval: vm has no method ', name); Halt(1); end;

  n := Integer(mi^.Arity) - 1;   { drop Self }
  nargs := args.count;
  pk := PInt64(mi^.ParamKinds);
  rk := mi^.RetKind;

  { --- Double param/return shapes (fpush/fpop): the one non-Variant family --- }
  if (rk = 0) and (n = 1) and (pk <> nil) and (pk[1] = TK_DOUBLE) then
  begin
    fpushfn := TFpushFn(mi^.Code);
    fpushfn(vmobj, pyvar_to_float(args.at(0)));
    res := MakeNone;
    Exit;
  end;
  if (rk = TK_DOUBLE) and (n = 0) then
  begin
    fpopfn := TFpopFn(mi^.Code);
    res := MakeFloat(fpopfn(vmobj));
    Exit;
  end;

  { --- general family: every param is a Variant (true for a NilPy-compiled host,
        and for the typed push/pop shapes). Pass args by value (pxx passes each
        `const Variant` by address); box the result per RetKind. --- }
  allVariant := True;
  if pk <> nil then
    for i := 1 to n do
      if pk[i] <> TK_VARIANT then allVariant := False;
  if not allVariant then
  begin
    writeln('pyeval: host method ', name, ' has a non-Variant, non-Double param shape');
    Halt(1);
  end;
  if nargs < n then
  begin writeln('pyeval: too few args to ', name, ' (need ', n, ', got ', nargs, ')'); Halt(1); end;

  if n >= 1 then a0 := args.at(0);
  if n >= 2 then a1 := args.at(1);
  if n >= 3 then a2 := args.at(2);
  if n >= 4 then a3 := args.at(3);
  if n >= 5 then a4 := args.at(4);
  { A host method (push/define_word/…) expects 64-bit cells: coerce any bignum
    arg back to Int64 so a promo never leaks onto the Forth stack. The double-cell
    words mask to 64 bits before push; this is the defensive belt. }
  if IsPromoV(a0) then a0 := pyvar_of_int(PyToI64(a0));
  if IsPromoV(a1) then a1 := pyvar_of_int(PyToI64(a1));
  if IsPromoV(a2) then a2 := pyvar_of_int(PyToI64(a2));
  if IsPromoV(a3) then a3 := pyvar_of_int(PyToI64(a3));
  if IsPromoV(a4) then a4 := pyvar_of_int(PyToI64(a4));
  code := mi^.Code;

  { Variant return }
  if rk = TK_VARIANT then
  begin
    case n of
      0: begin vf0 := TVFn0(code); res := vf0(vmobj); end;
      1: begin vf1 := TVFn1(code); res := vf1(vmobj, a0); end;
      2: begin vf2 := TVFn2(code); res := vf2(vmobj, a0, a1); end;
      3: begin vf3 := TVFn3(code); res := vf3(vmobj, a0, a1, a2); end;
      4: begin vf4 := TVFn4(code); res := vf4(vmobj, a0, a1, a2, a3); end;
      5: begin vf5 := TVFn5(code); res := vf5(vmobj, a0, a1, a2, a3, a4); end;
    else
      begin writeln('pyeval: host arity ', n, ' too large for ', name); Halt(1); end;
    end;
    Exit;
  end;

  { void return }
  if rk = 0 then
  begin
    case n of
      0: begin vp0 := TVPr0(code); vp0(vmobj); end;
      1: begin vp1 := TVPr1(code); vp1(vmobj, a0); end;
      2: begin vp2 := TVPr2(code); vp2(vmobj, a0, a1); end;
      3: begin vp3 := TVPr3(code); vp3(vmobj, a0, a1, a2); end;
      4: begin vp4 := TVPr4(code); vp4(vmobj, a0, a1, a2, a3); end;
      5: begin vp5 := TVPr5(code); vp5(vmobj, a0, a1, a2, a3, a4); end;
    else
      begin writeln('pyeval: host arity ', n, ' too large for ', name); Halt(1); end;
    end;
    res := MakeNone;
    Exit;
  end;

  { AnsiString return (next_token_strict, next_token, …) — arity 0..2 }
  if rk = 23 then
  begin
    case n of
      0: begin sf0 := TSFn0(code); res := MakeStr(sf0(vmobj)); end;
      1: begin sf1 := TSFn1(code); res := MakeStr(sf1(vmobj, a0)); end;
      2: begin sf2 := TSFn2(code); res := MakeStr(sf2(vmobj, a0, a1)); end;
    else
      begin writeln('pyeval: string-return arity ', n, ' unsupported for ', name); Halt(1); end;
    end;
    Exit;
  end;

  { Int64 / Integer / Boolean / Char return — arity 0..2 }
  if (rk = 13) or (rk = 1) or (rk = 2) or (rk = 3) then
  begin
    case n of
      0: begin if0 := TIFn0(code); res := pyvar_of_int(if0(vmobj)); end;
      1: begin if1 := TIFn1(code); res := pyvar_of_int(if1(vmobj, a0)); end;
      2: begin if2 := TIFn2(code); res := pyvar_of_int(if2(vmobj, a0, a1)); end;
    else
      begin writeln('pyeval: int-return arity ', n, ' unsupported for ', name); Halt(1); end;
    end;
    Exit;
  end;

  writeln('pyeval: unsupported host-call return kind ', rk, ' for ', name);
  Halt(1);
end;

{ ---- field (attribute) reflection: M2 ---- }

{ Read field `name` on `obj` and box it by its TTypeKind. Scalar kinds unbox to
  int/bool/float; a string field to a str variant; anything else (a class-valued
  field like memory/stack) is boxed as VT_OBJECT holding the field's stored
  pointer, so a following subscript / method call can reach it. }
procedure PyFieldGet(obj: Pointer; const name: AnsiString; var res: Variant);
var
  cls: PClassRTTI;
  kind: Int64;
  p: Pointer;
  r: PPyRec;
begin
  cls := GetInstanceRTTI(obj);
  if cls = nil then begin writeln('pyeval: no RTTI for attribute ', name); Halt(1); end;
  p := GetFieldPtr(obj, cls, name, kind);
  if p = nil then begin writeln('pyeval: object has no attribute ', name); Halt(1); end;
  r := PPyRec(@res);
  case kind of
    1: res := pyvar_of_int(PLongInt(p)^);        { tyInteger — 4-byte }
    2: res := pyvar_of_bool(PByte(p)^ <> 0);     { tyBoolean }
    3: res := pyvar_of_int(PByte(p)^);           { tyChar }
    13: res := pyvar_of_int(PInt64(p)^);         { tyInt64 }
    18: res := MakeFloat(PSingle(p)^);           { tySingle }
    19: res := MakeFloat(PDouble(p)^);           { tyDouble }
    22: res := PVariant(p)^;                      { tyVariant — copy the slot }
    23: res := MakeStr(PAnsiString(p)^);          { tyAnsiString }
  else
    { class / aggregate field: the slot holds an object pointer; expose it as a
      VT_OBJECT so subscripts and method calls can reach the container }
    r^.VType := 7; r^.Payload := PInt64(p)^;
  end;
end;

{ Write `val` into scalar/string field `name` on `obj`, coercing to the field's
  kind. Object-typed fields are not writable this way in M2 (would need lifetime
  handling); rejected. }
procedure PyFieldSet(obj: Pointer; const name: AnsiString; const val: Variant);
var
  cls: PClassRTTI;
  kind: Int64;
  p: Pointer;
begin
  cls := GetInstanceRTTI(obj);
  if cls = nil then begin writeln('pyeval: no RTTI for attribute ', name); Halt(1); end;
  p := GetFieldPtr(obj, cls, name, kind);
  if p = nil then begin writeln('pyeval: object has no attribute ', name); Halt(1); end;
  case kind of
    1: PLongInt(p)^ := pyvar_to_int(val);
    2: if pyvar_to_bool(val) then PByte(p)^ := 1 else PByte(p)^ := 0;
    3: PByte(p)^ := pyvar_to_int(val) and $FF;
    13: PInt64(p)^ := pyvar_to_int(val);
    18: PSingle(p)^ := pyvar_to_float(val);
    19: PDouble(p)^ := pyvar_to_float(val);
    22: PVariant(p)^ := val;
    23: PAnsiString(p)^ := pystr_of(val);
  else
    begin writeln('pyeval: cannot assign to object-typed attribute ', name); Halt(1); end;
  end;
end;

{ container[index] read. `container` is a VT_OBJECT variant; a list yields the
  element (Python negative indexing), a bytes object an int, a dict the value at
  the key. Slices are not handled here (M2b). }
procedure PySubscriptGet(const container: Variant; const index: Variant;
                         var res: Variant);
var o: TObject; li: TPyList; by: TPyBytes; di: TPyDict; i, n: Int64;
begin
  if PPyRec(@container)^.VType <> 7 then
  begin writeln('pyeval: cannot subscript a non-container'); Halt(1); end;
  o := TObject(Pointer(PPyRec(@container)^.Payload));
  if o is TPyList then
  begin
    li := TPyList(o); n := li.count; i := pyvar_to_int(index);
    if i < 0 then i := i + n;
    if (i < 0) or (i >= n) then begin writeln('pyeval: list index out of range'); Halt(1); end;
    res := li.at(i);
  end
  else if o is TPyBytes then
  begin
    by := TPyBytes(o); n := by.count; i := pyvar_to_int(index);
    if i < 0 then i := i + n;
    if (i < 0) or (i >= n) then begin writeln('pyeval: index out of range'); Halt(1); end;
    res := pyvar_of_int(by.at(i));
  end
  else if o is TPyDict then
  begin
    di := TPyDict(o);
    res := di.fetch(index);
  end
  else
    begin writeln('pyeval: unsupported subscript target'); Halt(1); end;
end;

{ container[index] = val }
procedure PySubscriptSet(const container: Variant; const index: Variant;
                         const val: Variant);
var o: TObject; li: TPyList; by: TPyBytes; di: TPyDict; i, n: Int64;
begin
  if PPyRec(@container)^.VType <> 7 then
  begin writeln('pyeval: cannot subscript-assign a non-container'); Halt(1); end;
  o := TObject(Pointer(PPyRec(@container)^.Payload));
  if o is TPyList then
  begin
    li := TPyList(o); n := li.count; i := pyvar_to_int(index);
    if i < 0 then i := i + n;
    if (i < 0) or (i >= n) then begin writeln('pyeval: list assignment index out of range'); Halt(1); end;
    li.put(i, val);
  end
  else if o is TPyBytes then
  begin
    by := TPyBytes(o); n := by.count; i := pyvar_to_int(index);
    if i < 0 then i := i + n;
    if (i < 0) or (i >= n) then begin writeln('pyeval: index out of range'); Halt(1); end;
    by.put(i, pyvar_to_int(val) and $FF);
  end
  else if o is TPyDict then
  begin
    di := TPyDict(o);
    di.store(index, val);
  end
  else
    begin writeln('pyeval: unsupported subscript-assign target'); Halt(1); end;
end;

{ container[lo:hi] = value. bytes take a variant RHS holding bytes; lists take a
  list RHS. Omitted bounds arrive as PY_SLICE_OMIT. }
procedure PySliceSet(const container: Variant; lo, hi: Int64; const val: Variant);
var o: TObject;
begin
  if PPyRec(@container)^.VType <> 7 then
  begin writeln('pyeval: cannot slice-assign a non-container'); Halt(1); end;
  o := TObject(Pointer(PPyRec(@container)^.Payload));
  if o is TPyBytes then
    pybytes_setslice_v(TPyBytes(o), lo, hi, val)
  else if o is TPyList then
    pylist_setslice(TPyList(o), lo, hi, TPyList(pyvarobj(val)))
  else
    begin writeln('pyeval: unsupported slice-assign target'); Halt(1); end;
end;

{ del container[index] }
procedure PyDelSubscript(const container: Variant; const index: Variant);
var o: TObject; li: TPyList; di: TPyDict; i, nn: Int64;
begin
  if PPyRec(@container)^.VType <> 7 then
  begin writeln('pyeval: cannot del a subscript of a non-container'); Halt(1); end;
  o := TObject(Pointer(PPyRec(@container)^.Payload));
  if o is TPyList then
  begin
    li := TPyList(o); nn := li.count; i := pyvar_to_int(index);
    if i < 0 then i := i + nn;
    if (i < 0) or (i >= nn) then begin writeln('pyeval: del index out of range'); Halt(1); end;
    li.pop_at(i);
  end
  else if o is TPyDict then
    TPyDict(o).remove(index)
  else
    begin writeln('pyeval: unsupported del target'); Halt(1); end;
end;

{ ---- tokenizer ---- }

var
  { token arrays (module-global; EvalPyStmts is not reentrant across a single
    source, which is fine — uforth runs one block body at a time) }
  TkKind:  array of Integer;
  TkText:  array of AnsiString;
  TkInt:   array of Int64;
  TkFloat: array of Double;
  TkN:     Integer;

  Src:  AnsiString;
  SLen: Integer;
  Pos:  Integer;      { 1-based cursor into Src during tokenize }
  Cur:  Integer;      { current token index during eval }

  EnvG: TPyDict;   { host-provided globals (read-only here); holds "vm" etc. }

  { Local scope kept as parallel arrays rather than a TPyDict: TPyDict keyed by a
    Variant boxed from an AnsiString is unreliable (store/indexof box the string
    inconsistently, and a heap key's bytes go stale — see the boxing landmine in
    pylib). Owned AnsiString names compared with `=` are exact and stable. }
  LclNames: array of AnsiString;
  LclVals:  array of Variant;
  LclN:     Integer;

  { Control-flow state. `Executing` gates side effects: while walking a
    not-taken branch (if/elif/else, or a while/for that skips its body once to
    advance past it) the grammar is still consumed but calls don't dispatch,
    stores don't write, and undefined names resolve to None instead of erroring.
    `BreakFlag` unwinds the innermost loop. }
  Executing: Boolean;
  BreakFlag: Boolean;
  { set by ExecStatement when the statement was a compound block (if/while/for):
    such a statement self-terminates at its DEDENT, so no `;`/NL separator follows. }
  StmtWasCompound: Boolean;

  { nested `def` functions: name -> (body token position, comma-joined params).
    A call saves/restores the local scope + cursor for a fresh function frame. }
  FnName:    array of AnsiString;
  FnBodyPos: array of Integer;
  FnParams:  array of AnsiString;
  FnN:       Integer;
  ReturnFlag:  Boolean;
  ReturnValue: Variant;

procedure AddTok(kind: Integer; const text: AnsiString; iv: Int64; fv: Double);
begin
  if TkN >= Length(TkKind) then
  begin
    if Length(TkKind) = 0 then SetLength(TkKind, 64)
    else SetLength(TkKind, Length(TkKind) * 2);
    SetLength(TkText, Length(TkKind));
    SetLength(TkInt, Length(TkKind));
    SetLength(TkFloat, Length(TkKind));
  end;
  TkKind[TkN] := kind;
  TkText[TkN] := text;
  TkInt[TkN] := iv;
  TkFloat[TkN] := fv;
  TkN := TkN + 1;
end;

function IsDigit(c: Char): Boolean;
begin
  IsDigit := (c >= '0') and (c <= '9');
end;

function IsHexDigit(c: Char): Boolean;
begin
  IsHexDigit := IsDigit(c) or ((c >= 'a') and (c <= 'f')) or
                ((c >= 'A') and (c <= 'F'));
end;

function IsIdentStart(c: Char): Boolean;
begin
  IsIdentStart := ((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z'))
                  or (c = '_');
end;

function IsIdentChar(c: Char): Boolean;
begin
  IsIdentChar := IsIdentStart(c) or IsDigit(c);
end;

function HexVal(c: Char): Int64;
begin
  if IsDigit(c) then HexVal := Ord(c) - Ord('0')
  else if (c >= 'a') and (c <= 'f') then HexVal := Ord(c) - Ord('a') + 10
  else HexVal := Ord(c) - Ord('A') + 10;
end;

procedure TokError(const msg: AnsiString);
begin
  writeln('pyeval tokenizer: ', msg);
  Halt(1);
end;

function PyEscQuote(const s: AnsiString): AnsiString;
var i: Integer;
begin
  Result := '';
  for i := 1 to Length(s) do
  begin
    if s[i] = '''' then Result := Result + '''''' else Result := Result + s[i];
  end;
end;

{ Source-level f-string desugar: rewrite `f'lit{expr:spec}lit'` into
  `('lit' + __fmt(expr, 'spec') + 'lit')` before tokenizing, so the normal
  expression grammar evaluates the holes. Normal string literals are copied
  verbatim (never rewritten). Nested brackets inside a hole are respected;
  `{{`/`}}` are literal braces; a `!r`/`!s`/`!a` conversion is parsed and
  ignored. Keeps f-strings out of the tokenizer/evaluator entirely. }
function PreprocessFStrings(const src: AnsiString): AnsiString;
var
  i, n, depth: Integer;
  c, q, ch: Char;
  outp, seg, hole, spec: AnsiString;
  prevIdent, needPlus: Boolean;
begin
  outp := ''; i := 1; n := Length(src); prevIdent := False;
  while i <= n do
  begin
    c := src[i];
    { normal string literal — copy verbatim }
    if (c = '''') or (c = '"') then
    begin
      q := c; outp := outp + c; i := i + 1;
      while (i <= n) and (src[i] <> q) do
      begin
        if (src[i] = '\') and (i < n) then begin outp := outp + src[i]; i := i + 1; end;
        outp := outp + src[i]; i := i + 1;
      end;
      if i <= n then begin outp := outp + src[i]; i := i + 1; end;
      prevIdent := False;
      continue;
    end;
    { f-string prefix (f/F not part of a longer identifier, followed by a quote) }
    if ((c = 'f') or (c = 'F')) and (not prevIdent) and (i < n)
       and ((src[i+1] = '''') or (src[i+1] = '"')) then
    begin
      q := src[i+1]; i := i + 2;
      outp := outp + '(';
      seg := ''; needPlus := False;
      while (i <= n) and (src[i] <> q) do
      begin
        ch := src[i];
        if (ch = '{') and (i < n) and (src[i+1] = '{') then begin seg := seg + '{'; i := i + 2; end
        else if (ch = '}') and (i < n) and (src[i+1] = '}') then begin seg := seg + '}'; i := i + 2; end
        else if ch = '{' then
        begin
          if seg <> '' then
          begin
            if needPlus then outp := outp + ' + ';
            outp := outp + '''' + PyEscQuote(seg) + '''';
            needPlus := True; seg := '';
          end;
          i := i + 1; hole := ''; depth := 0;
          while (i <= n) and not ((depth = 0) and
                 ((src[i] = '}') or (src[i] = ':') or (src[i] = '!'))) do
          begin
            if (src[i] = '(') or (src[i] = '[') or (src[i] = '{') then depth := depth + 1
            else if (src[i] = ')') or (src[i] = ']') or (src[i] = '}') then depth := depth - 1;
            hole := hole + src[i]; i := i + 1;
          end;
          spec := '';
          if (i <= n) and (src[i] = '!') then
          begin i := i + 1; if i <= n then i := i + 1; end;   { !r/!s/!a — ignored }
          if (i <= n) and (src[i] = ':') then
          begin
            i := i + 1;
            while (i <= n) and (src[i] <> '}') do begin spec := spec + src[i]; i := i + 1; end;
          end;
          if (i <= n) and (src[i] = '}') then i := i + 1;
          if needPlus then outp := outp + ' + ';
          outp := outp + '__fmt(' + hole + ', ''' + PyEscQuote(spec) + ''')';
          needPlus := True;
        end
        else begin seg := seg + ch; i := i + 1; end;
      end;
      if i <= n then i := i + 1;   { closing quote }
      if seg <> '' then
      begin
        if needPlus then outp := outp + ' + ';
        outp := outp + '''' + PyEscQuote(seg) + '''';
        needPlus := True;
      end;
      if not needPlus then outp := outp + '''''';   { empty f-string }
      outp := outp + ')';
      prevIdent := False;
    end
    else
    begin
      outp := outp + c;
      prevIdent := IsIdentChar(c);
      i := i + 1;
    end;
  end;
  Result := outp;
end;

procedure Tokenize(const s: AnsiString);
var
  c, c2: Char;
  start: Integer;
  ident, op, slit: AnsiString;
  iv, dg: Int64;
  fv, scale: Double;
  isFloat, ovf: Boolean;
  atLineStart: Boolean;
  col, sp: Integer;
  indent: array of Integer;   { indentation stack; indent[0] = 0 }
  nInd: Integer;
begin
  Src := s; SLen := Length(s); Pos := 1; TkN := 0;
  SetLength(indent, 64); indent[0] := 0; nInd := 1;
  atLineStart := True;
  while Pos <= SLen do
  begin
    { Python offside rule: at the start of each logical (non-blank, non-comment)
      line, compare leading-whitespace width to the indent stack and emit
      INDENT / DEDENT tokens. Blank and comment-only lines never change indent. }
    if atLineStart then
    begin
      sp := Pos; col := 0;
      while (sp <= SLen) and ((Src[sp] = ' ') or (Src[sp] = #9)) do
      begin col := col + 1; sp := sp + 1; end;
      { blank line or comment-only line: consume through its newline, no change }
      if (sp > SLen) or (Src[sp] = #10) or (Src[sp] = #13) or (Src[sp] = '#') then
      begin
        while (Pos <= SLen) and (Src[Pos] <> #10) do Pos := Pos + 1;
        if Pos <= SLen then Pos := Pos + 1;   { the newline }
        continue;   { still atLineStart }
      end;
      Pos := sp;   { skip the leading whitespace }
      if col > indent[nInd-1] then
      begin
        if nInd >= Length(indent) then SetLength(indent, Length(indent) * 2);
        indent[nInd] := col; nInd := nInd + 1;
        AddTok(PK_INDENT, '', 0, 0);
      end
      else
        while (nInd > 1) and (col < indent[nInd-1]) do
        begin nInd := nInd - 1; AddTok(PK_DEDENT, '', 0, 0); end;
      atLineStart := False;
    end;
    c := Src[Pos];
    if c = #10 then
    begin
      AddTok(PK_NL, '', 0, 0);
      Pos := Pos + 1;
      atLineStart := True;
      continue;
    end;
    { whitespace (not newline) }
    if (c = ' ') or (c = #9) or (c = #13) then
    begin
      Pos := Pos + 1;
      continue;
    end;
    { comment (to end of line; the newline is handled at the top of the loop) }
    if c = '#' then
    begin
      while (Pos <= SLen) and (Src[Pos] <> #10) do Pos := Pos + 1;
      continue;
    end;
    { number }
    if IsDigit(c) then
    begin
      { hex — overflow past Int64 becomes a promo big-literal token }
      if (c = '0') and (Pos + 1 <= SLen) and
         ((Src[Pos+1] = 'x') or (Src[Pos+1] = 'X')) then
      begin
        start := Pos;
        Pos := Pos + 2;
        iv := 0; ovf := False;
        if (Pos > SLen) or (not IsHexDigit(Src[Pos])) then
          TokError('malformed hex literal');
        while (Pos <= SLen) and (IsHexDigit(Src[Pos]) or (Src[Pos] = '_')) do
        begin
          if Src[Pos] <> '_' then
          begin
            dg := HexVal(Src[Pos]);
            if iv > (High(Int64) - dg) div 16 then ovf := True;
            if not ovf then iv := iv * 16 + dg;
          end;
          Pos := Pos + 1;
        end;
        if ovf then AddTok(PK_BIGINT, Copy(Src, start, Pos - start), 0, 0)
        else AddTok(PK_INT, '', iv, 0);
        continue;
      end;
      { decimal int or float }
      start := Pos;
      iv := 0; isFloat := False; ovf := False;
      while (Pos <= SLen) and (IsDigit(Src[Pos]) or (Src[Pos] = '_')) do
      begin
        if Src[Pos] <> '_' then
        begin
          dg := Ord(Src[Pos]) - Ord('0');
          if iv > (High(Int64) - dg) div 10 then ovf := True;
          if not ovf then iv := iv * 10 + dg;
        end;
        Pos := Pos + 1;
      end;
      fv := iv;
      if (Pos <= SLen) and (Src[Pos] = '.') then
      begin
        isFloat := True;
        Pos := Pos + 1;
        scale := 0.1;
        while (Pos <= SLen) and IsDigit(Src[Pos]) do
        begin
          fv := fv + (Ord(Src[Pos]) - Ord('0')) * scale;
          scale := scale * 0.1;
          Pos := Pos + 1;
        end;
      end;
      if (Pos <= SLen) and ((Src[Pos] = 'e') or (Src[Pos] = 'E')) then
        TokError('float exponent literals not supported in M1');
      if isFloat then AddTok(PK_FLOAT, '', 0, fv)
      else if ovf then AddTok(PK_BIGINT, Copy(Src, start, Pos - start), 0, 0)
      else AddTok(PK_INT, '', iv, 0);
      continue;
    end;
    { identifier / keyword }
    if IsIdentStart(c) then
    begin
      { reject f-strings up front (M1-rest) }
      if ((c = 'f') or (c = 'F')) and (Pos + 1 <= SLen) and
         ((Src[Pos+1] = '''') or (Src[Pos+1] = '"')) then
        TokError('f-strings not supported in M1');
      start := Pos;
      while (Pos <= SLen) and IsIdentChar(Src[Pos]) do Pos := Pos + 1;
      ident := Copy(Src, start, Pos - start);
      AddTok(PK_NAME, ident, 0, 0);
      continue;
    end;
    { string literal }
    if (c = '''') or (c = '"') then
    begin
      c2 := c;
      Pos := Pos + 1;
      slit := '';
      while (Pos <= SLen) and (Src[Pos] <> c2) do
      begin
        if (Src[Pos] = '\') and (Pos + 1 <= SLen) then
        begin
          Pos := Pos + 1;
          case Src[Pos] of
            'n': slit := slit + #10;
            't': slit := slit + #9;
            'r': slit := slit + #13;
            '\': slit := slit + '\';
            '''': slit := slit + '''';
            '"': slit := slit + '"';
            '0': slit := slit + #0;
          else
            slit := slit + Src[Pos];
          end;
        end
        else
          slit := slit + Src[Pos];
        Pos := Pos + 1;
      end;
      if Pos > SLen then TokError('unterminated string');
      Pos := Pos + 1;   { closing quote }
      AddTok(PK_STR, slit, 0, 0);
      continue;
    end;
    { operators / punctuation — longest match first }
    c2 := #0;
    if Pos + 1 <= SLen then c2 := Src[Pos+1];
    { 3-char: //= <<= >>= }
    if ((c = '/') and (c2 = '/') and (Pos+2 <= SLen) and (Src[Pos+2] = '=')) then
    begin AddTok(PK_OP, '//=', 0, 0); Pos := Pos + 3; continue; end;
    if ((c = '<') and (c2 = '<') and (Pos+2 <= SLen) and (Src[Pos+2] = '=')) then
    begin AddTok(PK_OP, '<<=', 0, 0); Pos := Pos + 3; continue; end;
    if ((c = '>') and (c2 = '>') and (Pos+2 <= SLen) and (Src[Pos+2] = '=')) then
    begin AddTok(PK_OP, '>>=', 0, 0); Pos := Pos + 3; continue; end;
    { 2-char }
    op := '';
    if (c = '/') and (c2 = '/') then op := '//'
    else if (c = '*') and (c2 = '*') then op := '**'
    else if (c = '<') and (c2 = '<') then op := '<<'
    else if (c = '>') and (c2 = '>') then op := '>>'
    else if (c = '<') and (c2 = '=') then op := '<='
    else if (c = '>') and (c2 = '=') then op := '>='
    else if (c = '=') and (c2 = '=') then op := '=='
    else if (c = '!') and (c2 = '=') then op := '!='
    else if (c = '+') and (c2 = '=') then op := '+='
    else if (c = '-') and (c2 = '=') then op := '-='
    else if (c = '*') and (c2 = '=') then op := '*='
    else if (c = '%') and (c2 = '=') then op := '%='
    else if (c = '&') and (c2 = '=') then op := '&='
    else if (c = '|') and (c2 = '=') then op := '|='
    else if (c = '^') and (c2 = '=') then op := '^=';
    if op <> '' then
    begin AddTok(PK_OP, op, 0, 0); Pos := Pos + 2; continue; end;
    { 1-char }
    case c of
      '+', '-', '*', '/', '%', '&', '|', '^', '~',
      '<', '>', '=', '(', ')', '[', ']', ',', ':', '.', ';', '{', '}':
        begin
          AddTok(PK_OP, Copy(Src, Pos, 1), 0, 0);
          Pos := Pos + 1;
        end;
    else
      TokError('unexpected character ' + Copy(Src, Pos, 1));
    end;
  end;
  { close any open blocks at end of input }
  if (TkN > 0) and (TkKind[TkN-1] <> PK_NL) then AddTok(PK_NL, '', 0, 0);
  while nInd > 1 do begin nInd := nInd - 1; AddTok(PK_DEDENT, '', 0, 0); end;
  AddTok(PK_EOF, '', 0, 0);
end;

{ ---- evaluator (recursive descent; every node returns via a var-out param) ---- }

procedure EvalError(const msg: AnsiString);
begin
  writeln('pyeval: ', msg);
  Halt(1);
end;

function CurKind: Integer;
begin
  CurKind := TkKind[Cur];
end;

function CurText: AnsiString;
begin
  CurText := TkText[Cur];
end;

function IsOp(const s: AnsiString): Boolean;
begin
  IsOp := (TkKind[Cur] = PK_OP) and (TkText[Cur] = s);
end;

function IsKw(const s: AnsiString): Boolean;
begin
  IsKw := (TkKind[Cur] = PK_NAME) and (TkText[Cur] = s);
end;

procedure Advance;
begin
  if TkKind[Cur] <> PK_EOF then Cur := Cur + 1;
end;

procedure ExpectOp(const s: AnsiString);
begin
  if not IsOp(s) then EvalError('expected ' + s);
  Advance;
end;

function LclFind(const name: AnsiString): Integer;
var i: Integer;
begin
  LclFind := -1;
  for i := 0 to LclN - 1 do
    if LclNames[i] = name then begin LclFind := i; Exit; end;
end;

procedure LclSet(const name: AnsiString; const v: Variant);
var i: Integer;
begin
  i := LclFind(name);
  if i >= 0 then begin LclVals[i] := v; Exit; end;
  if LclN >= Length(LclNames) then
  begin
    if Length(LclNames) = 0 then SetLength(LclNames, 16)
    else SetLength(LclNames, Length(LclNames) * 2);
    SetLength(LclVals, Length(LclNames));
  end;
  LclNames[LclN] := name;
  LclVals[LclN] := v;
  LclN := LclN + 1;
end;

{ Python type objects (int/str/…) as first-class values, needed by isinstance's
  second argument. Encoded in a pyeval-internal variant tag 100 whose payload is
  the VT_* the type maps to (int->2, float->3, bool->4, str->6, bytes/list/dict
  use their container discriminators 7/107/207). -1 if `name` is not a type. }
const PY_TYPETAG = 100;
function PyTypeCode(const name: AnsiString): Int64;
begin
  if (name = 'int') then PyTypeCode := 2
  else if (name = 'float') then PyTypeCode := 3
  else if (name = 'bool') then PyTypeCode := 4
  else if (name = 'str') then PyTypeCode := 6
  else if (name = 'bytes') or (name = 'bytearray') then PyTypeCode := 7
  else if (name = 'list') then PyTypeCode := 107
  else if (name = 'dict') then PyTypeCode := 207
  else PyTypeCode := -1;
end;

procedure LclDelete(const name: AnsiString);
var i, j: Integer;
begin
  i := LclFind(name);
  if i < 0 then Exit;
  for j := i to LclN - 2 do
  begin LclNames[j] := LclNames[j+1]; LclVals[j] := LclVals[j+1]; end;
  LclN := LclN - 1;
end;

function FnFind(const name: AnsiString): Integer;
var i: Integer;
begin
  FnFind := -1;
  for i := 0 to FnN - 1 do
    if FnName[i] = name then begin FnFind := i; Exit; end;
end;

procedure FnRegister(const name: AnsiString; bodyPos: Integer; const params: AnsiString);
var i: Integer;
begin
  i := FnFind(name);
  if i >= 0 then
  begin FnBodyPos[i] := bodyPos; FnParams[i] := params; Exit; end;
  if FnN >= Length(FnName) then
  begin
    if Length(FnName) = 0 then SetLength(FnName, 8)
    else SetLength(FnName, Length(FnName) * 2);
    SetLength(FnBodyPos, Length(FnName));
    SetLength(FnParams, Length(FnName));
  end;
  FnName[FnN] := name; FnBodyPos[FnN] := bodyPos; FnParams[FnN] := params;
  FnN := FnN + 1;
end;

procedure EnvGet(const name: AnsiString; var res: Variant);
var i: Integer; tc: Int64;
begin
  i := LclFind(name);
  if i >= 0 then
    res := LclVals[i]
  else if (EnvG <> nil) and (EnvG.indexof(name) >= 0) then
    res := EnvG.fetch(name)
  else
  begin
    tc := PyTypeCode(name);
    if tc >= 0 then
    begin PPyRec(@res)^.VType := PY_TYPETAG; PPyRec(@res)^.Payload := tc; end
    else if not Executing then
      res := MakeNone      { walking a skipped branch — names may be undefined }
    else
    begin
      EvalError('name not defined: ' + name);
      res := MakeNone;
    end;
  end;
end;

procedure ParseExpr(var res: Variant); forward;   { conditional/ternary — lowest }
procedure ParseCall(const callee: AnsiString; var res: Variant); forward;
procedure ParseMethodCall(const recv: Variant; const mname: AnsiString;
                          var res: Variant); forward;
procedure CallUserFn(fnIdx: Integer; args: TPyList; var res: Variant); forward;

{ atom, then a postfix chain of `.attr` (field read) and `[index]` (subscript). }
procedure ParsePrimary(var res: Variant);
var
  name, fld: AnsiString;
  recv, idx, elem, hiTmp: Variant;
  li: TPyList;
  dd: TPyDict;
  loVal, hiVal: Int64;
  haveLo: Boolean;
begin
  { ---- atom ---- }
  if TkKind[Cur] = PK_INT then
  begin res := pyvar_of_int(TkInt[Cur]); Advance; end
  else if TkKind[Cur] = PK_BIGINT then
  begin PyBigLit(TkText[Cur], res); Advance; end
  else if TkKind[Cur] = PK_FLOAT then
  begin res := MakeFloat(TkFloat[Cur]); Advance; end
  else if TkKind[Cur] = PK_STR then
  begin res := MakeStr(TkText[Cur]); Advance; end
  else if IsOp('[') then
  begin
    { list literal }
    Advance;
    li := TPyList.Create;
    while not IsOp(']') do
    begin
      ParseExpr(elem);
      li.append(elem);
      if IsOp(',') then Advance
      else if not IsOp(']') then EvalError('expected , or ] in list literal');
    end;
    ExpectOp(']');
    PPyRec(@res)^.VType := 7; PPyRec(@res)^.Payload := Int64(Pointer(li));
  end
  else if IsOp('{') then
  begin
    { dict literal { k: v, ... } or set literal { v, ... } (empty {} -> dict).
      A set is backed by a TPyList, per pylib's set model. }
    Advance;
    if IsOp('}') then
    begin
      Advance;
      dd := TPyDict.Create;
      PPyRec(@res)^.VType := 7; PPyRec(@res)^.Payload := Int64(Pointer(dd));
    end
    else
    begin
      ParseExpr(elem);
      if IsOp(':') then
      begin
        { dict }
        Advance; ParseExpr(idx);   { idx = value }
        dd := TPyDict.Create; dd.store(elem, idx);
        while IsOp(',') do
        begin
          Advance;
          if IsOp('}') then Break;
          ParseExpr(elem); ExpectOp(':'); ParseExpr(idx);
          dd.store(elem, idx);
        end;
        ExpectOp('}');
        PPyRec(@res)^.VType := 7; PPyRec(@res)^.Payload := Int64(Pointer(dd));
      end
      else
      begin
        { set -> TPyList }
        li := TPyList.Create; li.append(elem);
        while IsOp(',') do
        begin
          Advance;
          if IsOp('}') then Break;
          ParseExpr(elem); li.append(elem);
        end;
        ExpectOp('}');
        PPyRec(@res)^.VType := 7; PPyRec(@res)^.Payload := Int64(Pointer(li));
      end;
    end;
  end
  else if TkKind[Cur] = PK_NAME then
  begin
    name := TkText[Cur];
    if name = 'True' then begin Advance; res := pyvar_of_bool(True); end
    else if name = 'False' then begin Advance; res := pyvar_of_bool(False); end
    else if name = 'None' then begin Advance; res := MakeNone; end
    else
    begin
      Advance;
      if IsOp('(') then ParseCall(name, res)
      else EnvGet(name, res);
    end;
  end
  else if IsOp('(') then
  begin Advance; ParseExpr(res); ExpectOp(')'); end
  else
  begin EvalError('unexpected token in expression: "' + TkText[Cur] + '"'); res := MakeNone; end;

  { ---- postfix chain ---- }
  while IsOp('.') or IsOp('[') do
  begin
    if IsOp('.') then
    begin
      Advance;
      if TkKind[Cur] <> PK_NAME then EvalError('expected attribute name after "."');
      fld := TkText[Cur]; Advance;
      recv := res;
      if IsOp('(') then
        ParseMethodCall(recv, fld, res)
      else if Executing then PyFieldGet(pyvarobj(recv), fld, res)
      else res := MakeNone;
    end
    else
    begin
      { subscript or slice }
      Advance;   { [ }
      recv := res;
      haveLo := False;
      if not IsOp(':') then begin ParseExpr(idx); haveLo := True; end;
      if IsOp(':') then
      begin
        { slice [lo:hi(:step)] — bounds int-coerced, omitted -> PY_SLICE_OMIT }
        loVal := PY_SLICE_OMIT; hiVal := PY_SLICE_OMIT;
        if haveLo then loVal := pyvar_to_int(idx);
        Advance;
        if (not IsOp(']')) and (not IsOp(':')) then
        begin ParseExpr(hiTmp); hiVal := pyvar_to_int(hiTmp); end;
        if IsOp(':') then   { step — parsed and ignored (M2) }
        begin Advance; if not IsOp(']') then ParseExpr(hiTmp); end;
        ExpectOp(']');
        if Executing then res := pyvar_slice(recv, loVal, hiVal) else res := MakeNone;
      end
      else
      begin
        { plain index — keep idx as a Variant so dict string keys work }
        if not haveLo then EvalError('empty subscript');
        ExpectOp(']');
        if Executing then PySubscriptGet(recv, idx, res) else res := MakeNone;
      end;
    end;
  end;
end;

procedure ParseUnary(var res: Variant);
var t: Variant;
begin
  if IsOp('-') then
  begin
    Advance; ParseUnary(t);
    { -a: promo-aware (0 - a) for a bignum, else the plain neg }
    if IsPromoV(t) then PromoOp(pyvar_of_int(0), t, 2, res) else res := pyneg_v(t);
    Exit;
  end;
  if IsOp('+') then
  begin Advance; ParseUnary(res); Exit; end;
  if IsOp('~') then
  begin Advance; ParseUnary(t); res := pyinvert_v(t); Exit; end;
  ParsePrimary(res);
end;

procedure ParseMul(var res: Variant);
var a, b, t: Variant;
begin
  ParseUnary(a);
  while IsOp('*') or IsOp('/') or IsOp('//') or IsOp('%') do
  begin
    if IsOp('*') then
    begin Advance; ParseUnary(b);
      if IsIntishV(a) and IsIntishV(b) then begin PyIMul(a, b, t); a := t; end else a := pymul_v(a, b); end
    else if IsOp('//') then
    begin Advance; ParseUnary(b);
      { skipping a not-taken/def-skip branch: names read as None(0), so a real
        divide would be 0 div 0 -> runtime error 200. No side effect matters
        here, so just yield None. }
      if not Executing then a := MakeNone
      else if IsIntishV(a) and IsIntishV(b) then begin PyIFloorDiv(a, b, t); a := t; end else a := pyfloordiv_v(a, b); end
    else if IsOp('%') then
    begin Advance; ParseUnary(b);
      if not Executing then a := MakeNone
      else if IsIntishV(a) and IsIntishV(b) then begin PyIMod(a, b, t); a := t; end else a := pymod_v(a, b); end
    else begin Advance; ParseUnary(b);
      if not Executing then a := MakeNone
      else a := MakeFloat(pyvar_to_float(a) / pyvar_to_float(b)); end;
  end;
  res := a;
end;

procedure ParseAdd(var res: Variant);
var a, b, t: Variant;
begin
  ParseMul(a);
  while IsOp('+') or IsOp('-') do
  begin
    if IsOp('+') then
    begin Advance; ParseMul(b);
      if IsIntishV(a) and IsIntishV(b) then begin PyIAdd(a, b, t); a := t; end else a := pyadd_v(a, b); end
    else
    begin Advance; ParseMul(b);
      if IsIntishV(a) and IsIntishV(b) then begin PyISub(a, b, t); a := t; end else a := pysub_v(a, b); end;
  end;
  res := a;
end;

procedure ParseShift(var res: Variant);
var a, b, t: Variant;
begin
  ParseAdd(a);
  while IsOp('<<') or IsOp('>>') do
  begin
    if IsOp('<<') then begin Advance; ParseAdd(b); PyIShl(a, b, t); a := t; end
    else begin Advance; ParseAdd(b); PyIShr(a, b, t); a := t; end;
  end;
  res := a;
end;

procedure ParseBitAnd(var res: Variant);
var a, b, t: Variant;
begin
  ParseShift(a);
  while IsOp('&') do
  begin Advance; ParseShift(b);
    if IsIntishV(a) and IsIntishV(b) then begin PyIBitAnd(a, b, t); a := t; end else a := pybitand_v(a, b); end;
  res := a;
end;

procedure ParseBitXor(var res: Variant);
var a, b: Variant;
begin
  ParseBitAnd(a);
  while IsOp('^') do begin Advance; ParseBitAnd(b); a := pybitxor_v(a, b); end;
  res := a;
end;

procedure ParseBitOr(var res: Variant);
var a, b: Variant;
begin
  ParseBitXor(a);
  while IsOp('|') do begin Advance; ParseBitXor(b); a := pybitor_v(a, b); end;
  res := a;
end;

function PyCmpAhead: Boolean;
begin
  PyCmpAhead := IsOp('<') or IsOp('>') or IsOp('<=') or IsOp('>=')
    or IsOp('==') or IsOp('!=') or IsKw('is') or IsKw('in')
    or (IsKw('not') and (TkKind[Cur+1] = PK_NAME) and (TkText[Cur+1] = 'in'));
end;

procedure ParseCompare(var res: Variant);
var a, b: Variant; c: Int64; ok: Boolean;
begin
  ParseBitOr(a);
  if not PyCmpAhead then begin res := a; Exit; end;
  { Python chains: a < b < c == (a<b) and (b<c). `is`/`is not` are identity
    (value-equality here — sufficient for the `x is None` idiom); `in`/`not in`
    are membership. }
  ok := True;
  while PyCmpAhead do
  begin
    if IsOp('==') then begin Advance; ParseBitOr(b); ok := ok and PyIEq(a, b); end
    else if IsOp('!=') then begin Advance; ParseBitOr(b); ok := ok and (not PyIEq(a, b)); end
    else if IsOp('<') then begin Advance; ParseBitOr(b); c := PyICmp(a, b); ok := ok and (c < 0); end
    else if IsOp('>') then begin Advance; ParseBitOr(b); c := PyICmp(a, b); ok := ok and (c > 0); end
    else if IsOp('<=') then begin Advance; ParseBitOr(b); c := PyICmp(a, b); ok := ok and (c <= 0); end
    else if IsOp('>=') then begin Advance; ParseBitOr(b); c := PyICmp(a, b); ok := ok and (c >= 0); end
    else if IsKw('is') then
    begin
      Advance;
      if IsKw('not') then begin Advance; ParseBitOr(b); ok := ok and (not PyIEq(a, b)); end
      else begin ParseBitOr(b); ok := ok and PyIEq(a, b); end;
    end
    else if IsKw('in') then
    begin Advance; ParseBitOr(b); ok := ok and pyvar_contains(b, a); end
    else { not in }
    begin Advance; Advance; ParseBitOr(b); ok := ok and (not pyvar_contains(b, a)); end;
    a := b;
  end;
  res := pyvar_of_bool(ok);
end;

procedure ParseNot(var res: Variant);
var t: Variant;
begin
  if IsKw('not') then
  begin Advance; ParseNot(t); res := pyvar_of_bool(not pyvar_to_bool(t)); Exit; end;
  ParseCompare(res);
end;

procedure ParseAnd(var res: Variant);
var a, b: Variant;
begin
  ParseNot(a);
  while IsKw('and') do
  begin
    Advance; ParseNot(b);
    { value semantics: a and b -> b if a truthy else a }
    if pyvar_to_bool(a) then a := b;
  end;
  res := a;
end;

procedure ParseOr(var res: Variant);
var a, b: Variant;
begin
  ParseAnd(a);
  while IsKw('or') do
  begin
    Advance; ParseAnd(b);
    if not pyvar_to_bool(a) then a := b;
  end;
  res := a;
end;

{ ternary — lowest precedence. `A if C else B`. M1 evaluates all three eagerly
  and selects (the corpus branches are side-effect-free); a documented deviation
  mirroring pyor_v/pyand_v. }
procedure ParseExpr(var res: Variant);
var a, b, cond: Variant;
begin
  ParseOr(a);
  if IsKw('if') then
  begin
    Advance;
    ParseOr(cond);
    if not IsKw('else') then EvalError('ternary missing else');
    Advance;
    ParseExpr(b);
    if pyvar_to_bool(cond) then res := a else res := b;
    Exit;
  end;
  res := a;
end;

{ ---- builtins ---- }

{ isinstance(value, typeobj). typeobj is a PY_TYPETAG sentinel (payload = the
  type code from PyTypeCode). Maps the value's runtime tag/class to a code and
  compares. }
function PyIsInstance(const v: Variant; const t: Variant): Boolean;
var vt, want: Int64; o: TObject;
begin
  PyIsInstance := False;
  if PPyRec(@t)^.VType <> PY_TYPETAG then Exit;   { second arg was not a type }
  want := PPyRec(@t)^.Payload;
  vt := PPyRec(@v)^.VType;
  if (want = 2) then PyIsInstance := (vt = 1) or (vt = 2)                 { int }
  else if (want = 3) then PyIsInstance := (vt = 3)                        { float }
  else if (want = 4) then PyIsInstance := (vt = 4)                        { bool }
  else if (want = 6) then PyIsInstance := (vt = 6) or (vt = 5)            { str/char }
  else if vt = 7 then
  begin
    o := TObject(Pointer(PPyRec(@v)^.Payload));
    if want = 7 then PyIsInstance := o is TPyBytes
    else if want = 107 then PyIsInstance := o is TPyList
    else if want = 207 then PyIsInstance := o is TPyDict;
  end;
end;

{ hasattr(obj, name): a field or method of that name exists on obj's class.
  Also covers the dynamic-attribute store uforth uses (vm._trans_ptr lazy init). }
function PyHasAttr(const obj: Variant; const name: AnsiString): Boolean;
var cls: PClassRTTI; kind: Int64; p: Pointer;
begin
  PyHasAttr := False;
  if PPyRec(@obj)^.VType <> 7 then Exit;
  cls := GetInstanceRTTI(Pointer(PPyRec(@obj)^.Payload));
  if cls = nil then Exit;
  p := GetFieldPtr(Pointer(PPyRec(@obj)^.Payload), cls, name, kind);
  if p <> nil then begin PyHasAttr := True; Exit; end;
  if PyFindMethCI(cls, name) <> nil then begin PyHasAttr := True; Exit; end;
  PyHasAttr := pydynattr_has(Pointer(PPyRec(@obj)^.Payload), name);
end;

{ range(...) materialised into a TPyList, boxed as a VT_OBJECT variant. }
function pyrange_list(args: TPyList): Variant;
var lo, hi, step, i: Int64; n: Integer; r: TPyList; ro: PPyRec;
begin
  n := args.count;
  if n = 1 then begin lo := 0; hi := pyvar_to_int(args.at(0)); step := 1; end
  else if n = 2 then
    begin lo := pyvar_to_int(args.at(0)); hi := pyvar_to_int(args.at(1)); step := 1; end
  else
    begin lo := pyvar_to_int(args.at(0)); hi := pyvar_to_int(args.at(1));
          step := pyvar_to_int(args.at(2)); end;
  r := TPyList.Create;
  if step > 0 then
  begin i := lo; while i < hi do begin r.append(pyvar_of_int(i)); i := i + step; end; end
  else if step < 0 then
  begin i := lo; while i > hi do begin r.append(pyvar_of_int(i)); i := i + step; end; end;
  ro := PPyRec(@Result); ro^.VType := 7; ro^.Payload := Int64(Pointer(r));
end;

procedure CallBuiltin(const name: AnsiString; args: TPyList;
                      const endKw, sepKw: AnsiString;
                      haveEnd, haveSep: Boolean; var res: Variant);
var i, nargs: Integer; s, sep, endc: AnsiString; cand, e: Variant;
begin
  nargs := args.count;
  if name = 'int' then
  begin
    if nargs <> 1 then EvalError('int() expects 1 arg in M1');
    cand := args.at(0);
    { int() of a bignum is identity (stays arbitrary precision); else pyint_v }
    if IsPromoV(cand) then res := cand else res := pyint_v(cand);
    Exit;
  end;
  if name = 'float' then
  begin
    if nargs <> 1 then EvalError('float() expects 1 arg');
    res := MakeFloat(pyvar_to_float(args.at(0))); Exit;
  end;
  if name = 'abs' then
  begin
    if nargs <> 1 then EvalError('abs() expects 1 arg');
    cand := args.at(0);
    if IsPromoV(cand) then
    begin
      if PromoCmp(cand, pyvar_of_int(0)) < 0 then PromoOp(pyvar_of_int(0), cand, 2, res)
      else res := cand;
    end
    else res := pyabs_v(cand);
    Exit;
  end;
  if name = 'bool' then
  begin
    if nargs <> 1 then EvalError('bool() expects 1 arg');
    res := pyvar_of_bool(pyvar_to_bool(args.at(0))); Exit;
  end;
  if name = 'len' then
  begin
    if nargs <> 1 then EvalError('len() expects 1 arg');
    res := pyvar_of_int(pylen_v(args.at(0))); Exit;
  end;
  if name = 'ord' then
  begin
    if nargs <> 1 then EvalError('ord() expects 1 arg');
    res := pyvar_of_int(pyord_v(args.at(0))); Exit;
  end;
  if name = 'chr' then
  begin
    if nargs <> 1 then EvalError('chr() expects 1 arg');
    res := MakeStr(pystr_ofchar(Chr(pyvar_to_int(args.at(0)) and $FF))); Exit;
  end;
  if name = 'str' then
  begin
    if nargs <> 1 then EvalError('str() expects 1 arg');
    res := MakeStr(pystr_of(args.at(0))); Exit;
  end;
  if name = 'hex' then
  begin
    if nargs <> 1 then EvalError('hex() expects 1 arg');
    res := MakeStr(hex(pyvar_to_int(args.at(0)))); Exit;
  end;
  if name = '__fmt' then
  begin
    { f-string hole: __fmt(value, 'spec') — see PreprocessFStrings }
    res := MakeStr(pyformat_of(args.at(0), pystr_of(args.at(1)))); Exit;
  end;
  if name = 'isinstance' then
  begin
    res := pyvar_of_bool(PyIsInstance(args.at(0), args.at(1))); Exit;
  end;
  if name = 'repr' then
  begin
    if nargs <> 1 then EvalError('repr() expects 1 arg');
    res := MakeStr(pyvar_repr(args.at(0))); Exit;
  end;
  if (name = 'bytearray') or (name = 'bytes') then
  begin
    { bytearray() / bytearray(n) / bytes(existing) }
    if nargs = 0 then
      res := PyBoxObj(Pointer(bytearray))
    else
    begin
      cand := args.at(0);
      if PPyRec(@cand)^.VType = 7 then
        res := PyBoxObj(Pointer(bytes(TPyBytes(pyvarobj(cand)))))
      else
        res := PyBoxObj(Pointer(bytearray(pyvar_to_int(cand))));
    end;
    Exit;
  end;
  if name = 'hasattr' then
  begin
    res := pyvar_of_bool(PyHasAttr(args.at(0), pystr_of(args.at(1)))); Exit;
  end;
  if name = 'min' then
  begin
    if nargs < 1 then EvalError('min() needs args');
    cand := args.at(0);
    for i := 1 to nargs - 1 do
    begin e := args.at(i); if pycmp_v(e, cand) < 0 then cand := e; end;
    res := cand; Exit;
  end;
  if name = 'max' then
  begin
    if nargs < 1 then EvalError('max() needs args');
    cand := args.at(0);
    for i := 1 to nargs - 1 do
    begin e := args.at(i); if pycmp_v(e, cand) > 0 then cand := e; end;
    res := cand; Exit;
  end;
  if name = 'range' then
  begin
    { range(stop) | range(start,stop) | range(start,stop,step) -> a materialised
      TPyList of ints (correctness-first; a lazy iterator can come later). }
    res := pyrange_list(args);
    Exit;
  end;
  if name = 'print' then
  begin
    s := '';
    if haveSep then sep := sepKw else sep := ' ';
    if haveEnd then endc := endKw else endc := #10;
    for i := 0 to nargs - 1 do
    begin
      if i > 0 then s := s + sep;
      s := s + pystr_of(args.at(i));
    end;
    write(s); write(endc);
    res := MakeNone; Exit;
  end;
  EvalError('unknown call: ' + name + '()');
  res := MakeNone;
end;

function IsHostName(const name: AnsiString): Boolean;
begin
  IsHostName := (name = 'push') or (name = 'pop')
             or (name = 'fpush') or (name = 'fpop');
end;

procedure ParseCall(const callee: AnsiString; var res: Variant);
var
  args: TPyList;
  v, vmv: Variant;
  kwname, endKw, sepKw: AnsiString;
  haveEnd, haveSep: Boolean;
  vmobj: Pointer;
begin
  ExpectOp('(');
  args := TPyList.Create;
  haveEnd := False; haveSep := False;
  endKw := ''; sepKw := '';
  while not IsOp(')') do
  begin
    { keyword arg?  NAME '=' expr  (but not '==') }
    if (TkKind[Cur] = PK_NAME) and (TkKind[Cur+1] = PK_OP)
       and (TkText[Cur+1] = '=') then
    begin
      kwname := TkText[Cur];
      Advance; Advance;   { name '=' }
      ParseExpr(v);
      if kwname = 'end' then begin endKw := pystr_of(v); haveEnd := True; end
      else if kwname = 'sep' then begin sepKw := pystr_of(v); haveSep := True; end
      else if kwname = 'flush' then { ignore }
      else EvalError('unsupported keyword arg: ' + kwname);
    end
    else
    begin
      ParseExpr(v);
      args.append(v);
    end;
    if IsOp(',') then Advance
    else if not IsOp(')') then EvalError('expected , or ) in call');
  end;
  ExpectOp(')');

  { skipped branch: consume the call but do not dispatch (no side effects) }
  if not Executing then begin res := MakeNone; Exit; end;

  { user-defined nested function takes precedence (Python scoping) }
  if FnFind(callee) >= 0 then
  begin CallUserFn(FnFind(callee), args, res); Exit; end;

  if IsHostName(callee) then
  begin
    if (EnvG = nil) or (EnvG.indexof('vm') < 0) then
      EvalError('host call ' + callee + ' but no "vm" in globals');
    vmv := EnvG.fetch('vm');
    vmobj := pyvarobj(vmv);
    PyHostCall(vmobj, callee, args, res);
    Exit;
  end;
  CallBuiltin(callee, args, endKw, sepKw, haveEnd, haveSep, res);
end;

{ `( expr, ... )` into `args`; a `signed=<bool>` keyword arg (to_bytes/from_bytes)
  is captured into signedKw, other keyword args are ignored (e.g. byteorder is
  positional and consumed as an ordinary arg). }
procedure ParseArgs(args: TPyList; var signedKw: Boolean);
var v: Variant; kw: AnsiString;
begin
  signedKw := False;
  ExpectOp('(');
  while not IsOp(')') do
  begin
    if (TkKind[Cur] = PK_NAME) and (TkKind[Cur+1] = PK_OP) and (TkText[Cur+1] = '=') then
    begin
      kw := TkText[Cur]; Advance; Advance; ParseExpr(v);
      if kw = 'signed' then signedKw := pyvar_to_bool(v);
    end
    else
    begin
      ParseExpr(v);
      args.append(v);
    end;
    if IsOp(',') then Advance
    else if not IsOp(')') then EvalError('expected , or ) in method call');
  end;
  ExpectOp(')');
end;

{ recv.mname(args). Dispatches str / list / bytes / dict methods to pylib; any
  other VT_OBJECT receiver is treated as a reflected HOST object and routed
  through the trampoline (PyHostCall). Method coverage is the corpus subset;
  unsupported names error clearly. }
procedure ParseMethodCall(const recv: Variant; const mname: AnsiString;
                          var res: Variant);
var
  args: TPyList;
  o: TObject; li: TPyList; by: TPyBytes;
  s: AnsiString; b2: TPyBytes;
  signedKw: Boolean;
  rvt: Int64;
begin
  args := TPyList.Create;
  ParseArgs(args, signedKw);
  if not Executing then begin res := MakeNone; Exit; end;
  rvt := PPyRec(@recv)^.VType;

  { int.to_bytes(length, byteorder, *, signed=…) -> bytes }
  if (rvt = 1) or (rvt = 2) or (rvt = 4) then
  begin
    if mname = 'to_bytes' then
    begin
      by := pyint_to_bytes(pyvar_to_int(recv), pyvar_to_int(args.at(0)), signedKw);
      PPyRec(@res)^.VType := 7; PPyRec(@res)^.Payload := Int64(Pointer(by));
      Exit;
    end;
    EvalError('int method not supported: ' + mname);
  end;

  { int.from_bytes(bytes, byteorder, *, signed=…) — a static method on the int
    type object (a PY_TYPETAG sentinel). }
  if rvt = PY_TYPETAG then
  begin
    if (PPyRec(@recv)^.Payload = 2) and (mname = 'from_bytes') then
    begin
      res := pyvar_of_int(pyint_from_bytes(TPyBytes(pyvarobj(args.at(0))), signedKw));
      Exit;
    end;
    EvalError('type method not supported: ' + mname);
  end;

  { string methods }
  if rvt = 6 then
  begin
    s := PAnsiString(@PPyRec(@recv)^.Payload)^;
    if mname = 'upper' then res := MakeStr(pystr_upper(s))
    else if mname = 'lower' then res := MakeStr(pystr_lower(s))
    else if mname = 'strip' then
    begin
      if args.count = 0 then res := MakeStr(pystr_strip(s))
      else res := MakeStr(pystr_strip_chars(s, pystr_of(args.at(0))));
    end
    else if mname = 'join' then
      res := MakeStr(pystr_join(s, TPyList(pyvarobj(args.at(0)))))
    else if mname = 'startswith' then
      res := pyvar_of_bool(pystr_startswith(s, pystr_of(args.at(0))))
    else if mname = 'endswith' then
      res := pyvar_of_bool(pystr_endswith(s, pystr_of(args.at(0))))
    else if mname = 'find' then
      res := pyvar_of_int(pystr_find(s, pystr_of(args.at(0))))
    else if mname = 'encode' then
    begin
      b2 := pystr_encode(s);
      PPyRec(@res)^.VType := 7; PPyRec(@res)^.Payload := Int64(Pointer(b2));
    end
    else
      EvalError('str method not supported: ' + mname);
    Exit;
  end;

  if PPyRec(@recv)^.VType = 7 then
  begin
    o := TObject(Pointer(PPyRec(@recv)^.Payload));
    if o is TPyList then
    begin
      li := TPyList(o);
      if mname = 'append' then begin li.append(args.at(0)); res := MakeNone; end
      else if mname = 'insert' then
        begin li.insert(pyvar_to_int(args.at(0)), args.at(1)); res := MakeNone; end
      else if mname = 'pop' then
      begin
        if args.count = 0 then res := li.pop
        else res := li.pop(pyvar_to_int(args.at(0)));
      end
      else if mname = 'clear' then begin li.clear; res := MakeNone; end
      else if mname = 'extend' then
        begin li.extend(TPyList(pyvarobj(args.at(0)))); res := MakeNone; end
      else
        EvalError('list method not supported: ' + mname);
      Exit;
    end;
    if o is TPyBytes then
    begin
      by := TPyBytes(o);
      if mname = 'append' then begin by.append(pyvar_to_int(args.at(0))); res := MakeNone; end
      else if mname = 'decode' then
      begin
        if args.count = 0 then res := MakeStr(by.decode('utf-8'))
        else res := MakeStr(by.decode(pystr_of(args.at(0))));
      end
      else if mname = 'extend' then
        begin by.extend(TPyBytes(pyvarobj(args.at(0)))); res := MakeNone; end
      else
        EvalError('bytes method not supported: ' + mname);
      Exit;
    end;
    { otherwise: a reflected host object (vm) — dispatch through the trampoline }
    PyHostCall(Pointer(PPyRec(@recv)^.Payload), mname, args, res);
    Exit;
  end;

  EvalError('cannot call method ' + mname + ' on this value');
end;

{ ---- statements ---- }

procedure SkipSeparators;
begin
  while IsOp(';') or (CurKind = PK_NL) do Advance;
end;

procedure ExecStatement; forward;

{ Execute (or, if `doEval` is False, merely skip) the suite that follows a `:`.
  A suite is either INLINE — simple statements to end of line — or a BLOCK:
  NEWLINE INDENT statement+ DEDENT. Skipping walks the same grammar with
  Executing off so the token cursor lands past the suite either way. }
procedure ExecSuite(doEval: Boolean);
var saved: Boolean;
begin
  saved := Executing;
  Executing := saved and doEval;
  if CurKind = PK_NL then
  begin
    { block form }
    while CurKind = PK_NL do Advance;
    if CurKind <> PK_INDENT then
    begin Executing := saved; EvalError('expected an indented block'); end;
    Advance;   { INDENT }
    while (CurKind <> PK_DEDENT) and (CurKind <> PK_EOF) do
    begin
      if BreakFlag or ReturnFlag then
      begin
        { unwinding a loop or function: fast-skip the rest with eval off }
        Executing := False;
      end;
      ExecStatement;
      SkipSeparators;
    end;
    if CurKind = PK_DEDENT then Advance;
  end
  else
  begin
    { inline form: simple statements until newline / dedent / eof }
    while (CurKind <> PK_NL) and (CurKind <> PK_DEDENT) and (CurKind <> PK_EOF) do
    begin
      if BreakFlag or ReturnFlag then Executing := False;
      ExecStatement;
      while IsOp(';') do Advance;
    end;
  end;
  Executing := saved;
end;

procedure ExecIf;
var cond: Variant; done: Boolean;
begin
  Advance;   { if }
  ParseExpr(cond);
  ExpectOp(':');
  done := Executing and pyvar_to_bool(cond);
  ExecSuite(done);
  while IsKw('elif') do
  begin
    Advance;
    ParseExpr(cond);
    ExpectOp(':');
    if (not done) and Executing and pyvar_to_bool(cond) then
    begin ExecSuite(True); done := True; end
    else
      ExecSuite(False);
  end;
  if IsKw('else') then
  begin
    Advance; ExpectOp(':');
    ExecSuite(Executing and (not done));
  end;
end;

procedure ExecWhile;
var cond: Variant; condPos: Integer; guard: Int64;
begin
  Advance;   { while }
  condPos := Cur;
  guard := 0;
  while True do
  begin
    Cur := condPos;
    ParseExpr(cond);
    ExpectOp(':');
    if Executing and pyvar_to_bool(cond) then
    begin
      ExecSuite(True);
      if ReturnFlag then Break;   { unwind to the function frame }
      if BreakFlag then begin BreakFlag := False; Break; end;
      guard := guard + 1;
      if guard > 100000000 then EvalError('while: iteration guard tripped');
    end
    else
    begin
      ExecSuite(False);   { skip body once to advance past it }
      Break;
    end;
  end;
end;

procedure ExecFor;
var
  varName: AnsiString;
  iter: Variant;
  lst: TPyList;
  bodyPos, i, n: Integer;
begin
  Advance;   { for }
  if CurKind <> PK_NAME then EvalError('for: expected a loop variable');
  varName := TkText[Cur]; Advance;
  if not IsKw('in') then EvalError('for: expected "in"');
  Advance;
  ParseExpr(iter);
  ExpectOp(':');
  bodyPos := Cur;
  if not Executing then begin ExecSuite(False); Exit; end;
  if PPyRec(@iter)^.VType <> 7 then
    EvalError('for: M1/M2 iterate over a list/range only');
  lst := TPyList(Pointer(PPyRec(@iter)^.Payload));
  n := lst.count;
  if n = 0 then begin ExecSuite(False); Exit; end;
  for i := 0 to n - 1 do
  begin
    LclSet(varName, lst.at(i));
    Cur := bodyPos;
    ExecSuite(True);
    if ReturnFlag then Exit;   { unwind to the function frame }
    if BreakFlag then begin BreakFlag := False; Exit; end;
  end;
  { after the last real iteration Cur is already past the suite }
end;

function IsAssignOp(const s: AnsiString): Boolean;
begin
  IsAssignOp := (s = '=') or (s = '+=') or (s = '-=') or (s = '*=')
    or (s = '//=') or (s = '%=') or (s = '&=') or (s = '|=') or (s = '^=')
    or (s = '<<=') or (s = '>>=');
end;

{ Token-only scan: does a NAME (.attr | [expr])* chain from Cur end at an assign
  op? Decides assignment vs expression statement without evaluating anything. }
function AssignmentAhead: Boolean;
var p, depth: Integer;
begin
  AssignmentAhead := False;
  p := Cur;
  if TkKind[p] <> PK_NAME then Exit;
  p := p + 1;
  while True do
  begin
    if (TkKind[p] = PK_OP) and (TkText[p] = '.') then
    begin
      p := p + 1;
      if TkKind[p] <> PK_NAME then Exit;
      p := p + 1;
    end
    else if (TkKind[p] = PK_OP) and (TkText[p] = '[') then
    begin
      depth := 1; p := p + 1;
      while (depth > 0) and (TkKind[p] <> PK_EOF) do
      begin
        if (TkKind[p] = PK_OP) and (TkText[p] = '[') then depth := depth + 1
        else if (TkKind[p] = PK_OP) and (TkText[p] = ']') then depth := depth - 1;
        p := p + 1;
      end;
    end
    else
      Break;
  end;
  AssignmentAhead := (TkKind[p] = PK_OP) and IsAssignOp(TkText[p]);
end;

{ Assignment to a local, an attribute (obj.field), or a subscript
  (container[index]) — plain and augmented. The receiver chain is walked and
  intermediate steps read normally; only the final step is the lvalue. }
procedure DoAssignment;
var
  base, aug, fld: AnsiString;
  recv, idx, rhs, cur, v, tcont, tindex, hiTmp: Variant;
  tkind: Integer;   { 0 local, 1 attribute, 2 subscript, 3 slice }
  tname: AnsiString;
  tobj: Pointer;
  tlo, thi: Int64;
  isSlice, haveIdx: Boolean;
begin
  base := TkText[Cur]; Advance;
  tkind := 0; tname := base; tobj := nil;
  if IsOp('.') or IsOp('[') then
  begin
    EnvGet(base, recv);
    while True do
    begin
      if IsOp('.') then
      begin
        Advance;
        fld := TkText[Cur]; Advance;
        if (TkKind[Cur] = PK_OP) and IsAssignOp(TkText[Cur]) then
        begin tkind := 1; tobj := pyvarobj(recv); tname := fld; Break; end;
        if Executing then PyFieldGet(pyvarobj(recv), fld, recv) else recv := MakeNone;
      end
      else if IsOp('[') then
      begin
        Advance;
        isSlice := False; haveIdx := False; tlo := PY_SLICE_OMIT; thi := PY_SLICE_OMIT;
        if not IsOp(':') then begin ParseExpr(idx); haveIdx := True; end;
        if IsOp(':') then
        begin
          isSlice := True;
          if haveIdx then tlo := pyvar_to_int(idx);
          Advance;
          if (not IsOp(']')) and (not IsOp(':')) then begin ParseExpr(hiTmp); thi := pyvar_to_int(hiTmp); end;
          if IsOp(':') then begin Advance; if not IsOp(']') then ParseExpr(hiTmp); end;
        end;
        ExpectOp(']');
        if (TkKind[Cur] = PK_OP) and IsAssignOp(TkText[Cur]) then
        begin
          if isSlice then begin tkind := 3; tcont := recv; end
          else begin tkind := 2; tcont := recv; tindex := idx; end;
          Break;
        end;
        if Executing then
        begin
          if isSlice then recv := pyvar_slice(recv, tlo, thi)
          else PySubscriptGet(recv, idx, recv);
        end
        else recv := MakeNone;
      end
      else
        EvalError('invalid assignment target');
    end;
  end;

  aug := TkText[Cur]; Advance;
  ParseExpr(rhs);
  if not Executing then Exit;

  if aug <> '=' then
  begin
    if tkind = 3 then EvalError('augmented slice assignment not supported');
  end;

  if aug = '=' then v := rhs
  else
  begin
    if tkind = 0 then EnvGet(tname, cur)
    else if tkind = 1 then PyFieldGet(tobj, tname, cur)
    else PySubscriptGet(tcont, tindex, cur);
    { promo-aware for the int-ish operators (the double-cell re-sign step
      `lo -= 0x10000000000000000` is an augassign with a bignum RHS) }
    if aug = '+=' then
    begin if IsIntishV(cur) and IsIntishV(rhs) then PyIAdd(cur, rhs, v) else v := pyadd_v(cur, rhs); end
    else if aug = '-=' then
    begin if IsIntishV(cur) and IsIntishV(rhs) then PyISub(cur, rhs, v) else v := pysub_v(cur, rhs); end
    else if aug = '*=' then
    begin if IsIntishV(cur) and IsIntishV(rhs) then PyIMul(cur, rhs, v) else v := pymul_v(cur, rhs); end
    else if aug = '//=' then
    begin if IsIntishV(cur) and IsIntishV(rhs) then PyIFloorDiv(cur, rhs, v) else v := pyfloordiv_v(cur, rhs); end
    else if aug = '%=' then
    begin if IsIntishV(cur) and IsIntishV(rhs) then PyIMod(cur, rhs, v) else v := pymod_v(cur, rhs); end
    else if aug = '&=' then
    begin if IsIntishV(cur) and IsIntishV(rhs) then PyIBitAnd(cur, rhs, v) else v := pybitand_v(cur, rhs); end
    else if aug = '|=' then v := pybitor_v(cur, rhs)
    else if aug = '^=' then v := pybitxor_v(cur, rhs)
    else if aug = '<<=' then PyIShl(cur, rhs, v)
    else PyIShr(cur, rhs, v);
  end;

  if tkind = 0 then LclSet(tname, v)
  else if tkind = 1 then PyFieldSet(tobj, tname, v)
  else if tkind = 2 then PySubscriptSet(tcont, tindex, v)
  else PySliceSet(tcont, tlo, thi, v);
end;

{ del NAME | del container[index] (chains supported; final step deleted). }
procedure ExecDel;
var base, fld: AnsiString; recv, idx: Variant;
begin
  Advance;   { del }
  if CurKind <> PK_NAME then EvalError('del: expected a target');
  base := TkText[Cur]; Advance;
  if not (IsOp('.') or IsOp('[')) then
  begin
    if Executing then LclDelete(base);
    Exit;
  end;
  EnvGet(base, recv);
  while True do
  begin
    if IsOp('.') then
    begin
      Advance; fld := TkText[Cur]; Advance;
      if Executing then PyFieldGet(pyvarobj(recv), fld, recv) else recv := MakeNone;
    end
    else if IsOp('[') then
    begin
      Advance; ParseExpr(idx); ExpectOp(']');
      if not (IsOp('.') or IsOp('[')) then
      begin
        if Executing then PyDelSubscript(recv, idx);
        Exit;
      end;
      if Executing then PySubscriptGet(recv, idx, recv) else recv := MakeNone;
    end
    else
      EvalError('del: invalid target');
  end;
end;

{ raise ExcName('message') | raise ExcName | raise. The exception class name is
  consumed as a bare identifier (it is not a defined value); the first call
  argument, if any, is the message. Propagated by halting with a diagnostic —
  catchable try/except is a later milestone. }
procedure ExecRaise;
var excName, msg: AnsiString; args: TPyList; v: Variant; sk: Boolean;
begin
  Advance;   { raise }
  msg := '';
  if CurKind = PK_NAME then
  begin
    excName := TkText[Cur]; Advance;
    if IsOp('(') then
    begin
      args := TPyList.Create;
      ParseArgs(args, sk);
      if args.count > 0 then begin v := args.at(0); msg := pystr_of(v); end;
    end;
  end
  else
    excName := 'Exception';
  if Executing then
  begin
    writeln('pyeval: ', excName, ': ', msg);
    Halt(1);
  end;
end;

{ def name(p1, p2, ...): SUITE — registers the function and skips its body. }
procedure ExecDef;
var name, params: AnsiString; bodyPos: Integer;
begin
  Advance;   { def }
  if CurKind <> PK_NAME then EvalError('def: expected a name');
  name := TkText[Cur]; Advance;
  ExpectOp('(');
  params := '';
  while not IsOp(')') do
  begin
    if CurKind <> PK_NAME then EvalError('def: expected a parameter name');
    if params <> '' then params := params + ',';
    params := params + TkText[Cur]; Advance;
    if IsOp(',') then Advance
    else if not IsOp(')') then EvalError('def: expected , or ) in params');
  end;
  ExpectOp(')');
  ExpectOp(':');
  bodyPos := Cur;
  if Executing then FnRegister(name, bodyPos, params);
  ExecSuite(False);   { skip the body — it runs on call }
end;

procedure ExecStatement;
var v: Variant;
begin
  StmtWasCompound := False;
  { compound statements (self-terminating at DEDENT). Set the flag AFTER the call
    returns — the nested statements inside the block reset it. }
  if IsKw('if') then begin ExecIf; StmtWasCompound := True; Exit; end;
  if IsKw('while') then begin ExecWhile; StmtWasCompound := True; Exit; end;
  if IsKw('for') then begin ExecFor; StmtWasCompound := True; Exit; end;
  if IsKw('def') then begin ExecDef; StmtWasCompound := True; Exit; end;
  if IsKw('del') then begin ExecDel; Exit; end;
  if IsKw('raise') then begin ExecRaise; Exit; end;
  if IsKw('break') then begin Advance; if Executing then BreakFlag := True; Exit; end;
  if IsKw('return') then
  begin
    Advance;
    if (CurKind = PK_NL) or (CurKind = PK_EOF) or (CurKind = PK_DEDENT) or IsOp(';') then
      v := MakeNone
    else
      ParseExpr(v);
    if Executing then begin ReturnValue := v; ReturnFlag := True; end;
    Exit;
  end;
  if IsKw('pass') then begin Advance; Exit; end;
  if IsKw('import') or IsKw('continue') or IsKw('elif') or IsKw('else') then
    EvalError('statement "' + CurText + '" is not supported yet');

  if (TkKind[Cur] = PK_NAME) and AssignmentAhead then
  begin DoAssignment; Exit; end;

  { expression statement (e.g. push(x), pop()) — value discarded }
  ParseExpr(v);
end;

{ Call a nested `def` function: fresh local scope bound to the params, body run
  from its recorded token position, `return` value captured. The caller's scope,
  cursor, and return state are saved and restored so calls nest and re-enter. }
procedure CallUserFn(fnIdx: Integer; args: TPyList; var res: Variant);
var
  savedNames: array of AnsiString;
  savedVals:  array of Variant;
  savedN, savedCur, i, ai, plen: Integer;
  savedRF: Boolean;
  savedRV: Variant;
  params, pname: AnsiString;
begin
  { save the caller frame }
  savedN := LclN;
  SetLength(savedNames, LclN); SetLength(savedVals, LclN);
  for i := 0 to LclN - 1 do begin savedNames[i] := LclNames[i]; savedVals[i] := LclVals[i]; end;
  savedCur := Cur; savedRF := ReturnFlag; savedRV := ReturnValue;

  { fresh scope + bind params positionally }
  LclN := 0;
  params := FnParams[fnIdx];
  plen := Length(params); ai := 0; pname := ''; i := 1;
  while i <= plen + 1 do
  begin
    if (i > plen) or (params[i] = ',') then
    begin
      if pname <> '' then
      begin
        if ai < args.count then LclSet(pname, args.at(ai)) else LclSet(pname, MakeNone);
        ai := ai + 1; pname := '';
      end;
    end
    else
      pname := pname + params[i];
    i := i + 1;
  end;

  { run the body }
  ReturnFlag := False; ReturnValue := MakeNone;
  Cur := FnBodyPos[fnIdx];
  ExecSuite(True);
  res := ReturnValue;

  { restore the caller frame }
  ReturnFlag := savedRF; ReturnValue := savedRV;
  Cur := savedCur;
  LclN := savedN;
  if Length(LclNames) < savedN then SetLength(LclNames, savedN);
  if Length(LclVals) < savedN then SetLength(LclVals, savedN);
  for i := 0 to savedN - 1 do begin LclNames[i] := savedNames[i]; LclVals[i] := savedVals[i]; end;
end;

{ Trampoline that runs the pending `__body__` def. exec() stores a variant
  pointing here into the caller's namespace dict; NilPy's `ns["__body__"]()`
  unboxes the payload (this address) and calls it with the all-Variant dynamic
  ABI (0 args, Variant result — see PyMakeDynCall / PyDynCallSig). Runs the def
  registered by the immediately-preceding EvalPyStmts over the still-live token
  stream + EnvG. A var-out call into Result (not `Result := CallUserFn(...)`)
  sidesteps the Variant-fn-return NRVO corruption. }
function PyBodyTramp: Variant;
var idx: Integer; noArgs: TPyList;
begin
  idx := FnFind('__body__');
  if idx < 0 then begin PPyRec(@Result)^.VType := 0; PPyRec(@Result)^.Payload := 0; Exit; end;
  noArgs := TPyList.Create;
  CallUserFn(idx, noArgs, Result);
  noArgs.Free;
end;

procedure EvalPyStmts(const src: AnsiString; g: TPyDict; l: TPyDict);
begin
  EnvG := g;
  { locals live in pyeval's own arrays (see LclSet); the `l` dict argument is
    accepted for API compatibility with Python's exec(src, g, l) but is not the
    backing store — uforth's block locals are function-internal and never read
    back by the host. }
  LclN := 0;
  FnN := 0;
  Executing := True;
  BreakFlag := False;
  ReturnFlag := False;
  { Dedent first (as CPython's exec path does via textwrap.dedent): a corpus
    block extracted from indented .UFO source carries a uniform leading indent on
    every line, which would otherwise tokenize as a spurious opening INDENT. }
  Tokenize(PreprocessFStrings(pytextwrap_dedent(src)));
  Cur := 0;
  SkipSeparators;
  while (CurKind <> PK_EOF) and (CurKind <> PK_DEDENT) do
  begin
    ExecStatement;
    if (not StmtWasCompound) and (CurKind <> PK_EOF) and (CurKind <> PK_DEDENT)
       and not (IsOp(';') or (CurKind = PK_NL)) then
      EvalError('expected end of statement, got "' + CurText + '"');
    SkipSeparators;
  end;
  { The uforth exec() idiom is `exec("def __body__(): ...", env, ns)` followed by
    `ns["__body__"]()`. The loop above only REGISTERED the def (ExecDef records its
    body span). Publish it into the caller's namespace as a callable variant so
    the separate `ns["__body__"]()` reaches it: the value's payload is
    &PyBodyTramp, unboxed and called through the dynamic-call ABI. Keyed with a
    VT_STRING matching NilPy's dict key (PyVarEq compares string content). }
  if (l <> nil) and (FnFind('__body__') >= 0) then
    l.store(MakeStr('__body__'), PyBoxObj(Pointer(@PyBodyTramp)));
end;

end.
