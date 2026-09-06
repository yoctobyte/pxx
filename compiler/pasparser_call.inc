{ ===== pasparser_call.inc — Pascal frontend: calls, operators, directives ====

  Carved out of pasparser_*.inc, byte-for-byte, by
  refactor-a-carve-out-plexer-pparser-so-p-owns-its-own-files.

  Owned by Track P (Pascal frontend). Included from compiler.pas at exactly the
  point it used to occupy, so include ORDER is unchanged — that is what makes
  the carve-out provable by the self-host fixedpoint rather than by reading it.

  Contents: what a CALL SITE needs — `operator` overload definitions, argument
  parsing and default-argument filling, overload ranking and the method/ctor
  overload search, calling-convention and interface-method directives, the
  class-reference / metaclass operators, property index arguments, and GUID
  literals.

  DO NOT factor anything here into a shared helper with pyparser.inc/cparser.inc.
  What is shared between frontends is the AST and the IR, never the parser:
  devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md }

{ The (kind, record id) an operator OPERAND's declared type name denotes.

  Both operands resolve through here, so the LEFT key and the SECOND key cannot
  disagree about what `TVec` or `Double` means — which is the failure mode the
  two-key table exists to remove, not one to reintroduce by resolving each side
  its own way. feature-a-operator-table-keyed-on-both-operands }
procedure OperandTypeKindRec(const nm: AnsiString; var tk, rec: Integer);
var ci: Integer; stk: TTypeKind;
begin
  { Record the operand's real type kind so the registration tag matches how the
    use site looks it up (a record operand carries ASTTk=tyRecord, a class
    operand tyClass). Registering everything as tyClass made FindOpOverload miss
    for record operands, so `a + b` on records silently fell through to a scalar
    binop. }
  rec := IsRecordType(nm);
  if rec <> REC_NONE then
  begin
    tk := Ord(tyRecord);
    Exit;
  end;
  ci := FindUClass(nm);
  if ci >= 0 then
  begin
    rec := REC_UCLASS_BASE + ci;
    tk := Ord(tyClass);
    Exit;
  end;
  { SCALAR operand types (FPC allows operators on any type — tgenfunc8's
    `operator := (aOther: LongInt): String`). Keyed on the type kind with recId
    REC_NONE. }
  rec := REC_NONE;
  if CaseEqual(nm, 'string') or CaseEqual(nm, 'ansistring') then
    stk := tyAnsiString
  else
    { the shared builtin-type-name table, not a private copy of the float names
      — which is how `Extended` came to register as tyDouble here while
      ParseTypeKind gave it tyExtended. }
    stk := BuiltinTypeNameTk(nm);
  if stk = tyUnknown then
    Error('operator overloading: ' + nm + ' is not a supported operand type');
  tk := Ord(stk);
end;

{ Parses: operator < (a, b: TMyType): Boolean; begin...end;
  Called when CurTok = tkIdent('operator') at top level }
procedure ParseOperatorDef;
var
  opKind: TTokenKind;
  opKey, dupPi: Integer;
  scalarTk2: TTypeKind;
  synName: AnsiString;
  typeName, rightName: AnsiString;
  recId: Integer;
  opTypeKind: Integer;
  rightTk, rightRec: Integer;
  depth, i, j: Integer;
  isFunc, foundClose: Boolean;
  nameOff, nameLen: Integer;
  procIdx: Integer;
  isClassOp: Boolean;          { the declaration was spelled `class operator` }
  qualName: AnsiString;        { ...and the `TRec.` it was qualified with }
  qualTk, qualRec: Integer;
  savedCMC, savedMIOp: Integer;  { CurMethClass / MethImplOwnerCi across the body -- see below }
begin
  { `class operator TPt.+ (const a, b: TPt): TPt;` — FPC's ADVANCED-RECORD operator syntax.
    Both the `class` prefix and the `TRec.` qualifier are accepted and dropped: pxx keys an
    operator on its OPERAND TYPES, not on an owning type, so the qualifier carries no
    information the signature does not already have. A plain top-level
    `operator + (a, b: TPt): TPt` was already supported and means exactly the same thing —
    this just lets FPC's spelling through to the same machinery. }
  isClassOp := (CurTok.Kind = tkClass);
  if isClassOp then Next;
  Next; { consume 'operator' }
  qualName := '';
  if (CurTok.Kind = tkIdent) and (TokPos < TokCount) and (Tokens[TokPos].Kind = tkDot) then
  begin
    qualName := GetTokenStrFromRaw(Tokens[TokPos - 1].SOffset, Tokens[TokPos - 1].SLen);
    Next;   { the TRec qualifier }
    Next;   { the dot }
  end;
  { A `class operator` is a METHOD, so at top level it must name the record it
    belongs to. `class operator Add(A, B: TFoo): TFoo;` written outside any type
    is toperator10's %fail, and FPC says "constructors, destructors and class
    operators must be methods".

    This is reachable only from the top level: an in-record `class operator`
    DECLARATION never arrives here at all -- ParseTypeSection's member loop skips
    the signature to its `;` and discards it, because pxx keys an operator on its
    operand types and the declaration carries nothing the definition does not. So
    "no qualifier" here means "not attached to any record", with no third case.

    Before the Delphi NAME spellings landed the row was refused for an unrelated
    reason -- `Add` was not a recognised operator name -- and this check is what
    replaces that accident with the rule it was standing in for. }
  if isClassOp and (qualName = '') then
    Error('constructors, destructors and class operators must be methods: a '
          + '`class operator` outside a record or class body has no type to '
          + 'belong to (write `class operator TRec.<op>`, or drop `class` for a '
          + 'global operator)');
  { Resolve the qualifier HERE rather than after the body, because the body
    needs it: it is the scope the body parses in (see the CurMethClass note at
    ParseSubroutine below). ONE call, so the scope the body gets and the type the
    signature is checked against cannot disagree -- which is the same argument
    OperandTypeKindRec's own header makes about the two operand keys. A
    qualifier that names no type now reports at the HEADER instead of after the
    body, which is where it is. }
  qualTk := 0; qualRec := REC_NONE;
  if qualName <> '' then OperandTypeKindRec(qualName, qualTk, qualRec);
  opKind := CurTok.Kind;
  opKey := -1;
  { `in` and `><` are here for the same reason the keyword ones are: both are
    real operators the expression parser already builds an AN_BINOP for --
    `Ord(tkIn)` at the membership arm, `tkSymDiff` all the way down to five
    backends' codegen -- and neither could be OVERLOADED only because this list
    did not name it. Nothing else had to change for `operator in`.

    The KEYWORD-spelled operators (and/or/xor/shl/shr/not) belong in this list
    beside the punctuation ones: they are the same overloadable operators with a
    different lexeme, and FPC's own constexp.pas declares five of them on
    Tconstexprint. Leaving them out made `operator and (const a,b:T):T` a syntax
    error while `operator + (const a,b:T):T` was fine, which is a distinction
    the language does not draw. `not` is the unary one; the arity branch below
    is what separates it. }
  if opKind in [tkPlus, tkMinus, tkStar, tkSlash, tkDiv, tkMod, tkEq, tkNeq, tkLt, tkLe, tkGt, tkGe,
                tkAnd, tkOr, tkXor, tkShl, tkShr, tkNot, tkIn, tkSymDiff] then
    opKey := Ord(opKind)
  else if opKind = tkAssign then
    { `operator :=(src): TDst` — implicit conversion at assignment }
    opKey := Ord(tkAssign)
  else if opKind = tkIdent then
  begin
    { Named operators (FPC): Implicit = the := form; Explicit fires at
      value casts; Inc/Dec at the Inc()/Dec() statements; Enumerator at for-in.
      Initialize/Finalize are MANAGEMENT operators — the compiler invokes them
      at a variable's lifetime events, not at an expression. }
    if CaseEqual(CurTok.SVal, 'implicit') then opKey := Ord(tkAssign)
    else if CaseEqual(CurTok.SVal, 'explicit') then opKey := OPK_EXPLICIT
    else if CaseEqual(CurTok.SVal, 'inc') then opKey := OPK_INC
    else if CaseEqual(CurTok.SVal, 'dec') then opKey := OPK_DEC
    else if CaseEqual(CurTok.SVal, 'enumerator') then opKey := OPK_ENUMERATOR
    else if CaseEqual(CurTok.SVal, 'initialize') then opKey := OPK_INITIALIZE
    else if CaseEqual(CurTok.SVal, 'finalize') then opKey := OPK_FINALIZE
    else if CaseEqual(CurTok.SVal, 'addref') then opKey := OPK_ADDREF
    else if CaseEqual(CurTok.SVal, 'copy') then opKey := OPK_COPY
    { THE DELPHI NAMES FOR THE OPERATORS ALREADY SPELLED ABOVE AS SYMBOLS.
      `class operator Add(a, b: T): T` and `operator + (a, b: T): T` declare the
      same thing; only the lexeme differs, exactly as `Implicit` and `:=` above
      already do. So they map onto the SAME opKey rather than growing a second
      key space -- the use site is an AN_BINOP carrying a token ordinal, and a
      separate key would mean every lookup asking twice.
      devdocs/dev/normalise-dont-special-case.md

      The table is written WHOLE rather than filled in as rows demand it. A
      partial table is the arm that stays broken: the corpus asks for Add,
      Subtract, Multiply, Modulus, Negative, Positive, NotEqual, GreaterThan,
      RightShift, LogicalAnd/Or/Xor/Not and In, and there is no reason the
      thirteenth spelling should be the one that errors.

      Delphi draws a Logical/Bitwise distinction that Pascal's `and`/`or`/`xor`/
      `not` do not: both spellings mean the same operator on the same operand
      types here, and pxx keys an operator on its operand types, so they
      deliberately collapse onto one key. RightShift lands on tkShrLogical for
      the reason the `shr` arm below documents -- the lexer gives `shr` no token
      of its own and the AST carries the renamed ordinal. }
    else if CaseEqual(CurTok.SVal, 'add') then opKey := Ord(tkPlus)
    else if CaseEqual(CurTok.SVal, 'positive') then opKey := Ord(tkPlus)
    else if CaseEqual(CurTok.SVal, 'subtract') then opKey := Ord(tkMinus)
    else if CaseEqual(CurTok.SVal, 'negative') then opKey := Ord(tkMinus)
    else if CaseEqual(CurTok.SVal, 'multiply') then opKey := Ord(tkStar)
    else if CaseEqual(CurTok.SVal, 'divide') then opKey := Ord(tkSlash)
    else if CaseEqual(CurTok.SVal, 'intdivide') then opKey := Ord(tkDiv)
    else if CaseEqual(CurTok.SVal, 'modulus') then opKey := Ord(tkMod)
    else if CaseEqual(CurTok.SVal, 'leftshift') then opKey := Ord(tkShl)
    else if CaseEqual(CurTok.SVal, 'logicaland') then opKey := Ord(tkAnd)
    else if CaseEqual(CurTok.SVal, 'bitwiseand') then opKey := Ord(tkAnd)
    else if CaseEqual(CurTok.SVal, 'logicalor') then opKey := Ord(tkOr)
    else if CaseEqual(CurTok.SVal, 'bitwiseor') then opKey := Ord(tkOr)
    else if CaseEqual(CurTok.SVal, 'logicalxor') then opKey := Ord(tkXor)
    else if CaseEqual(CurTok.SVal, 'bitwisexor') then opKey := Ord(tkXor)
    else if CaseEqual(CurTok.SVal, 'logicalnot') then opKey := Ord(tkNot)
    else if CaseEqual(CurTok.SVal, 'bitwisenot') then opKey := Ord(tkNot)
    else if CaseEqual(CurTok.SVal, 'equal') then opKey := Ord(tkEq)
    else if CaseEqual(CurTok.SVal, 'notequal') then opKey := Ord(tkNeq)
    else if CaseEqual(CurTok.SVal, 'greaterthan') then opKey := Ord(tkGt)
    else if CaseEqual(CurTok.SVal, 'greaterthanorequal') then opKey := Ord(tkGe)
    else if CaseEqual(CurTok.SVal, 'lessthan') then opKey := Ord(tkLt)
    else if CaseEqual(CurTok.SVal, 'lessthanorequal') then opKey := Ord(tkLe)
    else if CaseEqual(CurTok.SVal, 'in') then opKey := Ord(tkIn)
    { `shr` is here rather than in the token list above because THE LEXER DOES
      NOT GIVE IT A TOKEN: `shl` lexes as tkShl (lexer.inc:327) and Pascal `shr`
      lexes as a plain tkIdent whose text is 'shr' -- ParseTerm spells the pair
      `(CurTok.Kind in [... tkShl]) or ((CurTok.Kind = tkIdent) and
      (CurTok.SVal = 'shr'))` at every one of its three sites for exactly that
      reason. That is a LEXING asymmetry and it survives; what does not is the
      operator id it used to leak into the AST. ParseTerm now renames it once,
      on the way in, so `ASTIVal[node]` carries Ord(tkShrLogical) — and this
      OVERLOAD KEY has to be the same value, because it is what FindOpOverload2
      is queried with when the use site's AN_BINOP is matched. The two must move
      together; test/test_operator_unary_and_keyword_forms.pas covers the pair and
      is what notices if they do not.
      bug-a-shr-reaches-the-ir-spelled-as-tkident }
    else if CaseEqual(CurTok.SVal, 'shr') then opKey := Ord(tkShrLogical)
    else if CaseEqual(CurTok.SVal, 'rightshift') then opKey := Ord(tkShrLogical);
  end;
  if opKey < 0 then
    Error('expected operator symbol after operator keyword');
  { Stay on operator token — do NOT call Next. TokPos → '(' }

  { Lookahead: the operand type name after EACH ':' at paren depth 1 — the
    first names the LEFT operand, the last the RIGHT one. `(a, b: T)` has one
    colon and both operands are T; `(a: Double; b: TCx)` has two and they
    differ, which is the whole point of the second key.

    The name comes from the token's own SOURCE TEXT, for every kind. This used
    to map four builtin type TOKENS back to names by hand (Integer/Boolean/
    Char/String), so `operator + (a: Double; b: TCx)` died at `operator: cannot
    determine operand type` — Double, Real, Single, Extended and LongWord are
    type KEYWORDS in this lexer and none of them was in the list. The resolution
    below already handles those names; only the token-to-name step was missing,
    and a hand-maintained list of which tokens have names is a list that will be
    short again the next time a type name becomes a keyword.
    feature-a-operator-table-keyed-on-both-operands }
  typeName := '';
  rightName := '';
  depth := 0;
  i := TokPos; { Tokens[TokPos] = '(' }
  while i < TokCount do
  begin
    if Tokens[i].Kind = tkLParen then Inc(depth)
    else if Tokens[i].Kind = tkRParen then
    begin
      Dec(depth);
      if depth = 0 then i := TokCount;   { end of the parameter list }
    end
    else if (Tokens[i].Kind = tkColon) and (depth = 1) then
    begin
      Inc(i);
      if (i < TokCount) and (Tokens[i].SLen > 0) then
      begin
        rightName := GetTokenStrFromRaw(Tokens[i].SOffset, Tokens[i].SLen);
        if typeName = '' then typeName := rightName;
      end;
    end;
    Inc(i);
  end;
  if typeName = '' then Error('operator: cannot determine operand type');
  if rightName = '' then rightName := typeName;

  OperandTypeKindRec(typeName, opTypeKind, recId);
  { `String` registers under BOTH the managed and frozen kinds — a string
    expression types as either depending on origin. }
  scalarTk2 := tyUnknown;
  if (recId = REC_NONE) and
     (CaseEqual(typeName, 'string') or CaseEqual(typeName, 'ansistring')) then
    scalarTk2 := tyString;

  { Determine function vs procedure: find matching ')' then check for ':' }
  depth := 0;
  i := TokPos;
  foundClose := False;
  while (i < TokCount) and not foundClose do
  begin
    if Tokens[i].Kind = tkLParen then Inc(depth)
    else if Tokens[i].Kind = tkRParen then
    begin
      Dec(depth);
      if depth = 0 then begin Inc(i); foundClose := True; end;
    end;
    if not foundClose then Inc(i);
  end;
  isFunc := (i < TokCount) and (Tokens[i].Kind = tkColon);

  { FPC named-result form: `operator + (a, b: T) z: T;` — the ident between ')'
    and ':' names the result variable. Excise it from the token stream (leaving
    the plain `): T` form) and bind it as an alias of Result for the body via
    OpResultAlias (consumed in FindSym). An alias — not a copy-out epilogue —
    so an early Exit still returns the value assigned so far. }
  OpResultAlias := '';
  if (not isFunc) and (i + 1 < TokCount) and (Tokens[i].Kind = tkIdent) and
     (Tokens[i + 1].Kind = tkColon) then
  begin
    OpResultAlias := GetTokenStrFromRaw(Tokens[i].SOffset, Tokens[i].SLen);
    for j := i to TokCount - 2 do
    begin
      Tokens[j].Kind := Tokens[j + 1].Kind;
      Tokens[j].IVal := Tokens[j + 1].IVal;
      Tokens[j].Line := Tokens[j + 1].Line;
      Tokens[j].SOffset := Tokens[j + 1].SOffset;
      Tokens[j].SLen := Tokens[j + 1].SLen;
    end;
    Dec(TokCount);
    { the file map is keyed on absolute token indices — move it with the tokens
      (bug-a-a-diagnostic-in-a-used-unit-names-the-wrong-source-file) }
    AdjustSrcRanges(i, -1);
    isFunc := True;
  end;

  { Synthesize unique proc name __op__NN }
  synName := '__op__';
  AppendChar(synName, Chr(Ord('0') + OvrlCount div 10));
  AppendChar(synName, Chr(Ord('0') + OvrlCount mod 10));

  { Insert 'function/procedure synName' at TokPos (before '(') }
  EnsureTokCapacity(TokCount + 3);
  for j := TokCount - 1 downto TokPos do
  begin
    Tokens[j + 2].Kind := Tokens[j].Kind;
    Tokens[j + 2].IVal := Tokens[j].IVal;
    Tokens[j + 2].Line := Tokens[j].Line;
    Tokens[j + 2].SOffset := Tokens[j].SOffset;
    Tokens[j + 2].SLen := Tokens[j].SLen;
  end;
  Inc(TokCount, 2);
  AdjustSrcRanges(TokPos, 2);   { …and the same for the insert }
  { No AdjustPass2Spans, for the reason spelled out at the splice in
    pasparser_generic.inc: ParseOperatorDef is reached only from ParseProgram
    and ParseUnit — an operator DEFINITION, never a body — so Pass2Active cannot
    be true here. Verified by instrumentation, not only by reading.
    bug-a-the-specialization-splice-does-not-adjust-the-body-pass-spans }

  if isFunc then Tokens[TokPos].Kind := tkFunction
  else Tokens[TokPos].Kind := tkProcedure;
  Tokens[TokPos].IVal := 0; Tokens[TokPos].Line := 0;
  Tokens[TokPos].SOffset := 0; Tokens[TokPos].SLen := 0;

  nameOff := TokCharLen;
  nameLen := Length(synName);
  if TokCharLen + nameLen > STRING_CAP then Error('token char pool overflow');
  for j := 1 to nameLen do
  begin
    TokChars[TokCharLen] := synName[j];
    Inc(TokCharLen);
  end;
  Tokens[TokPos+1].Kind := tkIdent;
  Tokens[TokPos+1].IVal := 0; Tokens[TokPos+1].Line := 0;
  Tokens[TokPos+1].SOffset := nameOff;
  Tokens[TokPos+1].SLen := nameLen;

  { A `class operator TRec.<op>` BODY IS A STATIC METHOD OF TRec, and until now
    it was parsed as a bare global `function __op__NN`. So the body could not
    see the record's own `class var`s, class consts or nested types without a
    qualifier -- `Inc(InitializeCount)` inside `class operator TFoo.Initialize`
    was `undefined variable (InitializeCount)` while the identical line inside
    `procedure TFoo.Bump` and inside `class procedure TFoo.CBump` both resolved.
    ONE ARM OF A THREE-WAY CASE, and the two that worked are what made this read
    as a management-operator gap rather than a scope one (fpc testsuite
    tmoperator7). devdocs/dev/normalise-dont-special-case.md

    CurMethClass is the whole mechanism: FindVarSym falls back to FindClassVar on
    it, and the class-const, property and nested-type lookups key on it too. It
    is exactly what ParseProcDecl sets for a method impl.

    CurSelfClass is deliberately NOT set. A class operator is STATIC -- there is
    no instance and no Self -- and ParseProcDecl draws the same line one line
    apart: `if not UMthIsStatic[mmi] then CurSelfClass := ...` and then
    CurMethClass unconditionally. Setting Self here would make a bare FIELD name
    resolve in a body that has no object to read it from.

    ParseProcDecl clears CurMethClass on its way out, so the restore below is
    what a nested operator definition would need; ParseOperatorDef is top-level
    only today, and the save/restore costs nothing and stops that being a fact
    the next caller has to rediscover. }
  savedCMC := CurMethClass;
  savedMIOp := MethImplOwnerCi;
  if qualRec <> REC_NONE then CurMethClass := qualRec;
  { ...and MethImplOwnerCi, because NESTED TYPES key on that one and not on
    CurMethClass. `var n: TAlias` in the operator body, where TAlias is declared
    inside TFoo, is resolved by ParseTypeKind through FindNestedType against
    MethImplOwnerCi -- so setting only the class-var/class-const scope left
    `unknown type: TAlias` behind. TWO variables carry "which type is this body
    a member of", and a fix that sets one of them looks complete right up to the
    first declaration that reads the other. ParseProcDecl saves and restores
    MethImplOwnerCi itself, so this value holds for exactly the body. }
  if qualRec >= REC_UCLASS_BASE then MethImplOwnerCi := qualRec - REC_UCLASS_BASE;

  { Advance into the injected 'function/procedure' token }
  Next;
  ParseSubroutine;
  CurMethClass := savedCMC;
  MethImplOwnerCi := savedMIOp;
  OpResultAlias := '';

  { After ParseSubroutine, the proc is registered — look it up by synName }
  procIdx := FindProc(synName);
  if procIdx < 0 then Error('operator: internal error, proc not found after parse');
  { The SECOND key, resolved now that the arity is known. A unary or conversion
    operator has no right operand and stores none — it is looked up by the
    single-key FindOpOverload, which does not read these columns. }
  rightTk := Ord(tyUnknown);
  rightRec := REC_NONE;
  if Procs[procIdx].ParamCount = 2 then
    OperandTypeKindRec(rightName, rightTk, rightRec);
  { Arity: conversion/unary named operators take exactly ONE parameter —
    FPC rejects `operator :=(S1, S2: String)` (tassignmentoperator1 %fail). }
  { Copy/AddRef are recognised so the spelling is not a syntax error, but they
    fire on a value COPY, which nothing dispatches yet — accepting one silently
    would give a record whose invariant simply never runs, which is worse than
    not compiling. Refuse loudly and name the ticket instead.
    feature-pascal-class-management-operators }
  if (opKey = OPK_ADDREF) or (opKey = OPK_COPY) then
    Error('operator Copy/AddRef is recognised but not dispatched yet — the copy '
          + 'lifetime event is a separate slice '
          + '(feature-pascal-management-operators-copy-and-addref)');
  if (opKey = OPK_INITIALIZE) or (opKey = OPK_FINALIZE) then
  begin
    { `class operator Initialize(var a: TFoo)` — exactly one VAR parameter of
      the record type, and no result. FPC's own shape. }
    if Procs[procIdx].ParamCount <> 1 then
      Error('a management operator must take exactly one parameter');
    if Procs[procIdx].IsFunc then
      Error('a management operator must be a procedure (no result)');
    if recId = REC_NONE then
      Error('a management operator needs a record or class operand type');
    if not Procs[procIdx].Params[0].IsRef then
      Error('a management operator takes its operand as a var parameter');
  end
  else if (opKey = Ord(tkAssign)) or (opKey = OPK_EXPLICIT) or (opKey = OPK_INC) or
     (opKey = OPK_DEC) or (opKey = OPK_ENUMERATOR) then
  begin
    if Procs[procIdx].ParamCount <> 1 then
      Error('this operator must take exactly one parameter');
    { FPC forbids an EXPLICIT conversion operator between two BUILT-IN ordinal
      types (toperator90's `operator Explicit (LongInt): Boolean` %fail): a
      standard conversion already exists, and a cast has to mean the standard
      one. A string/record/class/float on either side makes it a legal user
      conversion (tgenfunc8's LongInt <-> String).

      THE IMPLICIT FORM IS ALLOWED and used to be refused here beside it,
      because `Implicit` and `:=` share OPK with nothing separating them. The
      corpus states the rule as a PAIR and states it explicitly: toperator89 is
      `operator := (aArg: LongInt): Boolean` carrying `{ %NORUN }` and the
      comment "overloading the implicit assignment is allowed", toperator90 is
      the same conversion spelled `Explicit` carrying `{ %FAIL }` and the
      comment "overloading the explicit assignment is NOT allowed". Same
      operand types, same result type, opposite answers, differing only in the
      key -- which is as clean a discriminator as this corpus offers, and it is
      why this is not a widening judged by taste.
      Nothing else in the %FAIL population depends on the `:=` half: the other
      three refusable `operator :=` rows are tassignmentoperator1 (two
      parameters -- the arity branch above) and toperator92/95 (two conversions
      to the same result type -- the duplicate check below), and String is not
      ordinal in any case. }
    if (opKey = OPK_EXPLICIT) and
       (recId = REC_NONE) and TypeIsOrdinal(IntToTypeKind(opTypeKind)) and
       TypeIsOrdinal(Procs[procIdx].RetType) then
      Error('impossible operator overload: a standard conversion between these types exists');
  end
  else if ((opKey = Ord(tkMinus)) or (opKey = Ord(tkNot)) or (opKey = Ord(tkPlus))) and
          (Procs[procIdx].ParamCount = 1) then
  begin
    { The UNARY overload of a symbol that is also binary. `-` carries both in
      FPC and in real code -- constexp.pas declares the pair on Tconstexprint --
      so the arity is what tells them apart, here and in FindOpOverloadUnary.
      `not` is unary only, and rides the same branch rather than getting one of
      its own.

      Unary `+` is here too, since 2026-09-05. It was excluded because
      ParseSimpleExpr ate a leading plus as an identity before any node existed
      -- and the note said that if a corpus ever needed it, that was a ticket
      rather than a line here. The corpus needs it: terecs6 and terecs14 both
      declare `class operator Positive`, and terecs6 asserts the CALL happens
      (its body returns a.F+1, so identity gives the wrong VALUE rather than a
      diagnostic). ParseSimpleExpr now remembers the plus and dispatches on the
      parsed operand; nothing else moved.

      Same operand rule as the binary branch: the operation must not already be
      predefined, i.e. the operand has to be an aggregate. }
    if recId = REC_NONE then
      Error('impossible operator overload: this operation is predefined for built-in operand types');
    if not Procs[procIdx].IsFunc then
      Error('a unary operator must be a function (it has a result)');
  end
  else
  begin
    if Procs[procIdx].ParamCount <> 2 then
      Error('binary operator must take exactly two parameters');
    { FPC forbids overloading a BINARY symbol operator when the operation is
      predefined for the operand types — at least one operand must be a
      record/class (toperator13..68 %fails: +,-,<,= on LongInt/AnsiString).

      EITHER operand, which is what FPC means and what this checked wrongly:
      it read the LEFT operand only, so `operator * (a: Integer; b: TCx)` — a
      scalar on the left, the record on the right — was refused as if it were
      Integer*Integer. Widening the check alone would have been WORSE than the
      refusal: the table is keyed on the left operand, so the entry lands under
      (tkStar, tyInteger, REC_NONE) and a plain `3 * 5` would find it. What
      makes it safe is the use sites, which now consult the table only when one
      of the operands actually IS an aggregate, and take no fallback when the
      left one is not. See decide-operator-table-keyed-on-one-operand-or-two.
      feature-a-operator-table-keyed-on-both-operands }
    if (recId = REC_NONE) and (not TkIsRecordOrClass(rightTk)) then
      Error('impossible operator overload: this operation is predefined for built-in operand types');
  end;
  { FPC-parity rejections (bug-pascal-missing-diagnostics-fail-tests): }
  { = / <> are predefined for CLASS operands (reference equality) and cannot
    be overloaded (toperator71). The PXX dialect deliberately allows it (value
    equality on classes, test_op_overload.pas), so the rejection is strict-only.
    Other operators on records/classes are the normal overload surface and stay. }
  if StrictOperator and (opTypeKind = Ord(tyClass)) and
     ((opKey = Ord(tkEq)) or (opKey = Ord(tkNeq))) then
    Error('impossible operator overload: = and <> are predefined for class types (reference equality)');
  { A SECOND := / Implicit / Explicit from the same source type to the same
    RESULT type is ambiguous at every use site — String[80] vs String[90]
    targets are indistinguishable (toperator92; toperator95 splits the same
    pair across a class operator and a global one). Distinct results remain
    legal.

    "The same result type" used to mean the same type KIND, which made two
    conversions to two different RECORDS a duplicate — `operator :=(Integer):
    TA` and `operator :=(Integer): TB` are both `tyRecord`. FPC takes that pair,
    and so does the lookup now that it keys on the destination's record id, so
    the check asks the lookup rather than re-deciding what "same" means.

    maxRank 0: only an EXACT source-kind clash is a duplicate. QWord and Int64
    to one destination are two conversions, not one written twice — that is the
    pair FPC's own constexp.pas declares. }
  if (opKey = Ord(tkAssign)) or (opKey = OPK_EXPLICIT) then
  begin
    dupPi := FindOpConvRanked(opKey, opTypeKind, recId,
                              Ord(Procs[procIdx].RetType), ProcRetRecId[procIdx], 0);
    if dupPi >= 0 then
      Error('duplicate conversion operator: this source type already converts to this result type');
  end;
  { `class operator TFoo.GreaterThan(i, j: TBar): Boolean` -- a qualified
    operator none of whose types is the type it is qualified with. terecs7's
    %fail, and FPC states the rule in its own message, which is where this
    wording comes from rather than from a guess:
      "Either the result or at least one parameter must be of type TFoo"
    THE RESULT COUNTS, and that half is not decoration: a conversion INTO the
    record -- `class operator TFoo.Implicit(a: Integer): TFoo` -- has no operand
    of TFoo at all and is legal, verified against fpc 3.2.2 before this check
    was written. Testing the operands alone would have refused it.

    Only when the qualifier RESOLVES to a record: an unresolvable qualifier
    would otherwise answer REC_NONE and make every operator under it illegal. }
  if qualName <> '' then
  begin
    { qualTk/qualRec were resolved at the header -- see the note there. }
    if (qualRec <> REC_NONE) and (recId <> qualRec) and (rightRec <> qualRec) and
       (ProcRetRecId[procIdx] <> qualRec) then
      Error('either the result or at least one parameter must be of type '
            + qualName);
  end;
  RegisterOpOverload(opKey, opTypeKind, recId, rightTk, rightRec, procIdx);
  if scalarTk2 <> tyUnknown then
    RegisterOpOverload(opKey, Ord(scalarTk2), REC_NONE, rightTk, rightRec, procIdx);
end;

{ Linear (row-major) index of an N-D fixed array element, built from AST nodes so
  it feeds the ordinary 1-D AN_INDEX (no codegen change). Reads the dims from
  NDInfoLo/Span and the parsed index exprs from NDIdxNode; nd dimensions.
  Horner form: acc = (i0-lo0); acc = acc*span_d + (i_d - lo_d) for d = 1..nd-1. }
function NDChkIdx(idxNode: Integer; lo, hi: Int64): Integer;
{ {$R+}: wrap ONE N-D subscript in PXXRangeChkI64(i, lo, hi) — the flattened
  Horner index reaches IR as a single expression, so per-dimension bounds can
  only be applied here at composition time (statement-anchored, like every
  other {$R+} site). Passthrough when checks are off / builtinheap absent
  (feature-range-checks-nd-bases). }
var pi, a1, a2, a3, litN: Integer;
begin
  Result := idxNode;
  if not StmtRChecks then Exit;
  pi := FindProc('PXXRangeChkI64');
  if pi < 0 then Exit;
  a1 := AllocNode(AN_ARG); ASTLeft[a1] := idxNode; ASTTk[a1] := Ord(tyInt64);
  litN := AllocNode(AN_INT_LIT); ASTIVal[litN] := lo; ASTTk[litN] := Ord(tyInt64);
  a2 := AllocNode(AN_ARG); ASTLeft[a2] := litN; ASTTk[a2] := Ord(tyInt64);
  ASTRight[a1] := a2;
  litN := AllocNode(AN_INT_LIT); ASTIVal[litN] := hi; ASTTk[litN] := Ord(tyInt64);
  a3 := AllocNode(AN_ARG); ASTLeft[a3] := litN; ASTTk[a3] := Ord(tyInt64);
  ASTRight[a2] := a3;
  Result := AllocNode(AN_CALL); ASTIVal[Result] := pi;
  ASTLeft[Result] := a1; ASTRight[Result] := -1; ASTTk[Result] := Ord(tyInt64);
end;

function BuildFlatNDIndex(nd: Integer): Integer;
var d, loLit, spanLit, diff, scaled, acc: Integer;
begin
  loLit := AllocNode(AN_INT_LIT); ASTIVal[loLit] := NDInfoLo[0]; ASTTk[loLit] := Ord(tyInteger);
  acc := AllocNode(AN_BINOP); ASTIVal[acc] := Ord(tkMinus);
  ASTLeft[acc] := NDChkIdx(NDIdxNode[0], NDInfoLo[0],
                           NDInfoLo[0] + NDInfoSpan[0] - 1);
  ASTRight[acc] := loLit; ASTTk[acc] := Ord(tyInteger);
  for d := 1 to nd - 1 do
  begin
    spanLit := AllocNode(AN_INT_LIT); ASTIVal[spanLit] := NDInfoSpan[d]; ASTTk[spanLit] := Ord(tyInteger);
    scaled := AllocNode(AN_BINOP); ASTIVal[scaled] := Ord(tkStar);   { acc * span_d }
    ASTLeft[scaled] := acc; ASTRight[scaled] := spanLit; ASTTk[scaled] := Ord(tyInteger);
    loLit := AllocNode(AN_INT_LIT); ASTIVal[loLit] := NDInfoLo[d]; ASTTk[loLit] := Ord(tyInteger);
    diff := AllocNode(AN_BINOP); ASTIVal[diff] := Ord(tkMinus);    { i_d - lo_d }
    ASTLeft[diff] := NDChkIdx(NDIdxNode[d], NDInfoLo[d],
                              NDInfoLo[d] + NDInfoSpan[d] - 1);
    ASTRight[diff] := loLit; ASTTk[diff] := Ord(tyInteger);
    acc := AllocNode(AN_BINOP); ASTIVal[acc] := Ord(tkPlus);       { scaled + diff }
    ASTLeft[acc] := scaled; ASTRight[acc] := diff; ASTTk[acc] := Ord(tyInteger);
  end;
  Result := acc;
end;

{ A single leading subscript on an >=2-D fixed array selects a whole sub-array
  (row): `m[i]` of `array[a..b, c..d] of T` is the row `array[c..d] of T` at
  byte offset (i-lo0)*span1*..*span_{nd-1} elements. Build that flat element
  index so the ordinary element-stride AN_INDEX lands on the row's first
  element; its address is then the row base (what a `var`/`const` array param or
  whole-row reference needs). NDInfo* must be filled (NodeArrNDInfo). }
function BuildPartialNDIndex(indexNode: Integer; k: Integer): Integer;
var d, trailing, spanLit, acc, flat: Integer;
begin
  flat := BuildFlatNDIndex(k);
  trailing := 1;
  for d := k to NDInfoNDims - 1 do trailing := trailing * NDInfoSpan[d];
  acc := flat;
  if trailing <> 1 then
  begin
    spanLit := AllocNode(AN_INT_LIT); ASTIVal[spanLit] := trailing; ASTTk[spanLit] := Ord(tyInteger);
    acc := AllocNode(AN_BINOP); ASTIVal[acc] := Ord(tkStar);
    ASTLeft[acc] := flat; ASTRight[acc] := spanLit; ASTTk[acc] := Ord(tyInteger);
  end;
  ASTRight[indexNode] := acc;
  { The stamp and the index arithmetic are set TOGETHER, by one routine that
    takes the index node, because they are one fact stated twice and every call
    site is another chance to state only half of it. The row builder used to
    return the arithmetic and let each caller assign it; a caller that then
    forgot the stamp would build a sub-array that every consumer reads as an
    element -- silently, which is precisely what this column exists to end. }
  ASTNDRowSubs[indexNode] := k;
  Result := acc;
end;

procedure BuildPartialNDRowIndex(indexNode: Integer; rowIdxNode: Integer);
begin
  NDIdxNode[0] := rowIdxNode;
  BuildPartialNDIndex(indexNode, 1);
end;

{ If `node` is an N-D fixed array reference (a SymArrNDims ident, an
  UFldArrNDims record field, or a DEREF of a pointer to one), fill NDInfo* and
  return True. Lets m[..], r.m[..] and p^[..] share one path.

  The deref arm reads the pointee's shape off the POINTER symbol, where
  SymPtrElemNDims and the SymArrDimLo/Span rows already carry it (a pointer
  symbol has SymArrNDims=0, so those slots are free — the C frontend's
  `elem (*p)[A][B]` has stored them there all along). Without it a deref base
  answered False, the comma chain fell through to the jagged/dynamic sugar, and
  `qg^[i, j]` over `^array[0..1, 0..2]` indexed the FLAT extent as if it were
  one dimension: `0 1 2 1 2 10` where FPC prints `0 1 2 10 11 12`. Silent, exit
  0, and reading three elements past the row it was asked for.
  bug-p-a-pointer-to-a-multidim-array-indexes-and-measures-the-flat-extent }
function NodeArrNDInfo(node: Integer): Boolean;
var baseRec, fIdx, sym, d, base: Integer; fname: AnsiString;
begin
  Result := False;
  { Widened past the plain-identifier base 2026-09-01: the arm below read the
    pointer SYMBOL and a field / call result / array element / nested deref has
    none, so `r.q^[i, j]` over a `^array[0..1, 0..1]` answered False here and
    fell through to the jagged comma sugar -- element [0,0] right, every other
    element written at the flat offset. DerefPtrArrayNDInfo asks the symbol
    first and the pointee's ArrType row second, so the identifier spelling
    takes byte-for-byte the path it did.
    bug-a-p-caret-index-is-only-correct-when-the-pointer-is-a-plain-identifier }
  if DerefPtrArrayNDInfo(node) then
    Result := True
  else if (ASTKind[node] = AN_IDENT) and (ASTIVal[node] >= 0) and (SymArrNDims[ASTIVal[node]] >= 2) then
  begin
    sym := ASTIVal[node];
    NDInfoNDims := SymArrNDims[sym];
    base := sym * MAX_ARR_DIMS;
    for d := 0 to NDInfoNDims - 1 do
    begin NDInfoLo[d] := SymArrDimLo[base + d]; NDInfoSpan[d] := SymArrDimSpan[base + d]; end;
    Result := True;
  end
  else if ASTKind[node] = AN_FIELD then
  begin
    baseRec := ResolveNodeRec(ASTLeft[node]);
    if baseRec >= REC_UCLASS_BASE then
    begin
      fname := GetASTIdentName(node);
      fIdx := FindUField(baseRec - REC_UCLASS_BASE, fname);
      if (fIdx >= 0) and (UFldArrNDims[fIdx] >= 2) then
      begin
        NDInfoNDims := UFldArrNDims[fIdx];
        base := fIdx * MAX_ARR_DIMS;
        for d := 0 to NDInfoNDims - 1 do
        begin NDInfoLo[d] := UFldArrDimLo[base + d]; NDInfoSpan[d] := UFldArrDimSpan[base + d]; end;
        Result := True;
      end;
    end;
  end;
end;
{ A PARTIAL fixed N-D subscript -- `pa[0]` on `array[0..2] of TG`, `r2.rows[0]`,
  `p^[0]` -- names a whole SUB-ARRAY. Answer True and describe it as a 1-D
  array: how many elements it holds, and of what.

  This is the reader ASTNDRowSubs exists for. The AN_INDEX node's own ASTTk
  holds the ELEMENT's kind (there is nowhere else on an index node to put it),
  so every consumer that dispatches on the tag reads `pa[0]` as one Int64 --
  the same lie AN_DEREF tells for `p^` over a pointer-to-array, one node kind
  out, and the reason IsNodeArray needed its DerefPtrArrayInfo arm.

  Shape re-derived from the BASE through NodeArrNDInfo rather than copied onto
  the index node at parse time: the base is one field away and the array's own
  dim columns are the single source. Only dims 1..n-1 are read here because
  only one leading subscript can be spelled today; when a k-subscript partial
  index is accepted (the 3-D `b[0][0]` arm of the same ticket), the row is dims
  k..n-1 and the count is the product over that range -- k is what
  ASTNDRowSubs stores so that generalisation is a loop bound, not a new column.
  bug-a-2d-array-row-as-a-const-array-param-still-segfaults }
function NDRowSourceInfo(node: Integer; var rowCount: Integer;
                         var rowElemTk: TTypeKind; var rowElemRec: Integer): Boolean;
var nrBase, nrSym, d, nrStrCap, nrTk, nrRec: Integer; nrFld: AnsiString;
begin
  Result := False;
  rowCount := 0; rowElemTk := tyUnknown; rowElemRec := REC_NONE;
  if node < 0 then Exit;
  if ASTKind[node] <> AN_INDEX then Exit;
  if ASTNDRowSubs[node] <= 0 then Exit;
  nrBase := ASTLeft[node];
  if nrBase < 0 then Exit;
  if not NodeArrNDInfo(nrBase) then Exit;
  if ASTNDRowSubs[node] >= NDInfoNDims then Exit;
  rowCount := 1;
  for d := ASTNDRowSubs[node] to NDInfoNDims - 1 do rowCount := rowCount * NDInfoSpan[d];
  if rowCount <= 0 then begin rowCount := 0; Exit; end;
  if ASTKind[nrBase] = AN_IDENT then
  begin
    nrSym := ASTIVal[nrBase];
    if (nrSym < 0) or (nrSym >= SymCount) then begin rowCount := 0; Exit; end;
    rowElemTk := Syms[nrSym].ElemType;
    rowElemRec := Syms[nrSym].ElemRecName;
  end
  else if ASTKind[nrBase] = AN_FIELD then
  begin
    nrFld := GetASTIdentName(nrBase);
    nrRec := ResolveNodeRec(ASTLeft[nrBase]);
    rowElemTk := RecFieldType(nrRec, nrFld);
    rowElemRec := RecFieldRecId(nrRec, nrFld);
  end
  else if ASTKind[nrBase] = AN_DEREF then
  begin
    if not DerefPtrArrayElem(nrBase, nrTk, nrRec, nrStrCap) then
      begin rowCount := 0; Exit; end;
    rowElemTk := IntToTypeKind(nrTk);
    rowElemRec := nrRec;
  end
  else
    begin rowCount := 0; Exit; end;
  Result := True;
end;


{ ---- The ONE read-or-write decision for a property access ------------------
  A property access chooses its READ or its WRITE accessor by looking for `:=`,
  and for an INDEXED property that `:=` sits after the whole subscript group,
  not after the name. Seven sites in pasparser_lval.inc make that choice --
  bare name in a method, `Self.P`, `c.P`, `TCls.P`, with-scope, the selector
  walker, the default property -- and the three-line balanced scan had been
  copy-pasted to four of them. Nothing at any site said which kind it was, and
  the difference was invisible until an indexed property reached one of the
  other three: measured 2026-09-05, ONE declaration
  (`property A[i: LongInt]: LongInt read FR write FW`, distinct backing fields)
  gave THREE answers across four receiver spellings -- `c.A[2]` and `Self.A[1]`
  stored through FW, a bare `A[1]` was refused outright, and
  `with c do A[3] := 9` stored through **FR**, silently, with the read-back
  agreeing because the read went to the same wrong place.

  `afterNameTok` is the index in Tokens[] of the first token AFTER the property
  name, because the callers do not agree on whether the name is consumed: the
  arms reached from ParseLValueAST's entry have it consumed already (CurTok is
  the `[` or the `:=`, so pass `TokPos - 1`), while the selector walker still
  has CurTok on the name (pass `TokPos`). That disagreement is exactly why two
  of the copied scans started at TokPos and two at TokPos - 1, and why the
  parameter is spelled out rather than derived here.

  The bracket test is on the TOKEN and not on UPropIsIndexed: a FIELD-backed
  property whose field is an array carries a subscript group too, and pxx
  accepts that spelling (FPC does not, so there is no oracle for it -- but
  answering differently in four places is an internal inconsistency, which is a
  defect under any policy). One group only, deliberately: `P[i][j] := v`
  indexes the property's RESULT, which is not a write to the property, and all
  four proven copies stopped at the first group. }
function PropAccessIsWrite(afterNameTok: Integer): Boolean;
var i, w: Integer;
begin
  Result := False;
  if afterNameTok >= TokCount then Exit;
  if Tokens[afterNameTok].Kind = tkAssign then
  begin
    Result := True;
    Exit;
  end;
  if Tokens[afterNameTok].Kind <> tkLBrack then Exit;
  i := afterNameTok; w := 0;
  while i < TokCount do
  begin
    if Tokens[i].Kind = tkLBrack then Inc(w)
    else if Tokens[i].Kind = tkRBrack then
    begin
      Dec(w);
      if w = 0 then begin Inc(i); Break; end;
    end;
    Inc(i);
  end;
  Result := (i < TokCount) and (Tokens[i].Kind = tkAssign);
end;

{ Parse an indexed-property subscript `[e1 {, e2}]` (bracket not yet consumed)
  into a chain of AN_ARG nodes. head = first arg, tail = last (so a setter's value
  arg can be spliced after). Supports multi-index `obj.Cells[a, b]` / `obj[a, b]`. }
{ The `index N` constant of a property, as the accessor's first argument. Does nothing for a
  property without one, so it is safe to call unconditionally beside ParsePropIndexArgs. }
procedure PropIndexConstArg(pri: Integer; var head, tail: Integer);
var n: Integer;
begin
  if (pri < 0) or (not UPropHasIndex[pri]) then Exit;
  n := AllocNode(AN_INT_LIT);
  ASTIVal[n] := UPropIndexVal[pri];
  ASTTk[n] := Ord(tyInteger);
  head := AllocNode(AN_ARG);
  ASTLeft[head] := n;
  tail := head;
end;

procedure ParsePropIndexArgs(var head, tail: Integer);
var n: Integer;
begin
  Expect(tkLBrack, '[');
  ParseExpr;
  head := AllocNode(AN_ARG); ASTLeft[head] := CurASTNode; tail := head;
  while CurTok.Kind = tkComma do
  begin
    Next;
    ParseExpr;
    n := AllocNode(AN_ARG); ASTLeft[n] := CurASTNode;
    ASTRight[tail] := n; tail := n;
  end;
  Expect(tkRBrack, ']');
end;

{ ---- One place that knows how a property ACCESSOR is dispatched ------------
  Eleven sites built this by hand -- every default-property arm, both
  Self-relative arms, the qualified `o.Prop`, the grouped `(expr).Prop` in
  pasparser_expr.inc -- and all eleven spelled the SAME two-way choice:
  AN_VIRTUAL_CALL when the accessor has a vtable slot, AN_CALL when it does
  not. The choice is THREE-way. An interface receiver dispatches through the
  IMT (AN_INTF_CALL), takes Self from the fat pointer instead of argument 0,
  and carries its slot in ASTSOffset rather than ASTRight. None of the eleven
  copies knew that, so a property declared in an interface read a class VMT off
  a fat pointer -- the ordinary method call `i.M(...)` had the arm (see the
  AN_INTF_CALL site in ParseClassRecordSelectors) and the property path, being
  a separate copy, did not.

  recvNode = the receiver (instance or interface value). firstArg = the head of
  the caller's already-built AN_ARG chain of REAL arguments -- index args, then
  a setter's value -- or -1. Self is deliberately NOT in that chain: where Self
  goes is exactly the difference between the three shapes, and is this
  function's job rather than each caller's. }
function MakeAccessorCall(mci, mmi, mpi, recvNode, firstArg: Integer): Integer;
var callN, selfArg: Integer;
begin
  if (mci >= 0) and UClsIsInterface[mci] then
  begin
    callN := AllocNode(AN_INTF_CALL);
    ASTRight[callN] := recvNode;              { the interface value }
    ASTSOffset[callN] := UMthVirSlot[mmi];    { IMT slot }
    ASTLeft[callN] := firstArg;               { args, with NO Self at the head }
  end
  else
  begin
    if UMthVirSlot[mmi] >= 0 then
    begin
      callN := AllocNode(AN_VIRTUAL_CALL);
      ASTRight[callN] := UMthVirSlot[mmi];
    end
    else
      callN := AllocNode(AN_CALL);
    selfArg := AllocNode(AN_ARG);
    ASTLeft[selfArg] := recvNode;
    ASTRight[selfArg] := firstArg;
    ASTLeft[callN] := selfArg;                { args, Self first }
  end;
  ASTIVal[callN] := mpi;
  ASTTk[callN] := Ord(Procs[mpi].RetType);
  Result := callN;
end;

{ A SETTER's argument chain: the index args (if any) followed by the value,
  spliced onto the tail that ParsePropIndexArgs / PropIndexConstArg reported.
  Returns the head, for MakeAccessorCall's firstArg. Five of the eleven sites
  spelled this same if/else out. }
function AccessorArgChain(margIdx, mlastArg, valueNode: Integer): Integer;
var vArg: Integer;
begin
  vArg := AllocNode(AN_ARG);
  ASTLeft[vArg] := valueNode;
  if margIdx >= 0 then
  begin
    ASTRight[mlastArg] := vArg;
    Result := margIdx;
  end
  else
    Result := vArg;
end;

{ Append AN_INT_LIT default-value args for method params fromIdx..ParamCount-1
  (a call that omitted trailing defaulted args — mirrors the ctor fill at the
  TFoo.Create arity check). Errors if a remaining param has no default. The
  caller links head into the call node when lastArg starts at -1. }
{ The AST node for parameter k's declared default value. Errors when k has no
  default. Shared by the trailing-arg fill below and the Nil Python
  keyword-argument bind, which needs the same node for a HOLE in the middle. }
function DefaultArgValueNode(mpi, k: Integer): Integer;
var exprNode: Integer;
begin
  if (k >= MAX_PROC_PARAMS) or (not ProcParamHasDefault[mpi * MAX_PROC_PARAMS + k]) then
    Error('not enough arguments to ' + Procs[mpi].Name +
          ' (parameter ' + Procs[mpi].Params[k].Name + ' has no default)');
  { A NON-CONSTANT NilPy default (`b=[]`, `b={}`, `b=w`) was evaluated ONCE into
    a hidden global at the def statement, because that is when Python evaluates
    it — and it is what makes the shared-mutable-default idiom accumulate. The
    omitted argument therefore READS that global; it does not rebuild a value,
    which would give a fresh container per call and diverge on the accumulator
    idiom (bug-nilpy-non-constant-parameter-defaults-silently-become-none). }
  if ProcParamDefaultSym[mpi * MAX_PROC_PARAMS + k] >= 0 then
    exprNode := PyMakeIdent(ProcParamDefaultSym[mpi * MAX_PROC_PARAMS + k])
  else if ProcParamDefaultIsStr[mpi * MAX_PROC_PARAMS + k] then
  begin
    exprNode := AllocNode(AN_STR_LIT);
    ASTSOffset[exprNode] := ProcParamDefaultSOff[mpi * MAX_PROC_PARAMS + k];
    ASTSLen[exprNode] := ProcParamDefaultSLen[mpi * MAX_PROC_PARAMS + k];
    { Tag the literal with the PARAMETER's own string kind. tyString is the
      FROZEN inline-length kind; a parameter declared tyAnsiString is the
      managed refcounted one, and a frozen literal handed to it arrived as the
      EMPTY string. That is why a @dataclass `s: str = "t"` silently defaulted
      to '' while the int/float/bool defaults beside it were all correct —
      which is exactly what made the class look like defaults work.
      bug-nilpy-dataclass-str-field-default-is-dropped }
    if Procs[mpi].Params[k].TypeKind = tyAnsiString then
      ASTTk[exprNode] := Ord(tyAnsiString)
    else
      ASTTk[exprNode] := Ord(tyString);
  end
  else if ProcParamDefaultIsFloat[mpi * MAX_PROC_PARAMS + k] then
  begin
    { the stored ordinal IS the double's IEEE bits — see PyParamDefaultAt }
    exprNode := AllocNode(AN_FLOAT_LIT);
    ASTIVal[exprNode] := ProcParamDefaultVal[mpi * MAX_PROC_PARAMS + k];
    ASTTk[exprNode] := Ord(tyDouble);
  end
  else if ProcParamDefaultIsSet[mpi * MAX_PROC_PARAMS + k] then
  begin
    { a SET default: the value is the Data[] offset of the mask baked at the
      declaration, so the call site just references it }
    exprNode := AllocNode(AN_SET_CONST_REF);
    ASTIVal[exprNode] := ProcParamDefaultVal[mpi * MAX_PROC_PARAMS + k];
    ASTTk[exprNode] := Ord(tySet);
  end
  else if isNilPy and (Procs[mpi].Params[k].TypeKind = tyVariant) and
          (ProcParamDefaultIsNone[mpi * MAX_PROC_PARAMS + k] or
           ((ProcUnitIdx[mpi] >= 0) and
            (not UnitIsPyModule(ProcUnitIdx[mpi])))) then
    { A variant parameter is passed by REFERENCE — the callee reads a 16-byte
      slot through a pointer — so a `= None` default cannot be a bare ordinal:
      the callee dereferences it the moment it touches the parameter.
      `def go(self, x, s=None)` called as `A().go(1)` segfaulted on it.

      A NilPy def's declared value falls through to the ordinal node below and
      is boxed by IRLowerCallArg, exactly as a WRITTEN literal argument is —
      passing None for every default meant `def f(a=1)` called as `f()` ran
      with a=None, silently.

      A LIBRARY routine (ProcUnitIdx >= 0) is the other way round. Its
      `const opt: Variant = 0` spells "not supplied", and every façade in
      lib/pcl tests `pyvartag(v) <> 0` to find out. Boxing the 0 as an INTEGER
      made an omitted option look GIVEN: `canvas.configure(yscrollcommand=...)`
      passed a filled xscrollcommand too, and tkinter refused it — the first
      thing songformatter did at run time. }
    exprNode := PyMakeNone
  else if isNilPy and ProcParamDefaultIsBool[mpi * MAX_PROC_PARAMS + k] and
          (Procs[mpi].Params[k].TypeKind = tyVariant) then
  begin
    { `b=True` into a VARIANT parameter: recorded as the ordinal 1, and boxed as
      an integer the variant prints 1 rather than True. }
    exprNode := AllocNode(AN_BOOL_LIT);
    ASTIVal[exprNode] := ProcParamDefaultVal[mpi * MAX_PROC_PARAMS + k];
    ASTTk[exprNode] := Ord(tyBoolean);
  end
  else
  begin
    exprNode := AllocNode(AN_INT_LIT);
    ASTIVal[exprNode] := ProcParamDefaultVal[mpi * MAX_PROC_PARAMS + k];
    ASTTk[exprNode] := Ord(Procs[mpi].Params[k].TypeKind);
    { A REFERENCE-shaped parameter's only constant default is `nil`, and the
      node has to be the one a WRITTEN nil argument builds -- INT_LIT 0 tagged
      tyPointer -- not the literal 0 wearing the parameter's own kind. Tagged
      tyRecord (a method pointer, an interface) or tyClass, IRLowerCallArg read
      it as an aggregate and dereferenced address 0: `TakeDef;` on `procedure
      TakeDef(e: TEv = nil)` segfaulted while `TakeDef(nil)` two lines up was
      fine. Same shape as the tyVariant case below, one type family over.
      bug-a-nil-is-not-accepted-as-a-method-pointer-argument }
    if ProcParamIsNilable(mpi, k) and
       (ProcParamDefaultVal[mpi * MAX_PROC_PARAMS + k] = 0) then
      ASTTk[exprNode] := Ord(tyPointer);
    { A VARIANT parameter takes the literal as an INTEGER, so IRLowerCallArg
      boxes it into a variant temp and passes the temp's address. Tagged with
      the parameter's own type it looked like a variant already, the boxing was
      skipped, and the callee dereferenced a bare ordinal — `def g(self, x,
      s=5)` called as `A().g(1)` segfaulted. }
    if Procs[mpi].Params[k].TypeKind = tyVariant then
      ASTTk[exprNode] := Ord(tyInteger);
  end;
  DefaultArgValueNode := exprNode;
end;

{ THE ONE MOMENT THE COMPILER HAS TO KNOW A FILE'S ELEMENT WIDTH.
  `file of T` resolves to one shared RTL record (FileRec), so the width is not
  in the type — it rides on the SYMBOL (SymFileRecSize, stamped by Alloc* from
  the LastTypeFileRecSize channel). Every later operation reads it back out of
  the record, which means exactly one call has to carry it in, and Assign is
  that call because Pascal guarantees it runs first.

  Keyed on the PARAMETER NAME rather than on the routine's, so the mechanism is
  declared where it is used: any RTL routine that wants the width writes
  `__recsize: Integer = 128` as its trailing parameter and gets it. Keying on
  `Assign` would have put the knowledge in the compiler and left the RTL's
  signature looking like an ordinary defaulted argument.

  Silent when the first argument is not a file variable — a hand-written third
  argument never reaches here (nothing is being defaulted), and a FileRec that
  was declared through something Alloc* did not stamp keeps the declared 128
  rather than a zero. feature-pascal-typed-and-untyped-files }
function FileRecSizeArgOverride(mpi, k, firstArg: Integer): Integer;
var fsym: Integer;
begin
  Result := 0;
  if (k >= MAX_PROC_PARAMS) or (not CaseEqual(Procs[mpi].Params[k].Name, '__recsize')) then Exit;
  if firstArg < 0 then Exit;
  fsym := ASTLeft[firstArg];
  if (fsym < 0) or (ASTKind[fsym] <> AN_IDENT) then Exit;
  if (ASTIVal[fsym] < 0) or (ASTIVal[fsym] >= SymCount) then Exit;
  Result := SymFileRecSize[ASTIVal[fsym]];
end;

procedure FillDefaultArgs(mpi, fromIdx, callNode: Integer; var lastArg: Integer);
var exprNode, argSeq, k, recSz: Integer;
begin
  k := fromIdx;
  while k <= Procs[mpi].ParamCount - 1 do
  begin
    exprNode := DefaultArgValueNode(mpi, k);
    recSz := FileRecSizeArgOverride(mpi, k, ASTLeft[callNode]);
    if (recSz > 0) and (ASTKind[exprNode] = AN_INT_LIT) then
      ASTIVal[exprNode] := recSz;
    argSeq := AllocNode(AN_ARG);
    ASTLeft[argSeq] := exprNode;
    if lastArg = -1 then ASTLeft[callNode] := argSeq
    else ASTRight[lastArg] := argSeq;
    lastArg := argSeq;
    Inc(k);
  end;
end;

{ True when the arg list may stop here: next token is `)` and every remaining
  param (nextIdx..) carries a declared default. }
function CanFillDefaultsFrom(mpi, nextIdx: Integer): Boolean;
begin
  Result := (CurTok.Kind = tkRParen) and (nextIdx <= Procs[mpi].ParamCount - 1) and
            (nextIdx < MAX_PROC_PARAMS) and
            ProcParamHasDefault[mpi * MAX_PROC_PARAMS + nextIdx];
end;

{ Would CALLING this method already produce the method pointer the context
  wants? Then it is a CALL, not a reference, and TryParseParenlessMethodRef must
  stand down.

  This is Delphi's extended-syntax rule, and it is the only thing separating the
  two readings of a bare routine name in a context that wants a procedural
  value: the routine is CALLED when its result fits the target, and ADDRESSED
  when it does not. Every caller of the helper has already established that a
  METHOD POINTER is wanted, so "fits the target" is exactly "returns a method
  pointer" -- no other result type is assignable there, so no other result type
  changes the reading.

  Measured against FPC 3.2.2, which calls in both spellings:

    function TSvc.Handler: TSel;              { parameterless, returns TSel }
    t := Self.Handler;   -> FPC CALLS Handler
    t := Handler;        -> FPC CALLS Handler

  pxx took Handler's ADDRESS on the dotted spelling, stored a {Code, Data} pair
  built from the wrong routine, compiled clean, and SIGSEGV'd on the first call
  through `t`. That is the same failure shape as
  bug-p-a-class-method-cast-to-a-method-pointer-inline-segfaults, one construct
  further on, and it is why this test lives in the helper rather than in the arm
  that happened to need it: all three receiver spellings reach it.

  A method that REQUIRES arguments cannot be the call reading -- there are no
  arguments here, the `(` case exits earlier -- so it stays a reference.
  ParamCount includes the hidden Self. }
function MethodResultSatisfiesTarget(mmi: Integer): Boolean;
var mpi: Integer;
begin
  Result := False;
  if MethodPtrRecId = REC_NONE then Exit;
  mpi := UMthProc_[mmi];
  if (mpi < 0) or (mpi >= ProcCount) then Exit;
  if not Procs[mpi].IsFunc then Exit;
  if Procs[mpi].ParamCount > 1 then Exit;
  Result := (Procs[mpi].RetType = tyRecord) and (ProcRetRecId[mpi] = MethodPtrRecId);
end;

{ The procedural SIGNATURE of an arbitrary lvalue NODE: the Procs[] index to
  marshal an indirect call through it, or -1 when the node is not a procedural
  value. The Pascal twin of the C frontend's CNodeProcSig.

  It exists because "is this designator a procedural value?" was answered
  SPELLING BY SPELLING and never node-keyed, so each spelling had to be taught
  separately and only the first one ever was. A bare identifier read
  SymProcSig, a record field read UFldProcSig at its own AN_CALL_IND site, an
  array element read SymElemProcSig at another -- five AN_CALL_IND construction
  sites in pasparser_lval.inc plus one in pasparser_stmt.inc, each deriving the
  fact locally from whatever it happened to have in hand. The consequence is
  bug-p-a-parameterless-procedural-value-is-only-callable-bare-as-an-identifier:
  `m;` called, and `h.nul;`, `h.p;` and `a[0];` were all read as the start of an
  assignment and reported `expected ':=' before ';'`. The boundary was not `of
  object` and not the record field -- removing each showed it was neither -- it
  was that the designator is not a single identifier. FPC accepts all four, and
  real Pascal writes `OnClick;` far more often than `OnClick()`.

  Kinds it answers, which are the ones an lvalue walk can produce for a
  procedural value:
    AN_IDENT   a variable or parameter          -> SymProcSig
    AN_FIELD   a record/class field             -> UFldProcSig, via ResolveNodeRec
    AN_INDEX   an element of an array of them   -> SymElemProcSig / UFldProcSig

  Anything else answers -1, which is the "not a procedural value" reading and
  leaves every existing path untouched. devdocs/dev/normalise-dont-special-case.md }
function PasNodeProcSig(node: Integer): Integer;
var baseRec, fIdx, bi: Integer;
begin
  Result := -1;
  if (node < 0) or (node >= ASTNodeCount) then Exit;
  if ASTKind[node] = AN_IDENT then
  begin
    bi := Integer(ASTIVal[node]);
    if (bi >= 0) and (bi < SymCount) then Result := SymProcSig[bi];
  end
  else if ASTKind[node] = AN_FIELD then
  begin
    baseRec := ResolveNodeRec(ASTLeft[node]);
    if baseRec >= REC_UCLASS_BASE then
    begin
      fIdx := FindUField(baseRec - REC_UCLASS_BASE, GetASTIdentName(node));
      if (fIdx >= 0) and (not UFldIsArray[fIdx]) then Result := UFldProcSig[fIdx];
    end;
  end
  else if ASTKind[node] = AN_INDEX then
  begin
    if ASTKind[ASTLeft[node]] = AN_IDENT then
    begin
      bi := Integer(ASTIVal[ASTLeft[node]]);
      if (bi >= 0) and (bi < SymCount) then Result := SymElemProcSig[bi];
    end
    else if ASTKind[ASTLeft[node]] = AN_FIELD then
    begin
      baseRec := ResolveNodeRec(ASTLeft[ASTLeft[node]]);
      if baseRec >= REC_UCLASS_BASE then
      begin
        fIdx := FindUField(baseRec - REC_UCLASS_BASE, GetASTIdentName(ASTLeft[node]));
        if (fIdx >= 0) and UFldIsArray[fIdx] then Result := UFldProcSig[fIdx];
      end;
    end;
  end;
  { A signature is a Procs[] row; anything outside it is the "unset" -1, whatever
    sentinel the source column happened to carry. }
  if (Result < 0) or (Result >= ProcCount) then Result := -1;
end;

{ The same question as MethodResultSatisfiesTarget, asked about a FREE ROUTINE
  and against a procedural-valued TARGET SYMBOL: is `x := F` the CALL of F or
  the ADDRESS of F?

  It is the same Delphi extended-syntax rule and the same measured failure one
  construct over. The method arm got the rule when
  bug-p-a-parenless-method-reference-handles-two-of-four-receiver-spellings was
  fixed; the free-routine arm beside it (the AN_PROCADDR reading in
  pasparser_stmt.inc's assignment path) never had one, so it took the ADDRESS of
  any routine name at all. Measured 2026-09-04 against fpc 3.2.2 -Mdelphi, one
  program, two rows, both wrong in different ways:

    function MakeSel: TSel;  { TSel = procedure of object }
    function MakePl:  TPl;   { TPl  = procedure           }
    m := MakeSel;  m();   -> pxx SEGFAULT   (a {Code,Data} pair built from
                             MakeSel's own entry address, then called)
    p := MakePl;   p();   -> pxx SILENTLY calls MakePl instead of Plain
                             (no output where FPC prints `plain`)

  FPC calls in both. The address reading is not too strict here, it is the WRONG
  READING -- the same sentence MethodResultSatisfiesTarget's own note ends on.

  Deliberately NARROW: it answers True only when the routine's result actually
  FITS the target, so every program that compiles today and does not hit one of
  the two rows above keeps the address reading unchanged. A routine whose result
  does not fit was never a call candidate in FPC either (`@F` is how you spell
  the address, and it still is).

  TryDelphiBareProcArg states the same precedence for ARGUMENT position and
  reaches it the other way round -- a paramless function parses as a call there
  and falls back to @F through MatchCallDelphiProcAddr. Assignment has no such
  retry, so the decision has to be made up front, which is what this is.
  A routine that REQUIRES arguments cannot be the call reading: there are no
  arguments here (the `(` case exits earlier). }
{ The same question asked about the target's KIND rather than its SYMBOL, so a
  destination that is not a plain variable can ask it. A record FIELD and an
  array ELEMENT of a procedural type are procedural slots with no symbol of
  their own -- the symbol in hand is the record or the array, whose own
  TypeKind and SymProcSig say nothing about the slot being written.
  bug-p-delphi-mode-binds-a-bare-routine-name-only-for-a-variable-target }
function ProcSigCompatible(aPi, bPi: Integer): Boolean;
{ Two procedural signatures describe the same shape: same function-ness, same
  return type, same parameter count and the same parameter kinds in order.
  STRUCTURAL, not identity -- `ParseProcTypeSignature` mints a fresh
  `$proctype` Procs[] row per declaration, so two spellings of one shape are
  different rows and an identity test would call them incompatible.

  It exists because the question "does this routine's RESULT fit this
  procedural slot?" had no way to be asked: ProcResultSatisfiesKind answered
  "the result is A procedural value" and its own comment claimed that was
  "deliberately NARROW ... only when the routine's result actually FITS the
  target". The narrow test was never written.
  bug-p-a-bare-routine-name-whose-result-is-itself-procedural-is-called-not-taken }
var i: Integer;
begin
  Result := False;
  if (aPi < 0) or (aPi >= ProcCount) or (bPi < 0) or (bPi >= ProcCount) then Exit;
  if Procs[aPi].IsFunc <> Procs[bPi].IsFunc then Exit;
  if Procs[aPi].IsFunc and (Procs[aPi].RetType <> Procs[bPi].RetType) then Exit;
  if Procs[aPi].ParamCount <> Procs[bPi].ParamCount then Exit;
  if Procs[aPi].ParamCount > MAX_PROC_PARAMS then Exit;
  for i := 0 to Procs[aPi].ParamCount - 1 do
    if Procs[aPi].Params[i].TypeKind <> Procs[bPi].Params[i].TypeKind then Exit;
  Result := True;
end;

function ProcResultSatisfiesKind(pi: Integer; targetTk: TTypeKind;
                                 targetSig: Integer): Boolean;
begin
  Result := False;
  if (pi < 0) or (pi >= ProcCount) then Exit;
  if not Procs[pi].IsFunc then Exit;
  if Procs[pi].ParamCount > 0 then Exit;
  if targetTk = tyRecord then
    { a method-pointer target: "fits" is "returns a method pointer", exactly as
      for the method arm -- no other result type is assignable there. }
    Result := (MethodPtrRecId <> REC_NONE) and
              (Procs[pi].RetType = tyRecord) and (ProcRetRecId[pi] = MethodPtrRecId)
  else
    { a plain procedural target (tyPointer): "fits" is "returns a procedural
      value", which ProcRetProcSig records. That column was filled only by the C
      frontend until the Pascal return-type parse started carrying
      LastTypeProcSig onto it for bug-p-result-is-not-a-method-pointer-lvalue --
      the two fixes are the same missing fact read by two different consumers. }
    { …AND THE RESULT MUST FIT THIS TARGET, WHICH IS WHAT THE NOTE ABOVE ALREADY
      CLAIMED. The test was `RetType = tyPointer and ProcRetProcSig >= 0` --
      "returns A procedural value", any procedural value -- so a routine whose
      result is a DIFFERENT procedural shape than the slot read as a CALL and
      the returned routine was stored into a slot it does not fit. Measured
      against fpc 3.2.2 -Mdelphi, `TOuter = function: TInner`:
      `fo := MkOuter` CALLED MkOuter (side-effect counter 1 against fpc's 0),
      stored the TInner into the TOuter slot with no diagnostic, and the next
      `fo()` segfaulted. The paramless-ordinal control on the row above
      (`f := Src`) was 0 in both, which is what says the fit test and not the
      rule. bug-p-a-bare-routine-name-whose-result-is-itself-procedural-is-called-not-taken }
    Result := (Procs[pi].RetType = tyPointer) and (ProcRetProcSig[pi] >= 0) and
              ProcSigCompatible(ProcRetProcSig[pi], targetSig);
end;

function ProcResultSatisfiesTarget(pi, targetIdx: Integer): Boolean;
{ the symbol-keyed spelling, unchanged in meaning: it reads the kind off the
  symbol and asks the one question above. }
begin
  Result := False;
  if (targetIdx < 0) or (targetIdx >= SymCount) then Exit;
  Result := ProcResultSatisfiesKind(pi, Syms[targetIdx].TypeKind,
                                    SymProcSig[targetIdx]);
end;

{ `obj.M` / `TClass.M` with no `@` and no argument list, read as a method
  REFERENCE rather than a call.

  Delphi lets the `@` be omitted where a method POINTER is wanted, so the same
  three tokens mean two different things and only the CONTEXT separates them.
  Two contexts supply that context today -- an assignment whose LHS is a
  method-pointer variable, and a CAST whose target is a method-pointer type --
  and they were answering the question separately: the assignment arms had the
  reading, the cast arm did not, so `TSel(s.IPick)` fell through to the ordinary
  expression path, was parsed as a zero-argument CALL, and the returned integer
  was reinterpreted as a {Code, Data} pair. That crashed
  (bug-p-a-class-method-cast-to-a-method-pointer-inline-segfaults) until the
  arity check turned it into a diagnostic, which made it honest but no more
  correct: the call reading is not too strict, it is the WRONG READING.

  So the decision lives here, once, and the callers differ only in how they
  establish that a method pointer is wanted -- exactly the split
  BuildIndirectCallAST states for the callee node. Writing a fifth
  AN_METHODREF construction site instead is what root-cause-over-microfix.md
  says to stop and count rather than do.

  Both receiver flavours are handled because they are one concept: a VARIABLE
  (Self is the instance, AN_IDENT) and a CLASS NAME (Self is the metaclass, the
  RTTI blob, AN_CLASSREF -- whose VMT lives at +24, not [Self+0], which is
  IRMethodRefCode's business).

  Returns -1 without consuming anything when the tokens are not this shape, so
  a caller can simply fall through to ParseExpr. A following `(` means an
  argument list, i.e. a real call, and is left alone. }
function TryParseParenlessMethodRef: Integer;
var rsym, rci, rmmi, opNode, refNode: Integer;
begin
  Result := -1;
  if not DelphiMode then Exit;
  if CurTok.Kind <> tkIdent then Exit;
  if TokPos + 2 >= TokCount then Exit;

  { NO RECEIVER AT ALL -- a bare method name inside the class's own method,
    `TSel(Pick)`. Same concept as the two dotted spellings and the same node:
    the receiver is the implicit `Self`, which is an ordinary symbol in scope
    here, so this arm resolves it and then joins the instance-variable path
    unchanged rather than growing a third construction.

    Two guards make it safe to try before the dot test. A name that IS a symbol
    in scope is a variable and shadows the method, so it is not this shape --
    and that check runs FIRST, which is what keeps a local named after a method
    reading as the local. A following `(` is an argument list, i.e. a real call.
    Everything else falls through to the dotted arms untouched, with no tokens
    consumed.

    A class method's `Self` is the metaclass and its symbol carries REC_NONE, so
    it fails the class test below and exits -- the metaclass receiver is the
    separate arm C, which needs a sym-level predicate split out of
    NodeMetaclassCi and is a Track A change.
    bug-p-a-parenless-method-reference-handles-two-of-four-receiver-spellings }
  if (Tokens[TokPos].Kind <> tkDot) and (Tokens[TokPos].Kind <> tkLParen) and
     (FindSym(CurTok.SVal) < 0) then
  begin
    rsym := FindSym('Self');
    if rsym < 0 then Exit;
    if Syms[rsym].RecName < REC_UCLASS_BASE then Exit;
    if UClsIsRecord[Syms[rsym].RecName - REC_UCLASS_BASE] then Exit;
    rci := Syms[rsym].RecName - REC_UCLASS_BASE;
    rmmi := FindUMeth(rci, CurTok.SVal);
    if rmmi < 0 then Exit;
    if MethodResultSatisfiesTarget(rmmi) then Exit;

    { committed }
    opNode := AllocNode(AN_IDENT);
    ASTIVal[opNode] := rsym;
    ASTTk[opNode] := Ord(tyClass);
    refNode := AllocNode(AN_METHODREF);
    ASTIVal[refNode] := UMthProc_[rmmi];
    ASTLeft[refNode] := opNode;
    ASTRight[refNode] := UMthVirSlot[rmmi];
    ASTTk[refNode] := Ord(tyRecord);
    Next;   { consume the method name; there was no receiver to consume }
    Result := refNode;
    Exit;
  end;

  if Tokens[TokPos].Kind <> tkDot then Exit;
  if Tokens[TokPos + 1].Kind <> tkIdent then Exit;
  if Tokens[TokPos + 2].Kind = tkLParen then Exit;   { an argument list: a CALL }

  rci := -1;
  rmmi := -1;
  rsym := FindSym(CurTok.SVal);
  if (rsym >= 0) and (Syms[rsym].RecName >= REC_UCLASS_BASE) and
     (not UClsIsRecord[Syms[rsym].RecName - REC_UCLASS_BASE]) then
    rci := Syms[rsym].RecName - REC_UCLASS_BASE
  else if (rsym < 0) and (FindUClass(CurTok.SVal) >= 0) and
          (not UClsIsRecord[FindUClass(CurTok.SVal)]) then
    rci := FindUClass(CurTok.SVal)
  else if (rsym >= 0) and (SymMetaclassCi(rsym) >= 0) then
    { a METACLASS VARIABLE receiver -- `mc: class of TSvc; TSel(mc.Pick)`. It is
      a tyPointer whose POINTEE is a class, not a symbol whose RecName is one, so
      it misses both arms above. Asked through SymMetaclassCi, which is
      NodeMetaclassCi's AN_IDENT arm split to sym level precisely so this site
      does not have to allocate a node before it is committed. }
    rci := SymMetaclassCi(rsym)
  else
    Exit;

  rmmi := FindUMeth(rci, GetTokenStr(TokPos + 1));
  if rmmi < 0 then Exit;
  if MethodResultSatisfiesTarget(rmmi) then Exit;

  { committed: nothing below can fail, so no tokens are consumed speculatively }
  if rsym >= 0 then
  begin
    opNode := AllocNode(AN_IDENT);
    ASTIVal[opNode] := rsym;
    if SymMetaclassCi(rsym) >= 0 then
      ASTTk[opNode] := Ord(tyPointer)   { the variable holds the RTTI blob }
    else
      ASTTk[opNode] := Ord(tyClass);
  end
  else
  begin
    opNode := AllocNode(AN_CLASSREF);
    ASTIVal[opNode] := rci;
    ASTTk[opNode] := Ord(tyPointer);
  end;

  Next; Next;   { receiver name and '.'; CurTok = method name }
  refNode := AllocNode(AN_METHODREF);
  ASTIVal[refNode] := UMthProc_[rmmi];
  ASTLeft[refNode] := opNode;
  ASTRight[refNode] := UMthVirSlot[rmmi];   { VMT slot (>=0 virtual) }
  ASTTk[refNode] := Ord(tyRecord);
  Next;         { consume method name }
  Result := refNode;
end;

{ A method mentioned with NO argument list at all, where the method REQUIRES
  arguments: `s.IPick;` on `IPick(A: LongInt)`. Every method-call site shares the
  shape `if CurTok.Kind = tkLParen then begin ...parse args... end;` with no
  else, so the call node was returned holding only Self and the callee read
  whatever the argument register happened to contain. FPC rejects it; a FREE
  routine in the same position was already rejected here. One concept, two
  paths, and the second path is the one that stayed broken
  (normalise-dont-special-case.md).

  Too-few arguments INSIDE parens was never the hole -- Expect(tkComma) and
  ExpectCallRParen already catch that -- so this fires only on the no-paren
  shape, and shares ExpectCallRParen's wording because it is the same defect
  reported from the other side.

  What it must NOT reject: `p := s.Act` (a method POINTER, which is legitimately
  not a call) and `n := s.NoArgs` (parameterless). The first never reaches a call
  site at all -- it is resolved to AN_METHODREF earlier -- and the second is
  excluded by the ParamCount test. A trailing default is likewise not missing:
  Pascal defaults are trailing, so the flag on the FIRST unsupplied parameter
  settles the whole tail.
  bug-p-a-method-call-with-missing-arguments-is-accepted-and-reads-garbage }
procedure CheckMethodCallArity(mpi: Integer);
begin
  if (mpi < 0) or (mpi >= ProcCount) then Exit;
  if Procs[mpi].ParamCount <= 1 then Exit;          { Self only: nothing required }
  if (1 < MAX_PROC_PARAMS) and
     ProcParamHasDefault[mpi * MAX_PROC_PARAMS + 1] then Exit;
  ErrorRecover('wrong number of parameters in call to ' + Procs[mpi].Name);
end;

{ A call written with FEWER arguments than any overload declares, where the
  missing ones all carry defaults — `filedialog.askopenfilename()` against
  `askopenfilename(title=''; filetypes=...; ...)`. The method paths have filled
  trailing defaults for a long time (CanFillDefaultsFrom); the plain
  qualified/unqualified CALL path never did, so a Python call that simply
  omitted every optional argument reported "no overload matches these
  arguments" and named no reason.

  Returns the proc it filled for, or -1 to leave the caller's diagnostic alone.
  Only trailing parameters are supplied, and only when EVERY one of them has a
  declared default — an arity that is short by a non-defaulted parameter is
  still a real mismatch. }
function TryFillTrailingDefaults(const name: AnsiString; qUnit: Integer;
  var nArgs, argsHead, lastArg: Integer): Integer;
var i, k, cand, exprNode, argSeq, recSz: Integer; ok: Boolean;
begin
  cand := -1;
  for i := 0 to ProcCount - 1 do
    if ((Procs[i].Name = name) or
        ((not ProcCaseSensitive[i]) and CaseEqual(Procs[i].Name, name))) and
       ((qUnit < 0) or (ProcUnitIdx[i] = qUnit)) and
       (Procs[i].ParamCount > nArgs) and (Procs[i].ParamCount <= MAX_PROC_PARAMS) then
    begin
      ok := True;
      for k := nArgs to Procs[i].ParamCount - 1 do
      begin
        if not ProcParamHasDefault[i * MAX_PROC_PARAMS + k] then ok := False;
      end;
      if ok then
      begin
        cand := i;
        Break;
      end;
    end;
  if cand < 0 then
  begin
    TryFillTrailingDefaults := -1;
    Exit;
  end;
  for k := nArgs to Procs[cand].ParamCount - 1 do
  begin
    exprNode := DefaultArgValueNode(cand, k);
    { The file element width, same rule as in FillDefaultArgs — BOTH paths fill
      omitted trailing arguments and a statement-level `Assign(f, name)` takes
      this one, so an override written in only one of them is the second path
      that stays broken. }
    recSz := FileRecSizeArgOverride(cand, k, argsHead);
    if (recSz > 0) and (ASTKind[exprNode] = AN_INT_LIT) then
      ASTIVal[exprNode] := recSz;
    argSeq := AllocNode(AN_ARG);
    ASTLeft[argSeq] := exprNode;
    ASTRight[argSeq] := -1;
    if lastArg = -1 then argsHead := argSeq
    else ASTRight[lastArg] := argSeq;
    lastArg := argSeq;
  end;
  nArgs := Procs[cand].ParamCount;
  TryFillTrailingDefaults := cand;
end;

{ Count the arguments of the call whose NAME is CurTok (Tokens[TokPos] = '('
  when parenthesized): top-level commas + 1; 0 for `()` or no parens. Used to
  pick among method OVERLOADS before the signature-driven arg loop parses. }
function IsCallConvName(const s: AnsiString): Boolean;
{ THE list of calling-convention directive spellings. Every position that
  accepts one asks HERE, so adding a convention is one edit.

  Only the spellings are shared, not the guard: a directive LIST looks at
  CurTok and needs the not-reserved-word check below, while a procedural type's
  tail peeks one token past its own ';'. Sharing the guard too is what made the
  procedural-type site keep its own hard-coded `cdecl` and drift
  (compat-pascal-calling-convention-directives-uneven). }
begin
  Result := CaseEqual(s, 'cdecl') or CaseEqual(s, 'stdcall') or
            CaseEqual(s, 'safecall') or CaseEqual(s, 'register') or
            CaseEqual(s, 'pascal') or CaseEqual(s, 'mwpascal');
end;

function IsCallConvDirectiveTok: Boolean;
{ A calling-convention directive in ANY directive list — class-body member
  (`function QueryInterface(...): HResult; virtual; cdecl;` — testutils),
  record method, interface method signature, routine implementation header, and
  the routine pre-scan. They are plain identifiers, and pxx is a whole-program
  compiler with one internal convention, so they are parse-and-ignore
  everywhere.

  ONE list, five call sites, deliberately: each of those loops grew its own
  spelling of the set and they drifted apart — the implementation-side loop
  knew `cdecl` and `register` but not `stdcall`, so `procedure TC.Poke;
  stdcall;` parsed in the class body and then died on its own body's header.
  Add a convention to IsCallConvName and every position accepts it.

  Guarded on a following ';' because these words are not reserved: a FIELD named
  `register` is legal, and `register: Integer;` has a ':' next, so it stays a
  field. A directive is always followed by the semicolon. }
begin
  Result := False;
  if CurTok.Kind <> tkIdent then Exit;
  if not IsCallConvName(CurTok.SVal) then Exit;
  Result := (TokPos < TokCount) and (Tokens[TokPos].Kind = tkSemicolon);
end;

function IsInertRoutineDirectiveTok: Boolean;
{ A routine/method directive that pxx parses and IGNORES because it cannot mean
  anything here — as opposed to one it ignores because it has not got round to
  it. Same shape and same guard as IsCallConvDirectiveTok, and the same reason
  for existing: five directive loops each grew their own spelling of the set.

  - `noreturn`      a hint that the routine never returns. Nothing pxx emits
                    depends on it; FPC uses it to suppress a warning.
                    (fpc-source compiler/constexp.pas:93 is what needed it.)
  - `nostackframe`  omit the frame. An optimisation pxx does not make; emitting
                    a frame anyway is correct, only bigger.
  - `noinline`      the inverse hint. pxx's optimiser decides inlining on
                    shape, and already ignores a written `inline` for the same
                    reason (docs/language/dialect.md).
  - `far`, `near`   16-bit memory models. There is nothing to address far.
  - `local`         FPC: not visible outside its unit. pxx is a whole-program
                    compiler with no separate unit output, so a routine is
                    local exactly when nothing else names it.

  NOT here, deliberately, though they are all one-word directives that would
  parse just as easily: `varargs` (changes how a call marshals), `public`,
  `export`, `alias` and `weakexternal` (change linkage, which `--emit-obj` can
  observe), `compilerproc`/`internproc`/`rtlproc` (mark a routine the compiler
  supplies, and internproc has no body to parse), and `hardfloat`/`softfloat`
  (select a float ABI, and pxx HAS arm32 and riscv32 targets where the two
  differ). Ignoring any of those would make pxx compile something other than
  what was written, which is worse than refusing it. }
begin
  Result := False;
  if CurTok.Kind <> tkIdent then Exit;
  if not (CaseEqual(CurTok.SVal, 'noreturn') or CaseEqual(CurTok.SVal, 'nostackframe') or
          CaseEqual(CurTok.SVal, 'noinline') or CaseEqual(CurTok.SVal, 'far') or
          CaseEqual(CurTok.SVal, 'near') or CaseEqual(CurTok.SVal, 'local')) then Exit;
  Result := (TokPos < TokCount) and (Tokens[TokPos].Kind = tkSemicolon);
end;

function EatIntfMethodDirective: Boolean;
{ One directive on an INTERFACE method signature, plus its trailing ';'.
  An interface method is abstract and virtual by definition, so the dispatch
  directives (virtual/override/abstract/static) mean nothing here and FPC
  rejects them; what IS legal is `overload`, a calling convention, and the
  hint directives. All are parse-and-ignore -- overload resolution is
  signature-keyed, pxx is a whole-program compiler with one internal calling
  convention, and a hint changes no code.

  The interface member loop had NO directive handling at all, so a signature
  carrying one stopped the parse where it stood: rtl-generics' very first
  declaration is `function Compare(constref Left, Right: T): Integer;
  overload;`. Guarded like IsCallConvDirectiveTok -- these words are not
  reserved, so a directive is recognised only where a ';' (or `deprecated`'s
  message string) follows. }
begin
  Result := False;
  if CurTok.Kind = tkOverload then
  begin
    Next; Eat(tkSemicolon); Result := True; Exit;
  end;
  if IsCallConvDirectiveTok or IsInertRoutineDirectiveTok then
  begin
    Next; Eat(tkSemicolon); Result := True; Exit;
  end;
  if (CurTok.Kind = tkIdent) and
     (CaseEqual(CurTok.SVal, 'deprecated') or CaseEqual(CurTok.SVal, 'platform') or
      CaseEqual(CurTok.SVal, 'experimental') or CaseEqual(CurTok.SVal, 'unimplemented') or
      CaseEqual(CurTok.SVal, 'library') or CaseEqual(CurTok.SVal, 'varargs')) and
     (TokPos < TokCount) and
     ((Tokens[TokPos].Kind = tkSemicolon) or (Tokens[TokPos].Kind = tkString)) then
  begin
    Next;
    if CurTok.Kind = tkString then Next;   { `deprecated 'message'` }
    Eat(tkSemicolon);
    Result := True;
  end;
end;

function IsConstParamTok: Boolean;
{ `const` or FPC's `constref` opening a parameter group. constref is a plain
  identifier, not a keyword. FPC defines it as const that is ALWAYS passed by
  reference; pxx already passes const records/variants by reference (a TGUID is a
  record), and for a scalar the distinction is unobservable to the callee, so it
  maps onto const. testutils' IInterface.QueryInterface(constref IID: TGUID; ...)
  is what needs it. }
begin
  Result := (CurTok.Kind = tkConst) or
            ((CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'constref'));
end;

function TrailingCommaAt(i: Integer): Boolean;
{ Is the comma at token i a TRAILING one — nothing but the closing paren after
  it? Python allows `f(a, )` and so does this parser, but the argument COUNTER
  scored it as a second argument, which is the same silent miscount a
  brace-nested comma caused: no overload has the inflated arity, the candidate
  set comes back empty, and the caller falls back to the first-declared
  overload. `d.update(m, )` segfaulted for exactly that reason, with no dict
  literal in sight. Newlines are skipped so a comma trailing the last argument
  of a multi-line call reads the same as a single-line one. }
var k: Integer;
begin
  k := i + 1;
  while (k < TokCount) and (Tokens[k].Kind in [tkNewline, tkIndent, tkDedent]) do
    Inc(k);
  Result := (k < TokCount) and (Tokens[k].Kind = tkRParen);
end;

function CountCallArgsAhead: Integer;
var i, d: Integer;
begin
  Result := 0;
  { CurTok = the call NAME (paren at TokPos), or already ON the '(' (inherited
    path, name consumed) — scan from whichever position holds the '('  }
  if (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) then
    i := TokPos
  else if CurTok.Kind = tkLParen then
    i := TokPos - 1
  else
    Exit;
  if (i + 1 < TokCount) and (Tokens[i + 1].Kind = tkRParen) then Exit;
  Result := 1;
  d := 0;
  while i < TokCount do
  begin
    { tkBegin/tkEnd count as a nesting level too. In Pascal they are the
      begin/end KEYWORDS — an opening brace is a comment there, so it never
      reaches the token stream — and only an anonymous-method argument brings
      them here, where nesting is what you want anyway. In NIL PYTHON they are
      the BRACES, and leaving them out meant every comma inside a dict or set
      literal counted as an ARGUMENT separator: a two-entry dict literal passed
      to d.update(...) was read as a 2-argument call, no update overload has
      that arity, so the arity-viable candidate set came back EMPTY and the
      caller fell back to the first-declared overload — update(TPyList) — which
      read a TPyDict as a list and segfaulted. A one-entry literal has no comma
      and was therefore always fine, which is what made this look like a
      dict-literal bug rather than a counting one.
      bug-n-inline-multi-entry-dict-literal-arg-loses-its-values }
    if Tokens[i].Kind in [tkLParen, tkLBrack, tkBegin] then Inc(d)
    else if Tokens[i].Kind in [tkRParen, tkRBrack, tkEnd] then
    begin
      Dec(d);
      if d = 0 then Exit;
    end
    else if (Tokens[i].Kind = tkSemicolon) or (Tokens[i].Kind = tkEOF) then Exit
    else if (Tokens[i].Kind = tkComma) and (d = 1) and
            not TrailingCommaAt(i) then Inc(Result);
    Inc(i);
  end;
end;

function OverloadArgRank(pTk, aTk: TTypeKind): Integer;
{ How good a fit an argument of type aTk is for a parameter of type pTk, lower is
  better: 0 exact, 1 preferred conversion, 2 merely compatible, 3 impossible.

  The ranking exists because TypesCompatible alone is too coarse to CHOOSE with: a
  Char argument is compatible with Integer (both ordinal) AND with string, so a
  first-match scan handed `P('x')` to `P(Integer)` and passed 120. FPC prefers the
  string conversion for a character, and prefers numeric widening between numbers,
  so those two get rank 1 and everything else compatible sinks to 2. }
begin
  if pTk = aTk then begin Result := 0; Exit; end;

  { char -> string, and string flavour -> string flavour (a frozen tyString
    literal onto a managed AnsiString param).

    TypeIsFrozenString on the ARGUMENT, not `= tyString`: a record field of a
    `string[N]` keeps tyShortString where a bare variable normalises to
    tyString, so the field sank to rank 2 (merely compatible) while the
    variable got rank 1 in the same program -- a ranking asymmetry between two
    spellings of one type, which is how an overload gets chosen differently for
    `P(r.f)` than for `P(s)`. The PARAMETER side stays as it is: a frozen
    formal keeps its own exact match at rank 0 above.
    bug-a-a-frozen-record-field-is-refused-by-overload-resolution-against-an-ansistring-parameter }
  if ((pTk = tyString) or (pTk = tyAnsiString)) and
     (TypeIsFrozenString(aTk) or (aTk = tyAnsiString) or (aTk = tyChar)) then
  begin Result := 1; Exit; end;

  { numeric widening between non-character ordinals }
  if TypeIsOrdinal(pTk) and TypeIsOrdinal(aTk) and
     (pTk <> tyChar) and (aTk <> tyChar) then
  begin Result := 1; Exit; end;

  if TypesCompatible(pTk, aTk) then begin Result := 2; Exit; end;
  Result := 3;
end;

function HexDigitVal(c: Char): Integer;
begin
  if (c >= '0') and (c <= '9') then Result := Ord(c) - Ord('0')
  else if (c >= 'a') and (c <= 'f') then Result := Ord(c) - Ord('a') + 10
  else if (c >= 'A') and (c <= 'F') then Result := Ord(c) - Ord('A') + 10
  else Result := -1;
end;

procedure ParseGuidLiteral(ci: Integer; const s: AnsiString);
{ Record an interface's `['{XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}']` as the 16 raw
  bytes in TGuid MEMORY order — D1 is a little-endian u32, D2/D3 little-endian u16,
  D4 the remaining 8 bytes in written order. That is what a runtime `TGuid` looks
  like in memory, so GetInterface can compare the compile-time blob against the
  caller's TGuid byte for byte with no marshalling.

  A malformed literal is ignored rather than an error: the GUID is optional, and a
  source that carries a broken one still compiled before this. }
var
  hex: AnsiString;
  i, hi, lo, n: Integer;
  b: array[0..15] of Byte;
begin
  hex := '';
  for i := 1 to Length(s) do
  begin
    if HexDigitVal(s[i]) >= 0 then hex := hex + s[i]
    else if (s[i] <> '{') and (s[i] <> '}') and (s[i] <> '-') then Exit;  { junk }
  end;
  if Length(hex) <> 32 then Exit;

  { pack the 32 hex digits into 16 big-endian bytes first }
  for i := 0 to 15 do
  begin
    hi := HexDigitVal(hex[i * 2 + 1]);
    lo := HexDigitVal(hex[i * 2 + 2]);
    if (hi < 0) or (lo < 0) then Exit;
    b[i] := Byte(hi * 16 + lo);
  end;

  n := ci * 16;
  { D1: u32, byte-swapped to little-endian }
  UClsGuidB[n + 0] := b[3]; UClsGuidB[n + 1] := b[2];
  UClsGuidB[n + 2] := b[1]; UClsGuidB[n + 3] := b[0];
  { D2: u16 }
  UClsGuidB[n + 4] := b[5]; UClsGuidB[n + 5] := b[4];
  { D3: u16 }
  UClsGuidB[n + 6] := b[7]; UClsGuidB[n + 7] := b[6];
  { D4: 8 bytes, written order }
  for i := 0 to 7 do UClsGuidB[n + 8 + i] := b[8 + i];
  UClsHasGuid[ci] := True;
end;

function InternGuidBlob(ci: Integer): Integer;
{ The 16 GUID bytes of interface `ci`, interned as a data blob, returning the
  string-table index -- AN_GUIDCONST's payload. Interning rather than emitting a
  fresh blob per mention means the same interface named twice costs one copy, and
  it reuses the one data-emission path that already exists.

  The bytes are already in TGuid MEMORY order (ParseGuidLiteral put them there so
  __pxxGetInterface can compare against a caller's TGuid without marshalling), so
  this is a straight byte-for-byte copy. }
var s: AnsiString; i: Integer;
begin
  s := '';
  for i := 0 to 15 do s := s + Chr(UClsGuidB[ci * 16 + i]);
  InternGuidBlob := InternStr(s);
end;

{ NilPy spells `TFoo.ClassName` as `Foo.__name__` — the CLASS-side counterpart of
  `type(x).__name__`, which already answers through the same RTTI name. Mapped to
  the Pascal op rather than given a second lowering, so the two spellings cannot
  drift apart. bug-n-pyexception-leaks-through-name-and-repr }
function MapNilPyClassRefOpName(const nm: AnsiString): AnsiString;
begin
  if isNilPy and CaseEqual(nm, '__name__') then
    MapNilPyClassRefOpName := 'ClassName'
  else
    MapNilPyClassRefOpName := nm;
end;

{ The class-reference operations FPC puts on TObject in System, so they are reached
  with no `uses`:

    x.ClassName       the class's name
    x.ClassType       the class itself, as a TClass    (instances only)
    x.InheritsFrom(C) is x's class C, or a descendant of it

  Each is a walk over the RTTI blob, and each takes both shapes x can have:

    an INSTANCE       -> blob is __pxxRttiOf(x)   ([[x+0] - 8])
    a CLASS REFERENCE -> blob IS the value        (a TClass value is the blob ptr)

  blobNode is that blob. Returns -1 when the builtin helpers are not linked, so the
  caller can fall through to its normal handling. }
function GenMakeClassRefOp(blobNode: Integer; const opRaw: AnsiString; var outTk: TTypeKind): Integer;
var pi, callNode, argSeq, argSeq2: Integer; op: AnsiString;
begin
  Result := -1;
  { NilPy's `__name__` is ClassName — mapped here as well as in the predicate,
    so the two always agree about which names this handles. }
  op := MapNilPyClassRefOpName(opRaw);

  if CaseEqual(op, 'ClassType') then
  begin
    { ClassType IS the blob pointer -- no call at all, just a retype. }
    outTk := tyPointer;
    if CurTok.Kind = tkLParen then
    begin
      Next;
      Expect(tkRParen, ')');
    end;
    Result := blobNode;
    Exit;
  end;

  if CaseEqual(op, 'ClassName') then
  begin
    pi := FindProc('__pxxClassName');
    if pi < 0 then Exit;
    outTk := tyAnsiString;
  end
  else if CaseEqual(op, 'ClassParent') then
  begin
    { Answers a class reference, so outTk is tyPointer and ParseClassRefOpTail
      will happily chain further operations onto it --
      `d.ClassParent.ClassName`, which is the shape it is actually used in. }
    pi := FindProc('__pxxClassParent');
    if pi < 0 then Exit;
    outTk := tyPointer;
  end
  else if CaseEqual(op, 'InheritsFrom') then
  begin
    pi := FindProc('__pxxInheritsFrom');
    if pi < 0 then Exit;
    outTk := tyBoolean;
  end
  else if CaseEqual(op, 'UnitName') then
  begin
    { the blob's +96 word, which rtti_emit writes from UClsUnitIdx (and stamps
      'System' for TObject, matching FPC). Same one-field shape as ClassName
      and InstanceSize -- the value is emitted, this is only the accessor.
      feature-pascal-builtin-tobject-class }
    pi := FindProc('__pxxUnitName');
    if pi < 0 then Exit;
    outTk := tyAnsiString;
  end
  else if CaseEqual(op, 'InstanceSize') then
  begin
    { the blob's +16 word, which rtti_emit has always written }
    pi := FindProc('__pxxInstanceSize');
    if pi < 0 then Exit;
    outTk := tyInt64;
  end
  else if CaseEqual(op, 'ClassNameIs') then
  begin
    pi := FindProc('__pxxClassNameIs');
    if pi < 0 then Exit;
    outTk := tyBoolean;
  end
  else
    Exit;

  callNode := AllocNode(AN_CALL);
  ASTIVal[callNode] := pi;
  ASTTk[callNode] := Ord(Procs[pi].RetType);
  argSeq := AllocNode(AN_ARG);
  ASTLeft[argSeq] := blobNode;
  ASTLeft[callNode] := argSeq;

  if CaseEqual(op, 'InheritsFrom') or CaseEqual(op, 'ClassNameIs') then
  begin
    { the one argument: a class reference (blob pointer) for InheritsFrom, a
      string for ClassNameIs. Same shape, so the same arm builds it. }
    Expect(tkLParen, '(');
    ParseExpr;
    argSeq2 := AllocNode(AN_ARG);
    ASTLeft[argSeq2] := CurASTNode;
    ASTRight[argSeq] := argSeq2;
    Expect(tkRParen, ')');
  end
  else if CurTok.Kind = tkLParen then
  begin
    { FPC allows both `x.ClassName` and `x.ClassName()`. }
    Next;
    Expect(tkRParen, ')');
  end;

  Result := callNode;
end;

{ True for the names GenMakeClassRefOp handles. }
function IsClassRefOpName(const nm: AnsiString): Boolean;
var m: AnsiString;
begin
  m := MapNilPyClassRefOpName(nm);
  IsClassRefOpName := CaseEqual(m, 'ClassName') or CaseEqual(m, 'ClassType') or
                      CaseEqual(m, 'InheritsFrom') or CaseEqual(m, 'ClassParent') or
                      CaseEqual(m, 'InstanceSize') or CaseEqual(m, 'ClassNameIs') or
                      CaseEqual(m, 'UnitName');
end;

{ The class RTTI blob of an INSTANCE expression. An IR node, not a builtin call:
  `obj.ClassMethod(...)` has to pass the instance's RUNTIME class as Self, and NOTHING
  in the token stream predicts such a call, so the token pre-scan cannot know to pull
  the builtin unit for it. It is two loads either way. }
function GenMakeRttiOfCall(objNode: Integer): Integer;
var n: Integer;
begin
  n := AllocNode(AN_RTTIOF);
  ASTLeft[n] := objNode;
  ASTTk[n] := Ord(tyPointer);
  Result := n;
end;

{ Chain further class-reference operations onto one that just produced a TClass.

  `E.ClassType.InheritsFrom(AExceptionClass)` (fpcunit) is the case: ClassType yields
  a class reference, and the next selector applies to THAT, not to E. Only a
  class-reference result (tyPointer, i.e. ClassType) can carry a tail -- ClassName
  gives a string and InheritsFrom a Boolean, and neither takes these selectors. }
function ParseClassRefOpTail(node: Integer; var outTk: TTypeKind): Integer;
var nm: AnsiString; nxt: Integer;
begin
  Result := node;
  while (outTk = tyPointer) and (CurTok.Kind = tkDot) and
        (Tokens[TokPos].Kind = tkIdent) and IsClassRefOpName(GetTokenStr(TokPos)) do
  begin
    Next;                 { consume '.' -- CurTok is now the operation name }
    nm := CurTok.SVal;
    Next;                 { consume the operation name }
    nxt := GenMakeClassRefOp(Result, nm, outTk);
    if nxt < 0 then Exit;
    Result := nxt;
  end;
end;

{ Build a call to a STATIC (class) method, given the node that supplies its Self --
  the metaclass. CurTok is on the token AFTER the method name; an argument list, if
  present, is parsed here. Mirrors the qualified `TA.M(...)` block, which is the same
  call with the class named explicitly.

  Used for the BARE, unqualified form inside a method body, where the receiver is
  implicit:
    in a CLASS method    Self already IS the metaclass -> pass it straight through,
                         so `TMyTest.Suite` reaches TAssert.Suite with Self = TMyTest
                         and the class propagates down the chain;
    in an INSTANCE method the runtime class of Self -> __pxxRttiOf(Self). }
{ Close a METHOD call's argument list, reporting a surplus instead of dying on
  the paren.

  Every method-argument loop in the Pascal frontend is INDEX-DRIVEN: it parses
  exactly as many arguments as the method declares and then Expects `)`. So
  `c.M(1, 2)` on a parameterless M died as `Expected: ), but got:` pointing at
  the comma — a SYNTAX diagnostic for an ARITY mistake, and a halt, so nothing
  else in the file was reported. The plain-routine call path has said "no
  overload of X matches these arguments" and recovered since slice 3; the method
  paths could not even name the problem.

  There are SEVEN copies of that loop (pasparser_call, four in pasparser_lval,
  two in pasparser_expr), which is exactly why this is a shared tail and not a
  seventh hand-written guard — the copy is what stays broken
  (devdocs/dev/normalise-dont-special-case.md).

  Swallowing the surplus lands the parser after the `)` where a good call would
  have left it, so there is nothing to resync. Nothing reaches codegen: the
  driver halts on ErrCount before any emission.
  feature-a-error-does-not-halt-so-a-parse-can-be-speculative }
procedure ExpectCallRParen(mpi: Integer; lastArg: Integer);
var depth: Integer;
    absorbed: Boolean;
begin
  { An elided `array of const` tail is absorbed HERE rather than in each of the
    seven argument loops, for the same reason this tail is shared at all: the
    copy is what stays broken. lastArg is the loop's final AN_ARG (-1 where the
    caller has no meaningful one); AbsorbVariadicTailArgs re-homes its payload
    into a TVarRec vector and consumes the surplus, after which CurTok is `)`
    and the error below correctly does not fire.
    feature-writeln-as-library, method slice. }
  { Called UNCONDITIONALLY, not only when a surplus is visible. The
    single-element case `g.D('only')` leaves CurTok sitting on `)` -- there is
    nothing surplus about it -- and gating on `<> tkRParen` is exactly how the
    first cut of this silently kept that call crashing. The helper does its own
    (cheap) refusal: it exits unless the callee's LAST parameter is
    `array of const`. }
  absorbed := AbsorbVariadicTailArgs(mpi, lastArg);
  if (not absorbed) and (CurTok.Kind <> tkRParen) and
     (mpi >= 0) and (mpi < ProcCount) then
  begin
    ErrorRecover('wrong number of parameters in call to ' + Procs[mpi].Name);
    depth := 0;
    while CurTok.Kind <> tkEOF do
    begin
      if CurTok.Kind = tkLParen then Inc(depth)
      else if CurTok.Kind = tkRParen then
      begin
        if depth = 0 then Break;
        Dec(depth);
      end;
      Next;
    end;
  end;
  Expect(tkRParen, ')');
end;

function GenMakeStaticMethodCall(mpi: Integer; selfNode: Integer): Integer;
var callNode, lastArg, argSeq, exprNode, argIdx, ai: Integer;
    mkw, kwHead, kwCount: Integer;
begin
  callNode := AllocNode(AN_CALL);
  ASTIVal[callNode] := mpi;
  ASTTk[callNode] := Ord(Procs[mpi].RetType);
  { A VIRTUAL class method dispatches on the RUNTIME class, exactly as an instance one does:
    fpjson's `class function JSONType: TJSONType; virtual;` is read through a TJSONData
    reference and must answer for the object actually there. Self is the metaclass, so the
    VMT comes from the blob rather than from [Self+0] -- see AN_CLASS_VIRTUAL_CALL. }
  if GenVirtSlot >= 0 then
  begin
    ASTKind[callNode] := AN_CLASS_VIRTUAL_CALL;
    ASTSOffset[callNode] := GenVirtSlot;
  end;
  GenVirtSlot := -1;   { consumed: never leaks into the next call built }

  argSeq := AllocNode(AN_ARG);
  ASTLeft[argSeq] := selfNode;
  ASTLeft[callNode] := argSeq;
  lastArg := argSeq;

  if CurTok.Kind = tkLParen then
  begin
    Next;
    ai := 1;                    { param 0 is Self }
    { `obj.F()` -- EMPTY parens on a method whose parameters ALL have defaults. FPC accepts
      it (it is the ordinary way to call `FormatJSON()` in fcl-json's own test suite); the
      loop below would hand the `)` to ParseExpr and report "expected expression". A method
      with no parameters at all already worked, because the loop simply never ran. }
    if CurTok.Kind = tkRParen then
    begin
      if (Procs[mpi].ParamCount > 1) and CanFillDefaultsFrom(mpi, 1) then
        FillDefaultArgs(mpi, 1, callNode, lastArg);
      ai := Procs[mpi].ParamCount;    { nothing to parse; Expect(tkRParen) below consumes it }
    end;
    while ai <= Procs[mpi].ParamCount - 1 do
    begin
      { An `array of const` argument written as a LITERAL -- `DoError(msg, ['Nil', x])`
        (fpjson) -- and an open-array scalar literal. Without these the '[' is parsed as a
        SET and dies on "set item must be one character". The plain-routine call path has
        always checked for them; the method paths did not. }
      { `Base.st(1, b=7)` — a KEYWORD argument to a STATIC method reached
        through the class name. This loop is index-driven and interleaves
        FillDefaultArgs as it goes, which is why the keyword pair
        PyKwArgIndex/PyBindKwArgs was not simply bolted on when the INSTANCE
        shape got it: the two mechanisms would both claim the holes. So a
        keyword switches this call to the chain-driven discipline — tag the arg
        with its parameter index, stop at `)`, and let PyBindKwArgs do the
        reordering and hole-filling it already does for five other call sites.
        The no-keyword path below is untouched, and PyKwArgIndex returns 0
        unless isNilPy, so every Pascal call through here is byte-identical.
        bug-nilpy-a-static-method-called-on-the-class-takes-no-keyword-arguments }
      mkw := PyKwArgIndex(mpi, 1);
      if (CurTok.Kind = tkLBrack) and ParamIsVarRecArray(mpi, ai) then
        exprNode := ParseVarRecLiteralAST
      else if (CurTok.Kind = tkLBrack) and ParamIsOpenArrayScalar(mpi, ai) then
        exprNode := ParseArrayCtorAST(Procs[mpi].Params[ai].TypeKind,
          OpenArrayCtorRowLen(mpi, ai), ProcParamElemRowLo[mpi * MAX_PROC_PARAMS + ai])
      else if Procs[mpi].Params[ai].IsRef or Procs[mpi].Params[ai].IsArray then
      begin
        if ByRefArgStartsExpression(ParamIsConstVariant(mpi, ai)) then
        begin
          ParseExpr; exprNode := CurASTNode;
        end
        else
        begin
          argIdx := FindSym(CurTok.SVal); Next;
          exprNode := ParseLValueAST(argIdx, TokPos - 2);
        end;
      end
      else
      begin
        ParseExpr; exprNode := CurASTNode;
      end;
      SetLitCheckArg(exprNode, mpi, ai);
      argSeq := AllocNode(AN_ARG);
      ASTLeft[argSeq] := exprNode;
      ASTIVal[argSeq] := mkw;
      ASTRight[lastArg] := argSeq;
      lastArg := argSeq;
      if mkw <> 0 then
      begin
        if CurTok.Kind = tkRParen then Break;
        Expect(tkComma, ',');
        Inc(ai);
        Continue;
      end;
      if (ai < Procs[mpi].ParamCount - 1) and CanFillDefaultsFrom(mpi, ai + 1) then
      begin
        FillDefaultArgs(mpi, ai + 1, callNode, lastArg);
        ai := Procs[mpi].ParamCount - 1;
      end
      else if ai < Procs[mpi].ParamCount - 1 then Expect(tkComma, ',');
      Inc(ai);
    end;
    ExpectCallRParen(mpi, lastArg);
    { The chain starts at the SELF argument, exactly as the instance path hands
      it over — PyKwArgIndex returns the ABSOLUTE parameter index, and self is
      parameter 0, so the two agree without an offset. A no-keyword chain is
      returned untouched (PyBindKwArgs exits on its own first test). }
    kwHead := ASTLeft[callNode];
    kwCount := 0;
    PyBindKwArgs(mpi, kwHead, lastArg, kwCount);
    ASTLeft[callNode] := kwHead;
  end
  else if CanFillDefaultsFrom(mpi, 1) then
    FillDefaultArgs(mpi, 1, callNode, lastArg)
  else
    CheckMethodCallArity(mpi);

  Result := callNode;
end;

{ The metaclass to pass as Self for a BARE static-method call in the CURRENT body.
  -1 when there is no enclosing method. }
function GenMakeImplicitMetaclass: Integer;
var selfIdx, selfNode: Integer;
begin
  Result := -1;
  if (CurProc < 0) or (Procs[CurProc].ParamCount <= 0) then Exit;
  selfIdx := Procs[CurProc].Params[0].SymIdx;
  if selfIdx < 0 then Exit;
  selfNode := AllocNode(AN_IDENT);
  ASTIVal[selfNode] := selfIdx;
  ASTTk[selfNode] := Ord(Syms[selfIdx].TypeKind);
  if CurSelfClass >= REC_UCLASS_BASE then
    { an INSTANCE method: Self is the object -- take its RUNTIME class }
    Result := GenMakeRttiOfCall(selfNode)
  else
    { a CLASS method: Self already IS the metaclass }
    Result := selfNode;
end;

{ Is this bare identifier a value of CLASS-REFERENCE type (a TClass variable, param,
  or a field of the enclosing class)? A class reference is tyPointer whose element is
  tyClass -- the shape TClass, a metaclass Self, and ClassType all carry. Used to spot
  `E is <classref>`, where the class is a runtime value rather than a name. }
function IdentIsClassRefValue(const nm: AnsiString): Boolean;
var si, fi: Integer;
begin
  IdentIsClassRefValue := False;
  si := FindSym(nm);
  if si >= 0 then
  begin
    if (Syms[si].TypeKind = tyPointer) and (Syms[si].PtrElemTk = tyClass) then
    begin
      IdentIsClassRefValue := True;
      Exit;
    end;
    if (Syms[si].TypeKind = tyClass) and (Syms[si].RecName = REC_NONE) then
    begin
      IdentIsClassRefValue := True;
      Exit;
    end;
    Exit;   { a symbol of some other type shadows -- `is` is not an operator here }
  end;
  if (CurProc >= 0) and (CurMethClass >= REC_UCLASS_BASE) then
  begin
    fi := FindUField(CurMethClass - REC_UCLASS_BASE, nm);
    if fi >= 0 then
    begin
      { a class-reference FIELD carries the same "class with no concrete class id"
        shape, whether it is recorded as a pointer-to-class or a bare class }
      if (UFldTk[fi] = Ord(tyPointer)) and (UFldPtrElemTk[fi] = Ord(tyClass)) then
        IdentIsClassRefValue := True
      else if (UFldTk[fi] = Ord(tyClass)) and (UFldRec_[fi] = REC_NONE) then
        IdentIsClassRefValue := True;
    end;
  end;
end;

function GenMakeGetInterfaceCall(objNode: Integer): Integer;
{ Rewrite `<obj>.GetInterface(IID, Obj)` (and the bare, implicit-Self form) to
  __pxxGetInterface(<obj>, @IID, @Obj). CurTok must be on the '('.

  Both arguments go by ADDRESS. An AN_ADDR over a by-ref parameter auto-derefs in
  IRLowerAddress and yields the CALLER's address, so this is correct whether the
  argument is a plain variable (`var o: IFoo; obj.GetInterface(g, o)`) or an untyped
  `out` parameter being forwarded — which is exactly testutils' shape:

      function TNoRefCountObject.QueryInterface(constref IID: TGUID; out Obj): HResult;
      begin
        if GetInterface(IID, Obj) then ...

  Returns -1 when the builtin helper is not linked, so the caller can fall through
  to its normal "no such method" handling. }
var
  pi, callNode, a1, a2, addr1, addr2: Integer;
begin
  Result := -1;
  pi := FindProc('__pxxGetInterface');
  if pi < 0 then Exit;

  Expect(tkLParen, '(');

  callNode := AllocNode(AN_CALL);
  ASTIVal[callNode] := pi;
  ASTTk[callNode] := Ord(Procs[pi].RetType);

  a1 := AllocNode(AN_ARG);            { arg 0 = the instance }
  ASTLeft[a1] := objNode;
  ASTLeft[callNode] := a1;

  ParseExpr;                          { IID }
  addr1 := AllocNode(AN_ADDR);
  ASTLeft[addr1] := CurASTNode;
  ASTTk[addr1] := Ord(tyPointer);
  a2 := AllocNode(AN_ARG);
  ASTLeft[a2] := addr1;
  ASTRight[a1] := a2;

  Expect(tkComma, ',');

  ParseExpr;                          { Obj }
  addr2 := AllocNode(AN_ADDR);
  ASTLeft[addr2] := CurASTNode;
  ASTTk[addr2] := Ord(tyPointer);
  a1 := AllocNode(AN_ARG);
  ASTLeft[a1] := addr2;
  ASTRight[a2] := a1;

  Expect(tkRParen, ')');
  Result := callNode;
end;

procedure EmitMainBodyIntfTempRelease;
{ Release the COM-interface `as`-cast temps materialised in the MAIN program body
  (skGlobal, AddRef'd on creation by IRMaterializeIntfCast) at program exit. FPC
  keeps such an expression temp alive to end-of-main, so its object is destroyed
  AFTER the last body statement — not early when the source `iwX := nil` drops the
  global var's reference. pxx modelled the temp as a plain skGlobal alias (no
  retain, no release), so the object died at `iwX := nil` and the differential
  oracle saw a wrong exit checksum (bug-pascal-mainbody-ascast-temp-finalization
  -timing). Emitted after the main body, before EmitExit; PXXIntfRelease is
  nil-safe, so an as-cast whose branch never ran (nil BSS slot) is harmless. }
var i, pi, seqNode, lastSeq, callNode, aAddr, arg0, arg1, identNode, ci, sym: Integer;
begin
  if MainBodyIntfTempCount = 0 then Exit;
  pi := FindProc('PXXIntfRelease');
  if pi < 0 then Exit;
  seqNode := AllocNode(AN_SEQ);
  lastSeq := seqNode;
  for i := 0 to MainBodyIntfTempCount - 1 do
  begin
    sym := MainBodyIntfTempSym[i];
    ci := Syms[sym].RecName - REC_UCLASS_BASE;
    identNode := AllocNode(AN_IDENT);
    ASTIVal[identNode] := sym;
    ASTTk[identNode] := Ord(Syms[sym].TypeKind);
    aAddr := AllocNode(AN_ADDR);            { @slot }
    ASTLeft[aAddr] := identNode;
    ASTTk[aAddr] := Ord(tyPointer);
    arg0 := AllocNode(AN_ARG);
    ASTLeft[arg0] := aAddr;
    arg1 := AllocNode(AN_ARG);
    ASTLeft[arg1] := AllocNode(AN_INT_LIT);
    ASTIVal[ASTLeft[arg1]] := ci;
    ASTTk[ASTLeft[arg1]] := Ord(tyNativeInt);
    ASTRight[arg0] := arg1;
    callNode := AllocNode(AN_CALL);
    ASTIVal[callNode] := pi;
    ASTTk[callNode] := Ord(Procs[pi].RetType);
    ASTLeft[callNode] := arg0;
    if ASTLeft[lastSeq] = -1 then
      ASTLeft[lastSeq] := callNode
    else
    begin
      ASTRight[lastSeq] := AllocNode(AN_SEQ);
      lastSeq := ASTRight[lastSeq];
      ASTLeft[lastSeq] := callNode;
    end;
  end;
  CompileAST(seqNode);
end;

function RegisterLineEndingConst: Integer;
{ Intern System.LineEnding as an ordinary untyped string constant and return its index,
  so every later use is just a frozen string literal. Called lazily, only once nothing
  else has claimed the name — see the callers. Posix; Windows is not a target. }
begin
  Result := FindStrConst('LineEnding');
  if Result >= 0 then Exit;
  if StrConstCount >= MAX_TYPEALIAS then Error('too many string constants');
  if TokCharLen >= STRING_CAP then Error('string constant buffer overflow');
  StrConstName[StrConstCount] := 'LineEnding';
  StrConstOwner[StrConstCount] := -1;   { System.LineEnding is global }
  StrConstSOff[StrConstCount] := TokCharLen;
  StrConstSLen[StrConstCount] := 1;
  TokChars[TokCharLen] := #10;
  Inc(TokCharLen);
  Result := StrConstCount;
  StrConstUnitIdx[StrConstCount] := CurrentUnitIdx; StrConstDeclImpl[StrConstCount] := DeclInImplNow; Inc(StrConstCount);
end;

{ WHICH arguments in the call's parenthesised list START with '[' at bracket
  depth 0 -- an `array of const` literal (`TC.Log(fmt, ['answer', 42])`) or an
  open-array constructor. Bit j is argument j, 0-based over the EXPLICIT
  arguments; arguments past 31 are not represented (see the caller, which only
  narrows on the bits it has). Purely token-level: the real parse needs a
  parameter to bind against before it can tell either from a SET literal, and
  the speculative probe below has no parameter. lp is the index of the '('.

  Returns a MASK rather than a Boolean because the caller has to know the SLOT.
  Told only "somewhere in this call", it could do nothing but abandon type-aware
  selection entirely, and first-declared then won -- silently, and for a call
  that has exactly one right answer.
  bug-p-a-bracket-argument-turns-off-method-overload-selection }
function ArgListBracketElemMask(lp: Integer): LongWord;
var i, depth, slot: Integer; atElemStart: Boolean; tk: TTokenKind;
begin
  Result := 0;
  if lp < 0 then Exit;
  depth := 0; atElemStart := True; i := lp + 1; slot := 0;
  while i < TokCount do
  begin
    tk := Tokens[i].Kind;
    if tk = tkEOF then Exit;
    if (tk = tkLBrack) and (depth = 0) and atElemStart and (slot < 32) then
      Result := Result or (LongWord(1) shl slot);
    if (tk = tkLParen) or (tk = tkLBrack) then Inc(depth)
    else if (tk = tkRBrack) then Dec(depth)
    else if tk = tkRParen then
    begin
      if depth = 0 then Exit;
      Dec(depth);
    end;
    atElemStart := (tk = tkComma) and (depth = 0);
    if atElemStart then Inc(slot);
    Inc(i);
  end;
end;

{ True when some argument in the call's parenthesised list STARTS with a
  NilPy unpack -- `*xs` or `**kw` at bracket depth 0 (`**` lexes as two tkStar,
  so one test covers both). Purely token-level, and a
  sibling of ArgListHasBracketElem above for the same reason: a star is not an
  expression, so the speculative probe below hands it to ParseArgExpr, which
  reports "expected expression" -- and Error HALTS, so the probe's own
  "unsupported arg shape" escape (nArgs <> nExplicitArgs) is never reached and
  the compile dies on a call that is perfectly well formed.

  `c.take(*xs)` against `def take(self, *a)` was refused outright. The boundary
  is the arity filter: the probe only runs when the written arguments already
  fill the fixed parameters, which is why `c.take(0, *xs)` compiled and the
  shorter form did not -- a shape difference that looks like a call-site rule
  and is really "did the probe get to run".

  Answered BEFORE the probe, exactly as the `**` dict-keyword case is answered
  in PyDictKwOverloadAhead and the `[` case in ArgListHasBracketElem: a shape
  the probe cannot parse has to be settled before it, not after. Selection then
  falls back to arity, which is what these calls had before the probe existed --
  and arity is all that is knowable anyway, since an unpacked list's LENGTH is
  a runtime value.

  lp is the index of the '('.
  regression-test-nilpy-test-nilpy-star-unpack-into-a-collecting-callee }
function ArgListHasStarUnpack(lp: Integer): Boolean;
var i, depth: Integer; atElemStart: Boolean; tk: TTokenKind;
begin
  Result := False;
  if lp < 0 then Exit;
  depth := 0; atElemStart := True; i := lp + 1;
  while i < TokCount do
  begin
    tk := Tokens[i].Kind;
    if tk = tkEOF then Exit;
    if (tk = tkStar) and (depth = 0) and atElemStart then
    begin Result := True; Exit; end;
    if (tk = tkLParen) or (tk = tkLBrack) then Inc(depth)
    else if (tk = tkRBrack) then Dec(depth)
    else if tk = tkRParen then
    begin
      if depth = 0 then Exit;
      Dec(depth);
    end;
    atElemStart := (tk = tkComma) and (depth = 0);
    Inc(i);
  end;
end;

function OverloadArgParamIdx(pi, base, j, kwTok: Integer): Integer;
{ Which PARAMETER of `pi` does the probe's argument `j` bind to?

  For a positional argument that is `base + j` and always was. For a NilPy
  KEYWORD argument it is wherever the name says, and the difference is not
  cosmetic: `meth(a=0, v=(8, 6))` against
  `meth(a: Integer = -1; const s: AnsiString = ''; const v: Variant = 0)`
  binds its second argument to `v`, while `base + j` says `s`. The probe then
  judged a tuple against an AnsiString parameter, found a reference-shaped
  argument on a string slot, and refused a legal call:
  `no overload of meth matches these arguments`.

  The probe used to DISCARD the keyword name -- it steps over `name=` so the
  name is not parsed as an expression -- on the stated ground that it "only
  needs the argument's TYPE; which parameter it binds to is settled later by
  PyKwArgIndex". That is true of what the two loops below want to know, and
  false of how they INDEX, which is positional. So the name is recorded as a
  token index and resolved here instead of being thrown away.

  -1 means "no parameter of that name", which is not an error: a callee with
  `**kwargs` legitimately takes it. Both callers ABSTAIN on -1 rather than
  reject, which is this file's standing rule -- an unsound refusal of a legal
  program is worse than the looseness it replaces.
  bug-n-a-methods-keyword-call-drops-a-tuple-argument-when-an-earlier-default-is-skipped }
var i: Integer;
    nm: AnsiString;
begin
  if kwTok < 0 then
  begin
    OverloadArgParamIdx := base + j;
    Exit;
  end;
  OverloadArgParamIdx := -1;
  if (pi < 0) or (pi >= ProcCount) then Exit;
  nm := GetTokenStr(kwTok);
  for i := base to Procs[pi].ParamCount - 1 do
    if ParamNameEq(pi, Procs[pi].Params[i].Name, nm) then
    begin
      OverloadArgParamIdx := i;
      Exit;
    end;
end;

{ A typed-pointer ARGUMENT's POINTEE, and tyUnknown whenever it is not certain.

  The same certainty discipline MatchArgScalar and MatchArgArray follow, and for
  the same reason: tyUnknown doubles as the untyped-`Pointer` sentinel, so a
  guess here does not merely rank an overload wrongly, it REFUSES a PWideChar
  argument to the only overload that takes one. Exactly one shape is certain --
  a named pointer variable of depth one -- and everything else stays
  unconstrained. IsNodePChar's other three arms (cast, field, call result) are
  deliberately out: each would need its own wide twin before it could answer
  symmetrically, and a half-answer here is worse than no answer.

  The signed/unsigned byte spellings normalise onto tyChar because a PChar
  formal is written all three ways across the RTL and the C bindings.

  ONE definition, three consumers: the argument-match channel below, and the two
  METHOD overload rankers, which do not fill the channels (they parse their
  arguments speculatively and rewind, so there is no AN_ARG chain to walk).
  bug-p-a-pchar-and-a-pwidechar-parameter-are-one-overload }
function NodePtrElemTkCertain(node: Integer; argTk: TTypeKind): TTypeKind;
begin
  Result := tyUnknown;
  if (argTk <> tyPointer) or (node < 0) then Exit;
  if (ASTKind[node] <> AN_IDENT) or (ASTIVal[node] < 0) or
     (ASTIVal[node] >= SymCount) then Exit;
  if (Syms[ASTIVal[node]].TypeKind <> tyPointer) or
     (SymTR[ASTIVal[node]].PtrDepth <> 1) then Exit;
  Result := IntToTypeKind(SymTR[ASTIVal[node]].PtrBaseTk);
  if (Result = tyUInt8) or (Result = tyInt8) then Result := tyChar;
end;

{ Does argument `node` (of kind `argTk`) DISAGREE with parameter `pj` of
  candidate `pi` about the part of the type the KIND does not carry -- a managed
  string's element WIDTH, or a typed pointer's POINTEE?

  "Disagree" needs both sides to say something: an untyped `Pointer` formal, or
  a parameter from a path that never recorded a pointee, keeps matching whatever
  it matched before. Used to break a rank-0 TIE in the two method rankers, the
  same way the class-identity refinement beside it does -- and to rank 2 (merely
  compatible), never 3, because passing a PWideChar to the only overload taking
  a PChar is a real conversion FPC performs. What FPC does not do is PREFER it
  when a candidate that matches exactly exists. }
function OverloadArgElemMismatch(pi, pj, node: Integer; argTk: TTypeKind): Boolean;
var pe, ae: Integer;
begin
  Result := False;
  if (pj < 0) or (pj >= MAX_PROC_PARAMS) then Exit;
  if (argTk = tyAnsiString) and (Procs[pi].Params[pj].TypeKind = tyAnsiString) then
  begin
    Result := StrElemIsWide(ASTStrElemTkOf(node)) <>
              StrElemIsWide(ProcParamStrElemTk[pi * MAX_PROC_PARAMS + pj]);
    Exit;
  end;
  if (argTk = tyPointer) and (Procs[pi].Params[pj].TypeKind = tyPointer) then
  begin
    pe := ProcParamPtrElemTk[pi * MAX_PROC_PARAMS + pj];
    ae := Ord(NodePtrElemTkCertain(node, argTk));
    Result := (pe <> Ord(tyUnknown)) and (ae <> Ord(tyUnknown)) and (pe <> ae);
  end;
end;

procedure FillMatchArgChannelsAt(i, node: Integer; argTk: TTypeKind);
{ Fill the argument-match SIDE CHANNELS for ONE argument. SEVEN of them since
  2026-09-05 -- five, then MatchArgStrElemTk and MatchArgPtrElemTk -- so read
  the list below rather than this sentence's number.

  MatchParamCompatible, MatchParamExact and MatchArgRecMismatch (symtab.inc) are
  not functions of the two type kinds. They read MatchArgRec, MatchArgNil,
  MatchArgScalar, MatchArgArray, MatchArgArrayElemTk, MatchArgStrElemTk and
  MatchArgPtrElemTk, and every one of them was added because the kind pair alone
  gave a WRONG ANSWER -- the ticket citations below name which defect each
  time. Until 2026-09-05 all five were filled by five
  separate walks of the AN_ARG chain inside MatchCallDelphiProcAddr, so the
  knowledge lived in one caller and no other caller could reach it.

  PER-ARGUMENT, not per-chain, and that is deliberate. Every fill turned out to
  be a pure function of (node, argTk) -- none reads a neighbour, none needs the
  chain -- so the chain walking was incidental. Taking a chain would force the
  speculative overload probe in FindUMethOverloadAhead (below) to BUILD one from
  nodes it has already parsed, and that probe REWINDS its token stream: the
  tokens come back, but AN_ARG nodes allocated into the arena would not. A
  per-argument entry point lets the probe call this exactly where it already
  holds the node and allocate nothing.

  The caller sets the *Valid flags after its loop, and there are FEWER of them
  than there are channels: MatchArgArray/MatchArgArrayElemTk share
  MatchArgArrayValid, and MatchArgStrElemTk/MatchArgPtrElemTk share
  MatchArgElemValid (defs.inc). Count them there, not here.

  refactor-p-the-overload-probe-cannot-see-the-argument-match-channels }
begin
  if i >= MAX_PROC_PARAMS then Exit;

  { Record identity, for rec-aware overload phases.
    An AN_METHODREF argument is reported as tyRecord (it fills a method-pointer
    param) but ResolveNodeRec would yield the OBJECT's class, not the
    method-pointer record -- leave the record identity unconstrained so it binds
    to the `of object` param (its {Code,Data} pair is built at IR lowering).
    tyClass added with bug-a-overload-resolution-ignores-class-identity: without
    the argument's class id the matcher stays blind and binds an unrelated class
    to any class-typed parameter.
    bug-overload-resolution-record-identity }
  if ASTKind[node] = AN_METHODREF then MatchArgRec[i] := REC_NONE
  else if (argTk = tyRecord) or (argTk = tyClass) then
    MatchArgRec[i] := ResolveNodeRec(node)
  else MatchArgRec[i] := REC_NONE;

  { ...and which arguments are the literal `nil`. Its own channel rather than
    folded into MatchArgRec because it answers a different question -- not
    "which record is this" but "may this bind a nil-able parameter of ANY of the
    nil-able kinds".
    bug-a-nil-is-not-accepted-as-a-method-pointer-argument }
  MatchArgNil[i] := IsNilLiteralNode(node);

  { ...and the ALIAS the argument was declared through, so a DISTINCT type
    (`type TMyB = type byte`) can refuse the base-typed parameter FPC refuses it
    for. Only a symbol-bearing node can answer -- read the boundary in
    MatchArgAliasIdx's own header in defs.inc rather than guessing from here.
    bug-p-a-distinct-type-declaration-is-parsed-but-is-not-distinct }
  MatchArgAliasIdx[i] := -1;
  if (ASTKind[node] = AN_IDENT) and (ASTIVal[node] >= 0) and
     (ASTIVal[node] < SymCount) then
    MatchArgAliasIdx[i] := SymAliasIdx[Integer(ASTIVal[node])];

  { ...and whether the argument is a ROUTINE OR METHOD ADDRESS. Both node kinds
    are typed tyPointer deliberately (so `TakesPtr(@h.M)` works), and a
    procedural parameter is a tyRecord or carries a ProcParamProcSig, so the
    kind pair cannot answer it. MatchArgProcAddrOk (symtab.inc) reads this and
    asks the DESTINATION, exactly as MatchArgNilOk does.
    refactor-p-the-overload-probe-still-cannot-answer-two-argument-shapes }
  MatchArgProcAddr[i] := (ASTKind[node] = AN_PROCADDR) or
                         (ASTKind[node] = AN_METHODREF);

  { ...and whether the argument is DEFINITELY a scalar value, which disqualifies
    an ARRAY parameter. argTk cannot answer that: a fixed-array parameter and a
    fixed-array argument both present their ELEMENT kind, so an
    `array[0..2] of Integer` overload looked exactly like an `Integer` one and
    won by declaration order -- `Sum(n)` then read three elements off a 4-byte
    variable and segfaulted. Only shapes whose scalar-ness is CERTAIN are
    marked; anything else stays False and matches as before.
    bug-a-an-integer-argument-binds-a-fixed-array-overload }
  MatchArgScalar[i] :=
    ((TypeIsOrdinal(argTk) or TypeIsFloat(argTk)) and
     (argTk <> tyChar) and (argTk <> tyPointer)) and
    (((ASTKind[node] = AN_INT_LIT) or (ASTKind[node] = AN_FLOAT_LIT) or
      (ASTKind[node] = AN_BINOP)) or
     ((ASTKind[node] = AN_IDENT) and (ASTIVal[node] >= 0) and
      (ASTIVal[node] < SymCount) and not Syms[ASTIVal[node]].IsArray) or
     ((ASTKind[node] = AN_CALL) and (ASTIVal[node] >= 0) and
      (ProcRetFixedArrBytes[ASTIVal[node]] = 0) and
      not ProcRetIsDynArray[ASTIVal[node]]));

  { ...and the STRING twin of the same blindness. `array of AnsiString` presents
    tyAnsiString exactly as a plain `AnsiString` parameter does, so `P('hello')`
    bound whichever was DECLARED FIRST and the callee then read a dyn-array
    header off a string handle: `P(const v: array of AnsiString)` before
    `P(const v: AnsiString)` printed `arr 5` instead of `str hello`. Silent
    wrong dispatch, no diagnostic.
    A string LITERAL is its own node shape (AN_STR_LIT) and has to be listed;
    the rest reuse the shapes above unchanged, including AN_BINOP so a
    concatenation counts. Char stays out for the same reason it is out above:
    char<->string conversions are legitimate and ranked, not blocked.
    bug-p-a-string-argument-binds-an-array-of-string-overload }
  if (argTk = tyAnsiString) or (argTk = tyString) or
     (argTk = tyShortString) or (argTk = tyFixedString) then
    MatchArgScalar[i] :=
      (ASTKind[node] = AN_STR_LIT) or (ASTKind[node] = AN_BINOP) or
      ((ASTKind[node] = AN_IDENT) and (ASTIVal[node] >= 0) and
       (ASTIVal[node] < SymCount) and not Syms[ASTIVal[node]].IsArray) or
      ((ASTKind[node] = AN_CALL) and (ASTIVal[node] >= 0) and
       (ProcRetFixedArrBytes[ASTIVal[node]] = 0) and
       not ProcRetIsDynArray[ASTIVal[node]]);

  { ...and the mirror channel: which arguments are DEFINITELY an array, which
    disqualifies a SCALAR parameter. NOT the negation of MatchArgScalar --
    everything uncertain must stay False in BOTH, or an argument shape neither
    channel recognises would be blocked from every candidate at once.
    Same certainty discipline: a named array symbol, or a call to a routine
    whose RESULT is a fixed or dynamic array. Nothing else.
    bug-p-an-array-argument-binds-a-scalar-overload }
  MatchArgArray[i] :=
    ((ASTKind[node] = AN_IDENT) and (ASTIVal[node] >= 0) and
     (ASTIVal[node] < SymCount) and
     (Syms[ASTIVal[node]].IsArray or (SymDynDepth[ASTIVal[node]] > 0))) or
    ((ASTKind[node] = AN_CALL) and (ASTIVal[node] >= 0) and
     ((ProcRetFixedArrBytes[ASTIVal[node]] > 0) or
      ProcRetIsDynArray[ASTIVal[node]]));
  MatchArgArrayElemTk[i] := tyUnknown;
  if MatchArgArray[i] and (ASTKind[node] = AN_IDENT) and
     (ASTIVal[node] >= 0) and (ASTIVal[node] < SymCount) then
    MatchArgArrayElemTk[i] := Syms[ASTIVal[node]].TypeKind;

  { ...and the sixth: a managed string's ELEMENT WIDTH, which the kind channel
    cannot carry because AnsiString, WideString and UnicodeString are all
    tyAnsiString. Derived through ASTStrElemTkOf rather than stamped, for the
    reason that function's own header gives -- ASTStrElemTk is a carrier with
    few writers, so a PRODUCED wide string (`w1 + w2`, a wide-returning call)
    would read narrow off the raw slot. NORMALISED to Ord(tyChar) so 0 keeps
    meaning "not a managed string" here as it does everywhere else.
    bug-p-a-widestring-and-an-ansistring-parameter-are-one-overload }
  if argTk = tyAnsiString then
  begin
    if ASTStrElemTkOf(node) = Ord(tyWideChar) then
      MatchArgStrElemTk[i] := Ord(tyWideChar)
    else MatchArgStrElemTk[i] := Ord(tyChar);
  end
  else MatchArgStrElemTk[i] := 0;

  { ...and the seventh: a typed pointer's POINTEE, so PChar and PWideChar stop
    being one exact match. CERTAIN SHAPES ONLY, the discipline MatchArgScalar
    and MatchArgArray already follow -- a named pointer variable of depth one,
    and nothing else. IsNodePChar's other three arms (cast, field, call result)
    deliberately stay out: each would need its own wide twin to be symmetric,
    and a channel that answers narrow for a shape it cannot really see would
    refuse a PWideChar argument to the only overload that takes one. tyUnknown
    means "unconstrained", which is what every uncertain shape must stay.
    The signed/unsigned byte spellings normalise onto tyChar because a PChar
    formal is spelled all three ways across the RTL and the C bindings.
    bug-p-a-pchar-and-a-pwidechar-parameter-are-one-overload }
  MatchArgPtrElemTk[i] := NodePtrElemTkCertain(node, argTk);
end;

function FindUMethOverloadAhead(ci: Integer; const name: AnsiString; nExplicitArgs: Integer): Integer;
{ TYPE-aware method overload selection.

  FindUMethArity picks the first name match whose ARITY fits, so same-arity
  overloads (`AssertEquals(string)` vs `AssertEquals(Integer)` — fpcunit is built
  out of these) always ran the FIRST body no matter what was passed: silent wrong
  code, no diagnostic.

  Candidates = name matches up the parent chain whose arity accepts the call. With
  0 or 1 candidate this IS FindUMethArity, so the single-method paths are
  untouched. With more than one, the call's argument expressions are parsed
  SPECULATIVELY to learn their types, the token stream is rewound to exactly where
  it was, and the candidate whose parameters match wins — exact types first, then
  TypesCompatible (which is what maps a tyString literal onto an `AnsiString`
  param). See bug-pascal-method-overload-ignores-arg-types. }
const MAX_OVL_CAND = 32;
var
  cand: array[0..MAX_OVL_CAND-1] of Integer;
  argTk: array[0..MAX_PROC_PARAMS-1] of TTypeKind;
  argRec: array[0..MAX_PROC_PARAMS-1] of Integer;
  argIsNil: array[0..MAX_PROC_PARAMS-1] of Boolean;   { the literal `nil` at argument j }
  argNode: array[0..MAX_PROC_PARAMS-1] of Integer;    { argument j's parsed AST node, kept
                                                        across the rewind so the channels can
                                                        be filled AFTER all parsing is done --
                                                        see the fill in the nCand=1 gate }
  argKwTok: array[0..MAX_PROC_PARAMS-1] of Integer;   { token index of argument j's NilPy
                                                        keyword name, -1 if positional }
  pj: Integer;                                        { argument j's parameter slot }
  nCand, nArgs, i, j, c, pi, base, want, curr, mbase, cnt, lp, savedCurIdx, best: Integer;
  score, bestScore, rank, pRec, aRec, upDist, upCurr: Integer;
  nBr, brOnly: Integer;
  bmask: LongWord;
  ok, okBr, vetoed: Boolean;
  lo, name2: AnsiString;
begin
  Result := -1;
  name2 := name;
  lo := ULower(name2);

  { NilPy `d.update(a=1, b=2)` / `d.update(**e)`: the keywords are dict KEYS, so
    the argument list is ONE TPyDict however many of them there are. Answered
    before the arity filter (which counts them) and before the speculative probe
    (which cannot parse a `**` at all). PyDictKwOverloadAhead carries the why. }
  if isNilPy then
  begin
    i := PyDictKwOverloadAhead(ci, name);
    if i >= 0 then begin Result := i; Exit; end;
  end;

  { 1. collect the arity-viable candidates }
  nCand := 0;
  curr := ci;
  while curr >= 0 do
  begin
    mbase := UClsMBase[curr];
    cnt   := UClsMCount[curr];
    i := 0;
    while i < cnt do
    begin
      if UMemberNameMatch(UMthNOff[mbase + i], UMthNLen[mbase + i], curr, name, lo) then
      begin
        { EVERY method carries a Self at index 0 now -- a class method's Self is the
          metaclass. So the implicit arg is always there, static or not. }
        want := nExplicitArgs + 1;
        if ProcArityMatches(UMthProc_[mbase + i], want) and (nCand < MAX_OVL_CAND) then
        begin
          cand[nCand] := mbase + i;
          Inc(nCand);
        end;
      end;
      Inc(i);
    end;
    { Object Pascal HIDING: a method declared in a descendant without
      `overload` hides every inherited method of that name, so the walk stops
      after the level that declares it. Without this the parent's differently
      typed method stayed a candidate and could out-rank the descendant's:
      `l.Add(TFoo.Create(3))` on fgl's TFPGList<IFoo> bound
      TFPSList.Add(Item: Pointer) — a class instance IS compatible with
      Pointer — which dereferences its argument and stored the object's VMT
      word. The next read segfaulted.
      bug-p-a-descendant-method-does-not-hide-the-inherited-one }
    if UClsLevelHidesMeth(curr, name, lo) then Break;
    curr := UClsParent[curr];
  end;

  { nCand = 1 probes too. It used to short-circuit to FindUMethArity, which
    filters on ARITY alone, so the one-method case — most method calls in any
    program — never looked at its argument types at all: `c.M(p)` with
    `p: Pointer` and `M(const s: AnsiString)` compiled, while the identical free
    `FreeProc(p)` was refused, because the free path goes through MatchCall*
    which does check. Two resolvers for one concept and only one finished.
    Selection for the single candidate is UNCHANGED below (still
    FindUMethArity); the probe buys the REJECTION and nothing else.
    bug-p-a-single-candidate-method-call-does-not-check-its-argument-types }
  if nCand = 0 then
  begin
    Result := FindUMethArity(ci, name, nExplicitArgs);
    Exit;
  end;

  { 2. probe the argument types, then rewind. CurTok is Tokens[TokPos-1], so
       restoring TokPos to that index and calling Next reproduces it exactly. }
  savedCurIdx := TokPos - 1;
  if (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) then
    lp := TokPos
  else if CurTok.Kind = tkLParen then
    lp := TokPos - 1
  else
    lp := -1;

  { An `array of const` LITERAL or an open-array constructor written as `[...]`
    in an argument position. The probe parses arguments with ParseArgExpr, which
    has no parameter to bind against, so it reads the '[' as a SET LITERAL and
    dies on "set item must be one character" -- and Error halts, so the probe's
    own "unsupported arg shape" escape further down is never reached. Both
    conditions are required: a bare '[' really may be a set (that parses fine),
    and an open-array param really may be handed a variable (that parses fine
    too). It is the combination the probe cannot survive.

    Answered BEFORE the probe runs, the same way the NilPy `**` case is answered
    above -- a shape the probe cannot parse has to be settled before it, not
    after. Selection then falls back to arity, which is exactly what these calls
    had before the probe existed. Making the probe parameter-aware instead is
    refactor-p-the-overload-probe-cannot-see-the-argument-match-channels.
    regression-test-core-test-arrayofconst-to-method-b287 }
  { …and the NilPy unpack shapes, for the same reason and with no candidate
    test: `*xs` cannot be parsed by the probe under ANY signature. }
  if isNilPy and ArgListHasStarUnpack(lp) then
  begin
    Result := FindUMethArity(ci, name, nExplicitArgs);
    Exit;
  end;

  bmask := ArgListBracketElemMask(lp);
  if bmask <> 0 then
  begin
    ok := False;
    for c := 0 to nCand - 1 do
    begin
      pi := UMthProc_[cand[c]];
      for j := 1 to Procs[pi].ParamCount - 1 do
        if (j < MAX_PROC_PARAMS) and Procs[pi].Params[j].IsArray then ok := True;
    end;
    if ok then
    begin
      { Narrow on the bracket SLOTS before giving up on types. A candidate is
        viable here only if EVERY bracketed argument lands on an array
        parameter of its own; `Skip: Boolean` at that slot does not become
        legal because the overload set contains an array somewhere else.

        A tySet parameter at a bracket slot VETOES the narrowing outright --
        the `[...]` really may be a set there, and the same veto is what
        ParamIsVarRecArray applies on the parse side, so the two decisions
        cannot disagree about which spelling won.

        With exactly one survivor that is the answer, and it is the answer FPC
        gives. With none or several, fall through to the arity behaviour these
        calls had before the probe existed -- unchanged, deliberately: the
        probe still cannot PARSE a bracket argument, so it cannot rank one. }
      nBr := 0; brOnly := -1; vetoed := False;
      for c := 0 to nCand - 1 do
      begin
        pi := UMthProc_[cand[c]];
        okBr := True;
        for j := 0 to nExplicitArgs - 1 do
          if (j < 32) and ((bmask and (LongWord(1) shl j)) <> 0) then
          begin
            pj := 1 + j;
            if (pj >= MAX_PROC_PARAMS) or (pj >= Procs[pi].ParamCount) then
              okBr := False
            else
            begin
              if (not Procs[pi].Params[pj].IsArray) and
                 (Procs[pi].Params[pj].TypeKind = tySet) then vetoed := True;
              if not Procs[pi].Params[pj].IsArray then okBr := False;
            end;
          end;
        if okBr then begin Inc(nBr); brOnly := cand[c]; end;
      end;
      if (nBr = 1) and not vetoed then
      begin
        Result := brOnly;
        Exit;
      end;
      Result := FindUMethArity(ci, name, nExplicitArgs);
      Exit;
    end;
  end;

  nArgs := 0;
  for i := 0 to MAX_PROC_PARAMS - 1 do argIsNil[i] := False;
  for i := 0 to MAX_PROC_PARAMS - 1 do argKwTok[i] := -1;
  if (lp >= 0) and (nExplicitArgs > 0) then
  begin
    TokPos := lp + 1;
    Next;
    while (CurTok.Kind <> tkRParen) and (CurTok.Kind <> tkEOF) and
          (nArgs < MAX_PROC_PARAMS) do
    begin
      { NilPy `name=expr`: step over the keyword before probing, or the name is
        parsed as an expression and reported as an undefined variable — an
        OVERLOADED façade method could not be called with keyword arguments at
        all (`canvas.create_window((0,0), window=w)`). The name is RECORDED
        as well as stepped over. It used to be discarded here, on the ground
        that the probe "only needs the argument's TYPE; which parameter it
        binds to is settled later by PyKwArgIndex" -- true of what the loops
        below want to know, and false of how they INDEX, which is positional.
        See OverloadArgParamIdx. }
      if isNilPy and (CurTok.Kind = tkIdent) and
         (TokPos < TokCount) and (Tokens[TokPos].Kind = tkAssign) then
      begin
        argKwTok[nArgs] := TokPos - 1;   { CurTok IS the name; TokPos is its `=` }
        Next;   { the name }
        Next;   { the '=' }
      end;
      { ParseArgExpr, not ParseExpr: under NilPy an argument obeys PYTHON
        precedence and grammar, so a tuple argument `(0, 0)` is one expression
        here. Probed with the Pascal chain it stopped at the comma, typed the
        argument Integer and counted the tuple as two — which then ranked a
        `(x, y: Integer)` overload above the tuple one. }
      ParseArgExpr;
      argTk[nArgs] := IntToTypeKind(ASTTk[CurASTNode]);
      { the literal `nil`, for the single-candidate gate below. Read off the
        node here rather than through MatchArgNil[], which is the FREE path's
        side channel (pasparser_lval.inc:5704) and is not populated on this
        one — consulting it from here answered False for every nil and refused
        `SetOnKeyPtrCompare(nil)` across the whole fgl rung. }
      argIsNil[nArgs] := IsNilLiteralNode(CurASTNode);
      argNode[nArgs] := CurASTNode;   { for the channel fill below; the rewind restores
                                        TokPos only, so the node stays valid in the arena }
      if argTk[nArgs] = tyClass then
        argRec[nArgs] := ResolveNodeRec(CurASTNode)
      else
        argRec[nArgs] := REC_NONE;
      Inc(nArgs);
      if CurTok.Kind = tkComma then Next else Break;
    end;
  end;
  TokPos := savedCurIdx;
  Next;

  if nArgs <> nExplicitArgs then
  begin
    { probe disagreed with the token-level count (an unsupported arg shape) —
      keep the old behaviour rather than guess }
    Result := FindUMethArity(ci, name, nExplicitArgs);
    Exit;
  end;

  { 3. pick the candidate with the lowest total argument rank; ties keep the
       first-declared one (FPC's own tie-break). A candidate with any impossible
       argument is out. }
  best := -1;
  bestScore := 0;
  for c := 0 to nCand - 1 do
  begin
    pi := UMthProc_[cand[c]];
    base := 1;   { params[0] is always Self (metaclass for a class method) }
    ok := True;
    score := 0;
    for j := 0 to nArgs - 1 do
    begin
      pj := OverloadArgParamIdx(pi, base, j, argKwTok[j]);
      if (pj < base) or (pj >= MAX_PROC_PARAMS) then continue;   { abstain: see the helper }
      rank := OverloadArgRank(Procs[pi].Params[pj].TypeKind, argTk[j]);
      { CLASS-IDENTITY-aware refinement: two tyClass params tie at rank 0, so
        `Add(TJSONData)` vs `Add(TJSONObject)` picked whichever was declared
        first regardless of the argument's class. FPC picks the EXACT class,
        accepts an up-cast to an ancestor as merely compatible, and rejects an
        unrelated class. Both recs must be known — REC_NONE (nil, untagged)
        keeps the kind-level rank. (bug-pascal-overload-impl-decl-signature-match) }
      if (rank < 3) and (Procs[pi].Params[pj].TypeKind = tyClass) and
         (argTk[j] = tyClass) then
      begin
        pRec := ProcParamRecId[pi * MAX_PROC_PARAMS + pj];
        aRec := argRec[j];
        if (pRec >= REC_UCLASS_BASE) and (aRec >= REC_UCLASS_BASE) and (pRec <> aRec) then
        begin
          upDist := 0;
          upCurr := aRec - REC_UCLASS_BASE;
          while (upCurr >= 0) and (upCurr <> pRec - REC_UCLASS_BASE) do
          begin
            Inc(upDist);
            upCurr := UClsParent[upCurr];
          end;
          if upCurr < 0 then rank := 3        { unrelated class: impossible }
          else rank := 2;                     { ancestor up-cast: exact wins }
        end;
      end;
      { ...and the ELEMENT-aware refinement, the same shape as the class one
        above and for the same reason: two tyPointer params tie at rank 0, so
        `m(p: PChar)` and `m(p: PWideChar)` were picked by declaration order and
        a PWideChar argument ran the PChar body. Rank 2, not 3 -- the conversion
        is real and must stay available when it is the only candidate; what it
        must not do is beat an exact match. Covers the managed-string WIDTH
        twin as well, which ties the same way once WideString is not an alias.
        bug-p-a-pchar-and-a-pwidechar-parameter-are-one-overload }
      if (rank = 0) and OverloadArgElemMismatch(pi, pj, argNode[j], argTk[j]) then
        rank := 2;
      if rank >= 3 then ok := False;
      score := score + rank;
    end;
    if ok and ((best < 0) or (score < bestScore)) then
    begin
      best := cand[c];
      bestScore := score;
    end;
  end;

  { The single candidate IS the method; the only question the probe answers for
    it is whether its arguments are possible. Rank 3 is `not TypesCompatible`,
    the same predicate the free-call path rejects on, so this is reaching the
    shared answer rather than inventing a stricter one. }
  if nCand = 1 then
  begin
    { An ALLOWLIST, and deliberately a narrow one.

      The obvious gate — refuse whenever TypesCompatible says no — is UNSOUND
      here, and measuring it is the only reason that is known. Four distinct
      classes of legal call were refused, each traced to a channel this
      speculative probe does not have and the free-call path does:

        `CreateFmt('%s', [s])`      an `array of const` parameter, whose
                                    TypeKind is its ELEMENT kind  (MatchArgArray)
        `slist.Add('test', l)`      a generic type parameter, tyUnknown at the
                                    declaration                   (7 conformance
                                    programs and tgeneric9 between them)
        `SetOnKeyPtrCompare(nil)`   nil binds any reference-shaped parameter
                                                                  (MatchArgNil)
        `inherited Sort(ItemPtrCompare)`  a bare routine name as a procedural
                                    value, which the probe types as neither

      Each of those five side channels in pasparser_lval.inc exists because a
      previous agent hit the same wall: the KIND pair is not a sound predicate
      on its own. A denylist of exemptions would only be as complete as the
      corpora I happened to run, and an unsound gate that refuses a legal
      program is strictly worse than the looseness it replaces — the ticket
      notes the looseness is not a wrong answer, only a hidden one.

      So: refuse ONLY a reference-shaped argument bound to a string or numeric
      parameter. That is the shape the ticket was filed about (a `Pointer`
      reaching a `const AnsiString`, printing empty today and crashing the day
      the coercion is not benign), it cannot arise from any of the four classes
      above, and everything else abstains ON PURPOSE.

      Making the full check sound needs the probe to build an AN_ARG chain and
      run the free path's own populate-and-match, which means extracting that
      population out of pasparser_lval.inc into a helper both callers share.
      That is the real fix and it is a refactor, not this. }
    pi := UMthProc_[cand[0]];

    { THE ARGUMENT-MATCH SIDE CHANNELS, filled here so this gate can reach the
      free path's own answer instead of re-deriving a weaker one from kinds.
      Step 2 of
      refactor-p-the-overload-probe-cannot-see-the-argument-match-channels.

      WHERE this sits is the whole safety argument, so it is stated rather than
      left to be re-derived. The channels are GLOBALS with no per-call
      lifetime, and this probe runs NESTED inside argument parsing -- a method
      call in an argument position (`a.M(b.N(x), y)`) runs a second probe
      inside the first one's parse loop. Filling from that loop would therefore
      let the inner probe overwrite the outer one's channels before the outer
      one had read them.

      So the fill happens HERE, after `TokPos := savedCurIdx; Next`, in a
      window that was measured to contain no parsing at all: from the rewind to
      the end of this function there is no Parse*, Next, Expect, Eat, Rewind*
      or recursive probe call. That is the same discipline
      MatchCallDelphiProcAddr keeps for its own fill -- fill, match, retry, all
      with the token stream untouched -- and it is the reason the nodes are
      carried in argNode[] rather than read off CurASTNode in the loop.

      Indexed by the PARAMETER slot pj, not by the argument slot j: Params[0]
      is Self on every method, so the channels and MatchArgRecMismatch must
      agree about which slot they mean, and the predicate reads Params[j] and
      MatchArg*[j] with ONE j. Under NilPy keywords OverloadArgParamIdx makes
      that mapping non-identity, which is the other reason not to assume j.

      Cleared again below: no caller of MatchProcCall* may be left reading a
      fill that was made for a different argument list, which is the defect
      fixed in PyParseVariadicMinMax. }
    for j := 0 to nArgs - 1 do
    begin
      pj := OverloadArgParamIdx(pi, 1, j, argKwTok[j]);
      if (pj >= 1) and (pj < MAX_PROC_PARAMS) then
        FillMatchArgChannelsAt(pj, argNode[j], argTk[j]);
    end;
    MatchArgRecValid := True;
    MatchArgAliasValid := True;
    MatchArgNilValid := True;
    MatchArgScalarValid := True;
    MatchArgArrayValid := True;
    MatchArgElemValid := True;
    MatchArgProcAddrValid := True;

    ok := True;
    { A NilPy `*args` / `**kwargs` METHOD HAS NOT BEEN PACKED YET, so its
      arguments are not in its parameter slots and comparing them there asks a
      question about the wrong pairing. `def take(self, a, *rest, **kw)` called
      as `b.take(1, 2, 3)` presents three Integers; after PyPackStarArgs the
      callee sees `a`, a LIST and a DICT. This check runs BEFORE that packing --
      the packing is done by the NilPy call site once the argument list is
      parsed -- so arguments 2 and 3 were matched against the list and dict
      parameters and refused: "no overload of take matches these arguments",
      test_nilpy_star_methods_and_targets, an auto-filed Track T RED.

      Skipped rather than made precise on purpose. The pre-pack argument list
      and the post-pack parameter list are DIFFERENT SHAPES, not a shifted
      version of one shape, so there is no j-to-pj mapping this loop could use;
      OverloadArgParamIdx answers about the declared slots, which is right for
      every caller that has already packed and wrong for this one. Restoring
      the pre-a79ea9af6 answer for exactly these procs is the narrow fix, and
      the wide one -- checking after packing -- belongs where the packing is.

      NOT A REGRESSION IN THE GATE'S OWN TERMS: a79ea9af6 measured zero change
      across the Pascal corpus, conformance and fgl, and NilPy is in none of
      those three. A green scoped to the populations it was measured on.
      regression-test-core-test-nilpy-star-methods-and-targets-2 }
    if (ProcPyStarIdx[pi] >= 0) or (ProcPyKwIdx[pi] >= 0) then
      ok := True
    else
    for j := 0 to nArgs - 1 do
    begin
      pj := OverloadArgParamIdx(pi, 1, j, argKwTok[j]);
      if (pj >= 1) and (pj < MAX_PROC_PARAMS) then
      begin
        { The shared answer, reached rather than re-derived. This is the
          predicate the FREE path refuses on, and the asymmetry it removes was
          silent: `d.One(ia)` with `One(v: Integer)` and `ia: array[0..2] of
          Integer` compiled and printed the array's ADDRESS (4306992), while
          the identical free `One(ia)` was refused -- because the free path
          fills MatchArgArray and this probe could not. FPC 3.2.2 refuses both:
          "Incompatible type for arg no. 1: Got "TIA", expected "LongInt"".
          Measured on pin v403 too, so it is not a regression, it is the gap
          this ticket was filed about.
          bug-p-an-array-argument-binds-a-scalar-overload, method spelling. }
        if MatchArgRecMismatch(pi, pj, argTk[j]) then ok := False;
        if Procs[pi].Params[pj].IsArray then continue;
        if ProcParamUntyped[pi * MAX_PROC_PARAMS + pj] then continue;
        if argIsNil[j] then continue;
        { The UNION of what MatchProcCall's phases accept, not the one phase
          that asks about types. The free path reaches the looser answers by
          falling through to a later phase; this probe has rewound its token
          stream and gets one question, so it has to ask the union directly. }
        if not MatchParamAccepted(pi, pj, argTk[j]) then
          ok := False;
      end;
    end;
    { Nothing downstream may read a fill made for THIS argument list. }
    MatchArgProcAddrValid := False;
    MatchArgRecValid := False;
    MatchArgAliasValid := False;
    MatchArgNilValid := False;
    MatchArgScalarValid := False;
    MatchArgArrayValid := False;
    MatchArgElemValid := False;
    if not ok then
      Error('no overload of ' + name + ' matches these arguments');
    Result := FindUMethArity(ci, name, nExplicitArgs);
    Exit;
  end;

  if best < 0 then best := FindUMethArity(ci, name, nExplicitArgs);
  Result := best;
end;

{ `Read` / `Write` / `Readln` / `Writeln` at the CURRENT token, naming a METHOD of
  the enclosing class rather than the console intrinsic. The four names lex as
  intrinsic keyword tokens (paslexer.inc), so every position that expects an
  identifier has to ask this before dispatching -- pasparser_name.inc already
  re-admits them in member-NAME and method-NAME position, which is why the
  declaration and the qualified calls `Self.Read(b,c)` / `s.Read(b,c)` work.

  ONE predicate with two callers, deliberately. The statement arm
  (pasparser_stmt.inc, tkwriteln/tkwrite/tkReadln/tkRead) grew this test first
  for `bug-bare-read-write-in-method-hits-intrinsic`, and ParseFactorCore was
  never given it -- so `Read(B,C)` was a working STATEMENT and an
  `expected expression` in any EXPRESSION, which is the exact shape
  devdocs/dev/normalise-dont-special-case.md warns about: the second path is the
  one that stays broken. Widening it in one place now widens it for both.

  GATED ON A FOLLOWING `(` so a bare console `Write` / `Writeln` keeps the
  intrinsic path, and ARITY-GATED so a call no member could accept falls through
  to the intrinsic rather than binding to a member that cannot take it -- the
  arity gate is not optional politeness, it is
  bug-p-a-write-call-inside-a-method-named-write-binds-to-the-member-whatever-its-arity,
  where the copy that asked FindUMeth (name alone) wrote an empty file and
  returned True on x86-64 while refusing to build on three other targets. }
{ Is the token at index `ti` a BARE handle for record type `recId`? One core for
  three callers -- TextIOFileSym and FileIOFileSym below read it at the CURRENT
  token, and the call-site router reads it one token PAST an unconsumed `(`.
  The two CurTok-shaped predicates were byte-for-byte the same function with one
  record name changed, and a third copy taking an index would have been the
  point at which they started to drift.

  BARE means the next token is `,` or `)` -- not `f.field` / `f[i]`, since
  `WriteLn(f.Name)` is a console write of the string field, not a file write.
  SymOwnRecOf rather than the type KIND, so `var f: array[0..1] of Text` cannot
  be read as a handle: an array of Text carries TypeKind = tyRecord, and the old
  spelling said no only because AllocArray clears RecName.
  audit-a-typekind-tyrecord-is-not-a-guard-against-an-array-symbol }
function IOHandleSymAt(ti, recId: Integer): Integer;
var vidx: Integer;
begin
  Result := -1;
  if recId = REC_NONE then Exit;
  if (ti < 0) or (ti >= TokCount) then Exit;
  if Tokens[ti].Kind <> tkIdent then Exit;
  if not ((ti + 1 < TokCount) and (Tokens[ti + 1].Kind in [tkComma, tkRParen])) then Exit;
  vidx := FindSym(GetTokenStr(ti));
  if (vidx >= 0) and (SymOwnRecOf(vidx) = recId) then
    Result := vidx;
end;

{ Does the call starting at the CURRENT token pass a file handle as its FIRST
  argument? Asked with the routine name still unconsumed and `(` at Tokens[TokPos],
  so the first argument is Tokens[TokPos + 1].

  This is what decides `Write(f, x)` between the I/O intrinsic and a same-named
  METHOD of the enclosing class. No ordinary member takes a Text or a FileRec in
  first position by accident, so a file handle there is unambiguous -- whereas
  ARITY is not: a 2-parameter `Write(const Buffer; Count: Longint)` accepts
  `Write(f, 'payload')` on arity alone, and `const Buffer` is an untyped formal
  that accepts anything, so the type-directed overload probe does not rescue it.
  bug-p-a-two-argument-write-to-a-text-file-inside-a-class-with-a-write-member-silently-writes-nothing }
function CallFirstArgIsIOHandle: Boolean;
begin
  Result := False;
  if (TokPos >= TokCount) or (Tokens[TokPos].Kind <> tkLParen) then Exit;
  Result := (IOHandleSymAt(TokPos + 1, IsRecordType('text')) >= 0) or
            (IOHandleSymAt(TokPos + 1, IsRecordType('filerec')) >= 0);
end;

function IntrinsicNamesSelfMethodHere: Boolean;
begin
  Result := False;
  if not (CurTok.Kind in [tkRead, tkwrite, tkReadln, tkwriteln]) then Exit;
  if (CurProc < 0) or (CurSelfClass < REC_UCLASS_BASE) then Exit;
  if Tokens[TokPos].Kind <> tkLParen then Exit;
  { A FILE HANDLE in first position means the INTRINSIC, whatever a member's
    arity says. Arity alone is not enough and the gap was a silent wrong value:
    a 2-parameter `Write(const Buffer; Count: Longint)` accepts
    `Write(f, 'payload')` on arity, `const Buffer` is an untyped formal that
    accepts anything so the type-directed probe does not reject it either, and
    the call bound to the member -- file created, left EMPTY, exit 0. fpc 3.2.2
    refuses that source outright; we did neither, which is the one outcome
    nobody can act on.
    A member that genuinely WANTS a handle first is still reachable by
    qualifying (`Self.Write(f, n)`) -- the same escape hatch fpc makes you use
    to reach the intrinsic, pointed the other way. }
  if CallFirstArgIsIOHandle then Exit;
  Result := FindUMethArityStrict(SelfMemberCi(CurTok.SVal), CurTok.SVal,
                                 CountCallArgsAhead) >= 0;
end;

{ The same question about a GLOBAL routine: does a user-declared `Read` / `Write`
  / `Readln` / `Writeln` at unit or program level shadow the console intrinsic
  here? FPC's rule is plain shadowing -- measured against fpc 3.2.2, a program
  declaring `function Write(const s: string): Integer` has `Write('abcd')`
  return 4, the user routine, not a console write.

  SIBLING OF IntrinsicNamesSelfMethodHere ABOVE, carrying its three gates
  verbatim and for its reasons:

    * a following `(`, so a bare console `Write` / `Writeln` is untouched;
    * NOT a file handle in first position -- `Write(f, x)` is the intrinsic
      whatever a routine's arity says, which is
      bug-p-a-two-argument-write-to-a-text-file-inside-a-class-with-a-write-member-silently-writes-nothing
      pointed at free routines;
    * ARITY, so a console `Write(a, b, c)` in a program that also declares a
      one-argument `Write` still reaches the intrinsic instead of binding to a
      routine that cannot take it.

  THIS PREDICATE IS FALSE ON EVERY TREE THAT EXISTS TODAY, which is why the
  declaration widening in pasparser_proc.inc can land beside it: no unit in
  lib/rtl or the compiler can DECLARE such a routine (the header was refused),
  so FindProcArity cannot match one until somebody writes it. The behaviour
  change is scoped to source that is refused outright today.

  The METHOD predicate is asked first at both dispatch sites: an unqualified
  name inside a method means the member, and a global of the same name is what
  `Self.` exists to disambiguate away from -- the same precedence FPC has. }
function IntrinsicNamesGlobalRoutineHere: Boolean;
begin
  Result := False;
  if not (CurTok.Kind in [tkRead, tkwrite, tkReadln, tkwriteln]) then Exit;
  if (TokPos >= TokCount) or (Tokens[TokPos].Kind <> tkLParen) then Exit;
  if CallFirstArgIsIOHandle then Exit;
  Result := FindProcArity(CurTok.SVal, CountCallArgsAhead) >= 0;
end;

{ Does ANY constructor of class ci take an `array of const` / open array at explicit argument
  position argIdx (0-based, Self excluded)? The `TFoo.Create(args)` path parses its arguments
  BEFORE it picks the overload -- it has to, since it ranks the overloads by argument type --
  so it cannot ask the chosen signature whether a '[' is an array-of-const literal or a set.
  Asking whether ANY candidate wants one there is enough: `[` in that position has no other
  meaning for a constructor argument.

  Without this, `TJSONArray.Create([0, 'string', ...])` (fcl-json) parsed the literal as a SET
  and died on "set item must be one character" -- or, with an overloaded ctor, quietly picked
  the parameterless one and passed garbage. }
function ClassCtorWantsVarRecAt(ci, argIdx: Integer): Boolean;
var mi, mpi, base, cnt, k: Integer;
begin
  Result := False;
  if (ci < 0) or (ci >= UClsCount) then Exit;
  base := UClsMBase[ci];
  cnt := UClsMCount[ci];
  for k := 0 to cnt - 1 do
  begin
    mi := base + k;
    if not UMthIsCtor[mi] then continue;
    mpi := UMthProc_[mi];
    if mpi < 0 then continue;
    if (argIdx + 1) < Procs[mpi].ParamCount then
      if Procs[mpi].Params[argIdx + 1].IsArray then
      begin
        Result := True;
        Exit;
      end;
  end;
end;

function FindUCtorOverloadArgs(ci: Integer; argsHead: Integer): Integer;
{ Constructor overload selection from the ALREADY-PARSED argument list.

  Unlike a method call, a ctor's args are parsed BEFORE the ctor is chosen, so the
  argument types are sitting on the AST and no token probe is needed. Picking the
  first `Create` by name (the old behaviour) meant an overloaded ctor set always
  resolved to whichever Create was declared first — so `TFoo.Create('x')` against a
  parameterless first Create died with "too many arguments", and a same-arity set
  silently ran the wrong body. Same ranking as FindUMethOverloadAhead. }
const MAX_OVL_CAND = 32;
var
  cand: array[0..MAX_OVL_CAND-1] of Integer;
  argTk: array[0..MAX_PROC_PARAMS-1] of TTypeKind;
  argNodeC: array[0..MAX_PROC_PARAMS-1] of Integer;   { the argument NODES, for the element-aware tie-break }
  nCand, nArgs, i, j, c, pi, want, curr, mbase, cnt, best: Integer;
  score, bestScore, rank, argSeq: Integer;
  ok: Boolean;
  lo, nm: AnsiString;
begin
  nm := 'create';
  lo := ULower(nm);

  nArgs := 0;
  argSeq := argsHead;
  while (argSeq <> -1) and (nArgs < MAX_PROC_PARAMS) do
  begin
    argTk[nArgs] := IntToTypeKind(ASTTk[ASTLeft[argSeq]]);
    { the NODE too, not only its kind: the element-aware tie-break below asks
      about a managed string's width and a typed pointer's pointee, and neither
      is on the kind. Kept here rather than re-walked, because this loop is the
      one place the chain and the index line up. }
    argNodeC[nArgs] := ASTLeft[argSeq];
    Inc(nArgs);
    argSeq := ASTRight[argSeq];
  end;

  nCand := 0;
  curr := ci;
  while curr >= 0 do
  begin
    mbase := UClsMBase[curr];
    cnt   := UClsMCount[curr];
    i := 0;
    while i < cnt do
    begin
      if UMemberNameMatch(UMthNOff[mbase + i], UMthNLen[mbase + i], curr, nm, lo) then
      begin
        want := nArgs + 1;   { Self at 0 for every method, class methods included }
        if ProcArityMatches(UMthProc_[mbase + i], want) and (nCand < MAX_OVL_CAND) then
        begin
          cand[nCand] := mbase + i;
          Inc(nCand);
        end;
      end;
      Inc(i);
    end;
    { A Python __init__ REPLACES the base's — the type's own is what
      `Sub(arg)` runs, never an inherited constructor that happens to accept the
      same argument better. Ranking by argument TYPE picked the base's whenever
      the subclass's parameter was unannotated (i.e. a variant), so
      `class SettingsEditor(tk.Frame)` constructed a bare Frame and the
      subclass's body never ran. Pascal keeps the inherited-ctor lookup: FPC
      really does let `TSub.Create` resolve to the base's. }
    if isNilPy and (nCand > 0) then Break;
    curr := UClsParent[curr];
  end;

  if nCand = 0 then
  begin
    Result := FindUMeth(ci, 'create');
    Exit;
  end;

  best := -1;
  bestScore := 0;
  for c := 0 to nCand - 1 do
  begin
    pi := UMthProc_[cand[c]];
    ok := True;
    score := 0;
    for j := 0 to nArgs - 1 do
    begin
      rank := OverloadArgRank(Procs[pi].Params[1 + j].TypeKind, argTk[j]);
      { see the twin site in FindUMethOverloadAhead: two tyPointer (or two
        tyAnsiString) parameters tie at rank 0, and the part that separates them
        is not on the kind. }
      if (rank = 0) and OverloadArgElemMismatch(pi, 1 + j, argNodeC[j], argTk[j]) then
        rank := 2;
      if rank >= 3 then ok := False;
      score := score + rank;
    end;
    if ok and ((best < 0) or (score < bestScore)) then
    begin
      best := cand[c];
      bestScore := score;
    end;
  end;

  if best < 0 then best := cand[0];
  Result := best;
end;

function IsVarArgLvalueCast(n: Integer): Boolean;
{ FPC "variable typecast" as a var/out argument: `Cardinal(FTokenLength)` —
  an AN_PTR_CAST over a plain lvalue. The address is the operand's
  (IRLowerAddress peels the cast). Pascal Script's ParseToken call. }
begin
  Result := (n >= 0) and (ASTKind[n] = AN_PTR_CAST) and (ASTLeft[n] >= 0) and
            ((ASTKind[ASTLeft[n]] = AN_IDENT) or (ASTKind[ASTLeft[n]] = AN_FIELD) or
             (ASTKind[ASTLeft[n]] = AN_INDEX) or (ASTKind[ASTLeft[n]] = AN_DEREF));
end;

function PureDesignator(n: Integer): Boolean;
{ A node that can be re-evaluated with no observable effect: a variable, a field
  or element of one, a dereference, or a cast over any of those. Callers that
  CloneAST an operand into several places need this — a call or an operator
  expression would run more than once.

  A cast recurses into its operand rather than being accepted outright: `(f() as
  T)` is a cast, and re-evaluating it re-calls f(). An `as` cast also re-runs its
  runtime type check per copy, which is wasteful but not observable. }
var depth: Integer;
begin
  PureDesignator := False;
  depth := 0;
  while (n >= 0) and (depth < 32) do
  begin
    if (ASTKind[n] = AN_IDENT) or (ASTKind[n] = AN_FIELD) or
       (ASTKind[n] = AN_INDEX) or (ASTKind[n] = AN_DEREF) then
    begin
      PureDesignator := True;
      Exit;
    end;
    if (ASTKind[n] = AN_CLASS_CAST) or (ASTKind[n] = AN_PTR_CAST) or
       (ASTKind[n] = AN_AS_CAST) then
    begin
      n := ASTLeft[n];
      Inc(depth);
    end
    else
      Exit;
  end;
end;

function BuiltinFreeHere(node, recId: Integer; const fieldName: AnsiString;
                        afterNameTok: Integer): Boolean;
{ Is this `<designator>.Free;` — the built-in TObject.Free on a class instance
  with no user-declared Free — reached through a general member-access path?

  ParseStatementAST has recognised `obj.Free;` for a BARE IDENTIFIER for a long
  time, by matching the literal token shape `ident . Free ;`. Anything with a
  selector in front of it — `a[0].Free`, `d[0].Free`, `r.f.Free`, `h.f.Free`,
  `(o as T).Free` — misses that shape, falls through to ordinary member lookup,
  and dies as `"Free": no such member on this record/class`, because Free is
  not a member of any class the frontend knows. `FList[i].Free` is everyday
  Pascal, so that was a real hole
  (bug-p-free-and-destroy-only-work-on-a-simple-variable).

  The conditions, and why each is needed:
    - the base is a user CLASS, not a record (records are not freed);
    - the class declares no `Free` of its own — a user method named Free wins,
      exactly as the bare-identifier case already decides;
    - the token after the name ends a statement, so this is `x.Free;` and not
      a value position or a call with arguments. Same guard the existing case
      uses;
    - the base is a plain DESIGNATOR. GenMakeFreeObjectExpr CloneASTs its
      operand up to three times (nil test, Destroy, FreeMem), so a
      side-effecting base would run three times. An ident/field/index/deref/cast
      chain is a re-read, which is free.

  Destroy is deliberately not included: `Free` is the nil-guarded wrapper, and
  desugaring a direct `.Destroy` to the same thing would change its meaning. }
begin
  BuiltinFreeHere :=
    (node >= 0) and (recId >= REC_UCLASS_BASE) and
    (not UClsIsRecord[recId - REC_UCLASS_BASE]) and
    CaseEqual(fieldName, 'Free') and
    (FindUMeth(recId - REC_UCLASS_BASE, 'Free') < 0) and
    (afterNameTok < TokCount) and
    (Tokens[afterNameTok].Kind in [tkSemicolon, tkEnd, tkElse]) and
    PureDesignator(node);
end;

procedure RequireValueHasMembers(recId: Integer; const fieldName: AnsiString);
{ The hole one step to the LEFT of RequireRecMember: recId = REC_NONE, i.e. the
  receiver is not a record or class AT ALL. RecFieldType's not-found default
  fires the same way, so the fallthrough read the VALUE'S OWN BYTES at offset 0
  and typed them tyInteger. With a `type helper for string` in scope,
  `s.Twice.Twice` printed 24929 — the two bytes of 'aa' as an Int32 — and
  `s.Twice.IsEmpty` printed 24929 as well, the trailing member silently dropped,
  because a helper method's return type resets recId to REC_NONE and the
  selector loop then kept going. `(F).Twice` printed 113, ord('q').
  bug-p-a-member-on-a-computed-value-silently-reads-the-values-own-bytes

  SEPARATE from RequireRecMember, and called from only the two COMPUTED-receiver
  sites, deliberately. Folding it into RequireRecMember put it on all four
  member-dispatch copies, and two of those are DEREF sites where REC_NONE is
  normal and harmless: `arr[i]^.Field` over an array-of-pointer-to-record leaves
  the parser's running recId at REC_NONE while the field still resolves
  correctly downstream, so the shared arm refused valid code
  (test_arr_of_ptr_elemrec_b354, regression at 10dada0b7689). REC_NONE means
  "no record id HERE"; only on a computed value does it also mean "and there
  never will be one". }
begin
  if recId = REC_NONE then
    ErrorRecover('"' + fieldName + '": this value has no members (only records, '
                 + 'classes, interfaces and variants do)');
end;

procedure RequireRecMember(recId: Integer; const fieldName: AnsiString);
{ Guard on the AN_FIELD fallthrough paths: a member name that resolved to
  NOTHING on a user record/class (no field, no method/property/class var —
  those all dispatched earlier) must ERROR. Without this, RecFieldType's
  not-found default (tyInteger at offset 0) let an undefined field COMPILE
  and read garbage (bug-pascal-undefined-field-on-empty-record-compiles).
  Builtin records keep the lax path — their field names are compiler-authored. }
begin
  if (recId >= REC_UCLASS_BASE) and
     (FindUField(recId - REC_UCLASS_BASE, fieldName) < 0) then
    { RECOVERABLE: the caller then falls into RecFieldType's not-found default
      (tyInteger at offset 0) and carries on reading the file, which is exactly
      what used to happen SILENTLY. Reporting it is what changed; nothing is
      emitted, because the driver halts on ErrCount before any output.
      feature-a-error-does-not-halt-so-a-parse-can-be-speculative }
    ErrorRecover('"' + fieldName + '": no such member on this record/class');
end;

function ParamIsConstVariant(pi, slot: Integer): Boolean;
{ True for a `const v: Variant` parameter — by-ref internally (boxed at
  IRLowerCallArg), but NEVER a genuine var-binding target, so an expression may
  bind to it. The by-ref argument VALIDATOR two call sites up already treats it
  that way; ByRefArgStartsExpression below needs the same fact to stop reading
  `obj.method(a + b)` as a bare lvalue.
  bug-a-const-variant-arg-expression-fails-outside-pyexprmode }
begin
  Result := (pi >= 0) and (slot >= 0) and (slot < MAX_PROC_PARAMS) and
            (slot < Procs[pi].ParamCount) and
            (Procs[pi].Params[slot].TypeKind = tyVariant) and
            ProcParamIsConst[pi * MAX_PROC_PARAMS + slot];
end;

function ByRefArgStartsExpression(constVariantParam: Boolean): Boolean;
var bx, bd: Integer;
{ True when the next by-ref/array argument cannot be a bare variable lvalue:
  not an ident at all, or an ident that names no symbol and is followed by
  '(' — a type-cast lvalue like `PChar(s)^` / `Pointer(p)^` passed to a
  var/untyped parameter (bug-cast-deref-as-varparam-arg). Such args go
  through ParseExpr, whose cast/deref path yields an addressable node. }
begin
  if CurTok.Kind <> tkIdent then begin Result := True; Exit; end;
  { NilPy: a `const` parameter is by-ref, so a Python argument that merely
    STARTS with a name — `xs.append(a + b)` — was parsed as a bare lvalue and
    the parser stopped at the operator ("unexpected token" on the second
    operand). An ident followed by anything that continues an EXPRESSION rather
    than an lvalue is therefore an expression. The lvalue continuations are
    '.', '[' and '^'; ',' and ')' end a bare-variable argument.

    Gated on PyExprMode: Pascal's var-parameter binding must keep passing a
    bare variable by reference, and that path is under the self-host gate.
    Literal operands already worked, which is what hid this — only two NAMED
    operands hit it (bug-nilpy-expression-arg-to-a-const-param).

    ...and on constVariantParam, which lifts the same logic into PASCAL source
    for a `const Variant` parameter only. That parameter is by-ref internally
    but is never a genuine var-binding target, so there is no bare-lvalue
    requirement to protect — `pair.append(start + i)` failed in a plain Pascal
    unit (pylib.pas's own body) for exactly this reason. Genuine var/out/array
    by-ref params still require the gate.
    bug-a-const-variant-arg-expression-fails-outside-pyexprmode }
  if PyExprMode or constVariantParam then
  begin
    { Skip the whole lvalue CHAIN — `self._tok_quote_char`, `a.b[i].c` — and
      judge by what FOLLOWS it. One-token lookahead is not enough: uforth's
      operand is a field chain, so the next token is '.' either way. }
    bx := TokPos;
    while bx < TokCount do
    begin
      if (Tokens[bx].Kind = tkDot) and (bx + 1 < TokCount) and
         (Tokens[bx + 1].Kind = tkIdent) then
        bx := bx + 2
      else if Tokens[bx].Kind = tkCaret then
        Inc(bx)
      else if Tokens[bx].Kind = tkLBrack then
      begin
        bd := 0;
        while bx < TokCount do
        begin
          if Tokens[bx].Kind = tkLBrack then Inc(bd)
          else if Tokens[bx].Kind = tkRBrack then
          begin
            Dec(bd);
            if bd = 0 then begin Inc(bx); Break; end;
          end;
          Inc(bx);
        end;
      end
      else Break;
    end;
    if (bx < TokCount) and not (Tokens[bx].Kind in [tkComma, tkRParen]) then
    begin
      Result := True;
      Exit;
    end;
    { ...and a bare name that ENDS the argument (`obj.m(zero)`) is an expression
      when it names no symbol but DOES name a parameterless — or all-defaulted —
      function. It is a call producing a value, and a `const Variant` parameter
      takes values, so there is nothing to bind by reference.

      Without this the name fell to the bare-lvalue arm, reached ParseLValueAST
      with FindSym = -1, and came out as `undefined variable (zero)` — a
      diagnostic pointing at the ARGUMENT, naming a perfectly good function
      undefined, while the identical call through a FREE function compiled.

      Measured boundary: only METHOD + `const Variant` + a BARE name failed.
      By-value Variant, `const AnsiString`, and an explicit `zero()` (the `(`
      reaches the clause below) all compiled already.

      GATED, and the gate is load-bearing — this was tried ungated and it is a
      regression, not a generalisation. The method by-ref path has no validator
      that rejects a non-lvalue: it relies on this predicate answering False to
      force the bare-lvalue parse. Ungating therefore let a call RESULT bind to
      a genuine `var` parameter and the program COMPILED, where fpc says "Can't
      take the address of constant expressions". A wrong diagnostic beats a
      silent accept.
      bug-p-a-parameterless-function-is-undefined-as-a-method-call-argument }
    if FindSym(CurTok.SVal) < 0 then
    begin
      bd := FindProc(CurTok.SVal);
      if (bd >= 0) and Procs[bd].IsFunc and
         ((Procs[bd].ParamCount = 0) or
          ProcParamHasDefault[bd * MAX_PROC_PARAMS + 0]) then
      begin
        Result := True;
        Exit;
      end;
    end;
  end;
  Result := (FindSym(CurTok.SVal) < 0) and (TokPos < TokCount) and
            (Tokens[TokPos].Kind = tkLParen);
end;

function OwnFieldBeatsSym(idx: Integer; const nm: AnsiString): Integer;
{ FPC scope order inside a method body: the enclosing class's OWN field beats
  any unit-level name of the same spelling (const, var, typed const); only a
  genuine local or parameter shadows the field. A name that bound to a unit
  symbol is demoted to "unbound" here, which is what lets the implicit-Self
  field paths — they all fire on `idx < 0` — resolve it instead.

  Every bare-name resolution site must call this, or reads and writes disagree:
  an earlier attempt that changed only the assignment path made `s := v` reach
  the field while `s[1]` still read the const, which is worse than a uniform
  error. Same rule the bare class-CONST path already implements.
  bug-unit-const-shadows-a-field. }
begin
  Result := idx;
  if idx < 0 then Exit;
  if Syms[idx].Kind in [skLocal, skParam] then Exit;
  { needs a real Self to hang the field off: an instance/advanced-record method,
    never a class procedure (no Self) or a plain routine. }
  if (CurProc < 0) or (CurSelfClass < REC_UCLASS_BASE) then Exit;
  if Procs[CurProc].ParamCount <= 0 then Exit;
  if FindUField(CurSelfClass - REC_UCLASS_BASE, nm) >= 0 then Result := -1;
end;
