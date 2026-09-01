{ SPDX-License-Identifier: MPL-2.0 }
{ ===== Rust Parser (skeleton) =====

  Scope (feature-rust-frontend-skeleton, sub-ticket 1/12 of the Rust umbrella):
  fn / let(+mut, no-op) / plain expressions+binops / if-else / while / loop /
  plain (non-generic, non-trait) struct / calls / return. No match, no
  generics, no traits, no enum-with-data, no impl blocks, no references — all
  deferred to later sub-tickets (see feature-rust-frontend.md). Lowers
  directly onto the existing shared AST nodes (AN_IF/AN_WHILE/AN_CALL/...),
  same shape as clexer.inc/cparser.inc and pylexer.inc/pyparser.inc.

  Two-pass, C-frontend-shaped: pass 1 registers struct layouts and function
  signatures (so forward calls resolve via FindProc without requiring
  top-to-bottom definition order); pass 2 re-walks the same tokens and
  compiles bodies.

  x86-64 only (no new backend/ABI work — ticket scope). Functions take at
  most 4 scalar params (rdi/rsi/rdx/rcx), matching the same limit
  pyparser.inc's Nil-Python frontend has. Struct-typed params/returns are
  explicitly rejected for now (RTypeKindFromName below) to keep the calling
  convention scalar-only; passing structs by value/reference is follow-up
  work, not this skeleton.

  ===== enum + match (feature-rust-match-enum-payload, sub-ticket 2/12) =====

  No new shared AST node and no new TTypeKind: a tagged-union enum is built
  entirely out of the existing UClass/AddUField/RecFieldType machinery that
  already backs plain structs. An enum is a UClass (REnumCi[ci] marks it)
  whose fields are: a synthetic `__tag` discriminant at offset 0, then every
  variant's payload fields registered at the SAME overlapping byte range
  (offset 8) with variant-qualified mangled names ("Circle.0",
  "Rectangle.width") — AddUField/FindUField never assumed disjoint offsets,
  they just do a name lookup within a class's field window, so this is a
  real union with zero shared-internals changes. `match` desugars entirely
  at parse time into a chain of AN_IF nodes comparing `__tag`, with each
  arm's bound names materialized as ordinary fresh AllocVar locals assigned
  from the mangled field before the arm body is parsed — "pattern-bind" is
  just field-read + assign using vocabulary every frontend already has.

  Deliberate skeleton narrowing (documented, not silently dropped):
  - Enum values are constructed only as a `let` initializer (`let x =
    Variant(...);` / `let x = Enum::Variant { .. };`), never as a general
    subexpression — the same restriction plain struct literals already have
    (no AST node represents "a whole struct/union value" flowing through an
    expression; only named lvalue slots do).
  - `match` is a statement, not an expression-with-value (no `let y = match
    ...`) — same reason.
  - match scrutinee must be a plain local variable (`match shape { ... }`),
    not an arbitrary expression — sidesteps needing a general "resolve the
    static record type of this AST node" helper; a temp-materializing
    version is a small follow-up if a real test program needs it.
  - Bare (unqualified) variant names must be unique across all enums in the
    program; ambiguous names need the qualified `Enum::Variant` form.
  - No exhaustiveness/reachability checking (explicit non-goal). Arm-local
    binds do not roll back the symbol table (this compiler never pops
    scope mid-function — see RWhile bodies), so two arms binding the same
    name get two distinct, non-interfering stack slots each arm's own body
    resolves to correctly; a name reused by code *after* the whole match
    can be shadowed by a leftover arm binding — a known, narrow limitation
    consistent with this compiler having no block scoping, not a new gap
    this ticket introduces. }

function RParseExpr: Integer; forward;
function RParseBlock: Integer; forward;
function RParseStatement: Integer; forward;
function RParseIf: Integer; forward;
function RParseIfExpr: Integer; forward;
{ Called from RParseMatch (:1466) well above its own definition. pxx resolves
  names across the whole unit and FPC resolves them in SOURCE ORDER, so without
  this the file self-hosts perfectly and `compiler.pas` does not compile under
  FPC at all -- which breaks seeding a fresh tree that has no trusted binary
  yet. The per-fix loop structurally cannot catch that: `make compiler/pascal26`
  compiles the compiler WITH pxx, so the only compiler it ever consults is the
  one under test, and the byte-identical fixedpoint stays green throughout.
  `python3 tools/forwardlint.py` is what does catch it.
  bug-r-rexprrecid-breaks-the-fpc-bootstrap-seed }
function RExprRecId(node: Integer): Integer; forward;
{ RParseUnary's postfix `?` calls this well above its definition; same
  source-order rule as RExprRecId right above. }
function RParseTryOp(valNode: Integer): Integer; forward;
function RSpecializeGenericFn(gfi: Integer; const concreteTypeName: AnsiString): Integer; forward;
{ Both are used by RParseFormat, which sits above them because format! is an
  expression and the Debug expander is written next to println!. Same
  source-order rule as RExprRecId above. }
function RSpecIsDebug(fmtOff, start, len: Integer): Boolean; forward;
procedure RDebugExpand(recvNode, recId: Integer; const prefix: AnsiString); forward;

const
  RVAR_UNIT   = 0;
  RVAR_TUPLE  = 1;
  RVAR_STRUCT = 2;
  R_MAX_VARIANTS = 4096;
  R_MAX_ALIASES = 256;
  R_MAX_MATCH_ARMS = 64;

type
  TREnumVariant = record
    EnumCi: Integer;
    Name: AnsiString;
    Tag: Integer;
    Kind: Integer;
  end;
  TRMatchArm = record
    CondNode, BodyNode: Integer;
    IsWildcard: Boolean;
  end;

var
  REnumVariants: array[0..R_MAX_VARIANTS-1] of TREnumVariant;
  REnumVariantCount: Integer;
  REnumCi: array[0..MAX_UCLASS-1] of Boolean;
  { borrowed slices &a[lo..hi] (feature-rust-borrowed-slice-type, minimal):
    which UClasses are auto-registered __ptr+__len views + their element
    type — the Zig frontend's slice representation ported back. }
  RSliceCi: array[0..MAX_UCLASS-1] of Boolean;
  RSliceElemTk: array[0..MAX_UCLASS-1] of TTypeKind;
  { REC_UCLASS_BASE+ci of a record slice's element (REC_NONE for scalar slices) }
  RSliceElemRec: array[0..MAX_UCLASS-1] of Integer;
  { Option<T> (feature-rust-corpus-chess stage 2): monomorphized on demand,
    one auto-registered enum UClass per concrete T. Marked here as well as in
    REnumCi so the Some/None literal path can be resolved against an EXPECTED
    type instead of the global bare-variant table (every instantiation
    declares variants spelled `Some`/`None`, so the bare lookup is ambiguous
    by construction the moment a second T appears). }
  { serial for the compiler-generated locals that materialize a non-variable
    match/if-let scrutinee (`__scrut0`, ...); a Rust identifier cannot start
    with `__` followed by our digits by accident, and there is no block
    scoping to roll back into anyway. }
  RTempSerial: Integer;
  { Set only while the body of a `fmt` method under `impl fmt::Display` is
    being parsed. Inside it, two forms mean something they mean nowhere else:
    `write!(f, ..)` appends to the returned String, and `Ok(())` is a no-op.
    A narrow, clearly-delimited mode beats teaching those two spellings to the
    whole statement parser. }
  RInDisplayFmt: Boolean;
  { `{:?}` over a record, flattened to an alternating list: item i is the
    literal text RDbgText[i] followed by the field read RDbgNode[i] (-1 when
    the item is text only). A LIST, and not a rendered result, because the two
    consumers render differently and neither should learn the other's form:
    println! turns each item into a write, format! concatenates them. Global
    rather than a var parameter because both scanners parse every argument
    BEFORE they walk the format string, so there is no reentrancy to worry
    about -- a nested format! inside an argument is already finished. }
  RDbgText: array[0..255] of AnsiString;
  RDbgNode: array[0..255] of Integer;
  RDbgCount: Integer;
  ROptionCi: array[0..MAX_UCLASS-1] of Boolean;
  ROptionElemTk: array[0..MAX_UCLASS-1] of TTypeKind;
  ROptionElemRec: array[0..MAX_UCLASS-1] of Integer;
  { Result<T, E>, monomorphized the same way — see RResultClassForRec. }
  RResultCi: array[0..MAX_UCLASS-1] of Boolean;
  RResultOkTk: array[0..MAX_UCLASS-1] of TTypeKind;
  RResultOkRec: array[0..MAX_UCLASS-1] of Integer;
  RResultErrTk: array[0..MAX_UCLASS-1] of TTypeKind;
  RResultErrRec: array[0..MAX_UCLASS-1] of Integer;
  { Statements hoisted out of an EXPRESSION, to run before the statement that
    contains it. Today the only producer is the `?` try operator, which has to
    materialize its operand and can return early -- neither of which an
    expression node can express. RParseStatement is the single flush point,
    which is what makes this one mechanism rather than a special case per
    statement kind. -1 = nothing pending. }
  RPendingPreSeq: Integer;
  { `fn f() -> [T; N]` — the element COUNT, per proc; 0 = the return is not an
    array. Element kind lives in Procs[].RetType and element record id in
    ProcRetRecId, exactly as they do for Pascal's `function F: TArr`, so this
    is the one piece of shape the shared tables do not already carry in a form
    the Rust body parser can read back. (ProcRetFixedArrBytes carries the byte
    count, which is what the ABI needs and NOT enough to allocate the slot.) }
  RProcRetArrLen: array[0..MAX_PROCS-1] of Integer;
  { set by RRetTypeAt/RRetTypeCur as a side effect, in LastTypeRecId's style:
    the element count of a just-parsed `[T; N]` return type, 0 for any other. }
  RRetArrLen: Integer;
  { `[pub] type Alias = Target;` -- the corpus's `pub type Bitboard = u64;`.
    Recorded by RStripTopItems as the item is removed from the stream, and
    resolved in RTypeNameAt, which is the one canonical type-name reader:
    resolving THERE rather than in RTypeKindFromName means every downstream
    user (FindUClass, the record-id lookups, the array-element paths) sees the
    TARGET name and needs no alias knowledge of its own. Normalise rather than
    grow a second path.

    Narrowing: a SINGLE-TOKEN target only. `type M = Option<Square>;` or
    `type Row = [u8; 8];` still vanishes exactly as every alias did before, so
    this strictly widens what compiles and cannot break what did. }
  RAliasName: array[0..R_MAX_ALIASES-1] of AnsiString;
  RAliasTarget: array[0..R_MAX_ALIASES-1] of AnsiString;
  RAliasCount: Integer;
  { Module names declared by `mod x;` / `pub mod x;`. In a UNITY BUILD (the
    ladder's stage 3, the same trick test/zlib/runner.c uses) several modules
    are concatenated into one file, and everything then lives in ONE flat
    namespace -- but the source still says `attacks::knight(sq)` and
    `crate::board::Board::new()`. Concatenation does not fix that; the
    qualifiers have to go.

    Stripping needs to know which `Ident ::` prefixes are MODULES, because
    `Color::White` and `Board::new` are type paths and must survive. The crate
    root declares its modules, so `mod x;` is the answer and it is exact --
    no heuristic about capitalisation, and an unknown `foo::bar` still errors
    the way it should. `crate` / `self` / `super` are keywords and always go. }
  RModName: array[0..R_MAX_ALIASES-1] of AnsiString;
  RModCount: Integer;

  { Top-level `const NAME: [T; N] = [...]` — the corpus's attack tables, and
    the reason stage 3 is about data modules at all. Registered as a GLOBAL
    array by RRegisterTopConsts (CurProc < 0 at prescan time, so AllocArray
    puts it in BSS) with the element stores collected here, and prepended to
    `main`'s body.

    Deviation, deliberate and stated: Rust's `const` is a compile-time value
    that would live in .rodata; this one is a mutable global filled at startup.
    Every observable a compiling program has -- the values, their addresses
    being stable, reads from any function -- is the same, and the difference is
    a write nobody performs. Building real .rodata initializers is a shared-
    codegen job (Track A) and would buy nothing the engine can see. }
  RConstInitSeq: Integer;

function RResolveAlias(const name: AnsiString): AnsiString;
var i, hops: Integer; found: Boolean;
begin
  Result := name;
  { bounded, so `type A = B; type B = A;` cannot spin }
  for hops := 1 to R_MAX_ALIASES do
  begin
    found := False;
    for i := 0 to RAliasCount - 1 do
      if RAliasName[i] = Result then
      begin
        if RAliasTarget[i] = Result then Exit;
        Result := RAliasTarget[i];
        found := True;
        Break;
      end;
    if not found then Exit;
  end;
end;

function RIsModuleQualifier(const name: AnsiString): Boolean;
var i: Integer;
begin
  Result := (name = 'crate') or (name = 'self') or (name = 'super');
  if Result then Exit;
  for i := 0 to RModCount - 1 do
    if RModName[i] = name then begin Result := True; Exit; end;
end;

function RStoredName(const s: AnsiString): Integer;
var i: Integer;
begin
  Result := TokCharLen;
  for i := 1 to Length(s) do
  begin
    if TokCharLen >= STRING_CAP then Error('Rust: token char buffer overflow');
    TokChars[TokCharLen] := s[i];
    Inc(TokCharLen);
  end;
end;

function RIntToStr(n: Integer): AnsiString;
var rev, res: AnsiString; i: Integer;
begin
  rev := '';
  if n = 0 then AppendChar(rev, '0')
  else
    while n > 0 do
    begin
      AppendChar(rev, Chr(Ord('0') + (n mod 10)));
      n := n div 10;
    end;
  res := '';
  for i := Length(rev) downto 1 do AppendChar(res, rev[i]);
  Result := res;
end;

function RFindVariantBare(const name: AnsiString): Integer;
var i: Integer;
begin
  Result := -1;
  for i := 0 to REnumVariantCount - 1 do
    if CaseEqual(REnumVariants[i].Name, name) then begin Result := i; Exit; end;
end;

function RFindVariantInEnum(enumCi: Integer; const name: AnsiString): Integer;
var i: Integer;
begin
  Result := -1;
  for i := 0 to REnumVariantCount - 1 do
    if (REnumVariants[i].EnumCi = enumCi) and CaseEqual(REnumVariants[i].Name, name) then
    begin
      Result := i;
      Exit;
    end;
end;

{ ===== traits / impls / generic functions (feature-rust-generics-trait-bounds,
  sub-ticket 3/12) =====

  Same reuse-don't-extend-shared-internals approach as sub-ticket 2: no new
  AST node, no touch of the existing Pascal GenericFuncs/Specializations
  machinery in defs.inc (that pipeline is built around Pascal's explicit
  `specialize T<Concrete>` surface syntax and its own materialization path;
  Rust's generics are inferred-at-call-site, a different enough shape that a
  small private one made more sense than forcing a fit).

  - A trait is just a recorded name (RTraits) — "not a general
    trait-coherence solver": bound checking is pure membership in RImpls,
    it does not verify an impl actually provides every method a trait
    declares.
  - impl Type { fn m(&self, ...) { .. } } / impl Trait for Type { .. }:
    methods are ordinary functions with a mangled name ("Type::m",
    RegisterProc'd two-pass exactly like free functions) and a hidden
    `self` parameter passed as a tyRecord pointer (the existing
    Pascal var-record-parameter ABI already passes any tyRecord by address
    — see ParamSize's TARGET_PTR_SIZE branch — so `&self`/`self` field
    reads/writes need no new codegen). `impl Trait for Type` additionally
    records (TypeCi, TraitName) in RImpls.
  - A generic fn (`fn f<T: Bound>(x: T) -> T`) is never compiled directly:
    its token range is buffered (RGenericFuncs), and each call site
    triggers specialization by copying that token range to the end of the
    shared Tokens[] buffer with every occurrence of `T` textually replaced
    by the concrete type name, then compiling that copy exactly like a
    normal top-level fn (mangled "f$Point"), memoized so a second call with
    the same concrete type reuses the specialization via a plain FindProc.
  - Deliberate narrowing, documented not dropped: generic FUNCTIONS only,
    not generic STRUCTS (`struct Box<T>`) — a struct specialization needs a
    whole new UClass per concrete type, a materially separate feature axis
    from function specialization; T is inferred from the first parameter
    only (no cross-checking against other T-typed params/return — they are
    textually identical after substitution, so they can't disagree); one
    type parameter per generic fn (no `<T, U>`). }

const
  R_MAX_TRAITS = 256;
  R_MAX_IMPLS = 1024;
  R_MAX_GENERIC_FUNCS = 64;
  R_MAX_BOUNDS = 4;

type
  TRImpl = record
    TypeCi: Integer;
    TraitName: AnsiString;
  end;
  TRGenericFunc = record
    Name, ParamName: AnsiString;
    TokStart, TokCount: Integer;
    { literal 3: record-field array bounds can't use R_MAX_BOUNDS-1 under
      PXX self-host (same const-expr gap as TProc.Params — see defs.inc);
      keep in sync with R_MAX_BOUNDS = 4. }
    Bounds: array[0..3] of AnsiString;
    BoundCount: Integer;
  end;

var
  { current `impl TypeName` context — lets `Self` resolve in method
    bodies/signatures (empty outside an impl block) }
  RCurImplType: AnsiString;
  RTraits: array[0..R_MAX_TRAITS-1] of AnsiString;
  RTraitCount: Integer;
  RImpls: array[0..R_MAX_IMPLS-1] of TRImpl;
  RImplCount: Integer;
  RGenericFuncs: array[0..R_MAX_GENERIC_FUNCS-1] of TRGenericFunc;
  RGenericFuncCount: Integer;

function RScalarTypeName(tk: TTypeKind): AnsiString;
begin
  case tk of
    tyInt8: Result := 'i8';
    tyUInt8: Result := 'u8';
    tyInt16: Result := 'i16';
    tyUInt16: Result := 'u16';
    tyInteger: Result := 'i32';
    tyInt64: Result := 'i64';
    tyUInt32: Result := 'u32';
    tyUInt64: Result := 'u64';
    tyNativeInt: Result := 'isize';
    tyNativeUInt: Result := 'usize';
    tySingle: Result := 'f32';
    tyDouble: Result := 'f64';
    tyBoolean: Result := 'bool';
    tyChar: Result := 'char';
    else Result := '?';
  end;
end;

{ One auto-registered UClass per slice element type ("&[i64]"): __ptr (raw
  element address as i64 @0) + __len (i64 @8) — 16 bytes. elemRec is the
  element's REC_UCLASS_BASE+ci for a record/tuple-struct element, or REC_NONE
  for a scalar element (`&[i64]`); it names the slice by class and is stamped
  on the AN_DEREF of `slice[i]` so `slice[i].field` resolves. }
function RSliceClassForRec(elemTk: TTypeKind; elemRec: Integer): Integer;
var name: AnsiString; ci: Integer;
begin
  if (elemTk = tyRecord) and (elemRec >= REC_UCLASS_BASE) then
    name := '&[rec' + RIntToStr(elemRec) + ']'
  else
    name := '&[' + RScalarTypeName(elemTk) + ']';
  ci := FindUClass(name);
  if ci < 0 then
  begin
    ci := AddUClass(RStoredName(name), Length(name));
    UClsIsRecord[ci] := True;
    AddUField(ci, RStoredName('__ptr'), 5, 0, Ord(tyInt64), REC_NONE);
    AddUField(ci, RStoredName('__len'), 5, 8, Ord(tyInt64), REC_NONE);
    UClsAlign[ci] := 8;
    UClsSize_[ci] := 16;
    RSliceCi[ci] := True;
    RSliceElemTk[ci] := elemTk;
    RSliceElemRec[ci] := elemRec;
  end;
  Result := ci;
end;

function RSliceClassFor(elemTk: TTypeKind): Integer;
begin
  Result := RSliceClassForRec(elemTk, REC_NONE);
end;

{ One auto-registered enum UClass per concrete `Option<T>` — the ladder's
  stage-2 "monomorphized generic enum". Layout is exactly what a hand-written
  `enum OptionI64 { None, Some(i64) }` gets from RRegisterEnums: __tag (i64)
  at 0, the payload as the mangled field "Some.0" at the first aligned offset
  past it. Tags follow Rust's declaration order (None = 0, Some = 1), so a
  zeroed slot reads as None. Registering the two variants in REnumVariants is
  what makes `match` work with no further change: RParseMatch resolves arm
  names with RFindVariantInEnum against the scrutinee's own class. }
{ A monomorphized generic's payload occupies its OWN full size, and for a
  record that is RecSize. `TypeSlotSize(tyRecord)` answers 8 -- a pointer -- and
  says so in its own comment in symtab.inc: *caller must use RecSize() for full
  record size*. Getting it wrong does not fail loudly; the union is simply too
  small and the payload's tail is written past the end of the value.

  `Option<Square>` survived that for a whole rung because Square is exactly 8
  bytes. `Result<Pos, i64>` did not: `Pos { file: 4, rank: 2 }` read back as
  `4 0`, with `rank` landing outside the class. Which is the same shape as
  every other expensive bug here -- a plausible wrong value, not a crash. }
function RPayloadSize(tk: TTypeKind; rec: Integer): Integer;
begin
  if (tk = tyRecord) and (rec >= REC_UCLASS_BASE) then Result := RecSize(rec)
  else Result := TypeSlotSize(tk);
end;

function RPayloadAlign(tk: TTypeKind; rec: Integer): Integer;
begin
  if (tk = tyRecord) and (rec >= REC_UCLASS_BASE) then
  begin
    Result := UClsAlign[rec - REC_UCLASS_BASE];
    if Result <= 0 then Result := 8;
  end
  else Result := TypeAlign(tk);
end;

function ROptionClassForRec(elemTk: TTypeKind; elemRec: Integer): Integer;
var name: AnsiString; ci, vi, payOff, align: Integer;
begin
  if (elemTk = tyRecord) and (elemRec >= REC_UCLASS_BASE) then
    name := 'Option<rec' + RIntToStr(elemRec) + '>'
  else
    name := 'Option<' + RScalarTypeName(elemTk) + '>';
  ci := FindUClass(name);
  if ci < 0 then
  begin
    ci := AddUClass(RStoredName(name), Length(name));
    UClsIsRecord[ci] := True;
    REnumCi[ci] := True;
    ROptionCi[ci] := True;
    ROptionElemTk[ci] := elemTk;
    ROptionElemRec[ci] := elemRec;
    AddUField(ci, RStoredName('__tag'), 5, 0, Ord(tyInt64), REC_NONE);
    align := 8;
    if RPayloadAlign(elemTk, elemRec) > align then align := RPayloadAlign(elemTk, elemRec);
    payOff := AlignTo(8, RPayloadAlign(elemTk, elemRec));
    AddUField(ci, RStoredName('Some.0'), 6, payOff, Ord(elemTk), elemRec);
    UClsAlign[ci] := align;
    UClsSize_[ci] := AlignTo(payOff + RPayloadSize(elemTk, elemRec), align);
    if REnumVariantCount + 2 > R_MAX_VARIANTS then Error('Rust: too many enum variants');
    vi := REnumVariantCount; Inc(REnumVariantCount);
    REnumVariants[vi].EnumCi := ci;
    REnumVariants[vi].Name := 'None';
    REnumVariants[vi].Tag := 0;
    REnumVariants[vi].Kind := RVAR_UNIT;
    vi := REnumVariantCount; Inc(REnumVariantCount);
    REnumVariants[vi].EnumCi := ci;
    REnumVariants[vi].Name := 'Some';
    REnumVariants[vi].Tag := 1;
    REnumVariants[vi].Kind := RVAR_TUPLE;
  end;
  Result := ci;
end;

{ `Result<T, E>` — the same monomorphize-onto-the-enum-machinery trick
  ROptionClassForRec uses, with TWO payload variants instead of one and a
  half. Ok.0 and Err.0 live at the SAME offset: that is what a tagged union is,
  and it is what the hand-written `enum Shape` path already builds, so nothing
  downstream needs to know Result exists any more than it needed to know Option
  did.

  Tags follow the declaration order Rust writes them in, Ok = 0 and Err = 1,
  rather than Option's None = 0 / Some = 1. Nothing depends on the numbers
  matching across the two — a tag is only ever compared against its own
  class's variant table — but they are worth stating because "the payload one
  is 1" would be a plausible and wrong thing to assume from Option alone. }
function RResultClassForRec(okTk: TTypeKind; okRec: Integer;
                            errTk: TTypeKind; errRec: Integer): Integer;
var name: AnsiString; ci, vi, payOff, align, endOff: Integer;

  function ArgName(tk: TTypeKind; rec: Integer): AnsiString;
  begin
    if (tk = tyRecord) and (rec >= REC_UCLASS_BASE) then
      ArgName := 'rec' + RIntToStr(rec)
    else
      ArgName := RScalarTypeName(tk);
  end;

begin
  name := 'Result<' + ArgName(okTk, okRec) + ',' + ArgName(errTk, errRec) + '>';
  ci := FindUClass(name);
  if ci < 0 then
  begin
    ci := AddUClass(RStoredName(name), Length(name));
    UClsIsRecord[ci] := True;
    REnumCi[ci] := True;
    RResultCi[ci] := True;
    RResultOkTk[ci] := okTk;
    RResultOkRec[ci] := okRec;
    RResultErrTk[ci] := errTk;
    RResultErrRec[ci] := errRec;
    AddUField(ci, RStoredName('__tag'), 5, 0, Ord(tyInt64), REC_NONE);
    align := 8;
    if RPayloadAlign(okTk, okRec) > align then align := RPayloadAlign(okTk, okRec);
    if RPayloadAlign(errTk, errRec) > align then align := RPayloadAlign(errTk, errRec);
    payOff := AlignTo(8, align);
    AddUField(ci, RStoredName('Ok.0'), 4, payOff, Ord(okTk), okRec);
    AddUField(ci, RStoredName('Err.0'), 5, payOff, Ord(errTk), errRec);
    endOff := payOff + RPayloadSize(okTk, okRec);
    if payOff + RPayloadSize(errTk, errRec) > endOff then
      endOff := payOff + RPayloadSize(errTk, errRec);
    UClsAlign[ci] := align;
    UClsSize_[ci] := AlignTo(endOff, align);
    if REnumVariantCount + 2 > R_MAX_VARIANTS then Error('Rust: too many enum variants');
    vi := REnumVariantCount; Inc(REnumVariantCount);
    REnumVariants[vi].EnumCi := ci;
    REnumVariants[vi].Name := 'Ok';
    REnumVariants[vi].Tag := 0;
    REnumVariants[vi].Kind := RVAR_TUPLE;
    vi := REnumVariantCount; Inc(REnumVariantCount);
    REnumVariants[vi].EnumCi := ci;
    REnumVariants[vi].Name := 'Err';
    REnumVariants[vi].Tag := 1;
    REnumVariants[vi].Kind := RVAR_TUPLE;
  end;
  Result := ci;
end;

function RIsResultRec(recId: Integer): Boolean;
begin
  Result := (recId >= REC_UCLASS_BASE) and RResultCi[recId - REC_UCLASS_BASE];
end;

function RIsOptionRec(recId: Integer): Boolean;
begin
  Result := (recId >= REC_UCLASS_BASE) and ROptionCi[recId - REC_UCLASS_BASE];
end;

function RIsSliceRec(recId: Integer): Boolean;
begin
  Result := (recId >= REC_UCLASS_BASE) and RSliceCi[recId - REC_UCLASS_BASE];
end;

{ Is `recId`'s field `name` a fixed array (`squares: [i64; 64]`)? }
function RFieldIsArray(recId: Integer; const name: AnsiString): Boolean;
var fi: Integer;
begin
  Result := False;
  if recId < REC_UCLASS_BASE then Exit;
  fi := FindUField(recId - REC_UCLASS_BASE, name);
  Result := (fi >= 0) and UFldIsArray[fi];
end;

{ Its element count, or 0 when the field is not a fixed array. }
function RFieldArrLen(recId: Integer; const name: AnsiString): Integer;
var fi: Integer;
begin
  Result := 0;
  if recId < REC_UCLASS_BASE then Exit;
  fi := FindUField(recId - REC_UCLASS_BASE, name);
  if (fi >= 0) and UFldIsArray[fi] then Result := UFldArrLen[fi];
end;

function RIsSliceSym(symIdx: Integer): Boolean;
var rsCi: Integer;
begin
  { SymOwnClassIdx, not the RecName read this used to spell out: an ARRAY of
    slices carries TypeKind = tyRecord too (the field holds the ELEMENT's kind),
    so the old three lines asked "is the ELEMENT a slice" while the name says
    "is this symbol a slice". They answered correctly only because AllocArray
    clears RecName -- a mask, not a guard.
    audit-a-typekind-tyrecord-is-not-a-guard-against-an-array-symbol }
  rsCi := SymOwnClassIdx(symIdx);
  Result := (rsCi >= 0) and RSliceCi[rsCi];
end;

{ True when the bracket run starting at Tokens[k] (a `[`) contains a
  top-level `..` — slice range, not an index. }
function RBrackHasDotDotAt(k: Integer): Boolean;
var depth: Integer;
begin
  Result := False;
  depth := 1;
  Inc(k);
  while (depth > 0) and (Tokens[k].Kind <> tkEOF) do
  begin
    if Tokens[k].Kind = tkLBrack then Inc(depth)
    else if Tokens[k].Kind = tkRBrack then Dec(depth)
    else if (Tokens[k].Kind = tkDotDot) and (depth = 1) then
    begin
      Result := True;
      Exit;
    end;
    Inc(k);
  end;
end;

{ Traits that need no `trait` declaration in the source because the frontend
  knows them. `Display` is the one with behaviour attached (its `fmt` is
  rerouted, see RRegisterImpls); the rest are here so `impl Default for X` and
  friends register their methods as ordinary mangled procs instead of failing
  on an unknown trait. }
function RIsBuiltinTrait(const name: AnsiString): Boolean;
begin
  Result := (name = 'Display') or (name = 'Debug') or (name = 'Default') or
            (name = 'Clone') or (name = 'Copy') or (name = 'PartialEq') or
            (name = 'Eq') or (name = 'PartialOrd') or (name = 'Ord') or
            (name = 'From') or (name = 'Into');
end;

function RFindTrait(const name: AnsiString): Integer;
var i: Integer;
begin
  Result := -1;
  for i := 0 to RTraitCount - 1 do
    if CaseEqual(RTraits[i], name) then begin Result := i; Exit; end;
end;

function RTypeImplementsTrait(ci: Integer; const traitName: AnsiString): Boolean;
var i: Integer;
begin
  Result := False;
  for i := 0 to RImplCount - 1 do
    if (RImpls[i].TypeCi = ci) and CaseEqual(RImpls[i].TraitName, traitName) then
    begin
      Result := True;
      Exit;
    end;
end;

function RFindGenericFunc(const name: AnsiString): Integer;
var i: Integer;
begin
  Result := -1;
  for i := 0 to RGenericFuncCount - 1 do
    if CaseEqual(RGenericFuncs[i].Name, name) then begin Result := i; Exit; end;
end;

function RTypeNameOf(ci: Integer): AnsiString;
begin
  Result := GetTokenStrFromRaw(UClsNOff[ci], UClsNLen[ci]);
end;

{ Consumes an already-open `<...>` clause via CurTok/Next (CurTok must be
  tkLt on entry); leaves CurTok on the token after the matching `>`. }
procedure RSkipAngleClause;
var depth: Integer;
begin
  depth := 1; Next;
  while depth > 0 do
  begin
    if CurTok.Kind = tkLt then Inc(depth)
    else if CurTok.Kind = tkGt then Dec(depth);
    if depth > 0 then Next;
  end;
  Next; { consume the matching > }
end;

{ Set only while the single statement of a BARE (unbraced) match arm is
  being parsed -- `Some(v) => n = v,` has no `;`, its terminator is the arm
  comma or the match's closing brace. RParseBlock clears it for the duration
  of any nested block, so the leniency does not leak into `{ ... }` bodies. }
var RInMatchArm: Boolean;

{ Set only for the statements of a fn BODY, so Rust's implicit tail return
  applies there and ONLY there. An inner block's trailing expression is a
  BLOCK VALUE, which this frontend does not model -- treating one as a return
  would silently turn `if c { f() }` into an early exit from the function. }
var RTailOK: Boolean;

procedure RExpectStmtEnd;
begin
  if RInMatchArm and (CurTok.Kind <> tkSemicolon) then Exit;
  Expect(tkSemicolon, ';');
end;

function RSeqAppend(head, stmt: Integer): Integer;
var tail: Integer;
begin
  Result := head;
  if stmt < 0 then Exit;
  if Result < 0 then
  begin
    Result := AllocNode(AN_SEQ);
    ASTLeft[Result] := stmt;
    ASTRight[Result] := -1;
    Exit;
  end;
  tail := Result;
  while ASTRight[tail] >= 0 do tail := ASTRight[tail];
  ASTRight[tail] := AllocNode(AN_SEQ);
  tail := ASTRight[tail];
  ASTLeft[tail] := stmt;
  ASTRight[tail] := -1;
end;

function RMakeIdent(symIdx: Integer): Integer;
begin
  Result := AllocNode(AN_IDENT);
  ASTIVal[Result] := symIdx;
  ASTTk[Result] := Ord(Syms[symIdx].TypeKind);
end;

{ Rust type name -> TTypeKind. Sets LastTypeRecId when the name is a known
  struct (the AllocVar/AddUField convention every frontend already uses to
  pass a record id alongside tyRecord). allowStruct=False rejects struct
  names — used for fn params/return types, keeping the call ABI scalar-only
  for this skeleton; allowStruct=True is for `let` annotations and struct
  fields (nested value-type structs are fine, they're just bytes). }
function RTypeKindFromName(const name: AnsiString; allowStruct: Boolean): TTypeKind;
var ci: Integer;
begin
  if (name = 'Self') and (RCurImplType <> '') then
  begin
    Result := RTypeKindFromName(RCurImplType, allowStruct);
    Exit;
  end;
  LastTypeRecId := REC_NONE;
  if name = 'i8' then begin Result := tyInt8; Exit; end;
  if name = 'u8' then begin Result := tyUInt8; Exit; end;
  if name = 'i16' then begin Result := tyInt16; Exit; end;
  if name = 'u16' then begin Result := tyUInt16; Exit; end;
  if name = 'i32' then begin Result := tyInteger; Exit; end;
  if name = 'i64' then begin Result := tyInt64; Exit; end;
  if name = 'u32' then begin Result := tyUInt32; Exit; end;
  if name = 'u64' then begin Result := tyUInt64; Exit; end;
  if name = 'isize' then begin Result := tyNativeInt; Exit; end;
  if name = 'usize' then begin Result := tyNativeUInt; Exit; end;
  if name = 'f32' then begin Result := tySingle; Exit; end;
  if name = 'f64' then begin Result := tyDouble; Exit; end;
  if name = 'bool' then begin Result := tyBoolean; Exit; end;
  if name = 'char' then begin Result := tyChar; Exit; end;
  if (name = 'String') or (name = 'str') then begin Result := tyAnsiString; Exit; end;
  ci := FindUClass(name);
  if ci >= 0 then
  begin
    if not allowStruct then
      Error('Rust: struct-typed parameters/return values are not supported by the frontend skeleton yet (feature-rust-frontend-skeleton)');
    LastTypeRecId := REC_UCLASS_BASE + ci;
    Result := tyRecord;
    Exit;
  end;
  Error('Rust: unknown type ' + name);
  Result := tyUnknown;
end;

{ Reads a type at token index j, advances j past it, and returns the
  CANONICAL name to hand to RTypeKindFromName. Only generic form handled is
  `Option<T>`, which registers the concrete instantiation as a side effect and
  answers with that class's name — so every type site in the frontend gains
  Option support by routing its `GetTokenStr(j)` through here, without any of
  them learning what a generic is. }
function RTypeNameAt(var j: Integer): AnsiString;
var innerTk, okTk, errTk: TTypeKind; innerRec, okRec, errRec, ci: Integer;
begin
  if Tokens[j].Kind <> tkIdent then Error('Rust: expected a type name');
  { an alias resolves to its target HERE, so nothing downstream has to know
    aliases exist -- see the RAliasName note }
  Result := RResolveAlias(GetTokenStr(j));
  if (Result = 'Option') and (Tokens[j + 1].Kind = tkLt) then
  begin
    Inc(j, 2);
    { sequence the side-effecting RTypeKindFromName (sets LastTypeRecId)
      before reading LastTypeRecId -- do NOT rely on arg eval order. }
    innerTk := RTypeKindFromName(RTypeNameAt(j), True);
    innerRec := LastTypeRecId;
    if Tokens[j].Kind = tkShr then
      Error('Rust: nested Option<Option<T>> is not supported yet (the >> lexes as a shift)');
    if Tokens[j].Kind <> tkGt then Error('Rust: expected > closing Option<');
    Inc(j);
    ci := ROptionClassForRec(innerTk, innerRec);
    Result := RTypeNameOf(ci);
  end
  else if (Result = 'Result') and (Tokens[j + 1].Kind = tkLt) then
  begin
    { `Result<T, E>` — two params, otherwise the same monomorphize-on-demand
      as Option. Each argument's kind and record id are captured immediately
      after its own RTypeKindFromName call, because that call is what sets
      LastTypeRecId and the second one would otherwise clobber the first. }
    Inc(j, 2);
    okTk := RTypeKindFromName(RTypeNameAt(j), True);
    okRec := LastTypeRecId;
    if Tokens[j].Kind <> tkComma then Error('Rust: expected , between Result<T, E> parameters');
    Inc(j);
    errTk := RTypeKindFromName(RTypeNameAt(j), True);
    errRec := LastTypeRecId;
    if Tokens[j].Kind = tkShr then
      Error('Rust: a nested generic closing with >> is not supported yet (the >> lexes as a shift)');
    if Tokens[j].Kind <> tkGt then Error('Rust: expected > closing Result<');
    Inc(j);
    ci := RResultClassForRec(okTk, okRec, errTk, errRec);
    Result := RTypeNameOf(ci);
  end
  else
    Inc(j);
end;

{ Cursor-based twin of RTypeNameAt: CurTok must be the type's first token; on
  return CurTok is the token after the type. }
function RTypeNameCur: AnsiString;
var j: Integer;
begin
  j := TokPos - 1;
  Result := RTypeNameAt(j);
  TokPos := j;
  Next;
end;

{ The return-type clause after `->`, in RTypeNameAt's index form. Handles the
  ordinary `-> T` and the FIXED-ARRAY `-> [T; N]`, returning the element kind
  in both cases and setting RRetArrLen to N (0 when it was not an array).

  Rust spells the array type inline where Pascal needs a named one, but what it
  lowers to is the ABI Pascal's `function F: TArr` has used since
  bug-a-set-and-array-function-results-come-back-empty, unchanged:
  Procs[].RetType holds the ELEMENT kind, the aggregate nature lives in
  ProcRetFixedArrBytes, and ABIRetViaHiddenDestProc joins the two so the caller
  allocates the scratch and the callee's epilogue copies into it. The kind
  alone cannot show the aggregate -- that is the whole reason the byte count is
  recorded separately -- so an array return that skips ProcRetFixedArrBytes
  does not fail loudly, it returns one element's width and leaves the rest
  garbage.

  Which makes this the third rung running where the shared machinery already
  had the mechanism and the Rust frontend had simply never reached for it
  (record returns and &mut aliasing were the other two). }
function RRetTypeAt(var j: Integer): TTypeKind;
var n: Integer;
begin
  RRetArrLen := 0;
  if Tokens[j].Kind = tkLBrack then
  begin
    Inc(j);
    if Tokens[j].Kind <> tkIdent then Error('Rust: expected element type in [T; N] return');
    Result := RTypeKindFromName(RTypeNameAt(j), True);
    if Tokens[j].Kind <> tkSemicolon then Error('Rust: expected ; in [T; N] return type');
    Inc(j);
    if Tokens[j].Kind <> tkInteger then Error('Rust: array return length must be an integer literal');
    n := Tokens[j].IVal;
    if n <= 0 then Error('Rust: array return length must be positive');
    Inc(j);
    if Tokens[j].Kind <> tkRBrack then Error('Rust: expected ] closing a [T; N] return type');
    Inc(j);
    RRetArrLen := n;
    Exit;
  end;
  if Tokens[j].Kind <> tkIdent then Error('Rust: expected return type after ->');
  Result := RTypeKindFromName(RTypeNameAt(j), True);
end;

{ Cursor-based twin, mirroring RTypeNameCur: CurTok must be the token after
  `->`; on return CurTok is the token after the type. }
function RRetTypeCur: TTypeKind;
var j: Integer;
begin
  j := TokPos - 1;
  Result := RRetTypeAt(j);
  TokPos := j;
  Next;
end;

{ Record a fixed-array return's shape on the proc. Called from the SIGNATURE
  prepass rather than from the body, and that is load-bearing: a call site is
  lowered while the CALLER's body is parsed, which may be long before the
  callee's own body is reached, and IRBuildHiddenDest reads
  ProcRetFixedArrBytes at that moment. Set it at body time instead and
  `fn main` placed above its callee silently gets the scalar path. }
procedure RNoteRetArray(procIdx, n: Integer; elemTk: TTypeKind; elemRec: Integer);
var sz: Integer;
begin
  if n <= 0 then Exit;
  RProcRetArrLen[procIdx] := n;
  sz := TypeStorageSize(elemTk, elemRec);
  ProcRetFixedArrBytes[procIdx] := n * sz;
end;

{ Non-consuming, in RPeekAggregateCi's style: is the cursor at a call whose
  callee returns `[T; N]`? Answers from the REGISTERED signature rather than by
  parsing speculatively and rewinding, which is what lets `let t = attacks();`
  -- the form real source is written in -- allocate the right shape before the
  expression exists. -1 when it is not one.

  Both spellings, because both appear in the engine: a plain `f()` and a method
  `recv.m()`, the latter resolved through the receiver's class to the mangled
  `Type::method`. Narrowing: the receiver must be a plain record VARIABLE, the
  same limit every other place in this file that needs a static record type
  without a general node-type resolver. }
function RPeekArrayRetProc: Integer;
var symIdx: Integer;
begin
  Result := -1;
  if CurTok.Kind <> tkIdent then Exit;
  if Tokens[TokPos].Kind = tkLParen then
    Result := FindProc(CurTok.SVal)
  else if (Tokens[TokPos].Kind = tkDot) and (Tokens[TokPos + 1].Kind = tkIdent) and
          (Tokens[TokPos + 2].Kind = tkLParen) then
  begin
    symIdx := FindSym(CurTok.SVal);
    if (symIdx < 0) or (Syms[symIdx].RecName < REC_UCLASS_BASE) then Exit;
    Result := FindProc(RTypeNameOf(Syms[symIdx].RecName - REC_UCLASS_BASE) +
                       '::' + GetTokenStr(TokPos + 1));
  end;
  if (Result >= 0) and (RProcRetArrLen[Result] = 0) then Result := -1;
end;

function RIsStrTk(tk: TTypeKind): Boolean;
begin
  Result := (tk = tyAnsiString) or (tk = tyString);
end;

function RWiden(a, b: TTypeKind): TTypeKind;
begin
  { A string operand makes the result a MANAGED string. `+` is the only
    arithmetic operator Rust defines over strings, but the arm lives here
    rather than at the `+` site because RWiden is the one place every binary
    operator asks for its result type -- a second place is the one that stays
    wrong. The literal kind is tyString and the variable kind is tyAnsiString;
    the result is always the managed one, which is exactly what Pascal's own
    lowering does (`const_str tk=4` feeding a `store_sym tk=23`). }
  if RIsStrTk(a) or RIsStrTk(b) then Result := tyAnsiString
  else if (a = tyDouble) or (b = tyDouble) or (a = tySingle) or (b = tySingle) then Result := tyDouble
  else if (a = tyInt64) or (b = tyInt64) then Result := tyInt64
  else Result := tyInteger;
end;

function RBinOp(opTk: TTokenKind; left, right: Integer; resultTk: TTypeKind): Integer;
var node: Integer;
begin
  node := AllocNode(AN_BINOP);
  ASTIVal[node] := Ord(opTk);
  ASTLeft[node] := left;
  ASTRight[node] := right;
  ASTTk[node] := Ord(resultTk);
  Result := node;
end;

{ Concrete type name for a generic-function call-site argument (used as the
  specialization key / substituted into the buffered generic body). Scalar
  types map back to their Rust spelling; a struct/enum argument must be a
  plain variable (same narrowing as everywhere else a static record type is
  needed without a general "resolve this AST node's type" helper). }
function RConcreteTypeNameForArg(argNode: Integer): AnsiString;
begin
  case IntToTypeKind(ASTTk[argNode]) of
    tyInteger: Result := 'i32';
    tyInt64: Result := 'i64';
    tyUInt32: Result := 'u32';
    tyUInt64: Result := 'u64';
    tyNativeInt: Result := 'isize';
    tyNativeUInt: Result := 'usize';
    tySingle: Result := 'f32';
    tyDouble: Result := 'f64';
    tyBoolean: Result := 'bool';
    tyChar: Result := 'char';
    tyRecord:
    begin
      if ASTKind[argNode] <> AN_IDENT then
        Error('Rust: a struct/enum argument to a generic function must be a plain variable for now');
      Result := RTypeNameOf(Syms[ASTIVal[argNode]].RecName - REC_UCLASS_BASE);
    end;
    else
    begin
      Error('Rust: unsupported argument type for generic function type inference');
      Result := '';
    end;
  end;
end;

{ o.is_some() / o.is_none() / o.unwrap() / o.unwrap_or(d) over an Option<T>
  whose VALUE is `baseNode` -- a plain variable, a record field, an array
  element, anything that is an lvalue. Pure field reads off the tagged union
  plus, for unwrap_or, the shared AN_TERNARY the C and Zig frontends use for
  `?:` / `orelse`; no RTL call and no new AST node.

  `unwrap()` does NOT panic on None (it reads the payload slot as-is): this
  frontend has no panic path yet, and a checked unwrap is a follow-up once one
  exists. Documented in the ticket, not silent.

  The base node is REUSED as the receiver of both reads in unwrap_or, which is
  safe for the same reason the compound-assign desugar reuses its target: an
  lvalue here is a pure address chain with no side effects to repeat.

  CurTok must be the method name on entry; the whole call is consumed. }
function RIsOptionAccessorName(const m: AnsiString): Boolean;
begin
  Result := (m = 'is_some') or (m = 'is_none') or (m = 'unwrap') or (m = 'unwrap_or');
end;

{ A field node on an enum value: the `__tag` or a mangled payload
  (`Some.0`, `Err.0`, `Circle.w`). Named for Option when Option was the only
  monomorphized generic here; it was never Option-specific and Result uses it
  unchanged. }
function REnumField(baseNode, enumRec: Integer; const fname: AnsiString): Integer;
begin
  Result := AllocNode(AN_FIELD);
  ASTLeft[Result] := baseNode;
  ASTSOffset[Result] := RStoredName(fname); ASTSLen[Result] := Length(fname);
  if fname = '__tag' then ASTTk[Result] := Ord(tyInt64)
  else ASTTk[Result] := Ord(RecFieldType(enumRec, fname));
end;

function RParseOptionAccessor(baseNode, optRec: Integer): Integer;
var mname: AnsiString; argNode, pairNode: Integer;
begin
  mname := CurTok.SVal;
  Next; Next; { method name, ( }
  if mname = 'unwrap_or' then
  begin
    argNode := RParseExpr;
    Expect(tkRParen, ')');
    pairNode := AllocNode(AN_PAIR);
    ASTLeft[pairNode] := REnumField(baseNode, optRec, 'Some.0');
    ASTRight[pairNode] := argNode;
    argNode := AllocNode(AN_INT_LIT); ASTIVal[argNode] := 1; ASTTk[argNode] := Ord(tyInt64);
    Result := AllocNode(AN_TERNARY);
    ASTLeft[Result] := RBinOp(tkEq, REnumField(baseNode, optRec, '__tag'),
                              argNode, tyBoolean);
    ASTRight[Result] := pairNode;
    ASTTk[Result] := Ord(RecFieldType(optRec, 'Some.0'));
    Exit;
  end;
  Expect(tkRParen, ')');
  if mname = 'unwrap' then
  begin
    Result := REnumField(baseNode, optRec, 'Some.0');
    Exit;
  end;
  argNode := AllocNode(AN_INT_LIT); ASTTk[argNode] := Ord(tyInt64);
  if mname = 'is_some' then ASTIVal[argNode] := 1 else ASTIVal[argNode] := 0;
  Result := RBinOp(tkEq, REnumField(baseNode, optRec, '__tag'), argNode, tyBoolean);
end;

{ ===== Strings =====

  `String` and `&str` BOTH map to pxx's managed AnsiString. That is a real
  divergence from Rust, where one owns its buffer and the other borrows, and it
  is invisible for the same reason the const-array one is: the observation
  requires aliasing a string and mutating through one of the aliases, which is
  exactly what rustc's borrow checker refuses. A program rustc accepts cannot
  tell them apart, so carrying two representations would buy nothing and cost
  the whole borrow-tracking machinery this frontend does not have.

  The managed representation is what makes concatenation, comparison, length
  and refcounting free: they are the shared lowering's, already written and
  already gated by every Pascal and NilPy test in the tree. What the frontend
  supplies is spelling.

  Note the two kinds. A literal is tyString (the const_str node kind) and a
  variable is tyAnsiString; `RWiden` answers tyAnsiString for any mix, which is
  precisely the shape Pascal's own lowering emits. `RIsStrTk` is the test that
  must be used wherever "is this a string" is asked -- checking tyAnsiString
  alone silently drops every literal. }

{ `impl fmt::Display for X` registered `X::fmt(&self) -> String` (see
  RRegisterImpls). This is how every rendering path asks whether a record has
  one, and builds the call if it does -- `{}` in println!/format!, and
  `.to_string()`. Returns -1 when the type has no Display, which is what makes
  `{}` on a plain struct an error instead of a silent first-field write. }
function RDisplayCall(recvNode, recId: Integer): Integer;
var procIdx, argNode: Integer;
begin
  Result := -1;
  if recId < REC_UCLASS_BASE then Exit;
  procIdx := FindProc(RTypeNameOf(recId - REC_UCLASS_BASE) + '::fmt');
  if procIdx < 0 then Exit;
  Result := AllocNode(AN_CALL);
  ASTIVal[Result] := procIdx;
  ASTTk[Result] := Ord(tyAnsiString);
  argNode := AllocNode(AN_ARG);
  ASTLeft[argNode] := recvNode; ASTRight[argNode] := -1;
  ASTLeft[Result] := argNode;
end;

{ A literal string as an AST node. Three callers wanted their own copy of
  these four lines before it was lifted. }
function RStrLit(const t: AnsiString): Integer;
begin
  Result := AllocNode(AN_STR_LIT);
  ASTSOffset[Result] := RStoredName(t); ASTSLen[Result] := Length(t);
  ASTTk[Result] := Ord(tyString);
end;

function RIsStrMethodName(const m: AnsiString): Boolean;
begin
  Result := (m = 'len') or (m = 'is_empty') or (m = 'push_str') or
            (m = 'push') or (m = 'as_str') or (m = 'to_string') or
            (m = 'to_owned') or (m = 'clone') or (m = 'into');
end;

{ Does `recvTk.m()` belong to RParseStrMethod rather than to the ordinary
  record-method path? Two ways in, and the second is the reason this is a
  function and not an inline conjunction at both call sites: `to_string()` is
  also how a NUMBER becomes a string, so it must fire on a non-string receiver
  too. Not on a record or a class, though -- `impl Piece { fn to_string(&self) }`
  is ordinary Rust and stealing it would replace a user's own rendering with a
  number, silently. }
function RStrMethodApplies(recvTk: TTypeKind; recId: Integer; const m: AnsiString): Boolean;
begin
  if recvTk = tyClass then begin Result := False; Exit; end;
  { A RECORD's `to_string()` is Rust's ToString blanket impl over Display, so
    it is ours to lower -- but only when the type has no `to_string` of its
    OWN, which wins. Without that check a hand-written `fn to_string(&self)`
    would be silently replaced by the derived rendering, which is the same
    mistake as stealing `clone`. RStrOf then errors if the type has no
    Display either, so the failure is a message and not a wrong string. }
  if recvTk = tyRecord then
  begin
    Result := (m = 'to_string') and (recId >= REC_UCLASS_BASE) and
              (FindProc(RTypeNameOf(recId - REC_UCLASS_BASE) + '::to_string') < 0);
    Exit;
  end;
  Result := (RIsStrTk(recvTk) and RIsStrMethodName(m)) or (m = 'to_string');
end;

{ `s.method(...)` on a string. Two callers -- the identifier arm below (a
  string VARIABLE) and the postfix loop in RParseUnary (any string-valued
  EXPRESSION, e.g. a call result or a `format!`) -- and one implementation,
  the same split RParseOptionAccessor already has for Option. The cursor sits
  on the method NAME.

  `dstSym` is the receiver's symbol when there is one and -1 otherwise. Only
  the mutators need it, and they need it for a specific reason: an assignment
  wants a fresh lvalue node for its destination rather than the receiver node
  reused in two places, because a shared node makes the AST a DAG and every
  pass downstream assumes a tree. }
{ RStrOf is defined just below and used in this routine's tail; forward so the
  FPC seed build resolves it (pxx resolves across the unit, FPC in source
  order). bug-r-rexprrecid-breaks-the-fpc-bootstrap-seed }
function RStrOf(node: Integer): Integer; forward;

function RParseStrMethod(recv, dstSym: Integer): Integer;
var mname: AnsiString; argN, lenNode, argNode, zeroNode, node: Integer;
begin
  mname := CurTok.SVal;
  Next; Next; { method name, ( }

  if (mname = 'len') or (mname = 'is_empty') then
  begin
    Expect(tkRParen, ')');
    lenNode := AllocNode(AN_CALL);
    ASTIVal[lenNode] := -Ord(tkLength);
    ASTTk[lenNode] := Ord(tyInt64);
    argNode := AllocNode(AN_ARG);
    ASTLeft[argNode] := recv; ASTRight[argNode] := -1;
    ASTLeft[lenNode] := argNode;
    if mname = 'len' then begin Result := lenNode; Exit; end;
    zeroNode := AllocNode(AN_INT_LIT);
    ASTIVal[zeroNode] := 0; ASTTk[zeroNode] := Ord(tyInt64);
    Result := RBinOp(tkEq, lenNode, zeroNode, tyBoolean);
    Exit;
  end;

  { push_str(&str) and push(char) are the same operation on a managed string:
    append. Rust gives them different names because they differ in what they
    borrow, which is a distinction the representation above has already
    dissolved. Both are `()`-valued in Rust, so they only ever appear in
    statement position and an AN_ASSIGN is the right shape to return. }
  if (mname = 'push_str') or (mname = 'push') then
  begin
    if dstSym < 0 then
      Error('Rust: ' + mname + ' needs a variable receiver (this frontend cannot mutate a temporary)');
    argN := RParseExpr;
    Expect(tkRParen, ')');
    node := AllocNode(AN_ASSIGN);
    ASTLeft[node] := RMakeIdent(dstSym);
    ASTRight[node] := RBinOp(tkPlus, recv, argN, tyAnsiString);
    Result := node;
    Exit;
  end;

  { as_str / to_owned / clone / into on something already a string are all
    identity once String and &str are one type -- they exist in Rust to move
    between representations, and there is only one. Kept rather than rejected
    because real source is full of them. `to_string()` on a NUMBER lands here
    too, and RStrOf is identity for a string and a conversion otherwise, so
    one tail serves both without a second test. }
  Expect(tkRParen, ')');
  Result := RStrOf(recv);
end;

{ An expression rendered as a string, for `format!` and `to_string()` on a
  non-string. The integer path calls StrInt, which lives in the `builtin` unit
  the driver pulls alongside builtinheap -- the same routine Pascal's own
  `Str(x, s)` intrinsic rewrites to, rather than a second int->text formatter
  that would be the one that drifts. }
function RStrOf(node: Integer): Integer;
var tk: TTypeKind; callNode, argNode, widthNode, pairNode, tNode, fNode: Integer;
    procIdx: Integer;

begin
  tk := IntToTypeKind(ASTTk[node]);
  if RIsStrTk(tk) then begin Result := node; Exit; end;

  { a record renders through its own `impl fmt::Display` if it has one --
    which is what makes `x.to_string()` work on a Display type, since
    Rust's ToString blanket impl is exactly that. }
  if tk = tyRecord then
  begin
    procIdx := RDisplayCall(node, RExprRecId(node));
    if procIdx < 0 then
      Error('Rust: this type has no `impl fmt::Display`, so it cannot become a string');
    Result := procIdx;
    Exit;
  end;

  { A bool is two literals and a branch. Unlike println!'s bool -- which must
    avoid the string runtime because println! does not otherwise need it --
    format! has the runtime by definition, so the ternary is available here
    and is the smaller lowering. }
  if tk = tyBoolean then
  begin
    tNode := RStrLit('true');
    fNode := RStrLit('false');
    pairNode := AllocNode(AN_PAIR);
    ASTLeft[pairNode] := tNode; ASTRight[pairNode] := fNode;
    Result := AllocNode(AN_TERNARY);
    ASTLeft[Result] := node;
    ASTRight[Result] := pairNode;
    ASTTk[Result] := Ord(tyAnsiString);
    Exit;
  end;

  { A char becomes a string by concatenating it onto an empty one. The shared
    lowering already handles `string + char` -- it is what `s.push(c)` compiles
    to -- so this reuses a path the tests already cover rather than building
    the AN_STR_FROM_CHAR temp-and-yield desugar a second time. }
  if tk = tyChar then
  begin
    Result := RBinOp(tkPlus, RStrLit(''), node, tyAnsiString);
    Exit;
  end;

  if (tk = tyDouble) or (tk = tySingle) then
    Error('Rust: format!/to_string of a float is not supported yet (println! renders one)');

  procIdx := FindProc('StrInt');
  if procIdx < 0 then
    Error('Rust: the string runtime is not loaded (internal: builtin unit was not pulled)');
  callNode := AllocNode(AN_CALL);
  ASTIVal[callNode] := procIdx;
  ASTTk[callNode] := Ord(tyAnsiString);
  argNode := AllocNode(AN_ARG);
  ASTLeft[argNode] := node;
  widthNode := AllocNode(AN_INT_LIT);
  ASTIVal[widthNode] := 0; ASTTk[widthNode] := Ord(tyInteger);
  ASTRight[argNode] := AllocNode(AN_ARG);
  ASTLeft[ASTRight[argNode]] := widthNode;
  ASTRight[ASTRight[argNode]] := -1;
  ASTLeft[callNode] := argNode;
  Result := callNode;
end;

{ `format!("a{}b", x)` -> 'a' + StrOf(x) + 'b'. Deliberately NOT sharing
  RParsePrintln's splitter: that one emits WRITES and this one builds a VALUE,
  so the only thing they have in common is scanning `{}` out of a literal, and
  a shared scanner would have to hand back an ordered item list neither caller
  wants in that form. Duplicating ~20 lines of brace scanning is cheaper than
  the abstraction that couples an output path to an expression path. }
{ The body of `format!`, starting AT the format literal and consuming through
  the closing `)`. Split out so write!/writeln! -- which have a formatter
  argument in front of the literal -- can reuse the whole thing instead of
  rewinding the cursor into a shape RParseFormat would accept. }
function RParseFormatTail: Integer;
var fmtOff, fmtLen, i, segStart, specStart, argCount, argUsed: Integer;
    argExprs: array[0..7] of Integer;
    acc: Integer;
    isDbg: Boolean;

  procedure Append(part: Integer);
  begin
    if acc < 0 then acc := part
    else acc := RBinOp(tkPlus, acc, part, tyAnsiString);
  end;

  procedure AddSegment(off, len: Integer);
  var litNode: Integer;
  begin
    if len <= 0 then Exit;
    litNode := AllocNode(AN_STR_LIT);
    ASTSOffset[litNode] := off;
    ASTSLen[litNode] := len;
    ASTTk[litNode] := Ord(tyString);
    Append(litNode);
  end;

  procedure AddText(const t: AnsiString);
  begin
    if t = '' then Exit;
    Append(RStrLit(t));
  end;

  { The value twin of println!'s AddFormatted, over the SAME item list from
    RDebugExpand. The two consumers differ only in what they do with an item
    -- a write there, a concatenation here -- which is exactly why the
    expander hands back a list instead of rendered output. }
  procedure AddFormatted(exprNode: Integer; dbg: Boolean);
  var recId, k: Integer;
  begin
    recId := RExprRecId(exprNode);
    if (IntToTypeKind(ASTTk[exprNode]) = tyRecord) and (recId >= REC_UCLASS_BASE) then
    begin
      if not dbg then
      begin
        k := RDisplayCall(exprNode, recId);
        if k < 0 then
          Error('Rust: `{}` needs Display and this type has none -- use `{:?}`, ' +
                'implement `fmt::Display`, or format the fields');
        Append(k);
        Exit;
      end;
      RDbgCount := 0;
      RDebugExpand(exprNode, recId, '');
      for k := 0 to RDbgCount - 1 do
      begin
        AddText(RDbgText[k]);
        if RDbgNode[k] >= 0 then Append(RStrOf(RDbgNode[k]));
      end;
      Exit;
    end;
    { see the twin in RParsePrintln }
    if dbg and RIsStrTk(IntToTypeKind(ASTTk[exprNode])) then
    begin
      AddText('"'); Append(RStrOf(exprNode)); AddText('"');
      Exit;
    end;
    if dbg and (IntToTypeKind(ASTTk[exprNode]) = tyChar) then
    begin
      AddText(''''); Append(RStrOf(exprNode)); AddText('''');
      Exit;
    end;
    Append(RStrOf(exprNode));
  end;

begin
  if CurTok.Kind <> tkString then Error('Rust: format!/write! need a string literal format');
  fmtOff := Tokens[TokPos - 1].SOffset;
  fmtLen := Tokens[TokPos - 1].SLen;
  Next;

  argCount := 0;
  while Eat(tkComma) do
  begin
    if argCount > 7 then Error('Rust: format! supports at most 8 arguments (skeleton)');
    argExprs[argCount] := RParseExpr;
    Inc(argCount);
  end;
  Expect(tkRParen, ')');

  acc := -1;
  argUsed := 0;
  segStart := 0;
  i := 0;
  while i < fmtLen do
  begin
    if TokChars[fmtOff + i] = '{' then
    begin
      AddSegment(fmtOff + segStart, i - segStart);
      specStart := i + 1;
      while (i < fmtLen) and (TokChars[fmtOff + i] <> '}') do Inc(i);
      if i >= fmtLen then Error('Rust: unterminated {} placeholder in format string');
      isDbg := RSpecIsDebug(fmtOff, specStart, i - specStart);
      Inc(i);
      segStart := i;
      if argUsed >= argCount then Error('Rust: more {} placeholders than arguments');
      AddFormatted(argExprs[argUsed], isDbg);
      Inc(argUsed);
    end
    else
      Inc(i);
  end;
  AddSegment(fmtOff + segStart, fmtLen - segStart);
  if argUsed < argCount then Error('Rust: more arguments than {} placeholders');

  { `format!("")` is a legal empty string, and an all-literal format is a
    single tyString node -- both must come back as a MANAGED string so the
    caller's `let s: String` assignment and any later `+` see the right kind. }
  if acc < 0 then
  begin
    acc := AllocNode(AN_STR_LIT);
    ASTSOffset[acc] := RStoredName(''); ASTSLen[acc] := 0;
    ASTTk[acc] := Ord(tyString);
  end;
  Result := acc;
end;

function RParseFormat: Integer;
begin
  Next; { format }
  Next; { ! }
  Expect(tkLParen, '(');
  Result := RParseFormatTail;
end;

{ `write!(f, "fmt", args)` / `writeln!(...)` inside a Display `fmt` body.

  APPENDS to the method's Result rather than returning it, so a body with
  several writes accumulates and a body with one behaves identically. That is
  what makes the reroute honest: `write!` really is "add this text", and the
  trait's Formatter is the thing being replaced, not the semantics.

  The formatter argument is parsed and DISCARDED -- it names the writer this
  frontend does not have. Discarding it is safe precisely because the reroute
  gives the method exactly one place to write to. }
function RParseWriteMacro(isLn: Boolean): Integer;
var fmtNode, asgn: Integer;
begin
  if not RInDisplayFmt then
    Error('Rust: write!/writeln! are only supported inside a `impl fmt::Display` fmt body');
  Next; { write / writeln }
  Next; { ! }
  Expect(tkLParen, '(');
  if CurTok.Kind <> tkIdent then Error('Rust: write! expects the formatter as its first argument');
  Next;                                  { the formatter -- discarded }
  Expect(tkComma, ',');

  fmtNode := RParseFormatTail;           { the literal and its args, through `)` }

  if isLn then
    fmtNode := RBinOp(tkPlus, fmtNode, RStrLit(Chr(10)), tyAnsiString);

  asgn := AllocNode(AN_ASSIGN);
  ASTLeft[asgn] := RMakeIdent(Procs[CurProc].RetSymIdx);
  ASTRight[asgn] := RBinOp(tkPlus, RMakeIdent(Procs[CurProc].RetSymIdx),
                           fmtNode, tyAnsiString);
  Result := asgn;
end;

{ ===== derives: aggregates in expression position =====

  `#[derive(Clone, Copy, PartialEq)]` needs almost nothing from the frontend,
  which is the point of measuring before building: `Copy` is what a whole-record
  assignment already does, and `PartialEq` is what the shared record comparison
  already does, both proven by a test written before this rung. What was
  actually missing is dumber and older -- an enum VARIANT could not appear in
  an expression at all, so `c == Color::White` and `flip(Color::Black)` were
  parse errors while `let c: Color = Color::White` worked.

  The reason is structural, and it is stated on RParseAggregateIntoNode: no AST
  node carries a whole aggregate VALUE, so a literal is always N stores into a
  named slot. The expression form is therefore the same trick `?` uses --
  allocate a hidden local, hoist the stores into RPendingPreSeq (flushed at the
  single point in RParseStatement), and yield a read of the temp. }

{ RPeekAggregateCi narrowed to the forms that are unambiguous with no expected
  type. Two exclusions, both deliberate:

  - the BRACE literal `Name { .. }`. rustc forbids a struct literal in the
    condition of an `if`/`while`/`match` for exactly this reason: `if a == Sq
    { .. }` cannot be told from a comparison followed by the block. rustc wants
    parens there; so does this, and refusing agrees with the reference
    implementation rather than inventing a rule.

  - a BARE `Some` / `None` / `Ok` / `Err`. Every monomorphized instantiation
    spells its variants the same way, so with no expectation the global table
    answers with whichever class was registered FIRST -- a different layout,
    silently. `let` and `return` positions have an expected type and resolve it
    properly; an expression position does not, so this refuses rather than
    guesses. A wrong class here would be a plausible wrong value, which is the
    failure mode this frontend has already paid for three times. }
function RPeekExprAggregateCi: Integer;
var ci, vi: Integer;
begin
  Result := -1;
  if CurTok.Kind <> tkIdent then Exit;
  ci := FindUClass(CurTok.SVal);
  if ci >= 0 then
  begin
    if REnumCi[ci] and (Tokens[TokPos].Kind = tkPathSep) and
       (Tokens[TokPos + 1].Kind = tkIdent) and
       (RFindVariantInEnum(ci, GetTokenStr(TokPos + 1)) >= 0) then
      Result := ci;
    Exit;
  end;
  vi := RFindVariantBare(CurTok.SVal);
  if vi < 0 then Exit;
  ci := REnumVariants[vi].EnumCi;
  if RIsOptionRec(REC_UCLASS_BASE + ci) or RIsResultRec(REC_UCLASS_BASE + ci) then Exit;
  Result := ci;
end;

{ Parses the aggregate literal at the cursor into an already-existing target
  LVALUE (a node, so the target can be a local, a fn's Result slot, or a FIELD
  of one) and returns the chain of field stores. A literal is the only way a
  whole struct/enum value comes into existence here -- no AST node carries one
  through an expression -- so it is always N stores into a named slot, and
  every context that can name one uses this single implementation.

  The target node is REUSED as the base of each store rather than rebuilt.
  That is safe because a target lvalue is a pure address chain (ident, field,
  index over them) with no side effects to repeat -- the same property the
  compound-assign desugar relies on. }
function RParseAggregateIntoNode(targetNode, ci: Integer): Integer; forward;

function RMaterializeAggregate(ci: Integer): Integer;
var tempSym, storeSeq: Integer; tempName: AnsiString;
begin
  LastTypeRecId := REC_UCLASS_BASE + ci;
  tempName := '__agg' + RIntToStr(RTempSerial); Inc(RTempSerial);
  tempSym := AllocVar(tempName, tyRecord);
  storeSeq := RParseAggregateIntoNode(RMakeIdent(tempSym), ci);
  RPendingPreSeq := RSeqAppend(RPendingPreSeq, storeSeq);
  Result := RMakeIdent(tempSym);
end;

{ The `__ptr` / `__len` stores that make `sliceSym` a borrowed view of the
  fixed array `arrSym`. `loNode` < 0 means 0 and `hiNode` < 0 means the array's
  declared length, i.e. the whole-array borrow `&arr`.

  ONE implementation, called from both places a slice can be created: the
  `let s = &arr[lo..hi];` arm in RParseLet and the argument position in
  RParseCallArg. Argument position had no arm at all until 2026-08-29, so
  `f(&arr)` handed the ARRAY's address to a callee expecting a two-word header
  and the callee read `arr[0]` and `arr[1]` as __ptr and __len -- a clean
  compile and a segfault
  (bug-rust-whole-array-borrow-as-a-slice-argument-segfaults). The textbook
  double case of devdocs/dev/normalise-dont-special-case.md: the second path is
  the one that stays broken, so there is no second path. }
function RSliceHeaderStores(sliceSym, arrSym, loNode, hiNode: Integer): Integer;
var elemNode, addrNode, identNode, fieldNode, assignNode, lenNode, seq: Integer;
begin
  if loNode < 0 then
  begin
    loNode := AllocNode(AN_INT_LIT); ASTIVal[loNode] := 0; ASTTk[loNode] := Ord(tyInt64);
  end;
  if hiNode < 0 then
  begin
    hiNode := AllocNode(AN_INT_LIT);
    ASTIVal[hiNode] := Syms[arrSym].ArrLen;
    ASTTk[hiNode] := Ord(tyInt64);
  end;
  elemNode := AllocNode(AN_INDEX);
  ASTLeft[elemNode] := RMakeIdent(arrSym);
  ASTRight[elemNode] := loNode;
  ASTTk[elemNode] := Ord(Syms[arrSym].ElemType);
  addrNode := AllocNode(AN_ADDR);
  ASTLeft[addrNode] := elemNode;
  ASTTk[addrNode] := Ord(tyPointer);
  identNode := RMakeIdent(sliceSym);
  fieldNode := AllocNode(AN_FIELD);
  ASTLeft[fieldNode] := identNode;
  ASTSOffset[fieldNode] := RStoredName('__ptr'); ASTSLen[fieldNode] := 5;
  ASTTk[fieldNode] := Ord(tyInt64);
  assignNode := AllocNode(AN_ASSIGN);
  ASTLeft[assignNode] := fieldNode; ASTRight[assignNode] := addrNode;
  seq := RSeqAppend(-1, assignNode);
  lenNode := RBinOp(tkMinus, hiNode, loNode, tyInt64);
  fieldNode := AllocNode(AN_FIELD);
  ASTLeft[fieldNode] := identNode;
  ASTSOffset[fieldNode] := RStoredName('__len'); ASTSLen[fieldNode] := 5;
  ASTTk[fieldNode] := Ord(tyInt64);
  assignNode := AllocNode(AN_ASSIGN);
  ASTLeft[assignNode] := fieldNode; ASTRight[assignNode] := lenNode;
  Result := RSeqAppend(seq, assignNode);
end;

{ A borrowed slice over `arrSym` as a VALUE: a hidden local carrying the
  header, its two stores hoisted into RPendingPreSeq (flushed by
  RParseStatement, exactly as the `?` desugar and the aggregate materializer
  do), and the local's ident as the expression. }
function RMaterializeSliceOf(arrSym, loNode, hiNode: Integer): Integer;
var tempSym, ci: Integer; tempName: AnsiString;
begin
  ci := RSliceClassForRec(Syms[arrSym].ElemType, Syms[arrSym].ElemRecName);
  LastTypeRecId := REC_UCLASS_BASE + ci;
  tempName := '__slice' + RIntToStr(RTempSerial); Inc(RTempSerial);
  tempSym := AllocVar(tempName, tyRecord);
  RPendingPreSeq := RSeqAppend(RPendingPreSeq,
    RSliceHeaderStores(tempSym, arrSym, loNode, hiNode));
  Result := RMakeIdent(tempSym);
end;

{ One call argument, at parameter slot `slot` of `procIdx` (-1 when the callee
  is not known yet -- the generic-fn path infers T from its first argument).

  Every argument but one goes straight to RParseExpr. The exception is a borrow
  of a fixed ARRAY, because Rust spells two different things the same way:
  `&arr` for a `&[T]` SLICE param is a two-word __ptr/__len view, and `&arr` for
  a `&[T; N]` ARRAY-REFERENCE param is a bare address. The operand alone cannot
  tell them apart, which is why argument parsing is a function that knows the
  callee at all rather than a bare RParseExpr at five call sites --
  Params[slot].IsArray is the bit that separates them, and it is only reachable
  here. A RANGE borrow `&arr[lo..hi]` is unambiguous and never an array ref. }
function RParseCallArg(procIdx, slot: Integer): Integer;
var save, arrSym, loNode, hiNode: Integer; wantsArrayRef: Boolean;
begin
  if (CurTok.Kind = tkAmp) and
     ((Tokens[TokPos].Kind = tkIdent) or
      ((Tokens[TokPos].Kind = tkMut) and (Tokens[TokPos + 1].Kind = tkIdent))) then
  begin
    save := TokPos - 1;   { the `&` itself, for the rewind below }
    Next; { & }
    if CurTok.Kind = tkMut then Next;
    arrSym := FindSym(CurTok.SVal);
    if (arrSym >= 0) and Syms[arrSym].IsArray then
    begin
      wantsArrayRef := False;
      if (procIdx >= 0) and (slot >= 0) and (slot < Procs[procIdx].ParamCount) then
        wantsArrayRef := Procs[procIdx].Params[slot].IsArray;
      if not wantsArrayRef then
      begin
        Next; { the array name }
        loNode := -1; hiNode := -1;
        if (CurTok.Kind = tkLBrack) and RBrackHasDotDotAt(TokPos - 1) then
        begin
          Next;
          loNode := RParseExpr;
          Expect(tkDotDot, '..');
          hiNode := RParseExpr;
          Expect(tkRBrack, ']');
        end;
        Result := RMaterializeSliceOf(arrSym, loNode, hiNode);
        Exit;
      end;
    end;
    { not an array borrow after all -- rewind and let the ordinary expression
      grammar have it (RParseUnary drops a `&` on a record, which is right:
      records already travel by address). }
    TokPos := save; Next;
  end;
  Result := RParseExpr;
end;

function RParsePrimary: Integer;
var node, fieldNode, symIdx, procIdx, argNode, lastArg, fTokIdx, gfi, ci,
    argSlot: Integer;
    name, methodName, fullName: AnsiString;
begin
  case CurTok.Kind of
    { statement-position `if` never reaches here -- RParseStatement dispatches
      it to RParseIf first -- so this arm is only the value form. }
    tkIf: begin Result := RParseIfExpr; Exit; end;
    tkInteger:
    begin
      node := AllocNode(AN_INT_LIT); ASTIVal[node] := CurTok.IVal;
      { A suffix (`1u64`, `7usize`) is spelled exactly like the type name, so
        the one mapper answers for both. Unsuffixed, Rust's default is i32 --
        kept, EXCEPT that a value which does not fit one widens to i64 rather
        than silently truncating, which is the same judgement rustc makes when
        it refuses the literal outright. Both halves are about wrong VALUES:
        the suffix was lexed and dropped, so `1u64 << 44` evaluated to 0. }
      if CurTok.SVal <> '' then
        ASTTk[node] := Ord(RTypeKindFromName(CurTok.SVal, False))
      else if (CurTok.IVal > 2147483647) or (CurTok.IVal < -2147483648) then
        ASTTk[node] := Ord(tyInt64)
      else
        ASTTk[node] := Ord(tyInteger);
      Next; Result := node;
    end;
    tkFloat:
    begin
      node := AllocNode(AN_FLOAT_LIT); ASTIVal[node] := CurTok.IVal; ASTTk[node] := Ord(tyDouble);
      Next; Result := node;
    end;
    tkString:
    begin
      node := AllocNode(AN_STR_LIT);
      ASTSOffset[node] := Tokens[TokPos - 1].SOffset;
      ASTSLen[node] := Tokens[TokPos - 1].SLen;
      ASTTk[node] := Ord(tyString);
      Next; Result := node;
    end;
    tkTrue:
    begin
      node := AllocNode(AN_BOOL_LIT); ASTIVal[node] := 1; ASTTk[node] := Ord(tyBoolean);
      Next; Result := node;
    end;
    tkFalse:
    begin
      node := AllocNode(AN_BOOL_LIT); ASTIVal[node] := 0; ASTTk[node] := Ord(tyBoolean);
      Next; Result := node;
    end;
    tkLParen:
    begin
      Next; node := RParseExpr; Expect(tkRParen, ')'); Result := node;
    end;
    tkIdent:
    begin
      { format!(..) is an EXPRESSION -- unlike println!, which is dispatched
        from RParseStatement because it is only ever a statement. }
      if (CurTok.SVal = 'format') and (Tokens[TokPos].Kind = tkLogNot) and
         (Tokens[TokPos + 1].Kind = tkLParen) then
      begin
        Result := RParseFormat;
        Exit;
      end;
      { `Color::White` / `Piece::Pawn(x)` / a bare unit variant, anywhere an
        expression is allowed -- see RPeekExprAggregateCi. Checked before the
        associated-fn path below because `Enum::name` is spelled identically
        either way; the peek only answers for a name that really is a VARIANT
        of that enum, so `Enum::assoc_fn(..)` still falls through. }
      ci := RPeekExprAggregateCi;
      if ci >= 0 then
      begin
        Result := RMaterializeAggregate(ci);
        Exit;
      end;
      name := CurTok.SVal; Next;
      { `Type::fn(args)` / `Self::fn(args)` — associated-fn call on the
        mangled proc name (enum paths stay let-initializer-only) }
      if (CurTok.Kind = tkPathSep) and (Tokens[TokPos].Kind = tkIdent) and
         (Tokens[TokPos + 1].Kind = tkLParen) then
      begin
        if (name = 'Self') and (RCurImplType <> '') then name := RCurImplType;
        Next; { :: }
        name := name + '::' + CurTok.SVal;
        { String::new() is the empty string and String::from(e) is e -- both
          are constructors for a representation that is already whatever the
          argument is, so neither needs a proc. Intercepted BEFORE FindProc so
          a user `impl String` cannot shadow them into something that silently
          differs. }
        if (name = 'String::new') or (name = 'String::from') then
        begin
          Next; { fn name }
          Next; { ( }
          if name = 'String::new' then
          begin
            Expect(tkRParen, ')');
            node := AllocNode(AN_STR_LIT);
            ASTSOffset[node] := RStoredName(''); ASTSLen[node] := 0;
            ASTTk[node] := Ord(tyString);
          end
          else
          begin
            node := RStrOf(RParseExpr);
            Expect(tkRParen, ')');
          end;
          Result := node;
          Exit;
        end;
        procIdx := FindProc(name);
        if procIdx < 0 then Error('Rust: no associated fn ' + name);
        Next; { fn name }
        Next; { ( }
        node := AllocNode(AN_CALL);
        ASTIVal[node] := procIdx;
        ASTTk[node] := Ord(Procs[procIdx].RetType);
        lastArg := -1; argSlot := 0;
        if CurTok.Kind <> tkRParen then
          repeat
            argNode := AllocNode(AN_ARG);
            ASTLeft[argNode] := RParseCallArg(procIdx, argSlot); Inc(argSlot);
            ASTRight[argNode] := -1;
            if lastArg < 0 then ASTLeft[node] := argNode else ASTRight[lastArg] := argNode;
            lastArg := argNode;
          until not Eat(tkComma);
        Expect(tkRParen, ')');
        Result := node;
        Exit;
      end;
      if CurTok.Kind = tkLParen then
      begin
        procIdx := FindProc(name);
        if procIdx < 0 then
        begin
          gfi := RFindGenericFunc(name);
          if gfi < 0 then Error('Rust: call to undefined function ' + name);
          Next; { ( }
          if CurTok.Kind = tkRParen then
            Error('Rust: generic function ' + name + ' needs an argument to infer its type parameter');
          argNode := RParseExpr; { first arg, parsed once, used both to infer T and as arg 0 }
          procIdx := RSpecializeGenericFn(gfi, RConcreteTypeNameForArg(argNode));
          node := AllocNode(AN_CALL);
          ASTIVal[node] := procIdx;
          ASTTk[node] := Ord(Procs[procIdx].RetType);
          lastArg := AllocNode(AN_ARG);
          ASTLeft[lastArg] := argNode; ASTRight[lastArg] := -1;
          ASTLeft[node] := lastArg;
          argSlot := 1;
          while Eat(tkComma) do
          begin
            argNode := AllocNode(AN_ARG);
            ASTLeft[argNode] := RParseCallArg(procIdx, argSlot); Inc(argSlot);
            ASTRight[argNode] := -1;
            ASTRight[lastArg] := argNode; lastArg := argNode;
          end;
          Expect(tkRParen, ')');
          Result := node;
          Exit;
        end;
        Next;
        node := AllocNode(AN_CALL);
        ASTIVal[node] := procIdx;
        ASTTk[node] := Ord(Procs[procIdx].RetType);
        lastArg := -1; argSlot := 0;
        if CurTok.Kind <> tkRParen then
          repeat
            argNode := AllocNode(AN_ARG);
            ASTLeft[argNode] := RParseCallArg(procIdx, argSlot); Inc(argSlot);
            ASTRight[argNode] := -1;
            if lastArg < 0 then ASTLeft[node] := argNode else ASTRight[lastArg] := argNode;
            lastArg := argNode;
          until not Eat(tkComma);
        Expect(tkRParen, ')');
        Result := node;
        Exit;
      end;
      symIdx := FindSym(name);
      if symIdx < 0 then Error('Rust: undefined variable ' + name);
      node := RMakeIdent(symIdx);
      if (CurTok.Kind = tkLBrack) and RIsSliceSym(symIdx) then
      begin
        { s[i] — AN_DEREF(__ptr + i*elemsize), raw i64 pointer math (the
          Zig frontend's slice-index shape ported back). For a record-element
          slice the stride is RecSize and the deref carries the element recid
          (ASTIVal) so a trailing `.field` resolves via ResolveNodeRec. }
        Next;
        fieldNode := RParseExpr;
        Expect(tkRBrack, ']');
        ci := Syms[symIdx].RecName - REC_UCLASS_BASE;
        gfi := AllocNode(AN_INT_LIT);
        if (RSliceElemTk[ci] = tyRecord) and (RSliceElemRec[ci] >= REC_UCLASS_BASE) then
          ASTIVal[gfi] := RecSize(RSliceElemRec[ci])
        else
          ASTIVal[gfi] := TypeSlotSize(RSliceElemTk[ci]);
        ASTTk[gfi] := Ord(tyInt64);
        argNode := AllocNode(AN_FIELD);
        ASTLeft[argNode] := node;
        ASTSOffset[argNode] := RStoredName('__ptr'); ASTSLen[argNode] := 5;
        ASTTk[argNode] := Ord(tyInt64);
        lastArg := AllocNode(AN_DEREF);
        ASTLeft[lastArg] := RBinOp(tkPlus, argNode,
          RBinOp(tkStar, fieldNode, gfi, tyInt64), tyInt64);
        ASTTk[lastArg] := Ord(RSliceElemTk[ci]);
        if (RSliceElemTk[ci] = tyRecord) and (RSliceElemRec[ci] >= REC_UCLASS_BASE) then
        begin
          ASTIVal[lastArg] := RSliceElemRec[ci];   { record id for slice[i].field }
          { `slice[i].field` — AN_FIELD over the record deref, read or write. }
          if (CurTok.Kind = tkDot) and
             ((Tokens[TokPos].Kind = tkIdent) or (Tokens[TokPos].Kind = tkInteger)) then
          begin
            Next; { . }
            if CurTok.Kind = tkInteger then methodName := RIntToStr(CurTok.IVal)
            else methodName := CurTok.SVal;
            fTokIdx := TokPos - 1;
            Next;
            argNode := AllocNode(AN_FIELD);
            ASTLeft[argNode] := lastArg;
            ASTSOffset[argNode] := Tokens[fTokIdx].SOffset;
            ASTSLen[argNode] := Tokens[fTokIdx].SLen;
            ASTTk[argNode] := Ord(RecFieldType(RSliceElemRec[ci], methodName));
            Result := argNode;
            Exit;
          end;
        end;
        Result := lastArg;
        Exit;
      end;
      if (CurTok.Kind = tkLBrack) and Syms[symIdx].IsArray then
      begin
        { a[i] — plain fixed-array indexing }
        Next;
        fieldNode := RParseExpr;
        Expect(tkRBrack, ']');
        node := AllocNode(AN_INDEX);
        ASTLeft[node] := RMakeIdent(symIdx);
        ASTRight[node] := fieldNode;
        ASTTk[node] := Ord(Syms[symIdx].ElemType);
        { `arr[i].field` on an array of records: wrap the AN_INDEX in an
          AN_FIELD (read or, as an assign target, write). The element record is
          Syms[symIdx].ElemRecName, resolved by ResolveNodeRec(AN_INDEX) in the
          shared codegen. Supports named fields and tuple-struct `.0` digits. }
        if (Syms[symIdx].ElemType = tyRecord) and (CurTok.Kind = tkDot) and
           ((Tokens[TokPos].Kind = tkIdent) or (Tokens[TokPos].Kind = tkInteger)) then
        begin
          ci := Syms[symIdx].ElemRecName;
          Next; { . }
          if CurTok.Kind = tkInteger then methodName := RIntToStr(CurTok.IVal)
          else methodName := CurTok.SVal;
          fTokIdx := TokPos - 1;
          Next;
          argNode := AllocNode(AN_FIELD);
          ASTLeft[argNode] := node;
          ASTSOffset[argNode] := Tokens[fTokIdx].SOffset;
          ASTSLen[argNode] := Tokens[fTokIdx].SLen;
          if ci >= REC_UCLASS_BASE then
            ASTTk[argNode] := Ord(RecFieldType(ci, methodName))
          else
            ASTTk[argNode] := Ord(tyInt64);
          Result := argNode;
          Exit;
        end;
        Result := node;
        Exit;
      end;
      { o.is_some() / o.is_none() / o.unwrap() on an Option<T> — pure field
        reads off the tagged union, no RTL call and no new AST node.
        `unwrap()` does NOT panic on None (it reads the payload slot as-is):
        this frontend has no panic path yet, and a checked unwrap is a
        follow-up once one exists. Documented in the ticket, not silent. }
      { o.is_some() / is_none() / unwrap() / unwrap_or(d) on an Option
        VARIABLE. The field twin of this is in the `.field` arm below; both
        call the one RParseOptionAccessor. }
      if (CurTok.Kind = tkDot) and RIsOptionRec(Syms[symIdx].RecName) and
         (Tokens[TokPos].Kind = tkIdent) and (Tokens[TokPos + 1].Kind = tkLParen) and
         RIsOptionAccessorName(GetTokenStr(TokPos)) then
      begin
        Next; { . }
        Result := RParseOptionAccessor(node, Syms[symIdx].RecName);
        Exit;
      end;
      { a.len() / s.len() — array length constant / slice __len field }
      if (CurTok.Kind = tkDot) and (Tokens[TokPos].Kind = tkIdent) and
         (GetTokenStr(TokPos) = 'len') and (Tokens[TokPos + 1].Kind = tkLParen) and
         (Syms[symIdx].IsArray or RIsSliceSym(symIdx)) then
      begin
        Next; Next; Next; { . len ( }
        Expect(tkRParen, ')');
        if Syms[symIdx].IsArray then
        begin
          node := AllocNode(AN_INT_LIT);
          ASTIVal[node] := Syms[symIdx].ArrLen;
          ASTTk[node] := Ord(tyInt64);
        end
        else
        begin
          fieldNode := AllocNode(AN_FIELD);
          ASTLeft[fieldNode] := node;
          ASTSOffset[fieldNode] := RStoredName('__len'); ASTSLen[fieldNode] := 5;
          ASTTk[fieldNode] := Ord(tyInt64);
          node := fieldNode;
        end;
        Result := node;
        Exit;
      end;
      if (CurTok.Kind = tkDot) and (Tokens[TokPos].Kind = tkInteger) then
      begin
        { tuple-struct field access `s.0` — the digits are the field name }
        Next;
        name := RIntToStr(CurTok.IVal);
        fieldNode := AllocNode(AN_FIELD);
        ASTLeft[fieldNode] := node;
        ASTSOffset[fieldNode] := RStoredName(name);
        ASTSLen[fieldNode] := Length(name);
        ASTTk[fieldNode] := Ord(RecFieldType(Syms[symIdx].RecName, name));
        node := fieldNode;
        Next;
        Result := node;
        Exit;
      end;
      { s.len() / s.push_str(x) / s.to_string() on a string VARIABLE. The
        expression twin is the postfix loop in RParseUnary; both call the one
        RParseStrMethod. This arm exists at all because the generic `.method`
        path below resolves through the receiver's RECORD class, which a
        string does not have -- without the intercept `s.len()` reports that a
        record type nobody wrote has no method. }
      if (CurTok.Kind = tkDot) and
         (Tokens[TokPos].Kind = tkIdent) and (Tokens[TokPos + 1].Kind = tkLParen) and
         RStrMethodApplies(Syms[symIdx].TypeKind, Syms[symIdx].RecName, GetTokenStr(TokPos)) then
      begin
        Next; { . }
        Result := RParseStrMethod(node, symIdx);
        Exit;
      end;
      if CurTok.Kind = tkDot then
      begin
        Next;
        if CurTok.Kind <> tkIdent then Error('Rust: expected field or method name after .');
        if Tokens[TokPos].Kind = tkLParen then
        begin
          { method call: p.method(args) — self passed as &p (address); the
            existing by-reference record-parameter ABI (see ParamSize) takes
            the address of a plain identifier argument automatically, same
            as any Pascal `var` record parameter. }
          methodName := CurTok.SVal;
          ci := Syms[symIdx].RecName - REC_UCLASS_BASE;
          fullName := RTypeNameOf(ci) + '::' + methodName;
          procIdx := FindProc(fullName);
          { `#[derive(Clone)]` on a record: a derived clone is a field-wise
            copy, and a whole-record assignment is already exactly that, so
            `a.clone()` yields `a` itself and the copy happens where the
            result lands. Only when the type has no clone of its OWN -- a
            hand-written `fn clone(&self)` resolves above and wins, because a
            user's clone may do more than the derive would. }
          if (procIdx < 0) and (methodName = 'clone') and
             (Tokens[TokPos + 1].Kind = tkRParen) then
          begin
            Next; Next;                   { clone, ( }
            Expect(tkRParen, ')');
            Result := node;
            Exit;
          end;
          if procIdx < 0 then Error('Rust: ' + RTypeNameOf(ci) + ' has no method ' + methodName);
          Next; Next; { method name, ( }
          fieldNode := AllocNode(AN_CALL);
          ASTIVal[fieldNode] := procIdx;
          ASTTk[fieldNode] := Ord(Procs[procIdx].RetType);
          lastArg := AllocNode(AN_ARG);
          ASTLeft[lastArg] := node; ASTRight[lastArg] := -1;
          ASTLeft[fieldNode] := lastArg;
          argSlot := 1;   { slot 0 is the receiver }
          if CurTok.Kind <> tkRParen then
            repeat
              argNode := AllocNode(AN_ARG);
              ASTLeft[argNode] := RParseCallArg(procIdx, argSlot); Inc(argSlot);
              ASTRight[argNode] := -1;
              ASTRight[lastArg] := argNode; lastArg := argNode;
            until not Eat(tkComma);
          Expect(tkRParen, ')');
          node := fieldNode;
          Result := node;
          Exit;
        end;
        fTokIdx := TokPos - 1;
        fieldNode := AllocNode(AN_FIELD);
        ASTLeft[fieldNode] := node;
        ASTSOffset[fieldNode] := Tokens[fTokIdx].SOffset;
        ASTSLen[fieldNode] := Tokens[fTokIdx].SLen;
        ASTTk[fieldNode] := Ord(RecFieldType(Syms[symIdx].RecName, CurTok.SVal));
        methodName := CurTok.SVal;
        node := fieldNode;
        Next;
        { `s.field.method(..)` — a method on a RECORD-typed field. Same
          lowering as a method on a plain variable (self passed by address);
          the only new part is that the receiver's class comes from the field
          rather than from a symbol. `self.side.flip()` is how the engine
          spells it, and it was refused. }
        ci := RecFieldRecId(Syms[symIdx].RecName, methodName);
        { `b.ep.is_none()` — the accessors again, on a FIELD of Option type. }
        if RIsOptionRec(ci) and (CurTok.Kind = tkDot) and
           (Tokens[TokPos].Kind = tkIdent) and (Tokens[TokPos + 1].Kind = tkLParen) and
           RIsOptionAccessorName(GetTokenStr(TokPos)) then
        begin
          Next; { . }
          Result := RParseOptionAccessor(node, ci);
          Exit;
        end;
        if (ci >= REC_UCLASS_BASE) and (CurTok.Kind = tkDot) and
           (Tokens[TokPos].Kind = tkIdent) and (Tokens[TokPos + 1].Kind = tkLParen) then
        begin
          Next;
          fullName := RTypeNameOf(ci - REC_UCLASS_BASE) + '::' + CurTok.SVal;
          procIdx := FindProc(fullName);
          if procIdx < 0 then
            Error('Rust: ' + RTypeNameOf(ci - REC_UCLASS_BASE) + ' has no method ' + CurTok.SVal);
          Next; Next; { method name, ( }
          fieldNode := AllocNode(AN_CALL);
          ASTIVal[fieldNode] := procIdx;
          ASTTk[fieldNode] := Ord(Procs[procIdx].RetType);
          lastArg := AllocNode(AN_ARG);
          ASTLeft[lastArg] := node; ASTRight[lastArg] := -1;
          ASTLeft[fieldNode] := lastArg;
          argSlot := 1;   { slot 0 is the receiver }
          if CurTok.Kind <> tkRParen then
            repeat
              argNode := AllocNode(AN_ARG);
              ASTLeft[argNode] := RParseCallArg(procIdx, argSlot); Inc(argSlot);
              ASTRight[argNode] := -1;
              ASTRight[lastArg] := argNode; lastArg := argNode;
            until not Eat(tkComma);
          Expect(tkRParen, ')');
          Result := fieldNode;
          Exit;
        end;
        { `s.arr[i]` — indexing a fixed-array FIELD. AN_INDEX over the
          AN_FIELD, the same node pair Pascal's `r.arr[i]` builds; read or
          write (AN_INDEX is already an accepted assign target). }
        if (CurTok.Kind = tkLBrack) and RFieldIsArray(Syms[symIdx].RecName, methodName) then
        begin
          Next;
          argNode := RParseExpr;
          Expect(tkRBrack, ']');
          ci := RecFieldRecId(Syms[symIdx].RecName, methodName);
          fieldNode := AllocNode(AN_INDEX);
          ASTLeft[fieldNode] := node;
          ASTRight[fieldNode] := argNode;
          ASTTk[fieldNode] := ASTTk[node];
          node := fieldNode;
          { `s.arr[i].field` — an array field whose ELEMENT is a record.
            ResolveNodeRec's AN_INDEX/AN_FIELD arm already answers the element
            record from UFldRec_, so this is one more AN_FIELD and no shared
            change. Named fields and tuple-struct `.0` digits both. }
          if (ci >= REC_UCLASS_BASE) and (CurTok.Kind = tkDot) and
             ((Tokens[TokPos].Kind = tkIdent) or (Tokens[TokPos].Kind = tkInteger)) then
          begin
            Next;
            if CurTok.Kind = tkInteger then name := RIntToStr(CurTok.IVal)
            else name := CurTok.SVal;
            fTokIdx := TokPos - 1;
            Next;
            fieldNode := AllocNode(AN_FIELD);
            ASTLeft[fieldNode] := node;
            ASTSOffset[fieldNode] := Tokens[fTokIdx].SOffset;
            ASTSLen[fieldNode] := Tokens[fTokIdx].SLen;
            ASTTk[fieldNode] := Ord(RecFieldType(ci, name));
            node := fieldNode;
          end;
        end;
      end;
      Result := node;
    end;
    else
    begin
      Error('Rust: unexpected token in expression');
      Result := -1;
    end;
  end;
end;

function RParseUnary: Integer;
var node: Integer;
begin
  if CurTok.Kind = tkAmp then
  begin
    { `&x` / `&mut x` in argument/expression position is a no-op: record
      and slice values already travel by address through the record ABI.
      (Slice CREATION `&a[lo..hi]` is handled in RParseLet, before this.) }
    Next;
    if CurTok.Kind = tkMut then Next;
    Result := RParseUnary();
    Exit;
  end;
  if CurTok.Kind = tkMinus then
  begin
    Next;
    node := AllocNode(AN_NEG);
    { Parens force a real recursive call — a bare name here read the
      implicit Result alias instead (frank2-paramless-name-semantics;
      latent since the skeleton, caught in the bitops pass). }
    ASTLeft[node] := RParseUnary();
    ASTTk[node] := ASTTk[ASTLeft[node]];
    Result := node;
    Exit;
  end;
  if CurTok.Kind = tkLogNot then
  begin
    Next;
    node := AllocNode(AN_NOT);
    ASTLeft[node] := RParseUnary();
    { Rust `!` is logical on bool, BITWISE on integers — same duality as
      the shared IR's Pascal `not`, so tag by operand type. }
    if IntToTypeKind(ASTTk[ASTLeft[node]]) = tyBoolean then
      ASTTk[node] := Ord(tyBoolean)
    else
      ASTTk[node] := ASTTk[ASTLeft[node]];
    Result := node;
    Exit;
  end;
  Result := RParsePrimary;
  { postfix `?`, applied after the primary so it composes with `.field` and
    calls: `self.board.piece_at(sq)?` }
  while CurTok.Kind = tkQuestion do
  begin
    Next;
    Result := RParseTryOp(Result);
  end;
  { `format!(..).len()`, `f().to_string()` -- a string method on a string-valued
    expression that is not a plain variable. Same routine as the identifier
    arm's; only the receiver differs, and a temporary has no symbol, which is
    what makes the mutators refuse here rather than append to a value nobody
    can read back. }
  while (CurTok.Kind = tkDot) and
        (Tokens[TokPos].Kind = tkIdent) and (Tokens[TokPos + 1].Kind = tkLParen) and
        RStrMethodApplies(IntToTypeKind(ASTTk[Result]), RExprRecId(Result), GetTokenStr(TokPos)) do
  begin
    Next; { . }
    Result := RParseStrMethod(Result, -1);
  end;
end;

{ `expr as T` — numeric cast (binds tighter than * per Rust). v1: retag
  the node's static type; narrowing to an UNSIGNED target additionally
  masks the value (u8/u16/u32), so mailbox-byte style round-trips are
  exact. Narrowing to signed targets just retags (no sign-extension
  fixup) — documented corpus deviation. }
function RParseAs: Integer;
var left, maskNode: Integer; tk: TTypeKind;
begin
  left := RParseUnary;
  while (CurTok.Kind = tkIdent) and (CurTok.SVal = 'as') do
  begin
    Next;
    if CurTok.Kind <> tkIdent then Error('Rust: expected type after as');
    tk := RTypeKindFromName(CurTok.SVal, False);
    Next;
    case tk of
      tyUInt8:
      begin
        maskNode := AllocNode(AN_INT_LIT); ASTIVal[maskNode] := 255; ASTTk[maskNode] := Ord(tyInt64);
        left := RBinOp(tkAnd, left, maskNode, tk);
      end;
      tyUInt16:
      begin
        maskNode := AllocNode(AN_INT_LIT); ASTIVal[maskNode] := 65535; ASTTk[maskNode] := Ord(tyInt64);
        left := RBinOp(tkAnd, left, maskNode, tk);
      end;
      tyUInt32:
      begin
        maskNode := AllocNode(AN_INT_LIT); ASTIVal[maskNode] := $FFFFFFFF; ASTTk[maskNode] := Ord(tyInt64);
        left := RBinOp(tkAnd, left, maskNode, tk);
      end;
      else
        ASTTk[left] := Ord(tk);
    end;
  end;
  Result := left;
end;

function RParseMul: Integer;
var left, right, node: Integer; opTk: TTokenKind; rt: TTypeKind;
begin
  left := RParseAs;
  while CurTok.Kind in [tkStar, tkSlash, tkMod] do
  begin
    opTk := CurTok.Kind; Next;
    right := RParseAs;
    rt := RWiden(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right]));
    { Rust integer / is TRUNCATING division; the shared tkSlash BINOP is
      Pascal's REAL division (double bits reinterpreted as int64 =
      garbage). The Zig frontend hit this on its first run and left a
      note pointing HERE (feature-zig-frontend probe verdict) — the
      chess-corpus perft finally cashed it in: rank_of's sq/8 returned
      4607182418800017409 (the bit pattern of 1.0). Integer operands
      lower to tkDiv; float operands keep tkSlash. }
    if (opTk = tkSlash) and (rt <> tyDouble) and (rt <> tySingle) then
      opTk := tkDiv;
    node := RBinOp(opTk, left, right, rt);
    left := node;
  end;
  Result := left;
end;

function RParseAdd: Integer;
var left, right, node: Integer; opTk: TTokenKind;
begin
  left := RParseMul;
  while CurTok.Kind in [tkPlus, tkMinus] do
  begin
    opTk := CurTok.Kind; Next;
    right := RParseMul;
    node := RBinOp(opTk, left, right, RWiden(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right])));
    left := node;
  end;
  Result := left;
end;

{ Rust precedence: << >> bind tighter than &, then ^, then |, then the
  comparisons. tkAnd/tkOr/tkXor are the shared IR's Pascal-style ops —
  bitwise when the operands are integers. }
function RParseShift: Integer;
var left, right, node: Integer; opTk: TTokenKind;
begin
  left := RParseAdd;
  while CurTok.Kind in [tkShl, tkShr] do
  begin
    opTk := CurTok.Kind; Next;
    right := RParseAdd;
    { Rust >> is arithmetic on signed, logical on unsigned — the same split
      cparser encodes: tkShr = the arithmetic-sar sentinel, tkShrLogical = the
      logical one.

      This said tkIdent until 2026-09-01, and it was RIGHT when written
      (2026-07-08): Pascal spells `shr` as a plain identifier, so Ord(tkIdent)
      was the IR's logical-shr spelling everywhere. The rename to tkShrLogical
      (314481dd7, 2026-08-31) updated 25 sites across cparser, pasparser,
      pyparser and all seven backends -- and missed these three in rparser, so
      every unsigned `>>` in a Rust program reached codegen carrying an operator
      no backend handles and died on `Unsupported operator in IR codegen`.
      bug-a-shr-reaches-the-ir-spelled-as-tkident /
      regression-test-core-test-rust-module-items }
    if (opTk = tkShr) and not TypeSigned(IntToTypeKind(ASTTk[left])) then
      opTk := tkShrLogical;
    node := RBinOp(opTk, left, right, IntToTypeKind(ASTTk[left]));
    left := node;
  end;
  Result := left;
end;

function RParseBitAnd: Integer;
var left, right, node: Integer;
begin
  left := RParseShift;
  while CurTok.Kind = tkAmp do
  begin
    Next;
    right := RParseShift;
    node := RBinOp(tkAnd, left, right, RWiden(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right])));
    left := node;
  end;
  Result := left;
end;

function RParseBitXor: Integer;
var left, right, node: Integer;
begin
  left := RParseBitAnd;
  while CurTok.Kind = tkCaret do
  begin
    Next;
    right := RParseBitAnd;
    node := RBinOp(tkXor, left, right, RWiden(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right])));
    left := node;
  end;
  Result := left;
end;

function RParseBitOr: Integer;
var left, right, node: Integer;
begin
  left := RParseBitXor;
  while CurTok.Kind = tkPipe do
  begin
    Next;
    right := RParseBitXor;
    node := RBinOp(tkOr, left, right, RWiden(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right])));
    left := node;
  end;
  Result := left;
end;

function RParseCmp: Integer;
var left, right, node: Integer; opTk: TTokenKind;
begin
  left := RParseBitOr;
  if CurTok.Kind in [tkEq, tkNeq, tkLt, tkLe, tkGt, tkGe] then
  begin
    opTk := CurTok.Kind; Next;
    right := RParseBitOr;
    node := RBinOp(opTk, left, right, tyBoolean);
    left := node;
  end;
  Result := left;
end;

function RParseAnd: Integer;
var left, right, node: Integer;
begin
  left := RParseCmp;
  while CurTok.Kind = tkAnd do
  begin
    Next;
    right := RParseCmp;
    node := RBinOp(tkAnd, left, right, tyBoolean);
    left := node;
  end;
  Result := left;
end;

function RParseExpr: Integer;
var left, right, node: Integer;
begin
  left := RParseAnd;
  while CurTok.Kind = tkOr do
  begin
    Next;
    right := RParseAnd;
    node := RBinOp(tkOr, left, right, tyBoolean);
    left := node;
  end;
  Result := left;
end;

{ Resolves a match/if-let scrutinee. A plain variable is used directly;
  anything else -- `match self.piece_at(sq)`, the spelling real source uses --
  is evaluated ONCE into a generated local and matched through that. preSeq
  receives the materializing assignment, or stays -1 for the variable case.
  Disambiguation is free: an expression scrutinee is followed by the opening
  brace of the match/if-let body, and this frontend has no struct-literal
  expression form for that brace to be confused with. }
function RParseScrutinee(var preSeq: Integer): Integer;
var scrutIdent: AnsiString; scrutNode, recId, assignNode: Integer;
begin
  preSeq := -1;
  if (CurTok.Kind = tkIdent) and (Tokens[TokPos].Kind = tkBegin) then
  begin
    scrutIdent := CurTok.SVal;
    Result := FindSym(scrutIdent);
    if Result < 0 then Error('Rust: undefined variable ' + scrutIdent);
    Next;
    Exit;
  end;
  scrutNode := RParseExpr;
  recId := RExprRecId(scrutNode);
  if recId < REC_UCLASS_BASE then Error('Rust: match scrutinee must be an enum value');
  LastTypeRecId := recId;
  scrutIdent := '__scrut' + RIntToStr(RTempSerial); Inc(RTempSerial);
  Result := AllocVar(scrutIdent, tyRecord);
  assignNode := AllocNode(AN_ASSIGN);
  ASTLeft[assignNode] := RMakeIdent(Result); ASTRight[assignNode] := scrutNode;
  preSeq := RSeqAppend(-1, assignNode);
end;

{ Parses the payload pattern that follows a variant name -- `(a, b)` for a
  tuple variant, `{ f, g }` for a struct one, nothing for a unit variant --
  and returns the chain of assignments that materialize each bound name as a
  fresh local read out of the scrutinee's mangled payload field. Shared by
  `match` arms and `if let`, which bind identically. }
function RParsePatternBinds(scrutSym, enumCi, vi: Integer;
  const variantName: AnsiString): Integer;
var i, bindSym, fieldNode, assignNode: Integer;
    bindName, mangled: AnsiString; fieldTk: TTypeKind;

  procedure BindOne(const nm: AnsiString);
  begin
    fieldTk := RecFieldType(REC_UCLASS_BASE + enumCi, mangled);
    if fieldTk = tyRecord then LastTypeRecId := RecFieldRecId(REC_UCLASS_BASE + enumCi, mangled)
    else LastTypeRecId := REC_NONE;
    bindSym := AllocVar(nm, fieldTk);
    fieldNode := AllocNode(AN_FIELD);
    ASTLeft[fieldNode] := RMakeIdent(scrutSym);
    ASTSOffset[fieldNode] := RStoredName(mangled); ASTSLen[fieldNode] := Length(mangled);
    ASTTk[fieldNode] := Ord(Syms[bindSym].TypeKind);
    assignNode := AllocNode(AN_ASSIGN);
    ASTLeft[assignNode] := RMakeIdent(bindSym); ASTRight[assignNode] := fieldNode;
    Result := RSeqAppend(Result, assignNode);
  end;

begin
  Result := -1;
  case REnumVariants[vi].Kind of
    RVAR_TUPLE:
    begin
      Expect(tkLParen, '(');
      i := 0;
      if CurTok.Kind <> tkRParen then
        repeat
          if CurTok.Kind <> tkIdent then Error('Rust: expected bind name in tuple pattern');
          bindName := CurTok.SVal; Next;
          if bindName <> '_' then
          begin
            mangled := variantName + '.' + RIntToStr(i);
            BindOne(bindName);
          end;
          Inc(i);
        until not Eat(tkComma);
      Expect(tkRParen, ')');
    end;
    RVAR_STRUCT:
    begin
      Expect(tkBegin, '{');
      while CurTok.Kind <> tkEnd do
      begin
        if CurTok.Kind <> tkIdent then Error('Rust: expected field name in struct pattern');
        bindName := CurTok.SVal; Next;
        mangled := variantName + '.' + bindName;
        BindOne(bindName);
        if not Eat(tkComma) then Break;
      end;
      Expect(tkEnd, '}');
    end;
  end; { RVAR_UNIT: no pattern payload }
end;

{ `<scrut>.__tag = <vi's tag>` — the one comparison every pattern test is. }
function RTagTest(scrutSym, vi: Integer): Integer;
var fieldNode, valNode: Integer;
begin
  fieldNode := AllocNode(AN_FIELD);
  ASTLeft[fieldNode] := RMakeIdent(scrutSym);
  ASTSOffset[fieldNode] := RStoredName('__tag'); ASTSLen[fieldNode] := 5;
  ASTTk[fieldNode] := Ord(tyInt64);
  valNode := AllocNode(AN_INT_LIT);
  ASTIVal[valNode] := REnumVariants[vi].Tag; ASTTk[valNode] := Ord(tyInt64);
  Result := RBinOp(tkEq, fieldNode, valNode, tyBoolean);
end;

{ `expr?` -- Rust's try operator, desugared to exactly what the reference says
  it means: `match expr { Ok(v) => v, Err(e) => return Err(e) }`.

  Two of those three pieces cannot live in an expression node. The operand has
  to be materialized (it is evaluated once and read twice, and it may be a
  call), and the Err arm RETURNS from the enclosing function. So the statement
  half is hoisted into RPendingPreSeq and flushed by RParseStatement, and only
  the value half -- `temp.Ok.0` -- is what the expression evaluates to. Same
  shape RParseScrutinee already uses for a non-variable match subject, for the
  same reason.

  Narrowing, deliberate: the two error types must be IDENTICAL. Rust inserts a
  `From::from` conversion on the Err arm, which needs trait dispatch this
  frontend does not have; requiring a match is the honest version, and it
  errors loudly rather than converting wrongly. }
function RParseTryOp(valNode: Integer): Integer;
var recId, ci, retCi, tempSym, errVi, retErrVi: Integer;
    seq, asgn, ifNode, pairNode, thenSeq: Integer;
    tempName: AnsiString;
begin
  recId := RExprRecId(valNode);
  if not RIsResultRec(recId) then
    Error('Rust: `?` needs a Result<T, E> value');
  ci := recId - REC_UCLASS_BASE;
  if (CurProc < 0) or not RIsResultRec(ProcRetRecId[CurProc]) then
    Error('Rust: `?` needs the enclosing fn to return Result<T, E>');
  retCi := ProcRetRecId[CurProc] - REC_UCLASS_BASE;
  if (RResultErrTk[retCi] <> RResultErrTk[ci]) or
     (RResultErrRec[retCi] <> RResultErrRec[ci]) then
    Error('Rust: `?` error types must match -- this frontend has no From conversion');

  { __tryN := expr }
  LastTypeRecId := recId;
  tempName := '__try' + RIntToStr(RTempSerial); Inc(RTempSerial);
  tempSym := AllocVar(tempName, tyRecord);
  asgn := AllocNode(AN_ASSIGN);
  ASTLeft[asgn] := RMakeIdent(tempSym);
  ASTRight[asgn] := valNode;
  seq := RSeqAppend(-1, asgn);

  { if __tryN is Err: copy the payload into the enclosing Result and return }
  errVi := RFindVariantInEnum(ci, 'Err');
  retErrVi := RFindVariantInEnum(retCi, 'Err');
  asgn := AllocNode(AN_ASSIGN);
  ASTLeft[asgn] := REnumField(RMakeIdent(Procs[CurProc].RetSymIdx),
                              ProcRetRecId[CurProc], '__tag');
  ASTRight[asgn] := AllocNode(AN_INT_LIT);
  ASTIVal[ASTRight[asgn]] := REnumVariants[retErrVi].Tag;
  ASTTk[ASTRight[asgn]] := Ord(tyInt64);
  thenSeq := RSeqAppend(-1, asgn);
  asgn := AllocNode(AN_ASSIGN);
  ASTLeft[asgn] := REnumField(RMakeIdent(Procs[CurProc].RetSymIdx),
                              ProcRetRecId[CurProc], 'Err.0');
  ASTRight[asgn] := REnumField(RMakeIdent(tempSym), recId, 'Err.0');
  thenSeq := RSeqAppend(thenSeq, asgn);
  thenSeq := RSeqAppend(thenSeq, AllocNode(AN_EXIT));

  pairNode := AllocNode(AN_PAIR);
  ASTLeft[pairNode] := thenSeq;
  ASTRight[pairNode] := -1;
  ifNode := AllocNode(AN_IF);
  ASTLeft[ifNode] := RTagTest(tempSym, errVi);
  ASTRight[ifNode] := pairNode;
  seq := RSeqAppend(seq, ifNode);

  RPendingPreSeq := RSeqAppend(RPendingPreSeq, seq);
  Result := REnumField(RMakeIdent(tempSym), recId, 'Ok.0');
end;

function RParseIf: Integer;
var node, pairNode, condNode, thenNode, elseNode, preSeq, scrutSym,
    enumCi, vi, bindsSeq: Integer;
    variantName: AnsiString;
begin
  Next; { if }
  { `if let Variant(binds) = scrutinee { .. } [else { .. }]` -- a one-arm
    match, and lowered as exactly that: the same scrutinee materialization,
    the same tag test, the same pattern binds. Nothing about it is
    Option-specific; it works over any enum this frontend knows. }
  if CurTok.Kind = tkLet then
  begin
    Next;
    if CurTok.Kind <> tkIdent then Error('Rust: expected a variant pattern after `if let`');
    variantName := CurTok.SVal; Next;
    if CurTok.Kind = tkPathSep then begin Next; variantName := CurTok.SVal; Next; end;
    { the pattern is parsed AFTER the scrutinee is resolved, because binding a
      name needs the scrutinee's class -- so skip the payload here, note where
      it began, and come back to it. }
    scrutSym := TokPos - 1;          { reuse as the saved pattern position }
    if CurTok.Kind = tkLParen then
    begin
      while (CurTok.Kind <> tkRParen) and (CurTok.Kind <> tkEOF) do Next;
      Next;
    end
    else if CurTok.Kind = tkBegin then
    begin
      while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do Next;
      Next;
    end;
    if CurTok.Kind <> tkAssign then Error('Rust: expected = in `if let`');
    Next;
    enumCi := scrutSym;              { stash the pattern position }
    scrutSym := RParseScrutinee(preSeq);
    if Syms[scrutSym].RecName < REC_UCLASS_BASE then
      Error('Rust: `if let` scrutinee must be an enum value');
    vi := Syms[scrutSym].RecName - REC_UCLASS_BASE;
    if not REnumCi[vi] then Error('Rust: `if let` scrutinee must be an enum value');
    { Rewind to the pattern payload, now that the scrutinee's class is known.
      CurTok is Tokens[TokPos-1], so saving TokPos and restoring it as
      `TokPos := saved - 1; Next` puts the cursor back on exactly the token
      the scrutinee parse stopped at -- the body's opening brace. }
    node := TokPos;
    TokPos := enumCi; Next;
    enumCi := vi;
    vi := RFindVariantInEnum(enumCi, variantName);
    if vi < 0 then Error('Rust: unknown variant ' + variantName + ' in `if let`');
    bindsSeq := RParsePatternBinds(scrutSym, enumCi, vi, variantName);
    TokPos := node - 1; Next;
    Expect(tkBegin, '{');
    thenNode := RSeqAppend(bindsSeq, RParseBlock);
    Expect(tkEnd, '}');
    elseNode := -1;
    if CurTok.Kind = tkElse then
    begin
      Next;
      if CurTok.Kind = tkIf then
        elseNode := RParseIf()
      else
      begin
        Expect(tkBegin, '{');
        elseNode := RParseBlock;
        Expect(tkEnd, '}');
      end;
    end;
    pairNode := AllocNode(AN_PAIR);
    ASTLeft[pairNode] := thenNode; ASTRight[pairNode] := elseNode;
    node := AllocNode(AN_IF);
    ASTLeft[node] := RTagTest(scrutSym, vi); ASTRight[node] := pairNode;
    Result := RSeqAppend(preSeq, node);
    Exit;
  end;
  condNode := RParseExpr;
  Expect(tkBegin, '{');
  thenNode := RParseBlock;
  Expect(tkEnd, '}');
  elseNode := -1;
  if CurTok.Kind = tkElse then
  begin
    Next;
    if CurTok.Kind = tkIf then
      { Bare `RParseIf` here (no parens) would read this function's own
        implicit Result-alias pseudo-variable instead of recursing —
        classic Pascal gotcha, caught by testing (an `else if` chain
        silently lowered to IR_UNSUPPORTED downstream). Parens force an
        actual call, matching pyparser.inc's PyParseIf()'s own precedent. }
      elseNode := RParseIf()
    else
    begin
      Expect(tkBegin, '{');
      elseNode := RParseBlock;
      Expect(tkEnd, '}');
    end;
  end;
  pairNode := AllocNode(AN_PAIR);
  ASTLeft[pairNode] := thenNode;
  ASTRight[pairNode] := elseNode;
  node := AllocNode(AN_IF);
  ASTLeft[node] := condNode;
  ASTRight[node] := pairNode;
  Result := node;
end;

{ Is the `if` at the cursor an if-EXPRESSION in TAIL position -- `fn pick(n:
  i64) -> i64 { if n > 0 { 1 } else { -1 } }`, which is how real Rust writes a
  two-way accessor -- rather than an ordinary if-STATEMENT that merely happens
  to be last?

  Decided by a token scan, not by trying one parse and rewinding: Error()
  aborts, so there is no backtracking to rewind TO, and a speculative parse
  would leave allocated nodes behind either way.

  The discriminator is Rust's own: a block has a VALUE when its last token
  before the closing brace is not a semicolon and the block is not empty.
  Require that of both arms, require the `else` (an if with no else has no
  value -- Rust says so too), and require the whole thing to be followed by a
  closing brace or a comma, which is what puts it in tail position. Anything failing any of those is a statement and goes to RParseIf
  unchanged, so this cannot capture an if that was working before. }
function RIfBlockHasValue(openIdx: Integer; var closeIdx: Integer): Boolean;
var depth, i: Integer;
begin
  Result := False;
  closeIdx := -1;
  if Tokens[openIdx].Kind <> tkBegin then Exit;
  depth := 0; i := openIdx;
  while Tokens[i].Kind <> tkEOF do
  begin
    if Tokens[i].Kind = tkBegin then Inc(depth)
    else if Tokens[i].Kind = tkEnd then
    begin
      Dec(depth);
      if depth = 0 then begin closeIdx := i; Break; end;
    end;
    Inc(i);
  end;
  if closeIdx < 0 then Exit;
  { non-empty, and not statement-terminated }
  Result := (closeIdx > openIdx + 1) and (Tokens[closeIdx - 1].Kind <> tkSemicolon);
end;

function RIfIsTailValue: Boolean;
var i, closeIdx: Integer;
begin
  Result := False;
  if not RTailOK then Exit;
  i := TokPos - 1;
  if Tokens[i].Kind <> tkIf then Exit;
  Inc(i);
  if Tokens[i].Kind = tkLet then Exit;   { `if let` is its own form }
  { the condition cannot contain a bare open-brace -- Rust forbids a struct
    literal there for exactly this reason -- so the first one we meet opens
    the then-block }
  while (Tokens[i].Kind <> tkBegin) and (Tokens[i].Kind <> tkEOF) and
        (Tokens[i].Kind <> tkSemicolon) do Inc(i);
  if not RIfBlockHasValue(i, closeIdx) then Exit;
  if Tokens[closeIdx + 1].Kind <> tkElse then Exit;
  i := closeIdx + 2;
  while Tokens[i].Kind = tkIf do
  begin
    { `else if` chain: each rung must itself be a valued if }
    Inc(i);
    while (Tokens[i].Kind <> tkBegin) and (Tokens[i].Kind <> tkEOF) and
          (Tokens[i].Kind <> tkSemicolon) do Inc(i);
    if not RIfBlockHasValue(i, closeIdx) then Exit;
    if Tokens[closeIdx + 1].Kind <> tkElse then Exit;
    i := closeIdx + 2;
  end;
  if not RIfBlockHasValue(i, closeIdx) then Exit;
  { tail position: the fn body's closing brace, or a bare match arm's comma }
  Result := (Tokens[closeIdx + 1].Kind = tkEnd) or
            (RInMatchArm and (Tokens[closeIdx + 1].Kind = tkComma));
end;

{ `if c { a } else { b }` in a VALUE position -- `let df = if k < 4 { 1 } else
  { 2 };`, which is how real Rust spells what Pascal spells with a temp and two
  assignments. It is not the statement `if`: that one is RParseIf above, still
  dispatched from RParseStatement, and untouched.

  Lowers to the shared AN_TERNARY (Left = condition, Right = AN_PAIR(then,
  else)) -- the same node the C frontend builds for `c ? a : b` and Pascal for
  its own if-expression, so only the SELECTED arm is evaluated and nothing new
  reaches the IR. No Track A change; as with every rung in this window the
  mechanism was already there.

  Two deliberate narrowings. The `else` is REQUIRED, because an if-expression
  with no else has no value -- Rust says the same thing, in its own words
  (`()` is not `i64`). And each arm is a single EXPRESSION, not a block with
  statements and a tail: a block-with-value needs a hidden temp and a
  statement-sequence-in-expression-position, which is a different feature from
  this one and is not what the engine's tables use. }
function RParseIfExpr: Integer;
var condNode, thenNode, elseNode, pairNode, node: Integer;
    thenTk, elseTk: TTypeKind;
begin
  Next; { if }
  condNode := RParseExpr;
  Expect(tkBegin, '{');
  thenNode := RParseExpr;
  Expect(tkEnd, '}');
  if CurTok.Kind <> tkElse then
    Error('Rust: an `if` used as a value needs an `else` arm');
  Next;
  if CurTok.Kind = tkIf then
    { parens force an actual recursive CALL rather than a read of this
      function's own Result alias -- the same Pascal gotcha RParseIf records }
    elseNode := RParseIfExpr()
  else
  begin
    Expect(tkBegin, '{');
    elseNode := RParseExpr;
    Expect(tkEnd, '}');
  end;
  pairNode := AllocNode(AN_PAIR);
  ASTLeft[pairNode] := thenNode;
  ASTRight[pairNode] := elseNode;
  node := AllocNode(AN_TERNARY);
  ASTLeft[node] := condNode;
  ASTRight[node] := pairNode;
  { Matching arms keep their exact kind -- RWiden alone would collapse a
    u64/u64 pair to i32, which is the literal-suffix bug wearing a hat. }
  thenTk := IntToTypeKind(ASTTk[thenNode]);
  elseTk := IntToTypeKind(ASTTk[elseNode]);
  if thenTk = elseTk then ASTTk[node] := Ord(thenTk)
  else ASTTk[node] := Ord(RWiden(thenTk, elseTk));
  Result := node;
end;

function RParseWhile: Integer;
var node: Integer;
begin
  Next; { while }
  node := AllocNode(AN_WHILE);
  ASTLeft[node] := RParseExpr;
  { Anything the condition HOISTED -- a `?` operand, an enum literal's
    materialization -- would be evaluated once, outside the loop, silently and
    wrongly. Refused rather than mis-lowered. `if` is fine and is deliberately
    not guarded: its condition really is evaluated once.

    The message names both constructs rather than just `?` because the second
    one arrived later (rung 15) and a message naming only the first sends the
    reader looking for a `?` that is not there. }
  if RPendingPreSeq >= 0 then
    Error('Rust: this `while` condition needs a hoisted temporary (a `?`, or an enum literal) ' +
          'and would evaluate it once outside the loop -- bind it to a `let` above the loop instead');
  Expect(tkBegin, '{');
  ASTRight[node] := RParseBlock;
  Expect(tkEnd, '}');
  Result := node;
end;

function RParseLoop: Integer;
var node, condNode: Integer;
begin
  Next; { loop }
  Expect(tkBegin, '{');
  node := AllocNode(AN_WHILE);
  condNode := AllocNode(AN_BOOL_LIT); ASTIVal[condNode] := 1; ASTTk[condNode] := Ord(tyBoolean);
  ASTLeft[node] := condNode;
  ASTRight[node] := RParseBlock;
  Expect(tkEnd, '}');
  Result := node;
end;

{ The record id a record-valued expression yields, or REC_NONE when the node
  is not one of the shapes that carries one. }
function RExprRecId(node: Integer): Integer;
begin
  Result := REC_NONE;
  if node < 0 then Exit;
  if ASTKind[node] = AN_CALL then Result := ProcRetRecId[ASTIVal[node]]
  else if ASTKind[node] = AN_IDENT then Result := Syms[ASTIVal[node]].RecName
  { A FIELD / INDEX / DEREF target: the shared ResolveNodeRec already answers
    these (it is what the record-field codegen itself uses). AN_IDENT stays
    special-cased above because ResolveNodeRec answers an ARRAY symbol with its
    ELEMENT record, which is not what a whole-value context wants. }
  else if (ASTKind[node] = AN_FIELD) or (ASTKind[node] = AN_INDEX) or
          (ASTKind[node] = AN_DEREF) then
    Result := ResolveNodeRec(node);
end;

{ Emits the field stores that materialize an Option<T> into an EXISTING target
  symbol. Shared by the `let` initializer and by `return`, which are the two
  places a whole enum value comes into existence -- no AST node carries one
  through an expression, so both spell it as stores into a named slot. }
function ROptionStoreInto(targetSym, optCi: Integer; isSome: Boolean;
  valNode: Integer): Integer;
var fieldNode, tagNode, assignNode, seq: Integer; mangled: AnsiString;
begin
  fieldNode := AllocNode(AN_FIELD);
  ASTLeft[fieldNode] := RMakeIdent(targetSym);
  ASTSOffset[fieldNode] := RStoredName('__tag'); ASTSLen[fieldNode] := 5;
  ASTTk[fieldNode] := Ord(tyInt64);
  tagNode := AllocNode(AN_INT_LIT); ASTTk[tagNode] := Ord(tyInt64);
  if isSome then ASTIVal[tagNode] := 1 else ASTIVal[tagNode] := 0;
  assignNode := AllocNode(AN_ASSIGN);
  ASTLeft[assignNode] := fieldNode; ASTRight[assignNode] := tagNode;
  seq := RSeqAppend(-1, assignNode);
  if isSome then
  begin
    mangled := 'Some.0';
    fieldNode := AllocNode(AN_FIELD);
    ASTLeft[fieldNode] := RMakeIdent(targetSym);
    ASTSOffset[fieldNode] := RStoredName(mangled); ASTSLen[fieldNode] := Length(mangled);
    ASTTk[fieldNode] := Ord(RecFieldType(REC_UCLASS_BASE + optCi, mangled));
    assignNode := AllocNode(AN_ASSIGN);
    ASTLeft[assignNode] := fieldNode; ASTRight[assignNode] := valNode;
    seq := RSeqAppend(seq, assignNode);
  end;
  Result := seq;
end;

{ The class an AGGREGATE LITERAL at the cursor builds, or -1 when the cursor
  is not at one. Does not consume. `expectCi` is the class the context knows
  the value must have (a `let` annotation, or the enclosing fn's return
  record); it is what resolves a BARE variant name, which cannot name its own
  class -- and for a monomorphized Option<T> it is the only thing that can,
  since every instantiation spells its variants `Some`/`None`. Pass -1 when
  there is no expectation. }
function RPeekAggregateCi(expectCi: Integer): Integer;
var ci, vi: Integer;
begin
  Result := -1;
  if CurTok.Kind <> tkIdent then Exit;
  ci := FindUClass(CurTok.SVal);
  if ci >= 0 then
  begin
    { `Enum::Variant ...` }
    if REnumCi[ci] and (Tokens[TokPos].Kind = tkPathSep) then Result := ci
    { `Name(..)` tuple-struct / `Name { .. }` named-field literal. An enum's
      own name followed by neither is not a literal, and `Type::assoc(..)` is
      a call, so both fall through to the expression path. }
    else if (not REnumCi[ci]) and
            ((Tokens[TokPos].Kind = tkLParen) or (Tokens[TokPos].Kind = tkBegin)) then
      Result := ci;
    Exit;
  end;
  { a bare variant name: the expected class first, the global table second }
  if (expectCi >= 0) and REnumCi[expectCi] and
     (RFindVariantInEnum(expectCi, CurTok.SVal) >= 0) then
  begin
    Result := expectCi;
    Exit;
  end;
  vi := RFindVariantBare(CurTok.SVal);
  if vi >= 0 then Result := REnumVariants[vi].EnumCi;
end;

{ A struct name followed by an open brace, where the name is a plain
  (non-enum) struct: a struct literal, in a position where the grammar has
  already ruled out a block. Deliberately NOT folded into
  RPeekExprAggregateCi -- that one runs at every RParsePrimary, and in
  statement position an open brace after an expression is a BLOCK (the `if`,
  `while` and `match` heads all end that way), so reading the pair as a
  literal is only safe inside a bracket run. }
function RPeekStructLitCi: Integer;
var ci: Integer;
begin
  Result := -1;
  if CurTok.Kind <> tkIdent then Exit;
  ci := FindUClass(CurTok.SVal);
  if ci < 0 then Exit;
  if REnumCi[ci] then Exit;
  if Tokens[TokPos].Kind <> tkBegin then Exit;
  Result := ci;
end;

{ `base[k]` with a literal index. `base` is deliberately SHARED by every element
  node built from it rather than rebuilt per slot -- a target lvalue is a pure
  address chain, so the AST is a DAG here and that is fine (the field-store and
  array-literal arms have always done it). }
function RArrIndexNode(baseNode, k, tk: Integer): Integer;
var idxNode: Integer;
begin
  idxNode := AllocNode(AN_INT_LIT); ASTIVal[idxNode] := k; ASTTk[idxNode] := Ord(tyInt64);
  Result := AllocNode(AN_INDEX);
  ASTLeft[Result] := baseNode; ASTRight[Result] := idxNode;
  ASTTk[Result] := tk;
end;

{ One field's initializer, stored into an already-built field node. Three
  shapes, and the recursion is what makes a nested literal work:
    `ep: None` / `side: Color::White`  -> a nested aggregate literal
    `squares: [0; 64]` / `[a, b, c]`   -> unrolled to one store per element
    anything else                      -> an ordinary expression assignment }
function RStoreFieldValue(fieldNode, fieldRec, arrLen: Integer): Integer;
var valNode, assignNode, idxNode, elemNode, k, n, aggCi: Integer;
begin
  Result := -1;
  if (arrLen > 0) and (CurTok.Kind = tkLBrack) then
  begin
    Next;
    aggCi := RPeekStructLitCi;
    if aggCi >= 0 then
    begin
      { A struct-literal repeat as a field initializer. Rust's `[e; N]` on a
        Copy type is "evaluate once, copy N-1 times", and that is literally
        what this emits -- the literal fills slot 0 and every other slot is a
        whole-record copy of it. The scalar arm below re-evaluates per slot
        instead (a documented deviation); it cannot be done that way here,
        because an aggregate literal has no expression form to re-evaluate. }
      Result := RParseAggregateIntoNode(RArrIndexNode(fieldNode, 0, ASTTk[fieldNode]), aggCi);
      Expect(tkSemicolon, ';');
      if CurTok.Kind <> tkInteger then Error('Rust: repeat count must be an integer literal');
      n := CurTok.IVal;
      Next;
      Expect(tkRBrack, ']');
      if n <> arrLen then Error('Rust: repeat count does not match the array field length');
      for k := 1 to n - 1 do
      begin
        assignNode := AllocNode(AN_ASSIGN);
        ASTLeft[assignNode] := RArrIndexNode(fieldNode, k, ASTTk[fieldNode]);
        ASTRight[assignNode] := RArrIndexNode(fieldNode, 0, ASTTk[fieldNode]);
        Result := RSeqAppend(Result, assignNode);
      end;
      Exit;
    end;
    valNode := RParseExpr;
    if CurTok.Kind = tkSemicolon then
    begin
      { `[v; N]` repeat. Deviation, same one the let-level array literal
        documents: the element expression is re-evaluated per slot. }
      Next;
      if CurTok.Kind <> tkInteger then Error('Rust: repeat count must be an integer literal');
      n := CurTok.IVal;
      Next;
      Expect(tkRBrack, ']');
      if n <> arrLen then Error('Rust: repeat count does not match the array field length');
      for k := 0 to n - 1 do
      begin
        idxNode := AllocNode(AN_INT_LIT); ASTIVal[idxNode] := k; ASTTk[idxNode] := Ord(tyInt64);
        elemNode := AllocNode(AN_INDEX);
        ASTLeft[elemNode] := fieldNode; ASTRight[elemNode] := idxNode;
        ASTTk[elemNode] := ASTTk[fieldNode];
        assignNode := AllocNode(AN_ASSIGN);
        ASTLeft[assignNode] := elemNode; ASTRight[assignNode] := valNode;
        Result := RSeqAppend(Result, assignNode);
      end;
      Exit;
    end;
    k := 0;
    while True do
    begin
      if k >= arrLen then Error('Rust: too many elements for the array field');
      idxNode := AllocNode(AN_INT_LIT); ASTIVal[idxNode] := k; ASTTk[idxNode] := Ord(tyInt64);
      elemNode := AllocNode(AN_INDEX);
      ASTLeft[elemNode] := fieldNode; ASTRight[elemNode] := idxNode;
      ASTTk[elemNode] := ASTTk[fieldNode];
      assignNode := AllocNode(AN_ASSIGN);
      ASTLeft[assignNode] := elemNode; ASTRight[assignNode] := valNode;
      Result := RSeqAppend(Result, assignNode);
      Inc(k);
      if not Eat(tkComma) then Break;
      if CurTok.Kind = tkRBrack then Break;
      valNode := RParseExpr;
    end;
    Expect(tkRBrack, ']');
    Exit;
  end;
  if fieldRec >= REC_UCLASS_BASE then
  begin
    k := RPeekAggregateCi(fieldRec - REC_UCLASS_BASE);
    if k >= 0 then
    begin
      Result := RParseAggregateIntoNode(fieldNode, k);
      Exit;
    end;
  end;
  valNode := RParseExpr;
  assignNode := AllocNode(AN_ASSIGN);
  ASTLeft[assignNode] := fieldNode; ASTRight[assignNode] := valNode;
  Result := RSeqAppend(-1, assignNode);
end;

function RParseAggregateIntoNode(targetNode, ci: Integer): Integer;
var vi, k, tagNode, fieldNode, assignNode, seq, fTokIdx: Integer;
    variantName, fname, mangled: AnsiString;
begin
  seq := -1;
  if REnumCi[ci] then
  begin
    if (FindUClass(CurTok.SVal) = ci) and (Tokens[TokPos].Kind = tkPathSep) then
    begin
      Next; Next; { EnumName :: }
      if CurTok.Kind <> tkIdent then Error('Rust: expected variant name after ::');
    end;
    vi := RFindVariantInEnum(ci, CurTok.SVal);
    if vi < 0 then Error('Rust: unknown variant ' + CurTok.SVal);
    variantName := REnumVariants[vi].Name;
    Next;
    fieldNode := AllocNode(AN_FIELD);
    ASTLeft[fieldNode] := targetNode;
    ASTSOffset[fieldNode] := RStoredName('__tag'); ASTSLen[fieldNode] := 5;
    ASTTk[fieldNode] := Ord(tyInt64);
    tagNode := AllocNode(AN_INT_LIT);
    ASTIVal[tagNode] := REnumVariants[vi].Tag; ASTTk[tagNode] := Ord(tyInt64);
    assignNode := AllocNode(AN_ASSIGN);
    ASTLeft[assignNode] := fieldNode; ASTRight[assignNode] := tagNode;
    seq := RSeqAppend(seq, assignNode);
    case REnumVariants[vi].Kind of
      RVAR_TUPLE:
      begin
        Expect(tkLParen, '(');
        k := 0;
        if CurTok.Kind <> tkRParen then
          repeat
            mangled := variantName + '.' + RIntToStr(k);
            fieldNode := AllocNode(AN_FIELD);
            ASTLeft[fieldNode] := targetNode;
            ASTSOffset[fieldNode] := RStoredName(mangled); ASTSLen[fieldNode] := Length(mangled);
            ASTTk[fieldNode] := Ord(RecFieldType(REC_UCLASS_BASE + ci, mangled));
            seq := RSeqAppend(seq, RStoreFieldValue(fieldNode,
              RecFieldRecId(REC_UCLASS_BASE + ci, mangled),
              RFieldArrLen(REC_UCLASS_BASE + ci, mangled)));
            Inc(k);
          until not Eat(tkComma);
        Expect(tkRParen, ')');
      end;
      RVAR_STRUCT:
      begin
        Expect(tkBegin, '{');
        while CurTok.Kind <> tkEnd do
        begin
          if CurTok.Kind <> tkIdent then Error('Rust: expected field name in variant literal');
          fname := CurTok.SVal; Next;
          Expect(tkColon, ':');
          mangled := variantName + '.' + fname;
          fieldNode := AllocNode(AN_FIELD);
          ASTLeft[fieldNode] := targetNode;
          ASTSOffset[fieldNode] := RStoredName(mangled); ASTSLen[fieldNode] := Length(mangled);
          ASTTk[fieldNode] := Ord(RecFieldType(REC_UCLASS_BASE + ci, mangled));
          seq := RSeqAppend(seq, RStoreFieldValue(fieldNode,
            RecFieldRecId(REC_UCLASS_BASE + ci, mangled),
            RFieldArrLen(REC_UCLASS_BASE + ci, mangled)));
          if not Eat(tkComma) then Break;
        end;
        Expect(tkEnd, '}');
      end;
    end; { RVAR_UNIT: no payload }
    Result := seq;
    Exit;
  end;
  Next; { the struct name }
  if CurTok.Kind = tkLParen then
  begin
    { tuple struct `Name(a, b)` — fields are named "0", "1", ... }
    Next;
    k := 0;
    if CurTok.Kind <> tkRParen then
      repeat
        mangled := RIntToStr(k);
        fieldNode := AllocNode(AN_FIELD);
        ASTLeft[fieldNode] := targetNode;
        ASTSOffset[fieldNode] := RStoredName(mangled); ASTSLen[fieldNode] := Length(mangled);
        ASTTk[fieldNode] := Ord(RecFieldType(REC_UCLASS_BASE + ci, mangled));
        seq := RSeqAppend(seq, RStoreFieldValue(fieldNode,
          RecFieldRecId(REC_UCLASS_BASE + ci, mangled),
          RFieldArrLen(REC_UCLASS_BASE + ci, mangled)));
        Inc(k);
      until not Eat(tkComma);
    Expect(tkRParen, ')');
    Result := seq;
    Exit;
  end;
  Expect(tkBegin, '{');
  while CurTok.Kind <> tkEnd do
  begin
    if CurTok.Kind <> tkIdent then Error('Rust: expected field name in struct literal');
    fTokIdx := TokPos - 1;
    fname := CurTok.SVal;
    Next;
    Expect(tkColon, ':');
    fieldNode := AllocNode(AN_FIELD);
    ASTLeft[fieldNode] := targetNode;
    ASTSOffset[fieldNode] := Tokens[fTokIdx].SOffset;
    ASTSLen[fieldNode] := Tokens[fTokIdx].SLen;
    ASTTk[fieldNode] := Ord(RecFieldType(REC_UCLASS_BASE + ci, fname));
    seq := RSeqAppend(seq, RStoreFieldValue(fieldNode,
      RecFieldRecId(REC_UCLASS_BASE + ci, fname),
      RFieldArrLen(REC_UCLASS_BASE + ci, fname)));
    if not Eat(tkComma) then Break;
  end;
  Expect(tkEnd, '}');
  Result := seq;
end;

{ Same, into a named symbol. }
function RParseAggregateInto(targetSym, ci: Integer): Integer;
begin
  Result := RParseAggregateIntoNode(RMakeIdent(targetSym), ci);
end;

{ `let [mut] name [: Type] [= expr];` — mut is accepted and ignored (no
  borrow/mutability enforcement, per the umbrella's non-goal list). Two RHS
  shapes: a plain scalar expression, or a struct literal `Type { f: v, ... }`
  which lowers to one AN_ASSIGN per field (no single-node "construct" op
  exists for value-type structs, so the declaration is really N field
  stores chained by AN_SEQ). Trailing `;` is left for the caller. }
{ `[v; N]` repeat form or `[a, b, c]` list at the cursor (CurTok on `[`),
  allocating `name` as a fixed array and unrolling to one AN_INDEX store per
  element -- the same per-slot shape struct literals use, and for the same
  reason: no AST node carries a whole aggregate value.

  `annotLen` > 0 is the `[T; N]` annotation (element kind in `annotTk`), 0 means
  infer both from the literal itself. Lifted out of RParseLet so the top-level
  `const NAME: [T; N] = [...]` prescan can share it rather than grow a second
  copy -- the array-literal parser is exactly the kind of thing that gets fixed
  on one arm and left broken on the other.

  Repeat-form deviation, unchanged from when this lived inline: the element
  expression is re-evaluated per slot. }
function RParseArrayLiteral(const name: AnsiString; annotTk: TTypeKind;
                            annotLen: Integer): Integer;
var symIdx, seq, k, ci, ci2, vi, valNode, tagNode, fieldNode, assignNode,
    arrLen, aggCi: Integer;
    arrElemTk: TTypeKind;
    isArr: Boolean;
begin
  isArr := annotLen > 0;
  arrElemTk := annotTk;
  arrLen := annotLen;
    Next; { [ }
    aggCi := RPeekStructLitCi;
    if aggCi >= 0 then
    begin
      { A struct-literal repeat -- same evaluate-once/copy-the-rest lowering as
        the struct-field arm in RStoreFieldValue, and for the same reason. The
        count is scanned ahead of the parse because AllocArray needs the length
        before the element can be stored, and in `[e; N]` the count comes
        AFTER e. }
      ci := TokPos - 1; vi := 1;
      while (vi > 0) and (Tokens[ci].Kind <> tkEOF) do
      begin
        if Tokens[ci].Kind in [tkLBrack, tkLParen, tkBegin] then Inc(vi)
        else if Tokens[ci].Kind in [tkRBrack, tkRParen, tkEnd] then Dec(vi)
        else if (Tokens[ci].Kind = tkSemicolon) and (vi = 1) then Break;
        Inc(ci);
      end;
      if (Tokens[ci].Kind <> tkSemicolon) or (Tokens[ci + 1].Kind <> tkInteger) then
        Error('Rust: an array of struct literals needs the repeat form: [Name { .. }; N]');
      k := Tokens[ci + 1].IVal;
      if isArr and (k <> arrLen) then Error('Rust: repeat count does not match the [T; N] annotation');
      arrLen := k;
      if arrLen <= 0 then Error('Rust: array length must be positive');
      arrElemTk := tyRecord;
      LastTypeRecId := REC_UCLASS_BASE + aggCi;
      symIdx := AllocArray(name, tyRecord, 0, arrLen - 1);
      seq := RParseAggregateIntoNode(
        RArrIndexNode(RMakeIdent(symIdx), 0, Ord(tyRecord)), aggCi);
      Expect(tkSemicolon, ';');
      Next; { the count, already read by the scan }
      Expect(tkRBrack, ']');
      for k := 1 to arrLen - 1 do
      begin
        assignNode := AllocNode(AN_ASSIGN);
        ASTLeft[assignNode] := RArrIndexNode(RMakeIdent(symIdx), k, Ord(tyRecord));
        ASTRight[assignNode] := RArrIndexNode(RMakeIdent(symIdx), 0, Ord(tyRecord));
        seq := RSeqAppend(seq, assignNode);
      end;
      Result := seq;
      Exit;
    end;
    valNode := RParseExpr;
    if not isArr then
    begin
      arrElemTk := IntToTypeKind(ASTTk[valNode]);
      if arrElemTk = tyInteger then arrElemTk := tyInt64;
    end;
    if CurTok.Kind = tkSemicolon then
    begin
      { [v; N] repeat }
      Next;
      if CurTok.Kind <> tkInteger then Error('Rust: repeat count must be an integer literal');
      k := CurTok.IVal;
      Next;
      Expect(tkRBrack, ']');
      if isArr and (k <> arrLen) then Error('Rust: repeat count does not match the [T; N] annotation');
      arrLen := k;
      symIdx := AllocArray(name, arrElemTk, 0, arrLen - 1);
      seq := -1;
      for k := 0 to arrLen - 1 do
      begin
        tagNode := AllocNode(AN_INT_LIT); ASTIVal[tagNode] := k; ASTTk[tagNode] := Ord(tyInt64);
        fieldNode := AllocNode(AN_INDEX);
        ASTLeft[fieldNode] := RMakeIdent(symIdx);
        ASTRight[fieldNode] := tagNode;
        ASTTk[fieldNode] := Ord(arrElemTk);
        assignNode := AllocNode(AN_ASSIGN);
        ASTLeft[assignNode] := fieldNode; ASTRight[assignNode] := valNode;
        seq := RSeqAppend(seq, assignNode);
      end;
      Result := seq;
      Exit;
    end;
    { [a, b, c] list }
    symIdx := -1; seq := -1; k := 0;
    repeat
      if symIdx < 0 then
      begin
        { length unknown until parsed — but AllocArray needs it up front;
          count ahead over the tokens (list elements are expressions, so
          count top-level commas in the bracket run). }
        ci := TokPos - 1; ci2 := 1; vi := 1; { vi = depth, ci2 = count }
        while (vi > 0) and (Tokens[ci].Kind <> tkEOF) do
        begin
          if Tokens[ci].Kind in [tkLBrack, tkLParen] then Inc(vi)
          else if Tokens[ci].Kind in [tkRBrack, tkRParen] then Dec(vi)
          else if (Tokens[ci].Kind = tkComma) and (vi = 1) then Inc(ci2);
          Inc(ci);
        end;
        if isArr and (ci2 <> arrLen) then Error('Rust: list length does not match the [T; N] annotation');
        arrLen := ci2;
        symIdx := AllocArray(name, arrElemTk, 0, arrLen - 1);
      end;
      tagNode := AllocNode(AN_INT_LIT); ASTIVal[tagNode] := k; ASTTk[tagNode] := Ord(tyInt64);
      fieldNode := AllocNode(AN_INDEX);
      ASTLeft[fieldNode] := RMakeIdent(symIdx);
      ASTRight[fieldNode] := tagNode;
      ASTTk[fieldNode] := Ord(arrElemTk);
      assignNode := AllocNode(AN_ASSIGN);
      ASTLeft[assignNode] := fieldNode; ASTRight[assignNode] := valNode;
      seq := RSeqAppend(seq, assignNode);
      Inc(k);
      if not Eat(tkComma) then Break;
      valNode := RParseExpr;
    until False;
    Expect(tkRBrack, ']');
    Result := seq;
end;

function RParseLet: Integer;
var name, typeName, variantName, fname, mangled: AnsiString;
    symIdx, ci, structCi, fTokIdx, ci2, vi, k, tagOff, tagNode, tagAssign: Integer;
    annotTk, arrElemTk: TTypeKind; hasType, qualified, isArr: Boolean;
    identNode, fieldNode, valNode, assignNode, seq, arrLen, loNode, hiNode: Integer;
    arrElemRecId, optCi, arrSym: Integer;
    payTk: TTypeKind; isSome: Boolean;
begin
  Next; { let }
  if CurTok.Kind = tkMut then Next;
  if CurTok.Kind <> tkIdent then Error('Rust: expected variable name after let');
  name := CurTok.SVal; Next;
  hasType := False; annotTk := tyUnknown; structCi := -1;
  isArr := False; arrElemTk := tyUnknown; arrLen := 0; arrElemRecId := REC_NONE;
  if CurTok.Kind = tkColon then
  begin
    Next;
    if CurTok.Kind = tkLBrack then
    begin
      { `[T; N]` fixed-array annotation. T may be a struct/enum: a fixed array
        of records is stored + indexed by the shared codegen (ElemRecName), and
        `arr[i].field` resolves via ResolveNodeRec(AN_INDEX). }
      Next;
      if CurTok.Kind <> tkIdent then Error('Rust: expected element type in [T; N]');
      arrElemTk := RTypeKindFromName(RTypeNameCur, True);
      arrElemRecId := LastTypeRecId;
      Expect(tkSemicolon, ';');
      if CurTok.Kind <> tkInteger then Error('Rust: array length must be an integer literal (skeleton)');
      arrLen := CurTok.IVal;
      if arrLen <= 0 then Error('Rust: array length must be positive');
      Next;
      Expect(tkRBrack, ']');
      isArr := True;
    end
    else
    begin
      if CurTok.Kind <> tkIdent then Error('Rust: expected type after :');
      typeName := RTypeNameCur;
      structCi := FindUClass(typeName);
      annotTk := RTypeKindFromName(typeName, True);
    end;
    hasType := True;
  end;
  if CurTok.Kind <> tkAssign then
  begin
    if not hasType then Error('Rust: let without initializer needs a type annotation');
    if isArr then
    begin
      { fixed array of a record type: AllocArray reads LastTypeRecId for the
        element's size + ElemRecName (uninitialised is allowed here — pxx does
        not enforce Rust's definite-init; the movegen fills slots field-wise). }
      if arrElemTk = tyRecord then LastTypeRecId := arrElemRecId;
      AllocArray(name, arrElemTk, 0, arrLen - 1);
      Result := -1;
      Exit;
    end;
    if annotTk = tyRecord then LastTypeRecId := REC_UCLASS_BASE + structCi;
    symIdx := AllocVar(name, annotTk);
    Result := -1;
    Exit;
  end;
  Next; { = }
  { array literal RHS -- one shared implementation, see RParseArrayLiteral }
  if (isArr and (CurTok.Kind = tkLBrack)) or
     ((not hasType) and (CurTok.Kind = tkLBrack) and not RBrackHasDotDotAt(TokPos - 1)) then
  begin
    if isArr then Result := RParseArrayLiteral(name, arrElemTk, arrLen)
    else Result := RParseArrayLiteral(name, tyUnknown, 0);
    Exit;
  end;
  { whole-array RHS: `let t: [T; N] = build();` or `let t = build();` where
    `build` returns `[T; N]`, and `let b: [T; N] = a;` copying another array.
    One branch covers all three because the shared lowering already does: an
    AN_ASSIGN whose LHS is a fixed-array ident emits IR_COPY_REC from a CALL
    (sized by ProcRetFixedArrBytes -- the call's value IS the hidden
    destination's address) and from an LVALUE array alike.

    Without it the annotated form fell through to the scalar path and `t` was
    allocated as ONE element, so `t[0]` was not even an index -- the parse
    failed rather than miscompiling, which is the lucky half of this. The
    UNANNOTATED form is the one that matters for real source, since `let t =
    attacks();` is how it is actually written, and there the callee's
    registered return shape is the only thing that knows the length. }
  k := -1;
  if not hasType then k := RPeekArrayRetProc;
  if isArr or (k >= 0) then
  begin
    if not isArr then
    begin
      arrElemTk := Procs[k].RetType;
      arrElemRecId := ProcRetRecId[k];
      arrLen := RProcRetArrLen[k];
    end;
    valNode := RParseExpr;
    if arrElemTk = tyRecord then LastTypeRecId := arrElemRecId;
    symIdx := AllocArray(name, arrElemTk, 0, arrLen - 1);
    assignNode := AllocNode(AN_ASSIGN);
    ASTLeft[assignNode] := RMakeIdent(symIdx);
    ASTRight[assignNode] := valNode;
    Result := assignNode;
    Exit;
  end;
  { borrowed slice RHS: `&arr[lo..hi]` — __ptr := &arr[lo], __len := hi-lo
    (the Zig frontend's slice-creation shape ported back) }
  if (CurTok.Kind = tkAmp) and (Tokens[TokPos].Kind = tkIdent) and
     (Tokens[TokPos + 1].Kind = tkLBrack) and RBrackHasDotDotAt(TokPos + 1) then
  begin
    Next; { & }
    symIdx := FindSym(CurTok.SVal);
    if (symIdx < 0) or not Syms[symIdx].IsArray then
      Error('Rust: slicing needs a fixed-array variable (skeleton)');
    arrElemTk := Syms[symIdx].ElemType;
    Next;
    Expect(tkLBrack, '[');
    loNode := RParseExpr;
    Expect(tkDotDot, '..');
    hiNode := RParseExpr;
    Expect(tkRBrack, ']');
    ci := RSliceClassForRec(arrElemTk, Syms[symIdx].ElemRecName);
    LastTypeRecId := REC_UCLASS_BASE + ci;
    arrSym := symIdx;
    symIdx := AllocVar(name, tyRecord);
    Result := RSliceHeaderStores(symIdx, arrSym, loNode, hiNode);
    Exit;
  end;
  { Option<T> literal RHS: `Some(expr)` / `None`. Resolved against the
    ANNOTATED class when there is one, otherwise against the payload
    expression's own type (`let x = Some(3);` infers Option<i64>) -- never
    through the bare-variant table, which by construction cannot tell two
    instantiations' `Some` apart. A bare `None` has nothing to infer from, so
    it needs the annotation. Checked ahead of the general enum-literal branch
    below because those names are deliberately NOT unique across enums here. }
  if (CurTok.Kind = tkIdent) and ((CurTok.SVal = 'Some') or (CurTok.SVal = 'None')) and
     (FindUClass(CurTok.SVal) < 0) and (RFindVariantBare(CurTok.SVal) < 0) then
  begin
    isSome := CurTok.SVal = 'Some';
    Next;
    optCi := -1;
    if hasType and (annotTk = tyRecord) and (structCi >= 0) and ROptionCi[structCi] then
      optCi := structCi
    else if hasType then
      Error('Rust: Some/None initializer needs an Option<T> annotation, not ' + typeName);
    valNode := -1;
    if isSome then
    begin
      Expect(tkLParen, '(');
      valNode := RParseExpr;
      Expect(tkRParen, ')');
      if optCi < 0 then
      begin
        payTk := IntToTypeKind(ASTTk[valNode]);
        if payTk = tyInteger then payTk := tyInt64;
        if payTk = tyRecord then
          Error('Rust: Some(<struct>) needs an explicit Option<T> annotation');
        optCi := ROptionClassForRec(payTk, REC_NONE);
      end;
    end
    else if optCi < 0 then
      Error('Rust: `let ' + name + ' = None;` needs an Option<T> type annotation');
    LastTypeRecId := REC_UCLASS_BASE + optCi;
    symIdx := AllocVar(name, tyRecord);
    Result := ROptionStoreInto(symIdx, optCi, isSome, valNode);
    Exit;
  end;
  { every other aggregate literal -- an enum variant (bare or
    `Enum::Variant`), a tuple struct `Name(a, b)`, a named-field
    `Name { f: v }` -- goes through the one shared implementation, which the
    `return` path uses too. }
  ci := RPeekAggregateCi(structCi);
  if ci >= 0 then
  begin
    LastTypeRecId := REC_UCLASS_BASE + ci;
    symIdx := AllocVar(name, tyRecord);
    Result := RParseAggregateInto(symIdx, ci);
    Exit;
  end;
  { plain initializer — scalar, or a record-valued expression (today: a call
    to a record/Option-returning fn), which gets the SOURCE's record id and
    is copied by the shared AN_ASSIGN exactly as Pascal's `r := MakeR(x)` is. }
  valNode := RParseExpr;
  payTk := IntToTypeKind(ASTTk[valNode]);
  if payTk = tyRecord then
  begin
    optCi := RExprRecId(valNode);
    if optCi < REC_UCLASS_BASE then
      Error('Rust: cannot infer the record type of the initializer for ' + name);
    if hasType and ((annotTk <> tyRecord) or (REC_UCLASS_BASE + structCi <> optCi)) then
      Error('Rust: the type annotation on ' + name + ' does not match its initializer');
    LastTypeRecId := optCi;
    symIdx := AllocVar(name, tyRecord);
  end
  else if hasType then
  begin
    if annotTk = tyRecord then Error('Rust: struct assignment from a non-literal expression is not supported by the skeleton yet');
    symIdx := AllocVar(name, annotTk);
  end
  else
    symIdx := AllocVar(name, payTk);
  identNode := RMakeIdent(symIdx);
  assignNode := AllocNode(AN_ASSIGN);
  ASTLeft[assignNode] := identNode;
  ASTRight[assignNode] := valNode;
  Result := assignNode;
end;

{ `match scrutinee { Pat1(a, b) => { .. }, Pat2 { f } => { .. }, _ => { .. } }`
  Desugars entirely to a chain of AN_IF nodes comparing __tag; each arm's
  bound names are fresh AllocVar locals assigned from the mangled payload
  field before the arm body is parsed (see the file-header note on scoping).
  Scrutinee must be a plain local variable of enum type (skeleton narrowing:
  no temp-materializing of an arbitrary scrutinee expression yet). }
function RParseMatch: Integer;
var scrutSym, recId, enumCi, vi, i, armCount,
    condNode, bodyNode, bindsSeq, pairNode, chain, preSeq: Integer;
    variantName: AnsiString;
    isWildcard, savedTail: Boolean;
    arms: array[0..R_MAX_MATCH_ARMS-1] of TRMatchArm;
begin
  Next; { 'match' }
  savedTail := RTailOK; RTailOK := False;
  scrutSym := RParseScrutinee(preSeq);
  recId := Syms[scrutSym].RecName;
  if recId < REC_UCLASS_BASE then Error('Rust: match scrutinee must be an enum value');
  enumCi := recId - REC_UCLASS_BASE;
  if not REnumCi[enumCi] then Error('Rust: match scrutinee must be an enum value');

  Expect(tkBegin, '{');
  armCount := 0;
  while CurTok.Kind <> tkEnd do
  begin
    if armCount >= R_MAX_MATCH_ARMS then Error('Rust: too many match arms (skeleton limit)');
    isWildcard := False; vi := -1;
    if CurTok.Kind <> tkIdent then Error('Rust: expected a pattern in match arm');
    if CurTok.SVal = '_' then
    begin
      isWildcard := True;
      Next;
    end
    else
    begin
      variantName := CurTok.SVal; Next;
      if CurTok.Kind = tkPathSep then begin Next; variantName := CurTok.SVal; Next; end;
      vi := RFindVariantInEnum(enumCi, variantName);
      if vi < 0 then Error('Rust: unknown variant ' + variantName + ' in match');
    end;

    bindsSeq := -1;
    if not isWildcard then
      bindsSeq := RParsePatternBinds(scrutSym, enumCi, vi, variantName);

    { `=>` — two plain tokens (assign, then gt), same trick as `->` uses;
      no dedicated fat-arrow token needed. }
    if CurTok.Kind <> tkAssign then Error('Rust: expected => after match pattern');
    Next;
    if CurTok.Kind <> tkGt then Error('Rust: expected => after match pattern');
    Next;

    { Rust writes most arms as a bare expression (`Some(v) => f(v),`) and
      reserves the braced block for multi-statement arms. `match` is a
      statement here, so a bare arm is just one statement -- no
      value-of-a-match machinery needed for the common spelling. }
    if CurTok.Kind = tkBegin then
    begin
      Next;
      bodyNode := RSeqAppend(bindsSeq, RParseBlock);
      Expect(tkEnd, '}');
    end
    else
    begin
      { A bare arm is one statement, and it INHERITS the match's own
        tail-ness: `fn flip(self) -> Color { match self { White => Black,
        Black => White } }` is a match EXPRESSION in Rust, and its arms are
        the fn's return values. Matches modelled as statements get the same
        effect by letting each arm's single statement be a tail. Stated
        explicitly rather than left to fall out of the flag not being
        cleared, which is how it behaved before. }
      RInMatchArm := True;
      RTailOK := savedTail;
      bodyNode := RSeqAppend(bindsSeq, RParseStatement);
      RInMatchArm := False;
      RTailOK := False;
    end;
    Eat(tkComma);

    arms[armCount].IsWildcard := isWildcard;
    arms[armCount].BodyNode := bodyNode;
    if not isWildcard then arms[armCount].CondNode := RTagTest(scrutSym, vi);
    Inc(armCount);
  end;
  Expect(tkEnd, '}');

  { fold right-to-left into a nested if/else chain; no exhaustiveness check
    (non-goal) — if nothing matches the value falls through as a no-op. }
  chain := -1;
  for i := armCount - 1 downto 0 do
  begin
    if arms[i].IsWildcard then
      chain := arms[i].BodyNode
    else
    begin
      pairNode := AllocNode(AN_PAIR);
      ASTLeft[pairNode] := arms[i].BodyNode; ASTRight[pairNode] := chain;
      condNode := AllocNode(AN_IF);
      ASTLeft[condNode] := arms[i].CondNode; ASTRight[condNode] := pairNode;
      chain := condNode;
    end;
  end;
  RTailOK := savedTail;
  Result := RSeqAppend(preSeq, chain);
end;

{ Stage-0 corpus trivia (feature-rust-corpus-chess): compact the token
  stream in place, dropping top-level items this frontend treats as
  no-ops BEFORE any prescan runs (single choke point for all passes):
  - `use ...;`            (module imports — unity-build route instead)
  - `[pub] type X = ...;` (aliases — uses of the alias error later)
  - `pub` / `pub(...)`    (visibility — dropped everywhere at depth 0)
  Brace depth guards against touching identically-named idents inside
  function bodies. }
procedure RStripTopItems;
var src, dst, depth: Integer;
begin
  { Pass one collects `mod x;` names. Separate from the compaction below
    because a `mod` item may sit BELOW a use of its qualifier, and a
    single forward pass would then strip nothing. }
  RModCount := 0;
  src := 0; depth := 0;
  while Tokens[src].Kind <> tkEOF do
  begin
    if Tokens[src].Kind = tkBegin then Inc(depth)
    else if Tokens[src].Kind = tkEnd then Dec(depth)
    else if (depth = 0) and (Tokens[src].Kind = tkIdent) and (GetTokenStr(src) = 'mod') and
            (Tokens[src + 1].Kind = tkIdent) and (Tokens[src + 2].Kind = tkSemicolon) and
            (RModCount < R_MAX_ALIASES) then
    begin
      RModName[RModCount] := GetTokenStr(src + 1);
      Inc(RModCount);
    end;
    Inc(src);
  end;

  src := 0; dst := 0; depth := 0;
  while Tokens[src].Kind <> tkEOF do
  begin
    if Tokens[src].Kind = tkBegin then Inc(depth)
    else if Tokens[src].Kind = tkEnd then Dec(depth);
    if (depth = 0) and (Tokens[src].Kind = tkIdent) and
       ((GetTokenStr(src) = 'use') or (GetTokenStr(src) = 'mod')) then
    begin
      while (Tokens[src].Kind <> tkSemicolon) and (Tokens[src].Kind <> tkEOF) do Inc(src);
      if Tokens[src].Kind = tkSemicolon then Inc(src);
      Continue;
    end;
    if (depth = 0) and (Tokens[src].Kind = tkIdent) and (GetTokenStr(src) = 'type') then
    begin
      { RECORD it before dropping it. `type X = Y;` used to vanish whole and
        every use of X then died on `unknown type X` -- which the corpus hits
        on its first line, since `pub type Bitboard = u64;` is how a bitboard
        engine names its one central type. Single-token targets only; anything
        else falls through to the old drop-and-error, so this cannot break a
        program that compiled before. }
      if (Tokens[src + 1].Kind = tkIdent) and (Tokens[src + 2].Kind = tkAssign) and
         (Tokens[src + 3].Kind = tkIdent) and (Tokens[src + 4].Kind = tkSemicolon) and
         (RAliasCount < R_MAX_ALIASES) then
      begin
        RAliasName[RAliasCount] := GetTokenStr(src + 1);
        RAliasTarget[RAliasCount] := GetTokenStr(src + 3);
        Inc(RAliasCount);
      end;
      while (Tokens[src].Kind <> tkSemicolon) and (Tokens[src].Kind <> tkEOF) do Inc(src);
      if Tokens[src].Kind = tkSemicolon then Inc(src);
      Continue;
    end;
    { MODULE QUALIFIER dropped at any depth: `attacks::knight(sq)` and
      `crate::board::Board::new()` become `knight(sq)` and `Board::new()`,
      which is what they mean once the modules are one file. Only names a
      `mod` item declared, plus the `crate`/`self`/`super` keywords -- a TYPE
      path (`Color::White`, `Board::new`, `Self::EMPTY`) is left alone, which
      is the whole reason this is a table lookup and not a rule about
      capitalisation. Chains fall out for free: after dropping `crate ::` the
      loop re-examines `board ::` at the same position. }
    if (Tokens[src].Kind = tkIdent) and (Tokens[src + 1].Kind = tkPathSep) and
       RIsModuleQualifier(GetTokenStr(src)) then
    begin
      Inc(src, 2);
      Continue;
    end;
    { `pub` dropped at ANY depth — item visibility at depth 0, field
      visibility inside struct bodies. A user variable literally named
      `pub` would vanish too; that is not legal Rust anyway. }
    if (Tokens[src].Kind = tkIdent) and (GetTokenStr(src) = 'pub') then
    begin
      Inc(src);
      if Tokens[src].Kind = tkLParen then
      begin
        while (Tokens[src].Kind <> tkRParen) and (Tokens[src].Kind <> tkEOF) do Inc(src);
        Inc(src); { ) }
      end;
      Continue;
    end;
    Tokens[dst] := Tokens[src];
    Inc(src); Inc(dst);
  end;
  Tokens[dst] := Tokens[src]; { EOF }
  TokCount := dst + 1;
  MainProgramTokCount := TokCount;
end;

{ `const NAME: T = value;` at top level — scalar integer/bool constants
  registered via AddConst (folded at use sites through the existing
  skConst path). Array constants `const X: [T; N] = [...]` are SKIPPED
  whole for now (stage 2 of the chess-corpus ladder needs them as
  initialized globals; uses error until then). }
procedure RParseTopLevelConst;
var name: AnsiString; tk: TTypeKind; v: Int64; neg: Boolean; depth: Integer;
begin
  Next; { const }
  if CurTok.Kind <> tkIdent then Error('Rust: expected constant name after const');
  name := CurTok.SVal;
  Next;
  Expect(tkColon, ':');
  if CurTok.Kind = tkLBrack then
  begin
    { array constant — swallow the whole item (semicolons occur INSIDE
      the brackets: [T; N] and [v; N], so track bracket depth) }
    depth := 0;
    while CurTok.Kind <> tkEOF do
    begin
      if CurTok.Kind = tkLBrack then Inc(depth)
      else if CurTok.Kind = tkRBrack then Dec(depth)
      else if (CurTok.Kind = tkSemicolon) and (depth = 0) then Break;
      Next;
    end;
    Expect(tkSemicolon, ';');
    Exit;
  end;
  if CurTok.Kind <> tkIdent then Error('Rust: expected type in const ' + name);
  tk := RTypeKindFromName(CurTok.SVal, False);
  Next;
  Expect(tkAssign, '=');
  neg := False;
  if CurTok.Kind = tkMinus then begin neg := True; Next; end;
  if CurTok.Kind = tkTrue then begin v := 1; Next; end
  else if CurTok.Kind = tkFalse then begin v := 0; Next; end
  else if CurTok.Kind = tkInteger then begin v := CurTok.IVal; Next; end
  else
  begin
    Error('Rust: const ' + name + ' needs a literal value (skeleton)');
    v := 0;
  end;
  if neg then v := -v;
  AddConst(name, tk, v);
  Expect(tkSemicolon, ';');
end;

{ `for i in lo..hi { }` (exclusive) / `for i in lo..=hi { }` (inclusive) —
  desugars to i := lo; while i </<= hi { body; i := i + 1 }, the same
  AN_ASSIGN/AN_WHILE shape the Zig frontend's range for uses. The loop
  variable is a fresh i64 local (no iterator protocol, ranges only). }
function RParseFor: Integer;
var vname: AnsiString;
    symIdx, loNode, hiNode, bodyNode, initNode, condNode, incNode, oneNode, whileNode: Integer;
    inclusive: Boolean;
begin
  Next; { for }
  if CurTok.Kind <> tkIdent then Error('Rust: expected loop variable after for');
  vname := CurTok.SVal;
  Next;
  if not ((CurTok.Kind = tkIdent) and (CurTok.SVal = 'in')) then
    Error('Rust: expected `in` after the for loop variable');
  Next;
  loNode := RParseExpr;
  inclusive := (CurTok.Kind = tkDotDotEq);
  if not inclusive and (CurTok.Kind <> tkDotDot) then
    Error('Rust: for supports integer ranges only (lo..hi / lo..=hi, skeleton)');
  Next;
  hiNode := RParseExpr;

  symIdx := AllocVar(vname, tyInt64);

  Expect(tkBegin, '{');
  bodyNode := RParseBlock;
  Expect(tkEnd, '}');

  initNode := AllocNode(AN_ASSIGN);
  ASTLeft[initNode] := RMakeIdent(symIdx);
  ASTRight[initNode] := loNode;

  if inclusive then
    condNode := RBinOp(tkLe, RMakeIdent(symIdx), hiNode, tyBoolean)
  else
    condNode := RBinOp(tkLt, RMakeIdent(symIdx), hiNode, tyBoolean);

  oneNode := AllocNode(AN_INT_LIT);
  ASTIVal[oneNode] := 1;
  ASTTk[oneNode] := Ord(tyInteger);
  incNode := AllocNode(AN_ASSIGN);
  ASTLeft[incNode] := RMakeIdent(symIdx);
  ASTRight[incNode] := RBinOp(tkPlus, RMakeIdent(symIdx), oneNode, tyInt64);
  bodyNode := RSeqAppend(bodyNode, incNode);

  whileNode := AllocNode(AN_WHILE);
  ASTLeft[whileNode] := condNode;
  ASTRight[whileNode] := bodyNode;

  Result := RSeqAppend(RSeqAppend(-1, initNode), whileNode);
end;

{ Flatten `{:?}` over a record into RDbgText/RDbgNode. Rust's derived Debug
  for a struct is `Name { field: value, field: value }`, and that is exactly
  what this builds -- literal, field, literal, field.

  WHY THIS EXISTS AT ALL: before it, `println!("{:?}", pos)` printed `1`. The
  scanner treated `{:?}` as an ordinary placeholder and the write path,
  handed a record, wrote its FIRST FIELD. A derived-Debug struct rendered as a
  single integer, silently, in real output -- the fourth plausible wrong value
  this frontend has produced and the same shape as the other three.

  A nested record field recurses. A STRING field is quoted, because Debug
  quotes where Display does not. An ENUM is refused: Rust's Debug for one
  prints the VARIANT NAME, which is a runtime switch on __tag rather than a
  static item list, and printing a wrong-but-plausible tag number instead is
  precisely the failure this routine was written to end. An ARRAY field is
  refused for the same reason -- rendering it needs a loop, and half-rendering
  it would look like a value. }
{ TokSliceStr does exactly this, but it lives in rtti_emit.inc, which FPC's
  include stream reaches AFTER this file -- so calling it here compiles under
  pxx and breaks the seed build. Six lines beats a forward into a later unit.
  bug-r-rexprrecid-breaks-the-fpc-bootstrap-seed }
function RCharSlice(off, len: Integer): AnsiString;
var s: AnsiString; i: Integer;
begin
  s := '';
  i := 0;
  while i < len do begin AppendChar(s, TokChars[off + i]); Inc(i); end;
  RCharSlice := s;
end;

{ Is this placeholder's spec the Debug one? `{}` / `{:?}` are the two forms
  this frontend understands; anything else (`{:x}`, `{:>8}`, `{:.3}`) is
  REFUSED rather than silently rendered as `{}`, because a width or a radix
  that is quietly ignored produces output that looks right and is not. }
function RSpecIsDebug(fmtOff, start, len: Integer): Boolean;
var spec: AnsiString;
begin
  spec := RCharSlice(fmtOff + start, len);
  if spec = '' then begin Result := False; Exit; end;
  if spec = ':?' then begin Result := True; Exit; end;
  Error('Rust: format spec `{' + spec + '}` is not supported (only `{}` and `{:?}`)');
  Result := False;
end;

procedure RDebugExpand(recvNode, recId: Integer; const prefix: AnsiString);
var ci, base, cnt, k, fi, fieldNode: Integer;
    fname: AnsiString; ftk: TTypeKind; frec: Integer;
begin
  ci := recId - REC_UCLASS_BASE;
  if REnumCi[ci] then
    Error('Rust: `{:?}` of an enum is not supported yet (Debug prints the variant name, ' +
          'which needs a runtime switch on the tag) -- match on it and print the arm');
  base := UClsFBase[ci];
  cnt := UClsFCount[ci];
  if RDbgCount + 2 * cnt + 2 >= 255 then Error('Rust: `{:?}` value is too deeply nested');

  RDbgText[RDbgCount] := prefix + RTypeNameOf(ci) + ' { ';
  RDbgNode[RDbgCount] := -1;
  Inc(RDbgCount);

  for k := 0 to cnt - 1 do
  begin
    fi := base + k;
    fname := RCharSlice(UFldNOff[fi], UFldNLen[fi]);
    ftk := IntToTypeKind(UFldTk[fi]);
    frec := UFldRec_[fi];

    fieldNode := AllocNode(AN_FIELD);
    ASTLeft[fieldNode] := recvNode;
    ASTSOffset[fieldNode] := UFldNOff[fi];
    ASTSLen[fieldNode] := UFldNLen[fi];
    ASTTk[fieldNode] := Ord(ftk);

    if (ftk = tyRecord) and (frec >= REC_UCLASS_BASE) then
    begin
      RDebugExpand(fieldNode, frec, fname + ': ');
      { the separator belongs to the item AFTER a nested record, so append it
        as text-only rather than folding it into a field item }
      if k < cnt - 1 then
      begin
        RDbgText[RDbgCount] := ', ';
        RDbgNode[RDbgCount] := -1;
        Inc(RDbgCount);
      end;
      Continue;
    end;

    if RIsStrTk(ftk) then
    begin
      RDbgText[RDbgCount] := fname + ': "';
      RDbgNode[RDbgCount] := fieldNode;
      Inc(RDbgCount);
      RDbgText[RDbgCount] := '"';
      RDbgNode[RDbgCount] := -1;
      if k < cnt - 1 then RDbgText[RDbgCount] := '", ';
      Inc(RDbgCount);
      Continue;
    end;

    RDbgText[RDbgCount] := fname + ': ';
    RDbgNode[RDbgCount] := fieldNode;
    Inc(RDbgCount);
    if k < cnt - 1 then
    begin
      RDbgText[RDbgCount] := ', ';
      RDbgNode[RDbgCount] := -1;
      Inc(RDbgCount);
    end;
  end;

  RDbgText[RDbgCount] := ' }';
  RDbgNode[RDbgCount] := -1;
  Inc(RDbgCount);
end;

{ `println!("fmt {} ...", args);` / `print!(...)` — the Zig frontend's
  std.debug.print splitter ported back (feature-rust-misc-semantics #9 +
  feature-rust-rtl-macros-io #12, the format-output subset): literal fmt
  segments become AN_STR_LIT nodes pointing straight into the fmt token's
  already-decoded TokChars bytes, each {...} placeholder ({}, {:?}, ...)
  consumes the next argument, everything chains as one AN_ARG list under
  a single AN_WRITE / AN_WRITELN. {{ }} escapes are not handled. }
function RParsePrintln(isLn: Boolean): Integer;
var fmtOff, fmtLen, i, segStart, specStart: Integer;
    node, lastArg, argNode, litNode, seq, emitted: Integer;
    argExprs: array[0..7] of Integer;
    argCount, argUsed: Integer;
    isDbg: Boolean;

  { A string literal as a one-argument write node. }
  function WriteLit(const t: AnsiString): Integer;
  var w, a2, l2: Integer;
  begin
    l2 := RStrLit(t);
    a2 := AllocNode(AN_ARG);
    ASTLeft[a2] := l2; ASTRight[a2] := -1;
    w := AllocNode(AN_WRITE);
    ASTLeft[w] := a2;
    WriteLit := w;
  end;

  { Close the write node under construction and hand it to the sequence.
    `asLn` turns it into the WRITELN that ends the statement. }
  procedure FlushWrite(asLn: Boolean);
  begin
    if (node < 0) and asLn then
    begin
      { every placeholder was a bool, so there is no trailing text -- but the
        newline still has to happen }
      node := AllocNode(AN_WRITE);
      ASTLeft[node] := -1;
    end;
    if node < 0 then Exit;
    if asLn then ASTKind[node] := AN_WRITELN;
    seq := RSeqAppend(seq, node);
    Inc(emitted);
    node := -1;
    lastArg := -1;
  end;

  procedure AddArg(exprNode: Integer);
  var ifNode, pairNode: Integer;
  begin
    { Rust prints a bool as `true`/`false`; the shared Write renders tyBoolean
      in Pascal's spelling, `TRUE`/`FALSE`. That is a WRONG STRING in the
      output of any Rust program that prints one -- silent, and invisible until
      somebody reads the output expecting Rust.

      Chosen in the FRONTEND rather than taught to the shared writer, because
      the spelling is a property of the language and not of the value: Pascal's
      `TRUE` is correct for Pascal and must stay.

      Lowered as a branch between two literal WRITES rather than as a ternary
      over two strings. That was the first attempt and it does not work here:
      a string-valued ternary needs a temp and the managed-string runtime,
      which this frontend deliberately does not emit (`wantAnsiRuntime` is
      False -- Rust strings are &str slices), so it failed with `call to a
      runtime stub that was never emitted`. Splitting the write costs one
      branch and no runtime at all. }
    if IntToTypeKind(ASTTk[exprNode]) = tyBoolean then
    begin
      FlushWrite(False);
      pairNode := AllocNode(AN_PAIR);
      ASTLeft[pairNode] := WriteLit('true');
      ASTRight[pairNode] := WriteLit('false');
      ifNode := AllocNode(AN_IF);
      ASTLeft[ifNode] := exprNode;
      ASTRight[ifNode] := pairNode;
      seq := RSeqAppend(seq, ifNode);
      Inc(emitted);
      Exit;
    end;
    if node < 0 then
    begin
      node := AllocNode(AN_WRITE);
      ASTLeft[node] := -1;
      lastArg := -1;
    end;
    argNode := AllocNode(AN_ARG);
    ASTLeft[argNode] := exprNode;
    ASTRight[argNode] := -1;
    if lastArg < 0 then ASTLeft[node] := argNode else ASTRight[lastArg] := argNode;
    lastArg := argNode;
  end;

  procedure AddSegment(off, len: Integer);
  begin
    if len <= 0 then Exit;
    litNode := AllocNode(AN_STR_LIT);
    ASTSOffset[litNode] := off;
    ASTSLen[litNode] := len;
    ASTTk[litNode] := Ord(tyString);
    AddArg(litNode);
  end;

  procedure AddText(const t: AnsiString);
  begin
    if t = '' then Exit;
    AddArg(RStrLit(t));
  end;

  { One placeholder's worth of output. `{}` is Display and `{:?}` is Debug,
    and the difference MATTERS in three places: a record has no Display at all
    (rustc refuses it, and so does this -- writing its first field is what the
    old code did), a string is quoted under Debug and bare under Display, and
    everything else renders the same either way.

    A record's Debug is expanded into literal/field items and each item
    becomes an ordinary write, so this path needs no string runtime at all --
    which is why a `{:?}` on a struct does not drag in 60KB the way building
    the same text as a VALUE would. }
  procedure AddFormatted(exprNode: Integer; dbg: Boolean);
  var recId, k: Integer;
  begin
    recId := RExprRecId(exprNode);
    if (IntToTypeKind(ASTTk[exprNode]) = tyRecord) and (recId >= REC_UCLASS_BASE) then
    begin
      if not dbg then
      begin
        k := RDisplayCall(exprNode, recId);
        if k < 0 then
          Error('Rust: `{}` needs Display and this type has none -- use `{:?}`, ' +
                'implement `fmt::Display`, or print the fields');
        AddArg(k);
        Exit;
      end;
      RDbgCount := 0;
      RDebugExpand(exprNode, recId, '');
      for k := 0 to RDbgCount - 1 do
      begin
        AddText(RDbgText[k]);
        if RDbgNode[k] >= 0 then AddArg(RDbgNode[k]);
      end;
      Exit;
    end;
    { Debug quotes what Display leaves bare: a string in double quotes, a
      char in single ones. Every other scalar renders identically either way. }
    if dbg and RIsStrTk(IntToTypeKind(ASTTk[exprNode])) then
    begin
      AddText('"'); AddArg(exprNode); AddText('"');
      Exit;
    end;
    if dbg and (IntToTypeKind(ASTTk[exprNode]) = tyChar) then
    begin
      AddText(''''); AddArg(exprNode); AddText('''');
      Exit;
    end;
    AddArg(exprNode);
  end;

begin
  Next; { println / print }
  Next; { ! }
  Expect(tkLParen, '(');
  if CurTok.Kind <> tkString then Error('Rust: println!/print! need a string literal format');
  fmtOff := Tokens[TokPos - 1].SOffset;
  fmtLen := Tokens[TokPos - 1].SLen;
  Next;

  argCount := 0;
  while Eat(tkComma) do
  begin
    if argCount > 7 then Error('Rust: println! supports at most 8 arguments (skeleton)');
    argExprs[argCount] := RParseExpr;
    Inc(argCount);
  end;
  Expect(tkRParen, ')');

  node := -1;
  lastArg := -1;
  seq := -1;
  emitted := 0;
  argUsed := 0;

  segStart := 0;
  i := 0;
  while i < fmtLen do
  begin
    if TokChars[fmtOff + i] = '{' then
    begin
      AddSegment(fmtOff + segStart, i - segStart);
      specStart := i + 1;
      while (i < fmtLen) and (TokChars[fmtOff + i] <> '}') do Inc(i);
      if i >= fmtLen then Error('Rust: unterminated {} placeholder in format string');
      isDbg := RSpecIsDebug(fmtOff, specStart, i - specStart);
      Inc(i); { step past the closing brace }
      segStart := i;
      if argUsed >= argCount then Error('Rust: more {} placeholders than arguments');
      AddFormatted(argExprs[argUsed], isDbg);
      Inc(argUsed);
    end
    else
      Inc(i);
  end;
  AddSegment(fmtOff + segStart, fmtLen - segStart);
  if argUsed < argCount then Error('Rust: more arguments than {} placeholders');
  FlushWrite(isLn);

  { the overwhelmingly common case is one write node and no bool -- hand it
    back unwrapped, so nothing about the AST changes for a format string that
    never needed splitting }
  if emitted = 1 then Result := ASTLeft[seq] else Result := seq;
end;

{ An AGGREGATE LITERAL in a value position of a record-returning fn: stores
  it into the Result slot and hands back that chain plus a valueless AN_EXIT,
  or -1 when the cursor is not at one. Shared by explicit `return <lit>;` and
  by the implicit tail, which are the same thing written two ways. The
  enclosing fn's return record is the expected class, which is what lets a
  BARE `Some`/`None` resolve there at all. }
function RTryReturnAggregate: Integer;
var ci: Integer;
begin
  Result := -1;
  if (CurProc < 0) or (Procs[CurProc].RetType <> tyRecord) then Exit;
  if ProcRetRecId[CurProc] < REC_UCLASS_BASE then Exit;
  ci := RPeekAggregateCi(ProcRetRecId[CurProc] - REC_UCLASS_BASE);
  if ci < 0 then Exit;
  Result := RSeqAppend(RParseAggregateInto(Procs[CurProc].RetSymIdx, ci),
                       AllocNode(AN_EXIT));
end;

{ A value in RETURN position -- the explicit `return <expr>;` and the implicit
  tail are the same thing written two ways, so they go through here.

  For an ARRAY-returning fn the plain AN_EXIT is wrong and wrong QUIETLY: it
  lowers as a scalar store into Result, which for a fixed-array Result writes
  the source's ADDRESS into element 0 and leaves the rest untouched. Measured,
  not reasoned -- `store_sym Result := lea(a)` where a 32-byte copy belongs.
  The caller then copied its 32 bytes faithfully, so `[0,1,4,9]` came back as a
  stack address and three zeros, with nothing anywhere reporting a fault.

  So lower it the way the record rung already lowers `return Some(x)`: an
  explicit assignment into the Result slot, which reaches the whole-array
  IR_COPY_REC arm, then a VALUELESS return. Same shape and the same underlying
  reason -- no AST node carries a whole aggregate through an expression. }
function RReturnValue(valNode: Integer): Integer;
var node: Integer;
begin
  if (valNode >= 0) and (CurProc >= 0) and (RProcRetArrLen[CurProc] > 0) then
  begin
    node := AllocNode(AN_ASSIGN);
    ASTLeft[node] := RMakeIdent(Procs[CurProc].RetSymIdx);
    ASTRight[node] := valNode;
    Result := RSeqAppend(node, AllocNode(AN_EXIT));
    Exit;
  end;
  Result := AllocNode(AN_EXIT);
  ASTLeft[Result] := valNode;
end;

{ The single flush point for statements hoisted out of an expression (today:
  the `?` try operator's operand materialization and its early-return arm).
  A wrapper rather than a line at each `Exit` because RParseStatementInner has
  a dozen exits and the one that gets forgotten is the one that silently drops
  the early return.

  Save/restore rather than assign, so a nested statement -- an `if` body, a
  match arm -- flushes its own pending work at its own level instead of
  letting it escape to the enclosing statement. }
function RParseStatementInner: Integer; forward;

function RParseStatement: Integer;
var saved: Integer;
begin
  saved := RPendingPreSeq;
  RPendingPreSeq := -1;
  Result := RParseStatementInner;
  if RPendingPreSeq >= 0 then Result := RSeqAppend(RPendingPreSeq, Result);
  RPendingPreSeq := saved;
end;

function RParseStatementInner: Integer;
var name, fname: AnsiString; symIdx, node, rhsNode, lhsNode, baseNode, fieldNode, fTokIdx: Integer;
    opTk: TTokenKind; isSome: Boolean;
begin
  case CurTok.Kind of
    tkIf:
    begin
      { a tail if-EXPRESSION is a value, not a statement -- see RIfIsTailValue.
        Parsed as an expression here and wrapped by the ordinary tail check
        below, so it shares one path with every other tail value. }
      if RIfIsTailValue then Result := RReturnValue(RParseIfExpr)
      else Result := RParseIf;
      Exit;
    end;
    tkWhile: begin Result := RParseWhile; Exit; end;
    tkLoop: begin Result := RParseLoop; Exit; end;
    tkFor: begin Result := RParseFor; Exit; end;
    tkBegin: begin Next; Result := RParseBlock; Expect(tkEnd, '}'); Exit; end;
    tkSemicolon: begin Next; Result := -1; Exit; end;
    tkLet: begin Result := RParseLet; RExpectStmtEnd; Exit; end;
    tkExit:
    begin
      Next;
      { `return <aggregate literal>;` from a record-returning fn -- `Some(e)`,
        `None`, `Square(i)`, `Board { .. }`, `Enum::Variant(..)`. The value is
        materialized into the Result slot by field stores and then a plain
        valueless return: the same shape `let` uses, through the same
        RParseAggregateInto, for the same reason (no AST node carries a whole
        struct or enum value through an expression). The enclosing fn's return
        record is the expected class, which is what lets a BARE `Some`/`None`
        resolve at all. }
      node := RTryReturnAggregate;
      if node >= 0 then
      begin
        RExpectStmtEnd;
        Result := node;
        Exit;
      end;
      if CurTok.Kind <> tkSemicolon then node := RReturnValue(RParseExpr)
      else node := RReturnValue(-1);
      RExpectStmtEnd;
      Result := node;
      Exit;
    end;
    tkBreak: begin Next; RExpectStmtEnd; Result := AllocNode(AN_BREAK); Exit; end;
    tkContinue: begin Next; RExpectStmtEnd; Result := AllocNode(AN_CONTINUE); Exit; end;
  end;

  { the implicit tail written as an aggregate literal --
    `fn new(i: u8) -> Square { Square(i) }`, which is how an associated
    constructor is spelled in real source. Same lowering as the explicit
    `return Square(i);` right above, and only in a fn body (RTailOK). }
  if RTailOK then
  begin
    node := RTryReturnAggregate;
    if node >= 0 then begin Result := node; Exit; end;
  end;

  if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'match') then begin Result := RParseMatch; Exit; end;

  if (CurTok.Kind = tkIdent) and (Tokens[TokPos].Kind = tkLogNot) and
     (Tokens[TokPos + 1].Kind = tkLParen) and
     ((CurTok.SVal = 'println') or (CurTok.SVal = 'print')) then
  begin
    Result := RParsePrintln(CurTok.SVal = 'println');
    RExpectStmtEnd;
    Exit;
  end;

  if (CurTok.Kind = tkIdent) and (Tokens[TokPos].Kind = tkLogNot) and
     (Tokens[TokPos + 1].Kind = tkLParen) and
     ((CurTok.SVal = 'write') or (CurTok.SVal = 'writeln')) then
  begin
    Result := RParseWriteMacro(CurTok.SVal = 'writeln');
    { `write!(f, ..)?;` is the idiomatic spelling: the `?` propagates the
      fmt::Result to the caller. Once the reroute has replaced the Result with
      a String there is nothing left to propagate, so the `?` is consumed and
      dropped rather than sent to RParseTryOp, which would look for an
      enclosing fn returning Result and refuse. }
    if CurTok.Kind = tkQuestion then Next;
    { a `write!` is usually the TAIL expression of a fmt body and carries no
      semicolon -- so the terminator is optional here, unlike println!'s }
    if CurTok.Kind = tkSemicolon then Next;
    Exit;
  end;

  { `Ok(())` as the tail of a Display fmt body: the trait's way of saying
    "wrote it all", and there is nothing left to say once write! appends
    directly. A no-op rather than an error, because every real Display impl
    ends with one. }
  if RInDisplayFmt and (CurTok.Kind = tkIdent) and (CurTok.SVal = 'Ok') and
     (Tokens[TokPos].Kind = tkLParen) and (Tokens[TokPos + 1].Kind = tkLParen) and
     (Tokens[TokPos + 2].Kind = tkRParen) and (Tokens[TokPos + 3].Kind = tkRParen) then
  begin
    Next; Next; Next; Next; Next;
    if CurTok.Kind = tkSemicolon then Next;
    Result := AllocNode(AN_BLOCK);
    ASTLeft[Result] := -1;
    Exit;
  end;

  if (CurTok.Kind = tkIdent) and (Tokens[TokPos].Kind in
      [tkAssign, tkPlusEq, tkMinusEq, tkStarEq, tkSlashEq,
       tkAmpEq, tkPipeEq, tkXorEq, tkShlEq, tkShrEq]) then
  begin
    name := CurTok.SVal;
    symIdx := FindSym(name);
    if symIdx < 0 then Error('Rust: assignment to undefined variable ' + name);
    Next;
    opTk := CurTok.Kind;
    Next;
    rhsNode := RParseExpr;
    { compound forms desugar to name = name op expr (bit ops land on the
      shared Pascal-style tkAnd/tkOr/tkXor/tkShl/tkShr BINOPs) }
    case opTk of
      tkPlusEq:  rhsNode := RBinOp(tkPlus,  RMakeIdent(symIdx), rhsNode, Syms[symIdx].TypeKind);
      tkMinusEq: rhsNode := RBinOp(tkMinus, RMakeIdent(symIdx), rhsNode, Syms[symIdx].TypeKind);
      tkStarEq:  rhsNode := RBinOp(tkStar,  RMakeIdent(symIdx), rhsNode, Syms[symIdx].TypeKind);
      tkSlashEq:
        if (Syms[symIdx].TypeKind = tyDouble) or (Syms[symIdx].TypeKind = tySingle) then
          rhsNode := RBinOp(tkSlash, RMakeIdent(symIdx), rhsNode, Syms[symIdx].TypeKind)
        else
          rhsNode := RBinOp(tkDiv, RMakeIdent(symIdx), rhsNode, Syms[symIdx].TypeKind);
      tkAmpEq:   rhsNode := RBinOp(tkAnd,   RMakeIdent(symIdx), rhsNode, Syms[symIdx].TypeKind);
      tkPipeEq:  rhsNode := RBinOp(tkOr,    RMakeIdent(symIdx), rhsNode, Syms[symIdx].TypeKind);
      tkXorEq:   rhsNode := RBinOp(tkXor,   RMakeIdent(symIdx), rhsNode, Syms[symIdx].TypeKind);
      tkShlEq:   rhsNode := RBinOp(tkShl,   RMakeIdent(symIdx), rhsNode, Syms[symIdx].TypeKind);
      tkShrEq:
        if TypeSigned(Syms[symIdx].TypeKind) then
          rhsNode := RBinOp(tkShr, RMakeIdent(symIdx), rhsNode, Syms[symIdx].TypeKind)
        else
          rhsNode := RBinOp(tkShrLogical, RMakeIdent(symIdx), rhsNode, Syms[symIdx].TypeKind);
      else ;
    end;
    lhsNode := RMakeIdent(symIdx);
    node := AllocNode(AN_ASSIGN);
    ASTLeft[node] := lhsNode; ASTRight[node] := rhsNode;
    RExpectStmtEnd;
    Result := node;
    Exit;
  end;

  { `b = Board { .. };` — re-assigning a whole aggregate to an existing record
    variable, the plain-identifier twin of the field case below. }
  if (CurTok.Kind = tkIdent) and (Tokens[TokPos].Kind = tkAssign) then
  begin
    symIdx := FindSym(CurTok.SVal);
    if SymOwnClassIdx(symIdx) >= 0 then
    begin
      name := CurTok.SVal;
      Next; Next; { name = }
      fTokIdx := RPeekAggregateCi(SymOwnClassIdx(symIdx));
      if fTokIdx >= 0 then
      begin
        Result := RParseAggregateIntoNode(RMakeIdent(symIdx), fTokIdx);
        RExpectStmtEnd;
        Exit;
      end;
      node := AllocNode(AN_ASSIGN);
      ASTLeft[node] := RMakeIdent(symIdx);
      ASTRight[node] := RParseExpr;
      RExpectStmtEnd;
      Result := node;
      Exit;
    end;
  end;

  if (CurTok.Kind = tkIdent) and (Tokens[TokPos].Kind = tkDot) and
     (Tokens[TokPos + 1].Kind = tkIdent) and (Tokens[TokPos + 2].Kind = tkAssign) then
  begin
    name := CurTok.SVal;
    symIdx := FindSym(name);
    if symIdx < 0 then Error('Rust: assignment to undefined variable ' + name);
    Next; Next; { ident, . }
    fname := CurTok.SVal;
    fTokIdx := TokPos - 1;
    Next; Expect(tkAssign, '=');
    baseNode := RMakeIdent(symIdx);
    fieldNode := AllocNode(AN_FIELD);
    ASTLeft[fieldNode] := baseNode;
    ASTSOffset[fieldNode] := Tokens[fTokIdx].SOffset;
    ASTSLen[fieldNode] := Tokens[fTokIdx].SLen;
    ASTTk[fieldNode] := Ord(RecFieldType(SymOwnRecOf(symIdx), fname));
    { `self.ep = Some(sq);` — an aggregate literal stored straight into a
      record-typed FIELD. The same RParseAggregateIntoNode the `let` and
      `return` paths use, with the TARGET as the base node instead of a fresh
      local; nothing else can express a whole enum value in this position. }
    { SymOwnRecOf: Rust has no array-to-pointer decay, so `a.field` on an array
      is a user error and must NOT resolve against the ELEMENT's record the way
      C's `arr->field` deliberately does. REC_NONE is the right answer here.
      audit-a-typekind-tyrecord-is-not-a-guard-against-an-array-symbol }
    node := RecFieldRecId(SymOwnRecOf(symIdx), fname);
    if node >= REC_UCLASS_BASE then
    begin
      node := RPeekAggregateCi(node - REC_UCLASS_BASE);
      if node >= 0 then
      begin
        Result := RParseAggregateIntoNode(fieldNode, node);
        RExpectStmtEnd;
        Exit;
      end;
    end;
    rhsNode := RParseExpr;
    node := AllocNode(AN_ASSIGN);
    ASTLeft[node] := fieldNode; ASTRight[node] := rhsNode;
    RExpectStmtEnd;
    Result := node;
    Exit;
  end;

  Result := RParseExpr;
  { `a[i] = e;` / `s[i] = e;` / `a[i].field = e;` — indexed and
    indexed-field stores parse as an expression followed by `=` (AN_INDEX,
    slice AN_DEREF, and AN_FIELD over an indexed record are all valid assign
    targets). }
  { Rust's implicit tail return: the last expression of a fn BODY, with no
    trailing `;`, IS the return value. `fn file(self) -> u8 { self.0 % 8 }` is
    how real source spells a one-line accessor; an explicit `return` is the
    exception there, not the rule. RTailOK is what confines this to a fn body
    -- see RParseFnBody. }
  if RTailOK and ((CurTok.Kind = tkEnd) or
                  (RInMatchArm and (CurTok.Kind = tkComma))) then
  begin
    Result := RReturnValue(Result);
    Exit;
  end;
  if ((CurTok.Kind = tkAssign) or (CurTok.Kind in
        [tkPlusEq, tkMinusEq, tkStarEq, tkSlashEq,
         tkAmpEq, tkPipeEq, tkXorEq, tkShlEq, tkShrEq])) and
     ((ASTKind[Result] = AN_INDEX) or (ASTKind[Result] = AN_DEREF) or
      (ASTKind[Result] = AN_FIELD)) then
  begin
    opTk := CurTok.Kind;
    Next;
    { `self.ep = Some(sq);` — an aggregate literal stored straight into a
      record-typed FIELD (or array element). Same RParseAggregateIntoNode the
      `let` and `return` paths use, with the TARGET as the base node instead
      of a fresh local; nothing else can express a whole enum value here. }
    if opTk = tkAssign then
    begin
      symIdx := RExprRecId(Result);
      if symIdx >= REC_UCLASS_BASE then
      begin
        fTokIdx := RPeekAggregateCi(symIdx - REC_UCLASS_BASE);
        if fTokIdx >= 0 then
        begin
          Result := RParseAggregateIntoNode(Result, fTokIdx);
          RExpectStmtEnd;
          Exit;
        end;
      end;
    end;
    rhsNode := RParseExpr;
    { Compound forms on a FIELD / INDEX / slice target desugar the way the
      plain-identifier ones above do -- `self.n += 1` is `self.n = self.n + 1`
      -- by naming the target subtree on both sides of the store. Documented
      consequence: a target with a side-effecting subscript (`a[f()] += 1`)
      evaluates that subscript twice. Rust source that does this is rare
      enough not to pay for a temp-materializing lvalue path yet; it is a
      narrowing, not a silent wrong answer, and it is stated here. }
    if opTk <> tkAssign then
    begin
      case opTk of
        tkPlusEq:  rhsNode := RBinOp(tkPlus,  Result, rhsNode, IntToTypeKind(ASTTk[Result]));
        tkMinusEq: rhsNode := RBinOp(tkMinus, Result, rhsNode, IntToTypeKind(ASTTk[Result]));
        tkStarEq:  rhsNode := RBinOp(tkStar,  Result, rhsNode, IntToTypeKind(ASTTk[Result]));
        tkSlashEq: rhsNode := RBinOp(tkDiv,   Result, rhsNode, IntToTypeKind(ASTTk[Result]));
        tkAmpEq:   rhsNode := RBinOp(tkAnd,   Result, rhsNode, IntToTypeKind(ASTTk[Result]));
        tkPipeEq:  rhsNode := RBinOp(tkOr,    Result, rhsNode, IntToTypeKind(ASTTk[Result]));
        tkXorEq:   rhsNode := RBinOp(tkXor,   Result, rhsNode, IntToTypeKind(ASTTk[Result]));
        tkShlEq:   rhsNode := RBinOp(tkShl,   Result, rhsNode, IntToTypeKind(ASTTk[Result]));
        tkShrEq:
          { unsigned `>>=` is a LOGICAL shift; RParseShift spells that
            tkShrLogical, so spell it the same way here. }
          if TypeSigned(IntToTypeKind(ASTTk[Result])) then
            rhsNode := RBinOp(tkShr, Result, rhsNode, IntToTypeKind(ASTTk[Result]))
          else
            rhsNode := RBinOp(tkShrLogical, Result, rhsNode, IntToTypeKind(ASTTk[Result]));
        else ;
      end;
    end;
    node := AllocNode(AN_ASSIGN);
    ASTLeft[node] := Result;
    ASTRight[node] := rhsNode;
    Result := node;
  end;
  RExpectStmtEnd;
end;

function RParseBlock: Integer;
var stmt: Integer; savedArm, savedTail: Boolean;
begin
  Result := -1;
  { a braced body is ordinary code again, even when it is a match arm's -- so
    the bare-arm semicolon leniency stops at the brace, it does not leak in.
    Same for the tail-return rule: it belongs to a fn body, not to any block. }
  savedArm := RInMatchArm; RInMatchArm := False;
  savedTail := RTailOK; RTailOK := False;
  while CurTok.Kind <> tkEnd do
  begin
    if CurTok.Kind = tkEOF then Error('Rust: unterminated block (missing })');
    stmt := RParseStatement;
    Result := RSeqAppend(Result, stmt);
  end;
  RInMatchArm := savedArm;
  RTailOK := savedTail;
end;

{ A fn BODY, as distinct from an ordinary block: only here does a trailing
  expression with no `;` mean `return <it>` (Rust's implicit tail return). The
  flag is set per statement rather than by looking ahead for the last one,
  which comes to the same thing -- only the final statement of a body can be
  terminated by the closing brace instead of a semicolon. }
function RParseFnBody: Integer;
var stmt: Integer; savedTail: Boolean;
begin
  Result := -1;
  savedTail := RTailOK;
  while CurTok.Kind <> tkEnd do
  begin
    if CurTok.Kind = tkEOF then Error('Rust: unterminated function body (missing })');
    RTailOK := True;
    stmt := RParseStatement;
    Result := RSeqAppend(Result, stmt);
  end;
  RTailOK := savedTail;
end;

{ ===== Top-level: struct/fn signature prescan, then body compilation ===== }

procedure RRegisterStructShells;
var i: Integer;
begin
  for i := 0 to MainProgramTokCount - 2 do
    if (Tokens[i].Kind = tkRecord) and (Tokens[i + 1].Kind = tkIdent) and
       (FindUClass(GetTokenStr(i + 1)) < 0) then
      AddUClass(Tokens[i + 1].SOffset, Tokens[i + 1].SLen);
end;

procedure RRegisterStructFields;
var i, j, ci, curOff, sz, align, nameTokIdx, k, arrLen: Integer; tk: TTypeKind;
    mangled: AnsiString;
begin
  i := 0;
  while i < MainProgramTokCount - 2 do
  begin
    if (Tokens[i].Kind = tkRecord) and (Tokens[i + 1].Kind = tkIdent) and (Tokens[i + 2].Kind = tkLParen) then
    begin
      { tuple struct `struct Name(T, T, ...);` — fields named "0", "1", …
        (accessed as name.0), same layout math as named fields. }
      ci := FindUClass(GetTokenStr(i + 1));
      UClsIsRecord[ci] := True;
      curOff := 0; align := 1; k := 0;
      j := i + 3;
      while Tokens[j].Kind <> tkRParen do
      begin
        if Tokens[j].Kind <> tkIdent then Error('Rust: expected field type in tuple struct ' + GetTokenStr(i + 1));
        tk := RTypeKindFromName(GetTokenStr(j), True);
        Inc(j);
        sz := TypeSlotSize(tk);
        if TypeAlign(tk) > align then align := TypeAlign(tk);
        curOff := AlignTo(curOff, TypeAlign(tk));
        mangled := RIntToStr(k);
        AddUField(ci, RStoredName(mangled), Length(mangled), curOff, Ord(tk), LastTypeRecId);
        Inc(curOff, sz);
        Inc(k);
        if Tokens[j].Kind = tkComma then Inc(j);
      end;
      UClsAlign[ci] := align;
      UClsSize_[ci] := AlignTo(curOff, align);
    end
    else if (Tokens[i].Kind = tkRecord) and (Tokens[i + 1].Kind = tkIdent) and (Tokens[i + 2].Kind = tkBegin) then
    begin
      ci := FindUClass(GetTokenStr(i + 1));
      UClsIsRecord[ci] := True;
      curOff := 0; align := 1;
      j := i + 3;
      while Tokens[j].Kind <> tkEnd do
      begin
        if Tokens[j].Kind <> tkIdent then Error('Rust: expected field name in struct ' + GetTokenStr(i + 1));
        nameTokIdx := j; Inc(j);
        if Tokens[j].Kind <> tkColon then Error('Rust: expected : after field name');
        Inc(j);
        { `field: [T; N]` — a fixed array FIELD. The shared UClass machinery
          has always modelled one (UFldIsArray/UFldArrLen, what Pascal's
          `arr: array[0..N-1] of T` and C's `int a[N];` both land on); the
          Rust frontend just refused the syntax. chess.rs's Board is a
          mailbox array, so this is the rung it was blocking. }
        arrLen := 0;
        if Tokens[j].Kind = tkLBrack then
        begin
          Inc(j);
          if Tokens[j].Kind <> tkIdent then Error('Rust: expected element type in [T; N] field');
          tk := RTypeKindFromName(RTypeNameAt(j), True);
          if Tokens[j].Kind <> tkSemicolon then Error('Rust: expected ; in [T; N] field');
          Inc(j);
          if Tokens[j].Kind <> tkInteger then Error('Rust: [T; N] field length must be an integer literal');
          arrLen := Tokens[j].IVal;
          if arrLen <= 0 then Error('Rust: [T; N] field length must be positive');
          Inc(j);
          if Tokens[j].Kind <> tkRBrack then Error('Rust: expected ] in [T; N] field');
          Inc(j);
        end
        else
        begin
          if Tokens[j].Kind <> tkIdent then Error('Rust: expected field type');
          tk := RTypeKindFromName(RTypeNameAt(j), True);
        end;
        if (tk = tyRecord) and (LastTypeRecId >= REC_UCLASS_BASE) then
          sz := RecSize(LastTypeRecId)
        else
          sz := TypeSlotSize(tk);
        if TypeAlign(tk) > align then align := TypeAlign(tk);
        curOff := AlignTo(curOff, TypeAlign(tk));
        AddUField(ci, Tokens[nameTokIdx].SOffset, Tokens[nameTokIdx].SLen, curOff, Ord(tk), LastTypeRecId);
        if arrLen > 0 then
        begin
          UFldIsArray[UFldCount - 1] := True;
          UFldArrLen[UFldCount - 1] := arrLen;
          UFldDynDepth[UFldCount - 1] := 0;
          UFldArrDimLo[(UFldCount - 1) * MAX_ARR_DIMS] := 0;
          sz := sz * arrLen;
        end;
        Inc(curOff, sz);
        if Tokens[j].Kind = tkComma then Inc(j);
      end;
      UClsAlign[ci] := align;
      UClsSize_[ci] := AlignTo(curOff, align);
    end;
    Inc(i);
  end;
end;

{ `enum Name { Unit, Tuple(T1, T2), Struct { f: T, ... } }`. One UClass per
  enum: __tag discriminant at offset 0 (8 bytes), every variant's payload
  fields registered at offset 8 with mangled names ("Variant.0",
  "Variant.field") — a real union, all variants overlap the same bytes. }
procedure RRegisterEnums;
var i, j, k, ci, tag, curOff, maxEnd, align, sz, vi: Integer;
    variantName, fieldName, mangled: AnsiString; tk: TTypeKind;
begin
  i := 0;
  while i < MainProgramTokCount - 2 do
  begin
    if (Tokens[i].Kind = tkIdent) and (GetTokenStr(i) = 'enum') and
       (Tokens[i + 1].Kind = tkIdent) and (Tokens[i + 2].Kind = tkBegin) then
    begin
      ci := FindUClass(GetTokenStr(i + 1));
      if ci < 0 then ci := AddUClass(Tokens[i + 1].SOffset, Tokens[i + 1].SLen);
      UClsIsRecord[ci] := True;
      REnumCi[ci] := True;
      AddUField(ci, RStoredName('__tag'), 5, 0, Ord(tyInt64), REC_NONE);
      align := 8; maxEnd := 8; tag := 0;
      j := i + 3;
      while Tokens[j].Kind <> tkEnd do
      begin
        if Tokens[j].Kind <> tkIdent then Error('Rust: expected variant name in enum ' + GetTokenStr(i + 1));
        variantName := GetTokenStr(j); Inc(j);
        if REnumVariantCount >= R_MAX_VARIANTS then Error('Rust: too many enum variants');
        vi := REnumVariantCount; Inc(REnumVariantCount);
        REnumVariants[vi].EnumCi := ci;
        REnumVariants[vi].Name := variantName;
        REnumVariants[vi].Tag := tag;
        curOff := 8;
        if Tokens[j].Kind = tkLParen then
        begin
          REnumVariants[vi].Kind := RVAR_TUPLE;
          Inc(j); k := 0;
          while Tokens[j].Kind <> tkRParen do
          begin
            if Tokens[j].Kind <> tkIdent then Error('Rust: expected type in tuple variant ' + variantName);
            tk := RTypeKindFromName(GetTokenStr(j), True);
            Inc(j);
            sz := TypeSlotSize(tk);
            if TypeAlign(tk) > align then align := TypeAlign(tk);
            curOff := AlignTo(curOff, TypeAlign(tk));
            mangled := variantName + '.' + RIntToStr(k);
            AddUField(ci, RStoredName(mangled), Length(mangled), curOff, Ord(tk), LastTypeRecId);
            Inc(curOff, sz);
            if curOff > maxEnd then maxEnd := curOff;
            Inc(k);
            if Tokens[j].Kind = tkComma then Inc(j);
          end;
          Inc(j); { ) }
        end
        else if Tokens[j].Kind = tkBegin then
        begin
          REnumVariants[vi].Kind := RVAR_STRUCT;
          Inc(j);
          while Tokens[j].Kind <> tkEnd do
          begin
            if Tokens[j].Kind <> tkIdent then Error('Rust: expected field name in variant ' + variantName);
            fieldName := GetTokenStr(j); Inc(j);
            if Tokens[j].Kind <> tkColon then Error('Rust: expected : after field name');
            Inc(j);
            if Tokens[j].Kind <> tkIdent then Error('Rust: expected field type');
            tk := RTypeKindFromName(GetTokenStr(j), True);
            Inc(j);
            sz := TypeSlotSize(tk);
            if TypeAlign(tk) > align then align := TypeAlign(tk);
            curOff := AlignTo(curOff, TypeAlign(tk));
            mangled := variantName + '.' + fieldName;
            AddUField(ci, RStoredName(mangled), Length(mangled), curOff, Ord(tk), LastTypeRecId);
            Inc(curOff, sz);
            if curOff > maxEnd then maxEnd := curOff;
            if Tokens[j].Kind = tkComma then Inc(j);
          end;
          Inc(j); { consume the variant's closing brace }
        end
        else
          REnumVariants[vi].Kind := RVAR_UNIT;
        Inc(tag);
        if Tokens[j].Kind = tkComma then Inc(j);
      end;
      UClsAlign[ci] := align;
      UClsSize_[ci] := AlignTo(maxEnd, align);
    end;
    Inc(i);
  end;
end;

{ Registers the fn signature starting at Tokens[i] (must be tkFn); returns
  the index just past it (the body's opening brace). Tolerates an optional
  <...> clause right after the name (present, and already
  concrete-substituted, on a specialized generic-fn copy — see
  RSpecializeGenericFn; never present on an ordinary top-level fn, so this
  is a no-op there). Shared by the main prescan below and by generic
  specialization, so there is one signature-parsing implementation, not two. }
function RRegisterFnSignatureAt(i: Integer): Integer;
var j, depth, nparams, procIdx, k, retRecId, retArrLen: Integer; name: AnsiString;
    pnames: array[0..7] of AnsiString; ptypes: array[0..7] of TTypeKind;
    pbyref, parr: array[0..7] of Boolean; prec: array[0..7] of Integer;
    retType, sElemTk: TTypeKind;
begin
  name := GetTokenStr(i + 1);
  j := i + 2;
  if Tokens[j].Kind = tkLt then
  begin
    depth := 1; Inc(j);
    while depth > 0 do
    begin
      if Tokens[j].Kind = tkLt then Inc(depth)
      else if Tokens[j].Kind = tkGt then Dec(depth);
      Inc(j);
    end;
  end;
  if Tokens[j].Kind <> tkLParen then Error('Rust: expected ( after function name ' + name);
  Inc(j); nparams := 0;
  while Tokens[j].Kind <> tkRParen do
  begin
    if Tokens[j].Kind = tkMut then Inc(j);
    if nparams >= 6 then Error('Rust: too many parameters (register-convention limit is 6)');
    if Tokens[j].Kind <> tkIdent then Error('Rust: expected parameter name in ' + name);
    pnames[nparams] := GetTokenStr(j); Inc(j);
    if Tokens[j].Kind <> tkColon then Error('Rust: expected : in parameter list');
    Inc(j);
    { `&` / `&mut` on a param is RECORDED, not dropped. It is the one bit
      that decides ALIASING: ir.inc gives a record param that is by-ref only
      for ABI efficiency a private temp copy (ProcParamExplicitByRef False),
      which is right for a by-value `p: Board` and wrong for a reference.
      `&[T]` / `&mut [T]` is the borrowed-slice view type (the auto-registered
      __ptr+__len UClass) and keeps its existing handling -- a copy of a slice
      HEADER still points at the same elements, so it never depended on this. }
    pbyref[nparams] := False;
    parr[nparams] := False;
    if Tokens[j].Kind = tkAmp then
    begin
      pbyref[nparams] := True;
      Inc(j);
      if Tokens[j].Kind = tkMut then Inc(j);
    end;
    if Tokens[j].Kind = tkLBrack then
    begin
      Inc(j);
      if Tokens[j].Kind <> tkIdent then Error('Rust: expected element type in &[T] parameter');
      { sequence the side-effecting RTypeKindFromName (sets LastTypeRecId)
        before reading LastTypeRecId — do NOT rely on arg eval order. }
      sElemTk := RTypeKindFromName(RTypeNameAt(j), True);
      if Tokens[j].Kind = tkSemicolon then
      begin
        { `&[T; N]` — a REFERENCE TO AN ARRAY, which Rust distinguishes from
          the `&[T]` SLICE right below it and the engine's table code relies on
          the difference: a slice is a two-word view and an array reference is
          just the address, so `t[i]` on the two lowers differently. Registered
          as an ordinary by-address array param, which is what pxx's own array
          params already are (ABIParamSlotIsPointer answers True on isArray),
          so the length is not needed here -- AllocParam stamps the open-array
          ArrLen and nothing bounds-checks it. }
        Inc(j);
        if Tokens[j].Kind <> tkInteger then Error('Rust: array parameter length must be an integer literal');
        Inc(j);
        parr[nparams] := True;
        ptypes[nparams] := sElemTk;
        prec[nparams] := LastTypeRecId;
      end
      else
      begin
        prec[nparams] := REC_UCLASS_BASE + RSliceClassForRec(sElemTk, LastTypeRecId);
        ptypes[nparams] := tyRecord;
      end;
      if Tokens[j].Kind <> tkRBrack then Error('Rust: expected ] in &[T] parameter');
      Inc(j);
    end
    else
    begin
      if Tokens[j].Kind <> tkIdent then Error('Rust: expected parameter type');
      { struct/enum params allowed (always passed by address, same as self —
        see RParseTopLevelFn/RRegisterImpls). RETURN values too, as of the
        Option<T> rung: the shared machinery has always compiled a
        record-returning function (Pascal `function F: TRec` does), the Rust
        frontend simply never registered ProcRetRecId for one. }
      ptypes[nparams] := RTypeKindFromName(RTypeNameAt(j), True);
      prec[nparams] := LastTypeRecId;
    end;
    Inc(nparams);
    if Tokens[j].Kind = tkComma then Inc(j);
  end;
  Inc(j); { consume ) }
  retType := tyInteger; { Rust's () return; unused Result slot, same trick C's void uses }
  retRecId := REC_NONE;
  retArrLen := 0;
  if (Tokens[j].Kind = tkMinus) and (Tokens[j + 1].Kind = tkGt) then
  begin
    j := j + 2;
    retType := RRetTypeAt(j);
    retRecId := LastTypeRecId;
    retArrLen := RRetArrLen;
  end;
  procIdx := RegisterProc(name, True, retType, nparams, pnames, ptypes);
  if retType = tyRecord then ProcRetRecId[procIdx] := retRecId;
  RNoteRetArray(procIdx, retArrLen, retType, retRecId);
  for k := 0 to nparams - 1 do
    Procs[procIdx].Params[k].IsArray := parr[k];
  for k := 0 to nparams - 1 do
    if ptypes[k] = tyRecord then
    begin
      Procs[procIdx].Params[k].IsRef := True;
      { `p: &T` / `p: &mut T` genuinely aliases; a plain `p: T` is a move and
        the callee's private copy is observationally correct. A slice view is
        left alone (see the note at the parse site). }
      if pbyref[k] and not RIsSliceRec(prec[k]) then
        ProcParamExplicitByRef[procIdx * MAX_PROC_PARAMS + k] := True;
    end;
  Result := j;
end;

procedure RRegisterFnSignatures;
var i, depth: Integer;
begin
  depth := 0; i := 0;
  while i < MainProgramTokCount do
  begin
    if Tokens[i].Kind = tkBegin then Inc(depth)
    else if Tokens[i].Kind = tkEnd then Dec(depth)
    else if (depth = 0) and (Tokens[i].Kind = tkFn) and
            (Tokens[i + 1].Kind = tkIdent) and (Tokens[i + 2].Kind = tkLParen) then
      RRegisterFnSignatureAt(i);
    Inc(i);
  end;
end;

{ `trait Name { fn sig(&self, ...) -> RetType; ... }` — signature-only
  methods (no bodies, no nested braces), so a flat scan to the matching
  closing brace is enough. Only the trait's NAME is recorded (RTraits): bound-checking is
  pure (TypeCi, TraitName) membership in RImpls, not method-signature
  verification (see the file-header note — not a coherence solver). }
procedure RRegisterTraits;
var i, j: Integer;
begin
  i := 0;
  while i < MainProgramTokCount - 2 do
  begin
    if (Tokens[i].Kind = tkIdent) and (GetTokenStr(i) = 'trait') and
       (Tokens[i + 1].Kind = tkIdent) and (Tokens[i + 2].Kind = tkBegin) then
    begin
      if RTraitCount >= R_MAX_TRAITS then Error('Rust: too many traits');
      RTraits[RTraitCount] := GetTokenStr(i + 1);
      Inc(RTraitCount);
      j := i + 3;
      while Tokens[j].Kind <> tkEnd do Inc(j);
    end;
    Inc(i);
  end;
end;

{ `impl [Trait for] Type { fn method(&self, ...) -> RetType { .. } ... }`.
  Each method becomes an ordinary RegisterProc'd function named
  "Type::method" with `self` prepended as param 0 (type tyRecord — always
  pointer-passed under this ABI regardless of the record's own size, see
  ParamSize; no new codegen needed for field access through it). An
  `impl Trait for Type` additionally records (TypeCi, TraitName) in RImpls. }
procedure RRegisterImpls;
var i, j, k, ci, nparams, procIdx, selfBase, retRecId, retArrLen: Integer;
    typeName, traitName, methodName, fullName: AnsiString;
    pnamesFull: array[0..7] of AnsiString; ptypesFull: array[0..7] of TTypeKind;
    pbyrefFull: array[0..7] of Boolean;
    retType: TTypeKind; hasTrait, selfByRef: Boolean;
begin
  i := 0;
  while i < MainProgramTokCount - 2 do
  begin
    if (Tokens[i].Kind = tkIdent) and (GetTokenStr(i) = 'impl') then
    begin
      hasTrait := False; traitName := '';
      j := i + 1;
      { `impl fmt::Display for X` -- a trait name may be path-qualified, and
        the qualifier is not a module this frontend knows, so it is simply the
        last segment that names the trait.

        NOTE THE `tkFor`. Both arms tested `GetTokenStr(..) = 'for'` against a
        token that the lexer classifies as tkFor, whose SOffset/SLen are zero
        -- so the comparison was against the empty string and could never
        succeed. `impl Trait for Type` had therefore NEVER been recognised;
        every one of them was read as `impl <Trait>` and died with "impl for
        unknown type Area". Dead code that looked live, found by trying to
        extend it. }
      if (Tokens[j].Kind = tkIdent) and (Tokens[j + 1].Kind = tkPathSep) and
         (Tokens[j + 2].Kind = tkIdent) and (Tokens[j + 3].Kind = tkFor) then
      begin
        traitName := GetTokenStr(j + 2);
        hasTrait := True;
        j := j + 4;
      end
      else if (Tokens[j].Kind = tkIdent) and (Tokens[j + 1].Kind = tkFor) then
      begin
        traitName := GetTokenStr(j);
        hasTrait := True;
        j := j + 2;
      end;
      if hasTrait and (RFindTrait(traitName) < 0) and (not RIsBuiltinTrait(traitName)) then
        Error('Rust: unknown trait ' + traitName);
      if Tokens[j].Kind <> tkIdent then Error('Rust: expected type name after impl');
      typeName := GetTokenStr(j);
      ci := FindUClass(typeName);
      if ci < 0 then Error('Rust: impl for unknown type ' + typeName);
      RCurImplType := typeName; { `Self` in signatures resolves to this }
      Inc(j);
      if Tokens[j].Kind <> tkBegin then Error('Rust: expected { after impl ' + typeName);
      if hasTrait then
      begin
        if RImplCount >= R_MAX_IMPLS then Error('Rust: too many impls');
        RImpls[RImplCount].TypeCi := ci;
        RImpls[RImplCount].TraitName := traitName;
        Inc(RImplCount);
      end;
      Inc(j);
      while Tokens[j].Kind <> tkEnd do
      begin
        if Tokens[j].Kind <> tkFn then Error('Rust: expected fn in impl block for ' + typeName);
        Inc(j);
        if Tokens[j].Kind <> tkIdent then Error('Rust: expected method name in impl ' + typeName);
        methodName := GetTokenStr(j); Inc(j);
        if Tokens[j].Kind <> tkLParen then Error('Rust: expected ( after method name ' + methodName);
        Inc(j);
        { methods take self (by address); ASSOCIATED fns (no self) register
          too — called as Type::name(args), plain procs with mangled names }
        selfBase := 0; selfByRef := False;
        if (Tokens[j].Kind = tkAmp) or (Tokens[j].Kind = tkMut) or
           ((Tokens[j].Kind = tkIdent) and (GetTokenStr(j) = 'self')) then
        begin
          if Tokens[j].Kind = tkAmp then
          begin
            selfByRef := True;
            Inc(j);
            if Tokens[j].Kind = tkMut then Inc(j);   { `&mut self` }
          end
          else if Tokens[j].Kind = tkMut then Inc(j); { by-value `mut self` }
          if (Tokens[j].Kind <> tkIdent) or (GetTokenStr(j) <> 'self') then
            Error('Rust: expected self after & in ' + methodName);
          Inc(j);
          if Tokens[j].Kind = tkComma then Inc(j);
          pnamesFull[0] := 'self'; ptypesFull[0] := tyRecord;
          selfBase := 1;
        end;
        nparams := 0;
        { `fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result` is rerouted to
          `fn fmt(&self) -> String`. The Formatter and the fmt::Result are the
          trait's plumbing for a writer this frontend does not have; what a
          Display impl actually says is "here is my text", and a String says
          that with no trait dispatch, no writer object and no new machinery --
          which is exactly the shortcut the corpus ticket predicted would be
          cheaper than real trait dispatch. The param and the return
          annotation are skipped WHOLE so `fmt::Formatter` and `fmt::Result`
          never have to resolve as types. }
        if hasTrait and (traitName = 'Display') and (methodName = 'fmt') then
        begin
          while (Tokens[j].Kind <> tkRParen) and (Tokens[j].Kind <> tkEOF) do Inc(j);
          Inc(j); { ) }
          if (Tokens[j].Kind = tkMinus) and (Tokens[j + 1].Kind = tkGt) then
          begin
            j := j + 2;
            Inc(j);                                  { fmt }
            if Tokens[j].Kind = tkPathSep then j := j + 2;   { ::Result }
          end;
          fullName := typeName + '::fmt';
          procIdx := RegisterProc(fullName, True, tyAnsiString, selfBase, pnamesFull, ptypesFull);
          ProcRetRecId[procIdx] := REC_NONE;
          Procs[procIdx].Params[0].IsRef := True;
          ProcParamExplicitByRef[procIdx * MAX_PROC_PARAMS] := True;
          { skip the body }
          k := 0;
          while Tokens[j].Kind <> tkBegin do Inc(j);
          repeat
            if Tokens[j].Kind = tkBegin then Inc(k)
            else if Tokens[j].Kind = tkEnd then Dec(k);
            Inc(j);
          until (k = 0) or (Tokens[j].Kind = tkEOF);
          Continue;
        end;
        while Tokens[j].Kind <> tkRParen do
        begin
          if Tokens[j].Kind = tkMut then Inc(j);
          if nparams + selfBase >= 6 then Error('Rust: too many parameters in ' + methodName + ' (limit is 6 incl. self)');
          if Tokens[j].Kind <> tkIdent then Error('Rust: expected parameter name in ' + methodName);
          pnamesFull[nparams + selfBase] := GetTokenStr(j); Inc(j);
          if Tokens[j].Kind <> tkColon then Error('Rust: expected : in parameter list');
          Inc(j);
          { `&`/`&mut` on a method param, recorded for the same aliasing reason
            as on a free fn's -- the impl prescan did not accept it at all. }
          pbyrefFull[nparams + selfBase] := False;
          if Tokens[j].Kind = tkAmp then
          begin
            pbyrefFull[nparams + selfBase] := True;
            Inc(j);
            if Tokens[j].Kind = tkMut then Inc(j);
          end;
          if Tokens[j].Kind <> tkIdent then Error('Rust: expected parameter type');
          ptypesFull[nparams + selfBase] := RTypeKindFromName(RTypeNameAt(j), True);
          Inc(nparams);
          if Tokens[j].Kind = tkComma then Inc(j);
        end;
        Inc(j); { consume ) }
        retType := tyInteger;
        retRecId := REC_NONE;
        retArrLen := 0;
        if (Tokens[j].Kind = tkMinus) and (Tokens[j + 1].Kind = tkGt) then
        begin
          j := j + 2;
          retType := RRetTypeAt(j);
          retRecId := LastTypeRecId;
          retArrLen := RRetArrLen;
        end;
        fullName := typeName + '::' + methodName;
        procIdx := RegisterProc(fullName, True, retType, nparams + selfBase, pnamesFull, ptypesFull);
        if retType = tyRecord then ProcRetRecId[procIdx] := retRecId;
        RNoteRetArray(procIdx, retArrLen, retType, retRecId);
        { a record/enum param travels by address, exactly like self — without
          this the caller passes the value while AllocParam(isRef=True)
          dereferences it (the same mismatch the self note below records). }
        for k := 0 to nparams + selfBase - 1 do
          if ptypesFull[k] = tyRecord then Procs[procIdx].Params[k].IsRef := True;
        { RegisterProc always defaults Params[].IsRef to False — self is
          always passed by address (see the file-header note), so this must
          be set explicitly or the caller passes self by raw value while the
          callee's AllocParam(isRef=True) dereferences it as a pointer,
          reading garbage / segfaulting (found via testing, not by inspection). }
        if selfBase = 1 then
        begin
          Procs[procIdx].Params[0].IsRef := True;
          { `&self` / `&mut self` are REFERENCES and must alias the caller's
            record. Without ProcParamExplicitByRef, ir.inc reads the by-ref
            flag as the silent >8-byte ABI promotion and hands the method a
            private copy -- so `self.field = v` wrote into a temp and the
            caller saw nothing (measured as an IR_COPY_REC at the call site).
            A by-value `self` keeps the copy, which is what a move means. }
          if selfByRef then
            ProcParamExplicitByRef[procIdx * MAX_PROC_PARAMS] := True;
        end;
        for k := 0 to nparams + selfBase - 1 do
          if (k >= selfBase) and (ptypesFull[k] = tyRecord) and pbyrefFull[k] then
            ProcParamExplicitByRef[procIdx * MAX_PROC_PARAMS + k] := True;
        if Tokens[j].Kind <> tkBegin then Error('Rust: expected { for method body of ' + fullName);
        Inc(j);
        nparams := 1; { reuse as brace depth counter from here }
        while nparams > 0 do
        begin
          if Tokens[j].Kind = tkBegin then Inc(nparams)
          else if Tokens[j].Kind = tkEnd then Dec(nparams);
          if nparams > 0 then Inc(j);
        end;
        Inc(j); { consume the method's closing brace }
      end;
      RCurImplType := '';
    end;
    Inc(i);
  end;
end;

{ `fn name<T[: Bound(+Bound)*]>(params-using-T) -> RetOrT { body }`. Never
  compiled directly — buffers the whole declaration's token span
  (RGenericFuncs) for RSpecializeGenericFn to copy-and-substitute per call
  site. One type parameter, inferred from the first argument at the call
  site (see RParsePrimary) — not parsed from an explicit `f::<T>(...)` the
  way it would need to be if a bound also constrained the return type alone. }
procedure RRegisterGenericFuncs;
var i, j, depth, gfi: Integer; boundName: AnsiString; more: Boolean;
begin
  i := 0;
  while i < MainProgramTokCount - 3 do
  begin
    if (Tokens[i].Kind = tkFn) and (Tokens[i + 1].Kind = tkIdent) and (Tokens[i + 2].Kind = tkLt) then
    begin
      if RGenericFuncCount >= R_MAX_GENERIC_FUNCS then Error('Rust: too many generic functions');
      gfi := RGenericFuncCount; Inc(RGenericFuncCount);
      RGenericFuncs[gfi].Name := GetTokenStr(i + 1);
      j := i + 3;
      if Tokens[j].Kind <> tkIdent then Error('Rust: expected type parameter name in ' + RGenericFuncs[gfi].Name);
      RGenericFuncs[gfi].ParamName := GetTokenStr(j); Inc(j);
      RGenericFuncs[gfi].BoundCount := 0;
      if Tokens[j].Kind = tkColon then
      begin
        Inc(j);
        more := True;
        while more do
        begin
          if Tokens[j].Kind <> tkIdent then Error('Rust: expected trait bound name in ' + RGenericFuncs[gfi].Name);
          boundName := GetTokenStr(j);
          if RFindTrait(boundName) < 0 then Error('Rust: unknown trait ' + boundName + ' used as a bound');
          if RGenericFuncs[gfi].BoundCount >= R_MAX_BOUNDS then Error('Rust: too many trait bounds');
          RGenericFuncs[gfi].Bounds[RGenericFuncs[gfi].BoundCount] := boundName;
          Inc(RGenericFuncs[gfi].BoundCount);
          Inc(j);
          if Tokens[j].Kind = tkPlus then begin Inc(j); more := True; end
          else more := False;
        end;
      end;
      if Tokens[j].Kind <> tkGt then Error('Rust: expected > closing the type parameter list of ' + RGenericFuncs[gfi].Name);
      Inc(j);
      RGenericFuncs[gfi].TokStart := i;
      if Tokens[j].Kind <> tkLParen then Error('Rust: expected ( after the type parameter list');
      depth := 1; Inc(j);
      while depth > 0 do
      begin
        if Tokens[j].Kind = tkLParen then Inc(depth)
        else if Tokens[j].Kind = tkRParen then Dec(depth);
        Inc(j);
      end;
      if (Tokens[j].Kind = tkMinus) and (Tokens[j + 1].Kind = tkGt) then j := j + 3;
      if Tokens[j].Kind <> tkBegin then Error('Rust: expected { for the body of ' + RGenericFuncs[gfi].Name);
      depth := 1; Inc(j);
      while depth > 0 do
      begin
        if Tokens[j].Kind = tkBegin then Inc(depth)
        else if Tokens[j].Kind = tkEnd then Dec(depth);
        Inc(j);
      end;
      RGenericFuncs[gfi].TokCount := j - i;
      i := j - 1; { outer Inc(i) below lands exactly at j }
    end;
    Inc(i);
  end;
end;

procedure RParseTopLevelStruct;
begin
  Next; { struct }
  if CurTok.Kind <> tkIdent then Error('Rust: expected struct name');
  Next;
  if CurTok.Kind = tkLParen then
  begin
    { tuple struct `struct Name(T, ...);` — fields registered in the
      prescan; consume through the trailing semicolon. }
    while (CurTok.Kind <> tkRParen) and (CurTok.Kind <> tkEOF) do Next;
    Expect(tkRParen, ')');
    Expect(tkSemicolon, ';');
    Exit;
  end;
  Expect(tkBegin, '{');
  { fields were already registered by RRegisterStructFields; nothing left to
    compile for a plain value-type struct declaration. }
  while CurTok.Kind <> tkEnd do Next;
  Expect(tkEnd, '}');
end;

procedure RParseTopLevelEnum;
var depth: Integer;
begin
  Next; { 'enum' identifier }
  if CurTok.Kind <> tkIdent then Error('Rust: expected enum name');
  Next;
  Expect(tkBegin, '{');
  { variants were already registered by RRegisterEnums; nothing left to
    compile for the declaration itself. Depth-tracked: a struct-like variant
    (`Square { side: i32 }`) has its own nested brace pair. }
  depth := 1;
  while depth > 0 do
  begin
    if CurTok.Kind = tkBegin then Inc(depth)
    else if CurTok.Kind = tkEnd then Dec(depth);
    if depth > 0 then Next;
  end;
  Expect(tkEnd, '}');
end;

procedure RParseTopLevelTrait;
begin
  Next; { 'trait' identifier }
  if CurTok.Kind <> tkIdent then Error('Rust: expected trait name');
  Next;
  Expect(tkBegin, '{');
  { signature-only, no nested braces, already recorded by RRegisterTraits }
  while CurTok.Kind <> tkEnd do Next;
  Expect(tkEnd, '}');
end;

{ Skips a generic fn declaration entirely in the real (compiling) pass — it
  is never compiled directly, only via RSpecializeGenericFn's per-call-site
  copies. Pure token-skip (no parsing) since RRegisterGenericFuncs already
  buffered everything needed. }
procedure RSkipGenericFnDecl;
var depth: Integer;
begin
  Next; { fn }
  Next; { name }
  if CurTok.Kind = tkLt then RSkipAngleClause;
  Expect(tkLParen, '(');
  depth := 1;
  while depth > 0 do
  begin
    if CurTok.Kind = tkLParen then Inc(depth)
    else if CurTok.Kind = tkRParen then Dec(depth);
    if depth > 0 then Next;
  end;
  Next; { consume final ) }
  if CurTok.Kind = tkMinus then
  begin
    Next;
    if CurTok.Kind <> tkGt then Error('Rust: expected -> return type');
    Next; Next; { >, return-type ident }
  end;
  Expect(tkBegin, '{');
  depth := 1;
  while depth > 0 do
  begin
    if CurTok.Kind = tkBegin then Inc(depth)
    else if CurTok.Kind = tkEnd then Dec(depth);
    if depth > 0 then Next;
  end;
  Expect(tkEnd, '}');
end;

{ Spill the incoming integer param registers (rdi,rsi,rdx,rcx,r8,r9) into each
  param's frame slot, `count` params in index order. The internal call
  convention passes up to 6 integer/pointer args in registers; params 5 and 6
  (index 4,5) live in r8/r9 and need REX.R, so the REX prefix is computed per
  register rather than the old rdi..rcx-only `case`. sz<8 stores the low dword
  (matching the historic rdi..rcx behaviour); >6 params are rejected at parse
  time so no stack-arg read is needed here. }
{ REmitParamRegSpill lived here — raw x86-64 SysV register spill, borrowed by
  the Zig frontend too, and one of the three instances that named the missing
  frontend/backend layer. Replaced by EmitParamSpillsForTarget (ir_codegen.inc),
  which has arms for every target instead of one, handles 1- and 2-byte params
  and the tySingle narrow, and takes the all-stack path when a proc has more
  than six parameters. refactor-a-the-missing-layer-between-frontends-and-backends }

{ Allocate the routine's `Result` slot, plus the frame slot its prologue
  stashes the incoming hidden-destination pointer in when the return travels
  that way. Both body parsers -- free fn and impl method -- had a copy of this
  from the record-return rung, and an array return would have made it three
  copies of a thing whose failure mode is silent.

  Three shapes reach it. A SCALAR is a plain local. A RECORD needs its record
  id on the slot, or the hidden buffer is sized as a scalar and every field
  store lands wrong. A FIXED ARRAY must be allocated AS an array: AllocVar
  reserves ONE ELEMENT, because Procs[].RetType holds the ELEMENT kind for an
  array-returning routine, so `Result[i] := v` would index off a single slot
  and write over the rest of the frame -- which is Pascal's
  bug-a-nd-array-function-result-indexes-the-wrong-slot, reachable here for
  exactly the same reason and not by coincidence: the kind alone cannot show
  the aggregate.

  ABIRetViaHiddenDestProc, not RetViaHiddenDest, decides the hidden slot -- it
  is the query that reads ProcRetFixedArrBytes as well as the kind, and the
  kind-only one answers False for every array return. }
procedure RAllocResultSlot(procIdx: Integer);
var idx: Integer;
begin
  LastTypeRecId := ProcRetRecId[procIdx];
  if RProcRetArrLen[procIdx] > 0 then
  begin
    idx := AllocArray('Result', Procs[procIdx].RetType, 0, RProcRetArrLen[procIdx] - 1);
    Syms[idx].Kind := skLocal;
  end
  else
    idx := AllocVar('Result', Procs[procIdx].RetType);
  Procs[procIdx].RetSymIdx := idx;
  if ABIRetViaHiddenDestProc(procIdx) then
    ProcAggregateDestSym[procIdx] := AllocVar('', tyPointer);
end;

{ `impl [Trait for] Type { fn method(&self, ...) -> RetType { .. } ... }` —
  methods were already RegisterProc'd (mangled "Type::method") by
  RRegisterImpls; this compiles each body, same shape as RParseTopLevelFn
  but with `self` prepended as an implicit, always-by-reference param 0. }
procedure RParseTopLevelImpl;
var typeName, traitName, fname, pname, fullName: AnsiString;
    ci, procIdx, nparams, i, idx, savedSC, savedFS, patchPos, bodyNode, selfBase: Integer;
    pnames: array[0..7] of AnsiString; ptypes: array[0..7] of TTypeKind;
    precids: array[0..7] of Integer;
    isDisplayFmt: Boolean;
begin
  Next; { impl }
  traitName := '';
  { path-qualified trait name (`fmt::Display for X`) -- the twin of the
    prepass's; both must agree or the body parser will not know it is looking
    at a Display impl. }
  if (CurTok.Kind = tkIdent) and (Tokens[TokPos].Kind = tkPathSep) and
     (Tokens[TokPos + 1].Kind = tkIdent) and (Tokens[TokPos + 2].Kind = tkFor) then
  begin
    Next; Next;                 { qualifier, :: }
    traitName := CurTok.SVal;
    Next; Next;                 { trait name, 'for' }
  end
  else if (CurTok.Kind = tkIdent) and (Tokens[TokPos].Kind = tkFor) then
  begin
    traitName := CurTok.SVal;
    Next; Next; { trait name, 'for' }
  end;
  if CurTok.Kind <> tkIdent then Error('Rust: expected type name after impl');
  typeName := CurTok.SVal;
  ci := FindUClass(typeName);
  RCurImplType := typeName; { `Self` resolves to this until the block ends }
  Next;
  Expect(tkBegin, '{');
  while CurTok.Kind <> tkEnd do
  begin
    if CurTok.Kind <> tkFn then Error('Rust: expected fn in impl block for ' + typeName);
    Next;
    if CurTok.Kind <> tkIdent then Error('Rust: expected method name');
    fname := CurTok.SVal; Next;
    fullName := typeName + '::' + fname;
    procIdx := FindProc(fullName);
    if procIdx < 0 then Error('Rust: internal error — signature prescan missed ' + fullName);
    Expect(tkLParen, '(');
    selfBase := 0;
    if (CurTok.Kind = tkAmp) or (CurTok.Kind = tkMut) or
       ((CurTok.Kind = tkIdent) and (CurTok.SVal = 'self')) then
    begin
      if CurTok.Kind = tkAmp then
      begin
        Next;
        if CurTok.Kind = tkMut then Next;   { `&mut self` }
      end
      else if CurTok.Kind = tkMut then Next; { by-value `mut self` }
      if (CurTok.Kind <> tkIdent) or (CurTok.SVal <> 'self') then
        Error('Rust: expected self after & in ' + fullName);
      Next;
      Eat(tkComma);
      selfBase := 1;
    end;
    nparams := 0;
    { the Display reroute's body-side twin: the Formatter param and the
      `-> fmt::Result` are skipped whole, exactly as the prepass skipped them,
      and the body is parsed with RInDisplayFmt on. }
    isDisplayFmt := (traitName = 'Display') and (fname = 'fmt');
    if isDisplayFmt then
    begin
      while (CurTok.Kind <> tkRParen) and (CurTok.Kind <> tkEOF) do Next;
      Next;                                       { ) }
      if CurTok.Kind = tkMinus then
      begin
        Next; Expect(tkGt, '>');
        Next;                                     { fmt }
        if CurTok.Kind = tkPathSep then begin Next; Next; end;   { ::Result }
      end;
    end;
    while (not isDisplayFmt) and (CurTok.Kind <> tkRParen) do
    begin
      if CurTok.Kind = tkMut then Next;
      if nparams + selfBase >= 6 then Error('Rust: too many parameters (limit is 6 incl. self)');
      if CurTok.Kind <> tkIdent then Error('Rust: expected parameter name');
      pname := CurTok.SVal; Next;
      Expect(tkColon, ':');
      if CurTok.Kind = tkAmp then
      begin
        Next;
        if CurTok.Kind = tkMut then Next;
      end;
      if CurTok.Kind <> tkIdent then Error('Rust: expected parameter type');
      ptypes[nparams] := RTypeKindFromName(RTypeNameCur, True);
      precids[nparams] := LastTypeRecId;
      pnames[nparams] := pname;
      Inc(nparams);
      if not Eat(tkComma) then Break;
    end;
    if not isDisplayFmt then
    begin
      Expect(tkRParen, ')');
      if CurTok.Kind = tkMinus then
      begin
        Next; Expect(tkGt, '>');
        { consumed through RRetTypeCur so a multi-token `Option<T>` or `[T; N]`
          is skipped WHOLE; the registered signature is what actually types the
          method, so the value is discarded here on purpose. }
        RRetTypeCur;
      end;
    end;

    savedSC := SymCount; savedFS := FrameSize;
    FrameSize := 0; CurProc := procIdx;
    Procs[procIdx].BodyAddr := CodeLen;
    Procs[procIdx].ScopeBase := SymCount;
    if selfBase = 1 then
    begin
      LastTypeRecId := REC_UCLASS_BASE + ci;
      idx := AllocParam('self', tyRecord, True, False);
      Procs[procIdx].Params[0].SymIdx := idx;
    end;
    for i := 0 to nparams - 1 do
    begin
      LastTypeRecId := precids[i];
      if ptypes[i] = tyRecord then
        idx := AllocParam(pnames[i], ptypes[i], True, False)
      else
        idx := AllocParam(pnames[i], ptypes[i], False, False);
      Procs[procIdx].Params[i + selfBase].SymIdx := idx;
    end;

    RAllocResultSlot(procIdx);

    patchPos := EmitProcPrologue;
    Procs[procIdx].FramePatch := patchPos;
    EmitAggregateDestStash(procIdx);
    EmitParamSpillsForTarget(procIdx, nparams + selfBase);

    Expect(tkBegin, '{');
    RInDisplayFmt := isDisplayFmt;
    bodyNode := RParseFnBody;
    RInDisplayFmt := False;
    Expect(tkEnd, '}');

    { Zero every managed local before the body -- see the twin in
      RParseTopLevelFn for why this sits after the parse rather than after the
      prologue. }
    EmitManagedLocalsZeroInit(savedSC);

    CompileAST(bodyNode);
    EmitProcEpilog(Procs[procIdx].RetSymIdx);
    PatchProcPrologue(patchPos, FrameSize);
        { DWARF -g: the routine-body tail every Pascal proc ends with (pasparser_*.inc).
      Without it this frontend's functions had NO DW_TAG_subprogram, so
      `break <fn>` in gdb answered "Function not defined" — the same total
      absence NilPy had before 58937b717. ProcBodyEnd must be taken after the
      epilogue; the locals snapshot before the scope is rolled back. }
    ProcBodyEnd[procIdx] := CodeLen;
    ProcDbgMain[procIdx] := DbgTokIsDebuggable(TokPos);
    if DebugInfo and ProcDbgMain[procIdx] then DbgCaptureProcLocals(procIdx);
    SymRollbackTo(savedSC);
    FrameSize := savedFS;
    CurProc := -1;
  end;
  Expect(tkEnd, '}');
  RCurImplType := '';
end;

procedure RParseTopLevelFn;
var name, pname: AnsiString;
    procIdx, nparams, i, idx, savedSC, savedFS, patchPos, bodyNode: Integer;
    pnames: array[0..7] of AnsiString; ptypes: array[0..7] of TTypeKind;
    precids: array[0..7] of Integer; parr: array[0..7] of Boolean;
begin
  Next; { fn }
  if CurTok.Kind <> tkIdent then Error('Rust: expected function name');
  name := CurTok.SVal; Next;
  procIdx := FindProc(name);
  if procIdx < 0 then Error('Rust: internal error — signature prescan missed ' + name);
  { A specialized generic-fn copy still carries its (already-substituted)
    <...> clause textually, e.g. `fn identity$Point<Point>(...)` — tolerate
    and discard it here; an ordinary top-level fn never has one. }
  if CurTok.Kind = tkLt then RSkipAngleClause;
  Expect(tkLParen, '(');
  nparams := 0;
  while CurTok.Kind <> tkRParen do
  begin
    if CurTok.Kind = tkMut then Next;
    if CurTok.Kind <> tkIdent then Error('Rust: expected parameter name');
    pname := CurTok.SVal; Next;
    Expect(tkColon, ':');
    parr[nparams] := False;
    if CurTok.Kind = tkAmp then
    begin
      Next;
      if CurTok.Kind = tkMut then Next;
    end;
    if CurTok.Kind = tkLBrack then
    begin
      { &[T] / &mut [T] borrowed slice, or &[T; N] — a reference to a whole
        ARRAY, which is a different thing (see the twin site in
        RRegisterFnSignatureAt). }
      Next;
      if CurTok.Kind <> tkIdent then Error('Rust: expected element type in &[T] parameter');
      { sequence RTypeKindFromName (sets LastTypeRecId) before reading it;
        stash the element tk in ptypes[nparams] first, then set it to tyRecord. }
      ptypes[nparams] := RTypeKindFromName(RTypeNameCur, True);
      if CurTok.Kind = tkSemicolon then
      begin
        Next;
        if CurTok.Kind <> tkInteger then Error('Rust: array parameter length must be an integer literal');
        Next;
        parr[nparams] := True;
        precids[nparams] := LastTypeRecId;
      end
      else
      begin
        precids[nparams] := REC_UCLASS_BASE + RSliceClassForRec(ptypes[nparams], LastTypeRecId);
        ptypes[nparams] := tyRecord;
      end;
      pnames[nparams] := pname;
      Expect(tkRBrack, ']');
    end
    else
    begin
      if CurTok.Kind <> tkIdent then Error('Rust: expected parameter type');
      { struct/enum params allowed (see RRegisterFnSignatureAt); RTypeKindFromName
        sets LastTypeRecId as a side effect, which the NEXT param's lookup would
        clobber before we get to AllocParam below — capture it per-param now. }
      ptypes[nparams] := RTypeKindFromName(RTypeNameCur, True);
      precids[nparams] := LastTypeRecId;
      pnames[nparams] := pname;
    end;
    Inc(nparams);
    if not Eat(tkComma) then Break;
  end;
  Expect(tkRParen, ')');
  if CurTok.Kind = tkMinus then
  begin
    Next; Expect(tkGt, '>');
    { consumed through RRetTypeCur so a multi-token `Option<T>` or `[T; N]` is
      skipped WHOLE; the registered signature is what actually types the fn,
      so the value is discarded here on purpose. }
    RRetTypeCur;
  end;

  savedSC := SymCount; savedFS := FrameSize;
  FrameSize := 0; CurProc := procIdx;
  Procs[procIdx].BodyAddr := CodeLen;
  Procs[procIdx].ScopeBase := SymCount;
  for i := 0 to nparams - 1 do
  begin
    if parr[i] then
    begin
      { `&[T; N]` — an ordinary by-address array param (see the parse site). }
      LastTypeRecId := precids[i];
      idx := AllocParam(pnames[i], ptypes[i], False, True);
    end
    else if ptypes[i] = tyRecord then
    begin
      LastTypeRecId := precids[i];
      idx := AllocParam(pnames[i], ptypes[i], True, False);
    end
    else
      idx := AllocParam(pnames[i], ptypes[i], False, False);
    Procs[procIdx].Params[i].SymIdx := idx;
  end;
  { A record or array return travels by the caller-owned hidden destination
    pointer (NRVO), exactly as it does for Pascal and C: the callee needs a
    frame slot to stash that incoming pointer in, and the prologue needs to
    stash it before the param-copy clobbers the register. Omit either and
    Result is written through garbage -- the same segfault the C frontend hit
    on lua's by-value union return. }
  RAllocResultSlot(procIdx);

  patchPos := EmitProcPrologue;
  Procs[procIdx].FramePatch := patchPos;
  EmitAggregateDestStash(procIdx);
  EmitParamSpillsForTarget(procIdx, nparams);

  Expect(tkBegin, '{');
  bodyNode := RParseFnBody;
  Expect(tkEnd, '}');

  { Top-level const ARRAYS are globals filled at startup (see
    RRegisterTopConsts), and `main` is where startup is -- this frontend's
    driver calls main() and exits, with no separate init hook to hang them on.
    Prepended, not appended, so a const is already populated when the first
    statement runs. }
  if (name = 'main') and (RConstInitSeq >= 0) then
  begin
    bodyNode := RSeqAppend(RConstInitSeq, bodyNode);
    RConstInitSeq := -1;
  end;

  { Zero every managed local before the body runs. The SAME defect NilPy had
    (bug-nilpy-string-local-truncates-at-255): a managed local's slot starts as
    stale stack bytes, and the FIRST assignment to it releases whatever those
    bytes point at. It stayed invisible here for as long as this frontend had
    no managed type at all; `String` gave it one, and the symptom was the
    classic plausible one -- a two-`push` function returned the right answer in
    isolation and segfaulted once a caller had a string local of its own.

    Emitted HERE, between the param spills and the body, because Rust allocates
    its locals during the body PARSE (`let`), so SymCount is only complete once
    RParseFnBody has returned -- while the parse itself emits no code, so the
    zeroing still lands ahead of the first statement. Params are skParam and
    are skipped, so the spills above survive. }
  EmitManagedLocalsZeroInit(savedSC);

  CompileAST(bodyNode);
  EmitProcEpilog(Procs[procIdx].RetSymIdx);
  PatchProcPrologue(patchPos, FrameSize);
    { DWARF -g: the routine-body tail every Pascal proc ends with (pasparser_*.inc).
    Without it this frontend's functions had NO DW_TAG_subprogram, so
    `break <fn>` in gdb answered "Function not defined" — the same total
    absence NilPy had before 58937b717. ProcBodyEnd must be taken after the
    epilogue; the locals snapshot before the scope is rolled back. }
  ProcBodyEnd[procIdx] := CodeLen;
  ProcDbgMain[procIdx] := DbgTokIsDebuggable(TokPos);
  if DebugInfo and ProcDbgMain[procIdx] then DbgCaptureProcLocals(procIdx);
  SymRollbackTo(savedSC);
  FrameSize := savedFS;
  CurProc := -1;
end;

{ Returns the procIdx of `name$concreteTypeName`, compiling it on first use
  (memoized via a plain FindProc — a second call site with the same
  concrete type just reuses it). Copies the generic fn's buffered token
  range to the end of the shared Tokens[] buffer, substituting every
  occurrence of the type-parameter identifier with the concrete type name
  (and renaming the fn itself to the mangled name), then registers +
  compiles that copy exactly like an ordinary top-level fn. }
function RSpecializeGenericFn(gfi: Integer; const concreteTypeName: AnsiString): Integer;
var mangledName: AnsiString;
    procIdx, concreteCi, i, srcIdx, startTok, concreteOff, concreteLen, b, jmpPatch: Integer;
    savedTokPos: Integer; savedCurTok: TToken;
begin
  mangledName := RGenericFuncs[gfi].Name + '$' + concreteTypeName;
  procIdx := FindProc(mangledName);
  if procIdx >= 0 then begin Result := procIdx; Exit; end;

  concreteCi := FindUClass(concreteTypeName);
  for b := 0 to RGenericFuncs[gfi].BoundCount - 1 do
    if (concreteCi < 0) or not RTypeImplementsTrait(concreteCi, RGenericFuncs[gfi].Bounds[b]) then
      Error('Rust: ' + concreteTypeName + ' does not implement required trait ' +
            RGenericFuncs[gfi].Bounds[b] + ' (bound on generic function ' +
            RGenericFuncs[gfi].Name + ')');

  concreteOff := RStoredName(concreteTypeName); concreteLen := Length(concreteTypeName);
  startTok := TokCount;
  for i := 0 to RGenericFuncs[gfi].TokCount - 1 do
  begin
    srcIdx := RGenericFuncs[gfi].TokStart + i;
    EnsureTokCapacity(TokCount + 1);
    Tokens[TokCount] := Tokens[srcIdx];
    if srcIdx = RGenericFuncs[gfi].TokStart + 1 then
    begin
      { the fn's own name token: rename to the mangled specialized name }
      Tokens[TokCount].SOffset := RStoredName(mangledName);
      Tokens[TokCount].SLen := Length(mangledName);
    end
    else if (Tokens[srcIdx].Kind = tkIdent) and CaseEqual(GetTokenStr(srcIdx), RGenericFuncs[gfi].ParamName) then
    begin
      Tokens[TokCount].SOffset := concreteOff;
      Tokens[TokCount].SLen := concreteLen;
    end;
    Inc(TokCount); EnsureTokCapacity(TokCount+1);
  end;

  RRegisterFnSignatureAt(startTok);

  { Specialization triggers mid-expression while parsing whatever function
    called the generic one — e.g. inside main's own RParseBlock, BEFORE
    main's body is handed to CompileAST. Without this jmp, the specialized
    fn's prologue/body/epilogue would land in the code stream right after
    main's already-emitted prologue with nothing to skip over it, and
    execution would fall straight from main's prologue into the
    specialization's body instead of main's own (found by testing: a
    100%-reproducible segfault, not a hypothetical). Same bracketing
    pattern ParsePyProgram uses to insert runtime setup code mid-stream. }
  EmitB($E9); jmpPatch := CodeLen; EmitI32(0);

  savedTokPos := TokPos;
  savedCurTok := CurTok;
  TokPos := startTok;
  Next; { load the copy's 'fn' token }
  RParseTopLevelFn;
  TokPos := savedTokPos;
  CurTok := savedCurTok;

  Patch32(jmpPatch, CodeLen - (jmpPatch + 4));

  Result := FindProc(mangledName);
  if Result < 0 then Error('Rust: internal error specializing ' + RGenericFuncs[gfi].Name);
end;

{ Top-level `const NAME: [T; N] = [ ... ];` — registered BEFORE any function
  body is parsed, because Rust lets a const be used above its declaration and
  because a global must be allocated while CurProc < 0. Scalar consts stay with
  RParseTopLevelConst and its AddConst fold; only the ARRAY form lands here,
  which is the one that was being swallowed whole.

  The literal itself goes through the same RParseArrayLiteral as `let`, which
  is the point of having lifted it: an array-literal parser that exists twice
  is one that gets fixed on one arm.

  Cursor-mode inside a token scan: RParseArrayLiteral consumes via CurTok/Next,
  so TokPos is positioned, the item is parsed, and the scan resumes from where
  the parse actually stopped rather than from a re-derived index. }
procedure RRegisterTopConsts;
var i, depth, arrLen, savedTokPos: Integer;
    elemTk: TTypeKind;
    name: AnsiString;
begin
  RConstInitSeq := -1;
  savedTokPos := TokPos;
  i := 0; depth := 0;
  while Tokens[i].Kind <> tkEOF do
  begin
    if Tokens[i].Kind = tkBegin then Inc(depth)
    else if Tokens[i].Kind = tkEnd then Dec(depth)
    else if (depth = 0) and (Tokens[i].Kind = tkIdent) and (GetTokenStr(i) = 'const') and
            (Tokens[i + 1].Kind = tkIdent) and (Tokens[i + 2].Kind = tkColon) and
            (Tokens[i + 3].Kind = tkLBrack) then
    begin
      name := GetTokenStr(i + 1);
      TokPos := i + 3; Next;          { CurTok = '[' of the [T; N] annotation }
      Next;                           { past '[' }
      if CurTok.Kind <> tkIdent then Error('Rust: expected element type in a const [T; N]');
      elemTk := RTypeKindFromName(RTypeNameCur, True);
      Expect(tkSemicolon, ';');
      if CurTok.Kind <> tkInteger then Error('Rust: const array length must be an integer literal');
      arrLen := CurTok.IVal;
      if arrLen <= 0 then Error('Rust: const array length must be positive');
      Next;
      Expect(tkRBrack, ']');
      Expect(tkAssign, '=');
      RConstInitSeq := RSeqAppend(RConstInitSeq,
                                  RParseArrayLiteral(name, elemTk, arrLen));
      i := TokPos - 1;
      Continue;
    end;
    Inc(i);
  end;
  { the parse above drove the cursor; put it back where the caller had it }
  TokPos := savedTokPos;
  if TokPos > 0 then begin Dec(TokPos); Next; end else Next;
end;

{ Does this program need the managed-string runtime?

  It is a token scan and not a parse because the answer is owed BEFORE the
  parse: EmitAnsiStringRuntime's shims are reached by a direct relative call,
  so every caller has to be compiled after them, which puts the decision in
  the prologue. Same shape as the Pascal driver's DetectPascalRuntimeNeeds and
  the C driver's reuse of it.

  It is a GATE rather than an always-on because the cost is not small: pulling
  builtinheap and builtin takes a Rust hello-world from 2KB of code to ~62KB.
  Every program that says `String`, `&str`, `format!` or `to_string` pays it
  and every program that does not, does not.

  The subtle half is the STRING LITERAL. A literal inside `println!("...")` is
  a const_str the write path consumes directly and needs no runtime -- which is
  every Rust test written before this rung, and the reason they must not
  regress into pulling 60KB. A literal ANYWHERE else becomes a value, so it
  does. The scan tells them apart by position: a format literal is preceded by
  exactly `println` `!` `(` or `print` `!` `(`. }
function RNeedsStringRuntime: Boolean;
var i: Integer; nm: AnsiString;
begin
  Result := False;
  for i := 0 to MainProgramTokCount - 1 do
  begin
    if Tokens[i].Kind = tkIdent then
    begin
      nm := GetTokenStr(i);
      if (nm = 'String') or (nm = 'str') or (nm = 'format') or
         (nm = 'to_string') or (nm = 'to_owned') or (nm = 'push_str') then
      begin Result := True; Exit; end;
    end
    else if Tokens[i].Kind = tkString then
    begin
      if (i >= 3) and (Tokens[i - 1].Kind = tkLParen) and
         (Tokens[i - 2].Kind = tkLogNot) and (Tokens[i - 3].Kind = tkIdent) and
         ((GetTokenStr(i - 3) = 'println') or (GetTokenStr(i - 3) = 'print')) then
        { a println!/print! format literal -- consumed by the write path }
      else
      begin Result := True; Exit; end;
    end;
  end;
end;

procedure ParseRustProgram;
var callPatch, mainIdx, jmpPatch: Integer; wantStr: Boolean;
begin
  if TargetArch <> TARGET_X86_64 then
    Error('Rust frontend: only the x86-64 target is supported by the skeleton (feature-rust-frontend-skeleton)');

  { The shared checklist: BSS_INITIAL_RSP, the per-arch entry stub, the emitted
    div0 stub, the signal runtime and the --threadsafe I/O lock stubs. This
    driver used to open-code four of those and MISS RegisterBuiltinTGuid /
    RegisterBuiltinTObject -- which is the drift the prologue exists to stop.

    wantAnsiRuntime is False, and MEASURED so: passing True registers the
    PXXStr* forwards and emits the bodies EmitAnsiStringRuntime owns, but the
    rest of that family ships in builtinheap, which a .rs compile never parses.
    Every Rust program then failed with `unresolved forward: PXXStrFromLit`.
    Rust strings are `&str` slices here, not managed AnsiStrings, so the runtime
    is dead weight for this frontend rather than a step it is missing.
    refactor-a-one-program-driver-prologue-for-every-frontend }
  wantStr := RNeedsStringRuntime;
  EmitProgramPrologue(False, wantStr, True, jmpPatch);

  { Rust's "body" is three instructions, and this driver writes them itself
    rather than getting them from a parse: call main(), then
    exit_group(main's i32 return). println!/process::exit are out of scope
    (sub-ticket 12), so the trivial test programs this skeleton targets report
    their result via exit code, same convention as a hosted C `int main()`.
    The prologue's jump lands HERE, which is why the patch is taken first --
    the stubs it emitted sit between the ELF entry and this point. }
  PatchProgramEntryJump(jmpPatch);
  EmitB($E8); callPatch := CodeLen; EmitI32(0);   { call main }
  EmitB($89); EmitB($C7);            { mov edi, eax }
  EmitB($B8); EmitI32(231);          { mov eax, 231 (exit_group) }
  EmitB($0F); EmitB($05);            { syscall }

  { The string runtime's SHIMS are emitted machine code (above, inside the
    prologue); their BODIES ship in builtinheap, and StrInt -- the int->text
    routine format! and to_string() lower onto, the same one Pascal's `Str`
    intrinsic rewrites to -- ships in builtin. A .rs compile never parsed
    either, which is why wantAnsiRuntime was False here for the frontend's
    whole life: turning it on alone produced `unresolved forward:
    PXXStrFromLit`. Both halves, or neither.

    Position: after the four instructions above, whose last is exit_group, so
    the unit bodies are reached only by call and never fallen into. Order:
    builtinheap first, mirroring every other driver -- builtin's own bodies
    use the allocator. }
  if wantStr then
  begin
    ParseUsesUnitAmbient('builtinheap');
    ParseUsesUnitAmbient('builtin');
  end;

  REnumVariantCount := 0;
  RTraitCount := 0; RImplCount := 0; RGenericFuncCount := 0;
  RAliasCount := 0;
  RPendingPreSeq := -1;
  RStripTopItems;
  TokPos := 0;
  Next;
  { shells -> enums -> struct fields: a struct field may be enum-typed
    (Piece { color: Color }), so enums must exist before field
    registration; an enum payload referencing a struct still resolves
    against the shell. }
  RRegisterStructShells;
  RRegisterEnums;
  RRegisterStructFields;
  RRegisterTraits;
  RRegisterImpls;
  { after the type prescans (a const array's element may be a struct) and
    before any body is parsed (Rust allows a const to be used above its
    declaration, and a global needs CurProc < 0) }
  RRegisterTopConsts;
  RRegisterGenericFuncs;
  RRegisterFnSignatures;

  mainIdx := FindProc('main');
  if mainIdx < 0 then Error('Rust: no fn main() found');

  while CurTok.Kind <> tkEOF do
  begin
    if CurTok.Kind = tkRecord then RParseTopLevelStruct
    else if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'enum') then RParseTopLevelEnum
    else if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'trait') then RParseTopLevelTrait
    else if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'impl') then RParseTopLevelImpl
    else if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'const') then RParseTopLevelConst
    else if (CurTok.Kind = tkFn) and (Tokens[TokPos + 1].Kind = tkLt) then RSkipGenericFnDecl
    else if CurTok.Kind = tkFn then RParseTopLevelFn
    else Error('Rust: expected fn, struct, enum, trait, impl or const at top level');
  end;

  EmitProgramEpilogue;
  Patch32(callPatch, Procs[mainIdx].BodyAddr - (callPatch + 4));
end;
