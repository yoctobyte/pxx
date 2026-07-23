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

{ Reverse bridge: invoke a captured pyeval closure (a nested `def` passed to a
  host method as a value) with one Variant argument. NilPy's PyMakeDynCall routes
  here when the callee variant carries the VT_PYCLOSURE tag. }
function PyClosureCall1(const clv: Variant; const a0: Variant): Variant;

{ Pointer-form reverse bridge: a closure stored in a Callable/Pointer field
  (Word.native) and called as `word.native(vm2)`. pyclosure_is tells a closure
  object apart from a real compiled function address so the field-call site can
  branch. }
function pyclosure_is(p: Pointer): Boolean;
function pyclosure_call_ptr(objptr: Pointer; const a0: Variant): Integer;

{ Build a closure from raw SOURCE text — the compiled frontend's lowering of a
  Python `lambda`: `lambda vm: vm.push(A)` becomes
  pyclosure_src_new('vm', 'return vm.push(A)') with each free name's VALUE
  captured at build time via pyclosure_src_cap (returns the object, so the
  frontend can chain caps as one expression). The result is the same
  magic-sentinel closure object Word.native already dispatches on. }
function pyclosure_src_new(const params, src: AnsiString): Pointer;
function pyclosure_src_cap(obj: Pointer; const name: AnsiString; const v: Variant): Pointer;

{ BOUND COMPILED FUNCTION: a nested def taken as a value whose captures must
  travel with it (uforth's MARKER: `def restore(v): ...snapshot locals...;
  define_word(name, native=restore)`). The object carries the COMPILED code
  address plus each captured value as a register word; the field-call bridge
  recognises it by magic (like a closure) and calls code(arg, bound...).
  The body runs NATIVELY — no pyeval subset limits. }
function pyboundfn_new(code: Pointer; n: Int64; a0var: Int64): Pointer;
function pyboundfn_bind(obj: Pointer; idx: Int64; v: Int64): Pointer;
function pyboundfn_is(p: Pointer): Boolean;
function pyboundfn_bind_var(obj: Pointer; idx: Int64; const v: Variant): Pointer;
function pyboundfn_call_ptr(objptr: Pointer; const a0: Variant): Integer;

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
  PK_BYTES  = 14;   { b'...' literal — chars are byte values }
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
  { Pointer-family shape: every param is a pointer-sized register value
    (int/int64/bool/char/pointer/class/AnsiString-by-value), passed as an Int64 in
    an integer register, result an Int64 (a class/pointer return, or an ordinal).
    Covers annotated host methods like `define_word(name: str, native: Callable,
    forth_body, immediate: bool) -> Word` that the all-Variant path cannot call. }
  TPFn0 = function(self: Pointer): Int64;
  TPFn1 = function(self: Pointer; a: Int64): Int64;
  TPFn2 = function(self: Pointer; a, b: Int64): Int64;
  TPFn3 = function(self: Pointer; a, b, c: Int64): Int64;
  TPFn4 = function(self: Pointer; a, b, c, d: Int64): Int64;
  TPFn5 = function(self: Pointer; a, b, c, d, e: Int64): Int64;

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
  { slot takes its own +1 (magic-guarded; see the borrow-everywhere note in
    feature-nilpy-object-reclamation slice 2) }
  PXXObjRetain(p);
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

{ Int64 value of any int-ish variant, promo included (a promo that exceeds
  Int64 narrows mod 2^64, two's complement — callers coerce only where a
  64-bit cell is expected, and the wrap is what keeps the masked-cell idiom an
  identity; the CHECKED PXXPromoToInt64 trapped mid-idiom). }
function PyToI64(const v: Variant): Int64;
var s: array[0..1] of NativeInt;
begin
  if IsPromoV(v) then
  begin
    PXXPromoInit(@s); PXXPromoFromVariant(@s, @v);
    PyToI64 := PXXPromoToInt64Wrap(@s);
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
  op: 1 add, 2 sub, 3 mul, 4 floordiv, 5 mod, 6 and, 7 or, 8 xor,
  9 shl, 10 shr (the bitwise five have Python two's-complement semantics). }
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
  else if op = 6 then PXXPromoAnd(@pr, @pa, @pb)
  else if op = 7 then PXXPromoOr(@pr, @pa, @pb)
  else if op = 8 then PXXPromoXor(@pr, @pa, @pb)
  else if op = 9 then PXXPromoShl(@pr, @pa, @pb)
  else if op = 10 then PXXPromoShr(@pr, @pa, @pb)
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
  ia := pyvar_to_int(a); ib := pyvar_to_int(b);
  { the div-based overflow probe below itself SIGFPEs when r = Low(Int64) and
    ia = -1 (hardware idiv overflow), so the -1 multiplier is decided here:
    it overflows only for ib = Low(Int64). }
  if ia = -1 then
  begin
    if ib = Low(Int64) then PromoOp(a, b, 3, res)
    else res := pyvar_of_int(-ib);
    Exit;
  end;
  r := ia * ib;
  if (ia <> 0) and (r div ia <> ib) then PromoOp(a, b, 3, res)
  else res := pyvar_of_int(r);
end;

procedure PyIFloorDiv(const a, b: Variant; var res: Variant);
begin
  if IsPromoV(a) or IsPromoV(b) then PromoOp(a, b, 4, res)
  { Low(Int64) // -1 = 2^63, past Int64 — and the hardware idiv traps SIGFPE
    on exactly that pair, so it must promote BEFORE reaching pyfloordiv_v. }
  else if (pyvar_to_int(a) = Low(Int64)) and (pyvar_to_int(b) = -1) then
    PromoOp(a, b, 4, res)
  else res := pyfloordiv_v(a, b);
end;

procedure PyIMod(const a, b: Variant; var res: Variant);
begin
  if IsPromoV(a) or IsPromoV(b) then PromoOp(a, b, 5, res)
  { same idiv SIGFPE pair as PyIFloorDiv (the result is simply 0) }
  else if (pyvar_to_int(a) = Low(Int64)) and (pyvar_to_int(b) = -1) then
    PromoOp(a, b, 5, res)
  else res := pymod_v(a, b);
end;

{ `a << n` == a * 2^n; routed through PyIMul so overflow auto-promotes. }
procedure PyIShl(const a, nv: Variant; var res: Variant);
var p: Variant;
begin
  Pow2V(PyToI64(nv), p);
  PyIMul(a, p, res);
end;

{ `a >> n` == floor(a / 2^n) (Python arithmetic shift). Promo -> the promo
  runtime's arithmetic shr; Int64 -> the existing sign-propagating shift. }
procedure PyIShr(const a, nv: Variant; var res: Variant);
begin
  if IsPromoV(a) then PromoOp(a, nv, 10, res)
  else res := pyshr_v(a, nv);
end;

{ `a & b`. Both Int64 -> plain and (Int64 AND is already two's complement).
  A promo side -> the promo runtime's bitwise AND (Python two's-complement
  fixed-width view), which makes `-2 & 0xFFFFFFFFFFFFFFFF` the positive
  unsigned reading — the earlier mask-only mod-2^k rewrite kept the SIGN of a
  negative operand (Pascal mod truncates) and broke exactly those cells. }
procedure PyIBitAnd(const a, b: Variant; var res: Variant);
begin
  if (not IsPromoV(a)) and (not IsPromoV(b)) then
    res := pyvar_of_int(pyvar_to_int(a) and pyvar_to_int(b))
  else
    PromoOp(a, b, 6, res);
end;

procedure PyIBitOr(const a, b: Variant; var res: Variant);
begin
  if (not IsPromoV(a)) and (not IsPromoV(b)) then
    res := pyvar_of_int(pyvar_to_int(a) or pyvar_to_int(b))
  else
    PromoOp(a, b, 7, res);
end;

procedure PyIBitXor(const a, b: Variant; var res: Variant);
begin
  if (not IsPromoV(a)) and (not IsPromoV(b)) then
    res := pyvar_of_int(pyvar_to_int(a) xor pyvar_to_int(b))
  else
    PromoOp(a, b, 8, res);
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

{ `is` identity, plus the compiled Optional[str] narrowing: a host method typed
  Optional[str] returns None as an EMPTY AnsiString across the trampoline (the
  documented sentinel), so `tok is None` must accept '' — without it EXTRA.UFO's
  `.( ` loop (`tok = vm.next_token(); if tok is None: break`) never saw the end
  of the line and re-spun the tokenizer forever. }
function PyIsIdentity(const a, b: Variant): Boolean;
begin
  if ((PPyRec(@a)^.VType = 0) and (PPyRec(@b)^.VType = 6) and
      (PPyAnsiString(@PPyRec(@b)^.Payload)^ = '')) or
     ((PPyRec(@b)^.VType = 0) and (PPyRec(@a)^.VType = 6) and
      (PPyAnsiString(@PPyRec(@a)^.Payload)^ = '')) then
    PyIsIdentity := True
  else
    PyIsIdentity := PyIEq(a, b);
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

{ Case-insensitive string equality with NO allocation — the previous
  lowercase-both-then-compare cost two fresh PXXStrFromLit buffers per call,
  and PyFindMethCI runs once per host-method dispatch (the doloop leak the
  valgrind libc-heap profile attributed to PyHostCall). }
function PyEqCI(const a, b: AnsiString): Boolean;
var i, n: Integer; ca, cb: Char;
begin
  n := Length(a);
  if n <> Length(b) then begin PyEqCI := False; Exit; end;
  for i := 1 to n do
  begin
    ca := a[i]; cb := b[i];
    if (ca >= 'A') and (ca <= 'Z') then ca := Chr(Ord(ca) + 32);
    if (cb >= 'A') and (cb <= 'Z') then cb := Chr(Ord(cb) + 32);
    if ca <> cb then begin PyEqCI := False; Exit; end;
  end;
  PyEqCI := True;
end;

function PyFindMethCI(cls: PClassRTTI; const name: AnsiString): PMethInfo;
var curr: PClassRTTI; meths: PMethInfo; i: Integer;
begin
  PyFindMethCI := nil;
  curr := cls;
  while curr <> nil do
  begin
    if curr^.MethCount > 0 then
    begin
      meths := curr^.MethsPtr;
      for i := 0 to Integer(curr^.MethCount) - 1 do
        { zero-allocation CI compare — no lowercased copies to leak }
        if PyEqCI(meths[i].NamePtr^, name) then
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
  pf0: TPFn0; pf1: TPFn1; pf2: TPFn2; pf3: TPFn3; pf4: TPFn4; pf5: TPFn5;
  ptrFamily: Boolean;
  pa: array[0..4] of Int64;
  psHold: array[0..4] of AnsiString;   { keep AnsiString-by-value args alive across the call }
  pret: Int64;
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

  { --- pointer-family shape: an annotated host method whose params are all
        pointer-sized register values (int/int64/bool/char/pointer/class/
        AnsiString-by-value). uforth's `define_word(name: str, native: Callable,
        forth_body, immediate: bool) -> Word` is the driver. Each arg is coerced
        to the Int64 the callee's ABI expects in an integer register; omitted
        trailing params are filled from their per-kind zero default (None -> nil,
        False -> 0), matching Python's defaults. --- }
  if not allVariant then
  begin
    ptrFamily := (n <= 5) and (pk <> nil);
    if ptrFamily then
      for i := 1 to n do
        if not ((pk[i] = 1) or (pk[i] = 2) or (pk[i] = 3) or (pk[i] = 13) or
                (pk[i] = 17) or (pk[i] = 6) or (pk[i] = 23)) then ptrFamily := False;
    if not ptrFamily then
    begin
      writeln('pyeval: host method ', name, ' has an unsupported param shape');
      Halt(1);
    end;
    for i := 0 to 4 do pa[i] := 0;
    for i := 1 to n do
    begin
      if (i - 1) >= nargs then
        pa[i-1] := 0            { omitted -> per-kind zero default }
      else if pk[i] = 23 then
      begin
        psHold[i-1] := pystr_of(args.at(i-1));
        pa[i-1] := Int64(NativeInt(Pointer(psHold[i-1])));
      end
      else if (pk[i] = 17) or (pk[i] = 6) then
      begin
        { a Pointer/Callable/class param: a closure -> its object pointer, an
          object/function value -> its payload pointer, None -> nil. }
        a0 := args.at(i-1);
        case PPyRec(@a0)^.VType of
          VT_PYCLOSURE: pa[i-1] := PPyRec(@a0)^.Payload;
          7:            pa[i-1] := PPyRec(@a0)^.Payload;
          0:            pa[i-1] := 0;
        else            pa[i-1] := pyvar_to_int(a0);
        end;
      end
      else
        pa[i-1] := pyvar_to_int(args.at(i-1));   { int/int64/bool/char }
    end;
    code := mi^.Code;
    case n of
      0: begin pf0 := TPFn0(code); pret := pf0(vmobj); end;
      1: begin pf1 := TPFn1(code); pret := pf1(vmobj, pa[0]); end;
      2: begin pf2 := TPFn2(code); pret := pf2(vmobj, pa[0], pa[1]); end;
      3: begin pf3 := TPFn3(code); pret := pf3(vmobj, pa[0], pa[1], pa[2]); end;
      4: begin pf4 := TPFn4(code); pret := pf4(vmobj, pa[0], pa[1], pa[2], pa[3]); end;
      5: begin pf5 := TPFn5(code); pret := pf5(vmobj, pa[0], pa[1], pa[2], pa[3], pa[4]); end;
    end;
    { box the result by its kind: class/pointer -> VT_OBJECT; ordinal -> int;
      void (rk=0) -> None. }
    if (rk = 6) or (rk = 17) then
    begin
      PPyRec(@res)^.VType := 7; PPyRec(@res)^.Payload := pret;
      PXXObjRetain(Pointer(NativeInt(pret)));   { slot owns +1 (magic-guarded) }
    end
    else if rk = 0 then res := MakeNone
    else res := pyvar_of_int(pret);
    Exit;
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
  mi: PMethInfo;
  noArgs: TPyList;
  gname: AnsiString;
begin
  cls := GetInstanceRTTI(obj);
  if cls = nil then begin writeln('pyeval: no RTTI for attribute ', name); Halt(1); end;
  p := GetFieldPtr(obj, cls, name, kind);
  if p = nil then
  begin
    { A @property compiles to a METHOD, so an attribute read that misses the
      fields must invoke a 0-arg method of that name (uforth's `vm.base` — a
      miss here read the dynattr store instead, yielded None, and `ud % base`
      divided by zero). Arity 1 = self only, the getter shape; anything wider
      is a real method and stays a plain (dynattr) miss so `vm.push` as a
      value is not suddenly a call. }
    gname := '__prop_get_' + name;      { the @property getter's mangled name }
    mi := PyFindMethCI(cls, gname);
    if mi = nil then
    begin
      gname := name;
      mi := PyFindMethCI(cls, name);
    end;
    if (mi <> nil) and (mi^.Arity = 1) then
    begin
      noArgs := TPyList.Create;
      PyHostCall(obj, gname, noArgs, res);
      noArgs.Free;
      Exit;
    end;
    res := pydynattr_get(obj, name);
    Exit;
  end;
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
      VT_OBJECT so subscripts and method calls can reach the container. A field
      read BORROWS — the field keeps its own ref — so the variant must take +1
      (no-op on unheadered Pascal instances; the variant's scope-exit release
      balances it once the object arms are live). }
    r^.VType := 7; r^.Payload := PInt64(p)^;
    PXXObjRetain(Pointer(NativeInt(r^.Payload)));
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
  if p = nil then begin pydynattr_set(obj, name, val); Exit; end;
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
    s: AnsiString;
begin
  if PPyRec(@container)^.VType = 6 then
  begin
    { s[i] — a one-character string, Python indexing (the pictured-numeric
      digit table `'0123456789...'[digit]` comes through here) }
    s := PPyAnsiString(@PPyRec(@container)^.Payload)^;
    n := Length(s); i := pyvar_to_int(index);
    if i < 0 then i := i + n;
    if (i < 0) or (i >= n) then
    begin writeln('pyeval: string index out of range'); Halt(1); end;
    res := MakeStr(s[i + 1]);
    Exit;
  end;
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
  c, c2, hc: Char;
  start, hv, hk: Integer;
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
      { b'...' — a BYTES literal: scan like a string, tag PK_BYTES }
      if ((c = 'b') or (c = 'B')) and (Pos + 1 <= SLen) and
         ((Src[Pos+1] = '''') or (Src[Pos+1] = '"')) then
      begin
        Pos := Pos + 1;
        c2 := Src[Pos];
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
              'x':
                begin
                  hv := 0;
                  if (Pos + 2 <= SLen) then
                  begin
                    for hk := 1 to 2 do
                    begin
                      Pos := Pos + 1;
                      hc := Src[Pos];
                      if (hc >= '0') and (hc <= '9') then hv := hv * 16 + Ord(hc) - 48
                      else if (hc >= 'a') and (hc <= 'f') then hv := hv * 16 + Ord(hc) - 87
                      else if (hc >= 'A') and (hc <= 'F') then hv := hv * 16 + Ord(hc) - 55;
                    end;
                  end;
                  slit := slit + Chr(hv);
                end;
            else
              slit := slit + Src[Pos];
            end;
          end
          else
            slit := slit + Src[Pos];
          Pos := Pos + 1;
        end;
        if Pos > SLen then TokError('unterminated bytes literal');
        Pos := Pos + 1;
        AddTok(PK_BYTES, slit, 0, 0);
        continue;
      end;
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
            'x':
              begin
                hv := 0;
                if (Pos + 2 <= SLen) then
                  for hk := 1 to 2 do
                  begin
                    Pos := Pos + 1;
                    hc := Src[Pos];
                    if (hc >= '0') and (hc <= '9') then hv := hv * 16 + Ord(hc) - 48
                    else if (hc >= 'a') and (hc <= 'f') then hv := hv * 16 + Ord(hc) - 87
                    else if (hc >= 'A') and (hc <= 'F') then hv := hv * 16 + Ord(hc) - 55;
                  end;
                slit := slit + Chr(hv);
              end;
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
  else if (name = 'list') or (name = 'tuple') then PyTypeCode := 107  { a tuple IS a TPyList }
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

{ ---- persistent closures: a nested `def` captured as a VALUE (M2c) ---- }
{ A pyeval `def` used as a value — passed to a host method (uforth's
  `vm.define_word(name, native=_w)`) and called back much later as
  `word.native(vm2)` — must OUTLIVE its EvalPyStmts: Tokenize reuses the global
  token buffer on the next exec, and the enclosing locals (`name`) are gone too.
  So snapshot the whole token buffer, the body position, the params, and the
  enclosing locals into a persistent record. Boxed as a VT_PYCLOSURE (tag 9)
  variant whose payload is the record index; the reverse bridge (NilPy's
  PyMakeDynCall) sees the tag and routes the call to PyClosureCall1. }
const VT_PYCLOSURE = 9;
type
  TPyClosure = record
    Kinds:  array of Integer;
    Texts:  array of AnsiString;
    Ints:   array of Int64;
    Floats: array of Double;
    NTok:   Integer;
    BodyPos: Integer;
    Params:  AnsiString;
    CapNames: array of AnsiString;
    CapVals:  array of Variant;
    CapN:    Integer;
    { True for a closure built from raw SOURCE (pyclosure_src_new): its body is
      a FLAT statement stream at indent 0, run by a top-level loop rather than
      ExecSuite's after-a-colon suite grammar. }
    FlatSrc: Boolean;
  end;
  { A closure passed to a Callable/Pointer host param (uforth's
    `define_word(name, native=_w)`) is stored in the class's Pointer-typed field
    (Word.native) and later called as `word.native(vm2)` — an indirect call
    through a raw pointer, NOT the Variant dynamic-call path. So the value living
    in that field must be a POINTER that the call site can tell apart from a real
    compiled function address. A TClosureObj does that: its first word is a fixed
    Magic sentinel (the address of a pyeval global), which a real code pointer's
    first instruction bytes will not match, so `word.native(vm2)` can branch —
    closure -> PyClosureCallPtr, real fn -> the plain indirect call. }
  TClosureObj = record
    Magic: Pointer;
    Cidx:  Int64;
  end;
  PClosureObj = ^TClosureObj;
var
  Closures: array of TPyClosure;
  ClosureN: Integer;

  PyClosureMagicMarker: Integer;   { its ADDRESS is the closure sentinel }

{ Recycle stack of dead Closures[] rows (feature-nilpy-object-reclamation):
  a closure OBJECT is a refcounted RAW2 block; when it dies, PyEvalClosureFree
  releases the row's captures and token refs and parks the index here for the
  next creator. }
var
  ClosureFreeStk: array of Integer;
  ClosureFreeN: Integer;

procedure PyEvalClosureFree(objp: Pointer);
var c, i: Integer;
begin
  if objp = nil then Exit;
  if PClosureObj(objp)^.Magic <> @PyClosureMagicMarker then Exit;
  c := Integer(PClosureObj(objp)^.Cidx);
  if (c < 0) or (c >= ClosureN) then Exit;
  Closures[c].Kinds := nil;
  Closures[c].Texts := nil;
  Closures[c].Ints := nil;
  Closures[c].Floats := nil;
  for i := 0 to Closures[c].CapN - 1 do
  begin
    Closures[c].CapNames[i] := '';
    Closures[c].CapVals[i] := 0;   { variant := int releases any payload }
  end;
  SetLength(Closures[c].CapNames, 0);
  SetLength(Closures[c].CapVals, 0);
  Closures[c].CapN := 0;
  Closures[c].Params := '';
  Closures[c].NTok := 0;
  if ClosureFreeN >= Length(ClosureFreeStk) then
  begin
    if Length(ClosureFreeStk) = 0 then SetLength(ClosureFreeStk, 16)
    else SetLength(ClosureFreeStk, Length(ClosureFreeStk) * 2);
  end;
  ClosureFreeStk[ClosureFreeN] := c;
  ClosureFreeN := ClosureFreeN + 1;
end;

{ Pop a recycled registry row, or mint a fresh one. }
function PyClosureAllocRow: Integer;
begin
  if ClosureFreeN > 0 then
  begin
    ClosureFreeN := ClosureFreeN - 1;
    PyClosureAllocRow := ClosureFreeStk[ClosureFreeN];
    Exit;
  end;
  if ClosureN >= Length(Closures) then
  begin
    if Length(Closures) = 0 then SetLength(Closures, 8)
    else SetLength(Closures, Length(Closures) * 2);
  end;
  PyClosureAllocRow := ClosureN;
  ClosureN := ClosureN + 1;
end;

function PyMakeClosureObj(cidx: Int64): Pointer;
var o: PClosureObj;
begin
  PXXObjFinalizeHook := @PyObjFinalize;
  PyClosureFinalizeHook := @PyEvalClosureFree;
  o := PClosureObj(PXXObjAllocRaw2(SizeOf(TClosureObj)));
  o^.Magic := @PyClosureMagicMarker;
  o^.Cidx  := cidx;
  PyMakeClosureObj := Pointer(o);
end;

{ ---- bound compiled functions (see interface note) ---- }
type
  TBoundFnObj = record
    Magic:  Pointer;
    Code:   Pointer;
    NBound: Int64;
    A0Var:  Int64;   { 1 = the user argument is a VARIANT param (pass its address) }
    Bound:  array[0..19] of Int64;
  end;
  PBoundFnObj = ^TBoundFnObj;
  TBF1  = function(a0: Int64): Int64;
  TBF2  = function(a0, a1: Int64): Int64;
  TBF3  = function(a0, a1, a2: Int64): Int64;
  TBF4  = function(a0, a1, a2, a3: Int64): Int64;
  TBF5  = function(a0, a1, a2, a3, a4: Int64): Int64;
  TBF6  = function(a0, a1, a2, a3, a4, a5: Int64): Int64;
  TBF7  = function(a0, a1, a2, a3, a4, a5, a6: Int64): Int64;
  TBF8  = function(a0, a1, a2, a3, a4, a5, a6, a7: Int64): Int64;
  TBF9  = function(a0, a1, a2, a3, a4, a5, a6, a7, a8: Int64): Int64;
  TBF11 = function(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10: Int64): Int64;
  TBF13 = function(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12: Int64): Int64;
var
  PyBoundFnMagicMarker: Integer;

function pyboundfn_new(code: Pointer; n: Int64; a0var: Int64): Pointer;
var o: PBoundFnObj; i: Integer;
begin
  o := GetMem(SizeOf(TBoundFnObj));
  o^.Magic := @PyBoundFnMagicMarker;
  o^.Code := code;
  o^.NBound := n;
  o^.A0Var := a0var;
  for i := 0 to 19 do o^.Bound[i] := 0;
  pyboundfn_new := Pointer(o);
end;

function pyboundfn_bind(obj: Pointer; idx: Int64; v: Int64): Pointer;
var o: PBoundFnObj;
begin
  o := PBoundFnObj(obj);
  o^.Bound[idx] := v;
  pyboundfn_bind := obj;
end;

function pyboundfn_is(p: Pointer): Boolean;
begin
  pyboundfn_is := (p <> nil) and (PBoundFnObj(p)^.Magic = @PyBoundFnMagicMarker);
end;

{ Bind a VARIANT capture: variant params travel BY ADDRESS, and the enclosing
  local dies with its frame — so the value is copied into a small heap slot
  that lives as long as the object (leaked with it; markers are few). }
function pyboundfn_bind_var(obj: Pointer; idx: Int64; const v: Variant): Pointer;
var o: PBoundFnObj; pv: PVariant;
begin
  o := PBoundFnObj(obj);
  pv := GetMem(16);   { a Variant slot: 8-byte tag + 8-byte payload }
  PPyRec(pv)^.VType := 0; PPyRec(pv)^.Payload := 0;
  pv^ := v;
  o^.Bound[idx] := Int64(NativeInt(Pointer(pv)));
  pyboundfn_bind_var := obj;
end;

{ Call code(a0, bound...). a0 is the ONE user argument — a class/object variant
  yields its instance pointer, an int its value. Missing arities pad upward
  (extra register args are ABI-harmless); a procedure callee's garbage result
  is discarded. }
function pyboundfn_call_ptr(objptr: Pointer; const a0: Variant): Integer;
var o: PBoundFnObj; p0, rr: Int64; b: PInt64; code: Pointer;
    va0: Variant;
    f1: TBF1; f2: TBF2; f3: TBF3; f4: TBF4; f5: TBF5; f6: TBF6; f7: TBF7;
    f8: TBF8; f9: TBF9; f11: TBF11; f13: TBF13;
begin
  rr := 0;
  o := PBoundFnObj(objptr);
  code := o^.Code;
  if o^.A0Var <> 0 then
  begin
    { an unannotated (variant) first param travels BY ADDRESS }
    va0 := a0;
    p0 := Int64(NativeInt(Pointer(@va0)));
  end
  else
  case PPyRec(@a0)^.VType of
    7: p0 := PPyRec(@a0)^.Payload;
    0: p0 := 0;
  else p0 := pyvar_to_int(a0);
  end;
  b := @o^.Bound[0];
  case o^.NBound of
    0: begin f1 := TBF1(code); rr := f1(p0); end;
    1: begin f2 := TBF2(code); rr := f2(p0, b[0]); end;
    2: begin f3 := TBF3(code); rr := f3(p0, b[0], b[1]); end;
    3: begin f4 := TBF4(code); rr := f4(p0, b[0], b[1], b[2]); end;
    4: begin f5 := TBF5(code); rr := f5(p0, b[0], b[1], b[2], b[3]); end;
    5: begin f6 := TBF6(code); rr := f6(p0, b[0], b[1], b[2], b[3], b[4]); end;
    6: begin f7 := TBF7(code); rr := f7(p0, b[0], b[1], b[2], b[3], b[4], b[5]); end;
    7: begin f8 := TBF8(code); rr := f8(p0, b[0], b[1], b[2], b[3], b[4], b[5], b[6]); end;
    8: begin f9 := TBF9(code); rr := f9(p0, b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7]); end;
    9, 10:
      begin f11 := TBF11(code); rr := f11(p0, b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9]); end;
    else
      begin f13 := TBF13(code); rr := f13(p0, b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11]); end;
  end;
  if rr = 0 then pyboundfn_call_ptr := 0 else pyboundfn_call_ptr := 0;
end;


{ Closure from raw SOURCE (the compiled `lambda` lowering). Tokenizes the body
  text into the closure's own snapshot buffer — the live interpreter state
  (token buffer, cursor, source scanner) is saved and restored, so this is safe
  to call from inside a running EvalPyStmts. BodyPos 0 = the start of the flat
  `return <expr>` statement; ExecSuite's inline form runs it. }
function pyclosure_src_new(const params, src: AnsiString): Pointer;
var sKinds: array of Integer; sTexts: array of AnsiString;
    sInts: array of Int64; sFloats: array of Double;
    sTkN, sCur, sPos, sSLen: Integer; sSrc: AnsiString;
    c, i: Integer;
begin
  sKinds := TkKind; sTexts := TkText; sInts := TkInt; sFloats := TkFloat;
  sTkN := TkN; sCur := Cur; sSrc := Src; sPos := Pos; sSLen := SLen;
  Tokenize(src);
  c := PyClosureAllocRow;
  { ref-share, not deep-copy — see PyMakeClosure; here Tokenize(src) just
    allocated these arrays fresh, so nothing else mutates them }
  Closures[c].Kinds  := TkKind;
  Closures[c].Texts  := TkText;
  Closures[c].Ints   := TkInt;
  Closures[c].Floats := TkFloat;
  Closures[c].NTok := TkN;
  Closures[c].BodyPos := 0;
  Closures[c].Params := params;
  SetLength(Closures[c].CapNames, 0);
  SetLength(Closures[c].CapVals, 0);
  Closures[c].CapN := 0;
  Closures[c].FlatSrc := True;
  TkKind := sKinds; TkText := sTexts; TkInt := sInts; TkFloat := sFloats;
  TkN := sTkN; Cur := sCur; Src := sSrc; Pos := sPos; SLen := sSLen;
  pyclosure_src_new := PyMakeClosureObj(c);
end;

function pyclosure_src_cap(obj: Pointer; const name: AnsiString; const v: Variant): Pointer;
var c, n: Integer;
begin
  c := PClosureObj(obj)^.Cidx;
  n := Closures[c].CapN;
  SetLength(Closures[c].CapNames, n + 1);
  SetLength(Closures[c].CapVals, n + 1);
  Closures[c].CapNames[n] := name;
  Closures[c].CapVals[n] := v;
  Closures[c].CapN := n + 1;
  pyclosure_src_cap := obj;
end;

function PyMakeClosure(fnIdx: Integer): Variant;
var c, i: Integer; r: PPyRec;
begin
  c := PyClosureAllocRow;
  { REFERENCE-share the token arrays instead of deep-copying: a full snapshot
    of the exec source per closure (every `ns["__body__"]` lookup!) was the
    dominant per-call leak in uforth's PYTHON-word path (~20 KB/exec). Safe
    because the tokenization cache never mutates a live buffer in place — on a
    miss the live refs are nilled first and Tokenize allocates fresh arrays
    (see the cache note above). }
  Closures[c].Kinds  := TkKind;
  Closures[c].Texts  := TkText;
  Closures[c].Ints   := TkInt;
  Closures[c].Floats := TkFloat;
  Closures[c].NTok    := TkN;
  Closures[c].BodyPos := FnBodyPos[fnIdx];
  Closures[c].Params  := FnParams[fnIdx];
  SetLength(Closures[c].CapNames, LclN);
  SetLength(Closures[c].CapVals, LclN);
  for i := 0 to LclN - 1 do
  begin
    Closures[c].CapNames[i] := LclNames[i];
    Closures[c].CapVals[i]  := LclVals[i];
  end;
  Closures[c].CapN := LclN;
  r := PPyRec(@Result);
  r^.VType   := VT_PYCLOSURE;
  r^.Payload := Int64(NativeInt(PyMakeClosureObj(c)));   { payload = closure-obj pointer }
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
    else if FnFind(name) >= 0 then
      { a nested `def` used as a bare value (no call) — capture it as a closure so
        it survives being stored by a host method and called back later. }
      res := PyMakeClosure(FnFind(name))
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
  { ---- targeted module intercepts (import is a no-op statement) ----
    sys.stdout.write(EXPR) / sys.stdout.flush() — the corpus's D. / D.R
    printers. stderr writes are swallowed (matching the compiled side). }
  if (TkKind[Cur] = PK_NAME) and (TkText[Cur] = 'sys') and
     (TkKind[Cur+1] = PK_OP) and (TkText[Cur+1] = '.') then
  begin
    Advance; Advance;                    { sys . }
    name := CurText; Advance;            { stdout / stderr }
    if (CurKind = PK_OP) and (CurText = '.') then Advance;
    fld := CurText; Advance;             { write / flush }
    ExpectOp('(');
    if not IsOp(')') then
    begin
      ParseExpr(recv);
      if (fld = 'write') and (name = 'stdout') and Executing then
        write(pystr_of(recv));
    end;
    ExpectOp(')');
    res := MakeNone;
    Exit;
  end;
  { ---- atom ---- }
  if TkKind[Cur] = PK_INT then
  begin res := pyvar_of_int(TkInt[Cur]); Advance; end
  else if TkKind[Cur] = PK_BIGINT then
  begin PyBigLit(TkText[Cur], res); Advance; end
  else if TkKind[Cur] = PK_FLOAT then
  begin res := MakeFloat(TkFloat[Cur]); Advance; end
  else if TkKind[Cur] = PK_BYTES then
  begin
    res := PyBoxObj(Pointer(bytes(TkText[Cur])));   { chars are the byte values }
    Advance;
  end
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
    PXXObjRetain(Pointer(li));   { slot owns +1 (magic-guarded) }
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
      PXXObjRetain(Pointer(dd));   { slot owns +1 (magic-guarded) }
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
        PXXObjRetain(Pointer(dd));   { slot owns +1 (magic-guarded) }
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
        PXXObjRetain(Pointer(li));   { slot owns +1 (magic-guarded) }
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
  begin
    { `(expr)` is a grouping; `(a, b, ...)` is a tuple. A tuple is backed by a
      TPyList (same VT_OBJECT representation), so membership (`x in (d, 10)`) and
      iteration work — uforth's WORD uses `mem[..] not in (d, 10)`. }
    Advance;
    ParseExpr(res);
    if IsOp(',') then
    begin
      li := TPyList.Create;
      li.append(res);
      while IsOp(',') do
      begin
        Advance;
        if IsOp(')') then Break;   { trailing comma }
        ParseExpr(elem);
        li.append(elem);
      end;
      PPyRec(@res)^.VType := 7; PPyRec(@res)^.Payload := Int64(Pointer(li));
      PXXObjRetain(Pointer(li));   { slot owns +1 (magic-guarded) }
    end;
    ExpectOp(')');
  end
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
    { -a: promo-aware (0 - a) for a bignum — and for Low(Int64), whose plain
      neg wraps to itself while Python yields +2^63 }
    if IsPromoV(t) or (IsIntishV(t) and (PyToI64(t) = Low(Int64))) then
      PromoOp(pyvar_of_int(0), t, 2, res)
    else res := pyneg_v(t);
    Exit;
  end;
  if IsOp('+') then
  begin Advance; ParseUnary(res); Exit; end;
  if IsOp('~') then
  begin
    Advance; ParseUnary(t);
    { ~a = -a - 1; a bignum operand goes through the promo runtime }
    if IsPromoV(t) then
    begin
      PromoOp(pyvar_of_int(-1), t, 2, res);   { -1 - a == ~a }
      Exit;
    end;
    res := pyinvert_v(t);
    Exit;
  end;
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
      { skip-mode: names read as None and pymul_v on a mixed pair raises —
        same rule as // below }
      if not Executing then a := MakeNone
      else if IsIntishV(a) and IsIntishV(b) then begin PyIMul(a, b, t); a := t; end
      else if (PPyRec(@a)^.VType = 7) and
              (TObject(Pointer(PPyRec(@a)^.Payload)) is TPyBytes) and IsIntishV(b) then
        { b'..' * n — bytes repetition }
        a := PyBoxObj(Pointer(pybytes_repeat(TPyBytes(pyvarobj(a)), pyvar_to_int(b))))
      else a := pymul_v(a, b); end
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
      { skip-mode: names read as None, and pyadd_v('...' + None) raises a
        TypeError out of a branch that is not even taken — the dead
        `raise E('msg: ' + name)` in uforth's tick. Yield None like //. }
      if not Executing then a := MakeNone
      else if IsIntishV(a) and IsIntishV(b) then begin PyIAdd(a, b, t); a := t; end else a := pyadd_v(a, b); end
    else
    begin Advance; ParseMul(b);
      if not Executing then a := MakeNone
      else if IsIntishV(a) and IsIntishV(b) then begin PyISub(a, b, t); a := t; end else a := pysub_v(a, b); end;
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
var a, b, t: Variant;
begin
  ParseBitAnd(a);
  while IsOp('^') do
  begin Advance; ParseBitAnd(b);
    if IsIntishV(a) and IsIntishV(b) then begin PyIBitXor(a, b, t); a := t; end else a := pybitxor_v(a, b); end;
  res := a;
end;

procedure ParseBitOr(var res: Variant);
var a, b, t: Variant;
begin
  ParseBitXor(a);
  while IsOp('|') do
  begin Advance; ParseBitXor(b);
    if IsIntishV(a) and IsIntishV(b) then begin PyIBitOr(a, b, t); a := t; end else a := pybitor_v(a, b); end;
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
      if IsKw('not') then begin Advance; ParseBitOr(b); ok := ok and (not PyIsIdentity(a, b)); end
      else begin ParseBitOr(b); ok := ok and PyIsIdentity(a, b); end;
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
var a, b: Variant; sv: Boolean;
begin
  ParseNot(a);
  while IsKw('and') do
  begin
    Advance;
    { SHORT-CIRCUIT via a skip-mode parse of the dead operand — uforth's TO:
      `isinstance(current, tuple) and len(current) == 3` must not evaluate
      len() when current is an int. Value semantics: a and b -> b if a. }
    if Executing and pyvar_to_bool(a) then
    begin
      ParseNot(b);
      a := b;
    end
    else
    begin
      sv := Executing; Executing := False;
      ParseNot(b);
      Executing := sv;
    end;
  end;
  res := a;
end;

procedure ParseOr(var res: Variant);
var a, b: Variant; sv: Boolean;
begin
  ParseAnd(a);
  while IsKw('or') do
  begin
    Advance;
    if Executing and not pyvar_to_bool(a) then
    begin
      ParseAnd(b);
      a := b;
    end
    else
    begin
      sv := Executing; Executing := False;
      ParseAnd(b);
      Executing := sv;
    end;
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
  PXXObjRetain(Pointer(r));   { slot owns +1 (magic-guarded) }
end;

procedure CallBuiltin(const name: AnsiString; args: TPyList;
                      const endKw, sepKw: AnsiString;
                      haveEnd, haveSep: Boolean; var res: Variant);
var i, nargs: Integer; s, sep, endc: AnsiString; cand, e: Variant; li: TPyList;
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
    if IsPromoV(cand) or (IsIntishV(cand) and (PyToI64(cand) = Low(Int64))) then
    begin
      { promo, or Low(Int64) whose plain abs wraps to itself: 0 - a }
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
  if name = 'list' then
  begin
    { list() -> a fresh empty list; list(xs) -> a shallow copy }
    li := TPyList.Create;
    if nargs > 0 then
    begin
      cand := args.at(0);
      if (PPyRec(@cand)^.VType = 7) and
         (TObject(Pointer(PPyRec(@cand)^.Payload)) is TPyList) then
        li.extend(TPyList(pyvarobj(cand)))
      else if PPyRec(@cand)^.VType = 6 then
      begin
        { list("abc") -> one-character strings, Python's str iteration }
        s := PPyAnsiString(@PPyRec(@cand)^.Payload)^;
        for i := 1 to Length(s) do
          li.append(MakeStr(s[i]));
      end
      else
        EvalError('list(): unsupported argument');
    end;
    res := PyBoxObj(Pointer(li));
    Exit;
  end;
  if name = 'reversed' then
  begin
    { reversed(list|str) -> a reversed LIST (materialised) }
    li := TPyList.Create;
    if nargs > 0 then
    begin
      cand := args.at(0);
      if (PPyRec(@cand)^.VType = 7) and
         (TObject(Pointer(PPyRec(@cand)^.Payload)) is TPyList) then
      begin
        for i := TPyList(pyvarobj(cand)).count - 1 downto 0 do
          li.append(TPyList(pyvarobj(cand)).at(i));
      end
      else if PPyRec(@cand)^.VType = 6 then
      begin
        s := PPyAnsiString(@PPyRec(@cand)^.Payload)^;
        for i := Length(s) downto 1 do
          li.append(MakeStr(s[i]));
      end
      else
        EvalError('reversed(): unsupported argument');
    end;
    res := PyBoxObj(Pointer(li));
    Exit;
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
  if not Executing then begin res := MakeNone; args.Free; Exit; end;

  { user-defined nested function takes precedence (Python scoping) }
  if FnFind(callee) >= 0 then
  begin CallUserFn(FnFind(callee), args, res); args.Free; Exit; end;

  if IsHostName(callee) then
  begin
    if (EnvG = nil) or (EnvG.indexof('vm') < 0) then
      EvalError('host call ' + callee + ' but no "vm" in globals');
    vmv := EnvG.fetch('vm');
    vmobj := pyvarobj(vmv);
    PyHostCall(vmobj, callee, args, res);
    args.Free;
    Exit;
  end;
  CallBuiltin(callee, args, endKw, sepKw, haveEnd, haveSep, res);
  args.Free;
end;

{ `( expr, ... )` into `args`; a `signed=<bool>` keyword arg (to_bytes/from_bytes)
  is captured into signedKw, other keyword args are ignored (e.g. byteorder is
  positional and consumed as an ordinary arg). }
procedure ParseArgs(args: TPyList; var signedKw: Boolean);
var v, itv, item: Variant; kw, gname: AnsiString;
    exprStart, endPos, gi, gn: Integer;
    gres, glist: TPyList; go: TObject; gby: TPyBytes; gs: AnsiString;
    gexec: Boolean;
begin
  signedKw := False;
  ExpectOp('(');
  while not IsOp(')') do
  begin
    if (TkKind[Cur] = PK_NAME) and (TkKind[Cur+1] = PK_OP) and (TkText[Cur+1] = '=') then
    begin
      kw := TkText[Cur]; Advance; Advance; ParseExpr(v);
      { `signed=` steers pyint.to_bytes and is consumed out-of-band. Every other
        keyword arg is a host-method kwarg (uforth's `define_word(name,
        native=_w)`): append it positionally. uforth passes kwargs in the
        method's declaration order, and PyHostCall fills any omitted trailing
        params from their per-kind defaults, so positional order is correct. }
      if kw = 'signed' then signedKw := pyvar_to_bool(v)
      else args.append(v);
    end
    else
    begin
      { PROBE pass with Executing off: finds the expression's span end without
        evaluating (a genexp's item expr mentions the not-yet-bound loop var).
        Not a genexp -> re-parse for real; genexp -> per-item replays below. }
      exprStart := Cur;
      gexec := Executing;
      Executing := False;
      ParseExpr(v);
      Executing := gexec;
      if not IsKw('for') then
      begin
        Cur := exprStart;
        ParseExpr(v);
      end
      else
      begin
        { GENERATOR EXPRESSION `EXPR for NAME in ITER` — evaluated eagerly to a
          list (`''.join(chr(vm.memory[a+i]) for i in range(u))`, the corpus's
          string builders). The item expression's TOKEN SPAN is re-evaluated
          per element with NAME bound — same replay trick the typing pre-pass
          uses. No `if` filter and one loop variable: honest errors otherwise. }
        Advance;
        if TkKind[Cur] <> PK_NAME then EvalError('genexp: expected a name after for');
        gname := TkText[Cur]; Advance;
        if not IsKw('in') then EvalError('genexp: expected in');
        Advance;
        ParseExpr(itv);
        endPos := Cur;
        if not gexec then
        begin
          { skip-mode (a def registration walk): structure parsed, nothing runs }
          v := MakeNone;
          args.append(v);
          if IsOp(',') then Advance
          else if not IsOp(')') then EvalError('expected , or ) in method call');
          Continue;
        end;
        gres := TPyList.Create;
        if PPyRec(@itv)^.VType = 6 then
        begin
          gs := PPyAnsiString(@PPyRec(@itv)^.Payload)^;
          for gi := 1 to Length(gs) do
          begin
            LclSet(gname, MakeStr(gs[gi]));
            Cur := exprStart; ParseExpr(item);
            gres.append(item);
          end;
        end
        else
        begin
          go := TObject(Pointer(PPyRec(@itv)^.Payload));
          if go is TPyList then
          begin
            glist := TPyList(go); gn := glist.count;
            for gi := 0 to gn - 1 do
            begin
              LclSet(gname, glist.at(gi));
              Cur := exprStart; ParseExpr(item);
              gres.append(item);
            end;
          end
          else if go is TPyBytes then
          begin
            gby := TPyBytes(go); gn := gby.count;
            for gi := 0 to gn - 1 do
            begin
              LclSet(gname, pyvar_of_int(gby.at(gi)));
              Cur := exprStart; ParseExpr(item);
              gres.append(item);
            end;
          end
          else
            EvalError('genexp: unsupported iterable');
        end;
        Cur := endPos;
        PPyRec(@v)^.VType := 7;
        PPyRec(@v)^.Payload := Int64(NativeInt(Pointer(gres)));
        PXXObjRetain(Pointer(gres));   { slot owns +1 (magic-guarded) }
      end;
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
  i: Integer;
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
      PXXObjRetain(Pointer(by));   { slot owns +1 (magic-guarded) }
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
    else if mname = 'rjust' then
    begin
      if args.count >= 2 then
        res := MakeStr(pystr_rjust_c(s, pyvar_to_int(args.at(0)), pystr_of(args.at(1))))
      else
        res := MakeStr(pystr_rjust(s, pyvar_to_int(args.at(0))));
    end
    else if mname = 'find' then
      res := pyvar_of_int(pystr_find(s, pystr_of(args.at(0))))
    else if mname = 'index' then
    begin
      { str.index: find, but a MISS is a ValueError instead of -1 }
      i := pystr_find(s, pystr_of(args.at(0)));
      if i < 0 then EvalError('ValueError: substring not found');
      res := pyvar_of_int(i);
    end
    else if mname = 'encode' then
    begin
      b2 := pystr_encode(s);
      PPyRec(@res)^.VType := 7; PPyRec(@res)^.Payload := Int64(Pointer(b2));
      PXXObjRetain(Pointer(b2));   { slot owns +1 (magic-guarded) }
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
var name, params, pname: AnsiString; bodyPos: Integer; dv: Variant;
begin
  Advance;   { def }
  if CurKind <> PK_NAME then EvalError('def: expected a name');
  name := TkText[Cur]; Advance;
  ExpectOp('(');
  params := '';
  while not IsOp(')') do
  begin
    if CurKind <> PK_NAME then EvalError('def: expected a parameter name');
    pname := TkText[Cur]; Advance;
    if IsOp('=') then
    begin
      { `def _const(v, _lo=lo):` — a DEFAULT bound at def time (the corpus's
        capture idiom). Evaluate NOW and store as a LOCAL of the defining
        scope: PyMakeClosure snapshots the scope, so the body resolves the
        name through the capture. Not appended to params — the call site
        never passes it. }
      Advance;
      ParseExpr(dv);
      if Executing then LclSet(pname, dv);
    end
    else
    begin
      if params <> '' then params := params + ',';
      params := params + pname;
    end;
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
  if IsKw('import') then
  begin
    { `import sys` / `import time` — the module NAMES resolve through the
      targeted intercepts (sys.stdout.write etc.); the statement itself is
      consumed and ignored. Dotted names allowed. }
    Advance;
    while (CurKind = PK_NAME) or ((CurKind = PK_OP) and (CurText = '.')) or
          ((CurKind = PK_OP) and (CurText = ',')) do
      Advance;
    Exit;
  end;
  if IsKw('continue') or IsKw('elif') or IsKw('else') then
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

{ Run a captured closure (PyMakeClosure) with `args`. The whole interpreter state
  is swapped to the closure's snapshot — its own token buffer, a fresh scope
  holding the captured free vars plus the bound params, and the body cursor — then
  fully restored, so a closure can run while another EvalPyStmts / closure is on
  the stack (a native PYTHON word may call another). }
procedure PyClosureInvoke(cidx: Integer; args: TPyList; var res: Variant);
var
  sKinds:  array of Integer;   sTexts: array of AnsiString;
  sInts:   array of Int64;     sFloats: array of Double;
  sTkN, sCur, sLclN, sFnN, i, ai, plen: Integer;
  sLclNames: array of AnsiString; sLclVals: array of Variant;
  sFnName:  array of AnsiString;   sFnBodyPos: array of Integer;
  sFnParams: array of AnsiString;
  sRF, sExec, sBreak: Boolean; sRV: Variant;
  params, pname: AnsiString;
begin
  { save caller interpreter state }
  sKinds := TkKind; sTexts := TkText; sInts := TkInt; sFloats := TkFloat;
  sTkN := TkN; sCur := Cur; sLclN := LclN; sFnN := FnN;
  SetLength(sLclNames, LclN); SetLength(sLclVals, LclN);
  for i := 0 to LclN - 1 do begin sLclNames[i] := LclNames[i]; sLclVals[i] := LclVals[i]; end;
  SetLength(sFnName, FnN); SetLength(sFnBodyPos, FnN); SetLength(sFnParams, FnN);
  for i := 0 to FnN - 1 do
  begin sFnName[i] := FnName[i]; sFnBodyPos[i] := FnBodyPos[i]; sFnParams[i] := FnParams[i]; end;
  sRF := ReturnFlag; sRV := ReturnValue; sExec := Executing; sBreak := BreakFlag;

  { install the closure's snapshot token buffer }
  TkKind := Closures[cidx].Kinds; TkText := Closures[cidx].Texts;
  TkInt  := Closures[cidx].Ints;  TkFloat := Closures[cidx].Floats;
  TkN := Closures[cidx].NTok;

  { fresh scope: captured free vars first, params second (params shadow) }
  LclN := 0; FnN := 0;
  for i := 0 to Closures[cidx].CapN - 1 do
    LclSet(Closures[cidx].CapNames[i], Closures[cidx].CapVals[i]);
  params := Closures[cidx].Params;
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
    else pname := pname + params[i];
    i := i + 1;
  end;

  Executing := True; BreakFlag := False;
  ReturnFlag := False; ReturnValue := MakeNone;
  Cur := Closures[cidx].BodyPos;
  if Closures[cidx].FlatSrc then
  begin
    { source-built closure: flat statements at indent 0 until EOF }
    SkipSeparators;
    while (CurKind <> PK_EOF) and not ReturnFlag do
    begin
      ExecStatement;
      SkipSeparators;
    end;
  end
  else
    ExecSuite(True);
  res := ReturnValue;

  { restore caller interpreter state }
  TkKind := sKinds; TkText := sTexts; TkInt := sInts; TkFloat := sFloats;
  TkN := sTkN; Cur := sCur;
  FnN := sFnN;
  if Length(FnName) < sFnN then
  begin SetLength(FnName, sFnN); SetLength(FnBodyPos, sFnN); SetLength(FnParams, sFnN); end;
  for i := 0 to sFnN - 1 do
  begin FnName[i] := sFnName[i]; FnBodyPos[i] := sFnBodyPos[i]; FnParams[i] := sFnParams[i]; end;
  LclN := sLclN;
  if Length(LclNames) < sLclN then begin SetLength(LclNames, sLclN); SetLength(LclVals, sLclN); end;
  for i := 0 to sLclN - 1 do begin LclNames[i] := sLclNames[i]; LclVals[i] := sLclVals[i]; end;
  ReturnFlag := sRF; ReturnValue := sRV; Executing := sExec; BreakFlag := sBreak;
end;

{ Reverse bridge, 1-arg form: NilPy's PyMakeDynCall calls this when the callee
  VARIANT is a VT_PYCLOSURE. The var-out call into Result sidesteps the
  Variant-fn-return NRVO corruption. }
function PyClosureCall1(const clv: Variant; const a0: Variant): Variant;
var args: TPyList;
begin
  args := TPyList.Create;
  args.append(a0);
  PyClosureInvoke(PClosureObj(NativeInt(PPyRec(@clv)^.Payload))^.Cidx, args, Result);
  args.Free;
end;

{ Is `p` a closure object rather than a real compiled function address? The
  call-through-field site (`word.native(vm2)`) uses this to choose the bridge.
  Reading the first word of a code pointer is safe; a real function's opening
  bytes will not equal the sentinel address. }
function pyclosure_is(p: Pointer): Boolean;
begin
  pyclosure_is := (p <> nil) and (PClosureObj(p)^.Magic = @PyClosureMagicMarker);
end;

{ Reverse bridge, POINTER form: `word.native(vm2)` where the Callable field holds
  a closure object (uforth's VARIABLE/CONSTANT words). The closure's result is
  discarded — a Forth native word is `-> None`. }
function pyclosure_call_ptr(objptr: Pointer; const a0: Variant): Integer;
var args: TPyList; r: Variant;
begin
  args := TPyList.Create;
  args.append(a0);
  PyClosureInvoke(PClosureObj(objptr)^.Cidx, args, r);
  args.Free;
  pyclosure_call_ptr := 0;
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

{ ---- tokenization cache ------------------------------------------------
  A PYTHON-bodied Forth word re-enters EvalPyStmts with the SAME source on
  every execution, and tokenize+preprocess dominated the interpreter (~3ms per
  word — the blocktest ELF-HASH loops made it visible). Direct-mapped cache
  keyed by the raw source; a hit reuses the token arrays by reference. On a
  miss the live refs are NILLED first so Tokenize allocates fresh arrays and
  never mutates a cached buffer in place. }
const PYTOK_CACHE = 64;
type
  TTokCacheEntry = record
    Src:    AnsiString;
    Kinds:  array of Integer;
    Texts:  array of AnsiString;
    Ints:   array of Int64;
    Floats: array of Double;
    NTok:   Integer;
  end;
var
  TokCache: array[0..PYTOK_CACHE-1] of TTokCacheEntry;

function PyTokCacheSlot(const src: AnsiString): Integer;
var n: Integer;
begin
  n := Length(src);
  if n = 0 then begin PyTokCacheSlot := 0; Exit; end;
  PyTokCacheSlot := (n * 31 + Ord(src[1]) * 7 + Ord(src[n])) mod PYTOK_CACHE;
end;

procedure EvalPyStmts(const src: AnsiString; g: TPyDict; l: TPyDict);
var cslot: Integer;
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
  cslot := PyTokCacheSlot(src);
  if TokCache[cslot].Src = src then
  begin
    TkKind := TokCache[cslot].Kinds;
    TkText := TokCache[cslot].Texts;
    TkInt := TokCache[cslot].Ints;
    TkFloat := TokCache[cslot].Floats;
    TkN := TokCache[cslot].NTok;
  end
  else
  begin
    TkKind := nil; TkText := nil; TkInt := nil; TkFloat := nil;
    Tokenize(PreprocessFStrings(pytextwrap_dedent(src)));
    TokCache[cslot].Src := src;
    TokCache[cslot].Kinds := TkKind;
    TokCache[cslot].Texts := TkText;
    TokCache[cslot].Ints := TkInt;
    TokCache[cslot].Floats := TkFloat;
    TokCache[cslot].NTok := TkN;
  end;
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
