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
begin
  { `class operator TPt.+ (const a, b: TPt): TPt;` — FPC's ADVANCED-RECORD operator syntax.
    Both the `class` prefix and the `TRec.` qualifier are accepted and dropped: pxx keys an
    operator on its OPERAND TYPES, not on an owning type, so the qualifier carries no
    information the signature does not already have. A plain top-level
    `operator + (a, b: TPt): TPt` was already supported and means exactly the same thing —
    this just lets FPC's spelling through to the same machinery. }
  if CurTok.Kind = tkClass then Next;
  Next; { consume 'operator' }
  if (CurTok.Kind = tkIdent) and (TokPos < TokCount) and (Tokens[TokPos].Kind = tkDot) then
  begin
    Next;   { the TRec qualifier }
    Next;   { the dot }
  end;
  opKind := CurTok.Kind;
  opKey := -1;
  if opKind in [tkPlus, tkMinus, tkStar, tkSlash, tkDiv, tkMod, tkEq, tkNeq, tkLt, tkLe, tkGt, tkGe] then
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
    else if CaseEqual(CurTok.SVal, 'copy') then opKey := OPK_COPY;
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

  { Advance into the injected 'function/procedure' token }
  Next;
  ParseSubroutine;
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
    { FPC forbids conversion operators between two BUILT-IN ordinal types
      (toperator90's Explicit LongInt -> Boolean %fail): a standard
      conversion already exists. A string/record/class/float on either side
      makes it a legal user conversion (tgenfunc8's LongInt <-> String). }
    if ((opKey = Ord(tkAssign)) or (opKey = OPK_EXPLICIT)) and
       (recId = REC_NONE) and TypeIsOrdinal(IntToTypeKind(opTypeKind)) and
       TypeIsOrdinal(Procs[procIdx].RetType) then
      Error('impossible operator overload: a standard conversion between these types exists');
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
  { A SECOND := / Implicit / Explicit from the same source type to a result of
    the same TYPE KIND is ambiguous at every use site — String[80] vs
    String[90] targets are indistinguishable (toperator92; toperator95 splits
    the same pair across a class operator and a global one). Distinct result
    kinds (-> Integer vs -> String) remain legal. }
  if (opKey = Ord(tkAssign)) or (opKey = OPK_EXPLICIT) then
  begin
    dupPi := FindOpOverload(opKey, opTypeKind, recId);
    if (dupPi >= 0) and (Procs[dupPi].RetType = Procs[procIdx].RetType) then
      Error('duplicate conversion operator: this source type already converts to this result type');
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
function BuildPartialNDRowIndex(rowIdxNode: Integer): Integer;
var d, trailing, loLit, diff, spanLit: Integer;
begin
  trailing := 1;
  for d := 1 to NDInfoNDims - 1 do trailing := trailing * NDInfoSpan[d];
  loLit := AllocNode(AN_INT_LIT); ASTIVal[loLit] := NDInfoLo[0]; ASTTk[loLit] := Ord(tyInteger);
  diff := AllocNode(AN_BINOP); ASTIVal[diff] := Ord(tkMinus);
  ASTLeft[diff] := rowIdxNode; ASTRight[diff] := loLit; ASTTk[diff] := Ord(tyInteger);
  spanLit := AllocNode(AN_INT_LIT); ASTIVal[spanLit] := trailing; ASTTk[spanLit] := Ord(tyInteger);
  Result := AllocNode(AN_BINOP); ASTIVal[Result] := Ord(tkStar);
  ASTLeft[Result] := diff; ASTRight[Result] := spanLit; ASTTk[Result] := Ord(tyInteger);
end;

{ If `node` is an N-D fixed array reference (a SymArrNDims ident or an
  UFldArrNDims record field), fill NDInfo* and return True. Lets m[..] and
  r.m[..] share one path. }
function NodeArrNDInfo(node: Integer): Boolean;
var baseRec, fIdx, sym, d, base: Integer; fname: AnsiString;
begin
  Result := False;
  if (ASTKind[node] = AN_IDENT) and (ASTIVal[node] >= 0) and (SymArrNDims[ASTIVal[node]] >= 2) then
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

procedure FillDefaultArgs(mpi, fromIdx, callNode: Integer; var lastArg: Integer);
var exprNode, argSeq, k: Integer;
begin
  k := fromIdx;
  while k <= Procs[mpi].ParamCount - 1 do
  begin
    exprNode := DefaultArgValueNode(mpi, k);
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
var i, k, cand, exprNode, argSeq: Integer; ok: Boolean;
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
  Add a convention here and every position accepts it.

  Guarded on a following ';' because these words are not reserved: a FIELD named
  `register` is legal, and `register: Integer;` has a ':' next, so it stays a
  field. A directive is always followed by the semicolon. }
begin
  Result := False;
  if CurTok.Kind <> tkIdent then Exit;
  if not (CaseEqual(CurTok.SVal, 'cdecl') or CaseEqual(CurTok.SVal, 'stdcall') or
          CaseEqual(CurTok.SVal, 'safecall') or CaseEqual(CurTok.SVal, 'register') or
          CaseEqual(CurTok.SVal, 'pascal') or CaseEqual(CurTok.SVal, 'mwpascal')) then Exit;
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
  if IsCallConvDirectiveTok then
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
    literal onto a managed AnsiString param) }
  if ((pTk = tyString) or (pTk = tyAnsiString)) and
     ((aTk = tyString) or (aTk = tyAnsiString) or (aTk = tyChar)) then
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
                      CaseEqual(m, 'InstanceSize') or CaseEqual(m, 'ClassNameIs');
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
procedure ExpectCallRParen(mpi: Integer);
var depth: Integer;
begin
  if (CurTok.Kind <> tkRParen) and (mpi >= 0) and (mpi < ProcCount) then
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
    ExpectCallRParen(mpi);
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
    FillDefaultArgs(mpi, 1, callNode, lastArg);

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
  StrConstUnitIdx[StrConstCount] := CurrentUnitIdx; Inc(StrConstCount);
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
  nCand, nArgs, i, j, c, pi, base, want, curr, mbase, cnt, lp, savedCurIdx, best: Integer;
  score, bestScore, rank, pRec, aRec, upDist, upCurr: Integer;
  ok: Boolean;
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
    curr := UClsParent[curr];
  end;

  if nCand <= 1 then
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

  nArgs := 0;
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
        all (`canvas.create_window((0,0), window=w)`). The probe only needs the
        argument's TYPE; which parameter it binds to is settled later by
        PyKwArgIndex. }
      if isNilPy and (CurTok.Kind = tkIdent) and
         (TokPos < TokCount) and (Tokens[TokPos].Kind = tkAssign) then
      begin
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
      rank := OverloadArgRank(Procs[pi].Params[base + j].TypeKind, argTk[j]);
      { CLASS-IDENTITY-aware refinement: two tyClass params tie at rank 0, so
        `Add(TJSONData)` vs `Add(TJSONObject)` picked whichever was declared
        first regardless of the argument's class. FPC picks the EXACT class,
        accepts an up-cast to an ancestor as merely compatible, and rejects an
        unrelated class. Both recs must be known — REC_NONE (nil, untagged)
        keeps the kind-level rank. (bug-pascal-overload-impl-decl-signature-match) }
      if (rank < 3) and (Procs[pi].Params[base + j].TypeKind = tyClass) and
         (argTk[j] = tyClass) and ((base + j) < MAX_PROC_PARAMS) then
      begin
        pRec := ProcParamRecId[pi * MAX_PROC_PARAMS + base + j];
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
      if rank >= 3 then ok := False;
      score := score + rank;
    end;
    if ok and ((best < 0) or (score < bestScore)) then
    begin
      best := cand[c];
      bestScore := score;
    end;
  end;

  if best < 0 then best := FindUMethArity(ci, name, nExplicitArgs);
  Result := best;
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
