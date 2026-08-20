{ ===== pyforwards.inc — the NilPy frontend's forward declarations ============

  Carved out of parser.inc, byte-for-byte, by
  refactor-a-carve-out-plexer-pparser-so-p-owns-its-own-files.

  **Owned by Track N (Nil-Python frontend)**, not by Track P — this is the one
  slice of the carve-out that changes who owns the lines rather than only which
  file they sit in. Nearly 200 `Py*` forwards had accumulated inside the Pascal
  parser because Pascal was the seed and its file was simply where declarations
  went. That is what made a NilPy-only compiler inexpressible: omitting the
  Pascal frontend meant omitting parser.inc, which is where the NilPy frontend
  declared itself
  ([[feature-a-build-a-reduced-compiler-by-selecting-frontends-and-targets]]).

  Included from compiler.pas at exactly the point it used to occupy, so include
  ORDER is unchanged — that is what makes the carve-out provable by the
  self-host fixedpoint rather than by reading it.

  Contents: the forwards for everything `pyparser.inc` defines but the shared
  parser calls, plus `ParseArgExpr` — the hook itself. A call argument under
  NilPy must be parsed by the PYTHON precedence chain, because Pascal binds
  `and`/`or` tighter than comparison and reads `in` as set membership. That
  routine is the shape this whole refactor is about: the shared parser knows
  WHERE an expression is legal, and the language's own file decides what it
  MEANS (devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md).

  Two strays ride along, declared here only because they sat between two Py
  forwards when the cut was made: `VariantCastToTemp` and `PromoDemoteToInt64`
  are shared, not NilPy. Moving them is a semantic change, not a move, so it is
  deliberately NOT part of a refactor whose whole guarantee is that it changed
  nothing. }

procedure PyParseBoolExpr; forward;  { Nil Python boolean layer (defined in pyparser.inc) }
function PyParseLValueAST(idx: Integer; identTokIdx: Integer): Integer; forward;  { the NilPy half of ParseLValueAST, carved out into pyparser.inc — ParseLValueAST dispatches here on PyExprMode }
procedure PyParseFactorCore; forward;  { the NilPy half of ParseFactorCore, carved out into pyparser.inc — ParseFactorCore dispatches here on PyExprMode }
function PyMakeNone: Integer; forward;  { the None VALUE (a VT_EMPTY variant) — pyparser.inc }
function PyBuildGeneratorValue(gpi: Integer): Integer; forward;  { a generator CALL in value position becomes a cursor object (pyparser.inc) }
function PyProgSym(const name: AnsiString): Integer; forward;  { a name in the Nil Python PROGRAM's own scope, never a unit's (pyparser.inc) }
function PyParseSuite: Integer; forward;  { a Nil Python `: <suite>` block — the frontend tail of a for-in header (pyparser.inc) }
function PyNodeIsCallableValue(n: Integer): Boolean; forward;  { a bound method / lambda / function value — pyparser.inc }
function PyWrapHeapCallableCall(calleeNode, argsHead, n, defCall: Integer): Integer; forward;  { Callable-param call through a heap callable — pyparser.inc }
function PyBareNoneHere: Boolean; forward;  { a `None` with nothing after it that could continue an expression — pyparser.inc }
function PyNoneOperandHere: Boolean; forward;  { a `None` that is an OPERAND of the enclosing operator, whatever follows — pyparser.inc }
function PyMakeSuperCall(const name: AnsiString): Integer; forward;  { `super().m(args)` as a value (pyparser.inc) }
function PyRecIsCls(rec: Integer; const clsName: AnsiString): Boolean; forward;  { is this rec that pylib class, by identity OR inheritance? (pyparser.inc) }
function PyRecOverridesDunder(rec: Integer; const dunder: AnsiString): Boolean; forward;  { does this rec's own class DECLARE this dunder — an override a container fast-path must not step over? (pyparser.inc) }
function PySubscriptWantsDunder(mci, lbrackIdx: Integer): Boolean; forward;  { does this subscript belong to the class's own __getitem__/__setitem__ rather than to an INHERITED default property? (pyparser.inc) }
procedure PySuperConsumeArgs; forward;  { `super()` / `super(Cls, self)` argument list, either spelling (pyparser.inc) }
function PyDynAttrEverAssigned(const nm: AnsiString): Boolean; forward;  { is `.nm =` written anywhere? (pyparser.inc) }
function PyIndexCoerce(n: Integer): Integer; forward;  { Python __index__: an object used where an integer is required (pyparser.inc) }
function PyIndexNotIntKind(kind: AnsiString; idxNode: Integer): Integer; forward;  { …and the TypeError when it declares none (pyparser.inc) }
function PyIndexSeqKindCi(mci: Integer): AnsiString; forward;
function PyClassWantsIntIndex(ci: Integer): Boolean; forward;  { does a subscript of this class take an INTEGER (a sequence) rather than an object key? (pyparser.inc) }
function PyClsAttrSharedSym(const fname: AnsiString; var needsOvr: Boolean): Integer; forward;  { the one shared class-attribute slot of that name, for a VARIANT receiver (pyparser.inc) }
function PyClsAttrOvrSlot(ci: Integer; const fname: AnsiString): Integer; forward;  { that slot, when the attribute also needs per-instance overrides (pyparser.inc) }
function PyClsAttrOvrGet(baseNode: Integer; const fname: AnsiString; gsym: Integer): Integer; forward;  { instance read of an overridable class attribute: has? get : slot (pyparser.inc) }
function PyParseInputCall: Integer; forward;  { `input([prompt])` -> pyinput / pyinput_p, one builder for both intercepts (pyparser.inc) }
function PyParseFormatCall: Integer; forward; { `format(v[, spec])` -> pyformat_v, one builder for both intercepts (pyparser.inc) }
function PyParsePrint: Integer; forward;      { `print(...)`; a STATEMENT node — expression use wraps it in AN_COMMA (pyparser.inc) }
function PyIsClassNameChainAhead: Boolean; forward;   { CurTok begins `__class__ . __name__` (pyparser.inc) }
function PyMakeClassNameOf(node: Integer): Integer; forward;   { ...consume it and answer pytype_name_v(node) (pyparser.inc) }
function PyMethNameFor(ci: Integer; const mname: AnsiString): AnsiString; forward;  { the name to look up on this class for a Python method spelling — pylib's alias when the class does not declare it as written (pyparser.inc) }
function PyForceVariant(node: Integer): Integer; forward;  { box a value into a variant (pyparser.inc) }
function PyEvalOnce(node: Integer): Integer; forward;  { bind a value to a hidden temp so it is evaluated once (pyparser.inc) }
function PyMakePercentFormat(fmtNode, argsNode: Integer): Integer; forward;  { `str % args` (pyparser.inc) }
procedure PyParseListLiteral; forward; { Nil Python [a, b, c] literal (pyparser.inc) }
function PyParseStrMethod(baseNode: Integer; const mname: AnsiString): Integer; forward; { Nil Python s.upper() etc (pyparser.inc) }
function PyMakeDynCall(baseNode: Integer): Integer; forward; { Nil Python: call a callable stored in a variant (pyparser.inc) }
function PyBoxCallableValue(node: Integer): Integer; forward; { Nil Python: box a closure/bound-fn pointer into a callable variant (pyparser.inc) }
function PyMakeCallDunder(baseNode: Integer): Integer; forward; { Nil Python: call a class instance's __call__ (pyparser.inc) }
function PyWrapClosureFieldCall(fieldNode, argExpr, defCall: Integer): Integer; forward; { Nil Python: a Callable field may hold a pyeval closure (pyparser.inc) }
function PyMakeBoundMethod(mpi, selfNode: Integer): Integer; forward; { Nil Python: `obj.method` (no call) -> a bound-method value (pyparser.inc) }
procedure PyParseLambdaStub; forward; { Nil Python: lambda -> pyeval closure value (pyparser.inc) }
function PyNestedDefClosureValue(procIdx: Integer): Integer; forward; { Nil Python: nested-def-as-value with live bindings -> closure, or -1 (pyparser.inc) }
function PyIsIdent(const s: AnsiString): Boolean; forward; { (pyparser.inc) }
function PyMakeVariantGetItem(baseNode, idxNode: Integer): Integer; forward; { Nil Python v[key] on a variant (pyparser.inc) }
function PyMakeObjPtr(baseNode: Integer): Integer; forward; { Nil Python: object as a pointer for the dynattr store (pyparser.inc) }
function PyAugBinTok(k: TTokenKind): TTokenKind; forward; { Nil Python augmented-assign op (pyparser.inc) }
function PyMakePow(ppBase, ppExp: Integer): Integer; forward;  { Nil Python `**` lowering, shared with `**=` (pyparser.inc) }
function PyAugClassDunderNode(lhsNode: Integer; binTk: TTokenKind; rhsNode: Integer): Integer; forward; { Nil Python obj.field += x dunder dispatch (pyparser.inc) }
function PyNodeListCi(n: Integer): Integer; forward; { Nil Python: TPyList class index of a node, else -1 (pyparser.inc) }
function PyMakeDynAttrGet(baseNode: Integer; const fname: AnsiString): Integer; forward; { Nil Python obj.name dynamic read (pyparser.inc) }
function PyMakeDynAttrSet(baseNode: Integer; const fname: AnsiString; valNode: Integer): Integer; forward; { Nil Python obj.name = v dynamic write (pyparser.inc) }
function PyMakeVariantSetItem(baseNode, idxNode, valNode: Integer): Integer; forward; { Nil Python v[key]=val on a variant (pyparser.inc) }
function PyMakeIdent(symIdx: Integer): Integer; forward; { Nil Python: ident AST node for a symbol (pyparser.inc) }
function PyHiddenName(const stem: AnsiString): AnsiString; forward; { hidden temp name (pyparser.inc) }
function PyMakeSubscriptRead(selfNode, idxArgs, ci, pri: Integer): Integer; forward; { the read half of `d[k] += v` (pyparser.inc) }
function PyCloneArgChain(head: Integer): Integer; forward;
function PyMakeStrIndex(baseNode, idxNode: Integer): Integer; forward; { Nil Python s[i] (pyparser.inc) }
function PyQualifyNested(const name: AnsiString): AnsiString; forward; { Nil Python nested-def name lookup (pyparser.inc) }
function PyNestedDefOutranksSym(const name: AnsiString): Boolean; forward; { Nil Python: a nested def shadows a module global (pyparser.inc) }
function PyListRepeatPair(a, b: Integer): Boolean; forward;              { Nil Python `xs * n` (pyparser.inc) }
function PyMakeListRepeat(a, b: Integer): Integer; forward;              { Nil Python `xs * n` (pyparser.inc) }
function PyAugMulNode(left, right: Integer): Integer; forward;            { Nil Python `x *= n` on a sequence (pyparser.inc) }
function PyBytesRepeatPair(a, b: Integer): Boolean; forward;             { Nil Python `bytes * n` (pyparser.inc) }
function PyMakeBytesRepeat(a, b: Integer): Integer; forward;             { Nil Python `bytes * n` (pyparser.inc) }
function PyNodeIsPyBytes(n: Integer): Boolean; forward;                  { Nil Python: node typed TPyBytes? (pyparser.inc) }
function PyMakeBytesBinCall(const fname: AnsiString; a, b: Integer; retTk: TTypeKind): Integer; forward; { bytes binop helper call (pyparser.inc) }
function PyMakeListBinCall(const fname: AnsiString; a, b: Integer): Integer; forward; { list binop -> TPyList call (pyparser.inc) }
function PyMakeDictBinCall(const fname: AnsiString; a, b: Integer): Integer; forward; { dict binop -> TPyDict call, PEP 584 `|` (pyparser.inc) }
function PyNodeIsPyDict(n: Integer): Boolean; forward;                   { Nil Python: node typed TPyDict? (pyparser.inc) }
procedure ParsePyUnit(const uname: AnsiString); forward;   { a `.py` MODULE pulled in by an import (pyparser.inc) }
{ PyCallMeth1's forward lives in forwards.inc (FPC-seed catch-all, gated on
  PXX_NEED_FORWARDS) — a second one here duplicated it and FPC rejects a
  Function declared Public/Forward twice (regression-fpc-seed-drift-b1976-
  stale). PXX itself needs neither copy (lenient prescan). }
function PyCallMeth2(ci: Integer; const mname: AnsiString;
                     selfNode, arg1, arg2: Integer): Integer; forward;   { two-arg method call (pyparser.inc) }
function PyMakeTupleFrom(firstNode: Integer): Integer; forward;   { build a tuple from an existing first element (pyparser.inc) }
function PyBareGenExprAhead: Boolean; forward;   { bare genexpr as a call arg (pyparser.inc) }
{ a user object with __iter__ handed to a pylib routine that wants a container
  (bug-nilpy-builtins-over-a-user-iterable-answer-empty) — body in pyparser.inc }
function PyFixIterableArgs(procIdx, argsHead, nArgs: Integer): Boolean; forward;
{ a builtin TYPE handed to a callback (Pointer) parameter — body in pyparser.inc }
function PyFixCallableTypeArgs(const nm: AnsiString; argsHead, nArgs: Integer): Boolean; forward;
function PyStarForwardCall(procIdx, listNode, dictNode: Integer): Integer; forward;   { *args/**kwargs forwarding call (pyparser.inc) }
function PyNewContainerTemp(const clsName, tag: AnsiString): Integer; forward;   { a hoisted, empty pylib container temp (pyparser.inc) }
function PyReprContainer(n: Integer): Integer; forward;   { repr() of a container node (pyparser.inc) }
function PyMakeTruthy(n: Integer): Integer; forward;   { Nil Python truthiness, shared by bool()/if/not (pyparser.inc) }
function VariantCastToTemp(n: Integer; target: TTypeKind): Integer; forward;   { a typecast of a VARIANT is the CONVERSION, not a reinterpret of the record; defined beside PromoDemoteToInt64 }
function PromoDemoteToInt64(n: Integer): Integer; forward;   { promo -> machine int for a value CAST; defined beside PromoWidenToDouble, below its three call sites (FPC is strict about declaration order, pxx is not — bug-a-fpc-seed-drift-emitasmx64-forward) }
function PyWiden(a, b: TTypeKind): TTypeKind; forward;   { Nil Python numeric-kind widening (pyparser.inc) }
function PyRawName(off, len: Integer): AnsiString; forward;           { name text from the token pool (pyparser.inc) }                                   { Nil Python None literal node (pyparser.inc) }
function PyNodeIsPyList(n: Integer): Boolean; forward;                   { Nil Python: node typed TPyList? (pyparser.inc) }
function PySubscriptableSuffix(n: Integer): Boolean; forward; { Nil Python: may `[` follow this non-lvalue? (pyparser.inc) }
function PyMakeSuffixIndex(baseNode, idxNode: Integer): Integer; forward; { Nil Python x[i] on a non-lvalue (pyparser.inc) }
function PyNotSubscriptableNode(ci: Integer): Integer; forward; { Nil Python: run-time TypeError for a class with no __getitem__ (pyparser.inc) }
function PyClassErrCallNode(const procName: AnsiString; ci: Integer): Integer; forward; { Nil Python: a run-time error call naming the class (pyparser.inc) }
function PyClassStrNode(node, argCi: Integer): Integer; forward; { Nil Python: __str__/__repr__ else an Exception's .msg (pyparser.inc) }
function PyIsSliceBase(n: Integer): Boolean; forward;
function PySliceBracketAt(i: Integer): Boolean; forward; { Nil Python: is the bracket group at i a SLICE? (pyparser.inc) }
function PyParseSliceTail(baseNode, loNode: Integer): Integer; forward; { Nil Python x[a:b], from the ':' (pyparser.inc) }
function PyIterArgAsList(n: Integer): Integer; forward; { Nil Python: explode a str arg to an iterable builtin (pyparser.inc) }
function PyIsIntBaseTk(tk: TTypeKind): Boolean; forward; { Nil Python: is this an int base for .to_bytes? (pyparser.inc) }
function PyParseToBytes(baseNode: Integer): Integer; forward; { Nil Python <int>.to_bytes(...) intrinsic (pyparser.inc) }
function PyParseIntMethod(baseNode: Integer; const nm: AnsiString): Integer; forward; { Nil Python intercepted int method (pyparser.inc) }
function PyParseFloatMethod(baseNode: Integer; const nm: AnsiString; asInt: Boolean): Integer; forward; { Nil Python intercepted float method (pyparser.inc) }
function PyIsFloatMethodName(const nm: AnsiString): Boolean; forward; { Nil Python: is_integer/hex/as_integer_ratio/conjugate (pyparser.inc) }
function PyIsFloatBaseTk(tk: TTypeKind): Boolean; forward; { Nil Python: a STATICALLY float receiver (pyparser.inc) }
function PyIsFloatMethodBaseTk(tk: TTypeKind; const nm: AnsiString): Boolean; forward; { ...plus int for the three names it shares }
function PyIsIntFloatSharedMethodName(const nm: AnsiString): Boolean; forward; { is_integer / as_integer_ratio / conjugate }
function PyParseFromBytes: Integer; forward; { Nil Python int.from_bytes(...) intrinsic (pyparser.inc) }
function PyIsFromBytesAhead: Boolean; forward; { Nil Python: at `int.from_bytes(`? (pyparser.inc) }
function PyStoredName(const s: AnsiString): Integer; forward; { Nil Python: intern a name into TokChars (pyparser.inc) }
function PyAttrFieldIdx(recvNode: Integer; const attr: AnsiString): Integer; forward; { Nil Python hasattr/getattr field lookup (pyparser.inc) }
function PyMakeDynAttrSetByExpr(recvNode, nameNode, valNode: Integer): Integer; forward; { Nil Python setattr with a computed name (pyparser.inc) }
{ getattr(o, "p") where p is a PROPERTY — the read `o.p` builds (pyparser.inc) }
function PyMakePropRead(recvNode: Integer; const attr: AnsiString): Integer; forward;
function PyAttrExists(recvNode: Integer; const attr: AnsiString): Boolean; forward; { Nil Python hasattr: field OR method OR str/int method (pyparser.inc) }
function PyHasAttrClassChain(recvNode: Integer; const attr: AnsiString): Integer; forward; { Nil Python hasattr over a VARIANT receiver: run-time class test (pyparser.inc) }
function PyParseAttrName: AnsiString; forward; { Nil Python: the literal attr name in hasattr/getattr (pyparser.inc) }
function PyMakeDynAttrByExpr(recvNode, nameNode, dfltNode: Integer; wantHas: Boolean): Integer; forward; { ...and the COMPUTED-name form, resolved at run time (pyparser.inc) }
function PyTupleParenAhead: Boolean; forward; { Nil Python: is this '(' a tuple? (pyparser.inc) }
procedure PyParseListLiteralT(opener, closer: TTokenKind; dedup: Boolean); forward; { Nil Python list/tuple literal (pyparser.inc) }
function PyIsListCompAhead: Boolean; forward; { Nil Python: is `[ ... for ... ]` a comprehension? (pyparser.inc) }
function PyParseCompExprValue(bracketed: Boolean): Integer; forward;
function PyIsParenCompAhead: Boolean; forward;      { `(x for x in xs)` (pyparser.inc) }
function PyNextOverListAhead: Boolean; forward;     { is `next(...)`'s argument a sequence? (pyparser.inc) }
function PyParseParenComp: Integer; forward;
function PyMakeZip(aNode, bNode, cNode, dNode: Integer): Integer; forward;   { `zip(a, b[, c[, d]])` as a value; -1 for an absent stream (pyparser.inc) }
function PyMakeZipN(listNode: Integer): Integer; forward;                    { `zip(*rows)` / zip past four — over a LIST of iterables (pyparser.inc) }
function PyZipStarOperand(node: Integer): Integer; forward;                  { the star operand of `zip(*rows)` as a TPyList (pyparser.inc) }
function PyStarIterableNode(listNode: Integer): Integer; forward;            { `max(*xs)`: the iterable to compare — the one element's contents, or the list (pyparser.inc) }
function PyZipTailList(a, b, c, d: Integer): Integer; forward;               { four parsed zip operands plus the rest, as a TPyList temp (pyparser.inc) }
function PyStarIsIterableForm(const nm: AnsiString): Boolean; forward;       { `max(*xs)` means max(xs) — the two names that is true of (pyparser.inc) }
function PyIsSetCompAhead: Boolean; forward;    { set comprehension (pyparser.inc) }
function PyParseSetComp: Integer; forward;
function PyParseClassMethodCall(baseNode, ci: Integer; const mname: AnsiString): Integer; forward; { `Cls().m(...)` (pyparser.inc) } { Nil Python expression-position comprehension (pyparser.inc) }
function PyIsSysStreamAhead: Boolean; forward; { Nil Python: at `sys.stdout`/`sys.stderr`? (pyparser.inc) }
function PyStdlibCallAhead(var pname: AnsiString; var nTok: Integer): Boolean; forward; { Nil Python: at a mapped os./sys. call? (pyparser.inc) }
function PyUnboundStrMethodValue: Integer; forward; { Nil Python: `str.lower` as an unbound-method VALUE (pyparser.inc) }
function PyParseStdlibCall(const pname: AnsiString; nTok: Integer): Integer; forward; { Nil Python os./sys. call -> pylib shim (pyparser.inc) }
function PyParseVariadicMinMax(const nm: AnsiString): Integer; forward; { Nil Python min/max at 3+ args (pyparser.inc) }
function PyParseRangeList: Integer; forward;      { Nil Python: list(range(...)) materialised (pyparser.inc) }
function PyAnyProcWithArity(const nm: AnsiString; n: Integer): Boolean; forward; { any routine of this name with exactly n params (pyparser.inc) }
function PyParseSysStream: Integer; forward; { Nil Python sys.stdout/sys.stderr -> its fd (pyparser.inc) }
function PyIsIntMethodBaseTk(tk: TTypeKind; const nm: AnsiString): Boolean; forward; { Nil Python: may an int method claim this receiver? (pyparser.inc) }
function PyIsIntMethodName(const nm: AnsiString): Boolean; forward; { Nil Python: an intercepted int method name? (pyparser.inc) }
function PyIsIntMethodSuffixAhead: Boolean; forward; { Nil Python: at an intercepted int-method suffix? (pyparser.inc) }
function PyParseVariantMethod(baseNode: Integer; const mname: AnsiString): Integer; forward; { Nil Python obj.meth() on a VARIANT receiver (pyparser.inc) }
function PyMakeFuncValue: Integer; forward; { Nil Python bare def NAME as a value (pyparser.inc) }

{ Does proc pi declare any parameter with a DEFAULT? What decides whether a
  callable value has to carry a signature record rather than a bare code
  address -- see the call site in ParseFactorCore. }
function PyProcHasDefaultParam(pi: Integer): Boolean;
var k: Integer;
begin
  Result := False;
  if (pi < 0) or (pi >= ProcCount) then Exit;
  for k := 0 to Procs[pi].ParamCount - 1 do
    if (k < MAX_PROC_PARAMS) and ProcParamHasDefault[pi * MAX_PROC_PARAMS + k] then
    begin
      Result := True;
      Exit;
    end;
end;
function PyMakeFuncValueFor(pi: Integer; const nm: AnsiString): Integer; forward; { the same pair for a KNOWN proc (pyparser.inc) }
function PyFindVariantParamOverload(const nm: AnsiString; wantArity: Integer): Integer; forward; { Nil Python: same-arity all-Variant-param overload of nm (pyparser.inc) }
function PyGetOrMakeCallableWrapper(realPi: Integer): Integer; forward; { Nil Python: Variant-ABI wrapper around realPi, cached by name (pyparser.inc) }
function PyMakeCallablePtrArg(node: Integer; const what: AnsiString): Integer; forward; { Nil Python: a callable VALUE heading for a Pointer parameter (pyparser.inc) }
function PyClsAttrRedeclaredCi(ci: Integer; const nm: AnsiString): Boolean; forward; { Nil Python: is this class attribute redeclared down the chain? (pyparser.inc) }
function PyMakeClsAttrInstGet(baseNode: Integer; const fname: AnsiString): Integer; forward; { Nil Python: read it off the RECEIVER's runtime class (pyparser.inc) }
function PyHoistPark: Integer; forward; { Nil Python: take the hoist queue away for a TRIAL parse (pyparser.inc) }
procedure PyHoistRestore(saved: Integer); forward; { Nil Python: put a parked queue back, dropping the trial's (pyparser.inc) }
procedure PyHoistMerge(saved, trial: Integer); forward; { Nil Python: re-queue a parked trial parse's hoists (pyparser.inc) }
function PyScalarWrappableRetType(tk: TTypeKind): Boolean; forward; { Nil Python: is tk a genuine scalar/string result worth wrapping (pyparser.inc) }
function PyMakeVariantField(baseNode: Integer; const fname: AnsiString; var tk: TTypeKind; var recName: Integer): Integer; forward; { Nil Python obj.field on a VARIANT receiver (pyparser.inc) }
function PyMakeVariantPropRecv(baseNode: Integer; const pname: AnsiString; var ci: Integer): Integer; forward; { Nil Python obj.PROPERTY on a VARIANT receiver: the unboxed class-cast receiver (pyparser.inc) }
function PyKwArgIndex(mpi, firstParam: Integer): Integer; forward; { Nil Python `name=expr` call argument (pyparser.inc) }
function PyKwDictArgNode(mpi: Integer): Integer; forward; { Nil Python: `dict(a=1)` / `d.update(a=1)` keywords are KEYS (pyparser.inc) }
function PyKeywordsAreKeys(mpi: Integer): Boolean; forward; { Nil Python: is this the dict()/update() callee? (pyparser.inc) }
function PyDictKwArgsAhead: Boolean; forward; { Nil Python: at `name=` or `**expr` in an argument list? (pyparser.inc) }
function PyBuildKeywordDictHere: Integer; forward; { Nil Python: the dict `a=1, **e` describes, seeding it with a leading positional mapping when there is one (pyparser.inc) }
function PyKwDictArgsHere(mpi: Integer): Boolean; forward; { Nil Python: this callee's keywords are dict KEYS and a keyword run is in this argument list (pyparser.inc) }
function PyMinMaxDefaultAhead: Boolean; forward; { Nil Python: is there a `default=` keyword in this min/max call? (pyparser.inc) }
function PyBuiltinTypeCode(const nm: AnsiString): Integer; forward; { Nil Python: PYBT_* code for a builtin type NAME, else 0 (pyparser.inc) }
function PyMakeBuiltinTypeValue(code: Integer): Integer; forward; { Nil Python: a builtin type in VALUE position, as pybtype(code) (pyparser.inc) }
function PyDictKwOverloadAhead(ci: Integer; const name: AnsiString): Integer; forward; { Nil Python: the TPyDict.update arm a keywords-are-KEYS run resolves to (pyparser.inc) }
function PyKwNamesTokPos: Integer; forward; { Nil Python: '(' token index of the call at the current parse position, or -1 (pyparser.inc) }
function PyPromoteOverloadByKwAt(ci, mmi, parenTok: Integer; const mname: AnsiString): Integer; forward; { Nil Python: pick the UMeth overload a keyword argument names (pyparser.inc) }
function PyPromoteProcOverloadByKwAt(procIdx, firstParam, parenTok: Integer): Integer; forward; { Nil Python: pick the Procs[] overload a keyword argument names (pyparser.inc) }
procedure PyBindKwArgs(mpi: Integer; var argsHead, lastArg, nArgs: Integer); forward; { Nil Python keyword-argument reorder (pyparser.inc) }
procedure PyPackStarArgs(mpi: Integer; var argsHead, lastArg, nArgs: Integer;
                         selfSlots: Integer); forward; { Nil Python `*args`/`**kwargs` call-site packing (pyparser.inc) }
procedure PyParseStarMethodArgs(mpi, mcallNode: Integer; var mlastArg, mai: Integer); forward; { Nil Python varargs METHOD call (pyparser.inc) }
function PyStarArgAhead: Boolean; forward; { Nil Python: a `*expr` unpack left in this argument list (pyparser.inc) }
procedure PyStarUnpackMethodArgs(mpi, mcallNode: Integer; var mlastArg, mai: Integer); forward; { Nil Python `obj.m(*xs)` call-site unpack (pyparser.inc) }
procedure PyStarUnpackProcArgs(procIdx: Integer; var argsHead, lastArg, nArgs: Integer); forward; { Nil Python `f(1, *xs)` call-site unpack (pyparser.inc) }
function PyIsSetCall: Boolean; forward;   { Nil Python `set(...)` builtin, user definition permitting (pyparser.inc) }
function PyParseEmptySet: Integer; forward; { Nil Python set() / set(iterable) (pyparser.inc) }

procedure ParseArgExpr;
{ A call ARGUMENT under NilPy must be parsed by the Python precedence chain
  (or < and < not < comparison, and `in`/`is` with Python's meaning), not by
  the shared ParseExpr, which implements Pascal's -- where and/or bind TIGHTER
  than comparison and `in` is set membership. Without this `show(a in d)` and
  `show(x > 1 and y > 1)` were parse errors while the identical expressions
  worked in a statement, and every f-string hole is a call argument
  (bug-a-nilpy-and-or-in-unavailable-in-call-arguments).

  Same delegation PyParseListLiteral / PyParseStrMethod already use: the shared
  parser knows WHERE an expression is legal, pyparser.inc decides what it
  MEANS.

  A BARE generator expression — `f(x*2 for x in xs)` — is diverted HERE, which
  is the one place every call argument passes through. It must happen before
  the element expression is parsed, because that expression names the loop
  variable, which is not in scope until the `for`. The diversion used to sit at
  the ordinary-call argument loop and at the str-method path, so the same
  argument parsed one way for `sum(x for x in xs)` and failed with "undefined
  variable (x)" for `obj.take(x for x in xs)` and `f.writelines(s for s in xs)`
  — one construct, N argument loops, which is the shape
  devdocs/dev/normalise-dont-special-case.md is about
  (bug-nilpy-bare-genexpr-as-a-method-argument-does-not-parse). The ordinary
  site's own check is now redundant and harmless: it fires first and does the
  same thing. }
begin
  if PyExprMode and PyBareGenExprAhead then
  begin
    CurASTNode := PyParseCompExprValue(False);
    Exit;
  end;
  if PyExprMode then PyParseBoolExpr else ParseExpr;
end;

{ Types a NilPy str method may be called ON. tyChar is included because Python
  has NO character type: the shared lexer types a one-character literal like
  "b" (and `s[0]`) as tyChar, but to Python that is a str of length 1, so
  `"b".upper()` and `s[0].isspace()` must work. The pylib functions take
  AnsiString and the ordinary char->string conversion covers the argument. }
function PyIsStrBaseTk(tk: TTypeKind): Boolean;
begin
  PyIsStrBaseTk := (tk = tyString) or (tk = tyAnsiString) or (tk = tyChar);
end;
procedure PyParseSetLiteral; forward;  { Nil Python {a, b} literal (pyparser.inc) }
function PyClassCreateExpr: Integer; forward; { Nil Python ClassName(args) ctor (pyparser.inc) }
function PyIsExactCtorName(const nm: AnsiString): Boolean; forward; { Nil Python: `Name(` is a ctor only on an EXACT-case class match (pyparser.inc) }
function PyIsClassTypeExact(const nm: AnsiString): Boolean; forward; { Nil Python: is this name a class, matched EXACTLY (Python is case-sensitive)? (pyparser.inc) }
function PyBuiltinBaseCi(const nm: AnsiString): Integer; forward; { Nil Python: the pylib class a BUILTIN type name (list/dict/set/bytes) stands for, or -1 (pyparser.inc) }
function PyIsDictCompAhead: Boolean; forward; { Nil Python dict comprehension lookahead (pyparser.inc) }
function PyParseDictCompExprValue: Integer; forward; { Nil Python dict comp in expression position (pyparser.inc) }
