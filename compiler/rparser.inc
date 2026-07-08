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
function RSpecializeGenericFn(gfi: Integer; const concreteTypeName: AnsiString): Integer; forward;

const
  RVAR_UNIT   = 0;
  RVAR_TUPLE  = 1;
  RVAR_STRUCT = 2;
  R_MAX_VARIANTS = 4096;
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
  RTraits: array[0..R_MAX_TRAITS-1] of AnsiString;
  RTraitCount: Integer;
  RImpls: array[0..R_MAX_IMPLS-1] of TRImpl;
  RImplCount: Integer;
  RGenericFuncs: array[0..R_MAX_GENERIC_FUNCS-1] of TRGenericFunc;
  RGenericFuncCount: Integer;

function RScalarTypeName(tk: TTypeKind): AnsiString;
begin
  case tk of
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
  element address as i64 @0) + __len (i64 @8) — 16 bytes. }
function RSliceClassFor(elemTk: TTypeKind): Integer;
var name: AnsiString; ci: Integer;
begin
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
  end;
  Result := ci;
end;

function RIsSliceSym(symIdx: Integer): Boolean;
begin
  Result := (Syms[symIdx].TypeKind = tyRecord) and
            (Syms[symIdx].RecName >= REC_UCLASS_BASE) and
            RSliceCi[Syms[symIdx].RecName - REC_UCLASS_BASE];
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

function RWiden(a, b: TTypeKind): TTypeKind;
begin
  if (a = tyDouble) or (b = tyDouble) or (a = tySingle) or (b = tySingle) then Result := tyDouble
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

function RParsePrimary: Integer;
var node, fieldNode, symIdx, procIdx, argNode, lastArg, fTokIdx, gfi, ci: Integer;
    name, methodName, fullName: AnsiString;
begin
  case CurTok.Kind of
    tkInteger:
    begin
      node := AllocNode(AN_INT_LIT); ASTIVal[node] := CurTok.IVal; ASTTk[node] := Ord(tyInteger);
      Next; Result := node;
    end;
    tkFloat:
    begin
      node := AllocNode(AN_FLOAT_LIT); ASTIVal[node] := CurTok.IVal; ASTTk[node] := Ord(tyDouble);
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
      name := CurTok.SVal; Next;
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
          while Eat(tkComma) do
          begin
            argNode := AllocNode(AN_ARG);
            ASTLeft[argNode] := RParseExpr; ASTRight[argNode] := -1;
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
        lastArg := -1;
        if CurTok.Kind <> tkRParen then
          repeat
            argNode := AllocNode(AN_ARG);
            ASTLeft[argNode] := RParseExpr;
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
          Zig frontend's slice-index shape ported back). }
        Next;
        fieldNode := RParseExpr;
        Expect(tkRBrack, ']');
        ci := Syms[symIdx].RecName - REC_UCLASS_BASE;
        gfi := AllocNode(AN_INT_LIT);
        ASTIVal[gfi] := TypeSize(RSliceElemTk[ci]);
        ASTTk[gfi] := Ord(tyInt64);
        argNode := AllocNode(AN_FIELD);
        ASTLeft[argNode] := node;
        ASTSOffset[argNode] := RStoredName('__ptr'); ASTSLen[argNode] := 5;
        ASTTk[argNode] := Ord(tyInt64);
        lastArg := AllocNode(AN_DEREF);
        ASTLeft[lastArg] := RBinOp(tkPlus, argNode,
          RBinOp(tkStar, fieldNode, gfi, tyInt64), tyInt64);
        ASTTk[lastArg] := Ord(RSliceElemTk[ci]);
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
        Result := node;
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
          if procIdx < 0 then Error('Rust: ' + RTypeNameOf(ci) + ' has no method ' + methodName);
          Next; Next; { method name, ( }
          fieldNode := AllocNode(AN_CALL);
          ASTIVal[fieldNode] := procIdx;
          ASTTk[fieldNode] := Ord(Procs[procIdx].RetType);
          lastArg := AllocNode(AN_ARG);
          ASTLeft[lastArg] := node; ASTRight[lastArg] := -1;
          ASTLeft[fieldNode] := lastArg;
          if CurTok.Kind <> tkRParen then
            repeat
              argNode := AllocNode(AN_ARG);
              ASTLeft[argNode] := RParseExpr; ASTRight[argNode] := -1;
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
        node := fieldNode;
        Next;
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
var left, right, node: Integer; opTk: TTokenKind;
begin
  left := RParseAs;
  while CurTok.Kind in [tkStar, tkSlash, tkMod] do
  begin
    opTk := CurTok.Kind; Next;
    right := RParseAs;
    node := RBinOp(opTk, left, right, RWiden(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right])));
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
    { Rust >> is arithmetic on signed, logical on unsigned — the same
      split cparser encodes: tkShr = arithmetic-sar sentinel, tkIdent =
      the logical-shr sentinel Pascal's own shr uses. }
    if (opTk = tkShr) and not TypeSigned(IntToTypeKind(ASTTk[left])) then
      opTk := tkIdent;
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

function RParseIf: Integer;
var node, pairNode, condNode, thenNode, elseNode: Integer;
begin
  Next; { if }
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

function RParseWhile: Integer;
var node: Integer;
begin
  Next; { while }
  node := AllocNode(AN_WHILE);
  ASTLeft[node] := RParseExpr;
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

{ `let [mut] name [: Type] [= expr];` — mut is accepted and ignored (no
  borrow/mutability enforcement, per the umbrella's non-goal list). Two RHS
  shapes: a plain scalar expression, or a struct literal `Type { f: v, ... }`
  which lowers to one AN_ASSIGN per field (no single-node "construct" op
  exists for value-type structs, so the declaration is really N field
  stores chained by AN_SEQ). Trailing `;` is left for the caller. }
function RParseLet: Integer;
var name, typeName, variantName, fname, mangled: AnsiString;
    symIdx, ci, structCi, fTokIdx, ci2, vi, k, tagOff, tagNode, tagAssign: Integer;
    annotTk, arrElemTk: TTypeKind; hasType, qualified, isArr: Boolean;
    identNode, fieldNode, valNode, assignNode, seq, arrLen, loNode, hiNode: Integer;
begin
  Next; { let }
  if CurTok.Kind = tkMut then Next;
  if CurTok.Kind <> tkIdent then Error('Rust: expected variable name after let');
  name := CurTok.SVal; Next;
  hasType := False; annotTk := tyUnknown; structCi := -1;
  isArr := False; arrElemTk := tyUnknown; arrLen := 0;
  if CurTok.Kind = tkColon then
  begin
    Next;
    if CurTok.Kind = tkLBrack then
    begin
      { `[T; N]` fixed-array annotation }
      Next;
      if CurTok.Kind <> tkIdent then Error('Rust: expected element type in [T; N]');
      arrElemTk := RTypeKindFromName(CurTok.SVal, False);
      Next;
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
      typeName := CurTok.SVal;
      structCi := FindUClass(typeName);
      annotTk := RTypeKindFromName(typeName, True);
      Next;
    end;
    hasType := True;
  end;
  if CurTok.Kind <> tkAssign then
  begin
    if not hasType then Error('Rust: let without initializer needs a type annotation');
    if isArr then
    begin
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
  { array literal RHS: `[v; N]` repeat form or `[a, b, c]` list, unrolled
    to one AN_INDEX store per element (no whole-array construct node —
    the same per-slot shape struct literals use). Repeat form deviation:
    the element expression is re-evaluated per slot. }
  if (isArr and (CurTok.Kind = tkLBrack)) or
     ((not hasType) and (CurTok.Kind = tkLBrack) and not RBrackHasDotDotAt(TokPos - 1)) then
  begin
    Next; { [ }
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
    ci := RSliceClassFor(arrElemTk);
    fieldNode := AllocNode(AN_INDEX);
    ASTLeft[fieldNode] := RMakeIdent(symIdx);
    ASTRight[fieldNode] := loNode;
    ASTTk[fieldNode] := Ord(arrElemTk);
    valNode := AllocNode(AN_ADDR);
    ASTLeft[valNode] := fieldNode;
    ASTTk[valNode] := Ord(tyPointer);
    LastTypeRecId := REC_UCLASS_BASE + ci;
    symIdx := AllocVar(name, tyRecord);
    identNode := RMakeIdent(symIdx);
    fieldNode := AllocNode(AN_FIELD);
    ASTLeft[fieldNode] := identNode;
    ASTSOffset[fieldNode] := RStoredName('__ptr'); ASTSLen[fieldNode] := 5;
    ASTTk[fieldNode] := Ord(tyInt64);
    assignNode := AllocNode(AN_ASSIGN);
    ASTLeft[assignNode] := fieldNode; ASTRight[assignNode] := valNode;
    seq := RSeqAppend(-1, assignNode);
    fieldNode := AllocNode(AN_FIELD);
    ASTLeft[fieldNode] := identNode;
    ASTSOffset[fieldNode] := RStoredName('__len'); ASTSLen[fieldNode] := 5;
    ASTTk[fieldNode] := Ord(tyInt64);
    assignNode := AllocNode(AN_ASSIGN);
    ASTLeft[assignNode] := fieldNode;
    ASTRight[assignNode] := RBinOp(tkMinus, hiNode, loNode, tyInt64);
    Result := RSeqAppend(seq, assignNode);
    Exit;
  end;
  { enum literal RHS: bare `Variant(...)`/`Variant { .. }`/`Variant`, or
    qualified `Enum::Variant(...)`. Checked before the plain-struct-literal
    branch below since both start with a tkIdent. }
  ci2 := -1; vi := -1; qualified := False;
  if CurTok.Kind = tkIdent then
  begin
    ci2 := FindUClass(CurTok.SVal);
    if (ci2 >= 0) and REnumCi[ci2] and (Tokens[TokPos].Kind = tkPathSep) then
      qualified := True
    else if ci2 < 0 then
      vi := RFindVariantBare(CurTok.SVal);
  end;
  if qualified or (vi >= 0) then
  begin
    if qualified then
    begin
      Next; Next; { EnumName :: }
      if CurTok.Kind <> tkIdent then Error('Rust: expected variant name after ::');
      vi := RFindVariantInEnum(ci2, CurTok.SVal);
      if vi < 0 then Error('Rust: unknown variant ' + CurTok.SVal);
    end;
    variantName := REnumVariants[vi].Name;
    Next; { variant name }
    ci := REnumVariants[vi].EnumCi;
    LastTypeRecId := REC_UCLASS_BASE + ci;
    symIdx := AllocVar(name, tyRecord);
    identNode := RMakeIdent(symIdx);
    seq := -1;
    tagOff := RStoredName('__tag');
    fieldNode := AllocNode(AN_FIELD);
    ASTLeft[fieldNode] := identNode; ASTSOffset[fieldNode] := tagOff; ASTSLen[fieldNode] := 5;
    ASTTk[fieldNode] := Ord(tyInt64);
    tagNode := AllocNode(AN_INT_LIT); ASTIVal[tagNode] := REnumVariants[vi].Tag; ASTTk[tagNode] := Ord(tyInt64);
    tagAssign := AllocNode(AN_ASSIGN); ASTLeft[tagAssign] := fieldNode; ASTRight[tagAssign] := tagNode;
    seq := RSeqAppend(seq, tagAssign);
    case REnumVariants[vi].Kind of
      RVAR_TUPLE:
      begin
        Expect(tkLParen, '(');
        k := 0;
        if CurTok.Kind <> tkRParen then
          repeat
            valNode := RParseExpr;
            mangled := variantName + '.' + RIntToStr(k);
            fieldNode := AllocNode(AN_FIELD);
            ASTLeft[fieldNode] := identNode;
            ASTSOffset[fieldNode] := RStoredName(mangled); ASTSLen[fieldNode] := Length(mangled);
            ASTTk[fieldNode] := Ord(RecFieldType(REC_UCLASS_BASE + ci, mangled));
            assignNode := AllocNode(AN_ASSIGN);
            ASTLeft[assignNode] := fieldNode; ASTRight[assignNode] := valNode;
            seq := RSeqAppend(seq, assignNode);
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
          valNode := RParseExpr;
          mangled := variantName + '.' + fname;
          fieldNode := AllocNode(AN_FIELD);
          ASTLeft[fieldNode] := identNode;
          ASTSOffset[fieldNode] := RStoredName(mangled); ASTSLen[fieldNode] := Length(mangled);
          ASTTk[fieldNode] := Ord(RecFieldType(REC_UCLASS_BASE + ci, mangled));
          assignNode := AllocNode(AN_ASSIGN);
          ASTLeft[assignNode] := fieldNode; ASTRight[assignNode] := valNode;
          seq := RSeqAppend(seq, assignNode);
          if not Eat(tkComma) then Break;
        end;
        Expect(tkEnd, '}');
      end;
    end; { RVAR_UNIT: no payload }
    Result := seq;
    Exit;
  end;
  { struct literal RHS: `Type { field: expr, ... }` }
  if (CurTok.Kind = tkIdent) and (FindUClass(CurTok.SVal) >= 0) and (Tokens[TokPos].Kind = tkBegin) then
  begin
    ci := FindUClass(CurTok.SVal);
    Next; Expect(tkBegin, '{');
    LastTypeRecId := REC_UCLASS_BASE + ci;
    symIdx := AllocVar(name, tyRecord);
    identNode := RMakeIdent(symIdx);
    seq := -1;
    while CurTok.Kind <> tkEnd do
    begin
      if CurTok.Kind <> tkIdent then Error('Rust: expected field name in struct literal');
      fTokIdx := TokPos - 1;
      Next;
      Expect(tkColon, ':');
      valNode := RParseExpr;
      fieldNode := AllocNode(AN_FIELD);
      ASTLeft[fieldNode] := identNode;
      ASTSOffset[fieldNode] := Tokens[fTokIdx].SOffset;
      ASTSLen[fieldNode] := Tokens[fTokIdx].SLen;
      ASTTk[fieldNode] := Ord(RecFieldType(REC_UCLASS_BASE + ci, GetTokenStr(fTokIdx)));
      assignNode := AllocNode(AN_ASSIGN);
      ASTLeft[assignNode] := fieldNode;
      ASTRight[assignNode] := valNode;
      seq := RSeqAppend(seq, assignNode);
      if not Eat(tkComma) then Break;
    end;
    Expect(tkEnd, '}');
    Result := seq;
    Exit;
  end;
  { plain scalar initializer }
  valNode := RParseExpr;
  if hasType then
  begin
    if annotTk = tyRecord then Error('Rust: struct assignment from a non-literal expression is not supported by the skeleton yet');
    symIdx := AllocVar(name, annotTk);
  end
  else
    symIdx := AllocVar(name, IntToTypeKind(ASTTk[valNode]));
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
var scrutSym, recId, enumCi, vi, i, armCount, bindSym,
    tagFieldNode, tagValNode, condNode, bodyNode, bindsSeq, fieldNode, assignNode,
    pairNode, chain, fTokIdx: Integer;
    scrutIdent, variantName, bindName, mangled: AnsiString;
    isWildcard: Boolean;
    fieldTk: TTypeKind;
    arms: array[0..R_MAX_MATCH_ARMS-1] of TRMatchArm;
begin
  Next; { 'match' identifier }
  if CurTok.Kind <> tkIdent then Error('Rust: match scrutinee must be a plain variable for now');
  scrutIdent := CurTok.SVal;
  scrutSym := FindSym(scrutIdent);
  if scrutSym < 0 then Error('Rust: undefined variable ' + scrutIdent);
  Next;
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
    begin
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
                fieldTk := RecFieldType(REC_UCLASS_BASE + enumCi, mangled);
                if fieldTk = tyRecord then LastTypeRecId := RecFieldRecId(REC_UCLASS_BASE + enumCi, mangled)
                else LastTypeRecId := REC_NONE;
                bindSym := AllocVar(bindName, fieldTk);
                fieldNode := AllocNode(AN_FIELD);
                ASTLeft[fieldNode] := RMakeIdent(scrutSym);
                ASTSOffset[fieldNode] := RStoredName(mangled); ASTSLen[fieldNode] := Length(mangled);
                ASTTk[fieldNode] := Ord(Syms[bindSym].TypeKind);
                assignNode := AllocNode(AN_ASSIGN);
                ASTLeft[assignNode] := RMakeIdent(bindSym); ASTRight[assignNode] := fieldNode;
                bindsSeq := RSeqAppend(bindsSeq, assignNode);
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
            bindName := CurTok.SVal; fTokIdx := TokPos - 1; Next;
            mangled := variantName + '.' + bindName;
            fieldTk := RecFieldType(REC_UCLASS_BASE + enumCi, mangled);
            if fieldTk = tyRecord then LastTypeRecId := RecFieldRecId(REC_UCLASS_BASE + enumCi, mangled)
            else LastTypeRecId := REC_NONE;
            bindSym := AllocVar(bindName, fieldTk);
            fieldNode := AllocNode(AN_FIELD);
            ASTLeft[fieldNode] := RMakeIdent(scrutSym);
            ASTSOffset[fieldNode] := RStoredName(mangled); ASTSLen[fieldNode] := Length(mangled);
            ASTTk[fieldNode] := Ord(Syms[bindSym].TypeKind);
            assignNode := AllocNode(AN_ASSIGN);
            ASTLeft[assignNode] := RMakeIdent(bindSym); ASTRight[assignNode] := fieldNode;
            bindsSeq := RSeqAppend(bindsSeq, assignNode);
            if not Eat(tkComma) then Break;
          end;
          Expect(tkEnd, '}');
        end;
      end; { RVAR_UNIT: no pattern payload }
    end;

    { `=>` — two plain tokens (assign, then gt), same trick as `->` uses;
      no dedicated fat-arrow token needed. }
    if CurTok.Kind <> tkAssign then Error('Rust: expected => after match pattern');
    Next;
    if CurTok.Kind <> tkGt then Error('Rust: expected => after match pattern');
    Next;

    Expect(tkBegin, '{');
    bodyNode := RSeqAppend(bindsSeq, RParseBlock);
    Expect(tkEnd, '}');
    Eat(tkComma);

    arms[armCount].IsWildcard := isWildcard;
    arms[armCount].BodyNode := bodyNode;
    if not isWildcard then
    begin
      tagFieldNode := AllocNode(AN_FIELD);
      ASTLeft[tagFieldNode] := RMakeIdent(scrutSym);
      ASTSOffset[tagFieldNode] := RStoredName('__tag'); ASTSLen[tagFieldNode] := 5;
      ASTTk[tagFieldNode] := Ord(tyInt64);
      tagValNode := AllocNode(AN_INT_LIT);
      ASTIVal[tagValNode] := REnumVariants[vi].Tag; ASTTk[tagValNode] := Ord(tyInt64);
      arms[armCount].CondNode := RBinOp(tkEq, tagFieldNode, tagValNode, tyBoolean);
    end;
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
  Result := chain;
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
      while (Tokens[src].Kind <> tkSemicolon) and (Tokens[src].Kind <> tkEOF) do Inc(src);
      if Tokens[src].Kind = tkSemicolon then Inc(src);
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

{ `println!("fmt {} ...", args);` / `print!(...)` — the Zig frontend's
  std.debug.print splitter ported back (feature-rust-misc-semantics #9 +
  feature-rust-rtl-macros-io #12, the format-output subset): literal fmt
  segments become AN_STR_LIT nodes pointing straight into the fmt token's
  already-decoded TokChars bytes, each {...} placeholder ({}, {:?}, ...)
  consumes the next argument, everything chains as one AN_ARG list under
  a single AN_WRITE / AN_WRITELN. {{ }} escapes are not handled. }
function RParsePrintln(isLn: Boolean): Integer;
var fmtOff, fmtLen, i, segStart: Integer;
    node, lastArg, argNode, litNode: Integer;
    argExprs: array[0..7] of Integer;
    argCount, argUsed: Integer;

  procedure AddArg(exprNode: Integer);
  begin
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

  node := AllocNode(AN_WRITE);
  if isLn then ASTKind[node] := AN_WRITELN;
  ASTLeft[node] := -1;
  lastArg := -1;
  argUsed := 0;

  segStart := 0;
  i := 0;
  while i < fmtLen do
  begin
    if TokChars[fmtOff + i] = '{' then
    begin
      AddSegment(fmtOff + segStart, i - segStart);
      while (i < fmtLen) and (TokChars[fmtOff + i] <> '}') do Inc(i);
      if i >= fmtLen then Error('Rust: unterminated {} placeholder in format string');
      Inc(i); { step past the closing brace }
      segStart := i;
      if argUsed >= argCount then Error('Rust: more {} placeholders than arguments');
      AddArg(argExprs[argUsed]);
      Inc(argUsed);
    end
    else
      Inc(i);
  end;
  AddSegment(fmtOff + segStart, fmtLen - segStart);
  if argUsed < argCount then Error('Rust: more arguments than {} placeholders');

  Result := node;
end;

function RParseStatement: Integer;
var name, fname: AnsiString; symIdx, node, rhsNode, lhsNode, baseNode, fieldNode, fTokIdx: Integer;
    opTk: TTokenKind;
begin
  case CurTok.Kind of
    tkIf: begin Result := RParseIf; Exit; end;
    tkWhile: begin Result := RParseWhile; Exit; end;
    tkLoop: begin Result := RParseLoop; Exit; end;
    tkFor: begin Result := RParseFor; Exit; end;
    tkBegin: begin Next; Result := RParseBlock; Expect(tkEnd, '}'); Exit; end;
    tkSemicolon: begin Next; Result := -1; Exit; end;
    tkLet: begin Result := RParseLet; Expect(tkSemicolon, ';'); Exit; end;
    tkExit:
    begin
      Next;
      node := AllocNode(AN_EXIT);
      if CurTok.Kind <> tkSemicolon then ASTLeft[node] := RParseExpr;
      Expect(tkSemicolon, ';');
      Result := node;
      Exit;
    end;
    tkBreak: begin Next; Expect(tkSemicolon, ';'); Result := AllocNode(AN_BREAK); Exit; end;
    tkContinue: begin Next; Expect(tkSemicolon, ';'); Result := AllocNode(AN_CONTINUE); Exit; end;
  end;

  if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'match') then begin Result := RParseMatch; Exit; end;

  if (CurTok.Kind = tkIdent) and (Tokens[TokPos].Kind = tkLogNot) and
     (Tokens[TokPos + 1].Kind = tkLParen) and
     ((CurTok.SVal = 'println') or (CurTok.SVal = 'print')) then
  begin
    Result := RParsePrintln(CurTok.SVal = 'println');
    Expect(tkSemicolon, ';');
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
      tkSlashEq: rhsNode := RBinOp(tkSlash, RMakeIdent(symIdx), rhsNode, Syms[symIdx].TypeKind);
      tkAmpEq:   rhsNode := RBinOp(tkAnd,   RMakeIdent(symIdx), rhsNode, Syms[symIdx].TypeKind);
      tkPipeEq:  rhsNode := RBinOp(tkOr,    RMakeIdent(symIdx), rhsNode, Syms[symIdx].TypeKind);
      tkXorEq:   rhsNode := RBinOp(tkXor,   RMakeIdent(symIdx), rhsNode, Syms[symIdx].TypeKind);
      tkShlEq:   rhsNode := RBinOp(tkShl,   RMakeIdent(symIdx), rhsNode, Syms[symIdx].TypeKind);
      tkShrEq:
        if TypeSigned(Syms[symIdx].TypeKind) then
          rhsNode := RBinOp(tkShr, RMakeIdent(symIdx), rhsNode, Syms[symIdx].TypeKind)
        else
          rhsNode := RBinOp(tkIdent, RMakeIdent(symIdx), rhsNode, Syms[symIdx].TypeKind);
      else ;
    end;
    lhsNode := RMakeIdent(symIdx);
    node := AllocNode(AN_ASSIGN);
    ASTLeft[node] := lhsNode; ASTRight[node] := rhsNode;
    Expect(tkSemicolon, ';');
    Result := node;
    Exit;
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
    rhsNode := RParseExpr;
    baseNode := RMakeIdent(symIdx);
    fieldNode := AllocNode(AN_FIELD);
    ASTLeft[fieldNode] := baseNode;
    ASTSOffset[fieldNode] := Tokens[fTokIdx].SOffset;
    ASTSLen[fieldNode] := Tokens[fTokIdx].SLen;
    ASTTk[fieldNode] := Ord(RecFieldType(Syms[symIdx].RecName, fname));
    node := AllocNode(AN_ASSIGN);
    ASTLeft[node] := fieldNode; ASTRight[node] := rhsNode;
    Expect(tkSemicolon, ';');
    Result := node;
    Exit;
  end;

  Result := RParseExpr;
  { `a[i] = e;` / `s[i] = e;` — indexed stores parse as an expression
    followed by `=` (AN_INDEX / slice AN_DEREF are valid assign targets). }
  if (CurTok.Kind = tkAssign) and
     ((ASTKind[Result] = AN_INDEX) or (ASTKind[Result] = AN_DEREF)) then
  begin
    Next;
    node := AllocNode(AN_ASSIGN);
    ASTLeft[node] := Result;
    ASTRight[node] := RParseExpr;
    Result := node;
  end;
  Expect(tkSemicolon, ';');
end;

function RParseBlock: Integer;
var stmt: Integer;
begin
  Result := -1;
  while CurTok.Kind <> tkEnd do
  begin
    if CurTok.Kind = tkEOF then Error('Rust: unterminated block (missing })');
    stmt := RParseStatement;
    Result := RSeqAppend(Result, stmt);
  end;
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
var i, j, ci, curOff, sz, align, nameTokIdx: Integer; tk: TTypeKind;
begin
  i := 0;
  while i < MainProgramTokCount - 2 do
  begin
    if (Tokens[i].Kind = tkRecord) and (Tokens[i + 1].Kind = tkIdent) and (Tokens[i + 2].Kind = tkBegin) then
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
        if Tokens[j].Kind <> tkIdent then Error('Rust: expected field type');
        tk := RTypeKindFromName(GetTokenStr(j), True);
        Inc(j);
        sz := TypeSize(tk);
        if TypeAlign(tk) > align then align := TypeAlign(tk);
        curOff := AlignTo(curOff, TypeAlign(tk));
        AddUField(ci, Tokens[nameTokIdx].SOffset, Tokens[nameTokIdx].SLen, curOff, Ord(tk), LastTypeRecId);
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
            sz := TypeSize(tk);
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
            sz := TypeSize(tk);
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
var j, depth, nparams, procIdx, k: Integer; name: AnsiString;
    pnames: array[0..3] of AnsiString; ptypes: array[0..3] of TTypeKind;
    retType: TTypeKind;
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
    if nparams >= 4 then Error('Rust: too many parameters (skeleton limit is 4)');
    if Tokens[j].Kind <> tkIdent then Error('Rust: expected parameter name in ' + name);
    pnames[nparams] := GetTokenStr(j); Inc(j);
    if Tokens[j].Kind <> tkColon then Error('Rust: expected : in parameter list');
    Inc(j);
    if Tokens[j].Kind <> tkIdent then Error('Rust: expected parameter type');
    { struct/enum params allowed (always passed by address, same as self —
      see RParseTopLevelFn/RRegisterImpls); struct RETURN values stay out of
      scope, so the return type below still passes allowStruct=False. }
    ptypes[nparams] := RTypeKindFromName(GetTokenStr(j), True);
    Inc(j);
    Inc(nparams);
    if Tokens[j].Kind = tkComma then Inc(j);
  end;
  Inc(j); { consume ) }
  retType := tyInteger; { Rust's () return; unused Result slot, same trick C's void uses }
  if (Tokens[j].Kind = tkMinus) and (Tokens[j + 1].Kind = tkGt) then
  begin
    j := j + 2;
    if Tokens[j].Kind <> tkIdent then Error('Rust: expected return type after ->');
    retType := RTypeKindFromName(GetTokenStr(j), False);
    Inc(j);
  end;
  procIdx := RegisterProc(name, True, retType, nparams, pnames, ptypes);
  for k := 0 to nparams - 1 do
    if ptypes[k] = tyRecord then Procs[procIdx].Params[k].IsRef := True;
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
var i, j, ci, nparams, procIdx: Integer;
    typeName, traitName, methodName, fullName: AnsiString;
    pnamesFull: array[0..3] of AnsiString; ptypesFull: array[0..3] of TTypeKind;
    retType: TTypeKind; hasTrait: Boolean;
begin
  i := 0;
  while i < MainProgramTokCount - 2 do
  begin
    if (Tokens[i].Kind = tkIdent) and (GetTokenStr(i) = 'impl') then
    begin
      hasTrait := False; traitName := '';
      j := i + 1;
      if (Tokens[j].Kind = tkIdent) and (Tokens[j + 1].Kind = tkIdent) and
         (GetTokenStr(j + 1) = 'for') then
      begin
        traitName := GetTokenStr(j);
        if RFindTrait(traitName) < 0 then Error('Rust: unknown trait ' + traitName);
        hasTrait := True;
        j := j + 2;
      end;
      if Tokens[j].Kind <> tkIdent then Error('Rust: expected type name after impl');
      typeName := GetTokenStr(j);
      ci := FindUClass(typeName);
      if ci < 0 then Error('Rust: impl for unknown type ' + typeName);
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
        if Tokens[j].Kind = tkAmp then Inc(j);
        if (Tokens[j].Kind <> tkIdent) or (GetTokenStr(j) <> 'self') then
          Error('Rust: expected self as the first parameter of ' + methodName + ' (skeleton: no static/associated fns)');
        Inc(j);
        if Tokens[j].Kind = tkComma then Inc(j);
        pnamesFull[0] := 'self'; ptypesFull[0] := tyRecord;
        nparams := 0;
        while Tokens[j].Kind <> tkRParen do
        begin
          if Tokens[j].Kind = tkMut then Inc(j);
          if nparams >= 3 then Error('Rust: too many parameters (skeleton limit is 3 + self)');
          if Tokens[j].Kind <> tkIdent then Error('Rust: expected parameter name in ' + methodName);
          pnamesFull[nparams + 1] := GetTokenStr(j); Inc(j);
          if Tokens[j].Kind <> tkColon then Error('Rust: expected : in parameter list');
          Inc(j);
          if Tokens[j].Kind <> tkIdent then Error('Rust: expected parameter type');
          ptypesFull[nparams + 1] := RTypeKindFromName(GetTokenStr(j), False);
          Inc(j);
          Inc(nparams);
          if Tokens[j].Kind = tkComma then Inc(j);
        end;
        Inc(j); { consume ) }
        retType := tyInteger;
        if (Tokens[j].Kind = tkMinus) and (Tokens[j + 1].Kind = tkGt) then
        begin
          j := j + 2;
          if Tokens[j].Kind <> tkIdent then Error('Rust: expected return type after ->');
          retType := RTypeKindFromName(GetTokenStr(j), False);
          Inc(j);
        end;
        fullName := typeName + '::' + methodName;
        procIdx := RegisterProc(fullName, True, retType, nparams + 1, pnamesFull, ptypesFull);
        { RegisterProc always defaults Params[].IsRef to False — self is
          always passed by address (see the file-header note), so this must
          be set explicitly or the caller passes self by raw value while the
          callee's AllocParam(isRef=True) dereferences it as a pointer,
          reading garbage / segfaulting (found via testing, not by inspection). }
        Procs[procIdx].Params[0].IsRef := True;
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

{ `impl [Trait for] Type { fn method(&self, ...) -> RetType { .. } ... }` —
  methods were already RegisterProc'd (mangled "Type::method") by
  RRegisterImpls; this compiles each body, same shape as RParseTopLevelFn
  but with `self` prepended as an implicit, always-by-reference param 0. }
procedure RParseTopLevelImpl;
var typeName, traitName, fname, pname, fullName: AnsiString;
    ci, procIdx, nparams, i, idx, savedSC, savedFS, patchPos, bodyNode: Integer;
    pnames: array[0..2] of AnsiString; ptypes: array[0..2] of TTypeKind;
begin
  Next; { impl }
  if (CurTok.Kind = tkIdent) and (Tokens[TokPos].Kind = tkIdent) and (GetTokenStr(TokPos) = 'for') then
  begin
    traitName := CurTok.SVal;
    Next; Next; { trait name, 'for' }
  end;
  if CurTok.Kind <> tkIdent then Error('Rust: expected type name after impl');
  typeName := CurTok.SVal;
  ci := FindUClass(typeName);
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
    if CurTok.Kind = tkAmp then Next;
    if (CurTok.Kind <> tkIdent) or (CurTok.SVal <> 'self') then
      Error('Rust: expected self as the first parameter of ' + fullName);
    Next;
    Eat(tkComma);
    nparams := 0;
    while CurTok.Kind <> tkRParen do
    begin
      if CurTok.Kind = tkMut then Next;
      if nparams >= 3 then Error('Rust: too many parameters (skeleton limit is 3 + self)');
      if CurTok.Kind <> tkIdent then Error('Rust: expected parameter name');
      pname := CurTok.SVal; Next;
      Expect(tkColon, ':');
      if CurTok.Kind <> tkIdent then Error('Rust: expected parameter type');
      ptypes[nparams] := RTypeKindFromName(CurTok.SVal, False);
      pnames[nparams] := pname;
      Next;
      Inc(nparams);
      if not Eat(tkComma) then Break;
    end;
    Expect(tkRParen, ')');
    if CurTok.Kind = tkMinus then
    begin
      Next; Expect(tkGt, '>');
      if CurTok.Kind <> tkIdent then Error('Rust: expected return type after ->');
      Next;
    end;

    savedSC := SymCount; savedFS := FrameSize;
    FrameSize := 0; CurProc := procIdx;
    Procs[procIdx].BodyAddr := CodeLen;
    Procs[procIdx].ScopeBase := SymCount;
    LastTypeRecId := REC_UCLASS_BASE + ci;
    idx := AllocParam('self', tyRecord, True, False);
    Procs[procIdx].Params[0].SymIdx := idx;
    for i := 0 to nparams - 1 do
    begin
      idx := AllocParam(pnames[i], ptypes[i], False, False);
      Procs[procIdx].Params[i + 1].SymIdx := idx;
    end;
    idx := AllocVar('Result', Procs[procIdx].RetType);
    Procs[procIdx].RetSymIdx := idx;

    patchPos := EmitProcPrologue;
    Procs[procIdx].FramePatch := patchPos;
    for i := 0 to nparams do { 0 = self, 1..nparams = real params }
    begin
      idx := Procs[procIdx].Params[i].SymIdx;
      if ParamSize(idx) = 8 then EmitB($48);
      EmitB($89);
      case i of
        0: EmitB($BD);
        1: EmitB($B5);
        2: EmitB($95);
        3: EmitB($8D);
      end;
      EmitI32(Syms[idx].Offset);
    end;

    Expect(tkBegin, '{');
    bodyNode := RParseBlock;
    Expect(tkEnd, '}');

    CompileAST(bodyNode);
    EmitProcEpilog(Procs[procIdx].RetSymIdx);
    PatchProcPrologue(patchPos, FrameSize);
    SymRollbackTo(savedSC);
    FrameSize := savedFS;
    CurProc := -1;
  end;
  Expect(tkEnd, '}');
end;

procedure RParseTopLevelFn;
var name, pname: AnsiString;
    procIdx, nparams, i, idx, savedSC, savedFS, patchPos, bodyNode: Integer;
    pnames: array[0..3] of AnsiString; ptypes: array[0..3] of TTypeKind;
    precids: array[0..3] of Integer;
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
    if CurTok.Kind <> tkIdent then Error('Rust: expected parameter type');
    { struct/enum params allowed (see RRegisterFnSignatureAt); RTypeKindFromName
      sets LastTypeRecId as a side effect, which the NEXT param's lookup would
      clobber before we get to AllocParam below — capture it per-param now. }
    ptypes[nparams] := RTypeKindFromName(CurTok.SVal, True);
    precids[nparams] := LastTypeRecId;
    pnames[nparams] := pname;
    Next;
    Inc(nparams);
    if not Eat(tkComma) then Break;
  end;
  Expect(tkRParen, ')');
  if CurTok.Kind = tkMinus then
  begin
    Next; Expect(tkGt, '>');
    if CurTok.Kind <> tkIdent then Error('Rust: expected return type after ->');
    Next;
  end;

  savedSC := SymCount; savedFS := FrameSize;
  FrameSize := 0; CurProc := procIdx;
  Procs[procIdx].BodyAddr := CodeLen;
  Procs[procIdx].ScopeBase := SymCount;
  for i := 0 to nparams - 1 do
  begin
    if ptypes[i] = tyRecord then
    begin
      LastTypeRecId := precids[i];
      idx := AllocParam(pnames[i], ptypes[i], True, False);
    end
    else
      idx := AllocParam(pnames[i], ptypes[i], False, False);
    Procs[procIdx].Params[i].SymIdx := idx;
  end;
  idx := AllocVar('Result', Procs[procIdx].RetType);
  Procs[procIdx].RetSymIdx := idx;

  patchPos := EmitProcPrologue;
  Procs[procIdx].FramePatch := patchPos;
  for i := 0 to nparams - 1 do
  begin
    idx := Procs[procIdx].Params[i].SymIdx;
    if ParamSize(idx) = 8 then EmitB($48);
    EmitB($89);
    case i of
      0: EmitB($BD);
      1: EmitB($B5);
      2: EmitB($95);
      3: EmitB($8D);
    end;
    EmitI32(Syms[idx].Offset);
  end;

  Expect(tkBegin, '{');
  bodyNode := RParseBlock;
  Expect(tkEnd, '}');

  CompileAST(bodyNode);
  EmitProcEpilog(Procs[procIdx].RetSymIdx);
  PatchProcPrologue(patchPos, FrameSize);
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
    if TokCount >= MAX_TOKENS then Error('Rust: token buffer overflow specializing ' + RGenericFuncs[gfi].Name);
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
    Inc(TokCount);
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

procedure ParseRustProgram;
var callPatch, mainIdx: Integer;
begin
  if TargetArch <> TARGET_X86_64 then
    Error('Rust frontend: only the x86-64 target is supported by the skeleton (feature-rust-frontend-skeleton)');

  BSS_INITIAL_RSP := BSSSize; Inc(BSSSize, 8);
  { Entry stub: call main(), then exit_group(main's i32 return) — println!/
    process::exit are out of scope (sub-ticket 12), so the trivial test
    programs this skeleton targets report their result via exit code, same
    convention as a hosted C `int main()`. }
  EmitB($48); EmitB($89); EmitB($24); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);
  EmitB($E8); callPatch := CodeLen; EmitI32(0);   { call main }
  EmitB($89); EmitB($C7);            { mov edi, eax }
  EmitB($B8); EmitI32(231);          { mov eax, 231 (exit_group) }
  EmitB($0F); EmitB($05);            { syscall }

  REnumVariantCount := 0;
  RTraitCount := 0; RImplCount := 0; RGenericFuncCount := 0;
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

  ApplyCallFixups;
  Patch32(callPatch, Procs[mainIdx].BodyAddr - (callPatch + 4));
end;
