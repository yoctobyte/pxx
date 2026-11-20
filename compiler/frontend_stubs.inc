{ SPDX-License-Identifier: MPL-2.0 }
{ STUBS FOR AN OMITTED FRONTEND.

  A reduced build (feature-a-build-a-reduced-compiler-by-selecting-frontends-
  and-targets) drops a frontend's `{$include}` lines. Most of the tree does not
  notice — the shared parser's NilPy-aware BEHAVIOUR (`if isNilPy then ...`)
  compiles fine and simply never fires, which is why omitting a frontend costs
  far less than its reference count suggests. What does not survive is the
  handful of places where shared code CALLS a helper whose body lives in the
  frontend's own file.

  Measured 2026-08-19 by omission: eight functions, total, across both
  frontends. They are stubbed here rather than guarded at each of their ~40
  call sites, for the reason this repo keeps relearning — one place that
  records the fact beats forty predicates that re-derive it, and a guard
  forgotten at one site is a compile error in a configuration nobody builds
  that day.

  EVERY STUB IS UNREACHABLE BY CONSTRUCTION: each call site sits inside an
  `if isNilPy then` / C-parser branch, and a compiler built without a frontend
  cannot set that flag — it refuses the source file at dispatch. So the bodies
  raise rather than return a plausible value. A stub that quietly returned 0
  would turn "this build has no NilPy" into a wrong answer somewhere far away,
  which is exactly the shape of bug this codebase pays most for.

  Signatures MUST stay byte-identical to the real bodies. }

{$ifdef PXX_NO_CFRONT}
function CNodeDecaysToPointer(node: Integer): Boolean;
begin
  { array-to-pointer decay is a C rule; no C source can be in this build }
  CNodeDecaysToPointer := False;
end;

function FindCTypedef(const name: AnsiString): Integer;
begin
  FindCTypedef := -1;
end;

{ Reached only from the C dispatch arm and from a `uses './x.c'`, both of which
  refuse before they get here in this configuration. }
procedure AddDefaultCIncludeDirs;
begin
  Error('internal: AddDefaultCIncludeDirs reached in a build without the C frontend');
end;

{ Not an Error: --where PRINTS this list, and a diagnostic flag must answer in
  every build. With no C frontend there are no C headers to search, and an empty
  list says exactly that. }
procedure BuildCSysIncludeDirs;
begin
  CSysIncludeCount := 0;
  CSysIncludeBuilt := True;
end;

procedure ParseCUnit;
begin
  Error('internal: ParseCUnit reached in a build without the C frontend');
end;

procedure RegisterCMacroConsts;
begin
  Error('internal: RegisterCMacroConsts reached in a build without the C frontend');
end;
{$endif}

{ NilPy: the Py* routines the shared parser still CALLS (bodies in
  pyparser.inc), generated from their forwards or headers so each signature
  is the real one. Same rule as above for most: the call site sits behind
  isNilPy / PyExprMode or a .py source, which this build refuses, so it raises.
  The EXCEPTION is marked REACHED: a dozen the shared argument loops and lvalue
  paths call for every Pascal/C call or assignment, found by a build whose
  stubs logged instead of raising, run over every test source. Each returns
  what its real body answers when isNilPy is False -- an inert -1/0/False, or
  the real body itself where it is language-neutral (PyAugBinTok,
  PyKwNamesTokPos). Regenerating this list: a stub per Py* name a shared file
  references, signature copied from its forward or its pyparser.inc header.
  feature-a-build-a-reduced-compiler-by-selecting-frontends-and-targets }
{$ifdef PXX_NO_NILPY}
procedure PyParseBoolExpr;
begin
  Error('internal: PyParseBoolExpr reached in a build without the NilPy frontend');
end;

function PyParseLValueAST(idx: Integer; identTokIdx: Integer): Integer;
begin
  Error('internal: PyParseLValueAST reached in a build without the NilPy frontend');
end;

procedure PyNarrowIntMinMax;
begin
  Error('internal: PyNarrowIntMinMax reached in a build without the NilPy frontend');
end;

procedure PyProcCallValueIsNone;
begin
  Error('internal: PyProcCallValueIsNone reached in a build without the NilPy frontend');
end;

procedure PyParseFactorCore;
begin
  Error('internal: PyParseFactorCore reached in a build without the NilPy frontend');
end;

function PyMakeNone: Integer;
begin
  Error('internal: PyMakeNone reached in a build without the NilPy frontend');
end;

function PyBuildGeneratorValue(gpi: Integer): Integer;
begin
  Error('internal: PyBuildGeneratorValue reached in a build without the NilPy frontend');
end;

function PyParseSuite: Integer;
begin
  Error('internal: PyParseSuite reached in a build without the NilPy frontend');
end;

function PyNodeIsCallableValue(n: Integer): Boolean;
begin
  Error('internal: PyNodeIsCallableValue reached in a build without the NilPy frontend');
end;

function PyWrapHeapCallableCall(calleeNode, argsHead, n, defCall: Integer): Integer;
begin
  Error('internal: PyWrapHeapCallableCall reached in a build without the NilPy frontend');
end;

function PyRecIsCls(rec: Integer; const clsName: AnsiString): Boolean;
begin
  Error('internal: PyRecIsCls reached in a build without the NilPy frontend');
end;

function PyRecOverridesDunder(rec: Integer; const dunder: AnsiString): Boolean;
begin
  Error('internal: PyRecOverridesDunder reached in a build without the NilPy frontend');
end;

function PyDynAttrEverAssigned(const nm: AnsiString): Boolean;
begin
  Error('internal: PyDynAttrEverAssigned reached in a build without the NilPy frontend');
end;

function PyIndexCoerce(n: Integer): Integer;
begin
  Error('internal: PyIndexCoerce reached in a build without the NilPy frontend');
end;

function PyClsAttrOvrSlot(ci: Integer; const fname: AnsiString): Integer;
begin
  { REACHED by class-var reads: ClassVarPyOvr is set only by NilPy, so no
    attribute has a per-instance override slot }
  Result := -1;
end;

function PyClsAttrOvrGet(baseNode: Integer; const fname: AnsiString; gsym: Integer): Integer;
begin
  Error('internal: PyClsAttrOvrGet reached in a build without the NilPy frontend');
end;

function PyIsClassNameChainAhead: Boolean;
begin
  { REACHED outside NilPy: the shared argument loops call this for every
    call. This is the real body's answer when isNilPy is False. }
  Result := False;
end;

function PyIsBareClassRefAhead: Boolean;
begin
  { REACHED outside NilPy: the shared argument loops call this for every
    call. This is the real body's answer when isNilPy is False. }
  Result := False;
end;

function PyMakeClassRefOf(node: Integer): Integer;
begin
  Error('internal: PyMakeClassRefOf reached in a build without the NilPy frontend');
end;

function PyMakeClassNameOf(node: Integer): Integer;
begin
  Error('internal: PyMakeClassNameOf reached in a build without the NilPy frontend');
end;

function PyMethNameFor(ci: Integer; const mname: AnsiString): AnsiString;
begin
  Error('internal: PyMethNameFor reached in a build without the NilPy frontend');
end;

function PyForceVariant(node: Integer): Integer;
begin
  Error('internal: PyForceVariant reached in a build without the NilPy frontend');
end;

function PyBindOwnedOperandInline(n: Integer): Integer;
begin
  Error('internal: PyBindOwnedOperandInline reached in a build without the NilPy frontend');
end;

function PyEvalOnce(node: Integer): Integer;
begin
  Error('internal: PyEvalOnce reached in a build without the NilPy frontend');
end;

function PyRenderCallOwned(procIdx, n: Integer): Integer;
begin
  Error('internal: PyRenderCallOwned reached in a build without the NilPy frontend');
end;

function PyMakePercentFormat(fmtNode, argsNode: Integer): Integer;
begin
  Error('internal: PyMakePercentFormat reached in a build without the NilPy frontend');
end;

function PyParseStrMethod(baseNode: Integer; const mname: AnsiString): Integer;
begin
  Error('internal: PyParseStrMethod reached in a build without the NilPy frontend');
end;

function PyMakeDynCall(baseNode: Integer): Integer;
begin
  Error('internal: PyMakeDynCall reached in a build without the NilPy frontend');
end;

function PyClsMethCtorCall(node: Integer): Boolean;
begin
  Error('internal: PyClsMethCtorCall reached in a build without the NilPy frontend');
end;

function PyBoxCallableValue(node: Integer): Integer;
begin
  Error('internal: PyBoxCallableValue reached in a build without the NilPy frontend');
end;

function PyMakeCallDunder(baseNode: Integer): Integer;
begin
  Error('internal: PyMakeCallDunder reached in a build without the NilPy frontend');
end;

function PyWrapClosureFieldCall(fieldNode, argExpr, defCall: Integer): Integer;
begin
  Error('internal: PyWrapClosureFieldCall reached in a build without the NilPy frontend');
end;

function PyMakeBoundMethod(mpi, selfNode: Integer): Integer;
begin
  Error('internal: PyMakeBoundMethod reached in a build without the NilPy frontend');
end;

function PyMakeObjPtr(baseNode: Integer): Integer;
begin
  Error('internal: PyMakeObjPtr reached in a build without the NilPy frontend');
end;

function PyAugBinTok(k: TTokenKind): TTokenKind;
begin
  { REACHED by Pascal's own `+=` family: not NilPy-specific, the real body }
  case k of
    tkPlusEq:  Result := tkPlus;
    tkMinusEq: Result := tkMinus;
    tkStarEq:  Result := tkStar;
    tkSlashEq: Result := tkDiv;
    tkTrueDivEq: Result := tkSlash;
    tkModEq:   Result := tkMod;
    tkAmpEq:   Result := tkAnd;
    tkPipeEq:  Result := tkOr;
    tkXorEq:   Result := tkXor;
    tkShlEq:   Result := tkShl;
    tkShrEq:   Result := tkShr;
    tkAtEq:    Result := tkAt;
    else Result := tkEOF;
  end;
end;

function PyMakePow(ppBase, ppExp: Integer): Integer;
begin
  Error('internal: PyMakePow reached in a build without the NilPy frontend');
end;

function PyAugClassDunderNode(lhsNode: Integer; binTk: TTokenKind; rhsNode: Integer): Integer;
begin
  Error('internal: PyAugClassDunderNode reached in a build without the NilPy frontend');
end;

function PyIsVarGetitemCall(n: Integer): Boolean;
begin
  Error('internal: PyIsVarGetitemCall reached in a build without the NilPy frontend');
end;

function PyNodeListCi(n: Integer): Integer;
begin
  Error('internal: PyNodeListCi reached in a build without the NilPy frontend');
end;

function PyMakeDynAttrGet(baseNode: Integer; const fname: AnsiString): Integer;
begin
  Error('internal: PyMakeDynAttrGet reached in a build without the NilPy frontend');
end;

function PyMakeDynAttrSet(baseNode: Integer; const fname: AnsiString; valNode: Integer): Integer;
begin
  Error('internal: PyMakeDynAttrSet reached in a build without the NilPy frontend');
end;

function PyMakeIdent(symIdx: Integer): Integer;
begin
  Error('internal: PyMakeIdent reached in a build without the NilPy frontend');
end;

function PyMakeSubscriptRead(selfNode, idxArgs, ci, pri: Integer): Integer;
begin
  Error('internal: PyMakeSubscriptRead reached in a build without the NilPy frontend');
end;

function PyCloneArgChain(head: Integer): Integer;
begin
  Error('internal: PyCloneArgChain reached in a build without the NilPy frontend');
end;

function PyQualifyNested(const name: AnsiString): AnsiString;
begin
  Error('internal: PyQualifyNested reached in a build without the NilPy frontend');
end;

function PyListRepeatPair(a, b: Integer): Boolean;
begin
  Error('internal: PyListRepeatPair reached in a build without the NilPy frontend');
end;

function PyMakeListRepeat(a, b: Integer): Integer;
begin
  Error('internal: PyMakeListRepeat reached in a build without the NilPy frontend');
end;

function PyAugMulNode(left, right: Integer): Integer;
begin
  Error('internal: PyAugMulNode reached in a build without the NilPy frontend');
end;

function PyBytesRepeatPair(a, b: Integer): Boolean;
begin
  Error('internal: PyBytesRepeatPair reached in a build without the NilPy frontend');
end;

function PyMakeBytesRepeat(a, b: Integer): Integer;
begin
  Error('internal: PyMakeBytesRepeat reached in a build without the NilPy frontend');
end;

function PyNodeIsPyBytes(n: Integer): Boolean;
begin
  Error('internal: PyNodeIsPyBytes reached in a build without the NilPy frontend');
end;

function PyNodeIsPyDeque(n: Integer): Boolean;
begin
  Error('internal: PyNodeIsPyDeque reached in a build without the NilPy frontend');
end;

function PyMakeBytesBinCall(const fname: AnsiString; a, b: Integer; retTk: TTypeKind): Integer;
begin
  Error('internal: PyMakeBytesBinCall reached in a build without the NilPy frontend');
end;

function PyMakeListBinCall(const fname: AnsiString; a, b: Integer): Integer;
begin
  Error('internal: PyMakeListBinCall reached in a build without the NilPy frontend');
end;

function PyMakeDictBinCall(const fname: AnsiString; a, b: Integer): Integer;
begin
  Error('internal: PyMakeDictBinCall reached in a build without the NilPy frontend');
end;

function PyNodeIsPyDict(n: Integer): Boolean;
begin
  Error('internal: PyNodeIsPyDict reached in a build without the NilPy frontend');
end;

procedure ParsePyUnit(const uname: AnsiString);
begin
  Error('internal: ParsePyUnit reached in a build without the NilPy frontend');
end;

procedure PyLexModuleForClosure(const src, path: AnsiString);
begin
  Error('internal: PyLexModuleForClosure reached in a build without the NilPy frontend');
end;

function PyLexedRangeStart(const path: AnsiString): Integer;
begin
  Error('internal: PyLexedRangeStart reached in a build without the NilPy frontend');
end;

function PyPyRangeAt(idx: Integer; var lo, hi: Integer): Boolean;
begin
  { REACHED outside NilPy: the real body tests isNilPy / PyExprMode first;
    this is its answer when that is False. }
  Result := False;   { no .py source and no .py module in this build }
end;

function PyCallMeth2(ci: Integer; const mname: AnsiString; selfNode, arg1, arg2: Integer): Integer;
begin
  Error('internal: PyCallMeth2 reached in a build without the NilPy frontend');
end;

function PyFixIterableArgs(procIdx, argsHead, nArgs: Integer): Boolean;
begin
  Error('internal: PyFixIterableArgs reached in a build without the NilPy frontend');
end;

function PyCoerceCallableArgsIn(procIdx, argsHead: Integer): Boolean;
begin
  { REACHED outside NilPy: the real body tests isNilPy / PyExprMode first;
    this is its answer when that is False. }
  Result := False;
end;

function PyArgListHasStarElem: Boolean;
begin
  Error('internal: PyArgListHasStarElem reached in a build without the NilPy frontend');
end;

function PyPascalStarIdx(pi: Integer): Integer;
begin
  Error('internal: PyPascalStarIdx reached in a build without the NilPy frontend');
end;

function PyPromoteOverloadByStarAt(ci, mmi, parenTok: Integer; const mname: AnsiString): Integer;
begin
  { REACHED outside NilPy: the shared argument loops call this for every
    call. This is the real body's answer when isNilPy is False. }
  Result := mmi;   { no `*x` element in a non-NilPy argument list }
end;

function PyReprContainer(n: Integer): Integer;
begin
  Error('internal: PyReprContainer reached in a build without the NilPy frontend');
end;

function PyMakeTruthy(n: Integer): Integer;
begin
  Error('internal: PyMakeTruthy reached in a build without the NilPy frontend');
end;

function PyWiden(a, b: TTypeKind): TTypeKind;
begin
  Error('internal: PyWiden reached in a build without the NilPy frontend');
end;

function PyAugMarkedTok(k: TTokenKind): Boolean;
begin
  Error('internal: PyAugMarkedTok reached in a build without the NilPy frontend');
end;

function PyRawName(off, len: Integer): AnsiString;
begin
  Error('internal: PyRawName reached in a build without the NilPy frontend');
end;

function PyNodeIsPyList(n: Integer): Boolean;
begin
  Error('internal: PyNodeIsPyList reached in a build without the NilPy frontend');
end;

function PySubscriptableSuffix(n: Integer): Boolean;
begin
  Error('internal: PySubscriptableSuffix reached in a build without the NilPy frontend');
end;

function PyDynAttrSuffix(n: Integer): Boolean;
begin
  Error('internal: PyDynAttrSuffix reached in a build without the NilPy frontend');
end;

function PyMakeSuffixIndex(baseNode, idxNode: Integer): Integer;
begin
  Error('internal: PyMakeSuffixIndex reached in a build without the NilPy frontend');
end;

function PyNotSubscriptableNode(ci: Integer): Integer;
begin
  Error('internal: PyNotSubscriptableNode reached in a build without the NilPy frontend');
end;

function PyClassErrCallNode(const procName: AnsiString; ci: Integer): Integer;
begin
  Error('internal: PyClassErrCallNode reached in a build without the NilPy frontend');
end;

function PyClassStrNode(node, argCi: Integer): Integer;
begin
  Error('internal: PyClassStrNode reached in a build without the NilPy frontend');
end;

function PyIsSliceBase(n: Integer): Boolean;
begin
  Error('internal: PyIsSliceBase reached in a build without the NilPy frontend');
end;

function PyParseSliceTail(baseNode, loNode: Integer): Integer;
begin
  Error('internal: PyParseSliceTail reached in a build without the NilPy frontend');
end;

function PyIsIntBaseTk(tk: TTypeKind): Boolean;
begin
  Error('internal: PyIsIntBaseTk reached in a build without the NilPy frontend');
end;

function PyParseIntMethod(baseNode: Integer; const nm: AnsiString): Integer;
begin
  Error('internal: PyParseIntMethod reached in a build without the NilPy frontend');
end;

function PyParseFloatMethod(baseNode: Integer; const nm: AnsiString; asInt: Boolean): Integer;
begin
  Error('internal: PyParseFloatMethod reached in a build without the NilPy frontend');
end;

function PyIsFloatMethodName(const nm: AnsiString): Boolean;
begin
  Error('internal: PyIsFloatMethodName reached in a build without the NilPy frontend');
end;

function PyIsFloatMethodBaseTk(tk: TTypeKind; const nm: AnsiString): Boolean;
begin
  Error('internal: PyIsFloatMethodBaseTk reached in a build without the NilPy frontend');
end;

function PyAttrFieldIdx(recvNode: Integer; const attr: AnsiString): Integer;
begin
  Error('internal: PyAttrFieldIdx reached in a build without the NilPy frontend');
end;

function PyMakeDynAttrSetByExpr(recvNode, nameNode, valNode: Integer): Integer;
begin
  Error('internal: PyMakeDynAttrSetByExpr reached in a build without the NilPy frontend');
end;

function PyMakePropRead(recvNode: Integer; const attr: AnsiString): Integer;
begin
  Error('internal: PyMakePropRead reached in a build without the NilPy frontend');
end;

function PyAttrExists(recvNode: Integer; const attr: AnsiString): Boolean;
begin
  Error('internal: PyAttrExists reached in a build without the NilPy frontend');
end;

function PyHasAttrRuntimeChain(recvNode: Integer; const attr: AnsiString): Integer;
begin
  Error('internal: PyHasAttrRuntimeChain reached in a build without the NilPy frontend');
end;

function PyParseAttrName: AnsiString;
begin
  Error('internal: PyParseAttrName reached in a build without the NilPy frontend');
end;

function PyMakeDynAttrByExpr(recvNode, nameNode, dfltNode: Integer; wantHas: Boolean): Integer;
begin
  Error('internal: PyMakeDynAttrByExpr reached in a build without the NilPy frontend');
end;

function PyParseClassMethodCall(baseNode, ci: Integer; const mname: AnsiString): Integer;
begin
  Error('internal: PyParseClassMethodCall reached in a build without the NilPy frontend');
end;

function PyParseVariadicMinMax(const nm: AnsiString): Integer;
begin
  Error('internal: PyParseVariadicMinMax reached in a build without the NilPy frontend');
end;

function PyIsIntMethodBaseTk(tk: TTypeKind; const nm: AnsiString): Boolean;
begin
  Error('internal: PyIsIntMethodBaseTk reached in a build without the NilPy frontend');
end;

function PyIsIntMethodName(const nm: AnsiString): Boolean;
begin
  Error('internal: PyIsIntMethodName reached in a build without the NilPy frontend');
end;

function PyParseVariantMethod(baseNode: Integer; const mname: AnsiString): Integer;
begin
  Error('internal: PyParseVariantMethod reached in a build without the NilPy frontend');
end;

function PyMakeFuncValue: Integer;
begin
  { REACHED outside NilPy: the real body tests isNilPy / PyExprMode first;
    this is its answer when that is False. }
  Result := -1;
end;

function PyHoistPark: Integer;
begin
  { REACHED by trial parses: no NilPy statement is ever hoisted here, so the
    parked queue is the empty one }
  Result := -1;
end;

procedure PyHoistRestore(saved: Integer);
begin
  { REACHED: the matching restore of an always-empty queue }
end;

procedure PyHoistMerge(saved, trial: Integer);
begin
  Error('internal: PyHoistMerge reached in a build without the NilPy frontend');
end;

function PyKwArgIndex(mpi, firstParam: Integer): Integer;
begin
  { REACHED outside NilPy: the shared argument loops call this for every
    call. This is the real body's answer when isNilPy is False. }
  PyKwArgIndex := 0;
end;

function PyKwDictArgNode(mpi: Integer): Integer;
begin
  { REACHED outside NilPy: the shared argument loops call this for every
    call. This is the real body's answer when isNilPy is False. }
  Result := -1;
end;

function PyBuildKeywordDictHere: Integer;
begin
  Error('internal: PyBuildKeywordDictHere reached in a build without the NilPy frontend');
end;

function PyKwDictArgsHere(mpi: Integer): Boolean;
begin
  { REACHED outside NilPy: the real body tests isNilPy / PyExprMode first;
    this is its answer when that is False. }
  Result := False;
end;

function PyDictKwOverloadAhead(ci: Integer; const name: AnsiString; starOnly: Boolean): Integer;
begin
  { REACHED outside NilPy: the real body tests isNilPy / PyExprMode first;
    this is its answer when that is False. }
  Result := -1;
end;

function PyKwNamesTokPos: Integer;
begin
  { REACHED outside NilPy: the shared argument loops call this for every
    call. This is the real body's answer when isNilPy is False. }
  { not NilPy-specific: the real body, a token position }
  if CurTok.Kind = tkLParen then
    Result := TokPos - 1
  else if (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) then
    Result := TokPos
  else
    Result := -1;
end;

function PyPromoteOverloadByKwAt(ci, mmi, parenTok: Integer; const mname: AnsiString): Integer;
begin
  Error('internal: PyPromoteOverloadByKwAt reached in a build without the NilPy frontend');
end;

procedure PyBindKwArgs(mpi: Integer; var argsHead, lastArg, nArgs: Integer);
begin
  { REACHED outside NilPy: the shared argument loops call this for every
    call. This is the real body's answer when isNilPy is False. }
  { no argument carries a keyword mark (PyKwArgIndex answers 0) }
end;

procedure PyPackStarArgs(mpi: Integer; var argsHead, lastArg, nArgs: Integer; selfSlots: Integer);
begin
  { REACHED outside NilPy: the shared argument loops call this for every
    call. This is the real body's answer when isNilPy is False. }
  { no routine has a *args/**kwargs slot outside NilPy }
end;

procedure PyParseStarMethodArgs(mpi, mcallNode: Integer; var mlastArg, mai: Integer);
begin
  Error('internal: PyParseStarMethodArgs reached in a build without the NilPy frontend');
end;

function PyStarArgAhead: Boolean;
begin
  Error('internal: PyStarArgAhead reached in a build without the NilPy frontend');
end;

procedure PyStarUnpackMethodArgs(mpi, mcallNode: Integer; var mlastArg, mai: Integer);
begin
  Error('internal: PyStarUnpackMethodArgs reached in a build without the NilPy frontend');
end;

function PyIsExactCtorName(const nm: AnsiString): Boolean;
begin
  Error('internal: PyIsExactCtorName reached in a build without the NilPy frontend');
end;

function PyIsClassTypeExact(const nm: AnsiString): Boolean;
begin
  Error('internal: PyIsClassTypeExact reached in a build without the NilPy frontend');
end;

function PyCallableValueArity(pi: Integer): Integer;
begin
  Error('internal: PyCallableValueArity reached in a build without the NilPy frontend');
end;

function PyCallProc1(const pname: AnsiString; argNode: Integer): Integer;
begin
  Error('internal: PyCallProc1 reached in a build without the NilPy frontend');
end;

function PyBitVariantCall(const fname: AnsiString; left, right: Integer): Integer;
begin
  Error('internal: PyBitVariantCall reached in a build without the NilPy frontend');
end;

function PyNodeIsComplex(n: Integer): Boolean;
begin
  Error('internal: PyNodeIsComplex reached in a build without the NilPy frontend');
end;

function PyUnaryOperandIsNotANumber(n: Integer): Boolean;
begin
  Error('internal: PyUnaryOperandIsNotANumber reached in a build without the NilPy frontend');
end;

function PyMakeComplexBinop(op: TTokenKind; a, b: Integer): Integer;
begin
  Error('internal: PyMakeComplexBinop reached in a build without the NilPy frontend');
end;

function PyCallMeth1(ci: Integer; const mname: AnsiString; selfNode, argNode: Integer): Integer;
begin
  Error('internal: PyCallMeth1 reached in a build without the NilPy frontend');
end;

function PySeqAppend(head, stmt: Integer): Integer;
begin
  Error('internal: PySeqAppend reached in a build without the NilPy frontend');
end;

function PyMethodName(const name: AnsiString): AnsiString;
begin
  Error('internal: PyMethodName reached in a build without the NilPy frontend');
end;

function PyUserNameShadowsHere(const nm: AnsiString): Boolean;
begin
  Error('internal: PyUserNameShadowsHere reached in a build without the NilPy frontend');
end;

function PyGenFactoryFor(gpi: Integer): Integer;
begin
  Error('internal: PyGenFactoryFor reached in a build without the NilPy frontend');
end;

function PyParamTypeFromSites(defTok: Integer; const pname: AnsiString; mode: Integer; const clsName: AnsiString): TTypeKind;
begin
  Error('internal: PyParamTypeFromSites reached in a build without the NilPy frontend');
end;

function PyFoldHoistSince(savedTail, node: Integer): Integer;
begin
  Error('internal: PyFoldHoistSince reached in a build without the NilPy frontend');
end;

function PyFlushImportAliases(seq: Integer): Integer;
begin
  Error('internal: PyFlushImportAliases reached in a build without the NilPy frontend');
end;

procedure PyInitVariantLocals(scopeBase: Integer);
begin
  Error('internal: PyInitVariantLocals reached in a build without the NilPy frontend');
end;

procedure PyBitGuard(n: Integer);
begin
  Error('internal: PyBitGuard reached in a build without the NilPy frontend');
end;

function PyDiscardedCallIsOwned(p: Integer): Boolean;
begin
  Error('internal: PyDiscardedCallIsOwned reached in a build without the NilPy frontend');
end;

function PyCallYieldsOwnedObj(n: Integer): Boolean;
begin
  Error('internal: PyCallYieldsOwnedObj reached in a build without the NilPy frontend');
end;

procedure PyScanDefGlobals(bodyStart: Integer);
begin
  Error('internal: PyScanDefGlobals reached in a build without the NilPy frontend');
end;

function PyTrueDivResultTk(ltk, rtk: TTypeKind): TTypeKind;
begin
  Error('internal: PyTrueDivResultTk reached in a build without the NilPy frontend');
end;

function PyIntLiteralText(n: Int64): AnsiString;
begin
  Error('internal: PyIntLiteralText reached in a build without the NilPy frontend');
end;

procedure PyClsAttrRedeclScan;
begin
  Error('internal: PyClsAttrRedeclScan reached in a build without the NilPy frontend');
end;

function PyDfltPendFor(key: Integer): Integer;
begin
  Error('internal: PyDfltPendFor reached in a build without the NilPy frontend');
end;

function PyEvalParamDefault(var j: Integer; const pname: AnsiString): Integer;
begin
  Error('internal: PyEvalParamDefault reached in a build without the NilPy frontend');
end;

function PyParamDefaultAt(var j: Integer; const pname: AnsiString; var isStr: Boolean; var sOff, sLen: Integer): Int64;
begin
  Error('internal: PyParamDefaultAt reached in a build without the NilPy frontend');
end;

function PyUnitImportedName(const name: AnsiString; unitIdx, srcUnit: Integer): Boolean;
begin
  Error('internal: PyUnitImportedName reached in a build without the NilPy frontend');
end;

procedure PyStrictRefuse(const feature: AnsiString; const cpythonSays: AnsiString);
begin
  Error('internal: PyStrictRefuse reached in a build without the NilPy frontend');
end;

procedure PyCopyPascalDefaultsToWrapper(realPi, wrapPi, wrapArity: Integer);
begin
  Error('internal: PyCopyPascalDefaultsToWrapper reached in a build without the NilPy frontend');
end;

function PyParseBlock: Integer;
begin
  Error('internal: PyParseBlock reached in a build without the NilPy frontend');
end;

function PyParseStatement: Integer;
begin
  Error('internal: PyParseStatement reached in a build without the NilPy frontend');
end;

procedure PyParseImportRun;
begin
  Error('internal: PyParseImportRun reached in a build without the NilPy frontend');
end;

function PyBindImportUnitAlias(const realKey: AnsiString): Boolean;
begin
  Error('internal: PyBindImportUnitAlias reached in a build without the NilPy frontend');
end;

function PySourceExists(const path: AnsiString): Boolean;
begin
  Error('internal: PySourceExists reached in a build without the NilPy frontend');
end;

procedure PyParseRelImportNames(impLevel: Integer);
begin
  Error('internal: PyParseRelImportNames reached in a build without the NilPy frontend');
end;

procedure PyParseOneImport;
begin
  Error('internal: PyParseOneImport reached in a build without the NilPy frontend');
end;

function PyParseIf: Integer;
begin
  Error('internal: PyParseIf reached in a build without the NilPy frontend');
end;

function PyParseFallbackImportTry: Integer;
begin
  Error('internal: PyParseFallbackImportTry reached in a build without the NilPy frontend');
end;

function PyParseWithTail: Integer;
begin
  Error('internal: PyParseWithTail reached in a build without the NilPy frontend');
end;

function PyGenValueArgCell(argNode: Integer): Integer;
begin
  Error('internal: PyGenValueArgCell reached in a build without the NilPy frontend');
end;

function PyAugDunderName(binTk: TTokenKind; inPlace: Boolean): AnsiString;
begin
  Error('internal: PyAugDunderName reached in a build without the NilPy frontend');
end;

procedure PyCollectCalleeCaps(const calleeName: AnsiString; searchFrom: Integer);
begin
  Error('internal: PyCollectCalleeCaps reached in a build without the NilPy frontend');
end;

function PyQueueNestedDef: Integer;
begin
  Error('internal: PyQueueNestedDef reached in a build without the NilPy frontend');
end;

function PyModuleBindingsOf(const name: AnsiString; var sites: array of Integer): Integer;
begin
  Error('internal: PyModuleBindingsOf reached in a build without the NilPy frontend');
end;

function PyRedirectForeignModuleGlobal(i: Integer; const lo: AnsiString): Integer;
begin
  Error('internal: PyRedirectForeignModuleGlobal reached in a build without the NilPy frontend');
end;

function PyDefUsedAsValueByScan(const nm: AnsiString): Boolean;
begin
  Error('internal: PyDefUsedAsValueByScan reached in a build without the NilPy frontend');
end;

procedure PyBuildDValTable;
begin
  Error('internal: PyBuildDValTable reached in a build without the NilPy frontend');
end;

procedure PyRegisterDefShells;
begin
  Error('internal: PyRegisterDefShells reached in a build without the NilPy frontend');
end;

procedure PyParseDef;
begin
  Error('internal: PyParseDef reached in a build without the NilPy frontend');
end;

function PyFieldIsIntAccumulator(bodyStart, bodyEnd: Integer; const fld: AnsiString): Boolean;
begin
  Error('internal: PyFieldIsIntAccumulator reached in a build without the NilPy frontend');
end;

procedure PyParseMethod(ci: Integer);
begin
  Error('internal: PyParseMethod reached in a build without the NilPy frontend');
end;

function PyConsumeDottedModule(var rootName: AnsiString): AnsiString;
begin
  Error('internal: PyConsumeDottedModule reached in a build without the NilPy frontend');
end;

function PyRelativeImportLevel: Integer;
begin
  Error('internal: PyRelativeImportLevel reached in a build without the NilPy frontend');
end;

function PyImportRootPlainIsConsumedOnly(const root: AnsiString): Boolean;
begin
  Error('internal: PyImportRootPlainIsConsumedOnly reached in a build without the NilPy frontend');
end;

procedure PyParseImportUnitAs(const name, lang: AnsiString);
begin
  Error('internal: PyParseImportUnitAs reached in a build without the NilPy frontend');
end;

procedure PyParseImportUnit(const name: AnsiString);
begin
  Error('internal: PyParseImportUnit reached in a build without the NilPy frontend');
end;

function PyPackageSubmoduleKey(const pkgName, sub: AnsiString): AnsiString;
begin
  Error('internal: PyPackageSubmoduleKey reached in a build without the NilPy frontend');
end;

procedure PyLexImportClosure;
begin
  { REACHED outside NilPy: the real body tests isNilPy / PyExprMode first;
    this is its answer when that is False. }
end;

procedure ParsePyProgram;
begin
  Error('internal: ParsePyProgram reached in a build without the NilPy frontend');
end;

function PyParseClassRecordSelectors(node, recId: Integer; var outTk: TTypeKind): Integer;
begin
  Error('internal: PyParseClassRecordSelectors reached in a build without the NilPy frontend');
end;

procedure PyRefuseDynArrayResult(procIdx: Integer);
begin
  Error('internal: PyRefuseDynArrayResult reached in a build without the NilPy frontend');
end;

procedure PyCheckDynArrBoundRead(const name: AnsiString);
begin
  Error('internal: PyCheckDynArrBoundRead reached in a build without the NilPy frontend');
end;
{$endif}
