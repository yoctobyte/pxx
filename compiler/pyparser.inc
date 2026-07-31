{ SPDX-License-Identifier: MPL-2.0 }
{ ===== Nil Python Parser =====

  Expression operators accepted by the .npy lexer/parser boundary:
    Python spelling   shared parser token   policy
    + - *             tkPlus/tkMinus/tkStar same arithmetic semantics
    //                tkDiv                 integer division
    %                 tkMod                 integer remainder
    == != < <= > >=   tkEq/tkNeq/...        comparisons
    and or not        tkAnd/tkOr/tkNot      boolean operators

  `/` is intentionally rejected in v1: use `//` for integer division. The
  lexer reports other Python-only operators before this parser is entered.
}

const
  { 128 was too small for a real module: songformatter's key_analysis.py plus a
    driver crosses it and the compile stops at "too many inferred module
    locals". The table is per-scope constraints, four words each — 512 costs
    nothing and covers a file several times that size. }
  PY_MAX_LOCALS = 512;

type
  TPyLocalConstraint = record
    Name: AnsiString;
    TypeKind: TTypeKind;
    RecCi: Integer;   { class index when TypeKind = tyClass, else -1 }
  end;

const
  PY_MAX_DC_FIELDS = 512;
  { default kinds for dataclass fields }
  PYDC_NONE  = 0;
  PYDC_INT   = 1;
  PYDC_FLOAT = 2;
  PYDC_STR   = 3;
  PYDC_BOOL  = 4;
  PYDC_NIL   = 5;  { None default: 0/nil for pointer-like and Optional[int] fields }
  PYDC_FACTORY_LIST = 6;  { field(default_factory=list): fresh empty TPyList per construction }
  PYDC_FACTORY_DICT = 8;  { field(default_factory=dict): fresh empty TPyDict per construction }
  PYDC_FACTORY_EXPR = 7;  { field(default_factory=lambda: <expr>): IVal/SOff carry the
                            body's token span, re-parsed at every construction site }

var
  PyLocals: array[0..PY_MAX_LOCALS-1] of TPyLocalConstraint;
  PyLocalCount: Integer;
  PyModuleLocals: array[0..PY_MAX_LOCALS-1] of TPyLocalConstraint;
  PyModuleLocalCount: Integer;
  { PyCollectLocalsAST's trial parse is on. The assignment paths report every
    RHS type they build so the table can WIDEN: the symbol table alone only
    remembers a local's FIRST assignment, which is exactly the information
    Python's implicit declaration does not give you (`x = 1` then `x = "s"`
    is one variant local, not an Integer one). }
  PyTypingPass: Boolean;
  { List-comprehension mode for PyParseForIn: when PyCompTarget >= 0 the loop
    has NO parsed suite. Instead its body is `PyCompTarget.append(EXPR)`, where
    EXPR is re-parsed from the tokens at PyCompExprStart (a comprehension writes
    the element expression BEFORE the `for`), and the header ends at `]` rather
    than `:`. See PyParseListComp. }
  PyCompTarget: Integer;
  PyCompExprStart: Integer;
  { DICT-comprehension mode: when set, the comprehension target is a TPyDict and
    the element region is `KEY : VALUE` (not one EXPR), so the body becomes
    `target.store(KEY, VALUE)` instead of `.append(EXPR)`. See PyParseDictComp. }
  PyCompIsDict: Boolean;
  { SET-comprehension mode: a brace group with a `for` and no colon. The target
    is a TPyList (which is how NilPy represents a set) and elements go in through
    `add`, the duplicate-skipping insert, so len() matches Python's. }
  PyCompIsSet: Boolean;
  { Statement HOISTING, for expression-position comprehensions/genexprs. A
    comprehension used inside an expression (`"\n".join(x for x in it)`, or a
    bracketed one as a call argument) cannot be an expression on its own — the
    single-pass AST has no statement-in-expression node. So it desugars into a
    hidden temp filled by a loop, PUSHES those setup statements here, and yields
    the temp. Each statement-sequence builder flushes this before the statement
    it just parsed, so the setup runs first. }
  PyHoistHead: Integer;
  PyTypingChanged: Boolean;
  PyHiddenSeq: Integer;   { serial for hidden for-in loop temps }
  { One parsed `def` header, filled by PyParseDefHeader and read by both its
    callers — the shell pre-pass and PyParseDef itself. Globals rather than a
    dozen var parameters because there must be exactly ONE implementation of
    the header grammar: the pre-pass decides the registered SIGNATURE and
    PyParseDef decides the FRAME, and any disagreement between them is a
    silent ABI mismatch rather than a parse error. }
  { A for target with MORE than two names — `for a, b, c in triples:`. The first
    two keep their own variables (the dict/enumerate/zip forms only ever have
    two); anything beyond them lands here and is unpacked from the element by
    index, which is the only form that can serve three. }
  PyForExtraName: array[0..5] of AnsiString;
  PyForExtraCount: Integer;
  PyHdrName: AnsiString;
  PyHdrNParams: Integer;
  PyHdrIsProc: Boolean;
  PyHdrRetType: TTypeKind;
  PyHdrRetCi: Integer;
  PyHdrPNames: array[0..31] of AnsiString;
  PyHdrPTypes: array[0..31] of TTypeKind;
  PyHdrPCis: array[0..31] of Integer;
  PyHdrPSigs: array[0..31] of Integer;   { Callable signature per parameter, or -1 }
  PyHdrDefHas: array[0..31] of Boolean;
  PyHdrDefIsStr: array[0..31] of Boolean;
  PyHdrDefIsNone: array[0..31] of Boolean;
  PyHdrDefIsFloat: array[0..31] of Boolean;
  PyDefaultWasNone: Boolean;   { set by PyParamDefaultAt — see there }
  PyDefaultWasFloat: Boolean;
  PyHdrDefVal: array[0..31] of Int64;
  PyHdrDefSOff: array[0..31] of Integer;
  PyHdrDefSLen: array[0..31] of Integer;
  { parameter index of `*args` / `**kwargs` in the header just parsed, or -1 }
  PyHdrStarIdx: Integer;
  PyHdrKwIdx: Integer;
  { @dataclass field defaults, appended in declaration order per class ci.
    Looked up positionally by PyClassCreate to fill omitted trailing args. }
  PyDcCi:   array[0..PY_MAX_DC_FIELDS-1] of Integer;
  PyDcKind: array[0..PY_MAX_DC_FIELDS-1] of Integer;
  PyDcIVal: array[0..PY_MAX_DC_FIELDS-1] of Int64;
  PyDcSOff: array[0..PY_MAX_DC_FIELDS-1] of Integer;
  PyDcSLen: array[0..PY_MAX_DC_FIELDS-1] of Integer;
  PyDcCount: Integer;
  PyDcClassIsDc: array[0..PY_MAX_DC_FIELDS-1] of Boolean;  { indexed by ci }
  { True when the member pre-pass already ran the FULL PyRegisterClassMembers
    for this ci (methods + fields + defaults), so PyParseClass must not run it
    again — a second full run would duplicate the append-only PyDc* defaults
    and re-RegisterProc every method. Hoisting members is what lets the
    module-collect trial parse resolve `x = obj.method()`
    (bug-nilpy-method-result-copied-to-var-undefined). }
  PyMembersHoisted: array[0..MAX_UCLASS-1] of Boolean;

function PyIsIdent(const s: AnsiString): Boolean;
begin
  Result := (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, s);
end;

{ `/` is Python true division and maps to the shared tkSlash float-division
  path (int operands produce a float, matching CPython). `//` is tkDiv. }

procedure PyExpectIdent(const s: AnsiString);
begin
  if not PyIsIdent(s) then Error('Nil Python: expected ' + s);
  Next;
end;

procedure PySkipNewlines;
begin
  while CurTok.Kind = tkNewline do Next;
end;

function PySeqAppend(head, stmt: Integer): Integer; forward;
{ An integer literal node, for the pair-unpack indices below. }
function PyMakeIntLit(v: Int64): Integer;
begin
  Result := AllocNode(AN_INT_LIT);
  ASTIVal[Result] := v;
  ASTTk[Result] := Ord(tyInteger);
end;

{ One element of a `for a, b in pairs` loop target: `pair[idx]` through pylib's
  pyvar_getitem. An ordinary function on purpose — TPyList.at is INLINED, and an
  inline body built from here leaked its AN_INLINE_PARAM placeholder into
  lowering. }
function PyPairItem(pairNode, idx: Integer): Integer;
var argNode, idxArg, callNode: Integer;
begin
  argNode := AllocNode(AN_ARG);
  ASTLeft[argNode] := pairNode;
  idxArg := AllocNode(AN_ARG);
  ASTLeft[idxArg] := PyMakeIntLit(idx);
  ASTRight[idxArg] := -1;          { terminate the chain — an unset ASTRight
                                     ran the argument list into other nodes }
  ASTRight[argNode] := idxArg;
  callNode := AllocNode(AN_CALL);
  ASTIVal[callNode] := FindProc('pyvar_getitem');
  if ASTIVal[callNode] < 0 then Error('Nil Python: pylib (pyvar_getitem) not loaded');
  ASTTk[callNode] := Ord(tyVariant);
  ASTLeft[callNode] := argNode;
  Result := callNode;
end;

function PyBuildComp(targetSym, exprStart: Integer): Integer; forward; { comprehension core (pyparser.inc) }
function PyMakeIdent(symIdx: Integer): Integer; forward; { (pyparser.inc) }
function PyHiddenName(const stem: AnsiString): AnsiString; forward; { hidden temp name (pyparser.inc) }
function PyCallMeth1(ci: Integer; const mname: AnsiString;
                     selfNode, argNode: Integer): Integer; forward; { one-arg method call (pyparser.inc) }
function PyParseFor: Integer; forward;
function PyBareGenExprAhead: Boolean; forward; { bare genexpr as a call arg (pyparser.inc) }

{ Queue a setup statement to run before the current one — see PyHoistHead. }
procedure PyHoistStmt(node: Integer);
var scan: Integer;
begin
  { The SAME node queued twice makes the chain self-referential — PySeqAppend
    links the tail to it, and the tail IS it — so the flush walks forever and
    the body lowers a repeated, half-valid statement. It happens for real: the
    typing pre-pass runs several iterations and rolls ASTNodeCount back to the
    same watermark each round, so each round's hoist gets the same node id.
    Queueing a node already on the chain is never meaningful. }
  scan := PyHoistHead;
  while scan >= 0 do
  begin
    if (scan = node) or (ASTLeft[scan] = node) then Exit;
    scan := ASTRight[scan];
  end;
  PyHoistHead := PySeqAppend(PyHoistHead, node);
end;

{ Requeue a stashed hoist chain IN FRONT of whatever is pending. A header
  expression's hoisted setup (a literal build in an if/while condition) must
  flush at the ENCLOSING statement, not be stolen by the first nested suite's
  own flush — that compiled the build INSIDE the then-branch while the
  condition read the still-nil temp. }
procedure PyHoistPrepend(stash: Integer);
var tail: Integer;
begin
  if stash < 0 then Exit;
  tail := stash;
  while ASTRight[tail] >= 0 do tail := ASTRight[tail];
  ASTRight[tail] := PyHoistHead;
  PyHoistHead := stash;
end;

{ Prepend any hoisted setup statements to `seq`, then clear. Called by each
  statement-sequence builder right after it parses one statement, so the
  expression-comprehension setup lands before the statement that uses it. }
function PyFlushHoist(seq: Integer): Integer;
var h, node: Integer;
begin
  Result := seq;
  h := PyHoistHead;
  PyHoistHead := -1;
  while h >= 0 do
  begin
    node := ASTLeft[h];
    if node >= 0 then Result := PySeqAppend(Result, node);
    h := ASTRight[h];
  end;
end;

function PySeqAppend(head, stmt: Integer): Integer;
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

function PyTypeFromTokenIndex(i: Integer): TTypeKind;
var lo: AnsiString;
begin
  Result := tyUnknown;
  if (i < 0) or (i >= TokCount) then Exit;
  case Tokens[i].Kind of
    tkInteger: Result := tyInteger;
    tkFloat: Result := tyDouble;
    tkString: Result := tyString;
    tkTrue, tkFalse: Result := tyBoolean;
    tkInteger_T: Result := tyInteger;
    tkBoolean_T: Result := tyBoolean;
    tkString_T: Result := tyString;
    tkReal_T, tkSingle_T, tkDouble_T, tkExtended_T: Result := tyDouble;
    tkIdent:
    begin
      lo := LowerCase(GetTokenStr(i));
      if lo = 'int' then Result := tyInt64   { NilPy int = a 64-bit cell }
      else if lo = 'float' then Result := tyDouble
      else if lo = 'bool' then Result := tyBoolean
      else if lo = 'str' then Result := tyString
      else if IsClassType(GetTokenStr(i)) then Result := tyClass;
    end;
  end;
end;

(* An open brace starts a set OR a dict, and Python decides on the punctuation
   inside: comma-separated is a set, colon-separated is a dict, and an EMPTY
   pair of braces is a DICT (Python has no empty-set literal). Look for a ':'
   at bracket depth 1 relative to the opening brace at index i — depth counts
   parens, brackets and braces alike, so a ':' inside a nested call, slice or
   literal does not vote.
   Braces are spelled out in prose here on purpose: a literal brace inside a
   brace-delimited comment desyncs the self-host lexer
   (project_nested_comment_brace_selfhost_landmine). *)
function PyDictLiteralAt(i: Integer): Boolean;
var depth: Integer;
begin
  Result := False;
  if (i + 1 < TokCount) and (Tokens[i + 1].Kind = tkEnd) then
  begin
    Result := True;             (* empty braces = empty dict, not empty set *)
    Exit;
  end;
  depth := 0;
  while i < TokCount do
  begin
    if Tokens[i].Kind in [tkBegin, tkLBrack, tkLParen] then Inc(depth)
    else if Tokens[i].Kind in [tkEnd, tkRBrack, tkRParen] then
    begin
      Dec(depth);
      if depth = 0 then Exit;
    end
    else if (depth = 1) and (Tokens[i].Kind = tkColon) then
    begin
      Result := True;
      Exit;
    end
    else if (depth = 1) and (Tokens[i].Kind = tkStar) and
            (i + 1 < TokCount) and (Tokens[i + 1].Kind = tkStar) then
    begin
      { `{**a, **b}` is a DICT with no colon in it at all — the spread is what
        marks it. Without this it read as a set literal and failed to parse. }
      Result := True;
      Exit;
    end;
    Inc(i);
  end;
end;

(* Is the bracket group opening at token index i a SLICE rather than a plain
   subscript? Same depth-1 colon scan as PyDictLiteralAt: a ':' belonging to a
   nested call, dict literal or inner slice does not vote. The lvalue subscript
   path has to know BEFORE it commits, because the default-indexed-property
   machinery consumes the bracket itself. *)
function PySliceBracketAt(i: Integer): Boolean;
var depth: Integer;
begin
  Result := False;
  depth := 0;
  while i < TokCount do
  begin
    if Tokens[i].Kind in [tkBegin, tkLBrack, tkLParen] then Inc(depth)
    else if Tokens[i].Kind in [tkEnd, tkRBrack, tkRParen] then
    begin
      Dec(depth);
      if depth = 0 then Exit;
    end
    else if (depth = 1) and (Tokens[i].Kind = tkColon) then
    begin
      Result := True;
      Exit;
    end;
    Inc(i);
  end;
end;

(* Is CurTok the '(' of a TUPLE — a parenthesised group with a top-level
   comma — rather than a plain parenthesised expression? Only the `in` RHS
   needs to know: `x in ("a", "b")` is membership over a tuple, while `(a)` is
   just grouping. Same depth-1 scan as PyDictLiteralAt. *)
{ Index-based twin of PyTupleParenAhead, for the token scanners that work off
  an index rather than the cursor. }
function PyTupleParenAt(i: Integer): Boolean;
var depth: Integer;
begin
  Result := False;
  if (i >= TokCount) or (Tokens[i].Kind <> tkLParen) then Exit;
  depth := 0;
  while i < TokCount do
  begin
    if Tokens[i].Kind in [tkBegin, tkLBrack, tkLParen] then Inc(depth)
    else if Tokens[i].Kind in [tkEnd, tkRBrack, tkRParen] then
    begin
      Dec(depth);
      if depth = 0 then Exit;
    end
    else if (depth = 1) and (Tokens[i].Kind = tkComma) then
    begin
      Result := True;
      Exit;
    end;
    Inc(i);
  end;
end;

function PyTupleParenAhead: Boolean;
var i, depth: Integer;
begin
  Result := False;
  if CurTok.Kind <> tkLParen then Exit;
  i := TokPos - 1;
  depth := 0;
  while i < TokCount do
  begin
    if Tokens[i].Kind in [tkBegin, tkLBrack, tkLParen] then Inc(depth)
    else if Tokens[i].Kind in [tkEnd, tkRBrack, tkRParen] then
    begin
      Dec(depth);
      if depth = 0 then Exit;
    end
    else if (depth = 1) and (Tokens[i].Kind = tkComma) then
    begin
      Result := True;
      Exit;
    end;
    Inc(i);
  end;
end;

function PyDictLiteralAhead: Boolean;
begin
  Result := PyDictLiteralAt(TokPos - 1);   (* TokPos-1 = the opening brace *)
end;

var
  PyLastTypeCi: Integer;  { class index when PyParseType returned tyClass }
  PyAnnLastCi: Integer;   { class index when PyAnnTypeAt returned tyClass }
  { Signature proc index when PyAnnTypeAt saw a `Callable[[...], R]` — the same
    `$proctype` shape a Pascal procedural type registers, so an indirect call
    through the value marshals through the machinery that already exists
    (feature-nilpy-function-values). -1 when the annotation was not Callable. }
  PyAnnLastProcSig: Integer;
  PyCountAlias: AnsiString;  { local name bound to itertools.count ('' = none) }
  { Names a module pulled in with `from X import name`, tagged with the
    IMPORTING module's unit index. Unit scope in this compiler is flat, so a
    name another module imported is findable from everywhere — which is wrong
    for a builtin spelling: songformatter's convertrawtext.py writes `from
    settings import get, set`, and that must shadow `set` in convertrawtext
    ALONE, not inside key_analysis.py, where `set(MODE_INTERVALS[mode])` is the
    builtin. Python scopes a name to the module that imported it, so record who
    imported what and ask this table rather than the global one.
    bug-nilpy-imported-name-shadows-builtin-everywhere. }
  PyOptMissingSym: array[0..127] of Integer;  { interned names bound to None by an unresolved optional import }
  PyExprHadOptionalMissing: Boolean;  { the expression just parsed reached an unavailable module }
  PyOptMissingCount: Integer;
  PyImpName: array[0..255] of Integer;      { interned lowercase name }
  PyImpNameUnit: array[0..255] of Integer;  { CurrentUnitIdx of the importer }
  PyImpNameCount: Integer;
  { True only while parsing a def's RETURN annotation: there Optional[int] maps
    to tyVariant (None = VT_EMPTY tag) instead of the tyInt64 0-sentinel, so
    `return d.get(k)` hands back a None distinguishable from a legitimate 0
    (decide-nilpy-optional-int-none-vs-zero). FIELDS and params keep the
    0-sentinel mapping, which existing consumers (fpjson) rely on. }
  PyAnnRetScope: Boolean;

{ Token-index annotation parser for the richer grammar dataclass fields use:
    NAME | NAME '[' ann {',' ann} ']' | "ForwardRef" | None
  v1 mapping (uforth rung): Optional[X] -> X with nil/0 for None (an
  Optional[int] whose legit value could be 0 would alias the sentinel — noted
  in the ticket; honest variant-tagged fields come later), Callable[...] ->
  tyPointer, Any -> tyVariant, container types (List/Dict/Tuple/Set) remain a
  clean unsupported error. Advances i past the annotation. }
function PyAnnTypeAt(var i: Integer): TTypeKind; forward;

{ ONE annotation term. PyAnnTypeAt below layers PEP 604 unions (`int | None`)
  over this, so every caller gets union support for free. }
function PyAnnTypeTermAt(var i: Integer): TTypeKind;
var lo: AnsiString; depth: Integer;
    sigN, sigPi: Integer; sigIsFunc: Boolean; sigRet: TTypeKind;
    sigPNames: array[0..15] of AnsiString;
    sigPTypes: array[0..15] of TTypeKind;
    sigPCis: array[0..15] of Integer;
begin
  Result := tyUnknown;
  PyAnnLastCi := -1;
  PyAnnLastProcSig := -1;
  if i >= MainProgramTokCount then Exit;
  if Tokens[i].Kind = tkString then
  begin
    { forward reference: "VM" }
    PyAnnLastCi := FindUClass(GetTokenStr(i));
    if PyAnnLastCi >= 0 then Result := tyClass;
    Inc(i);
    Exit;
  end;
  if Tokens[i].Kind = tkNil then begin Inc(i); Exit; end;
  if Tokens[i].Kind <> tkIdent then Exit;
  lo := LowerCase(GetTokenStr(i));
  if lo = 'int' then begin Result := tyInt64; Inc(i); Exit; end;   { 64-bit cell }
  if lo = 'float' then begin Result := tyDouble; Inc(i); Exit; end;
  if lo = 'bool' then begin Result := tyBoolean; Inc(i); Exit; end;
  if lo = 'str' then
  begin
    { NilPy strings are MANAGED (unbounded) — the same tyAnsiString locals and
      fields already use. Returning the FROZEN tyString here left `def f(s: str)`
      params frozen (255-char ceiling; and a variant arg unboxed to a managed
      handle then mismarshalled as a frozen slot -> garbage). One place, so the
      param header and the class pre-pass agree. }
    if PyProgramMode then Result := tyAnsiString else Result := tyString;
    Inc(i); Exit;
  end;
  if lo = 'any' then begin Result := tyVariant; Inc(i); Exit; end;
  { `bytes` / `bytearray` annotate the pylib TPyBytes class — the same object
    bytearray(n) returns, so an annotated parameter and an inferred local agree. }
  if (lo = 'bytes') or (lo = 'bytearray') then
  begin
    PyAnnLastCi := FindUClass('TPyBytes');
    if PyAnnLastCi >= 0 then Result := tyClass else Result := tyUnknown;
    Inc(i);
    Exit;
  end;
  if lo = 'optional' then
  begin
    Inc(i);
    if (i < MainProgramTokCount) and (Tokens[i].Kind = tkLBrack) then
    begin
      Inc(i);
      Result := PyAnnTypeAt(i);
      if (i < MainProgramTokCount) and (Tokens[i].Kind = tkRBrack) then Inc(i);
      { Optional[int]: None maps to 0 (see header note) — widen to 64-bit so
        the sentinel space is the full address range }
      if Result = tyInteger then Result := tyInt64;
      if Result = tyString then Result := tyAnsiString;
      { RETURN annotations only: an Optional[int] result is a real variant so
        None (VT_EMPTY) and a legitimate 0 stay distinct — with the 0-sentinel
        `if x is not None` took the wrong branch on a valid 0 (uforth's
        _lookup_local_slot, slot 0 read as absent). }
      if PyAnnRetScope and (Result = tyInt64) then Result := tyVariant;
    end;
    Exit;
  end;
  if lo = 'callable' then
  begin
    { `Callable[[P1, P2], R]` — the parameter list and result really are parsed
      now, into a `$proctype` signature Proc (BodyAddr = -1), exactly as a Pascal
      procedural type registers one. The bracket group used to be SKIPPED, which
      left the value an untyped pointer: it could be passed around but never
      called, since the call site had no signature to marshal against
      (feature-nilpy-function-values). }
    Inc(i);
    sigN := 0;
    sigIsFunc := False;
    sigRet := tyInteger;
    if (i < MainProgramTokCount) and (Tokens[i].Kind = tkLBrack) then
    begin
      Inc(i);
      { the PARAMETER list — `[P1, P2]` or `[]` }
      if (i < MainProgramTokCount) and (Tokens[i].Kind = tkLBrack) then
      begin
        Inc(i);
        while (i < MainProgramTokCount) and (Tokens[i].Kind <> tkRBrack) do
        begin
          if sigN >= 16 then Error('Nil Python: too many Callable parameters');
          if PyAnnTypeAt(i) = tyUnknown then
            Error('Nil Python: unsupported Callable parameter type');
          { Parameters follow the same function-object ABI as the result: the
            annotation is a hint, the def that arrives here decides nothing, so
            both ends pass variants (by reference, nilpy's variant convention).
            A `Callable[[str], ...]` handed a def with an unannotated (variant)
            parameter used to pass an AnsiString by value into a slot the callee
            dereferenced as a variant address. }
          sigPTypes[sigN] := tyVariant;
          sigPCis[sigN] := -1;
          sigPNames[sigN] := 'p' + PyIntLiteralText(sigN);
          Inc(sigN);
          if (i < MainProgramTokCount) and (Tokens[i].Kind = tkComma) then Inc(i);
        end;
        if (i < MainProgramTokCount) and (Tokens[i].Kind = tkRBrack) then Inc(i);
      end;
      if (i < MainProgramTokCount) and (Tokens[i].Kind = tkComma) then Inc(i);
      { the RESULT — `None` for a procedure, else a type }
      if (i < MainProgramTokCount) and (Tokens[i].Kind = tkNil) then Inc(i)
      else
      begin
        sigRet := PyAnnTypeAt(i);
        sigIsFunc := sigRet <> tyUnknown;
        if not sigIsFunc then sigRet := tyInteger
        else
          { The declared result is a HINT, not an ABI: this signature marshals
            calls to whichever def is passed in, and that def's own inference
            may well disagree (`-> list[str]` vs a body returning `d.get(k, [])`,
            which is a variant). Both ends therefore use the variant
            hidden-destination convention — see PyDefUsedAsValue. }
          sigRet := tyVariant;
      end;
      if (i < MainProgramTokCount) and (Tokens[i].Kind = tkRBrack) then Inc(i);
    end;
    sigPi := RegisterProc('$proctype', sigIsFunc, sigRet, sigN, sigPNames, sigPTypes);
    Procs[sigPi].BodyAddr := -1;
    { Record each class-typed Callable-parameter's rec id in ProcParamRecId —
      the per-param class store the call-marshalling path actually reads
      (ir.inc coerceParamSym / LastTypeRecId). RegisterProc leaves every raw
      param's Params[].SymIdx = -1 (no allocated Syms entry), so the old
      `Syms[Procs[sigPi].Params[depth].SymIdx].RecName := ...` was `Syms[-1]` —
      a latent out-of-bounds write 40 bytes before the Syms base (silent when
      it lands on padding, memory-corrupting when a layout shift puts a live
      block there) that ALSO never recorded the class (nothing reads a raw
      param's Syms RecName). }
    for depth := 0 to sigN - 1 do
      if (sigPTypes[depth] = tyClass) and (sigPCis[depth] >= 0) and
         (depth < MAX_PROC_PARAMS) then
        ProcParamRecId[sigPi * MAX_PROC_PARAMS + depth] :=
          REC_UCLASS_BASE + sigPCis[depth];
    PyAnnLastProcSig := sigPi;
    Result := tyPointer;
    Exit;
  end;
  if lo = 'list' then
  begin
    Inc(i);
    if (i < MainProgramTokCount) and (Tokens[i].Kind = tkLBrack) then
    begin
      depth := 1; Inc(i);
      while (i < MainProgramTokCount) and (depth > 0) do
      begin
        if Tokens[i].Kind = tkLBrack then Inc(depth)
        else if Tokens[i].Kind = tkRBrack then Dec(depth);
        Inc(i);
      end;
    end;
    Result := tyClass;   { TPyList; element types are dynamic (variant slots) }
    PyAnnLastCi := FindUClass('TPyList');
    Exit;
  end;
  if lo = 'dict' then
  begin
    Inc(i);
    if (i < MainProgramTokCount) and (Tokens[i].Kind = tkLBrack) then
    begin
      depth := 1; Inc(i);
      while (i < MainProgramTokCount) and (depth > 0) do
      begin
        if Tokens[i].Kind = tkLBrack then Inc(depth)
        else if Tokens[i].Kind = tkRBrack then Dec(depth);
        Inc(i);
      end;
    end;
    Result := tyClass;   { TPyDict; key and value types are dynamic (variant slots) }
    PyAnnLastCi := FindUClass('TPyDict');
    Exit;
  end;
  if lo = 'set' then
  begin
    { A set is BACKED BY TPyList — the brace literal already lowers that way,
      `in` already scans it, and TPyList.add appends only when absent, which
      is the whole set contract uforth uses (a membership guard). Not a hash
      set: same reasoning as TPyDict's linear scan. Ordering is insertion
      order rather than Python's arbitrary order, which is a DIFFERENCE, not
      a bug to chase — Python's set order is unspecified, so no correct
      program can depend on it. }
    Inc(i);
    if (i < MainProgramTokCount) and (Tokens[i].Kind = tkLBrack) then
    begin
      depth := 1; Inc(i);
      while (i < MainProgramTokCount) and (depth > 0) do
      begin
        if Tokens[i].Kind = tkLBrack then Inc(depth)
        else if Tokens[i].Kind = tkRBrack then Dec(depth);
        Inc(i);
      end;
    end;
    Result := tyClass;
    PyAnnLastCi := FindUClass('TPyList');
    Exit;
  end;
  if lo = 'tuple' then
  begin
    { A tuple annotation is TPyList, which is the representation the rest of the
      frontend ALREADY assumes: `isinstance(x, tuple)` tests TPyList (see
      PyIsInstance), and a tuple display lowers to a list. Annotations are
      erased anyway — they pick a type for inference, and TPyList is the right
      one for something indexed, iterated and unpacked.

      The DIFFERENCE from CPython, deliberate and worth stating: a tuple is
      mutable here and is not hashable, so it cannot be a dict key. A program
      that keys a dict by a tuple will fail at that use site rather than
      silently misbehave. Immutability is not modelled anywhere in NilPy yet.

      Previously this was a hard error, which rejected a whole module for an
      annotation the compiler then erases — songformatter's key_analysis.py died
      on `tuple[str, float]` after passing everything else. }
    Inc(i);
    if (i < MainProgramTokCount) and (Tokens[i].Kind = tkLBrack) then
    begin
      depth := 1; Inc(i);
      while (i < MainProgramTokCount) and (depth > 0) do
      begin
        if Tokens[i].Kind = tkLBrack then Inc(depth)
        else if Tokens[i].Kind = tkRBrack then Dec(depth);
        Inc(i);
      end;
    end;
    Result := tyClass;
    PyAnnLastCi := FindUClass('TPyList');
    Exit;
  end;
  if IsClassType(GetTokenStr(i)) then
  begin
    Result := tyClass;
    PyAnnLastCi := FindUClass(GetTokenStr(i));
    Inc(i);
    Exit;
  end;
end;

{ PEP 604 unions: `int | None`, `str | None`, `A | B`.

  Python 3.10+ spells Optional[X] as `X | None`, and real code uses it far more
  than the typing spelling — songformatter's key_analysis.py has
  `-> int | None` and it rejected the whole module with "unexpected token".

  Annotations pick a type for inference and are then erased, so a union takes the
  first term that names a type. When one arm is None the union IS Optional, so it
  gets Optional's exact treatment (the widening below), which is what keeps
  `if x is not None` correct for a legitimate 0. A union of two real types
  (`int | str`) keeps the first: NilPy has no union type, and the alternative is
  rejecting code whose annotation it would have thrown away anyway. }
function PyAnnTypeAt(var i: Integer): TTypeKind;
var termT: TTypeKind; before, ci, sig: Integer; sawNone, first: Boolean;
begin
  Result := tyUnknown;
  ci := -1;
  sig := -1;
  sawNone := False;
  first := True;
  while True do
  begin
    before := i;
    if (i < MainProgramTokCount) and (Tokens[i].Kind = tkNil) then
      sawNone := True;
    termT := PyAnnTypeTermAt(i);
    if first or ((Result = tyUnknown) and (termT <> tyUnknown)) then
    begin
      if first or (termT <> tyUnknown) then
      begin
        Result := termT;
        ci := PyAnnLastCi;
        sig := PyAnnLastProcSig;
      end;
    end;
    first := False;
    if i = before then Inc(i);   { never spin on a term that consumed nothing }
    if (i < MainProgramTokCount) and (Tokens[i].Kind = tkPipe) then
      Inc(i)
    else
      Break;
  end;
  PyAnnLastCi := ci;
  PyAnnLastProcSig := sig;
  if sawNone then
  begin
    { same widening as Optional[...] — see the note there }
    if Result = tyInteger then Result := tyInt64;
    if Result = tyString then Result := tyAnsiString;
    if PyAnnRetScope and (Result = tyInt64) then Result := tyVariant;
  end;
end;

function PyParseType: TTypeKind;
var i: Integer;
begin
  { full annotation grammar (Optional/Callable/Any/List/forward refs) via the
    token-index parser, then resync the stream }
  i := TokPos - 1;
  Result := PyAnnTypeAt(i);
  if Result = tyUnknown then
    Error('Nil Python: expected type annotation (int, float, bool, str, Any, Optional/Callable/List[...], or a class name)');
  PyLastTypeCi := PyAnnLastCi;
  TokPos := i;
  Next;
end;

function PyNumeric(tk: TTypeKind): Boolean;
begin
  Result := (tk = tyInteger) or (tk = tyInt64) or (tk = tySingle) or
            (tk = tyDouble) or (tk = tyExtended);
end;

function PyVariantScalar(tk: TTypeKind): Boolean;
begin
  Result := PyNumeric(tk) or (tk = tyBoolean) or (tk = tyChar) or
            (tk = tyString) or (tk = tyAnsiString);
end;

var
  PyInferName: AnsiString;  { name under type inference, for diagnostics }
  PyWidenA, PyWidenB: TTypeKind;
  PyInferLastCi: Integer;   { class index of the last tyClass inference result }

function PyWidenErr: AnsiString;
begin
  Result := 'Nil Python: annotate the type / too dynamic [a=' +
            AIntToStr(Ord(PyWidenA)) + ' b=' + AIntToStr(Ord(PyWidenB)) + ']';
  if PyInferName <> '' then Result := Result + ' (inferring ' + PyInferName + ')';
end;

function PyWiden(a, b: TTypeKind): TTypeKind;
begin
  PyWidenA := a; PyWidenB := b;
  if a = tyUnknown then begin Result := b; Exit; end;
  if b = tyUnknown then begin Result := a; Exit; end;
  if a = b then begin Result := a; Exit; end;
  if TypeIsPromoInt(a) or TypeIsPromoInt(b) then
  begin
    { Promotable int (a wide literal, or an expression it infected). It joins a
      VARIANT as a variant — a promo boxes into one (inline -> VT_INT64, heap ->
      VT_PROMO_INT64) — and stays PROMO among machine ints, which is what
      carries `x & 0xFFFFFFFFFFFFFFFF` through the scalar binop typing.
      Promo + float has no scalar lowering; error honestly (annotate). }
    if (a = tyVariant) or (b = tyVariant) then
      Result := tyVariant
    else if (TypeIsPromoInt(a) or (a = tyInteger) or (a = tyInt64) or (a = tyBoolean)) and
            (TypeIsPromoInt(b) or (b = tyInteger) or (b = tyInt64) or (b = tyBoolean)) then
      Result := tyPromoInt64
    else
    begin
      Error(PyWidenErr);
      Result := tyUnknown;
    end;
    Exit;
  end;
  if (a = tyVariant) or (b = tyVariant) then
  begin
    { A class (list/dict/object) boxes into a variant as VT_OBJECT — the same
      representation container slots and isinstance already use — so a local
      that is a `.get()` result (variant) one moment and a `{...}` literal
      (tyClass) the next widens to variant rather than erroring. }
    if ((a = tyVariant) or PyVariantScalar(a) or (a = tyClass)) and
       ((b = tyVariant) or PyVariantScalar(b) or (b = tyClass)) then
    begin
      Result := tyVariant;
      Exit;
    end;
    Error(PyWidenErr);
  end;
  if PyNumeric(a) and PyNumeric(b) then
  begin
    if (a = tyDouble) or (b = tyDouble) or (a = tyExtended) or (b = tyExtended) then
      Result := tyDouble
    else if (a = tyInt64) or (b = tyInt64) then
      Result := tyInt64
    else
      Result := tyInteger;
    Exit;
  end;
  { string ⊕ char (e.g. `res = res + c`) stays a string — widening to variant
    here would poison the local: a variant scalar-loaded on `return` yields
    its tag word, not the payload. }
  if ((a = tyString) or (a = tyAnsiString)) and (b = tyChar) then
  begin
    Result := a;
    Exit;
  end;
  if (a = tyChar) and ((b = tyString) or (b = tyAnsiString)) then
  begin
    Result := b;
    Exit;
  end;
  { The two string kinds are ONE Python type. A literal is born tyString and a
    concat / pystr_* result is tyAnsiString, so a local built up by `cur = cur
    + c` sees both; without this the pair fell through to the variant rule and
    the local was scalar-loaded as a tagged value.

    tyAnsiString (MANAGED) wins. tyString is the frozen, length-prefixed kind
    with a 255-character ceiling, so an inferred local silently STOPPED GROWING
    at 255 while a str FIELD — mapped to tyAnsiString explicitly — did not:
    the same expression meant two different things depending on where its
    result was stored, and only one of them was Python
    (bug-nilpy-string-local-truncates-at-255). The earlier attempt at this
    corrupted the heap through the scalar->Variant boxing bug
    (bug-a-str-boxed-into-variant-does-not-own-bytes), which is now fixed. }
  if ((a = tyString) or (a = tyAnsiString)) and
     ((b = tyString) or (b = tyAnsiString)) then
  begin
    Result := tyAnsiString;
    Exit;
  end;
  { Two kinds that share no scalar representation but both BOX: a variant holds
    either, a scalar by value and a class as VT_OBJECT — exactly what the
    class-meets-variant rule above already relies on. This is what a plain
    rebinding needs: convertrawtext.py sets `temp_file = 'tmppdf.pdf'` and then
    `temp_file = tempfile.NamedTemporaryFile(...)`, which Python allows and
    which used to be rejected as "too dynamic". }
  if (PyVariantScalar(a) or (a = tyClass)) and
     (PyVariantScalar(b) or (b = tyClass)) then
  begin
    Result := tyVariant;
    Exit;
  end;
  Error(PyWidenErr);
  Result := tyUnknown;
end;

procedure PyInitVariantLocals(scopeBase: Integer);
var i: Integer;
begin
  for i := scopeBase to SymCount - 1 do
    if (Syms[i].Kind = skLocal) and (Syms[i].TypeKind = tyVariant) then
    begin
      EmitB($48); EmitB($C7); EmitB($85); EmitI32(Syms[i].Offset); EmitI32(0);
      EmitB($48); EmitB($C7); EmitB($85); EmitI32(Syms[i].Offset + 8); EmitI32(0);
    end;
end;

{ Nil Python boolean-expression layer: Python precedence (or < and < not <
  comparison), unlike Pascal where and/or bind tighter than comparison. The
  comparison/arithmetic atom is parsed by the shared ParseExpr, whose and/or/not
  consumption is suppressed while PyExprMode is set; parenthesised sub-expressions
  re-enter PyParseBoolExpr (see ParseFactor). Result in CurASTNode. }
{ Reject a boolean operand adjacent to a bitwise operator: Python binds
  comparisons LOOSER than & | ^ << >>, the shared ParseExpr atom binds them
  tighter, so the unparenthesized mixed case would silently change meaning.
  Explicit parens express either reading. }
procedure PyBitGuard(n: Integer);
begin
  if IntToTypeKind(ASTTk[n]) = tyBoolean then
    Error('Nil Python: parenthesize the comparison next to a bitwise operator');
end;

{ Names bound to None because the optional import they came from did not
  resolve. Kept so a USE of such a name can be turned into a runtime failure
  that names the module, instead of a compile error about a missing method —
  CPython compiles the same file and raises only if the code runs.
  feature-nilpy-fallback-import. }
function PyOptionalMissingNamed(const nm: AnsiString): Boolean;
var i, ni: Integer;
begin
  PyOptionalMissingNamed := False;
  if nm = '' then Exit;
  ni := InternStr(LowerCase(nm));
  for i := 0 to PyOptMissingCount - 1 do
    if PyOptMissingSym[i] = ni then begin PyOptionalMissingNamed := True; Exit; end;
end;

procedure PyNoteOptionalMissingName(const nm: AnsiString);
begin
  if PyOptionalMissingNamed(nm) then Exit;
  if PyOptMissingCount >= 128 then Exit;
  PyOptMissingSym[PyOptMissingCount] := InternStr(LowerCase(nm));
  Inc(PyOptMissingCount);
end;

{ Tracked by NAME, not by symbol index: NilPy parses a body more than once
  (the module-local pre-pass trial-parses; def bodies compile from stored token
  positions), and a fresh pass allocates fresh symbols. A name is stable. }
{ Does the ENCLOSING function assign this name AFTER the nested def being
  parsed? Python binds a closure at CALL time, so a name assigned further down
  is an ordinary capture that simply has no symbol yet at this point. The scan
  starts past the DEDENT(s) that close the nested def itself.
  bug-nilpy-closure-capture-assigned-later. }
function PyEnclosingAssigns(fromTok: Integer; const nm: AnsiString): Boolean;
var i, depth: Integer;
begin
  PyEnclosingAssigns := False;
  i := fromTok;
  while (i < MainProgramTokCount) and (Tokens[i].Kind in [tkDedent, tkNewline]) do Inc(i);
  depth := 0;
  while i < MainProgramTokCount do
  begin
    if Tokens[i].Kind = tkIndent then Inc(depth)
    else if Tokens[i].Kind = tkDedent then
    begin
      Dec(depth);
      if depth < 0 then Exit;          { left the enclosing body }
    end
    else if (Tokens[i].Kind = tkIdent) and (i + 1 < MainProgramTokCount) and
            (Tokens[i + 1].Kind = tkAssign) and (GetTokenStr(i) = nm) then
    begin
      PyEnclosingAssigns := True;
      Exit;
    end;
    Inc(i);
  end;
end;

function PyIsOptionalMissingNode(n: Integer): Boolean;
begin
  PyIsOptionalMissingNode := False;
  if n < 0 then Exit;
  if ASTKind[n] <> AN_IDENT then Exit;
  PyIsOptionalMissingNode := PyOptionalMissingNamed(Syms[ASTIVal[n]].Name);
end;

function PyOptionalMissingName(n: Integer): AnsiString;
begin
  PyOptionalMissingName := Syms[ASTIVal[n]].Name;
end;

{ A value taken FROM an unavailable optional module is itself unavailable:
  `img = Image.open(f)` then `img.resize(...)`. Marking the target keeps the
  whole chain compiling and failing at the first call that runs. }
{ Keyed off a FLAG rather than the RHS node: the expression layers wrap a call
  (coercions, boxing), so testing the node kind missed the very case this is
  for. The flag is set wherever an unavailable-module call is built and read
  here, at the assignment that stores its result. }
procedure PyNoteOptionalTaint(symIdx, rhsNode: Integer);
begin
  if symIdx < 0 then Exit;
  if not PyExprHadOptionalMissing then Exit;
  PyNoteOptionalMissingName(Syms[symIdx].Name);
end;

{ Swallow a trailing `.name(...)` chain on an unavailable value:
  `ImageDraw.Draw(mask).rectangle(...)`. Every link is equally unavailable, so
  the whole chain collapses onto the single raise the head produced, and the
  parser lands where the statement ends. Without this the call result was
  parsed and the '.' after it had nothing to attach to. }
procedure PySkipOptionalMissingChain;
var depth: Integer;
begin
  { the head call's OWN argument list first — the dispatch site hands control
    here before those arguments have been consumed }
  if CurTok.Kind = tkLParen then
  begin
    depth := 0;
    while CurTok.Kind <> tkEOF do
    begin
      if CurTok.Kind = tkLParen then Inc(depth)
      else if CurTok.Kind = tkRParen then
      begin
        Dec(depth);
        if depth = 0 then begin Next; Break; end;
      end;
      Next;
    end;
  end;
  while (CurTok.Kind = tkDot) and (TokPos < TokCount) and
        (Tokens[TokPos].Kind = tkIdent) do
  begin
    Next;                              { '.' }
    Next;                              { member name }
    if CurTok.Kind <> tkLParen then Exit;
    depth := 0;
    while CurTok.Kind <> tkEOF do
    begin
      if CurTok.Kind = tkLParen then Inc(depth)
      else if CurTok.Kind = tkRParen then
      begin
        Dec(depth);
        if depth = 0 then begin Next; Break; end;
      end;
      Next;
    end;
  end;
end;

function PyMakeOptionalMissingCall(const what: AnsiString): Integer;
var procIdx, argNode, litNode: Integer;
begin
  procIdx := FindProc('pyoptional_missing');
  if procIdx < 0 then Error('Nil Python: pylib (pyoptional_missing) not loaded');
  litNode := AllocNode(AN_STR_LIT);
  ASTSOffset[litNode] := PyStoredName(what);
  ASTSLen[litNode] := Length(what);
  ASTTk[litNode] := Ord(tyString);
  argNode := AllocNode(AN_ARG);
  ASTLeft[argNode] := litNode;
  ASTRight[argNode] := -1;
  PyMakeOptionalMissingCall := AllocNode(AN_CALL);
  ASTIVal[PyMakeOptionalMissingCall] := procIdx;
  ASTLeft[PyMakeOptionalMissingCall] := argNode;
  ASTTk[PyMakeOptionalMissingCall] := Ord(tyVariant);
  LastExprTk := tyVariant;
  PyExprHadOptionalMissing := True;
  PySkipOptionalMissingChain;
end;

{ isinstance(x, T) / isinstance(x, (T1, T2, ...)) — desugared to tag checks
  on variants (int also accepts bool, like CPython) and closed-world
  AN_IS_TEST class checks; a variant operand is unboxed via pylib pyvarobj.
  The operand subtree is re-emitted per OR term (pure idents in the corpus;
  a side-effecting operand would double-evaluate — b346 family, noted). }
procedure PyParseIsinstance;
var xNode, node, left, term, callN, argN, tagCall: Integer;
    isVar, hadTuple: Boolean; nm: AnsiString; ci: Integer;

  function TagEq(tagConst: Int64): Integer;
  var c, a, e: Integer;
  begin
    a := AllocNode(AN_ARG);
    ASTLeft[a] := xNode;
    c := AllocNode(AN_CALL);
    ASTIVal[c] := FindProc('pyvartag');
    if ASTIVal[c] < 0 then Error('Nil Python: pylib (pyvartag) not loaded');
    ASTTk[c] := Ord(tyInt64);
    ASTLeft[c] := a;
    e := AllocNode(AN_INT_LIT);
    ASTIVal[e] := tagConst;
    ASTTk[e] := Ord(tyInt64);
    Result := AllocNode(AN_BINOP);
    ASTIVal[Result] := Ord(tkEq);
    ASTLeft[Result] := c; ASTRight[Result] := e;
    ASTTk[Result] := Ord(tyBoolean);
  end;

  function OrJoin(a, b: Integer): Integer;
  begin
    if a < 0 then begin Result := b; Exit; end;
    Result := AllocNode(AN_BINOP);
    ASTIVal[Result] := Ord(tkOr);
    ASTLeft[Result] := a; ASTRight[Result] := b;
    ASTTk[Result] := Ord(tyBoolean);
  end;

begin
  Next;                     { 'isinstance' }
  Expect(tkLParen, '(');
  PyParseBoolExpr;
  xNode := CurASTNode;
  isVar := IntToTypeKind(ASTTk[xNode]) = tyVariant;
  Expect(tkComma, ',');
  left := -1;
  hadTuple := CurTok.Kind = tkLParen;
  if hadTuple then Next;                 { optional tuple of types }
  repeat
    if CurTok.Kind <> tkIdent then Error('Nil Python: expected a type in isinstance');
    nm := LowerCase(CurTok.SVal);
    if nm = 'int' then
      { VT_PROMO_INT64: a heap-tier promotable int (a masked cell past 2^63)
        is still Python `int` — without this, uforth's push() normalization
        skipped exactly the values that most needed it }
      term := OrJoin(OrJoin(OrJoin(TagEq(VT_INT), TagEq(VT_INT64)), TagEq(VT_BOOL)),
                     TagEq(VT_PROMO_INT64))
    else if nm = 'float' then term := TagEq(VT_DOUBLE)
    else if nm = 'str' then term := TagEq(VT_STRING)
    else if nm = 'bool' then term := TagEq(VT_BOOL)
    else
    begin
      { Python's container type NAMES map to the pylib classes that back them;
        `list` etc. are not user classes, so FindUClass alone never found them.
        `tuple` is TPyList because that is how a tuple is represented. }
      if (nm = 'list') or (nm = 'tuple') then ci := FindUClass('TPyList')
      else if nm = 'dict' then ci := FindUClass('TPyDict')
      else if (nm = 'bytes') or (nm = 'bytearray') then ci := FindUClass('TPyBytes')
      else ci := FindUClass(CurTok.SVal);
      if ci < 0 then Error('Nil Python: unknown type in isinstance: ' + CurTok.SVal);
      if isVar then
      begin
        { (tag == VT_OBJECT) and (pyvarobj(x) is C) }
        argN := AllocNode(AN_ARG);
        ASTLeft[argN] := xNode;
        callN := AllocNode(AN_CALL);
        ASTIVal[callN] := FindProc('pyvarobj');
        if ASTIVal[callN] < 0 then Error('Nil Python: pylib (pyvarobj) not loaded');
        ASTTk[callN] := Ord(tyPointer);
        ASTLeft[callN] := argN;
        node := AllocNode(AN_IS_TEST);
        ASTLeft[node] := callN;
        ASTIVal[node] := ci;
        ASTTk[node] := Ord(tyBoolean);
        tagCall := TagEq(VT_OBJECT);
        term := AllocNode(AN_BINOP);
        ASTIVal[term] := Ord(tkAnd);
        ASTLeft[term] := tagCall; ASTRight[term] := node;
        ASTTk[term] := Ord(tyBoolean);
      end
      else
      begin
        node := AllocNode(AN_IS_TEST);
        ASTLeft[node] := xNode;
        ASTIVal[node] := ci;
        ASTTk[node] := Ord(tyBoolean);
        term := node;
      end;
    end;
    Next;
    left := OrJoin(left, term);
  until not Eat(tkComma);
  { Close exactly what was opened. The old form treated the FIRST ')' as the
    tuple's and swallowed a following one as the call's — so a bare
    `isinstance(x, int)` whose ')' was immediately followed by another, as in
    `max(v for v in xs if isinstance(v, int))`, ate the genexpr's closer and
    the parse ran off the end of the program. }
  if hadTuple then Expect(tkRParen, ')');   { tuple close }
  Expect(tkRParen, ')');                    { call close }
  CurASTNode := left;
end;

{ Bitwise-not / comparison+arithmetic atom. `~` binds like a unary op. }
procedure PyParseBitOperand;
var node: Integer;
begin
  if PyIsIdent('isinstance') and (TokPos < TokCount) and
     (Tokens[TokPos].Kind = tkLParen) then
  begin
    PyParseIsinstance;
    Exit;
  end;
  if CurTok.Kind = tkLogNot then
  begin
    Next;
    PyParseBitOperand;
    PyBitGuard(CurASTNode);
    node := AllocNode(AN_NOT);
    ASTLeft[node] := CurASTNode;
    ASTTk[node] := ASTTk[CurASTNode];   { integer-typed AN_NOT = bitwise not }
    CurASTNode := node;
  end
  else
    ParseExpr;   { comparison + arithmetic atom }
end;

procedure PyParseShift;
var left, right, node: Integer; op: TTokenKind; w: TTypeKind;
begin
  PyParseBitOperand;
  left := CurASTNode;
  while (CurTok.Kind = tkShl) or (CurTok.Kind = tkShr) do
  begin
    op := CurTok.Kind;
    PyBitGuard(left); Next; PyParseBitOperand; right := CurASTNode; PyBitGuard(right);
    node := AllocNode(AN_BINOP); ASTIVal[node] := Ord(op);
    ASTLeft[node] := left; ASTRight[node] := right;
    { A shift of machine ints is typed PROMO: `1 << 64` must promote past
      Int64 (CPython), and Python's >> is arithmetic floor division while the
      native shr is logical — both need the promo runtime, unconditionally.
      Variant operands keep the variant typing; the variant binop routes
      shifts through the same runtime (NilPy-only op map). }
    w := PyWiden(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right]));
    if (w = tyInteger) or (w = tyInt64) or (w = tyBoolean) then
      w := tyPromoInt64;
    ASTTk[node] := Ord(w);
    left := node;
  end;
  CurASTNode := left;
end;

procedure PyParseBitAnd;
var left, right, node: Integer;
begin
  PyParseShift;
  left := CurASTNode;
  while CurTok.Kind = tkAmp do
  begin
    PyBitGuard(left); Next; PyParseShift; right := CurASTNode; PyBitGuard(right);
    node := AllocNode(AN_BINOP); ASTIVal[node] := Ord(tkAnd);
    ASTLeft[node] := left; ASTRight[node] := right;
    ASTTk[node] := Ord(PyWiden(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right])));
    left := node;
  end;
  CurASTNode := left;
end;

procedure PyParseBitXor;
var left, right, node: Integer;
begin
  PyParseBitAnd;
  left := CurASTNode;
  while CurTok.Kind = tkXor do
  begin
    PyBitGuard(left); Next; PyParseBitAnd; right := CurASTNode; PyBitGuard(right);
    node := AllocNode(AN_BINOP); ASTIVal[node] := Ord(tkXor);
    ASTLeft[node] := left; ASTRight[node] := right;
    ASTTk[node] := Ord(PyWiden(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right])));
    left := node;
  end;
  CurASTNode := left;
end;

procedure PyParseBitOr;
var left, right, node: Integer;
begin
  PyParseBitXor;
  left := CurASTNode;
  while CurTok.Kind = tkPipe do
  begin
    PyBitGuard(left); Next; PyParseBitXor; right := CurASTNode; PyBitGuard(right);
    node := AllocNode(AN_BINOP); ASTIVal[node] := Ord(tkOr);
    ASTLeft[node] := left; ASTRight[node] := right;
    ASTTk[node] := Ord(PyWiden(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right])));
    left := node;
  end;
  CurASTNode := left;
end;

{ `is` / `is not`: identity comparison. v1 lowers to pointer/scalar equality —
  correct for the None checks uforth uses (class refs and pointer fields
  compare against nil; Optional[int] fields compare against the 0 sentinel,
  consistent with that documented mapping). }
{ `pyvartag(v) = tag` (or <>), as a Boolean node. }
function PyMakeTagTest(xNode, tag: Integer; negate: Boolean): Integer;
var procIdx, argN, callN, litN: Integer;
begin
  procIdx := FindProc('pyvartag');
  if procIdx < 0 then Error('Nil Python: pylib (pyvartag) not loaded');
  argN := AllocNode(AN_ARG);
  ASTLeft[argN] := xNode;
  callN := AllocNode(AN_CALL);
  ASTIVal[callN] := procIdx;
  ASTTk[callN] := Ord(tyInt64);
  ASTLeft[callN] := argN;
  litN := AllocNode(AN_INT_LIT);
  ASTIVal[litN] := tag;
  ASTTk[litN] := Ord(tyInt64);
  Result := AllocNode(AN_BINOP);
  if negate then ASTIVal[Result] := Ord(tkNeq) else ASTIVal[Result] := Ord(tkEq);
  ASTLeft[Result] := callN;
  ASTRight[Result] := litN;
  ASTTk[Result] := Ord(tyBoolean);
end;

procedure PyParseIsCmp;
var left, right, node, i, j, ucCi, ucMmi: Integer; neg, dunderBuilt: Boolean; rTk: TTypeKind;
begin
  PyParseBitOr;
  left := CurASTNode;
  while PyIsIdent('is') or (CurTok.Kind = tkIn) or
        ((CurTok.Kind = tkNot) and (TokPos < TokCount) and
         (Tokens[TokPos].Kind = tkIn)) do
  begin
    if PyIsIdent('is') then
    begin
      Next;
      neg := False;
      if CurTok.Kind = tkNot then begin neg := True; Next; end;
      { `x is None` / `x is not None`. The lowering depends on the STATIC type of
        the left side — comparing a managed string or a scalar directly against a
        None variant read the wrong bytes and crashed. }
      if PyBareNoneHere then
      begin
        Next;
        rTk := IntToTypeKind(ASTTk[left]);
        if rTk = tyVariant then
          { VARIANT: a tag test (VT_EMPTY), not a payload compare — a payload
            compare answered True for a slot holding integer 0. }
          node := PyMakeTagTest(left, 0, neg)
        else if (rTk = tyString) or (rTk = tyAnsiString) or (rTk = tyChar) then
        begin
          { STRING: a content compare against None read the wrong bytes and
            crashed. Test the managed HANDLE for nil via pystr_is_none. }
          j := AllocNode(AN_ARG); ASTLeft[j] := left; ASTRight[j] := -1;
          node := AllocNode(AN_CALL);
          ASTIVal[node] := FindProc('pystr_is_none');
          if ASTIVal[node] < 0 then Error('Nil Python: pylib (pystr_is_none) not loaded');
          ASTTk[node] := Ord(tyBoolean); ASTLeft[node] := j;
          if neg then
          begin
            i := AllocNode(AN_NOT); ASTLeft[i] := node; ASTTk[i] := Ord(tyBoolean);
            node := i;
          end;
        end
        else
        begin
          { numeric (Optional[int]'s None sentinel is 0) and object/pointer (nil
            is None) both compare the value to 0. }
          node := AllocNode(AN_BINOP);
          if neg then ASTIVal[node] := Ord(tkNeq) else ASTIVal[node] := Ord(tkEq);
          ASTLeft[node] := left;
          right := AllocNode(AN_INT_LIT); ASTIVal[right] := 0;
          if (rTk = tyClass) or (rTk = tyPointer) then ASTTk[right] := Ord(tyPointer)
          else ASTTk[right] := ASTTk[left];
          ASTRight[node] := right; ASTTk[node] := Ord(tyBoolean);
        end;
        left := node;
        Continue;
      end;
      PyParseBitOr;
      right := CurASTNode;
      node := AllocNode(AN_BINOP);
      if neg then ASTIVal[node] := Ord(tkNeq) else ASTIVal[node] := Ord(tkEq);
      ASTLeft[node] := left; ASTRight[node] := right;
      ASTTk[node] := Ord(tyBoolean);
      { `is` lowers to the same tkEq node `==` does, so the CONTENT comparisons
        ir.inc added for `==` (pylist_eq / pydict_eq) swept it along: two
        distinct lists with equal elements answered `a is c` -> True, inverting
        the one thing `is` exists for. Mark the node as an IDENTITY compare so
        those arms decline it and the pointer compare stands
        (bug-nilpy-is-on-two-lists-compares-contents). }
      ASTSLen[node] := PY_BINOP_IDENTITY;
      left := node;
    end
    else
    begin
      { [not] in — membership via pylib pycontains(list, value) }
      neg := CurTok.Kind = tkNot;
      if neg then Next;
      Expect(tkIn, 'in');
      { `x in ("a", "b")` — a TUPLE on the right. Built as the same TPyList a
        `[...]` literal produces, so membership, evaluation order and the
        container dispatch below are all shared rather than special-cased.
        A plain `(expr)` has no top-level comma and still parses as grouping. }
      if PyTupleParenAhead then
        PyParseListLiteralT(tkLParen, tkRParen, False)
      else
        PyParseBitOr;
      right := CurASTNode;
      { The container decides the helper, and getting it wrong is not a type
        error but a CRASH: pycontains would scan a TPyDict's or a string's
        header words as if they were variant slots.
          dict   -> key membership
          str    -> SUBSTRING containment, which is what `in` means in Python
          else   -> list element membership }
      dunderBuilt := False;
      rTk := IntToTypeKind(ASTTk[right]);
      if (rTk = tyString) or (rTk = tyAnsiString) then
        node := FindProc('pystr_contains')
      else if rTk = tyVariant then
        { container type known only at run time (a dict/list slot value) —
          unbox and dispatch inside pyvar_contains. }
        node := FindProc('pyvar_contains')
      else if ResolveNodeRec(right) = REC_UCLASS_BASE + FindUClass('TPyDict') then
        node := FindProc('pydictcontains')
      else if (ResolveNodeRec(right) >= REC_UCLASS_BASE) and
              (ResolveNodeRec(right) <> REC_UCLASS_BASE + FindUClass('TPyList')) and
              (ResolveNodeRec(right) <> REC_UCLASS_BASE + FindUClass('TPyBytes')) then
      begin
        { A USER class (not one of pylib's own containers): `x in obj` must
          call obj.__contains__(x) when it declares one -- the fallback below
          (pycontains, a TPyList-only scan) otherwise read the instance's raw
          bytes as if they were list-element slots, a silent wrong answer, not
          a crash (bug-nilpy-dunder-protocols-ignored-fall-back-to-handle-
          arithmetic — same failure family as that ticket's `len()` fix just
          above). No `__contains__` at all is not a container and should say
          so loudly rather than guess. }
        ucCi := ResolveNodeRec(right) - REC_UCLASS_BASE;
        ucMmi := FindUMeth(ucCi, '__contains__');
        if ucMmi >= 0 then
        begin
          right := PyCallMeth1(ucCi, PyRawName(UMthNOff[ucMmi], UMthNLen[ucMmi]), right, left);
          if right >= 0 then dunderBuilt := True
          else Error('Nil Python: "in" could not call __contains__');
        end
        else
        begin
          { A genuine RUNTIME error (a `try/except` around this must still
            compile and run its handler), not the compile-time Error() a
            first attempt used here -- that aborted the whole compilation
            instead. }
          node := FindProc('PyNotContainerError');
          if node < 0 then Error('Nil Python: pylib (PyNotContainerError) not loaded');
          right := AllocNode(AN_CALL);
          ASTIVal[right] := node;
          ASTTk[right] := Ord(tyBoolean);
          ASTLeft[right] := -1;
          dunderBuilt := True;
        end;
      end
      else
        node := FindProc('pycontains');
      if (not dunderBuilt) and (node < 0) then
        Error('Nil Python: pylib (pycontains) not loaded');
      if not dunderBuilt then
      begin
        { A tyChar value (`s[0] in ("a","b")`, a subscript yields tyChar) is boxed
          VT_CHAR, but the collection holds VT_STRING elements, so the tag never
          matched and membership was always False. In Python a char IS a 1-char
          str; promote it via pystr_ofchar so it compares as one. See the same
          receiver coercion in PyParseStrMethod. }
        if IntToTypeKind(ASTTk[left]) = tyChar then
        begin
          j := FindProc('pystr_ofchar');
          if j < 0 then Error('Nil Python: pylib (pystr_ofchar) not loaded');
          i := AllocNode(AN_ARG);
          ASTLeft[i] := left;
          left := AllocNode(AN_CALL);
          ASTIVal[left] := j;
          ASTTk[left] := Ord(tyAnsiString);
          ASTLeft[left] := i;
        end;
        i := AllocNode(AN_ARG);            { the container, arg 0 }
        ASTLeft[i] := right;
        j := AllocNode(AN_ARG);            { the value, arg 1 }
        ASTLeft[j] := left;
        ASTRight[i] := j;
        right := AllocNode(AN_CALL);
        ASTIVal[right] := node;
        ASTTk[right] := Ord(tyBoolean);
        ASTLeft[right] := i;
      end;
      if neg then
      begin
        node := AllocNode(AN_NOT);
        ASTLeft[node] := right;
        ASTTk[node] := Ord(tyBoolean);
        left := node;
      end
      else
        left := right;
    end;
  end;
  CurASTNode := left;
end;

procedure PyParseBoolNot;
var node, zeroNode, operand, lenNode, argNode: Integer; opTk: TTypeKind;
begin
  if CurTok.Kind = tkNot then
  begin
    Next;
    PyParseBoolNot;
    operand := CurASTNode;
    opTk := IntToTypeKind(ASTTk[operand]);
    { Python's `not` is TRUTHINESS, and every non-zero integer is truthy.
      AN_NOT on a non-boolean operand is Pascal's BITWISE complement — so
      `not 5` produced -6, which is non-zero and therefore printed True, and
      `not 2` in an if-condition took the wrong branch. Silently: only 0 and 1
      came out right, and 0 only by luck (-1 is also truthy).

      For an ordinal operand the answer is `operand = 0` instead. Booleans
      keep AN_NOT, where it is already logical.

      A STRING is truthy when it is non-empty, so `not s` is `Length(s) = 0`.
      Falling through to AN_NOT complemented the string HANDLE instead, which
      is never zero, so `not s` was True for every string including a
      non-empty one — silently, and `if s:` / `bool(s)` were correct all
      along, which is what hid it (bug-nilpy-not-on-string-always-true).
      A class or variant operand is still its own question and still goes
      through AN_NOT unchanged. }
    if PyIsStrBaseTk(opTk) then
    begin
      lenNode := AllocNode(AN_CALL);
      ASTIVal[lenNode] := -Ord(tkLength);
      ASTTk[lenNode] := Ord(tyInteger);
      argNode := AllocNode(AN_ARG);
      ASTLeft[argNode] := operand;
      ASTRight[argNode] := -1;
      ASTLeft[lenNode] := argNode;
      zeroNode := AllocNode(AN_INT_LIT);
      ASTIVal[zeroNode] := 0;
      ASTTk[zeroNode] := Ord(tyInteger);
      node := AllocNode(AN_BINOP);
      ASTIVal[node] := Ord(tkEq);
      ASTLeft[node] := lenNode;
      ASTRight[node] := zeroNode;
      ASTTk[node] := Ord(tyBoolean);
    end
    else if (opTk = tyClass) and (ResolveNodeRec(operand) >= REC_UCLASS_BASE) and
            PyIsPylibContainerCi(ResolveNodeRec(operand) - REC_UCLASS_BASE) then
    begin
      { A LIST / DICT / bytes is truthy when NON-EMPTY (Python), so `not xs` is
        `len(xs) = 0` — via .count. Falling through to AN_NOT complemented the
        object HANDLE (never nil), so `not xs` was True for every container
        including a non-empty one (bug-nilpy-not-on-container-always-true, the
        `if not tokens:` in uforth's interpret loop broke on real tokens). }
      lenNode := PyCallMeth1(ResolveNodeRec(operand) - REC_UCLASS_BASE, 'count', operand, -1);
      if lenNode < 0 then Error('Nil Python: pylib container .count not loaded');
      zeroNode := AllocNode(AN_INT_LIT);
      ASTIVal[zeroNode] := 0;
      ASTTk[zeroNode] := Ord(tyInteger);
      node := AllocNode(AN_BINOP);
      ASTIVal[node] := Ord(tkEq);
      ASTLeft[node] := lenNode;
      ASTRight[node] := zeroNode;
      ASTTk[node] := Ord(tyBoolean);
    end
    else if opTk = tyClass then
    begin
      { Any OTHER object (a user class, an re match object — anything that is
        not a pylib container handled above). Python: an instance is truthy
        unless it is None, so `not o` is `o = nil`. AN_NOT here complemented
        the object HANDLE, which is never nil, so `not o` was True for every
        live object — the same shape as the string and container cases above,
        and just as silent: `if o:` was right all along.

        This is what made songformatter's key analysis return wrong keys.
        `_quality_bucket` opens with `if not match: return None, "unknown"`
        over an `re.match` result, so EVERY chord came back unclassified, every
        key scored identically, and the detector ranked ALL_KEYS in insertion
        order. No crash, no diagnostic — just plausible wrong answers.
        [[bug-nilpy-not-on-object-always-true]] }
      zeroNode := AllocNode(AN_INT_LIT);
      ASTIVal[zeroNode] := 0;
      ASTTk[zeroNode] := Ord(tyPointer);
      node := AllocNode(AN_BINOP);
      ASTIVal[node] := Ord(tkEq);
      ASTLeft[node] := operand;
      ASTRight[node] := zeroNode;
      ASTTk[node] := Ord(tyBoolean);
    end
    else if (opTk = tyBoolean) or not PyNumeric(opTk) then
    begin
      node := AllocNode(AN_NOT);
      ASTLeft[node] := operand;
      ASTTk[node] := Ord(tyBoolean);
    end
    else
    begin
      zeroNode := AllocNode(AN_INT_LIT);
      ASTIVal[zeroNode] := 0;
      ASTTk[zeroNode] := Ord(opTk);
      node := AllocNode(AN_BINOP);
      ASTIVal[node] := Ord(tkEq);
      ASTLeft[node] := operand;
      ASTRight[node] := zeroNode;
      ASTTk[node] := Ord(tyBoolean);
    end;
    CurASTNode := node;
  end
  else
    PyParseIsCmp;   { is/is-not over the bitwise chain over ParseExpr }
end;

{ An INTEGER-ish kind: the arms of a value-returning or/and unify onto Int64. }
function PyIsIntLikeTk(tk: TTypeKind): Boolean;
begin
  Result := tk in [tyInteger, tyInt8, tyUInt8, tyInt16, tyUInt16, tyInt32,
                   tyUInt32, tyInt64, tyUInt64, tyNativeInt, tyNativeUInt];
end;

function PyBoolOpReturnsOperand(a, b: Integer): Boolean; forward;
function PyMakeBoolOpValue(a, b: Integer; isOr: Boolean): Integer; forward;

procedure PyParseBoolAnd;
var left, right, node: Integer;
begin
  PyParseBoolNot;
  left := CurASTNode;
  while CurTok.Kind = tkAnd do
  begin
    Next;
    if PyBareNoneHere then          { `x and None` — see the or-path note }
    begin
      Next;
      right := PyMakeNone;
    end
    else
    begin
      PyParseBoolNot;
      right := CurASTNode;
    end;
    if PyBoolOpReturnsOperand(left, right) then
      node := PyMakeBoolOpValue(left, right, False)
    else
    begin
      node := AllocNode(AN_BINOP); ASTIVal[node] := Ord(tkAnd);
      ASTLeft[node] := PyMakeTruthy(left); ASTRight[node] := PyMakeTruthy(right);
      ASTTk[node] := Ord(tyBoolean);
    end;
    left := node;
  end;
  CurASTNode := left;
end;

{ A truthiness condition for `n` in an `if`/`while` context. Python truthiness is
  type-directed, but a raw NilPy condition tests the storage cell:
    - a VARIANT tests its tag word, so `if v:` was true for every variant
      including one holding 0 — route it through pylib bool().
    - a LIST / DICT / bytes is a class HANDLE (never nil), so `if xs:` was true
      for every container including an empty one — test `len(xs) <> 0` via .count
      (bug-nilpy-if-on-container-always-true; uforth's `and self.include_stack`
      indexed [-1] on an empty list because the guard never went false).
  Ordinals and strings already test correctly (0 / empty are falsy natively), so
  they pass through unchanged. }
{ Unbox a VARIANT value to a class instance pointer: pyvarobj(v) -> the payload
  pointer, hard-cast to class ci. Used when a variant (e.g. a dict/list element,
  dynamically typed) is stored into a tyClass slot — a field or class-typed local.
  Without it the raw 16-byte variant is written into an 8-byte class slot and the
  reader sees garbage (a class object round-tripped through a dict, then assigned
  back to `self.field`, lost its identity and read empty fields — uforth's INCLUDE
  input-source restore across nested files). }
function PyUnboxVariantToClassEx(varNode, ci: Integer; owned: Boolean): Integer;
var unboxArg, unboxCall, castNode: Integer;
    fn: AnsiString;
begin
  unboxArg := AllocNode(AN_ARG); ASTLeft[unboxArg] := varNode; ASTRight[unboxArg] := -1;
  unboxCall := AllocNode(AN_CALL);
  if owned then fn := 'pyvarobj_owned' else fn := 'pyvarobj';
  ASTIVal[unboxCall] := FindProc(fn);
  if ASTIVal[unboxCall] < 0 then Error('Nil Python: pylib (' + fn + ') not loaded');
  ASTTk[unboxCall] := Ord(tyPointer);
  ASTLeft[unboxCall] := unboxArg;
  castNode := AllocNode(AN_CLASS_CAST);
  ASTLeft[castNode] := unboxCall;
  ASTIVal[castNode] := ci;
  ASTTk[castNode]   := Ord(tyClass);
  Result := castNode;
end;

function PyUnboxVariantToClass(varNode, ci: Integer): Integer;
begin
  Result := PyUnboxVariantToClassEx(varNode, ci, False);
end;


function PyMakeTruthy(n: Integer): Integer;
var procIdx, argNode, rec, lenNode, zeroNode, node: Integer;
    nilNode, guardNode, falseNode, pairNode, ternNode: Integer;
begin
  Result := n;
  { A STRING tests EMPTY, explicitly: a string cell used as a raw condition is a
    pointer, and an empty literal's pointer is not nil, so `"" or x` took the
    empty arm. `Length(s) <> 0` is the same shape `not s` already uses
    (bug-nilpy-not-on-string-always-true — this is that bug on the truthy side). }
  if PyIsStrBaseTk(IntToTypeKind(ASTTk[n])) then
  begin
    lenNode := AllocNode(AN_CALL);
    ASTIVal[lenNode] := -Ord(tkLength);
    ASTTk[lenNode] := Ord(tyInteger);
    argNode := AllocNode(AN_ARG);
    ASTLeft[argNode] := n;
    ASTRight[argNode] := -1;
    ASTLeft[lenNode] := argNode;
    zeroNode := AllocNode(AN_INT_LIT);
    ASTIVal[zeroNode] := 0;
    ASTTk[zeroNode] := Ord(tyInteger);
    node := AllocNode(AN_BINOP);
    ASTIVal[node] := Ord(tkNeq);
    ASTLeft[node] := lenNode;
    ASTRight[node] := zeroNode;
    ASTTk[node] := Ord(tyBoolean);
    Result := node;
    Exit;
  end;
  if IntToTypeKind(ASTTk[n]) = tyVariant then
  begin
    procIdx := FindProc('bool');
    if procIdx < 0 then Exit;
    argNode := AllocNode(AN_ARG);
    ASTLeft[argNode] := n; ASTRight[argNode] := -1;
    Result := AllocNode(AN_CALL);
    ASTIVal[Result] := procIdx;
    ASTTk[Result] := Ord(tyBoolean);
    ASTLeft[Result] := argNode;
    Exit;
  end;
  if IntToTypeKind(ASTTk[n]) = tyClass then
  begin
    rec := ResolveNodeRec(n);
    if (rec >= REC_UCLASS_BASE) and PyIsPylibContainerCi(rec - REC_UCLASS_BASE) then
    begin
      lenNode := PyCallMeth1(rec - REC_UCLASS_BASE, 'count', n, -1);
      if lenNode < 0 then Exit;
      zeroNode := AllocNode(AN_INT_LIT);
      ASTIVal[zeroNode] := 0; ASTTk[zeroNode] := Ord(tyInteger);
      node := AllocNode(AN_BINOP); ASTIVal[node] := Ord(tkNeq);
      ASTLeft[node] := lenNode; ASTRight[node] := zeroNode;
      ASTTk[node] := Ord(tyBoolean);
      { A container field/var typed Optional[List]/List can be None (a nil class
        pointer). count() would deref nil and SIGSEGV, so guard: nil -> falsy
        without calling count. `(n <> nil) ? (count<>0) : false`. n is a
        field/var read here (no side effect), so evaluating it twice is safe.
        (bug: `if w.forth_body:` in uforth's inner interpreter crashed on native
        words whose forth_body is None.) }
      nilNode := AllocNode(AN_INT_LIT);
      ASTIVal[nilNode] := 0; ASTTk[nilNode] := Ord(tyPointer);
      guardNode := AllocNode(AN_BINOP); ASTIVal[guardNode] := Ord(tkNeq);
      ASTLeft[guardNode] := n; ASTRight[guardNode] := nilNode;
      ASTTk[guardNode] := Ord(tyBoolean);
      falseNode := AllocNode(AN_INT_LIT);
      ASTIVal[falseNode] := 0; ASTTk[falseNode] := Ord(tyBoolean);
      pairNode := AllocNode(AN_PAIR);
      ASTLeft[pairNode] := node; ASTRight[pairNode] := falseNode;
      ternNode := AllocNode(AN_TERNARY);
      ASTLeft[ternNode] := guardNode; ASTRight[ternNode] := pairNode;
      ASTTk[ternNode] := Ord(tyBoolean);
      Result := ternNode;
    end;
  end;
end;

{ True when `a or b` / `a and b` must return an OPERAND (Python semantics) rather
  than a Boolean — i.e. it is a VALUE, not pure control flow. Triggered when an
  operand is a variant or a class (a container/object); pure ordinal/boolean
  operands keep the cheap boolean form, which every condition context uses. }
{ Python's `or`/`and` yield an OPERAND, not a bool — `name = given or "default"`
  is the ubiquitous default-value idiom, and songformatter writes it constantly
  (`match.group(2) or ""`, `document.get("file_path") or None`). So operand
  semantics apply whenever either side is anything but a Boolean; two Booleans
  keep the plain boolean lowering, where the two readings agree anyway and the
  cheaper one is worth having. In a CONDITION the difference is invisible: the
  `if`/`while` path wraps the result in the same truthiness test either way. }
function PyBoolOpReturnsOperand(a, b: Integer): Boolean;
var ta, tb: TTypeKind;
begin
  ta := IntToTypeKind(ASTTk[a]); tb := IntToTypeKind(ASTTk[b]);
  { ...but only when the two arms have a type the RESULT can carry: a variant or
    class arm (which boxes anything), two strings, or two of the same kind.
    MIXED kinds — `self.f and word.upper() != self.f`, a string and a Boolean —
    keep the boolean lowering, because typing that ternary as either arm's type
    reinterprets the other one (a Boolean read as a string pointer SEGFAULTS,
    which is how this rule was found). The operands are truthiness-tested there,
    so an empty string is still falsy; what is lost is only the VALUE identity of
    a mixed-type `or`, and that shape does not occur outside a condition.

    A str-vs-NUMBER pair (int or float, NOT Boolean) is admitted separately
    below: `name = given or "default"` is the ordinary Python default-value
    idiom, and it mixes a str with whatever `given` actually is whenever that
    is not itself a str — `0 or "x"`, `"" or 5` — which is exactly this shape
    OUTSIDE a condition, falsifying the "does not occur" premise above
    (bug-nilpy-mixed-type-and-or-returns-a-bool-not-the-operand).
    PyMakeBoolOpValue's own type decision already has a `tyVariant` fallback
    for a genuinely mixed pair (boxing each arm rather than reinterpreting
    it), which is what makes this safe now in a way the original comment's
    "typing the ternary as either arm's type" concern does not apply to —
    the ternary is typed VARIANT, not str or int, so neither arm is read
    through the other's representation. Boolean is deliberately NOT included
    here (PyIsIntLikeTk already excludes it) — a str-vs-Boolean pair is
    exactly the segfault repro the original rule was written to avoid, and
    stays on the boolean lowering. }
  Result := (ta = tyVariant) or (tb = tyVariant) or (ta = tyClass) or (tb = tyClass)
            or (PyIsStrBaseTk(ta) and PyIsStrBaseTk(tb))
            or (PyIsIntLikeTk(ta) and PyIsIntLikeTk(tb))
            or (PyIsStrBaseTk(ta) and (PyIsIntLikeTk(tb) or TypeIsFloat(tb)))
            or (PyIsStrBaseTk(tb) and (PyIsIntLikeTk(ta) or TypeIsFloat(ta)))
            or (ta = tb);
end;

{ `a or b` as a value -> `a if truthy(a) else b`; `a and b` -> `b if truthy(a)
  else a`. Lowered to AN_TERNARY so ONLY the selected arm evaluates — Python
  short-circuit. `a` appears in both the condition and an arm — fine for the
  side-effect-free operands the corpus uses; a call with side effects would
  double-evaluate (noted).

  A prior version used an eager pylib call (pyand_v/pyor_v) to get clean variant
  boxing, but that evaluated BOTH operands and so lost short-circuit — the common
  `if xs and xs[0]:` / `if tokens and tokens[-1]...:` guard then indexed an empty
  container and crashed (bug-nilpy-and-or-not-short-circuit). The ternary keeps
  short-circuit; class/variant-valued ternary arms are already handled (see the
  conditional-expression lowering below). }
function PyMakeBoolOpValue(a, b: Integer; isOr: Boolean): Integer;
var condNode, thenNode, elseNode, pairNode, node: Integer;
    ta, tb: TTypeKind;
begin
  condNode := PyMakeTruthy(a);
  if isOr then begin thenNode := a; elseNode := b; end
  else begin thenNode := b; elseNode := a; end;
  pairNode := AllocNode(AN_PAIR);
  ASTLeft[pairNode] := thenNode;
  ASTRight[pairNode] := elseNode;
  node := AllocNode(AN_TERNARY);
  ASTLeft[node] := condNode;
  ASTRight[node] := pairNode;
  ta := IntToTypeKind(ASTTk[a]); tb := IntToTypeKind(ASTTk[b]);
  { BOTH arms, not either — this used to fire whenever ONE side was a str and
    typed the WHOLE result AnsiString even when the other side was a plain
    scalar (int/float), so `1 or "x"` stored a raw integer into a slot the
    rest of the program treated as a managed string handle and dereferenced
    it as one: SIGSEGV. Only reachable once PyBoolOpReturnsOperand started
    admitting str-vs-number pairs into this value path at all — a LATENT bug
    in this function, not something the admit-the-pair fix introduced, since
    that pairing never reached here before
    (bug-nilpy-mixed-type-and-or-returns-a-bool-not-the-operand). A
    genuinely mixed pair now falls through to the tyVariant arm below, which
    boxes each arm instead of reinterpreting one as the other's
    representation — matching the conditional-expression parser's own
    `PyIsStrBaseTk(ta) and PyIsStrBaseTk(tb)` rule just above it in this
    file. }
  if PyIsStrBaseTk(ta) and PyIsStrBaseTk(tb) then
    ASTTk[node] := Ord(tyAnsiString)
  else if PyIsIntLikeTk(ta) and PyIsIntLikeTk(tb) then
    { two integer widths — the wider one carries both arms }
    ASTTk[node] := Ord(tyInt64)
  else if ASTTk[a] = ASTTk[b] then
    { same type on both arms -> keep it, preserving a container/class identity so
      `.method()` on the result still resolves }
    ASTTk[node] := ASTTk[thenNode]
  else
    ASTTk[node] := Ord(tyVariant);
  Result := node;
end;

procedure PyParseBoolExpr;
var left, right, node, condNode, elseNode, pairNode: Integer;
begin
  PyParseBoolAnd;
  left := CurASTNode;
  while CurTok.Kind = tkOr do
  begin
    Next;
    { `x or None` — None as a VALUE is pylib's VT_EMPTY variant, not the nil/zero
      cell a bare literal parses to; without this the fallback arm printed EMPTY
      where CPython prints None (the feature-nilpy-none-variant family, same
      treatment the conditional expression already gives its else arm). }
    if PyBareNoneHere then
    begin
      Next;
      right := PyMakeNone;
    end
    else
    begin
      PyParseBoolAnd;
      right := CurASTNode;
    end;
    if PyBoolOpReturnsOperand(left, right) then
      node := PyMakeBoolOpValue(left, right, True)
    else
    begin
      node := AllocNode(AN_BINOP); ASTIVal[node] := Ord(tkOr);
      ASTLeft[node] := PyMakeTruthy(left); ASTRight[node] := PyMakeTruthy(right);
      ASTTk[node] := Ord(tyBoolean);
    end;
    left := node;
  end;
  { Python's CONDITIONAL EXPRESSION, `A if C else B` — the value comes first
    and the condition second, unlike every other language's ternary. Lowest
    precedence in the expression grammar, so it wraps the whole or-expression
    just parsed, and the else-arm recurses so `a if p else b if q else c`
    chains to the right as Python does.

    Reuses AN_TERNARY, which the C frontend already lowers (Left = condition,
    Right = AN_PAIR(then, else)) with only the selected arm evaluated. The
    result type is taken from the THEN arm; the two arms having different
    types is a NilPy question the corpus does not raise. }
  if CurTok.Kind = tkIf then
  begin
    Next;
    PyParseBoolExpr;
    condNode := PyMakeTruthy(CurASTNode);
    if CurTok.Kind <> tkElse then
      Error('Nil Python: a conditional expression needs an else');
    Next;
    { `A if C else None`: None is a real value (VT_EMPTY variant) — the nil
      literal boxed integer 0 and the consumer's `is None` tag-test failed
      (feature-nilpy-none-variant, sibling of the literal/setter routes). }
    if PyBareNoneHere then
    begin
      Next;
      CurASTNode := PyMakeNone;
    end
    else
      PyParseBoolExpr;
    elseNode := CurASTNode;
    pairNode := AllocNode(AN_PAIR);
    ASTLeft[pairNode] := left;
    ASTRight[pairNode] := elseNode;
    node := AllocNode(AN_TERNARY);
    ASTLeft[node] := condNode;
    ASTRight[node] := pairNode;
    { NilPy strings are MANAGED; a string-valued conditional tagged with the
      then-arm's frozen tyString printed garbage when used directly as a write
      argument, because a frozen string is content-addressed and a conditional
      yields a value, not a location. Tagging the result managed matches how
      every other NilPy string expression is typed. }
    if PyIsStrBaseTk(IntToTypeKind(ASTTk[left])) and
       PyIsStrBaseTk(IntToTypeKind(ASTTk[elseNode])) then
      ASTTk[node] := Ord(tyAnsiString)
    else
      { The arms may have DIFFERENT types — `"x" if v == "x" else v - 1` is
        ordinary Python, and songformatter writes exactly that. Widen across
        both, the same rule an assignment uses: a str/int pair boxes into a
        variant and each value survives as itself. Taking the THEN arm's type
        (or forcing a string when EITHER arm was one) stringified the numeric
        arm, so `[0, 'x', 2]` came out as `['0', 'x', '2']` — a plausible wrong
        value. bug-nilpy-ternary-comprehension-element-stringified. }
      ASTTk[node] := Ord(PyWiden(IntToTypeKind(ASTTk[left]),
                                 IntToTypeKind(ASTTk[elseNode])));
    left := node;
  end;
  CurASTNode := left;
end;

{ NilPy variable-binding resolution. A program/local name must never bind to an
  imported unit's global. Python's namespace is locals + module globals +
  builtins — NOT a used unit's internal variables. FindSym, however, walks the
  whole flat symbol table case-insensitively, so a user variable `cur` (a str)
  silently reuses pylib/pyeval's implementation global `Cur` (an Integer). The
  shared BSS slot is then stored/loaded at the wrong width — a truncated pointer
  that segfaults (surfaced when auto-using pyeval regressed str_param). Return the
  match only when it belongs to the main program (SymUnitIdx = -1, set because
  CurrentUnitIdx is -1 outside an imported unit); otherwise -1 so the caller
  AllocVars a fresh program-scoped variable that shadows the unit global.
  Mirrors the unit-scoping FindProcOverload already applies to procedures. }
function PyProgSym(const name: AnsiString): Integer;
{ A name belonging to the COMPILATION UNIT being parsed: the program itself
  (SymUnitIdx = -1), or — while a `.py` MODULE is being compiled — that module's
  own symbols, which carry its unit index. Without the second case a module's
  method could not see its own `self`: every symbol it allocates is tagged with
  the unit, so the test "must be program-level" rejected all of them
  (feature-nilpy-py-module-loader). Symbols of OTHER units stay invisible here,
  which is the point of the check — an RTL unit's internals must not bind to a
  bare Python name. }
var si: Integer;
begin
  si := FindSym(name);
  if (si >= 0) and (SymUnitIdx[si] <> -1) and (SymUnitIdx[si] <> CurrentUnitIdx) then si := -1;
  PyProgSym := si;
end;

function PyFindConstraint(const name: AnsiString): Integer;
var i: Integer;
begin
  for i := 0 to PyLocalCount - 1 do
    if PyLocals[i].Name = name then begin Result := i; Exit; end;
  Result := -1;
end;

{ Record one assignment's RHS type against a local, widening. Only the trial
  parse calls this; the real parse's frame is already laid out. }
procedure PyNoteLocalType(const name: AnsiString; tk: TTypeKind; rec: Integer);
var ci: Integer; w: TTypeKind;
begin
  if tk = tyUnknown then Exit;
  ci := PyFindConstraint(name);
  if ci < 0 then
  begin
    if PyLocalCount >= PY_MAX_LOCALS then
      Error('Nil Python: too many inferred locals');
    PyLocals[PyLocalCount].Name := name;
    PyLocals[PyLocalCount].TypeKind := tk;
    if rec >= REC_UCLASS_BASE then PyLocals[PyLocalCount].RecCi := rec - REC_UCLASS_BASE
    else PyLocals[PyLocalCount].RecCi := -1;
    Inc(PyLocalCount);
    PyTypingChanged := True;
    Exit;
  end;
  w := PyWiden(PyLocals[ci].TypeKind, tk);
  if w <> PyLocals[ci].TypeKind then
  begin
    PyLocals[ci].TypeKind := w;
    PyTypingChanged := True;
  end;
  if (PyLocals[ci].RecCi < 0) and (rec >= REC_UCLASS_BASE) then
  begin
    PyLocals[ci].RecCi := rec - REC_UCLASS_BASE;
    PyTypingChanged := True;
  end;
end;

function PyFindModuleConstraint(const name: AnsiString): Integer;
var i: Integer;
begin
  for i := 0 to PyModuleLocalCount - 1 do
    if PyModuleLocals[i].Name = name then begin Result := i; Exit; end;
  Result := -1;
end;

{ (PyDefReturnType, the token scan that recovered a top-level def's return
  type before any Proc existed, was retired by PyRegisterDefShells — the
  signatures are registered up front now, so FindProc answers it.) }
{ The str-method table — the ONE place a NilPy string method is described.

  Both the desugar (PyParseStrMethod) and the type-inference scanner
  (PyInferExprType) read it, so they cannot drift: a method added here is
  immediately known to both, and inference can never disagree with the call it
  will actually build. Returns False for a name that is not a str method, which
  is what lets inference leave non-method `.foo` alone.

  Adding a method = one row here + the pylib function. }
function PyStrMethodInfo(const mname: AnsiString; var pname: AnsiString;
                         var retTk: TTypeKind; var wantArgs: Integer): Boolean;
begin
  retTk := tyAnsiString;    { the str->str default; rows below override }
  wantArgs := 0;
  Result := True;
  if CaseEqual(mname, 'upper') then pname := 'pystr_upper'
  else if CaseEqual(mname, 'lower') then pname := 'pystr_lower'
  { strip family: 0 args (whitespace) or 1 arg (a CHARS set) — see the -5 case
    in PyParseStrMethod, which appends _chars for the one-argument form. }
  else if CaseEqual(mname, 'strip') then begin pname := 'pystr_strip'; wantArgs := -5; end
  else if CaseEqual(mname, 'lstrip') then begin pname := 'pystr_lstrip'; wantArgs := -5; end
  else if CaseEqual(mname, 'rstrip') then begin pname := 'pystr_rstrip'; wantArgs := -5; end
  else if CaseEqual(mname, 'startswith') then
    begin pname := 'pystr_startswith'; retTk := tyBoolean; wantArgs := 1; end
  else if CaseEqual(mname, 'endswith') then
    begin pname := 'pystr_endswith'; retTk := tyBoolean; wantArgs := 1; end
  else if CaseEqual(mname, 'find') then
    { .find(sub) and .find(sub, start) — see the -3 case in PyParseStrMethod }
    begin pname := 'pystr_find'; retTk := tyInteger; wantArgs := -3; end
  else if CaseEqual(mname, 'encode') then
    { .encode(enc [, errors=...]) — the arguments are accepted and DROPPED; see
      the -4 case in PyParseStrMethod and pystr_encode for what that means. }
    begin pname := 'pystr_encode'; retTk := tyClass; wantArgs := -4; end
  else if CaseEqual(mname, 'format') then
    { one or two positional arguments — see the -6 case in PyParseStrMethod }
    begin pname := 'pystr_format'; retTk := tyAnsiString; wantArgs := -6; end
  else if CaseEqual(mname, 'isspace') then
    begin pname := 'pystr_isspace'; retTk := tyBoolean; end
  else if CaseEqual(mname, 'isdigit') then
    begin pname := 'pystr_isdigit'; retTk := tyBoolean; end
  else if CaseEqual(mname, 'isalpha') then
    begin pname := 'pystr_isalpha'; retTk := tyBoolean; end
  else if CaseEqual(mname, 'isupper') then
    begin pname := 'pystr_isupper'; retTk := tyBoolean; end
  else if CaseEqual(mname, 'islower') then
    begin pname := 'pystr_islower'; retTk := tyBoolean; end
  else if CaseEqual(mname, 'join') then
    begin pname := 'pystr_join'; wantArgs := 1; end
  else if CaseEqual(mname, 'split') then
    { 0 or 1 args, and the two forms are DIFFERENT algorithms — see pylib.
      PyParseStrMethod picks the concrete function from the arg count. }
    begin pname := 'pystr_split_sep'; retTk := tyClass; wantArgs := -1; end
  else if CaseEqual(mname, 'rjust') then
    { 1 or 2 args: rjust(width) pads with spaces, rjust(width, fill) with the
      first character of fill. PyParseStrMethod picks the concrete function
      from the arg count, like split. }
    begin pname := 'pystr_rjust'; wantArgs := -2; end
  else if CaseEqual(mname, 'splitlines') then
    begin pname := 'pystr_splitlines'; retTk := tyClass; end
  else if CaseEqual(mname, 'replace') then
    { .replace(old, new) and .replace(old, new, count) — see the -7 case in
      PyParseStrMethod. Its absence is what made songformatter's
      `song_text = song_text.replace(...)` fall through to the unresolved-import
      raise (bug-nilpy-songformatter-first-render-walls). }
    begin pname := 'pystr_replace'; wantArgs := -7; end
  else if CaseEqual(mname, 'count') then
    begin pname := 'pystr_count'; retTk := tyInteger; wantArgs := 1; end
  else if CaseEqual(mname, 'rfind') then
    begin pname := 'pystr_rfind'; retTk := tyInteger; wantArgs := 1; end
  else if CaseEqual(mname, 'title') then pname := 'pystr_title'
  else if CaseEqual(mname, 'capitalize') then pname := 'pystr_capitalize'
  else if CaseEqual(mname, 'swapcase') then pname := 'pystr_swapcase'
  { casefold is lower() for the byte strings we have — no Unicode folding }
  else if CaseEqual(mname, 'casefold') then pname := 'pystr_lower'
  else if CaseEqual(mname, 'isalnum') then
    begin pname := 'pystr_isalnum'; retTk := tyBoolean; end
  else if CaseEqual(mname, 'ljust') then
    { width, plus an OPTIONAL fill character — the -2 form, like rjust }
    begin pname := 'pystr_ljust'; wantArgs := -2; end
  else if CaseEqual(mname, 'center') then
    begin pname := 'pystr_center'; wantArgs := -2; end
  else if CaseEqual(mname, 'zfill') then
    begin pname := 'pystr_zfill'; wantArgs := 1; end
  else if CaseEqual(mname, 'removeprefix') then
    begin pname := 'pystr_removeprefix'; wantArgs := 1; end
  else if CaseEqual(mname, 'removesuffix') then
    begin pname := 'pystr_removesuffix'; wantArgs := 1; end
  else
  begin
    pname := '';
    Result := False;
  end;
end;

{ Does ANY user class declare this method? (Records excluded — the closed-world
  dispatch below skips them too.) }
function PyAnyClassDeclaresMeth(const mname: AnsiString): Boolean;
var ci: Integer;
begin
  Result := False;
  for ci := 0 to UClsCount - 1 do
  begin
    if UClsIsRecord[ci] then Continue;
    if FindUMeth(ci, mname) >= 0 then begin Result := True; Exit; end;
  end;
end;

{ str methods whose NAME is also a common object method: `title` is str.title()
  and tkinter's window title, `count` is str.count() and a container's. On a
  VARIANT receiver a declared class method wins for these — `root.title("x")` is
  what real code means, and the str spelling is reached anyway whenever the
  receiver is statically a string. Every other str method keeps str-first
  priority, which is what the dynamically-typed corpus relies on. }
function PyStrMethodLosesToClass(const mname: AnsiString): Boolean;
begin
  Result := (CaseEqual(mname, 'title') or CaseEqual(mname, 'count')) and
            PyAnyClassDeclaresMeth(mname);
end;

{ A name that is BOTH a type name and a builtin conversion call. }
function PyIsBuiltinConvName(const nm: AnsiString): Boolean;
var lo: AnsiString;
begin
  lo := LowerCase(nm);
  Result := (lo = 'str') or (lo = 'int') or (lo = 'float') or (lo = 'bool') or
            (lo = 'list') or (lo = 'dict') or (lo = 'set') or (lo = 'bytes') or
            (lo = 'bytearray');
end;

{ Is the bracket group opening at lbIdx a SLICE (`[a:b]`) rather than an index?
  A ':' at depth 1 is the whole test; a nested subscript or call keeps its own
  colons at a deeper level. }
function PySliceBracketAt(lbIdx, endIdx: Integer): Boolean;
var k, depth: Integer;
begin
  Result := False;
  depth := 0;
  k := lbIdx;
  while k < endIdx do
  begin
    if Tokens[k].Kind in [tkLBrack, tkLParen, tkBegin] then Inc(depth)
    else if Tokens[k].Kind in [tkRParen, tkEnd] then Dec(depth)
    else if Tokens[k].Kind = tkRBrack then
    begin
      Dec(depth);
      if depth = 0 then Exit;
    end
    else if (depth = 1) and (Tokens[k].Kind = tkColon) then
    begin
      Result := True;
      Exit;
    end;
    Inc(k);
  end;
end;

function PyInferExprType(startIdx, endIdx: Integer): TTypeKind;
var i, ci, si, procIdx, depth, smArgs, fci, fi, k2, rcvCi: Integer; tk: TTypeKind;
    name, lo, smPName: AnsiString;
begin
  Result := tyUnknown;
  PyInferLastCi := -1;
  { A CONDITIONAL EXPRESSION types as its THEN arm, so infer from the part
    before the `if` and stop. Without this the scanner walked straight through
    `x if c else y`, widening across the condition and the else-arm, and a
    class-valued conditional lost its identity — the next `.method()` on the
    local then failed to resolve, surfacing as a misleading "expected :" at the
    following line (bug-nilpy-conditional-expression-loses-its-type). }
  k2 := startIdx;
  depth := 0;
  while k2 < endIdx do
  begin
    if Tokens[k2].Kind in [tkBegin, tkLBrack, tkLParen] then Inc(depth)
    else if Tokens[k2].Kind in [tkEnd, tkRBrack, tkRParen] then Dec(depth)
    else if (depth = 0) and (Tokens[k2].Kind = tkIf) and (k2 > startIdx) then
    begin
      Result := PyInferExprType(startIdx, k2);
      Exit;
    end;
    Inc(k2);
  end;
  { A COMPARISON or a membership test yields a Boolean whatever its operands
    are, and the scan below types an expression by the operands it recognises:
    `return v in {"0", "1"}` typed itself by the set literal (a TPyList) and
    `return v > "0"` by the string, so the def's registered result type
    disagreed with what the body actually returns — the caller read a Boolean
    as an object pointer and crashed on the next use
    (bug-nilpy-comparison-return-type-inferred-from-operands). `and`/`or` are
    deliberately NOT here: Python hands back an OPERAND, not a Boolean, and
    NilPy implements that. Depth-tracked so an operator inside a call or a
    subscript does not decide the whole expression. }
  k2 := startIdx;
  depth := 0;
  while k2 < endIdx do
  begin
    if Tokens[k2].Kind in [tkBegin, tkLBrack, tkLParen] then Inc(depth)
    else if Tokens[k2].Kind in [tkEnd, tkRBrack, tkRParen] then Dec(depth)
    else if (depth = 0) and (Tokens[k2].Kind in [tkEq, tkNeq, tkLt, tkLe,
                                                 tkGt, tkGe, tkIn]) then
    begin
      Result := tyBoolean;
      Exit;
    end;
    Inc(k2);
  end;
  { `not <expr>` is a Boolean too. }
  if (startIdx < endIdx) and (Tokens[startIdx].Kind = tkNot) then
  begin
    Result := tyBoolean;
    Exit;
  end;
  { A parenthesised TUPLE is built as a TPyList, so it must INFER as one too —
    otherwise an unannotated `return (a, b)` typed itself Integer and handed
    back the list pointer truncated. }
  if (startIdx < endIdx) and (Tokens[startIdx].Kind = tkLParen) and
     PyTupleParenAt(startIdx) then
  begin
    Result := tyClass;
    PyInferLastCi := FindUClass('TPyList');
    Exit;
  end;
  if (startIdx < endIdx) and
     ((Tokens[startIdx].Kind = tkLBrack) or (Tokens[startIdx].Kind = tkBegin)) then
  begin
    Result := tyClass;   { list / set-as-list / dict literal }
    if (Tokens[startIdx].Kind = tkBegin) and PyDictLiteralAt(startIdx) then
      PyInferLastCi := FindUClass('TPyDict')
    else
      PyInferLastCi := FindUClass('TPyList');
    Exit;
  end;
  { A QUALIFIED construction — `tk.Canvas(root)`, the form every tkinter
    application writes. Unqualified `Canvas(root)` was typed below; this one was
    not, so `self.canvas = tk.Canvas(root)` recorded a field with no class
    identity and every later `self.canvas.method(...)` fell through to the
    dynamic-attribute path — which cannot bind keyword arguments, so
    `self.canvas.create_text(0, 0, text="x")` was a parse error while the same
    call through a LOCAL compiled. (The module qualifier is a unit alias here:
    NilPy turns `import tkinter as tk` into a uses-clause alias, so the class is
    found by its bare name.) }
  if (startIdx + 2 < endIdx) and (Tokens[startIdx].Kind = tkIdent) and
     (Tokens[startIdx + 1].Kind = tkDot) and (Tokens[startIdx + 2].Kind = tkIdent) and
     (startIdx + 3 < endIdx) and (Tokens[startIdx + 3].Kind = tkLParen) and
     (FindUClass(GetTokenStr(startIdx + 2)) >= 0) then
  begin
    Result := tyClass;
    PyInferLastCi := FindUClass(GetTokenStr(startIdx + 2));
    Exit;
  end;
  if (startIdx < endIdx) and (Tokens[startIdx].Kind = tkIdent) and
     IsClassType(GetTokenStr(startIdx)) and (startIdx + 1 < endIdx) and
     (Tokens[startIdx + 1].Kind = tkLParen) and
     (FindUClass(GetTokenStr(startIdx)) >= 0) then
  begin
    { ...and only for a class that REALLY exists: `str(x)` / `int(x)` are
      builtin CONVERSIONS whose names IsClassType also answers to, and typing
      them tyClass-with-no-identity made an unannotated `return str(x)` hand
      back a string handle the caller read as an object pointer — a segfault.
      The builtin table further down gives them their real result types. }
    Result := tyClass;
    PyInferLastCi := FindUClass(GetTokenStr(startIdx));
    Exit;
  end;
  i := startIdx;
  while i < endIdx do
  begin
    { A str method called on a string LITERAL — `"a,b".split(",")`. The scan
      below only inspects IDENT tokens, so a literal base never reached the
      str-method case and the result fell through untyped: a local assigned
      from "a,b".split(",") carried no class identity, len() picked the
      AnsiString overload over the TPyList one and read a class pointer as a
      string handle. Handled here, before the ident dispatch. }
    if (Tokens[i].Kind = tkString) and (i + 3 < endIdx) and
       (Tokens[i + 1].Kind = tkDot) and (Tokens[i + 2].Kind = tkIdent) and
       (Tokens[i + 3].Kind = tkLParen) and
       PyStrMethodInfo(GetTokenStr(i + 2), smPName, tk, smArgs) then
    begin
      if tk = tyClass then PyInferLastCi := FindUClass('TPyList');
      i := i + 3; depth := 0;
      while i < endIdx do
      begin
        if Tokens[i].Kind = tkLParen then Inc(depth)
        else if Tokens[i].Kind = tkRParen then
        begin
          Dec(depth);
          if depth = 0 then Break;
        end;
        Inc(i);
      end;
      Result := PyWiden(Result, tk);
      Inc(i);
      Continue;
    end;
    tk := PyTypeFromTokenIndex(i);
    { A type NAME followed by '(' is a conversion CALL, not a bare type: it must
      go through the call branch below, which knows the conversion's result type
      AND skips the argument group. Reading it as a type here typed `str(d)` as
      a string and then WIDENED over the argument `d` — and since locals exist
      only in the body pass, the shell pre-pass said `str` and the body pass said
      `variant` for the same def: two different return types for one signature,
      i.e. the silent ABI mismatch, and the def crashed on return. }
    if (tk <> tyUnknown) and (Tokens[i].Kind = tkIdent) and (i + 1 < endIdx) and
       (Tokens[i + 1].Kind = tkLParen) and PyIsBuiltinConvName(GetTokenStr(i)) then
      tk := tyUnknown;
    if tk = tyUnknown then
    begin
      if Tokens[i].Kind = tkIdent then
      begin
        name := GetTokenStr(i);
        { Call form `name(...)`: take the callee's return type and skip the
          whole argument group so arg tokens do not pollute the widening. }
        if (i + 1 < endIdx) and (Tokens[i + 1].Kind = tkLParen) and
           ((not IsClassType(name)) or PyIsBuiltinConvName(name)) then
        begin
          { ...and the builtin CONVERSIONS get in even though IsClassType
            answers to their names: `str`, `int`, `float`, `bool`, `list`,
            `dict`, `set` are type names AND callable intrinsics, and the guard
            above kept `return str(x)` from ever reaching the table below. }
          { Shared-parser builtins are not Procs; without this they would fall
            through to tyVariant and poison the local's type (a variant local
            scalar-loaded on `return` yields its TAG, not the value). }
          lo := LowerCase(name);
          if (lo = 'length') or (lo = 'ord') or (lo = 'pos') then tk := tyInteger
          else if lo = 'chr' then tk := tyChar
          else if lo = 'copy' then tk := tyString
          { The NilPy BUILTINS the shared parser lowers as intrinsics: they are
            not Procs either, so `return str(x)` in an unannotated def inferred
            an INTEGER, and the caller then read the returned string handle as a
            number — a segfault or a garbage integer, silently
            (bug-nilpy-unannotated-return-infers-number-for-string-concat is the
            operator half of the same blind spot). }
          else if (lo = 'str') or (lo = 'repr') or (lo = 'format') then tk := tyAnsiString
          else if lo = 'int' then tk := tyInt64
          else if lo = 'float' then tk := tyDouble
          else if lo = 'bool' then tk := tyBoolean
          else if (lo = 'len') or (lo = 'index') then tk := tyInteger
          else if (lo = 'any') or (lo = 'all') then tk := tyBoolean
          else if (lo = 'list') or (lo = 'sorted') or (lo = 'set') or
                  (lo = 'zip') or (lo = 'enumerate') then
          begin
            tk := tyClass;
            PyInferLastCi := FindUClass('TPyList');
          end
          else if lo = 'dict' then
          begin
            tk := tyClass;
            PyInferLastCi := FindUClass('TPyDict');
          end
          else if (lo = 'sum') or (lo = 'max') or (lo = 'min') or (lo = 'next') or
                  (lo = 'abs') then tk := tyVariant
          else
          begin
            { Every top-level def has a registered Proc by now
              (PyRegisterDefShells), so FindProc is the whole answer — the old
              PyDefReturnType token scan that stood in for it is gone. }
            procIdx := FindProc(name);
            if procIdx >= 0 then tk := Procs[procIdx].RetType;
            { A call returning a CLASS has to record WHICH class, or the
              inferred local/field carries tyClass with no identity and
              overload resolution mis-picks — `len(bytearray(n))` chose the
              AnsiString overload and read a class pointer as a string handle,
              segfaulting. Same failure the str-method branches above document.
              ProcRetRecId is a REC ID; PyInferLastCi is a CLASS INDEX. }
            if (procIdx >= 0) and (tk = tyClass) and
               (ProcRetRecId[procIdx] >= REC_UCLASS_BASE) then
              PyInferLastCi := ProcRetRecId[procIdx] - REC_UCLASS_BASE;
            if tk = tyUnknown then tk := tyVariant;
          end;
          i := i + 1; depth := 0;
          while i < endIdx do
          begin
            if Tokens[i].Kind = tkLParen then Inc(depth)
            else if Tokens[i].Kind = tkRParen then
            begin
              Dec(depth);
              if depth = 0 then Break;
            end;
            Inc(i);
          end;
          Result := PyWiden(Result, tk);
          Inc(i);
          Continue;
        end;
        if IsClassType(name) then tk := tyClass;
        ci := PyFindConstraint(name);
        if (tk = tyUnknown) and (ci >= 0) then tk := PyLocals[ci].TypeKind
        else
        begin
          si := PyProgSym(name);
          if si >= 0 then tk := Syms[si].TypeKind;
        end;
        { obj.method(...) on a class-typed name: the expression's type is the
          METHOD's return type; skip the whole postfix chain. }
        { The receiver's class: a constrained local, or `self`, which never
          appears in PyLocals — so `w = self.lookup(k)` inferred nothing and the
          local lost the method's return class. The next `w.method()` then had
          no class to resolve against and the parse stopped before the '(' with
          a misleading "expected :" on the FOLLOWING line
          (bug-nilpy-self-method-call-loses-return-class). }
        rcvCi := -1;
        if (ci >= 0) and (PyLocals[ci].RecCi >= 0) then rcvCi := PyLocals[ci].RecCi
        else if (name = 'self') and (CurSelfClass >= REC_UCLASS_BASE) then
          rcvCi := CurSelfClass - REC_UCLASS_BASE;
        if (rcvCi >= 0) and
           (i + 3 < endIdx) and (Tokens[i + 1].Kind = tkDot) and
           (Tokens[i + 2].Kind = tkIdent) and (Tokens[i + 3].Kind = tkLParen) then
        begin
          si := FindUMeth(rcvCi, GetTokenStr(i + 2));
          if si >= 0 then
          begin
            tk := Procs[UMthProc_[si]].RetType;
            { REC ID -> CLASS INDEX. Assigning the rec id straight across left
              every consumer to add REC_UCLASS_BASE a second time. }
            if (tk = tyClass) and (ProcRetRecId[UMthProc_[si]] >= REC_UCLASS_BASE) then
              PyInferLastCi := ProcRetRecId[UMthProc_[si]] - REC_UCLASS_BASE;
            i := i + 3; depth := 0;
            while i < endIdx do
            begin
              if Tokens[i].Kind = tkLParen then Inc(depth)
              else if Tokens[i].Kind = tkRParen then
              begin
                Dec(depth);
                if depth = 0 then Break;
              end;
              Inc(i);
            end;
            Result := PyWiden(Result, tk);
            Inc(i);
            Continue;
          end;
        end;
        { Plain `.field` chain on a class-typed name (no call parens): follow it
          so the inferred type AND class identity are the FINAL field's.
          Without it `x = o.inner` left x as tyClass with no identity and the
          later `x.name` mis-resolved to Integer, printing a raw pointer.
          Depends on PyRegisterClassFieldsPrepass having run — before that,
          every class had zero fields at this point and there was nothing to
          walk. The method form below handles the `(`-terminated case. }
        if (tk = tyClass) and (ci >= 0) and (PyLocals[ci].RecCi >= 0) and
           (i + 2 < endIdx) and (Tokens[i + 1].Kind = tkDot) and
           (Tokens[i + 2].Kind = tkIdent) and
           not ((i + 3 < endIdx) and (Tokens[i + 3].Kind = tkLParen)) then
        begin
          fci := PyLocals[ci].RecCi;
          Inc(i);
          while (i + 1 < endIdx) and (Tokens[i].Kind = tkDot) and
                (Tokens[i + 1].Kind = tkIdent) and (fci >= 0) do
          begin
            fi := FindUField(fci, GetTokenStr(i + 1));
            if fi < 0 then Break;
            tk := IntToTypeKind(UFldTk[fi]);
            if (tk = tyClass) and (UFldRec_[fi] >= REC_UCLASS_BASE) then
              fci := UFldRec_[fi] - REC_UCLASS_BASE
            else
              fci := -1;
            i := i + 2;
          end;
          if tk = tyClass then PyInferLastCi := fci;
          Result := PyWiden(Result, tk);
          Continue;
        end;
        { Method form `name.upper(...)` on a string: the expression's type is
          the str method's result, and the whole postfix chain is skipped so the
          method name (a bare ident to this scanner) does not widen the result
          to variant — which would make an inferred local a variant and then
          scalar-load its TAG on return. Kept in step with PyParseStrMethod's
          table; anything not listed there Errors at parse time, so an unknown
          name never reaches here. }
        if ((tk = tyString) or (tk = tyAnsiString)) and (i + 3 < endIdx) and
           (Tokens[i + 1].Kind = tkDot) and (Tokens[i + 2].Kind = tkIdent) and
           (Tokens[i + 3].Kind = tkLParen) and
           PyStrMethodInfo(GetTokenStr(i + 2), smPName, tk, smArgs) then
        begin
          { A str method returning a CLASS returns a TPyList (split /
            splitlines). Record which class, or the inferred local carries
            tyClass with no identity and overload resolution mis-picks — len()
            on it chose the AnsiString overload and read a class pointer as a
            string handle, segfaulting. }
          if tk = tyClass then PyInferLastCi := FindUClass('TPyList');
          i := i + 3; depth := 0;
          while i < endIdx do
          begin
            if Tokens[i].Kind = tkLParen then Inc(depth)
            else if Tokens[i].Kind = tkRParen then
            begin
              Dec(depth);
              if depth = 0 then Break;
            end;
            Inc(i);
          end;
          Result := PyWiden(Result, tk);
          Inc(i);
          Continue;
        end;
        { A SLICE `name[a:b]` is not an index: it yields a container of the
          same kind as the receiver — a str slice is a str, and slicing a
          KNOWN list yields a list. A variant/unknown receiver's slice used to
          be assumed to be a list too, but a variant can just as easily hold a
          str at runtime — `pyvar_slice` already dispatches on the tag and
          returns whichever is correct, so forcing tyClass/TPyList on the
          STATIC side made a string-holding variant's slice get unboxed as an
          object on return, coming back `[]` (empty) or, worse, SIGSEGV
          (bug-nilpy-subscript-and-slice-of-a-variant-get-the-wrong-static-type).
          Without any receiver-kind arm at all, a def whose body ended in
          `return b[:6]` fell to the Integer default instead
          (bug-nilpy-slice-of-variant-local-returned-is-unusable) — tyVariant
          for an unknown/variant receiver keeps that original fix (any
          non-Integer answer already unblocked it) while also handling the
          string case now that pyvar_slice's tag dispatch is trusted instead
          of guessed. Detected by a ':' at bracket depth 1. }
        if (i + 1 < endIdx) and (Tokens[i + 1].Kind = tkLBrack) and
           PySliceBracketAt(i + 1, endIdx) then
        begin
          if (tk = tyString) or (tk = tyAnsiString) or (tk = tyChar) then
            tk := tyAnsiString
          else if tk = tyClass then
          begin
            tk := tyClass;
            PyInferLastCi := FindUClass('TPyList');
          end
          else
          begin
            tk := tyVariant;
            PyInferLastCi := -1;
          end;
          i := i + 1; depth := 0;
          while i < endIdx do
          begin
            if Tokens[i].Kind = tkLBrack then Inc(depth)
            else if Tokens[i].Kind = tkRBrack then
            begin
              Dec(depth);
              if depth = 0 then Break;
            end;
            Inc(i);
          end;
          Result := PyWiden(Result, tk);
          Inc(i);
          Continue;
        end;
        { Subscript form `name[...]` on a list/dict/unconstrained variant: the
          element could be anything (a str, a float, a bool, another
          container), so the result is a VARIANT — not the tyInteger the
          fallthrough token walk below produced by mistakenly widening on the
          INDEX expression's own type (an int literal index made every
          `xs[i]` infer Integer, a string key happened to make `d[k]` infer
          string by the same accident). Skip the bracket group entirely so
          neither the index nor the element tokens reach that walk
          (bug-nilpy-return-type-inference-mistypes-several-expression-shapes,
          bug-nilpy-subscript-and-slice-of-a-variant-get-the-wrong-static-type).
          String/AnsiString/Char receivers are handled by the char-yielding arm
          right below instead. }
        if ((tk = tyClass) or (tk = tyVariant) or (tk = tyUnknown)) and
           (i + 1 < endIdx) and (Tokens[i + 1].Kind = tkLBrack) and
           not PySliceBracketAt(i + 1, endIdx) then
        begin
          tk := tyVariant;
          PyInferLastCi := -1;
          i := i + 1; depth := 0;
          while i < endIdx do
          begin
            if Tokens[i].Kind = tkLBrack then Inc(depth)
            else if Tokens[i].Kind = tkRBrack then
            begin
              Dec(depth);
              if depth = 0 then Break;
            end;
            Inc(i);
          end;
          Result := PyWiden(Result, tk);
          Inc(i);
          Continue;
        end;
        { Subscript form `name[...]` on a string yields a char; skip the
          bracket group so the index expression's int does not widen the
          result to variant. }
        if ((tk = tyString) or (tk = tyAnsiString)) and (i + 1 < endIdx) and
           (Tokens[i + 1].Kind = tkLBrack) then
        begin
          tk := tyChar;
          i := i + 1; depth := 0;
          while i < endIdx do
          begin
            if Tokens[i].Kind = tkLBrack then Inc(depth)
            else if Tokens[i].Kind = tkRBrack then
            begin
              Dec(depth);
              if depth = 0 then Break;
            end;
            Inc(i);
          end;
        end;
      end;
    end;
    if tk <> tyUnknown then Result := PyWiden(Result, tk);
    Inc(i);
  end;
end;

procedure PyRegisterClassShells;
var i: Integer;
begin
  for i := PyScanLo to MainProgramTokCount - 2 do
    if (Tokens[i].Kind = tkClass) and (Tokens[i + 1].Kind = tkIdent) and
       (FindUClass(GetTokenStr(i + 1)) < 0) then
      { Marked FORWARD, because that is what these rows are: a stub so a class
        can be NAMED before its declaration is parsed, which the full parse then
        fills. Left unmarked they are indistinguishable from a real declaration,
        so the full parse looked like a SECOND class of the same name — which
        is what a duplicate-name diagnostic has to be able to tell apart
        (bug-pascal-duplicate-class-name-silently-shadows). The Pascal forward
        stub `TFoo = class;` already carries this flag and the class-declaration
        path already knows to reuse such a row rather than shadow it. }
      UClsForward[AddUClass(Tokens[i + 1].SOffset, Tokens[i + 1].SLen)] := True;
end;

{ (PyCollectLocals and PyCollectModuleLocals, the token-scanning local-typing
  pre-passes, were retired by PyCollectLocalsAST and PyCollectModuleLocalsAST
  — feature-n-nilpy-ast-based-typing. Both parse instead of scanning.
  PyInferExprType survives only for the CTOR FIELD scan, which still has no
  parseable block of its own: fields must exist before any body is parsed.) }


function PyFindBodyEnd(bodyStart: Integer): Integer;
var i, depth: Integer;
begin
  depth := 1;
  i := bodyStart;
  while i < MainProgramTokCount do
  begin
    if Tokens[i].Kind = tkIndent then Inc(depth)
    else if Tokens[i].Kind = tkDedent then
    begin
      Dec(depth);
      if depth = 0 then begin Result := i; Exit; end;
    end;
    Inc(i);
  end;
  Error('Nil Python: unterminated indented block');
  Result := MainProgramTokCount;
end;

function PyMakeIdent(symIdx: Integer): Integer;
begin
  Result := AllocNode(AN_IDENT);
  ASTIVal[Result] := symIdx;
  ASTTk[Result] := Ord(Syms[symIdx].TypeKind);
end;

function PyIntLiteralText(n: Int64): AnsiString;
var rev, res: AnsiString; negative: Boolean; i: Integer;
begin
  rev := '';
  res := '';
  negative := n < 0;
  if negative then n := -n;
  if n = 0 then
    AppendChar(rev, '0')
  else
    while n > 0 do
    begin
      AppendChar(rev, Chr(Ord('0') + (n mod 10)));
      n := n div 10;
    end;
  if negative then AppendChar(res, '-');
  for i := Length(rev) downto 1 do AppendChar(res, rev[i]);
  Result := res;
end;

function PyStoredName(const s: AnsiString): Integer;
var i: Integer;
begin
  Result := TokCharLen;
  for i := 1 to Length(s) do
  begin
    if TokCharLen >= STRING_CAP then Error('token char buffer overflow');
    TokChars[TokCharLen] := s[i];
    Inc(TokCharLen);
  end;
end;

function PyRawName(off, len: Integer): AnsiString;
var i: Integer; s: AnsiString;
begin
  s := '';
  for i := 0 to len - 1 do AppendChar(s, TokChars[off + i]);
  Result := s;
end;

{ A class ATTRIBUTE constant (`name = "x"` at class level) — the entry index for
  class ci or an inherited one, or -1. See the PyClsAttr* note in defs.inc. }
function PyFindClsAttr(ci: Integer; const nm: AnsiString): Integer;
var i, c: Integer;
begin
  Result := -1;
  c := ci;
  while c >= 0 do
  begin
    for i := 0 to PyClsAttrCount - 1 do
      if (PyClsAttrCi[i] = c) and
         CaseEqual(PyRawName(PyClsAttrNOff[i], PyClsAttrNLen[i]), nm) then
      begin
        Result := i;
        Exit;
      end;
    c := UClsParent[c];
  end;
end;

{ The hidden GLOBAL that holds a non-literal class attribute's one value —
  `mode = Inner()` evaluated once, as Python evaluates a class body once. Named
  rather than tracked in a side table on purpose: the symbol table already is
  the registry, and the construction path finds the value by rebuilding the same
  name from the class and field it is copying. }
function PyClsAttrGlobalName(ci: Integer; const nm: AnsiString): AnsiString;
begin
  Result := '$clsattr.' + PyRawName(UClsNOff[ci], UClsNLen[ci]) + '.' + nm;
end;

{ Is the class-body line at CurTok an attribute whose initialiser needs REAL
  evaluation? CurTok is the name, Tokens[TokPos] the '='. A single literal
  followed by the end of the line is the folded-constant case the pre-pass
  already took. }
function PyClsAttrExprAhead: Boolean;
var k: Integer;
begin
  Result := False;
  k := TokPos + 1;                { the token after '=' }
  if k >= TokCount then Exit;
  if (Tokens[k].Kind in [tkInteger, tkFloat, tkString, tkTrue, tkFalse, tkNil]) and
     (k + 1 < TokCount) and (Tokens[k + 1].Kind in [tkNewline, tkDedent, tkEOF]) then
    Exit;
  Result := True;
end;

{ Evaluate one such attribute into its hidden global, at the point the class
  statement runs. CurTok is the attribute name. }
procedure PyEmitClassAttrExpr(ci: Integer);
var nm, gname: AnsiString; gsym, valNode, asgn, fi: Integer;
begin
  nm := CurTok.SVal;
  Next;                            { onto '=' }
  Next;                            { onto the expression }
  PyParseBoolExpr;
  valNode := CurASTNode;
  gname := PyClsAttrGlobalName(ci, nm);
  gsym := AllocVar(gname, IntToTypeKind(ASTTk[valNode]));
  Syms[gsym].RecName := ResolveNodeRec(valNode);
  { RETYPE the field to what the initialiser actually produced. The pre-pass had
    only the tokens to go on and defaulted to a variant; a list or dict literal
    yields a CLASS handle, and storing one into a variant slot left the tag
    garbage — `Cfg().LIMITS[1]` read None. The slot was laid out variant-sized
    (16 bytes), so a narrower kind always fits. }
  fi := FindUField(ci, nm);
  if fi >= 0 then
  begin
    UFldTk[fi] := ASTTk[valNode];
    UFldRec_[fi] := Syms[gsym].RecName;
  end;
  asgn := AllocNode(AN_ASSIGN);
  ASTLeft[asgn] := PyMakeIdent(gsym);
  ASTRight[asgn] := valNode;
  PyHoistStmt(asgn);
  while not (CurTok.Kind in [tkNewline, tkDedent, tkEOF]) do Next;
end;

{ That constant as an expression node. }
function PyClsAttrNode(ai: Integer): Integer;
begin
  case PyClsAttrKind[ai] of
    PYDC_STR:
      begin
        Result := AllocNode(AN_STR_LIT);
        ASTSOffset[Result] := PyClsAttrSOff[ai];
        ASTSLen[Result] := PyClsAttrSLen[ai];
        ASTTk[Result] := Ord(tyString);
      end;
    PYDC_FLOAT:
      begin
        Result := AllocNode(AN_FLOAT_LIT);
        ASTIVal[Result] := PyClsAttrIVal[ai];
        ASTTk[Result] := Ord(tyDouble);
      end;
    PYDC_BOOL:
      begin
        Result := AllocNode(AN_INT_LIT);
        ASTIVal[Result] := PyClsAttrIVal[ai];
        ASTTk[Result] := Ord(tyBoolean);
      end;
    PYDC_NIL:
      Result := PyMakeNone;
  else
    begin
      Result := AllocNode(AN_INT_LIT);
      ASTIVal[Result] := PyClsAttrIVal[ai];
      ASTTk[Result] := Ord(tyInt64);
    end;
  end;
end;

function PyClassCreate: Integer; forward;

{ Is the construction at CurTok followed by a `.name(` suffix — `Cls().m(...)`?
  Then the statement's right-hand side is a CALL whose receiver happens to be a
  construction, not a construction on its own. Scans past the ctor's own
  argument list, which may itself contain parentheses. }
function PyCtorSuffixAhead: Boolean;
var i, depth: Integer;
begin
  Result := False;
  i := TokPos;                     { the '(' after the class name }
  depth := 0;
  while i < TokCount do
  begin
    if Tokens[i].Kind in [tkLParen, tkLBrack, tkBegin] then Inc(depth)
    else if Tokens[i].Kind in [tkRParen, tkRBrack, tkEnd] then
    begin
      Dec(depth);
      if depth = 0 then
      begin
        Result := (i + 2 < TokCount) and (Tokens[i + 1].Kind = tkDot) and
                  (Tokens[i + 2].Kind = tkIdent);
        Exit;
      end;
    end
    else if Tokens[i].Kind in [tkNewline, tkEOF] then Exit;
    Inc(i);
  end;
end;

{ `_count(1)` (the itertools.count alias) -> a fresh TPyCounter. }
(* `set()` — Python's empty-set constructor. There is no empty-set LITERAL in
   Python (empty braces are a dict), so this call is the only way to write one,
   and it is how the uforth VM initialises its required-files guard.

   Recognised at the assignment-RHS intercepts rather than as a general
   expression: `set` is not a registered proc, so anywhere else it still says
   "undefined variable (set)". Every censused use is an assignment; widen this
   if a corpus ever calls set() in an argument position. *)
{ A CONSTANT parameter default at token index j (`= None`, `= False`,
  `= 0`, `= -1`, `= ""`), for both the class pre-pass and PyParseDef. Advances
  j past the value and returns the ordinal; a string default reports itself
  through isStr plus the char-pool span, matching the ProcParamDefault* arrays
  the shared call path already fills omitted trailing args from.

  None is 0 — the same sentinel PyAnnTypeAt gives Optional[X], so `x: Optional[Word] = None`
  and a nil class reference agree. A NON-constant default (a name, a call, a
  list) is a clean error rather than a guess: Python evaluates it ONCE at
  definition time, and quietly picking either "once" or "per call" would be a
  silent semantic difference. }
function PyParamDefaultAt(var j: Integer; const pname: AnsiString;
                          var isStr: Boolean; var sOff, sLen: Integer): Int64;
var depth: Integer;
begin
  Result := 0;
  isStr := False;
  sOff := 0;
  sLen := 0;
  { `= None` has to stay distinguishable from `= 0` and `= False`, which record
    the same ordinal: a NilPy parameter is a VARIANT, and filling an omitted one
    means building the actual value — None, an int, or a string. Reported
    through a global rather than another var parameter, since every caller of
    this function wants the same answer right after the call. }
  PyDefaultWasNone := True;
  PyDefaultWasFloat := False;
  case Tokens[j].Kind of
    tkNil:     begin Inc(j); Exit; end;
    { A FLOAT default (`max_zoom=2.0`). The token already carries the IEEE 754
      bits in IVal, which is what ProcParamDefaultVal stores, so the value
      travels as-is and only needs to be FLAGGED. Without this it fell through
      to the non-constant branch and became None — `min(max_zoom, ...)` then
      compared against 0 and songformatter's preview rendered its whole page
      into a 128x76 corner at the minimum zoom. }
    tkFloat:   begin Result := Tokens[j].IVal; PyDefaultWasNone := False;
                     PyDefaultWasFloat := True; Inc(j); Exit; end;
    tkTrue:    begin Result := 1; PyDefaultWasNone := False; Inc(j); Exit; end;
    tkFalse:   begin PyDefaultWasNone := False; Inc(j); Exit; end;
    tkInteger: begin Result := Tokens[j].IVal; PyDefaultWasNone := False; Inc(j); Exit; end;
    tkString:
      begin
        isStr := True;
        PyDefaultWasNone := False;
        sOff := Tokens[j].SOffset;
        sLen := Tokens[j].SLen;
        Inc(j);
        Exit;
      end;
    tkMinus:
      if Tokens[j + 1].Kind = tkInteger then
      begin
        Result := -Tokens[j + 1].IVal;
        PyDefaultWasNone := False;
        j := j + 2;
        Exit;
      end
      else if Tokens[j + 1].Kind = tkFloat then
      begin
        { negate by flipping the IEEE sign bit — the bits are the value here }
        Result := Tokens[j + 1].IVal xor Int64($8000000000000000);
        PyDefaultWasNone := False;
        PyDefaultWasFloat := True;
        j := j + 2;
        Exit;
      end;
  end;
  { NON-CONSTANT default, e.g. `target: Word = w` where w is an enclosing
    local. Python evaluates such a default ONCE at def time (closure-by-value
    capture — the loop-variable idiom). uforth uses it only for native word
    bodies, which reach the interpreter through the exec/native path (a stub),
    so they never actually run in a COMPILED uforth. To move compilation past
    the wall we accept the expression, skip its token span (balancing brackets,
    stopping at the top-level comma or ')'), and treat the parameter as an
    optional None-valued default. True def-time capture is filed as a feature
    (feature-nilpy-closure-default-and-remaining). }
  begin
    depth := 0;
    while j < TokCount do
    begin
      case Tokens[j].Kind of
        tkLParen, tkLBrack, tkBegin: Inc(depth);
        tkRParen:
          begin
            if depth = 0 then Exit;   { the closing ) of the param list }
            Dec(depth);
          end;
        tkRBrack, tkEnd: Dec(depth);
        tkComma: if depth = 0 then Exit;
      end;
      Inc(j);
    end;
  end;
end;

{ Does a user definition of this name shadow the builtin spelling HERE — in the
  module being parsed right now? Python's rule is per-module: a name counts if
  this module defines it (a def or a module-level variable, both tagged with the
  current unit) or imported it by name. A def in some OTHER module does not,
  even though flat unit scope makes it findable. bug-nilpy-imported-name-shadows-builtin-everywhere. }
function PyUserNameShadowsHere(const nm: AnsiString): Boolean;
var si, i, ni: Integer;
begin
  Result := True;
  if FindProcInUnit(nm, CurrentUnitIdx) >= 0 then Exit;
  si := FindSym(nm);
  if (si >= 0) and (SymUnitIdx[si] = CurrentUnitIdx) then Exit;
  ni := InternStr(LowerCase(nm));
  for i := 0 to PyImpNameCount - 1 do
    if (PyImpName[i] = ni) and (PyImpNameUnit[i] = CurrentUnitIdx) then Exit;
  Result := False;
end;

{ `set(...)`, empty or over an iterable. NOT a hook when THIS module declares or
  imports its own `set` — songformatter's settings.py has `def set(section,
  option, value)` and convertrawtext.py imports it by name, and a user
  definition must win over a builtin spelling where it is in scope. }
function PyIsSetCall: Boolean;
begin
  Result := (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'set') and
            (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) and
            (not PyUserNameShadowsHere('set'));
end;

function PyIsEmptySetCall: Boolean;
begin
  Result := PyIsSetCall and (TokPos + 1 < TokCount) and
            (Tokens[TokPos + 1].Kind = tkRParen);
end;

{ A set is a TPyList (the representation annotations and `in` already use), so
  `set()` is an empty one and `set(xs)` is a duplicate-skipping copy through
  pylib's pyset_of — which also accepts a dict (its keys) and a string (its
  characters), like CPython. }
function PyParseEmptySet: Integer;
var ci, recId, sizeNode, argNode: Integer;
begin
  if not PyIsEmptySetCall then
  begin
    Next;                          (* set *)
    Expect(tkLParen, '(');
    PyParseBoolExpr;
    argNode := AllocNode(AN_ARG);
    ASTLeft[argNode] := CurASTNode;
    Result := AllocNode(AN_CALL);
    ASTIVal[Result] := FindProc('pyset_of');
    if ASTIVal[Result] < 0 then Error('Nil Python: pylib (pyset_of) not loaded');
    ASTTk[Result] := Ord(tyClass);
    ASTRight[Result] := REC_UCLASS_BASE + FindUClass('TPyList');
    ASTLeft[Result] := argNode;
    Expect(tkRParen, ')');
    CurASTNode := Result;
    Exit;
  end;
  Next; Next; Next;                (* set ( ) *)
  ci := FindUClass('TPyList');
  if ci < 0 then Error('Nil Python: pylib (TPyList) not loaded');
  recId := REC_UCLASS_BASE + ci;
  Result := AllocNode(AN_CALL);
  ASTIVal[Result] := -Ord(tkGetMem);
  ASTTk[Result] := Ord(tyClass);
  ASTRight[Result] := recId;
  sizeNode := AllocNode(AN_INT_LIT);
  ASTIVal[sizeNode] := RecSize(recId);
  ASTTk[sizeNode] := Ord(tyInteger);
  argNode := AllocNode(AN_ARG);
  ASTLeft[argNode] := sizeNode;
  ASTLeft[Result] := argNode;
  CurASTNode := Result;
end;

function PyIsCountCall: Boolean;
begin
  Result := (PyCountAlias <> '') and (CurTok.Kind = tkIdent) and
            CaseEqual(CurTok.SVal, PyCountAlias) and
            (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen);
end;

function PyParseCountCreate: Integer;
var ci, recId, node, argNode, sizeNode, valArg: Integer;
begin
  ci := FindUClass('TPyCounter');
  if ci < 0 then Error('Nil Python: pylib (TPyCounter) not loaded');
  recId := REC_UCLASS_BASE + ci;
  Next;                       { the alias ident }
  Expect(tkLParen, '(');
  node := AllocNode(AN_CALL);
  ASTIVal[node] := -Ord(tkGetMem);
  ASTTk[node] := Ord(tyClass);
  ASTRight[node] := recId;
  sizeNode := AllocNode(AN_INT_LIT);
  ASTIVal[sizeNode] := RecSize(recId);
  ASTTk[sizeNode] := Ord(tyInteger);
  argNode := AllocNode(AN_ARG);
  ASTLeft[argNode] := sizeNode;
  ASTLeft[node] := argNode;
  PyParseBoolExpr;
  valArg := AllocNode(AN_ARG);
  ASTLeft[valArg] := CurASTNode;
  ASTRight[argNode] := valArg;
  Expect(tkRParen, ')');
  Result := node;
end;

function PyClassCreateExpr: Integer;
begin
  Result := PyClassCreate;
end;

{ The default VALUE node for dataclass field `fidx` of class ci, where dcBase
  is the class's first entry in the PyDc* default table. Extracted so BOTH the
  trailing-argument fill and the keyword-argument hole fill use ONE
  construction: a factory default is re-parsed per construction site, so a
  second copy would quietly diverge. }
const
  { widest dataclass argument list the keyword binder handles; the ctor
    synthesiser already caps a dataclass at 15 fields }
  PY_MAX_DC_KW = 32;

function PyDcDefaultNode(ci, dcBase, fidx: Integer): Integer;
var i, k, valNode, tkNode: Integer; tkF: TTypeKind;
begin
  i := dcBase + fidx;
  if (i >= PyDcCount) or (PyDcCi[i] <> ci) or (PyDcKind[i] = PYDC_NONE) then
    Error('Nil Python: missing argument for dataclass field without default');
case PyDcKind[i] of
    PYDC_INT:
    begin
      valNode := AllocNode(AN_INT_LIT);
      ASTIVal[valNode] := PyDcIVal[i];
      ASTTk[valNode] := Ord(tyInteger);
    end;
    PYDC_FLOAT:
    begin
      valNode := AllocNode(AN_FLOAT_LIT);
      ASTIVal[valNode] := PyDcIVal[i];
      ASTTk[valNode] := Ord(tyDouble);
    end;
    PYDC_STR:
    begin
      valNode := AllocNode(AN_STR_LIT);
      ASTSOffset[valNode] := PyDcSOff[i];
      ASTSLen[valNode] := PyDcSLen[i];
      ASTTk[valNode] := Ord(tyString);
    end;
    PYDC_NIL:
    begin
      tkF := IntToTypeKind(UFldTk[UClsFBase[ci] + (i - dcBase)]);
      if tkF = tyAnsiString then
        Error('Nil Python: None default for a str field is not supported yet');
      valNode := AllocNode(AN_INT_LIT);
      ASTIVal[valNode] := 0;
      ASTTk[valNode] := Ord(tkF);
    end;
    PYDC_FACTORY_EXPR:
    begin
      { re-parse the captured lambda-body span at this construction
        site: evaluated per construction, like CPython's factory }
      k := TokPos - 1;              { restore point (CurTok's index) }
      TokPos := PyDcIVal[i];
      Next;
      PyParseBoolExpr;
      valNode := CurASTNode;
      TokPos := k;
      Next;
    end;
    PYDC_FACTORY_LIST:
    begin
      { fresh empty TPyList (same GetMem+ctor shape as a [] literal) }
      k := FindUClass('TPyList');
      if k < 0 then Error('Nil Python: pylib (TPyList) not loaded');
      valNode := AllocNode(AN_CALL);
      ASTIVal[valNode] := -Ord(tkGetMem);
      ASTTk[valNode] := Ord(tyClass);
      ASTRight[valNode] := REC_UCLASS_BASE + k;
      tkNode := AllocNode(AN_INT_LIT);
      ASTIVal[tkNode] := RecSize(REC_UCLASS_BASE + k);
      ASTTk[tkNode] := Ord(tyInteger);
      k := AllocNode(AN_ARG);
      ASTLeft[k] := tkNode;
      ASTLeft[valNode] := k;
    end;
    PYDC_FACTORY_DICT:
    begin
      { fresh empty TPyDict (same GetMem+ctor shape as a {} literal) }
      k := FindUClass('TPyDict');
      if k < 0 then Error('Nil Python: pylib (TPyDict) not loaded');
      valNode := AllocNode(AN_CALL);
      ASTIVal[valNode] := -Ord(tkGetMem);
      ASTTk[valNode] := Ord(tyClass);
      ASTRight[valNode] := REC_UCLASS_BASE + k;
      tkNode := AllocNode(AN_INT_LIT);
      ASTIVal[tkNode] := RecSize(REC_UCLASS_BASE + k);
      ASTTk[tkNode] := Ord(tyInteger);
      k := AllocNode(AN_ARG);
      ASTLeft[k] := tkNode;
      ASTLeft[valNode] := k;
    end;
    else { PYDC_BOOL }
    begin
      valNode := AllocNode(AN_INT_LIT);
      ASTIVal[valNode] := PyDcIVal[i];
      ASTTk[valNode] := Ord(tyBoolean);
    end;
  end;
  Result := valNode;
end;

function PyClassCreate: Integer;
var name: AnsiString; ci, recId, node, argNode, lastArg, sizeNode: Integer;
    nArgs, i, k, dcBase, valNode, tkNode, ctorMi, ctorPi: Integer; tkF: TTypeKind;
    kwI, kwJ, kwFld, kwMax, kwPos, kwDcBase: Integer; kwName: AnsiString;
    kwCtorMi, kwCtorPi, kwPk, kwVal: Integer;
    kwAny: Boolean; kwSlot: array[0..PY_MAX_DC_KW - 1] of Integer;
    attrAny: Boolean; attrSym, attrAsgn, attrFld, attrFi, attrGSym: Integer;
begin
  name := CurTok.SVal;
  ci := -1;
  if PyCtorQualUnit >= 0 then ci := FindUClassInUnit(name, PyCtorQualUnit);
  { skip a same-named RECORD (the RTL's `Text` file type against tkinter's Text
    widget): a construction always means the class }
  if ci < 0 then ci := FindUClassNonRecord(name);
  if ci < 0 then ci := FindUClass(name);
  if ci < 0 then Error('Nil Python: class not found: ' + name);
  recId := REC_UCLASS_BASE + ci;
  Next;
  Expect(tkLParen, '(');
  node := AllocNode(AN_CALL);
  ASTIVal[node] := -Ord(tkGetMem);
  ASTTk[node] := Ord(tyClass);
  ASTRight[node] := recId;
  sizeNode := AllocNode(AN_INT_LIT);
  ASTIVal[sizeNode] := RecSize(recId);
  ASTTk[sizeNode] := Ord(tyInteger);
  argNode := AllocNode(AN_ARG);
  ASTLeft[argNode] := sizeNode;
  ASTLeft[node] := argNode;
  lastArg := argNode;
  nArgs := 0;
  { `Word(name=n, wid=w)` — keyword arguments. A @dataclass has no ctor METHOD
    (its arguments map straight onto the fields, in declaration order), so a
    keyword binds to a FIELD index rather than to a proc parameter. Collected
    into kwSlot here and re-emitted in field order below. }
  for kwI := 0 to PY_MAX_DC_KW - 1 do kwSlot[kwI] := -1;
  kwAny := False;
  kwMax := -1;
  kwPos := 0;
  while CurTok.Kind <> tkRParen do
  begin
    kwFld := -1;
    if (CurTok.Kind = tkIdent) and (TokPos < TokCount) and
       (Tokens[TokPos].Kind = tkAssign) then
    begin
      kwName := CurTok.SVal;
      { The CONSTRUCTOR's parameters come FIRST when there is one. A
        hand-written `__init__` names its options as parameters, and it usually
        stores them into fields of the same name — `def __init__(self, parent,
        on_next, on_change=None): self.on_next = on_next`. Matching the FIELD
        first then bound the keyword to a field INDEX while the positional
        argument had already taken that slot, and the construction was rejected
        with "got multiple values for field 'on_next'" — an argument list that
        is plain Python. Only a class with NO ctor (the dataclass shape, whose
        arguments map straight onto its fields) falls through to the fields. }
      kwCtorMi := FindUMeth(ci, 'create');
      kwFld := -1;
      if kwCtorMi >= 0 then
      begin
        kwCtorPi := UMthProc_[kwCtorMi];
        for kwPk := 1 to Procs[kwCtorPi].ParamCount - 1 do
          if CaseEqual(Procs[kwCtorPi].Params[kwPk].Name, kwName) then
            kwFld := kwPk - 1;
      end;
      if kwFld < 0 then
      begin
        kwFld := FindUField(ci, kwName);
        if kwFld >= 0 then
          kwFld := kwFld - UClsFBase[ci]   { absolute -> field INDEX }
        else
          Error('Nil Python: ' + name + ' has no field or constructor parameter named ''' +
                kwName + '''');
      end;
      Next; Next;                          { the name and the '=' }
      kwAny := True;
    end;
    PyParseBoolExpr;
    argNode := AllocNode(AN_ARG);
    ASTLeft[argNode] := CurASTNode;
    ASTRight[argNode] := -1;
    if kwFld < 0 then
    begin
      if kwAny then
        Error('Nil Python: positional argument after keyword argument in ' + name + '()');
      kwFld := kwPos;
      Inc(kwPos);
    end;
    if (kwFld < 0) or (kwFld >= PY_MAX_DC_KW) then
      Error('Nil Python: too many arguments to ' + name + '()');
    if kwSlot[kwFld] >= 0 then
      Error('Nil Python: ' + name + '() got multiple values for field ''' + kwName + '''');
    kwSlot[kwFld] := argNode;
    if kwFld > kwMax then kwMax := kwFld;
    Inc(nArgs);
    if not Eat(tkComma) then break;
  end;
  Expect(tkRParen, ')');
  { Re-emit in FIELD order. A hole below the highest supplied field is filled
    from the declared default — uforth's Word(...) skips data_addr between
    immediate and wid, so interior holes are the normal case, not an edge one.
    Trailing fields are left to the existing fill below. }
  { Unconditional: with no keyword at all this simply re-links the chain in the
    order it was parsed, so the positional path is unchanged. Skipping it left
    every AN_ARG with ASTRight = -1 and the call ran off a one-element chain. }
  begin
    lastArg := ASTLeft[node];              { the GetMem size arg }
    for kwI := 0 to kwMax do
    begin
      if kwSlot[kwI] >= 0 then
      begin
        argNode := kwSlot[kwI];
        { A VARIANT argument landing in a CLASS-typed dataclass FIELD. The call
          lowering already unboxes it (IRLowerCallArg's pyvarobj block), but an
          unboxed pointer is a bare reference: the field slot is never released,
          so nothing balances it, while the variant TEMP the value came out of is
          released at the end of the statement and takes the object with it. The
          field then points at a freed block — correct at the call, garbage (or a
          recycled neighbour's list) at the first read. Unbox HERE instead, with
          a retain, so the field owns what it holds.
          [[bug-nilpy-slice-of-variant-local-returned-is-unusable]] }
        if (ci < PY_MAX_DC_FIELDS) and PyDcClassIsDc[ci] and
           (kwI < UClsFCount[ci]) and
           (IntToTypeKind(ASTTk[ASTLeft[argNode]]) = tyVariant) and
           (UFldTk[UClsFBase[ci] + kwI] = Ord(tyClass)) and
           (UFldRec_[UClsFBase[ci] + kwI] >= REC_UCLASS_BASE) then
          ASTLeft[argNode] := PyUnboxVariantToClassEx(ASTLeft[argNode],
            UFldRec_[UClsFBase[ci] + kwI] - REC_UCLASS_BASE, True);
      end
      else
      begin
        kwDcBase := -1;
        for kwJ := 0 to PyDcCount - 1 do
          if PyDcCi[kwJ] = ci then begin kwDcBase := kwJ; break; end;
        if kwDcBase >= 0 then
        begin
          argNode := AllocNode(AN_ARG);
          ASTLeft[argNode] := PyDcDefaultNode(ci, kwDcBase, kwI);
          ASTRight[argNode] := -1;
        end
        else
        begin
          { A hand-written __init__ rather than a @dataclass: fill the hole from
            the CTOR PARAMETER's declared default, the same table the trailing
            fill below reads. Without this, keyword arguments had to cover a
            contiguous PREFIX of the parameters, so skipping one optional was an
            error — `W(master, text="x")` with a `width` in between. That is the
            normal shape of every widget call a tkinter-style façade takes
            (`tk.Canvas(self, highlightthickness=0)`), which is what made such a
            façade impossible to write. Param 0 is self, so user arg kwI is
            param kwI+1. }
          kwCtorMi := FindUMeth(ci, 'create');
          if kwCtorMi < 0 then
            Error('Nil Python: ' + name + '() has no constructor to take defaults from');
          kwCtorPi := UMthProc_[kwCtorMi];
          kwPk := kwI + 1;
          if (kwPk >= MAX_PROC_PARAMS) or
             (not ProcParamHasDefault[kwCtorPi * MAX_PROC_PARAMS + kwPk]) then
            Error('Nil Python: ' + name + '() is missing a value for parameter ' +
                  AIntToStr(kwI + 1) + ', which has no default');
          if ProcParamDefaultIsStr[kwCtorPi * MAX_PROC_PARAMS + kwPk] then
          begin
            kwVal := AllocNode(AN_STR_LIT);
            ASTSOffset[kwVal] := ProcParamDefaultSOff[kwCtorPi * MAX_PROC_PARAMS + kwPk];
            ASTSLen[kwVal] := ProcParamDefaultSLen[kwCtorPi * MAX_PROC_PARAMS + kwPk];
            ASTTk[kwVal] := Ord(tyString);
          end
          else if ProcParamDefaultIsFloat[kwCtorPi * MAX_PROC_PARAMS + kwPk] then
          begin
            kwVal := AllocNode(AN_FLOAT_LIT);
            ASTIVal[kwVal] := ProcParamDefaultVal[kwCtorPi * MAX_PROC_PARAMS + kwPk];
            ASTTk[kwVal] := Ord(tyDouble);
          end
          else if Procs[kwCtorPi].Params[kwPk].TypeKind = tyVariant then
            { A VARIANT hole. Two things go wrong with a bare ordinal here: the
              parameter is passed by REFERENCE, so the callee dereferences it
              (`tk.Label(root, textvariable=sv)` skipped `font` and segfaulted),
              and a library's `= 0` means "not supplied", which every façade
              reads as `pyvartag(v) <> 0`. None is both — an addressable empty
              variant. Same rule as DefaultArgValueNode, which the non-ctor
              paths use. }
            kwVal := PyMakeNone
          else
          begin
            kwVal := AllocNode(AN_INT_LIT);
            ASTIVal[kwVal] := ProcParamDefaultVal[kwCtorPi * MAX_PROC_PARAMS + kwPk];
            { the LITERAL's type, not the parameter's: tagged as the parameter's
              it looked like a value that needed no conversion, and the
              call-argument boxing never ran }
            ASTTk[kwVal] := Ord(Procs[kwCtorPi].Params[kwPk].TypeKind);
          end;
          argNode := AllocNode(AN_ARG);
          ASTLeft[argNode] := kwVal;
          ASTRight[argNode] := -1;
        end;
      end;
      ASTRight[lastArg] := argNode;
      lastArg := argNode;
    end;
    nArgs := kwMax + 1;
  end;
  { A hand-written ctor's declared parameter DEFAULTS. PyClassCreate builds
    the call itself — GetMem size, then the user args — so it never passes
    through the shared path that fills omitted trailing args, and `C()` on a
    ctor with defaults handed the body uninitialised stack (a segfault, not a
    diagnostic). Param 0 is self, so user arg n is param n+1. }
  ctorMi := FindUMeth(ci, 'create');
  if ctorMi >= 0 then
  begin
    ctorPi := UMthProc_[ctorMi];
    while nArgs < Procs[ctorPi].ParamCount - 1 do
    begin
      k := nArgs + 1;
      if (k >= MAX_PROC_PARAMS) or
         (not ProcParamHasDefault[ctorPi * MAX_PROC_PARAMS + k]) then Break;
      if ProcParamDefaultIsStr[ctorPi * MAX_PROC_PARAMS + k] then
      begin
        valNode := AllocNode(AN_STR_LIT);
        ASTSOffset[valNode] := ProcParamDefaultSOff[ctorPi * MAX_PROC_PARAMS + k];
        ASTSLen[valNode] := ProcParamDefaultSLen[ctorPi * MAX_PROC_PARAMS + k];
        ASTTk[valNode] := Ord(tyString);
      end
      else if ProcParamDefaultIsFloat[ctorPi * MAX_PROC_PARAMS + k] then
      begin
        { a FLOAT default (max_zoom=2.0): IVal holds the IEEE bits, and only
          AN_FLOAT_LIT tags them tyDouble — an AN_INT_LIT here handed the body
          the bit pattern as an integer. }
        valNode := AllocNode(AN_FLOAT_LIT);
        ASTIVal[valNode] := ProcParamDefaultVal[ctorPi * MAX_PROC_PARAMS + k];
        ASTTk[valNode] := Ord(tyDouble);
      end
      else if Procs[ctorPi].Params[k].TypeKind = tyVariant then
        { A VARIANT parameter's omitted default has to be a real variant, not a
          bare integer: `def __init__(self, a, on_change=None)` types on_change
          Any, and filling it with AN_INT_LIT 0 handed the callee a machine word
          where it reads a 16-byte slot — the call SEGFAULTED, or printed empty
          fields, while passing the argument explicitly worked. pynone() is the
          same None the `return None` path already uses for a variant result. }
        valNode := PyMakeNone
      else
      begin
        valNode := AllocNode(AN_INT_LIT);
        ASTIVal[valNode] := ProcParamDefaultVal[ctorPi * MAX_PROC_PARAMS + k];
        ASTTk[valNode] := Ord(Procs[ctorPi].Params[k].TypeKind);
      end;
      argNode := AllocNode(AN_ARG);
      ASTLeft[argNode] := valNode;
      ASTRight[lastArg] := argNode;
      lastArg := argNode;
      Inc(nArgs);
    end;
  end;
  { @dataclass: fill omitted trailing args from field defaults. }
  if (ci < PY_MAX_DC_FIELDS) and PyDcClassIsDc[ci] then
  begin
    { locate the class's first default-table entry }
    dcBase := -1; k := 0;
    for i := 0 to PyDcCount - 1 do
      if PyDcCi[i] = ci then begin dcBase := i; break; end;
    if dcBase >= 0 then
      while nArgs < UClsFCount[ci] do
      begin
        valNode := PyDcDefaultNode(ci, dcBase, nArgs);
        argNode := AllocNode(AN_ARG);
        ASTLeft[argNode] := valNode;
        ASTRight[lastArg] := argNode;
        lastArg := argNode;
        Inc(nArgs);
      end;
  end;
  Result := node;
  { PXXDBG=n.ctorargs — every construction's slot kinds and types. This is the
    probe that disproved the recorded root cause of
    bug-nilpy-slice-of-variant-local-returned-is-unusable (the argument was
    tyVariant in BOTH passes, not mis-tagged tyClass); it cost a source patch
    and a self-compile to ask that question then. }
  if PxxDbgEnabled('n.ctorargs') then
  begin
    Write('PXXDBG n.ctorargs ', name, ' trial=', Ord(PyTypingPass));
    argNode := ASTRight[ASTLeft[node]];
    k := 0;
    while argNode >= 0 do
    begin
      Write(' [', k, ']kind=', ASTKind[ASTLeft[argNode]],
            ',tk=', ASTTk[ASTLeft[argNode]]);
      argNode := ASTRight[argNode];
      Inc(k);
    end;
    WriteLn;
  end;
  { CLASS ATTRIBUTES (`name = "note_counting"` at class level): give the new
    instance its own copy. Python attaches them to the CLASS and reads them
    through the instance, which is indistinguishable from this for every read —
    the difference is only visible if the CLASS attribute is rebound at run time
    to change existing instances, which nothing here does.

    Emitted as hoisted stores on a temp, so they land AFTER the constructor. A
    class with a constructor is therefore REFUSED rather than silently having
    its ctor's own writes overwritten — that is the one case where "after" is
    the wrong order and guessing would be silent corruption. }
  attrAny := False;
  for i := 0 to PyClsAttrCount - 1 do
    if PyClsAttrCi[i] = ci then attrAny := True;
  { ...and the NON-literal ones, which live in a hidden global apiece rather
    than in the constant table (PyEmitClassAttrExpr). They are found by name,
    from the class's own field list. }
  for i := 0 to UClsFCount[ci] - 1 do
    if FindSym(PyClsAttrGlobalName(ci,
         PyRawName(UFldNOff[UClsFBase[ci] + i], UFldNLen[UClsFBase[ci] + i]))) >= 0 then
      attrAny := True;
  { A class WITH a constructor applies its class attributes at the head of that
    constructor (PyClassAttrInitSeq), which is Python's order — before
    `__init__` runs, so `__init__` can overwrite them. Only a class without one
    needs the hoisted-temp form below, where "after" is the only order there is
    and nothing can be overwritten. }
  if attrAny and (FindUMeth(ci, 'create') >= 0) then attrAny := False;
  if attrAny then
  begin
    attrSym := AllocVar(PyHiddenName('clsattr'), tyClass);
    Syms[attrSym].RecName := recId;
    attrAsgn := AllocNode(AN_ASSIGN);
    ASTLeft[attrAsgn] := PyMakeIdent(attrSym);
    ASTRight[attrAsgn] := node;
    PyHoistStmt(attrAsgn);
    for i := 0 to PyClsAttrCount - 1 do
      if PyClsAttrCi[i] = ci then
      begin
        attrFld := AllocNode(AN_FIELD);
        ASTLeft[attrFld] := PyMakeIdent(attrSym);
        ASTSOffset[attrFld] := PyClsAttrNOff[i];
        ASTSLen[attrFld] := PyClsAttrNLen[i];
        attrFi := FindUField(ci, PyRawName(PyClsAttrNOff[i], PyClsAttrNLen[i]));
        if attrFi >= 0 then ASTTk[attrFld] := UFldTk[attrFi]
        else ASTTk[attrFld] := Ord(tyVariant);
        attrAsgn := AllocNode(AN_ASSIGN);
        ASTLeft[attrAsgn] := attrFld;
        ASTRight[attrAsgn] := PyClsAttrNode(i);
        PyHoistStmt(attrAsgn);
      end;
    { the non-literal ones: copy the shared value out of its hidden global }
    for i := 0 to UClsFCount[ci] - 1 do
    begin
      attrFi := UClsFBase[ci] + i;
      attrGSym := FindSym(PyClsAttrGlobalName(ci,
                    PyRawName(UFldNOff[attrFi], UFldNLen[attrFi])));
      if attrGSym < 0 then Continue;
      attrFld := AllocNode(AN_FIELD);
      ASTLeft[attrFld] := PyMakeIdent(attrSym);
      ASTSOffset[attrFld] := UFldNOff[attrFi];
      ASTSLen[attrFld] := UFldNLen[attrFi];
      ASTTk[attrFld] := UFldTk[attrFi];
      attrAsgn := AllocNode(AN_ASSIGN);
      ASTLeft[attrAsgn] := attrFld;
      ASTRight[attrAsgn] := PyMakeIdent(attrGSym);
      PyHoistStmt(attrAsgn);
    end;
    Result := PyMakeIdent(attrSym);
  end;
end;

{ The class attributes of `ci`, as assignments onto SELF, for the head of the
  constructor. Python creates class attributes when the CLASS is defined, so an
  instance sees them before `__init__` runs and `__init__` may overwrite them —
  which is the opposite of applying them to a finished object. Emitting them
  here is what lets a class have both (`class TkCanvasBackend: blendmode =
  _BlendModes()` beside an `__init__`), where the construction path had to
  refuse. Returns -1 when the class has none. }
function PyClassAttrInitSeq(ci, selfSym: Integer): Integer;
var i, fi, gsym, fldNode, asgn, seq: Integer;
begin
  seq := -1;
  for i := 0 to PyClsAttrCount - 1 do
    if PyClsAttrCi[i] = ci then
    begin
      fldNode := AllocNode(AN_FIELD);
      ASTLeft[fldNode] := PyMakeIdent(selfSym);
      ASTSOffset[fldNode] := PyClsAttrNOff[i];
      ASTSLen[fldNode] := PyClsAttrNLen[i];
      fi := FindUField(ci, PyRawName(PyClsAttrNOff[i], PyClsAttrNLen[i]));
      if fi >= 0 then ASTTk[fldNode] := UFldTk[fi]
      else ASTTk[fldNode] := Ord(tyVariant);
      asgn := AllocNode(AN_ASSIGN);
      ASTLeft[asgn] := fldNode;
      ASTRight[asgn] := PyClsAttrNode(i);
      seq := PySeqAppend(seq, asgn);
    end;
  { the non-literal ones live in a hidden global apiece }
  for i := 0 to UClsFCount[ci] - 1 do
  begin
    fi := UClsFBase[ci] + i;
    gsym := FindSym(PyClsAttrGlobalName(ci, PyRawName(UFldNOff[fi], UFldNLen[fi])));
    if gsym < 0 then Continue;
    fldNode := AllocNode(AN_FIELD);
    ASTLeft[fldNode] := PyMakeIdent(selfSym);
    ASTSOffset[fldNode] := UFldNOff[fi];
    ASTSLen[fldNode] := UFldNLen[fi];
    ASTTk[fldNode] := UFldTk[fi];
    asgn := AllocNode(AN_ASSIGN);
    ASTLeft[asgn] := fldNode;
    ASTRight[asgn] := PyMakeIdent(gsym);
    seq := PySeqAppend(seq, asgn);
  end;
  PyClassAttrInitSeq := seq;
end;

{ Nil Python str methods: `s.upper()` -> pylib pystr_upper(s).

  Reached from the shared parser's postfix `.member` branch (parser.inc) once
  the base expression is known to be string-typed and PyExprMode is on; the
  method name is already consumed, CurTok is the '('. Returns the AN_CALL node
  with ASTTk set to the method's result type, which the caller feeds back into
  its suffix loop so chains keep parsing.

  Adding a method = one row here plus the pylib function. Keep the two in step:
  an unknown name must Error, never fall through to the record-field path,
  which would build a bogus field access on a string (the tarrconstr8 class of
  silent breakage the array guard above this site exists to prevent). }
{ NilPy `s[i]` -> pylib pystr_at(s, i). Python subscripts are 0-based and allow
  negative indices; Pascal's are 1-based with neither. Doing the fixup in the
  RUNTIME helper rather than as index arithmetic here keeps the negative case
  (which needs Length(s)) correct without evaluating the base twice. }
{ Nil Python KEYWORD ARGUMENTS — `f(a, key=expr)`.

  Two halves. This one runs at the point an argument would be parsed: if the
  next two tokens are `ident =` (NOT `==` — the lexer already split those into
  tkEq), consume them and resolve the name against the callee's declared
  parameters, returning paramIndex+1. 0 means "ordinary positional argument",
  so a zero-initialised AN_ARG node reads as positional and every Pascal path
  is unaffected. firstParam is 1 on the method path, where Params[0] is Self
  and `self=` must not be bindable by name.

  The callee-side defaults (ProcParamDefault*) already existed; all that was
  missing was binding by name at the call site. }
function PyKwArgIndex(mpi, firstParam: Integer): Integer;
var nm: AnsiString;
    i, kwSib: Integer;
begin
  PyKwArgIndex := 0;
  if not isNilPy then Exit;
  if CurTok.Kind <> tkIdent then Exit;
  if Tokens[TokPos].Kind <> tkAssign then Exit;
  nm := CurTok.SVal;
  Next;              { the name }
  Next;              { the '=' }
  for i := firstParam to Procs[mpi].ParamCount - 1 do
    if CaseEqual(Procs[mpi].Params[i].Name, nm) then
    begin
      PyKwArgIndex := i + 1;
      Exit;
    end;
  { No declared parameter of that name — but a callee with `**kwargs` takes it
    anyway, into the dict. The KEY has to survive until the whole argument list
    is parsed, so the string literal node is allocated here and its index
    returned NEGATIVE (-(node+1)); PyPackStarArgs decodes it. }
  if ProcPyKwIdx[mpi] >= 0 then
  begin
    i := AllocNode(AN_STR_LIT);
    ASTSOffset[i] := PyStoredName(nm);
    ASTSLen[i] := Length(nm);
    ASTTk[i] := Ord(tyString);
    PyKwArgIndex := -(i + 1);
    Exit;
  end;
  { …or a SIBLING OVERLOAD has it, and the call site simply resolved to the wrong
    member: the keyword name is checked against the ONE proc already chosen, not
    against the overload SET (bug-nilpy-keyword-arg-vs-overload-set). Say that,
    instead of the flatly untrue "has no parameter named" — the name exists, it
    is on another arity, and the reader has no way to guess that from the old
    message. }
  for i := 0 to ProcCount - 1 do
    if (i <> mpi) and CaseEqual(Procs[i].Name, Procs[mpi].Name) then
      for kwSib := 0 to Procs[i].ParamCount - 1 do
        if CaseEqual(Procs[i].Params[kwSib].Name, nm) then
          Error('Nil Python: ' + Procs[mpi].Name + ' has no parameter named '''
                + nm + ''' in the overload taking '
                + PyIntLiteralText(Procs[mpi].ParamCount)
                + ' argument(s) — a sibling overload taking '
                + PyIntLiteralText(Procs[i].ParamCount)
                + ' does. Keyword names are resolved against the chosen overload,'
                + ' not the whole set: pass it positionally for now'
                + ' (bug-nilpy-keyword-arg-vs-overload-set)');
  Error('Nil Python: ' + Procs[mpi].Name + ' has no parameter named ''' + nm + '''');
end;

{ The second half: once the whole argument list is parsed, reorder the AN_ARG
  chain into declaration order. Each node carries its binding in ASTIVal
  (paramIndex+1 from PyKwArgIndex, 0 = positional, consumed here so IR lowering
  sees an ordinary chain). Holes BELOW the highest bound parameter are filled
  from the declared defaults; trailing holes are left alone so the existing
  FillDefaultArgs / IR default path keeps handling them.

  No-op — chain untouched, not even walked twice — when no argument was a
  keyword, which is every Pascal call and most NilPy ones. }
procedure PyBindKwArgs(mpi: Integer; var argsHead, lastArg, nArgs: Integer);
var slot: array[0..MAX_PROC_PARAMS-1] of Integer;
    n, k, pos, maxIdx, i: Integer;
    anyKw, sawKw: Boolean;
begin
  anyKw := False;
  n := argsHead;
  while n >= 0 do
  begin
    if ASTIVal[n] <> 0 then anyKw := True;
    n := ASTRight[n];
  end;
  if not anyKw then Exit;

  for i := 0 to MAX_PROC_PARAMS - 1 do slot[i] := -1;
  pos := 0; maxIdx := -1; sawKw := False;
  n := argsHead;
  while n >= 0 do
  begin
    if ASTIVal[n] <> 0 then
    begin
      k := ASTIVal[n] - 1;
      ASTIVal[n] := 0;
      sawKw := True;
    end
    else
    begin
      if sawKw then
        Error('Nil Python: positional argument after keyword argument in call to '
              + Procs[mpi].Name);
      k := pos;
      Inc(pos);
    end;
    if (k < 0) or (k >= MAX_PROC_PARAMS) then
      Error('Nil Python: too many arguments to ' + Procs[mpi].Name);
    if slot[k] >= 0 then
      Error('Nil Python: ' + Procs[mpi].Name + ' got multiple values for parameter '''
            + Procs[mpi].Params[k].Name + '''');
    slot[k] := n;
    if k > maxIdx then maxIdx := k;
    n := ASTRight[n];
  end;

  { Trailing defaulted params too, not only the holes below maxIdx: a keyword
    call decouples arity from position, so the loops that normally stop at `)`
    and hand the tail to FillDefaultArgs have already been broken out of. }
  i := maxIdx + 1;
  while (i <= Procs[mpi].ParamCount - 1) and (i < MAX_PROC_PARAMS) and
        ProcParamHasDefault[mpi * MAX_PROC_PARAMS + i] do
  begin
    slot[i] := -1;
    maxIdx := i;
    Inc(i);
  end;

  for i := 0 to maxIdx do
    if slot[i] < 0 then
    begin
      k := AllocNode(AN_ARG);
      ASTLeft[k] := DefaultArgValueNode(mpi, i);
      slot[i] := k;
    end;

  for i := 0 to maxIdx - 1 do ASTRight[slot[i]] := slot[i + 1];
  ASTRight[slot[maxIdx]] := -1;
  argsHead := slot[0];
  lastArg := slot[maxIdx];
  nArgs := maxIdx + 1;
end;

function PyMakeStrIndex(baseNode, idxNode: Integer): Integer;
var procIdx, callNode, a0, a1: Integer;
begin
  procIdx := FindProc('pystr_at');
  if procIdx < 0 then Error('Nil Python: pylib (pystr_at) not loaded');
  a0 := AllocNode(AN_ARG);
  ASTLeft[a0] := baseNode;
  a1 := AllocNode(AN_ARG);
  ASTLeft[a1] := idxNode;
  ASTRight[a0] := a1;
  callNode := AllocNode(AN_CALL);
  ASTIVal[callNode] := procIdx;
  ASTTk[callNode] := Ord(tyChar);
  ASTLeft[callNode] := a0;
  Result := callNode;
end;

function PyParseStrMethod(baseNode: Integer; const mname: AnsiString): Integer;
var pname: AnsiString;
    retTk: TTypeKind;
    procIdx, callNode, argNode, lastArg, i, k, wantArgs: Integer;
begin
  if not PyStrMethodInfo(mname, pname, retTk, wantArgs) then
    Error('Nil Python: unsupported str method .' + mname + '() (have: upper, '
      + 'lower, strip, lstrip, rstrip, startswith, endswith, find, isspace, '
      + 'isdigit, isalpha, isalnum, isupper, islower, format, '
      + 'join, split, splitlines, replace, count, rfind, title, capitalize, '
      + 'swapcase, casefold, ljust, rjust, center, zfill, removeprefix, '
      + 'removesuffix)');

  procIdx := FindProc(pname);
  if procIdx < 0 then Error('Nil Python: pylib (' + pname + ') not loaded');

  { A tyChar receiver becomes a real 1-length string first — see pystr_ofchar. }
  if IntToTypeKind(ASTTk[baseNode]) = tyChar then
  begin
    i := FindProc('pystr_ofchar');
    if i < 0 then Error('Nil Python: pylib (pystr_ofchar) not loaded');
    callNode := AllocNode(AN_ARG);
    ASTLeft[callNode] := baseNode;
    baseNode := AllocNode(AN_CALL);
    ASTIVal[baseNode] := i;
    ASTTk[baseNode] := Ord(tyAnsiString);
    ASTLeft[baseNode] := callNode;
  end;

  { the string itself is argument 0 — the receiver }
  argNode := AllocNode(AN_ARG);
  ASTLeft[argNode] := baseNode;
  lastArg := argNode;

  Expect(tkLParen, '(');
  i := 0;
  if wantArgs = -4 then
  begin
    { SKIP the arguments rather than parse them: `errors="replace"` is a
      keyword argument, not an expression, so parsing it would fail on the
      bare name. Balanced skip to the closing paren. }
    k := 1;
    while (k > 0) and (CurTok.Kind <> tkEOF) do
    begin
      if CurTok.Kind = tkLParen then Inc(k)
      else if CurTok.Kind = tkRParen then
      begin
        Dec(k);
        if k = 0 then Break;
      end;
      Next;
    end;
  end;
  while (wantArgs <> -4) and (CurTok.Kind <> tkRParen) do
  begin
    { A bare generator expression as an argument — `"\n".join(x for x in it)`.
      Detected BEFORE the EXPR is parsed, because the EXPR references the loop
      variable, which is not in scope until the `for`. PyParseCompExprValue
      desugars it to a hoisted hidden list and yields that list, so join sees an
      ordinary iterable. }
    if PyBareGenExprAhead then
      CurASTNode := PyParseCompExprValue(False)
    else
      PyParseBoolExpr;
    callNode := AllocNode(AN_ARG);
    ASTLeft[callNode] := CurASTNode;
    ASTRight[lastArg] := callNode;
    lastArg := callNode;
    Inc(i);
    if CurTok.Kind = tkComma then Next
    else Break;
  end;
  Expect(tkRParen, ')');
  if wantArgs = -1 then
  begin
    { optional-argument form: split(), split(sep) and split(sep, maxsplit) are
      separate functions. }
    if i = 0 then pname := 'pystr_split_ws'
    else if i = 2 then pname := 'pystr_split_sep_max'
    else if i <> 1 then
      Error('Nil Python: str method .' + mname + '() takes at most two arguments');
    procIdx := FindProc(pname);
    if procIdx < 0 then Error('Nil Python: pylib (' + pname + ') not loaded');
  end
  else if wantArgs = -4 then
  begin
    { Arguments accepted and DISCARDED. Only .encode uses this: our strings are
      byte strings, so the encoding argument has nothing to select, and the
      `errors` keyword cannot trigger. Swallowing them keeps the corpus
      spelling working without pretending we implement codecs — the limitation
      is filed as bug-nilpy-encode-ignores-the-codec. }
    procIdx := FindProc(pname);
    if procIdx < 0 then Error('Nil Python: pylib (' + pname + ') not loaded');
  end
  else if wantArgs = -3 then
  begin
    { substring plus an OPTIONAL start offset — find }
    if i = 2 then pname := pname + '_from'
    else if i <> 1 then
      Error('Nil Python: str method .' + mname + '() takes one or two arguments');
    procIdx := FindProc(pname);
    if procIdx < 0 then Error('Nil Python: pylib (' + pname + ') not loaded');
  end
  else if wantArgs = -5 then
  begin
    { strip family: no arg (whitespace) or one CHARS-set arg }
    if i = 1 then pname := pname + '_chars'
    else if i <> 0 then
      Error('Nil Python: str method .' + mname + '() takes at most one argument');
    procIdx := FindProc(pname);
    if procIdx < 0 then Error('Nil Python: pylib (' + pname + ') not loaded');
  end
  else if wantArgs = -7 then
  begin
    { old + new, plus an OPTIONAL occurrence count — replace }
    if i = 3 then pname := pname + '_n'
    else if i <> 2 then
      Error('Nil Python: str method .' + mname + '() takes two or three arguments');
    procIdx := FindProc(pname);
    if procIdx < 0 then Error('Nil Python: pylib (' + pname + ') not loaded');
  end
  else if wantArgs = -2 then
  begin
    { width plus an OPTIONAL fill character — rjust }
    if i = 2 then pname := pname + '_c'
    else if i <> 1 then
      Error('Nil Python: str method .' + mname + '() takes one or two arguments');
    procIdx := FindProc(pname);
    if procIdx < 0 then Error('Nil Python: pylib (' + pname + ') not loaded');
  end
  else if wantArgs = -6 then
  begin
    { .format(a) / .format(a, b) — pylib overloads by arity, so the call just
      has to pass the arguments through }
    { ONE argument. The two-argument overload is written and does not marshal
      correctly (the second Variant arrives wrong and the call segfaults), so
      it is refused rather than shipped: a crash is worse than a diagnostic.
      feature-nilpy-str-format-multiarg. }
    if i <> 1 then
      Error('Nil Python: str method .format() takes exactly one argument here; '
            + 'several placeholders are not implemented yet — use an f-string');
    procIdx := FindProc(pname);
    if procIdx < 0 then Error('Nil Python: pylib (' + pname + ') not loaded');
  end
  else if i <> wantArgs then
  begin
    if wantArgs = 0 then
      Error('Nil Python: str method .' + mname + '() takes no arguments')
    else
      Error('Nil Python: str method .' + mname + '() takes exactly one argument');
  end;

  callNode := AllocNode(AN_CALL);
  ASTIVal[callNode] := procIdx;
  ASTTk[callNode] := Ord(retTk);
  ASTLeft[callNode] := argNode;
  LastExprTk := retTk;
  Result := callNode;
end;

{ A `[` may follow a non-lvalue factor when the value is subscriptable in
  Python: a str (including a literal), a list, or a dict. ParseFactor asks
  before consuming the bracket so nothing else's syntax is stolen. }
function PySubscriptableSuffix(n: Integer): Boolean;
var rec, listCi, dictCi: Integer;
begin
  Result := False;
  if n < 0 then Exit;
  if PyIsStrBaseTk(IntToTypeKind(ASTTk[n])) then begin Result := True; Exit; end;
  { a variant may hold a container — subscript dispatches at run time }
  if IntToTypeKind(ASTTk[n]) = tyVariant then begin Result := True; Exit; end;
  if IntToTypeKind(ASTTk[n]) <> tyClass then Exit;
  rec := ResolveNodeRec(n);
  if rec < REC_UCLASS_BASE then Exit;
  listCi := FindUClass('TPyList');
  dictCi := FindUClass('TPyDict');
  Result := ((listCi >= 0) and (rec = REC_UCLASS_BASE + listCi)) or
            ((dictCi >= 0) and (rec = REC_UCLASS_BASE + dictCi));
end;

{ `base[idx]` for those bases: pystr_at for a string, the container's own getter
  for a list (`get`) or a dict (`fetch`) — the same methods the lvalue path
  reaches, just built here because a non-lvalue never gets there. }
{ `v[key]` on a variant -> pyvar_getitem(v, key); yields a variant.
  (PyMakeNone's forward declaration lives in parser.inc's Py* forward block —
  parser.inc's PyExprMode nil arm and PyParseBoolExpr both need it.) }

{ A `lambda p1, ...: <expr>` — lowered to a PYEVAL CLOSURE built from the
  body's SOURCE text: pyclosure_src_new(params, 'return <expr>') with every
  free name's VALUE captured at build time via chained pyclosure_src_cap
  calls. The result is the same magic-sentinel closure object the reverse
  bridge (`word.native(vm2)` and PyMakeDynCall) already dispatches on, so a
  lambda stored into a Callable field runs exactly like a captured nested
  `def` (uforth: `define_word("STATE", native=lambda vm: vm.push(A))`).
  The body is re-tokenized by pyeval at build time, so the text below is a
  space-joined reconstruction from the token span — exotic tokens error
  honestly rather than desugaring wrong. }

{ Text of one body token for that reconstruction. }
function PyLambdaTokText(i: Integer): AnsiString;
begin
  case Tokens[i].Kind of
    tkIdent:   Result := GetTokenStr(i);
    tkInteger: Result := PyIntLiteralText(Tokens[i].IVal);
    tkString:  Result := '"' + GetTokenStr(i) + '"';
    tkDot:     Result := '.';
    tkComma:   Result := ',';
    tkLParen:  Result := '(';
    tkRParen:  Result := ')';
    tkLBrack:  Result := '[';
    tkRBrack:  Result := ']';
    tkColon:   Result := ':';
    tkPlus:    Result := '+';
    tkMinus:   Result := '-';
    tkStar:    Result := '*';
    tkSlash:   Result := '/';
    tkDiv:     Result := '//';
    tkMod:     Result := '%';
    tkAmp:     Result := '&';
    tkPipe:    Result := '|';
    tkXor:     Result := '^';
    tkShl:     Result := '<<';
    tkShr:     Result := '>>';
    tkLogNot:  Result := '~';
    tkEq:      Result := '==';
    tkNeq:     Result := '!=';
    tkLt:      Result := '<';
    tkLe:      Result := '<=';
    tkGt:      Result := '>';
    tkGe:      Result := '>=';
    tkAnd:     Result := 'and';
    tkOr:      Result := 'or';
    tkNot:     Result := 'not';
    tkIn:      Result := 'in';
    tkIf:      Result := 'if';
    tkElse:    Result := 'else';
    tkNil:     Result := 'None';
    tkTrue:    Result := 'True';
    tkFalse:   Result := 'False';
    { statement-level tokens, for whole nested-def bodies (DOES> closures) }
    tkAssign:  Result := '=';
    tkExit:    Result := 'return';
    tkWhile:   Result := 'while';
    tkBreak:   Result := 'break';
    tkRaise:   Result := 'raise';
    tkwriteln: Result := 'print';
    tkPlusEq:  Result := '+=';
    tkMinusEq: Result := '-=';
    tkStarEq:  Result := '*=';
    tkSlashEq: Result := '//=';
    tkTrueDivEq: Result := '/=';
    tkModEq:   Result := '%=';
    tkAmpEq:   Result := '&=';
    tkPipeEq:  Result := '|=';
    tkXorEq:   Result := '^=';
  else
    Error('Nil Python: this token is not supported in a lambda/closure body yet');
    Result := '';
  end;
end;

{ Is this lambda body a CALL whose value is discarded — `self.canvas.configure(
  ...)`, `print(x)`, `handler(a, b)`? That is the GUI-callback shape, and it is
  the only shape the lifted path takes today: the bound-fn bridge
  (pyboundfn_call_ptr) DISCARDS the callee's result, so a lambda whose value a
  caller reads (`key=lambda p: p[1]`) must keep the pyeval closure, which
  returns one. Refusing loudly here beats lifting a body whose value silently
  disappears. }
function PyLambdaBodyIsDiscardableCall(bStart, bEnd: Integer): Boolean;
var i, depth: Integer; sawCall: Boolean;
begin
  Result := False;
  if bEnd - bStart < 3 then Exit;
  if Tokens[bStart].Kind <> tkIdent then Exit;
  if Tokens[bEnd - 1].Kind <> tkRParen then Exit;
  depth := 0;
  sawCall := False;
  for i := bStart to bEnd - 1 do
  begin
    if Tokens[i].Kind in [tkLParen, tkLBrack, tkBegin] then
    begin
      if (depth = 0) and (Tokens[i].Kind = tkLParen) and (i > bStart) then sawCall := True;
      Inc(depth);
    end
    else if Tokens[i].Kind in [tkRParen, tkRBrack, tkEnd] then Dec(depth)
    else if depth = 0 then
    begin
      { at depth 0 only the callee chain may appear: `a.b.c(` }
      if not (Tokens[i].Kind in [tkIdent, tkDot]) then Exit;
    end;
  end;
  Result := sawCall and (depth = 0);
end;

procedure PyParseLambdaStub;
var depth, bStart, bEnd, i, j, pi, capPi, symIdx: Integer;
    params, src, nm: AnsiString;
    pNames: array[0..7] of AnsiString;
    nParams: Integer;
    node, argA, argB, capNode: Integer;
    dup: Boolean;
    { `lambda *args, key=key, var=var:` — a DEFAULTED parameter is Python's
      idiom for capturing a loop variable by value, not a parameter the caller
      ever supplies. Held here and bound as a build-time capture, exactly as the
      nested-def path already binds its default-arg expressions. }
    dcNames: array[0..7] of AnsiString;
    dcSyms: array[0..7] of Integer;
    dcCount: Integer;
    { the LIFTED path: this lambda's own proc and the values bound into it }
    lamProc, lamN, bindIdx, argC, vNode, capSym: Integer;
    lamCallee, k: Integer; cn2: AnsiString;
    lamNames: array[0..MAX_PROC_PARAMS-1] of AnsiString;
    lamTypes: array[0..MAX_PROC_PARAMS-1] of TTypeKind;
    lamSyms: array[0..MAX_PROC_PARAMS-1] of Integer;
    lamRecs: array[0..MAX_PROC_PARAMS-1] of Integer;
    newPi, bindPi, varBindPi: Integer;
begin
  Next;                                { consume `lambda` }
  params := '';
  nParams := 0;
  dcCount := 0;
  while (CurTok.Kind <> tkColon) and (CurTok.Kind <> tkEOF) do
  begin
    if CurTok.Kind = tkIdent then
    begin
      if (TokPos < TokCount) and (Tokens[TokPos].Kind = tkAssign) then
      begin
        { `name=<value>` — a CAPTURE, not a parameter. Only a bare name is
          supported as the value (which is the whole idiom: `key=key`); anything
          richer says so rather than binding the wrong thing. }
        if dcCount > High(dcNames) then Error('Nil Python: too many lambda default captures');
        dcNames[dcCount] := CurTok.SVal;
        Next; Next;                    { the name and the '=' }
        if CurTok.Kind <> tkIdent then
          Error('Nil Python: a lambda default capture must be a plain name (key=key)');
        symIdx := PyProgSym(CurTok.SVal);
        if symIdx < 0 then
          Error('Nil Python: lambda default capture ' + dcNames[dcCount] + ' names nothing');
        dcSyms[dcCount] := symIdx;
        Inc(dcCount);
        Next;                          { the value name }
        Continue;
      end;
      if nParams > High(pNames) then Error('Nil Python: too many lambda parameters');
      pNames[nParams] := LowerCase(CurTok.SVal);
      Inc(nParams);
      if params <> '' then params := params + ',';
      params := params + CurTok.SVal;
    end;
    Next;
  end;
  Expect(tkColon, ':');
  { the body expression's token span, balanced to a depth-0 ',' ')' or line end }
  bStart := TokPos - 1;
  depth := 0;
  while CurTok.Kind <> tkEOF do
  begin
    if CurTok.Kind in [tkLParen, tkLBrack, tkBegin] then Inc(depth)
    else if CurTok.Kind in [tkRParen, tkRBrack, tkEnd] then
    begin
      if depth = 0 then Break;
      Dec(depth);
    end
    else if (depth = 0) and (CurTok.Kind in [tkComma, tkNewline, tkDedent]) then Break;
    Next;
  end;
  bEnd := TokPos - 1;

  { ---- LIFT: compile the lambda as a real proc when its shape allows ----
    A lambda is a nested def with one expression body, so the machinery that
    already lifts a captures-only nested def (pyboundfn_new / _bind_var, and the
    pending-body queue) serves it unchanged. Lifting means the body is COMPILED:
    keyword arguments bind by name against the real signature, method calls go
    through the ordinary call path, and there is no interpreter in the callback.
    Everything the lifter does not accept keeps the pyeval closure below — that
    fallback is the reason this can be narrow.
    (feature-nilpy-lambda-compiled-closure) }
  newPi := FindProc('pyboundfn_new');
  bindPi := FindProc('pyboundfn_bind');
  varBindPi := FindProc('pyboundfn_bind_var');
  if (not PyTypingPass) and (nParams <= 1) and (newPi >= 0) and (bindPi >= 0) and
     (varBindPi >= 0) and PyLambdaBodyIsDiscardableCall(bStart, bEnd) then
  begin
    lamN := 0;
    { A ZERO-parameter lambda is lifted too, under a DUMMY own parameter nothing
      references. The bound-fn bridge always passes one argument, so a proc with
      no parameter at all would be called with an extra register argument and a
      shifted capture list; a name no Python source can spell absorbs it. Without
      the lift, `root.after(300, lambda: draw())` fell to the pyeval closure,
      which cannot call a COMPILED def — "pyeval: unknown call: draw()", and the
      Tk event loop never came back (bug-nilpy-zero-param-lambda-cannot-call-a-def). }
    if nParams = 1 then lamNames[0] := pNames[0]   { the one own parameter, unannotated }
    else lamNames[0] := '$lamarg0';
    lamTypes[0] := tyVariant;
    lamSyms[0] := -1;
    lamRecs[0] := REC_NONE;
    lamN := 1;
    { the `key=key` defaults first: Python's own idiom for pinning a value }
    for i := 0 to dcCount - 1 do
    begin
      if lamN >= PY_MAX_CAPS then Break;
      lamNames[lamN] := LowerCase(dcNames[i]);
      lamTypes[lamN] := Syms[dcSyms[i]].TypeKind;
      lamSyms[lamN] := dcSyms[i];
      lamRecs[lamN] := Syms[dcSyms[i]].RecName;
      Inc(lamN);
    end;
    { then every free name in the body that is an enclosing LOCAL or PARAM —
      `self` above all. A global needs no capture: the lifted proc is top level
      and sees it directly. }
    for i := bStart to bEnd - 1 do
      if (Tokens[i].Kind = tkIdent) and
         ((i = bStart) or (Tokens[i - 1].Kind <> tkDot)) then
      begin
        nm := LowerCase(GetTokenStr(i));
        dup := False;
        for j := 0 to lamN - 1 do
          if lamNames[j] = nm then dup := True;
        if dup then Continue;
        capSym := PyProgSym(GetTokenStr(i));
        if capSym < 0 then
        begin
          { TRANSITIVE capture, the same rule a nested def already follows: the
            name is a sibling NESTED DEF, and calling it forwards ITS captures —
            which this lambda must therefore hold too. songformatter's redraw is
            exactly this: `cv.after(120, lambda: draw(cv.winfo_width()))`, where
            `draw` captures `self`; the lambda never mentions self, so without
            this the call reported "captures self, which is not in scope". }
          lamCallee := FindProc(PyQualifyNested(GetTokenStr(i)));
          if (lamCallee >= 0) and (PyCapCount[lamCallee] > 0) then
            for k := 0 to PyCapCount[lamCallee] - 1 do
            begin
              cn2 := PyCapName[lamCallee * PY_MAX_CAPS + k];
              dup := False;
              for j := 0 to lamN - 1 do
                if lamNames[j] = LowerCase(cn2) then dup := True;
              if dup then Continue;
              capSym := PyProgSym(cn2);
              if capSym < 0 then Continue;
              if not (Syms[capSym].Kind in [skLocal, skParam]) then Continue;
              if Syms[capSym].IsArray or (Syms[capSym].TypeKind = tyRecord) then Continue;
              { A managed STRING is skipped by the direct scan above (a bound
                slot holds an Int64, and a borrowed handle there would outlive
                its owner). It cannot be skipped HERE: this capture is not for
                the lambda's own use, it is an ARGUMENT the callee's call site
                must supply, and leaving it out makes that call fail with
                "captures <name>, which is not in scope at this call" — which
                is what stopped songformatter's redraw. }
              if lamN >= PY_MAX_CAPS then Break;
              lamNames[lamN] := LowerCase(cn2);
              lamTypes[lamN] := Syms[capSym].TypeKind;
              lamSyms[lamN] := capSym;
              lamRecs[lamN] := Syms[capSym].RecName;
              Inc(lamN);
            end;
          Continue;
        end;
        if not (Syms[capSym].Kind in [skLocal, skParam]) then Continue;
        if Syms[capSym].IsArray or (Syms[capSym].TypeKind = tyRecord) then Continue;
        if (Syms[capSym].TypeKind = tyAnsiString) or (Syms[capSym].TypeKind = tyString) then Continue;
        if lamN >= PY_MAX_CAPS then Break;
        lamNames[lamN] := nm;
        lamTypes[lamN] := Syms[capSym].TypeKind;
        lamSyms[lamN] := capSym;
        lamRecs[lamN] := Syms[capSym].RecName;
        Inc(lamN);
      end;

    { PXXDBG=n.caps — the lambda's lifted parameter list (own arg first, then
      every captured/forwarded name). The capture set is what a forwarded
      sibling call needs, so when a call reports "captures X, which is not in
      scope", this is the list to look at first. }
    if PxxDbgEnabled('n.caps') then
    begin
      Write('PXXDBG n.caps lambda@', bStart, ' nest=', PyNestPrefix, ' params=');
      for j := 0 to lamN - 1 do Write(lamNames[j], ' ');
      WriteLn;
    end;

    if PyPendLamCount < PY_MAX_NESTED then
    begin
      Inc(PyLamSeq);
      { A FUNCTION returning a variant — the ABI every bridge that invokes a
        lifted lambda declares (see PyCompileLambdaBody). Nobody reads the value;
        what matters is that the callee obeys the result convention its callers
        assume. As a procedure it did not, and the caller dereferenced a stale
        result register. }
      lamProc := RegisterProc('$pylam' + AIntToStr(PyLamSeq), True, tyVariant,
                              lamN, lamNames, lamTypes);
      Procs[lamProc].BodyAddr := -1;
      for j := 1 to lamN - 1 do
        if (lamTypes[j] = tyClass) and (lamRecs[j] >= REC_UCLASS_BASE) and
           (j < MAX_PROC_PARAMS) then
          ProcParamRecId[lamProc * MAX_PROC_PARAMS + j] := lamRecs[j];
      PyPendLamTok[PyPendLamCount] := bStart;
      PyPendLamProc[PyPendLamCount] := lamProc;
      PyPendLamWrapReal[PyPendLamCount] := -1;   { not a callable-value wrapper }
      Inc(PyPendLamCount);

      { pyboundfn_new(addr, nBound, a0var=1) — the own param is a variant and
        travels by ADDRESS, exactly as the nested-def path passes its own }
      argA := AllocNode(AN_ARG);
      node := AllocNode(AN_PROCADDR);
      ASTIVal[node] := lamProc; ASTTk[node] := Ord(tyPointer);
      ASTLeft[argA] := node;
      argB := AllocNode(AN_ARG);
      node := AllocNode(AN_INT_LIT);
      ASTIVal[node] := lamN - 1; ASTTk[node] := Ord(tyInt64);
      ASTLeft[argB] := node;
      ASTRight[argA] := argB;
      argC := AllocNode(AN_ARG);
      node := AllocNode(AN_INT_LIT);
      ASTIVal[node] := 1; ASTTk[node] := Ord(tyInt64);
      ASTLeft[argC] := node;
      ASTRight[argB] := argC;
      node := AllocNode(AN_CALL);
      ASTIVal[node] := newPi; ASTLeft[node] := argA; ASTTk[node] := Ord(tyPointer);

      { bind each captured value, in parameter order }
      for j := 1 to lamN - 1 do
      begin
        bindIdx := j - 1;
        argA := AllocNode(AN_ARG);
        ASTLeft[argA] := node;
        argB := AllocNode(AN_ARG);
        vNode := AllocNode(AN_INT_LIT);
        ASTIVal[vNode] := bindIdx; ASTTk[vNode] := Ord(tyInt64);
        ASTLeft[argB] := vNode;
        ASTRight[argA] := argB;
        argC := AllocNode(AN_ARG);
        ASTLeft[argC] := PyMakeIdent(lamSyms[j]);
        ASTRight[argB] := argC;
        node := AllocNode(AN_CALL);
        if lamTypes[j] = tyVariant then ASTIVal[node] := varBindPi
        else ASTIVal[node] := bindPi;
        ASTLeft[node] := argA; ASTTk[node] := Ord(tyPointer);
      end;

      CurASTNode := node;
      LastExprTk := tyPointer;
      Exit;
    end;
  end;

  pi := FindProc('pyclosure_src_new');
  capPi := FindProc('pyclosure_src_cap');
  if (pi < 0) or (capPi < 0) then
  begin
    { pyeval not loaded: keep the old degrade-to-None behaviour }
    CurASTNode := PyMakeNone;
    LastExprTk := tyVariant;
    Exit;
  end;

  src := 'return';
  for i := bStart to bEnd - 1 do
    src := src + ' ' + PyLambdaTokText(i);

  { pyclosure_src_new(params, src) }
  argA := AllocNode(AN_ARG);
  argB := AllocNode(AN_STR_LIT);
  ASTSOffset[argB] := PyStoredName(params); ASTSLen[argB] := Length(params);
  ASTTk[argB] := Ord(tyString);
  ASTLeft[argA] := argB;
  argB := AllocNode(AN_ARG);
  node := AllocNode(AN_STR_LIT);
  ASTSOffset[node] := PyStoredName(src); ASTSLen[node] := Length(src);
  ASTTk[node] := Ord(tyString);
  ASTLeft[argB] := node;
  ASTRight[argA] := argB;
  node := AllocNode(AN_CALL);
  ASTIVal[node] := pi; ASTLeft[node] := argA; ASTTk[node] := Ord(tyPointer);

  { capture each free name that resolves to a value symbol: chained
    pyclosure_src_cap(obj, 'name', name). Idents after a '.' are members;
    the lambda's own params bind at invoke time. }
  for i := bStart to bEnd - 1 do
    if (Tokens[i].Kind = tkIdent) and
       ((i = bStart) or (Tokens[i - 1].Kind <> tkDot)) then
    begin
      nm := LowerCase(GetTokenStr(i));
      dup := False;
      for j := 0 to nParams - 1 do
        if pNames[j] = nm then dup := True;
      { a name captured once is enough (values, not references) }
      for j := bStart to i - 1 do
        if (Tokens[j].Kind = tkIdent) and (LowerCase(GetTokenStr(j)) = nm) and
           ((j = bStart) or (Tokens[j - 1].Kind <> tkDot)) then dup := True;
      if dup then Continue;
      symIdx := PyProgSym(GetTokenStr(i));
      if symIdx < 0 then Continue;
      if not (Syms[symIdx].Kind in [skGlobal, skLocal, skParam]) then Continue;
      if Syms[symIdx].IsArray or (Syms[symIdx].TypeKind = tyRecord) then Continue;
      argA := AllocNode(AN_ARG);
      ASTLeft[argA] := node;                       { the closure obj so far }
      argB := AllocNode(AN_ARG);
      capNode := AllocNode(AN_STR_LIT);
      ASTSOffset[capNode] := PyStoredName(GetTokenStr(i));
      ASTSLen[capNode] := Length(GetTokenStr(i));
      ASTTk[capNode] := Ord(tyString);
      ASTLeft[argB] := capNode;
      ASTRight[argA] := argB;
      capNode := AllocNode(AN_ARG);
      ASTLeft[capNode] := PyMakeIdent(symIdx);
      ASTRight[argB] := capNode;
      node := AllocNode(AN_CALL);
      ASTIVal[node] := capPi; ASTLeft[node] := argA; ASTTk[node] := Ord(tyPointer);
    end;

  { the defaulted params, bound under the PARAMETER's name }
  for i := 0 to dcCount - 1 do
  begin
    argA := AllocNode(AN_ARG);
    ASTLeft[argA] := node;
    argB := AllocNode(AN_ARG);
    capNode := AllocNode(AN_STR_LIT);
    ASTSOffset[capNode] := PyStoredName(dcNames[i]);
    ASTSLen[capNode] := Length(dcNames[i]);
    ASTTk[capNode] := Ord(tyString);
    ASTLeft[argB] := capNode;
    ASTRight[argA] := argB;
    capNode := AllocNode(AN_ARG);
    ASTLeft[capNode] := PyMakeIdent(dcSyms[i]);
    ASTRight[argB] := capNode;
    node := AllocNode(AN_CALL);
    ASTIVal[node] := capPi; ASTLeft[node] := argA; ASTTk[node] := Ord(tyPointer);
  end;

  CurASTNode := node;
  LastExprTk := tyPointer;
end;

{ A NESTED def taken AS A VALUE whose meaning depends on values live RIGHT NOW —
  default-arg expressions (`def does_runtime(vm2, _addr=data_addr): ...`, the
  uforth DOES> idiom: defaults bind per-invocation of the enclosing word) or
  scanned captures. A plain proc ADDRESS loses those bindings, so build a pyeval
  closure instead: pyclosure_src_new(<non-default params>, <body source>) with
  each defaulted param and each captured enclosing name bound as a build-time
  value cap. Returns the AST node, or -1 when the plain address is still right
  (no defaults, no captures — the fast path stays untouched). }
{ Bound-compiled-fn VALUE for a captures-only nested def: pyboundfn_new(addr,
  n) then chained pyboundfn_bind(obj, i, <capture value>) — each capture
  resolved HERE, the same actual a direct call site would append. Returns -1
  when a capture cannot travel as a register word (variant/unresolved), so the
  caller falls back to the plain address. }
function PyMakeBoundFnValue(procIdx: Integer): Integer;
var j, symIdx, node, argA, argB, argC, pi, bindPi, varBindPi, vNode: Integer;
    nm: AnsiString;
begin
  Result := -1;
  pi := FindProc('pyboundfn_new');
  bindPi := FindProc('pyboundfn_bind');
  varBindPi := FindProc('pyboundfn_bind_var');
  if (pi < 0) or (bindPi < 0) or (varBindPi < 0) then Exit;
  if PyCapCount[procIdx] > 12 then Exit;
  for j := 0 to PyCapCount[procIdx] - 1 do
  begin
    nm := PyCapName[procIdx * PY_MAX_CAPS + j];
    symIdx := PyProgSym(nm);
    if symIdx < 0 then Exit;
    if not (Syms[symIdx].Kind in [skGlobal, skLocal, skParam]) then Exit;
    { a MANAGED capture stored as a raw word would dangle when the enclosing
      scope releases it — refuse, fall back to the plain address. Variants are
      fine: they bind through a heap COPY (pyboundfn_bind_var). }
    if (Syms[symIdx].TypeKind = tyAnsiString) or (Syms[symIdx].TypeKind = tyString) then Exit;
    if Syms[symIdx].IsArray or (Syms[symIdx].TypeKind = tyRecord) then Exit;
  end;

  argA := AllocNode(AN_ARG);
  node := AllocNode(AN_PROCADDR);
  ASTIVal[node] := procIdx; ASTTk[node] := Ord(tyPointer);
  ASTLeft[argA] := node;
  argB := AllocNode(AN_ARG);
  node := AllocNode(AN_INT_LIT);
  ASTIVal[node] := PyCapCount[procIdx]; ASTTk[node] := Ord(tyInt64);
  ASTLeft[argB] := node;
  ASTRight[argA] := argB;
  node := AllocNode(AN_CALL);
  ASTIVal[node] := pi; ASTLeft[node] := argA; ASTTk[node] := Ord(tyPointer);

  for j := 0 to PyCapCount[procIdx] - 1 do
  begin
    nm := PyCapName[procIdx * PY_MAX_CAPS + j];
    symIdx := PyProgSym(nm);
    argA := AllocNode(AN_ARG);
    ASTLeft[argA] := node;
    argB := AllocNode(AN_ARG);
    vNode := AllocNode(AN_INT_LIT);
    ASTIVal[vNode] := j; ASTTk[vNode] := Ord(tyInt64);
    ASTLeft[argB] := vNode;
    ASTRight[argA] := argB;
    argC := AllocNode(AN_ARG);
    ASTLeft[argC] := PyMakeIdent(symIdx);
    ASTRight[argB] := argC;
    node := AllocNode(AN_CALL);
    if Syms[symIdx].TypeKind = tyVariant then
      ASTIVal[node] := varBindPi
    else
      ASTIVal[node] := bindPi;
    ASTLeft[node] := argA; ASTTk[node] := Ord(tyPointer);
  end;
  Result := node;
end;

procedure PyWarnUnbindableClosure(procIdx: Integer; const why: AnsiString);
{ A nested def taken AS A VALUE whose captures cannot be bound falls back to
  the bare code address — and the compiled body then reads its lifted capture
  parameters out of whatever the registers happen to hold. That fallback is a
  silently wrong program, so it says so. A warning and not an error because the
  shape is legal Python and the value may never actually be called; the
  diagnostic is what turns a plausible number into something greppable. }
begin
  if PyCapCount[procIdx] <= 0 then Exit;   { nothing to bind: the address IS the value }
  WarnAt(CurTok.Line,
         'Nil Python: the nested def ' + Procs[procIdx].Name +
         ' captures enclosing names but cannot carry them as a value because ' +
         why + ' — calling it after the enclosing call returns will read garbage');
end;

function PyNestedDefClosureValue(procIdx: Integer): Integer;
var defTok, i, j, k, depth: Integer;
    pNames: array[0..15] of AnsiString;
    pDefS, pDefE: array[0..15] of Integer;
    nP, nDef, nOwn, bindIdx, savedTok, ownPi: Integer;
    node, argA, argB, argC, vNode, newPi, bindPi, varBindPi, symIdx: Integer;
    objBindPi: Integer;
    nm: AnsiString;
    anyBind: Boolean;

  { Which parameter of the lifted body does bound value `bi` land in? The
    captures were appended AFTER the def's own parameters, so it is own-count +
    bi. This used to be spelled `bindIdx + 1` inline at both call sites — the
    same "exactly one own argument" assumption the call bridge made, and it
    misread the type of a NEIGHBOURING parameter once the arity was not 1,
    binding an integer capture as a variant address
    (bug-nilpy-escaping-closure-captures-unbound-unless-arity-is-one). Named so
    the two sites cannot drift apart again. }
  function BoundParamIsVariant(bi: Integer): Boolean;
  var pidx: Integer;
  begin
    pidx := nOwn + bi;
    BoundParamIsVariant := (pidx < Procs[procIdx].ParamCount) and
                           (Procs[procIdx].Params[pidx].TypeKind = tyVariant);
  end;

  { chain one pyboundfn_bind / _bind_var / _bind_obj call:
    node := bind(node, idx, valNode) }
  procedure ChainBind(valNode: Integer; isVar: Boolean; isObj: Boolean);
  begin
    argA := AllocNode(AN_ARG);
    ASTLeft[argA] := node;
    argB := AllocNode(AN_ARG);
    vNode := AllocNode(AN_INT_LIT);
    ASTIVal[vNode] := bindIdx; ASTTk[vNode] := Ord(tyInt64);
    ASTLeft[argB] := vNode;
    ASTRight[argA] := argB;
    argC := AllocNode(AN_ARG);
    ASTLeft[argC] := valNode;
    ASTRight[argB] := argC;
    node := AllocNode(AN_CALL);
    if isObj and (objBindPi >= 0) then ASTIVal[node] := objBindPi
    else if isVar then ASTIVal[node] := varBindPi
    else ASTIVal[node] := bindPi;
    ASTLeft[node] := argA; ASTTk[node] := Ord(tyPointer);
    Inc(bindIdx);
  end;

begin
  { A nested def taken AS A VALUE whose meaning depends on values live NOW —
    default-arg expressions (uforth's DOES>/DEFER: the defaults bind
    per-invocation values) or scanned captures (uforth's MARKER restore).
    Lowered to a BOUND COMPILED FUNCTION: pyboundfn_new(addr, n) with each
    defaulted param's expression and each capture VALUE bound in parameter
    order; the call bridge then invokes the COMPILED body natively as
    code(arg, defaults..., caps...). -1 = nothing to bind (plain address) or
    an unbindable shape (fall back to the plain address). }
  Result := -1;
  if (procIdx < 0) or (PyDefTokOf[procIdx] = 0) then Exit;
  defTok := PyDefTokOf[procIdx] - 1;
  newPi := FindProc('pyboundfn_new');
  bindPi := FindProc('pyboundfn_bind');
  varBindPi := FindProc('pyboundfn_bind_var');
  objBindPi := FindProc('pyboundfn_bind_obj');
  if (newPi < 0) or (bindPi < 0) or (varBindPi < 0) then Exit;

  { scan the header straight off the tokens: def NAME ( params ) ... }
  i := defTok;
  if Tokens[i].Kind <> tkFunction then Exit;
  Inc(i);
  Inc(i);
  if Tokens[i].Kind <> tkLParen then Exit;
  Inc(i);
  nP := 0;
  depth := 1;
  while (i < TokCount) and (depth > 0) do
  begin
    if Tokens[i].Kind = tkLParen then Inc(depth)
    else if Tokens[i].Kind = tkRParen then
    begin
      Dec(depth);
      if depth = 0 then Break;
    end
    else if (depth = 1) and (Tokens[i].Kind = tkIdent) and
            ((Tokens[i - 1].Kind = tkLParen) or (Tokens[i - 1].Kind = tkComma)) then
    begin
      if nP > High(pNames) then Exit;
      pNames[nP] := GetTokenStr(i);
      pDefS[nP] := -1; pDefE[nP] := -1;
      Inc(nP);
    end
    else if (depth = 1) and (Tokens[i].Kind = tkAssign) and (nP > 0) then
    begin
      pDefS[nP - 1] := i + 1;
      j := i + 1; k := 0;
      while j < TokCount do
      begin
        if Tokens[j].Kind in [tkLParen, tkLBrack, tkBegin] then Inc(k)
        else if Tokens[j].Kind in [tkRParen, tkRBrack, tkEnd] then
        begin
          if k = 0 then Break;
          Dec(k);
        end
        else if (k = 0) and (Tokens[j].Kind = tkComma) then Break;
        Inc(j);
      end;
      pDefE[nP - 1] := j;
      i := j - 1;
    end;
    Inc(i);
  end;

  nDef := 0;
  nOwn := 0;
  for j := 0 to nP - 1 do
    if pDefS[j] >= 0 then Inc(nDef) else Inc(nOwn);
  anyBind := (nDef > 0) or (PyCapCount[procIdx] > 0);
  { An UNANNOTATED single param compiled as a VARIANT also forces the bound-fn
    wrapper even with nothing to bind: the raw-address fallback lets the
    call bridge marshal per the FIELD's Callable annotation (vm: VM -> raw
    instance pointer) while the compiled body reads the slot as a variant —
    the pointer was reinterpreted as a variant tag and the first method call
    dispatched through garbage (uforth's `def w(vm):` native words, /STRING).
    The wrapper's A0Var route passes the argument boxed by address instead. }
  if not anyBind then
    if (nOwn <> 1) or (nDef > 0) or (Procs[procIdx].ParamCount < 1) or
       (Procs[procIdx].Params[0].TypeKind <> tyVariant) then Exit;
  { The bridge marshals up to THREE own arguments before the bound values, so
    every ordinary closure arity is representable. It used to assume exactly
    one and this read `if nOwn <> 1 then Exit` — and that Exit did not fall
    back to anything safe: it emitted the bare code address with NO captures
    bound, so `def b():` capturing an enclosing local read its captures out of
    the dead parent frame and printed an address
    (bug-nilpy-escaping-closure-captures-unbound-unless-arity-is-one).
    Past three, there is still no way to pass the arguments — WARN rather than
    silently produce that wrong value. }
  if nOwn > 3 then
  begin
    PyWarnUnbindableClosure(procIdx, 'it takes ' + PyIntLiteralText(nOwn) +
                            ' arguments and the call bridge marshals at most 3');
    Exit;
  end;
  if nDef + PyCapCount[procIdx] > 12 then
  begin
    PyWarnUnbindableClosure(procIdx, 'it has more than 12 values to bind');
    Exit;
  end;

  { every capture must resolve to a value symbol we can bind }
  for j := 0 to PyCapCount[procIdx] - 1 do
  begin
    nm := PyCapName[procIdx * PY_MAX_CAPS + j];
    symIdx := PyProgSym(nm);
    if symIdx < 0 then
    begin
      PyWarnUnbindableClosure(procIdx, 'it captures ' + nm + ', which does not resolve here');
      Exit;
    end;
    if not (Syms[symIdx].Kind in [skGlobal, skLocal, skParam]) then
    begin
      PyWarnUnbindableClosure(procIdx, 'it captures ' + nm + ', which is not a value');
      Exit;
    end;
    if (Syms[symIdx].TypeKind = tyAnsiString) or (Syms[symIdx].TypeKind = tyString) then
    begin
      PyWarnUnbindableClosure(procIdx, 'it captures the string ' + nm +
                              ', which cannot travel as a register word');
      Exit;
    end;
    if Syms[symIdx].IsArray or (Syms[symIdx].TypeKind = tyRecord) then
    begin
      PyWarnUnbindableClosure(procIdx, 'it captures ' + nm +
                              ', an array or record, which cannot travel as a register word');
      Exit;
    end;
  end;

  { pyboundfn_new(addr, n, a0var) — a0var says whether the own params are
    VARIANT (unannotated) and must travel by address }
  argA := AllocNode(AN_ARG);
  node := AllocNode(AN_PROCADDR);
  ASTIVal[node] := procIdx; ASTTk[node] := Ord(tyPointer);
  ASTLeft[argA] := node;
  argB := AllocNode(AN_ARG);
  node := AllocNode(AN_INT_LIT);
  ASTIVal[node] := nDef + PyCapCount[procIdx]; ASTTk[node] := Ord(tyInt64);
  ASTLeft[argB] := node;
  ASTRight[argA] := argB;
  argC := AllocNode(AN_ARG);
  node := AllocNode(AN_INT_LIT);
  { nOwn > 0 guard: with no own parameters, Params[0] is the first LIFTED
    CAPTURE, and testing its type would set the by-address flag off a value the
    caller never passes. }
  if (nOwn > 0) and (Procs[procIdx].ParamCount > 0) and
     (Procs[procIdx].Params[0].TypeKind = tyVariant) then
    ASTIVal[node] := 1
  else
    ASTIVal[node] := 0;
  ASTTk[node] := Ord(tyInt64);
  ASTLeft[argC] := node;
  ASTRight[argB] := argC;
  node := AllocNode(AN_CALL);
  ASTIVal[node] := newPi; ASTLeft[node] := argA; ASTTk[node] := Ord(tyPointer);

  { ...then say how many OWN parameters the body takes, so the bridge knows how
    many argument slots precede the captures. pyboundfn_new defaults it to 1 for
    the lambda lifter, which injects a dummy own parameter precisely because the
    bridge used to have no way to be told otherwise. }
  ownPi := FindProc('pyboundfn_setown');
  if ownPi >= 0 then
  begin
    argA := AllocNode(AN_ARG);
    ASTLeft[argA] := node;
    argB := AllocNode(AN_ARG);
    vNode := AllocNode(AN_INT_LIT);
    ASTIVal[vNode] := nOwn; ASTTk[vNode] := Ord(tyInt64);
    ASTLeft[argB] := vNode;
    ASTRight[argA] := argB;
    node := AllocNode(AN_CALL);
    ASTIVal[node] := ownPi; ASTLeft[node] := argA; ASTTk[node] := Ord(tyPointer);
  end;
  bindIdx := 0;

  { bind each DEFAULTED param: its default expression re-parsed HERE, in the
    scope where the def statement stands — Python's default-at-def-time rule }
  for j := 0 to nP - 1 do
    if pDefS[j] >= 0 then
    begin
      savedTok := TokPos - 1;
      TokPos := pDefS[j];
      Next;
      PyParseBoolExpr;
      k := CurASTNode;
      TokPos := savedTok;
      Next;
      { pass mode follows the CALLEE PARAM's type: a variant param reads an
        ADDRESS (bind_var heap-boxes the value), a concrete one a raw word }
      ChainBind(k, BoundParamIsVariant(bindIdx), False);
    end;

  { then each scanned CAPTURE, by current value }
  for j := 0 to PyCapCount[procIdx] - 1 do
  begin
    nm := PyCapName[procIdx * PY_MAX_CAPS + j];
    symIdx := PyProgSym(nm);
    { a CLASS capture binds through the retaining form: the enclosing scope
      releases its own reference on return, and the closure outlives it }
    ChainBind(PyMakeIdent(symIdx), BoundParamIsVariant(bindIdx),
              Syms[symIdx].TypeKind = tyClass);
  end;

  Result := node;
end;

{ The object as a POINTER for the dynamic-attribute store: a variant is unboxed
  through pyvarobj; a class instance already IS the object pointer. }
function PyMakeObjPtr(baseNode: Integer): Integer;
var procIdx, argNode: Integer;
begin
  if IntToTypeKind(ASTTk[baseNode]) <> tyVariant then begin Result := baseNode; Exit; end;
  procIdx := FindProc('pyvarobj');
  if procIdx < 0 then Error('Nil Python: pylib (pyvarobj) not loaded');
  argNode := AllocNode(AN_ARG); ASTLeft[argNode] := baseNode; ASTRight[argNode] := -1;
  Result := AllocNode(AN_CALL);
  ASTIVal[Result] := procIdx;
  ASTTk[Result] := Ord(tyPointer);
  ASTLeft[Result] := argNode;
end;

{ `obj.name` (dynamic attribute read) -> pydynattr_get(obj, "name") for a
  receiver STATICALLY known to be a class (obj is a genuine object pointer,
  or nil), else pydynattr_get_v(v, "name") for a VARIANT receiver — its
  runtime tag decides whether the payload is even an object pointer at all,
  and pydynattr_get(pyvarobj(v), ...)'s naive unwrap would ClassName garbage
  for a scalar (str/int/float/bool) variant on a miss. }
function PyMakeDynAttrGet(baseNode: Integer; const fname: AnsiString): Integer;
var procIdx, a0, a1, nameNode: Integer; isVariantRecv: Boolean;
begin
  isVariantRecv := IntToTypeKind(ASTTk[baseNode]) = tyVariant;
  if isVariantRecv then
    procIdx := FindProc('pydynattr_get_v')
  else
    procIdx := FindProc('pydynattr_get');
  if procIdx < 0 then Error('Nil Python: pylib (pydynattr_get/_v) not loaded');
  nameNode := AllocNode(AN_STR_LIT);
  ASTSOffset[nameNode] := PyStoredName(fname);
  ASTSLen[nameNode] := Length(fname);
  ASTTk[nameNode] := Ord(tyString);
  a0 := AllocNode(AN_ARG);
  if isVariantRecv then ASTLeft[a0] := baseNode
  else ASTLeft[a0] := PyMakeObjPtr(baseNode);
  a1 := AllocNode(AN_ARG); ASTLeft[a1] := nameNode;
  ASTRight[a0] := a1; ASTRight[a1] := -1;
  Result := AllocNode(AN_CALL);
  ASTIVal[Result] := procIdx;
  ASTTk[Result] := Ord(tyVariant);
  ASTLeft[Result] := a0;
end;

{ `obj.name = val` (dynamic attribute write) -> pydynattr_set(obj, "name", val). }
function PyMakeDynAttrSet(baseNode: Integer; const fname: AnsiString; valNode: Integer): Integer;
var procIdx, a0, a1, a2, nameNode: Integer;
begin
  procIdx := FindProc('pydynattr_set');
  if procIdx < 0 then Error('Nil Python: pylib (pydynattr_set) not loaded');
  nameNode := AllocNode(AN_STR_LIT);
  ASTSOffset[nameNode] := PyStoredName(fname);
  ASTSLen[nameNode] := Length(fname);
  ASTTk[nameNode] := Ord(tyString);
  a0 := AllocNode(AN_ARG); ASTLeft[a0] := PyMakeObjPtr(baseNode);
  a1 := AllocNode(AN_ARG); ASTLeft[a1] := nameNode;
  a2 := AllocNode(AN_ARG); ASTLeft[a2] := valNode;
  ASTRight[a0] := a1; ASTRight[a1] := a2; ASTRight[a2] := -1;
  Result := AllocNode(AN_CALL);
  ASTIVal[Result] := procIdx;
  ASTTk[Result] := Ord(tyUnknown);
  ASTLeft[Result] := a0;
end;

function PyMakeVariantGetItem(baseNode, idxNode: Integer): Integer;
var procIdx, a0, a1: Integer;
begin
  procIdx := FindProc('pyvar_getitem');
  if procIdx < 0 then Error('Nil Python: pylib (pyvar_getitem) not loaded');
  a0 := AllocNode(AN_ARG); ASTLeft[a0] := baseNode;
  a1 := AllocNode(AN_ARG); ASTLeft[a1] := idxNode;
  ASTRight[a0] := a1; ASTRight[a1] := -1;
  Result := AllocNode(AN_CALL);
  ASTIVal[Result] := procIdx;
  ASTTk[Result] := Ord(tyVariant);
  ASTLeft[Result] := a0;
end;

{ The READ half of a subscript augmented assignment: call the default indexed
  property's GETTER with the same self and index arguments the setter is about to
  use. `d[k] += v` needs the current element, and the setter path has already
  consumed the bracket group, so the arguments are re-used rather than re-parsed.
  (feature-nilpy-augmented-subscript-assign) }
{ A fresh AN_ARG chain over the SAME expression nodes. The read and the write
  of `d[k] += v` both need the index arguments, and sharing one chain linked the
  setter's value onto the reader's arguments — a cycle the compiler then walked
  forever. }
function PyCloneArgChain(head: Integer): Integer;
var n, prev, copy: Integer;
begin
  Result := -1;
  prev := -1;
  n := head;
  while n >= 0 do
  begin
    copy := AllocNode(AN_ARG);
    ASTLeft[copy] := ASTLeft[n];
    ASTRight[copy] := -1;
    if prev < 0 then Result := copy else ASTRight[prev] := copy;
    prev := copy;
    n := ASTRight[n];
  end;
end;

{ `zip(a, b)` as a value -> pylib pyzip, which builds the pair list. }
function PyMakeZip(aNode, bNode: Integer): Integer;
var a0, a1: Integer;
begin
  a0 := AllocNode(AN_ARG); ASTLeft[a0] := aNode;
  a1 := AllocNode(AN_ARG); ASTLeft[a1] := bNode; ASTRight[a1] := -1;
  ASTRight[a0] := a1;
  Result := AllocNode(AN_CALL);
  ASTIVal[Result] := FindProc('pyzip');
  if ASTIVal[Result] < 0 then Error('Nil Python: pylib (pyzip) not loaded');
  ASTTk[Result] := Ord(tyClass);
  ASTRight[Result] := REC_UCLASS_BASE + FindUClass('TPyList');
  ASTLeft[Result] := a0;
end;

function PyMakeSubscriptRead(selfNode, idxArgs, ci, pri: Integer): Integer;
var methName: AnsiString; i, mmi, mpi, selfArg, callNode: Integer;
begin
  methName := '';
  for i := 0 to UPropReadMLen[pri] - 1 do
    AppendChar(methName, TokChars[UPropReadMOff[pri] + i]);
  mmi := FindUMeth(ci, methName);
  if mmi < 0 then Error('Nil Python: default property getter not found: ' + methName);
  mpi := UMthProc_[mmi];
  selfArg := AllocNode(AN_ARG);
  ASTLeft[selfArg] := selfNode;
  ASTRight[selfArg] := idxArgs;
  if UMthVirSlot[mmi] >= 0 then
  begin
    callNode := AllocNode(AN_VIRTUAL_CALL);
    ASTRight[callNode] := UMthVirSlot[mmi];
  end
  else
    callNode := AllocNode(AN_CALL);
  ASTIVal[callNode] := mpi;
  ASTTk[callNode] := Ord(Procs[mpi].RetType);
  ASTLeft[callNode] := selfArg;
  Result := callNode;
end;

{ `v[key] = val` on a variant -> pyvar_setitem(v, key, val), a statement. }
function PyMakeVariantSetItem(baseNode, idxNode, valNode: Integer): Integer;
var procIdx, a0, a1, a2, callNode, tmpSym, tmpAssign, innerComma: Integer;
begin
  procIdx := FindProc('pyvar_setitem');
  if procIdx < 0 then Error('Nil Python: pylib (pyvar_setitem) not loaded');
  { pyvar_setitem is a void PROCEDURE, so its own call carries no result --
    but `v[key] = val` is used as a VALUE-BEARING expression wherever a
    chained assignment nests one subscript store inside another
    (`xs[0] = xs[1] = 3`, right-associative). Store the value into a hidden
    temp FIRST, call pyvar_setitem with it, then yield the temp: gives
    Python's actual semantics (every target gets the ORIGINAL value) instead
    of silently dropping the outer store, which is what returning the void
    call node itself did
    (bug-nilpy-chained-subscript-assignment-writes-only-the-last-target). }
  tmpSym := AllocVar(PyHiddenName('setval'), tyVariant);
  tmpAssign := AllocNode(AN_ASSIGN);
  ASTLeft[tmpAssign] := PyMakeIdent(tmpSym);
  ASTRight[tmpAssign] := valNode;

  a0 := AllocNode(AN_ARG); ASTLeft[a0] := baseNode;
  a1 := AllocNode(AN_ARG); ASTLeft[a1] := idxNode;
  a2 := AllocNode(AN_ARG); ASTLeft[a2] := PyMakeIdent(tmpSym);
  ASTRight[a0] := a1; ASTRight[a1] := a2; ASTRight[a2] := -1;
  callNode := AllocNode(AN_CALL);
  ASTIVal[callNode] := procIdx;
  ASTTk[callNode] := Ord(tyUnknown);
  ASTLeft[callNode] := a0;

  innerComma := AllocNode(AN_COMMA);
  ASTLeft[innerComma] := callNode;
  ASTRight[innerComma] := PyMakeIdent(tmpSym);
  ASTTk[innerComma] := Ord(tyVariant);

  Result := AllocNode(AN_COMMA);
  ASTLeft[Result] := tmpAssign;
  ASTRight[Result] := innerComma;
  ASTTk[Result] := Ord(tyVariant);
end;

function PyMakeSuffixIndex(baseNode, idxNode: Integer): Integer;
var rec, listCi, dictCi, procIdx, a0, a1: Integer;
begin
  if PyIsStrBaseTk(IntToTypeKind(ASTTk[baseNode])) then
  begin
    Result := PyMakeStrIndex(baseNode, idxNode);
    Exit;
  end;
  if IntToTypeKind(ASTTk[baseNode]) = tyVariant then
  begin
    { `v[key]` on a variant — dispatch to pyvar_getitem, which unboxes the
      container at run time (dict by key, list by int index). }
    procIdx := FindProc('pyvar_getitem');
    if procIdx < 0 then Error('Nil Python: pylib (pyvar_getitem) not loaded');
    a0 := AllocNode(AN_ARG); ASTLeft[a0] := baseNode;
    a1 := AllocNode(AN_ARG); ASTLeft[a1] := idxNode;
    ASTRight[a0] := a1; ASTRight[a1] := -1;
    Result := AllocNode(AN_CALL);
    ASTIVal[Result] := procIdx;
    ASTTk[Result] := Ord(tyVariant);
    ASTLeft[Result] := a0;
    Exit;
  end;
  rec := ResolveNodeRec(baseNode);
  listCi := FindUClass('TPyList');
  dictCi := FindUClass('TPyDict');
  if (listCi >= 0) and (rec = REC_UCLASS_BASE + listCi) then
    Result := PyCallMeth1(listCi, 'at', baseNode, idxNode)
  else if (dictCi >= 0) and (rec = REC_UCLASS_BASE + dictCi) then
    Result := PyCallMeth1(dictCi, 'fetch', baseNode, idxNode)
  else
    Result := -1;
  if Result < 0 then Error('Nil Python: this value cannot be subscripted');
end;

{ ---- SLICES  `b[lo:hi]` ----------------------------------------------------
  Python slices reach the parser as a subscript whose index expression is
  followed by ':'. Nothing in the Pascal dialect puts a ':' inside brackets
  (set ranges use '..'), so the form is unambiguous and the shared parser can
  hand the whole tail here the moment it sees the colon.

  A slice on a str/list PRODUCES a value; a slice on bytes is also an
  assignment TARGET. Rather than invent an lvalue node for the second case,
  the read call is built first and rewritten into pybytes_setslice by
  PyRewriteSliceAssign when an '=' turns out to follow — the read call
  already carries base, lo and hi in its argument chain. }

function PyBytesCi: Integer;
begin
  PyBytesCi := FindUClass('TPyBytes');
end;

{ Is this node sliceable? str, bytes and list are; a dict is NOT (Python has
  no dict slice), which is why this is not PySubscriptableSuffix. }
function PyIsSliceBase(n: Integer): Boolean;
var rec, listCi, bytesCi: Integer;
begin
  Result := False;
  if n < 0 then Exit;
  if PyIsStrBaseTk(IntToTypeKind(ASTTk[n])) then begin Result := True; Exit; end;
  { a variant may hold a sliceable container — dispatched at run time }
  if IntToTypeKind(ASTTk[n]) = tyVariant then begin Result := True; Exit; end;
  if IntToTypeKind(ASTTk[n]) <> tyClass then Exit;
  rec := ResolveNodeRec(n);
  if rec < REC_UCLASS_BASE then Exit;
  listCi  := FindUClass('TPyList');
  bytesCi := PyBytesCi;
  Result := ((listCi >= 0) and (rec = REC_UCLASS_BASE + listCi)) or
            ((bytesCi >= 0) and (rec = REC_UCLASS_BASE + bytesCi));
end;

{ The sentinel an omitted bound is compiled to; pylib's PySliceBounds turns it
  back into 0 or len. Kept in sync with PY_SLICE_OMIT in pylib.pas. }
function PySliceOmitNode: Integer;
begin
  Result := AllocNode(AN_INT_LIT);
  ASTIVal[Result] := 2147483647;
  ASTTk[Result] := Ord(tyInteger);
end;

{ base[lo:hi] as a VALUE. Picks the pylib function by element type so each
  container keeps its own result type: str -> str, bytes -> bytes, list ->
  list. }
function PyMakeSlice(baseNode, loNode, hiNode: Integer): Integer;
var procIdx, callNode, a0, a1, a2, rec, listCi, bytesCi: Integer;
    pname: AnsiString;
    retTk: TTypeKind;
begin
  pname := '';
  retTk := tyInteger;
  if IntToTypeKind(ASTTk[baseNode]) = tyVariant then
  begin
    pname := 'pyvar_slice';       { unbox and slice at run time; yields a variant }
    retTk := tyVariant;
  end
  else if PyIsStrBaseTk(IntToTypeKind(ASTTk[baseNode])) then
  begin
    pname := 'pystr_slice';
    retTk := tyAnsiString;
  end
  else
  begin
    rec := ResolveNodeRec(baseNode);
    listCi  := FindUClass('TPyList');
    bytesCi := PyBytesCi;
    if (bytesCi >= 0) and (rec = REC_UCLASS_BASE + bytesCi) then
    begin
      pname := 'pybytes_slice';
      retTk := tyClass;
    end
    else if (listCi >= 0) and (rec = REC_UCLASS_BASE + listCi) then
    begin
      pname := 'pylist_slice';
      retTk := tyClass;
    end;
  end;
  if pname = '' then Error('Nil Python: this value cannot be sliced');
  procIdx := FindProc(pname);
  if procIdx < 0 then Error('Nil Python: pylib (' + pname + ') not loaded');

  a0 := AllocNode(AN_ARG); ASTLeft[a0] := baseNode;
  a1 := AllocNode(AN_ARG); ASTLeft[a1] := loNode;
  a2 := AllocNode(AN_ARG); ASTLeft[a2] := hiNode;
  { the ARG chain must be LINKED, not just allocated in order }
  ASTRight[a0] := a1;
  ASTRight[a1] := a2;
  ASTRight[a2] := -1;
  callNode := AllocNode(AN_CALL);
  ASTIVal[callNode] := procIdx;
  ASTTk[callNode] := Ord(retTk);
  ASTLeft[callNode] := a0;
  { a class-typed result must carry its record id or `.` and `[` on the slice
    would not resolve; a str slice must carry NO record id, set explicitly
    rather than trusting the allocator }
  if retTk = tyClass then
    ASTRight[callNode] := ResolveNodeRec(baseNode)
  else
    ASTRight[callNode] := -1;
  LastExprTk := retTk;
  Result := callNode;
end;

{ Parse the tail of a slice: CurTok is the ':' , `loNode` is the low bound
  already parsed (-1 when omitted, as in `b[:n]`). Consumes through ']'. }
function PyParseSliceTail(baseNode, loNode: Integer): Integer;
var hiNode, revIdx, revArg: Integer; stepNeg, loOmitted, hiOmitted: Boolean;
begin
  Next;                              { consume ':' }
  loOmitted := loNode < 0;
  if loNode < 0 then loNode := PySliceOmitNode;
  hiOmitted := (CurTok.Kind = tkRBrack) or (CurTok.Kind = tkColon);
  if hiOmitted then
    hiNode := PySliceOmitNode        { `b[lo:]`, and `b[lo::step]` }
  else
  begin
    PyParseBoolExpr;
    hiNode := CurASTNode;
  end;
  { An optional STEP: `xs[lo:hi:step]`. Only the whole-range reverse `[::-1]`
    is implemented, because that is the idiom real code uses and pylib already
    has `reversed` (a reversed COPY, which is what a slice yields anyway). Any
    other step is refused by name rather than approximated — a slice that
    silently ignored its step would produce a plausible wrong answer. }
  if CurTok.Kind = tkColon then
  begin
    Next;                            { consume the second ':' }
    if CurTok.Kind = tkRBrack then
      Error('Nil Python: a slice step is required after the second '':''');
    stepNeg := (CurTok.Kind = tkMinus) and (TokPos < TokCount) and
               (Tokens[TokPos].Kind = tkInteger) and (Tokens[TokPos].IVal = 1);
    if not (stepNeg and loOmitted and hiOmitted) then
      Error('Nil Python: only the whole-range reverse slice [::-1] is supported; '
            + 'other steps are not implemented');
    Next; Next;                      { '-' and the 1 }
    Expect(tkRBrack, ']');
    { A slice of a STRING is a string; `reversed` would hand back a list of
      characters, which prints as a list and crashes wherever a string was
      expected. Pick the helper from the base's type. }
    if IntToTypeKind(ASTTk[baseNode]) in [tyString, tyAnsiString] then
      revIdx := FindProc('pystr_reverse')
    else
      revIdx := FindProc('reversed');
    if revIdx < 0 then Error('Nil Python: pylib (reversed) not loaded');
    Result := AllocNode(AN_CALL);
    ASTIVal[Result] := revIdx;
    revArg := AllocNode(AN_ARG);
    ASTLeft[revArg] := baseNode;
    ASTRight[revArg] := -1;
    ASTLeft[Result] := revArg;
    ASTTk[Result] := Ord(Procs[revIdx].RetType);
    ASTRight[Result] := ProcRetRecId[revIdx];
    LastExprTk := Procs[revIdx].RetType;
    CurASTNode := Result;
    Exit;
  end;
  Expect(tkRBrack, ']');
  Result := PyMakeSlice(baseNode, loNode, hiNode);
  CurASTNode := Result;
end;

{ True when `n` is the pybytes_slice call built above, i.e. a slice that is
  being used as an assignment TARGET rather than a value. }
function PyIsBytesSliceCall(n: Integer): Boolean;
var procIdx: Integer;
begin
  Result := False;
  if n < 0 then Exit;
  if ASTKind[n] <> AN_CALL then Exit;
  procIdx := FindProc('pybytes_slice');
  if (procIdx >= 0) and (ASTIVal[n] = procIdx) then begin Result := True; Exit; end;
  { a LIST slice read (`l[lo:hi]`) is also a valid slice-assign target }
  procIdx := FindProc('pylist_slice');
  Result := (procIdx >= 0) and (ASTIVal[n] = procIdx);
end;

{ `b[lo:hi] = src` / `l[lo:hi] = src` — turn the already-built read into the
  setter call by swapping the target proc and appending the source as a fourth
  argument. The whole statement IS this call. }
function PyRewriteSliceAssign(sliceNode, rhsNode: Integer): Integer;
var procIdx, a3, a: Integer;
begin
  if ASTIVal[sliceNode] = FindProc('pylist_slice') then
    procIdx := FindProc('pylist_setslice')
  else if IntToTypeKind(ASTTk[rhsNode]) = tyVariant then
    { `bytes[a:b] = <variant>` (e.g. a dict-fetched bytes value) — unbox at run
      time; a raw variant handed to pybytes_setslice is misread as a TPyBytes. }
    procIdx := FindProc('pybytes_setslice_v')
  else
    procIdx := FindProc('pybytes_setslice');
  if procIdx < 0 then Error('Nil Python: pylib (setslice) not loaded');
  a3 := AllocNode(AN_ARG);
  ASTLeft[a3] := rhsNode;
  ASTRight[a3] := -1;
  a := ASTLeft[sliceNode];
  while ASTRight[a] >= 0 do a := ASTRight[a];
  ASTRight[a] := a3;
  ASTIVal[sliceNode] := procIdx;
  { pybytes_setslice is a PROCEDURE: no result type, and the record id the read
    call carried has to go or the statement looks class-typed }
  ASTTk[sliceNode] := Ord(tyUnknown);
  ASTRight[sliceNode] := -1;
  Result := sliceNode;
end;

{ ---- to_bytes / from_bytes -------------------------------------------------
  Both are recognised as intrinsics with a FIXED argument shape, not as real
  methods: their Python spelling ends in a keyword argument (`signed=True`)
  and NilPy has no keyword arguments. See pylib for why that trade is right.

  The shape accepted is exactly the one the corpus uses:
      <int>.to_bytes(n, "little", signed=<expr>)
      int.from_bytes(<bytes>, "little", signed=<expr>)
  Anything else — a big-endian order, a missing `signed=` — is an ERROR rather
  than a silently ignored argument, because both would produce plausible wrong
  bytes rather than a failure. }

function PyIsIntBaseTk(tk: TTypeKind): Boolean;
begin
  { tyPromoInt64: a wide-literal-infected int (`0xFF... if flag else 0`) is
    still Python int; the receiver narrows mod 2^64 at the intrinsic's Int64
    parameter, which reproduces the unsigned byte image. }
  Result := (tk = tyInteger) or (tk = tyInt64) or (tk = tyInt8) or
            (tk = tyInt16) or (tk = tyUInt8) or (tk = tyUInt16) or
            (tk = tyUInt32) or (tk = tyUInt64) or TypeIsPromoInt(tk);
end;

{ Parses the shared tail `, "little", signed=<expr> )` and returns the node for
  the signed flag. CurTok is the comma before the byte order. }
function PyParseByteOrderAndSigned: Integer;
var ordText: AnsiString;
begin
  Expect(tkComma, ',');
  if CurTok.Kind <> tkString then
    Error('Nil Python: to_bytes/from_bytes needs a literal byte order, "little"');
  ordText := CurTok.SVal;
  if ordText <> 'little' then
    Error('Nil Python: only the "little" byte order is supported, got "'
          + ordText + '"');
  Next;
  Expect(tkComma, ',');
  if (CurTok.Kind <> tkIdent) or (LowerCase(CurTok.SVal) <> 'signed') then
    Error('Nil Python: to_bytes/from_bytes needs the signed= keyword argument');
  Next;
  Expect(tkAssign, '=');
  PyParseBoolExpr;
  Result := CurASTNode;
end;

{ `<int>.to_bytes(...)`; CurTok is the '(' . }
function PyParseToBytes(baseNode: Integer): Integer;
var procIdx, callNode, a0, a1, a2, nNode, sNode: Integer;
begin
  procIdx := FindProc('pyint_to_bytes');
  if procIdx < 0 then Error('Nil Python: pylib (pyint_to_bytes) not loaded');
  Expect(tkLParen, '(');
  PyParseBoolExpr;
  nNode := CurASTNode;
  sNode := PyParseByteOrderAndSigned;
  Expect(tkRParen, ')');
  a0 := AllocNode(AN_ARG); ASTLeft[a0] := baseNode;
  a1 := AllocNode(AN_ARG); ASTLeft[a1] := nNode;
  a2 := AllocNode(AN_ARG); ASTLeft[a2] := sNode;
  ASTRight[a0] := a1; ASTRight[a1] := a2; ASTRight[a2] := -1;
  callNode := AllocNode(AN_CALL);
  ASTIVal[callNode] := procIdx;
  ASTTk[callNode] := Ord(tyClass);
  ASTRight[callNode] := ProcRetRecId[procIdx];   { TPyBytes identity }
  ASTLeft[callNode] := a0;
  LastExprTk := tyClass;
  Result := callNode;
end;

{ `int.from_bytes(...)`; CurTok is the '(' . }
function PyParseFromBytes: Integer;
var procIdx, callNode, a0, a1, bNode, sNode: Integer;
begin
  procIdx := FindProc('pyint_from_bytes');
  if procIdx < 0 then Error('Nil Python: pylib (pyint_from_bytes) not loaded');
  Expect(tkLParen, '(');
  PyParseBoolExpr;
  bNode := CurASTNode;
  sNode := PyParseByteOrderAndSigned;
  Expect(tkRParen, ')');
  a0 := AllocNode(AN_ARG); ASTLeft[a0] := bNode;
  a1 := AllocNode(AN_ARG); ASTLeft[a1] := sNode;
  ASTRight[a0] := a1; ASTRight[a1] := -1;
  callNode := AllocNode(AN_CALL);
  ASTIVal[callNode] := procIdx;
  ASTTk[callNode] := Ord(tyInt64);
  ASTRight[callNode] := -1;
  ASTLeft[callNode] := a0;
  LastExprTk := tyInt64;
  Result := callNode;
end;

{ Is CurTok the '.' of a `.to_bytes(` suffix? Used by the generic postfix
  chains to LEAVE the suffix alone so the intrinsic can claim it — a grouped
  `(10).to_bytes(...)` would otherwise be eaten as a member access on an
  integer and die as "unexpected token". }
function PyIsToBytesSuffixAhead: Boolean;
begin
  Result := (CurTok.Kind = tkDot) and (TokPos + 1 < TokCount) and
            (Tokens[TokPos].Kind = tkIdent) and
            (LowerCase(GetTokenStr(TokPos)) = 'to_bytes') and
            (Tokens[TokPos + 1].Kind = tkLParen);
end;

{ `sys.stdout` / `sys.stderr` as an ORDINARY EXPRESSION yielding the stream's
  fd. Done at the factor level, not inside print's file= handling, because
  `sys` is a deferred stdlib import and therefore not a symbol: every pass that
  parses the expression — including the typing pre-pass, which runs BEFORE
  statement parsing and was the one actually rejecting it — has to agree that
  `sys.stderr` resolves. Modelling it as an fd integer is what lets
  AN_WRITE/AN_WRITELN pick it up through their existing ival slot. }
function PyIsSysStreamAhead: Boolean;
var base, nm: AnsiString;
begin
  Result := False;
  if (TokPos < 1) or (TokPos + 1 >= TokCount) then Exit;
  base := LowerCase(GetTokenStr(TokPos - 1));
  if Tokens[TokPos].Kind <> tkDot then Exit;
  nm := LowerCase(GetTokenStr(TokPos + 1));
  if base = 'sys' then
    { ANY sys attribute: the four modelled ones below, and everything else as a
      runtime "not available here". `sys._MEIPASS` is the shape — PyInstaller
      sets it and CPython raises AttributeError when it is absent, which is
      exactly what the application's `try/except` around it expects. Reported
      at run time, not silently zero. }
    Result := True
  else if base = 'os' then
    { os.SEEK_SET/CUR/END — the whence CONSTANTS, bare values not calls. }
    Result := (nm = 'seek_set') or (nm = 'seek_cur') or (nm = 'seek_end');
end;

function PyParseSysStream: Integer;
var nm: AnsiString; procIdx: Integer;
begin
  nm := LowerCase(GetTokenStr(TokPos + 1));
  Next; Next; Next;              { base, '.', the member name }
  if (nm = 'seek_set') or (nm = 'seek_cur') or (nm = 'seek_end') then
  begin
    Result := AllocNode(AN_INT_LIT);
    if nm = 'seek_cur' then ASTIVal[Result] := 1
    else if nm = 'seek_end' then ASTIVal[Result] := 2
    else ASTIVal[Result] := 0;
    ASTTk[Result] := Ord(tyInteger);
    ASTRight[Result] := -1;
    LastExprTk := tyInteger;
    Exit;
  end;
  if nm = 'platform' then
  begin
    { sys.platform — the value CPython reports on the platform pxx hosts on.
      songformatter branches on it to pick a file-opener command, and every
      such test in real code is `== "darwin"` / `.startswith("win")`, so a
      constant string is the whole of what is needed. When pxx targets Windows
      this has to follow the TARGET, not the host. }
    Result := AllocNode(AN_STR_LIT);
    ASTSOffset[Result] := PyStoredName('linux');
    ASTSLen[Result] := 5;
    ASTTk[Result] := Ord(tyString);
    LastExprTk := tyString;
    Exit;
  end;
  if nm = 'argv' then
  begin
    { sys.argv as a VALUE — the command line as a TPyList of strings. }
    procIdx := FindProc('pysys_argv');
    if procIdx < 0 then Error('Nil Python: pylib (pysys_argv) not loaded');
    Result := AllocNode(AN_CALL);
    ASTIVal[Result] := procIdx;
    ASTTk[Result] := Ord(tyClass);
    ASTRight[Result] := ProcRetRecId[procIdx];
    ASTLeft[Result] := -1;
    LastExprTk := tyClass;
    Exit;
  end;
  if (nm <> 'stdout') and (nm <> 'stderr') and (nm <> 'stdin') then
  begin
    { an attribute this sys does not have — raise, as CPython does }
    Result := PyMakeOptionalMissingCall('sys.' + nm);
    LastExprTk := IntToTypeKind(ASTTk[Result]);
    Exit;
  end;
  Result := AllocNode(AN_INT_LIT);
  { stdin=0, stdout=1, stderr=2 — the fd each stream stands for. }
  if nm = 'stderr' then ASTIVal[Result] := 2
  else if nm = 'stdin' then ASTIVal[Result] := 0
  else ASTIVal[Result] := 1;
  ASTTk[Result] := Ord(tyInteger);
  ASTRight[Result] := -1;
  LastExprTk := tyInteger;
end;

{ ---- stdlib dotted calls: os.path.join(...), sys.exit(...) ----------------
  `os` and `sys` are deferred imports and never become symbols, so a dotted
  call on them cannot go through ordinary member resolution — it is mapped by
  NAME onto a pylib function instead. Same reasoning as sys.stdout/sys.stderr
  above, and handled at the same factor level so every pass agrees.

  Deliberately a fixed table rather than a general module system: each entry is
  a shim with real semantics behind it, and an unmapped name must stay an
  error rather than resolve to something plausible. }
function PyStdlibCallProc(const dotted: AnsiString): AnsiString;
begin
  if dotted = 'os.path.isabs' then Result := 'pyos_path_isabs'
  else if dotted = 'os.path.join' then Result := 'pyos_path_join'
  else if dotted = 'os.path.exists' then Result := 'pyos_path_exists'
  else if dotted = 'os.path.abspath' then Result := 'pyos_path_abspath'
  else if dotted = 'os.path.dirname' then Result := 'pyos_path_dirname'
  else if dotted = 'os.getcwd' then Result := 'pyos_getcwd'
  else if dotted = 'os.environ.get' then Result := 'pyos_environ_get'
  else if dotted = 'os.getenv' then Result := 'pyos_getenv'
  else if dotted = 'os.remove' then Result := 'pyos_remove'
  else if dotted = 'os.startfile' then Result := 'pyos_startfile'
  else if dotted = 'os.rename' then Result := 'pyos_rename'
  else if dotted = 'os.stat' then Result := 'pyos_stat'
  else if dotted = 'sys.exit' then Result := 'pysys_exit'
  else if dotted = 'sys.stdin.read' then Result := 'pystdin_read'
  else if dotted = 'sys.stdin.readline' then Result := 'pystdin_readline'
  else if dotted = 'sys.stdin.isatty' then Result := 'pystdin_isatty'
  else if dotted = 'select.select' then Result := 'pyselect_select'
  else if dotted = 'textwrap.dedent' then Result := 'pytextwrap_dedent'
  { dict.fromkeys(iterable) — a CLASSMETHOD, so it reaches the same table: the
    base name is a type rather than a module, which changes nothing here.
    songformatter uses `list(dict.fromkeys(xs))`, the standard order-preserving
    dedupe. }
  else if dotted = 'dict.fromkeys' then Result := 'pydict_fromkeys'
  { math.floor/math.ceil must NOT reach the RTL Math unit's own Floor/Ceil
    (Double->Double, correct for the Pascal frontend, wrong for Python's int
    contract) -- intercepted here by name, ahead of the ordinary qualified-
    call resolution that `import math` would otherwise hit.
    bug-nilpy-implicit-return-is-0-and-math-floor-returns-a-float }
  else if dotted = 'math.floor' then Result := 'pymath_floor'
  else if dotted = 'math.ceil' then Result := 'pymath_ceil'
  else Result := '';
end;

{ nTok = how many tokens the dotted name occupies, so the caller can skip to
  the '(' . CurTok is the leading `os`/`sys`. }
function PyStdlibCallAhead(var pname: AnsiString; var nTok: Integer): Boolean;
var base, d2, d3: AnsiString;
begin
  Result := False; pname := ''; nTok := 0;
  if TokPos < 1 then Exit;
  base := LowerCase(GetTokenStr(TokPos - 1));
  if (base <> 'os') and (base <> 'sys') and (base <> 'textwrap') and
     (base <> 'select') and (base <> 'dict') and (base <> 'math') then Exit;
  if (TokPos >= TokCount) or (Tokens[TokPos].Kind <> tkDot) then Exit;
  if TokPos + 1 >= TokCount then Exit;
  d2 := base + '.' + LowerCase(GetTokenStr(TokPos + 1));
  { three segments first — `os.path.join` must not be read as `os.path` }
  if (TokPos + 4 < TokCount) and (Tokens[TokPos + 2].Kind = tkDot) and
     (Tokens[TokPos + 4].Kind = tkLParen) then
  begin
    d3 := d2 + '.' + LowerCase(GetTokenStr(TokPos + 3));
    pname := PyStdlibCallProc(d3);
    if pname <> '' then begin nTok := 5; Result := True; Exit; end;
  end;
  if (TokPos + 2 < TokCount) and (Tokens[TokPos + 2].Kind = tkLParen) then
  begin
    pname := PyStdlibCallProc(d2);
    if pname <> '' then begin nTok := 3; Result := True; Exit; end;
  end;
end;

function PyParseStdlibCall(const pname: AnsiString; nTok: Integer): Integer;
var procIdx, callNode, argNode, lastArg, i, nArgs: Integer;
begin
  nArgs := 0;
  procIdx := FindProc(pname);
  if procIdx < 0 then Error('Nil Python: pylib (' + pname + ') not loaded');
  for i := 1 to nTok do Next;          { the dotted name; CurTok = '(' }
  Expect(tkLParen, '(');
  lastArg := -1;
  callNode := AllocNode(AN_CALL);
  ASTIVal[callNode] := procIdx;
  ASTTk[callNode] := Ord(Procs[procIdx].RetType);
  ASTRight[callNode] := ProcRetRecId[procIdx];
  ASTLeft[callNode] := -1;
  if CurTok.Kind <> tkRParen then
    repeat
      if CurTok.Kind = tkRParen then Break;   { a trailing comma before ) }
      PyParseBoolExpr;
      argNode := AllocNode(AN_ARG);
      ASTLeft[argNode] := CurASTNode;
      ASTRight[argNode] := -1;
      if lastArg < 0 then ASTLeft[callNode] := argNode
      else ASTRight[lastArg] := argNode;
      lastArg := argNode;
      Inc(nArgs);
    until not Eat(tkComma);
  Expect(tkRParen, ')');
  { The optional-DEFAULT form of a shim, e.g. `os.environ.get(name, default)`
    beside `os.environ.get(name)`. FindProc takes the first overload, and a call
    node carries one fixed proc index, so the two arities cannot be one
    overloaded name here — the second is registered as `<name>_d` and selected
    by the count. Without this the two-argument call bound to the one-argument
    proc and the default was silently dropped. }
  if nArgs > Procs[procIdx].ParamCount then
  begin
    i := FindProc(pname + '_d');
    if (i >= 0) and (Procs[i].ParamCount = nArgs) then
    begin
      procIdx := i;
      ASTIVal[callNode] := procIdx;
      ASTTk[callNode] := Ord(Procs[procIdx].RetType);
      ASTRight[callNode] := ProcRetRecId[procIdx];
    end
    else
      Error('Nil Python: ' + pname + ' takes ' +
            'fewer arguments than were given');
  end;
  LastExprTk := IntToTypeKind(ASTTk[callNode]);
  Result := callNode;
end;

{ hasattr(obj, "name") / getattr(obj, "name" [, default]).

  Every censused use passes a STRING LITERAL attribute name, and NilPy classes
  have statically-declared fields, so both resolve at COMPILE time against the
  receiver's class. A receiver with no static class (a variant, e.g. a caught
  exception) counts as "does not declare it" — which is right for the corpus,
  where getattr(e, "errno", 1) probes for attributes our exception shims do not
  have and wants the default.

  Deviation worth knowing: Python's hasattr answers "has this attribute been
  ASSIGNED on this instance", per object. NilPy fields always exist and are
  zero-initialised, so a declared field reports True even before first
  assignment. Filed as decide-nilpy-hasattr-per-instance-semantics. }
function PyAttrFieldIdx(recvNode: Integer; const attr: AnsiString): Integer;
var rec, ci: Integer;
begin
  Result := -1;
  if recvNode < 0 then Exit;
  rec := ResolveNodeRec(recvNode);
  if rec < REC_UCLASS_BASE then Exit;
  ci := rec - REC_UCLASS_BASE;
  Result := FindUField(ci, attr);
end;

{ Reads the string-literal attribute name; CurTok is the ',' before it. }
function PyParseAttrName: AnsiString;
begin
  Expect(tkComma, ',');
  if CurTok.Kind <> tkString then
    Error('Nil Python: hasattr/getattr needs a literal attribute name');
  Result := CurTok.SVal;
  Next;
end;

{ Is the token stream at `int.from_bytes(` ? CurTok is the `int` ident. }
function PyIsFromBytesAhead: Boolean;
begin
  Result := (CurTok.Kind = tkIdent) and (LowerCase(CurTok.SVal) = 'int') and
            (TokPos + 1 < TokCount) and (Tokens[TokPos].Kind = tkDot) and
            (Tokens[TokPos + 1].Kind = tkIdent) and
            (LowerCase(GetTokenStr(TokPos + 1)) = 'from_bytes');
end;

{ `v.field` (READ) where `v` is a VARIANT: unbox to the class that declares the
  field and read it. Returns -1 when no class declares the name. }
{ Read `<class>.field` off a variant: unbox to that class and read. }
function PyVariantFieldArm(baseNode, ci, fi: Integer;
                           const fname: AnsiString): Integer;
var unboxArg, unboxCall, castNode: Integer;
begin
  unboxArg := AllocNode(AN_ARG);
  ASTLeft[unboxArg] := baseNode;
  unboxCall := AllocNode(AN_CALL);
  ASTIVal[unboxCall] := FindProc('pyvarobj');
  if ASTIVal[unboxCall] < 0 then Error('Nil Python: pylib (pyvarobj) not loaded');
  ASTTk[unboxCall] := Ord(tyPointer);
  ASTLeft[unboxCall] := unboxArg;
  castNode := AllocNode(AN_CLASS_CAST);
  ASTLeft[castNode] := unboxCall;
  ASTIVal[castNode] := ci;
  ASTTk[castNode]   := Ord(tyClass);
  Result := AllocNode(AN_FIELD);
  ASTLeft[Result] := castNode;
  ASTSOffset[Result] := PyStoredName(fname);
  ASTSLen[Result] := Length(fname);
  ASTTk[Result] := UFldTk[fi];
end;

{ Force a node to Variant. A scalar goes through pyvar_id, whose parameter is a
  const Variant, so the ordinary call-argument boxing does the work. }
function PyForceVariant(node: Integer): Integer;
var argNode: Integer;
begin
  if IntToTypeKind(ASTTk[node]) = tyVariant then
  begin
    PyForceVariant := node;
    Exit;
  end;
  argNode := AllocNode(AN_ARG);
  ASTLeft[argNode] := node;
  ASTRight[argNode] := -1;
  PyForceVariant := AllocNode(AN_CALL);
  ASTIVal[PyForceVariant] := FindProc('pyvar_id');
  if ASTIVal[PyForceVariant] < 0 then Error('Nil Python: pylib (pyvar_id) not loaded');
  ASTTk[PyForceVariant] := Ord(tyVariant);
  ASTLeft[PyForceVariant] := argNode;
end;

{ `v.field` (READ) where `v` is a VARIANT: unbox to the class that declares the
  field and read it. Returns -1 when no class declares the name.

  When SEVERAL classes declare it and they disagree on offset or type, the class
  is decided at RUN TIME — one `pyvarobj(v) is C ? <read as C> : ...` arm per
  candidate, which is exactly how a METHOD on a variant is dispatched
  (PyParseVariantMethod). This used to be refused outright, telling the
  application to annotate a local; `event.x` in a Tk callback is the shape, and
  tkinter's Event (Integer at 8) collides with any other class that has an `x`
  (songformatter's text object holds a Variant at 24). Refusing was safe but it
  asked the program to change, and the program is the thing being compiled.

  Arms are boxed to Variant when the candidates' field types differ, so the
  expression has ONE type whichever class turns up. }
function PyMakeVariantField(baseNode: Integer; const fname: AnsiString;
                            var tk: TTypeKind; var recName: Integer): Integer;
const MAX_FIELD_CANDIDATES = 16;
var ci, fi, i, n, armN, condN, pairN, tern, unboxArg, unboxCall: Integer;
    cands: array[0..MAX_FIELD_CANDIDATES - 1] of Integer;
    candFi: array[0..MAX_FIELD_CANDIDATES - 1] of Integer;
    sameShape: Boolean;
begin
  Result := -1;
  n := 0;
  for ci := 0 to UClsCount - 1 do
  begin
    if UClsIsRecord[ci] then Continue;
    fi := FindUField(ci, fname);
    if fi < 0 then Continue;
    if n < MAX_FIELD_CANDIDATES then
    begin
      cands[n] := ci;
      candFi[n] := fi;
      Inc(n);
    end;
  end;
  if n = 0 then Exit;

  sameShape := True;
  for i := 1 to n - 1 do
    if (UFldTk[candFi[i]] <> UFldTk[candFi[0]]) or
       (UFldOff_[candFi[i]] <> UFldOff_[candFi[0]]) then sameShape := False;

  if sameShape then
  begin
    { one layout: read it directly, exactly as before — no dispatch, and the
      emitted code for every program that already compiled is unchanged }
    Result := PyVariantFieldArm(baseNode, cands[0], candFi[0], fname);
    tk := IntToTypeKind(UFldTk[candFi[0]]);
    recName := UFldRec_[candFi[0]];
    Exit;
  end;

  { Several layouts: decide at run time. The LAST candidate is the fallback arm,
    so a receiver of none of these classes reads as that one did before —
    wrong, but no worse than the single-class guess this replaces, and the
    common case (a receiver that IS one of them) is now right. }
  Result := PyForceVariant(PyVariantFieldArm(baseNode, cands[n - 1],
                                             candFi[n - 1], fname));
  for i := n - 2 downto 0 do
  begin
    armN := PyForceVariant(PyVariantFieldArm(baseNode, cands[i], candFi[i], fname));
    { cond: pyvarobj(v) is <candidate> — the test isinstance lowers to }
    unboxArg := AllocNode(AN_ARG);
    ASTLeft[unboxArg] := baseNode;
    unboxCall := AllocNode(AN_CALL);
    ASTIVal[unboxCall] := FindProc('pyvarobj');
    if ASTIVal[unboxCall] < 0 then Error('Nil Python: pylib (pyvarobj) not loaded');
    ASTTk[unboxCall] := Ord(tyPointer);
    ASTLeft[unboxCall] := unboxArg;
    condN := AllocNode(AN_IS_TEST);
    ASTLeft[condN] := unboxCall;
    ASTIVal[condN] := cands[i];
    ASTTk[condN] := Ord(tyBoolean);

    pairN := AllocNode(AN_PAIR);
    ASTLeft[pairN] := armN;
    ASTRight[pairN] := Result;
    tern := AllocNode(AN_TERNARY);
    ASTLeft[tern] := condN;
    ASTRight[tern] := pairN;
    ASTTk[tern] := Ord(tyVariant);
    Result := tern;
  end;
  tk := tyVariant;
  recName := REC_NONE;
end;

{ A synthetic call signature: nArgs Variant params, Variant result, no body.
  Used for a DYNAMIC call through a value whose callable type is not known
  statically — `ns["__body__"]()`, where the dict holds a callable. Registered
  once per arity and reused. }
function PyDynCallSig(nArgs: Integer): Integer;
var pNames: array[0..15] of AnsiString; pTypes: array[0..15] of TTypeKind;
    i: Integer;
begin
  if nArgs > 15 then Error('Nil Python: too many arguments in a dynamic call');
  for i := 0 to nArgs - 1 do
  begin
    pNames[i] := '$dynarg';   { param names are irrelevant to a call signature }
    pTypes[i] := tyVariant;
  end;
  Result := RegisterProc('$pydyn', True, tyVariant, nArgs, pNames, pTypes);
  Procs[Result].BodyAddr := -1;
end;

{ Wrap a 1-arg dynamic call so a VT_PYCLOSURE callee routes to pyeval's reverse
  bridge instead of being unboxed as a code pointer. Builds
  `pyvartag(callee)=9 ? PyClosureCall1(callee, arg) : <defCall>`. calleeNode is
  the callee variant; argExpr is the single argument expression; defCall is the
  already-built AN_CALL_IND fast path. }
function PyWrapClosureDynCall(calleeNode, argExpr, defCall: Integer): Integer;
var tagCall, tagArg, nineLit, guard, clArgC, clArgA, thenCall, pair, tern: Integer;
    tagPi, callPi: Integer;
begin
  tagPi := FindProc('pyvartag');
  callPi := FindProc('PyClosureCall1');
  if (tagPi < 0) or (callPi < 0) then
  begin PyWrapClosureDynCall := defCall; Exit; end;

  { pyvartag(callee) }
  tagArg := AllocNode(AN_ARG); ASTLeft[tagArg] := calleeNode; ASTRight[tagArg] := -1;
  tagCall := AllocNode(AN_CALL);
  ASTIVal[tagCall] := tagPi; ASTLeft[tagCall] := tagArg; ASTTk[tagCall] := Ord(tyInt64);

  nineLit := AllocNode(AN_INT_LIT);
  ASTIVal[nineLit] := 9; ASTTk[nineLit] := Ord(tyInt64);

  guard := AllocNode(AN_BINOP); ASTIVal[guard] := Ord(tkEq);
  ASTLeft[guard] := tagCall; ASTRight[guard] := nineLit; ASTTk[guard] := Ord(tyBoolean);

  { PyClosureCall1(callee, arg) }
  clArgA := AllocNode(AN_ARG); ASTLeft[clArgA] := argExpr; ASTRight[clArgA] := -1;
  clArgC := AllocNode(AN_ARG); ASTLeft[clArgC] := calleeNode; ASTRight[clArgC] := clArgA;
  thenCall := AllocNode(AN_CALL);
  ASTIVal[thenCall] := callPi; ASTLeft[thenCall] := clArgC; ASTTk[thenCall] := Ord(tyVariant);

  pair := AllocNode(AN_PAIR);
  ASTLeft[pair] := thenCall; ASTRight[pair] := defCall;
  tern := AllocNode(AN_TERNARY);
  ASTLeft[tern] := guard; ASTRight[tern] := pair; ASTTk[tern] := Ord(tyVariant);
  PyWrapClosureDynCall := tern;
end;

{ Wrap a 1-arg call through a Callable/Pointer FIELD (`word.native(vm2)`) so a
  field holding a pyeval closure object routes to the pointer-form reverse bridge.
  The field pointer holds either a real compiled function address (uforth's own
  `w_plus`) or a closure object (uforth's VARIABLE/CONSTANT words, whose native is
  a captured PYTHON `def`); pyclosure_is tells them apart at runtime. Builds
  `pyclosure_is(field) ? pyclosure_call_ptr(field, arg) : <defCall>`. fieldNode is
  the field read (side-effect-free, so re-used across guard and arms); argExpr the
  single argument; defCall the already-built AN_CALL_IND. }
function PyWrapClosureFieldCall(fieldNode, argExpr, defCall: Integer): Integer;
var isArg, isCall, clArgP, clArgA, thenCall, pair, tern: Integer;
    isPi, callPi: Integer;
    bfIsPi, bfCallPi, bfIsArg, bfIsCall, bfArgA, bfArgP, bfCall: Integer;
begin
  isPi := FindProc('pyclosure_is');
  callPi := FindProc('pyclosure_call_ptr');
  if (isPi < 0) or (callPi < 0) then
  begin PyWrapClosureFieldCall := defCall; Exit; end;

  isArg := AllocNode(AN_ARG); ASTLeft[isArg] := fieldNode; ASTRight[isArg] := -1;
  isCall := AllocNode(AN_CALL);
  ASTIVal[isCall] := isPi; ASTLeft[isCall] := isArg; ASTTk[isCall] := Ord(tyBoolean);

  clArgA := AllocNode(AN_ARG); ASTLeft[clArgA] := argExpr; ASTRight[clArgA] := -1;
  clArgP := AllocNode(AN_ARG); ASTLeft[clArgP] := fieldNode; ASTRight[clArgP] := clArgA;
  thenCall := AllocNode(AN_CALL);
  ASTIVal[thenCall] := callPi; ASTLeft[thenCall] := clArgP; ASTTk[thenCall] := Ord(tyInteger);

  { middle branch: a BOUND COMPILED FN (captures-only nested def as a value —
    uforth's MARKER restore) — pyboundfn_is ? pyboundfn_call_ptr : defCall }
  bfIsPi := FindProc('pyboundfn_is');
  bfCallPi := FindProc('pyboundfn_call_ptr');
  if (bfIsPi >= 0) and (bfCallPi >= 0) then
  begin
    bfIsArg := AllocNode(AN_ARG); ASTLeft[bfIsArg] := fieldNode; ASTRight[bfIsArg] := -1;
    bfIsCall := AllocNode(AN_CALL);
    ASTIVal[bfIsCall] := bfIsPi; ASTLeft[bfIsCall] := bfIsArg; ASTTk[bfIsCall] := Ord(tyBoolean);
    bfArgA := AllocNode(AN_ARG); ASTLeft[bfArgA] := argExpr; ASTRight[bfArgA] := -1;
    bfArgP := AllocNode(AN_ARG); ASTLeft[bfArgP] := fieldNode; ASTRight[bfArgP] := bfArgA;
    bfCall := AllocNode(AN_CALL);
    ASTIVal[bfCall] := bfCallPi; ASTLeft[bfCall] := bfArgP; ASTTk[bfCall] := Ord(tyInteger);
    pair := AllocNode(AN_PAIR);
    ASTLeft[pair] := bfCall; ASTRight[pair] := defCall;
    tern := AllocNode(AN_TERNARY);
    ASTLeft[tern] := bfIsCall; ASTRight[tern] := pair; ASTTk[tern] := Ord(tyInteger);
    defCall := tern;
  end;

  pair := AllocNode(AN_PAIR);
  ASTLeft[pair] := thenCall; ASTRight[pair] := defCall;
  tern := AllocNode(AN_TERNARY);
  ASTLeft[tern] := isCall; ASTRight[tern] := pair; ASTTk[tern] := Ord(tyInteger);
  PyWrapClosureFieldCall := tern;
end;

{ `g = lambda ...` — box the lambda's value so the NAME is typed tyVariant.
  Both lambda lowerings hand back a heap OBJECT pointer (a pyeval closure, or a
  lifted bound-fn), and a pointer-typed local never reaches ParsePostfix's
  dynamic-call path, which keys on tyVariant — so `g(5)` compiled to nothing at
  all. Returns the node unchanged for anything that is not one of those calls;
  argument positions are deliberately untouched, since a callee's `const x:
  Variant` parameter already boxes the pointer for them. }
function PyBoxCallableValue(node: Integer): Integer;
var pi, boxPi: Integer; nm: AnsiString;
begin
  PyBoxCallableValue := node;
  if node < 0 then Exit;
  if ASTKind[node] <> AN_CALL then Exit;
  if IntToTypeKind(ASTTk[node]) <> tyPointer then Exit;
  pi := ASTIVal[node];
  if pi < 0 then Exit;
  nm := LowerCase(Procs[pi].Name);
  if (nm <> 'pyclosure_src_new') and (nm <> 'pyclosure_src_cap') and
     (nm <> 'pyboundfn_new') and (nm <> 'pyboundfn_bind') and
     (nm <> 'pyboundfn_setown') and
     (nm <> 'pyboundfn_bind_var') and (nm <> 'pyboundfn_bind_obj') then Exit;
  boxPi := FindProc('pyvar_of_callable');
  if boxPi < 0 then Exit;
  pi := AllocNode(AN_ARG);
  ASTLeft[pi] := node; ASTRight[pi] := -1;
  PyBoxCallableValue := AllocNode(AN_CALL);
  ASTIVal[PyBoxCallableValue] := boxPi;
  ASTLeft[PyBoxCallableValue] := pi;
  ASTTk[PyBoxCallableValue] := Ord(tyVariant);
end;

{ Wrap a dynamic call so a FUNCTION VALUE callee (VT_BOUNDMETHOD, tag 8 — what
  `f = some_def` / `f = obj.method` stores) routes to pybound_callv<n> instead of
  being unboxed as a code address. The payload of a tag-8 variant is the
  {code, recv} PAIR, so the plain indirect path jumped into the pair's own bytes,
  and a bound method needs its receiver prepended besides. Builds
  `pycallback_is(callee) ? pybound_callv<n>(callee, args...) : <defCall>`.

  calleeNode is re-used across the guard and the call, so this is only applied
  when re-reading it is free of side effects (a name or a field — the same rule
  PyWrapClosureDynCall/PyMakeTruthy follow). argsHead is the AN_ARG chain of the
  already-parsed arguments; those nodes are shared between the arms, which is
  safe because a ternary evaluates exactly one arm. }
function PyWrapBoundDynCall(calleeNode, argsHead, n, defCall: Integer): Integer;
var isArg, isCall, cArgs, cArg, thenCall, pair, tern, i, a: Integer;
    isPi, callPi: Integer;
    argNodes: array[0..2] of Integer;
begin
  PyWrapBoundDynCall := defCall;
  if n > 3 then Exit;
  if (ASTKind[calleeNode] <> AN_IDENT) and (ASTKind[calleeNode] <> AN_FIELD) then Exit;
  isPi := FindProc('pycallback_is');
  case n of
    0: callPi := FindProc('pybound_callv0');
    1: callPi := FindProc('pybound_callv1');
    2: callPi := FindProc('pybound_callv2');
  else callPi := FindProc('pybound_callv3');
  end;
  if (isPi < 0) or (callPi < 0) then Exit;

  { pycallback_is(callee) }
  isArg := AllocNode(AN_ARG); ASTLeft[isArg] := calleeNode; ASTRight[isArg] := -1;
  isCall := AllocNode(AN_CALL);
  ASTIVal[isCall] := isPi; ASTLeft[isCall] := isArg; ASTTk[isCall] := Ord(tyBoolean);

  { pybound_callv<n>(callee, a0..) — a FRESH AN_ARG chain over the same argument
    expressions; the defCall arm owns the original chain and the two must not
    share link fields. }
  a := argsHead; i := 0;
  while (a >= 0) and (i < n) do
  begin
    argNodes[i] := ASTLeft[a];
    a := ASTRight[a];
    Inc(i);
  end;
  cArgs := -1;
  for i := n - 1 downto 0 do
  begin
    cArg := AllocNode(AN_ARG);
    ASTLeft[cArg] := argNodes[i]; ASTRight[cArg] := cArgs;
    cArgs := cArg;
  end;
  cArg := AllocNode(AN_ARG);
  ASTLeft[cArg] := calleeNode; ASTRight[cArg] := cArgs;
  thenCall := AllocNode(AN_CALL);
  ASTIVal[thenCall] := callPi; ASTLeft[thenCall] := cArg; ASTTk[thenCall] := Ord(tyVariant);

  pair := AllocNode(AN_PAIR);
  ASTLeft[pair] := thenCall; ASTRight[pair] := defCall;
  tern := AllocNode(AN_TERNARY);
  ASTLeft[tern] := isCall; ASTRight[tern] := pair; ASTTk[tern] := Ord(tyVariant);
  PyWrapBoundDynCall := tern;
end;

{ `<value>(args)` where the value is a CLASS INSTANCE defining `__call__` --
  Python's callable-object protocol. Without this, a class instance followed
  by '(' produced either a hard parse error or (depending on the shape) a
  garbage value read off the instance pointer, never the method
  (bug-nilpy-dunder-protocols-ignored-fall-back-to-handle-arithmetic).
  Returns baseNode unchanged when the class has no `__call__`, so the caller
  falls through to whatever ordinarily happens to a class value followed by
  '(' (a parse error today — there is no other legitimate reading). CurTok is
  the '('; arbitrary arity, unlike PyCallMeth1/2's fixed 0/1/2 args. }
function PyMakeCallDunder(baseNode: Integer): Integer;
var ci, mmi, mpi, selfArg, lastArg, argNode, notCallablePi: Integer;
begin
  Result := baseNode;
  ci := ResolveNodeRec(baseNode);
  if ci < REC_UCLASS_BASE then Exit;
  mmi := FindUMeth(ci - REC_UCLASS_BASE, '__call__');
  Expect(tkLParen, '(');
  if mmi < 0 then
  begin
    { No `__call__`: consume the argument list (still evaluated, matching
      Python's own left-to-right argument evaluation before the TypeError)
      and raise a genuine runtime error -- a `try/except` around this must
      still compile and run its handler, the same reasoning as
      PyNotContainerError just above. }
    while CurTok.Kind <> tkRParen do
    begin
      PyParseBoolExpr;
      if not Eat(tkComma) then Break;
    end;
    Expect(tkRParen, ')');
    notCallablePi := FindProc('PyNotCallableError');
    if notCallablePi < 0 then Error('Nil Python: pylib (PyNotCallableError) not loaded');
    Result := AllocNode(AN_CALL);
    ASTIVal[Result] := notCallablePi;
    ASTTk[Result] := Ord(tyInteger);
    ASTLeft[Result] := -1;
    Exit;
  end;
  mpi := UMthProc_[mmi];
  selfArg := AllocNode(AN_ARG);
  ASTLeft[selfArg] := baseNode; ASTRight[selfArg] := -1;
  lastArg := selfArg;
  while CurTok.Kind <> tkRParen do
  begin
    PyParseBoolExpr;
    argNode := AllocNode(AN_ARG);
    ASTLeft[argNode] := CurASTNode; ASTRight[argNode] := -1;
    ASTRight[lastArg] := argNode;
    lastArg := argNode;
    if not Eat(tkComma) then Break;
  end;
  Expect(tkRParen, ')');
  Result := AllocNode(AN_CALL);
  ASTIVal[Result] := mpi;
  ASTTk[Result] := Ord(Procs[mpi].RetType);
  ASTRight[Result] := ProcRetRecId[mpi];
  ASTLeft[Result] := selfArg;
end;

{ `<value>(args)` where the value is a VARIANT holding a callable — the function
  `exec()` stored in a namespace dict, called as `ns["__body__"]()`. Unbox the
  variant to its payload (the code pointer) and emit an indirect call with a
  synthetic all-variant signature. CurTok is the '('. }
function PyMakeDynCall(baseNode: Integer): Integer;
var unboxArg, unboxCall, argsHead, lastArg, argNode, n, sigPi: Integer;
    nmArg, nmLit, dispPi, dispArg: Integer; calleeNm: AnsiString;
begin
  { the callee code address = the variant's payload as a pointer }
  unboxArg := AllocNode(AN_ARG);
  ASTLeft[unboxArg] := baseNode;
  ASTRight[unboxArg] := -1;
  unboxCall := AllocNode(AN_CALL);
  { the CHECKED unbox: a nil payload (the name is None) raises TypeError instead
    of calling address 0 }
  ASTIVal[unboxCall] := FindProc('pyvar_callee_addr');
  if ASTIVal[unboxCall] >= 0 then
  begin
    { name the callee when it is a plain variable, so the message points at the
      culprit rather than at "object" }
    nmArg := AllocNode(AN_ARG);
    nmLit := AllocNode(AN_STR_LIT);
    if ASTKind[baseNode] = AN_IDENT then
      calleeNm := Syms[ASTIVal[baseNode]].Name
    else if ASTKind[baseNode] = AN_FIELD then
      calleeNm := PyRawName(ASTSOffset[baseNode], ASTSLen[baseNode])
    else if (TokPos >= 2) and (Tokens[TokPos - 2].Kind = tkIdent) then
      { last resort: the token right before the '(' — a subscript or call-result
        receiver has no name of its own, but the source text does }
      calleeNm := GetTokenStr(TokPos - 2)
    else
      calleeNm := '';
    ASTSOffset[nmLit] := PyStoredName(calleeNm);
    ASTSLen[nmLit] := Length(calleeNm);
    ASTTk[nmLit] := Ord(tyString);
    ASTLeft[nmArg] := nmLit;
    ASTRight[nmArg] := -1;
    ASTRight[unboxArg] := nmArg;
  end
  else ASTIVal[unboxCall] := FindProc('pyvarobj');
  if ASTIVal[unboxCall] < 0 then Error('Nil Python: pylib (pyvarobj) not loaded');
  ASTTk[unboxCall] := Ord(tyPointer);
  ASTLeft[unboxCall] := unboxArg;

  Expect(tkLParen, '(');
  argsHead := -1; lastArg := -1; n := 0;
  while CurTok.Kind <> tkRParen do
  begin
    PyParseBoolExpr;
    argNode := AllocNode(AN_ARG);
    ASTLeft[argNode] := CurASTNode;
    ASTRight[argNode] := -1;
    if argsHead = -1 then argsHead := argNode else ASTRight[lastArg] := argNode;
    lastArg := argNode;
    Inc(n);
    if CurTok.Kind = tkComma then Next else Break;
  end;
  Expect(tkRParen, ')');

  { ONE runtime dispatcher when pyeval offers it — and for a .npy program it
    always does. pyvar_callv<n>(callee, args...) tells the four callable shapes
    apart ITSELF (see its comment in pyeval.pas), replacing unbox-then-indirect
    plus a stack of compile-time tag guesses. It is also what makes a LAMBDA
    bound to a name callable: a lambda's value is a closure or bound-fn OBJECT,
    which no tag guard recognised. Arities past 3 keep the old lowering. }
  dispPi := -1;
  if n = 0 then dispPi := FindProc('pyvar_callv0')
  else if n = 1 then dispPi := FindProc('pyvar_callv1')
  else if n = 2 then dispPi := FindProc('pyvar_callv2')
  else if n = 3 then dispPi := FindProc('pyvar_callv3');
  if dispPi >= 0 then
  begin
    dispArg := AllocNode(AN_ARG);
    ASTLeft[dispArg] := baseNode;
    ASTRight[dispArg] := argsHead;
    Result := AllocNode(AN_CALL);
    ASTIVal[Result] := dispPi;
    ASTLeft[Result] := dispArg;
    ASTTk[Result] := Ord(tyVariant);
    Exit;
  end;

  sigPi := PyDynCallSig(n);
  Result := AllocNode(AN_CALL_IND);
  ASTLeft[Result]  := argsHead;
  ASTRight[Result] := unboxCall;         { code address }
  ASTIVal[Result]  := sigPi;
  ASTTk[Result]    := Ord(tyVariant);
  ASTSLen[Result]  := 0;                 { plain proc pointer, no Self }

  { Reverse bridge for pyeval closures. `word.native(vm2)` may hold either a
    compiled NilPy function value (a raw proc address — the default AN_CALL_IND
    above) OR a pyeval closure captured from a PYTHON block's nested `def`
    (uforth's VARIABLE/CONSTANT words). The latter is boxed as a VT_PYCLOSURE
    (tag 9) whose payload is a closure index, not a code pointer, so unboxing it
    as an address would crash. Branch at runtime: tag 9 -> PyClosureCall1;
    everything else -> the fast indirect call. Only the 1-arg shape is emitted
    (every uforth native word is `native(vm)`); other arities keep the plain
    path. baseNode is re-used across the guard and both arms — it is a field/var
    read here, so evaluating it more than once is safe (same idiom as
    PyMakeTruthy / PyMakeBoolOpValue). }
  { A function VALUE (tag 8) reaches the same place with a {code, recv} pair
    payload — see PyWrapBoundDynCall. Applied first so the closure guard, when
    it fires, wraps the whole thing. }
  Result := PyWrapBoundDynCall(baseNode, argsHead, n, Result);

  if n = 1 then
    Result := PyWrapClosureDynCall(baseNode, ASTLeft[argsHead], Result);
end;

{ Wrap a call through a `Callable[...]`-annotated PARAMETER so a heap callable
  works. The annotation registers a $proctype signature and the call lowers to a
  typed INDIRECT call — correct for a compiled def, fatal for a lambda or a
  closure, whose value is an OBJECT pointer: the call jumped into the object's
  own bytes. Builds `pycallable_obj_is(f) ? pyvar_callv<n>(f, args...) :
  <the indirect call>`, so the fast path is untouched and the object path goes
  to the same universal dispatcher a variant callee already uses
  (bug-nilpy-callable-annotated-param-segfaults-on-a-heap-callable).

  calleeNode is re-read across the guard and both arms — it is a plain variable
  here, so evaluating it twice is free of side effects (the same rule
  PyWrapClosureFieldCall / PyMakeTruthy follow). Returns defCall unchanged for
  arities past 3 or when pylib is not loaded. }
function PyWrapHeapCallableCall(calleeNode, argsHead, n, defCall: Integer): Integer;
var isArg, isCall, dispArg, thenCall, pair, tern, isPi, dispPi: Integer;
begin
  PyWrapHeapCallableCall := defCall;
  if n > 3 then Exit;
  isPi := FindProc('pycallable_obj_is');
  if isPi < 0 then Exit;
  dispPi := -1;
  if n = 0 then dispPi := FindProc('pyvar_callv0')
  else if n = 1 then dispPi := FindProc('pyvar_callv1')
  else if n = 2 then dispPi := FindProc('pyvar_callv2')
  else if n = 3 then dispPi := FindProc('pyvar_callv3');
  if dispPi < 0 then Exit;

  isArg := AllocNode(AN_ARG); ASTLeft[isArg] := calleeNode; ASTRight[isArg] := -1;
  isCall := AllocNode(AN_CALL);
  ASTIVal[isCall] := isPi; ASTLeft[isCall] := isArg; ASTTk[isCall] := Ord(tyBoolean);

  dispArg := AllocNode(AN_ARG);
  ASTLeft[dispArg] := calleeNode;
  ASTRight[dispArg] := argsHead;
  thenCall := AllocNode(AN_CALL);
  ASTIVal[thenCall] := dispPi; ASTLeft[thenCall] := dispArg;
  ASTTk[thenCall] := Ord(tyVariant);

  pair := AllocNode(AN_PAIR);
  ASTLeft[pair] := thenCall; ASTRight[pair] := defCall;
  tern := AllocNode(AN_TERNARY);
  ASTLeft[tern] := isCall; ASTRight[tern] := pair; ASTTk[tern] := Ord(tyVariant);
  PyWrapHeapCallableCall := tern;
end;

{ `obj.method` used as a VALUE (no following call): capture it as a bound-method
  variant so the receiver is not dropped. pybound_new(@method, self) boxes
  {code, recv}; the receiver is passed by ADDRESS-as-value (an object reference is
  already a pointer). See feature-nilpy-bound-method-value: uforth's exec env
  binds `self.push`/`self.pop` this way. mpi is the method proc (param 0 = Self);
  selfNode supplies the receiver. }
function PyMakeBoundMethod(mpi, selfNode: Integer): Integer;
var procAddr, recvArg, selfArg, callNode, boundPi: Integer;
begin
  boundPi := FindProc('pybound_new');
  if boundPi < 0 then Error('Nil Python: pylib (pybound_new) not loaded');
  procAddr := AllocNode(AN_PROCADDR);
  ASTIVal[procAddr] := mpi;
  ASTTk[procAddr]   := Ord(tyPointer);
  callNode := AllocNode(AN_CALL);
  ASTIVal[callNode] := boundPi;
  ASTTk[callNode]   := Ord(tyVariant);
  selfArg := AllocNode(AN_ARG);  ASTLeft[selfArg] := procAddr;   { code }
  recvArg := AllocNode(AN_ARG);  ASTLeft[recvArg] := selfNode;   { recv }
  ASTRight[selfArg] := recvArg;  ASTRight[recvArg] := -1;
  ASTLeft[callNode] := selfArg;
  Result := callNode;
end;

{ `v.field(args)` where `v` is a VARIANT and `field` holds a function value:
  unbox to the owning class, read the field, call through it. }
function PyMakeVariantFieldCall(baseNode, ci: Integer; const fname: AnsiString;
                                sigPi: Integer): Integer;
var unboxArg, unboxCall, castNode, fieldNode, argsHead, lastArg, argNode, n: Integer;
begin
  unboxArg := AllocNode(AN_ARG);
  ASTLeft[unboxArg] := baseNode;
  unboxCall := AllocNode(AN_CALL);
  ASTIVal[unboxCall] := FindProc('pyvarobj');
  if ASTIVal[unboxCall] < 0 then Error('Nil Python: pylib (pyvarobj) not loaded');
  ASTTk[unboxCall] := Ord(tyPointer);
  ASTLeft[unboxCall] := unboxArg;
  castNode := AllocNode(AN_CLASS_CAST);
  ASTLeft[castNode] := unboxCall;
  ASTIVal[castNode] := ci;
  ASTTk[castNode]   := Ord(tyClass);
  fieldNode := AllocNode(AN_FIELD);
  ASTLeft[fieldNode] := castNode;
  ASTSOffset[fieldNode] := PyStoredName(fname);
  ASTSLen[fieldNode] := Length(fname);
  ASTTk[fieldNode] := Ord(tyPointer);
  Expect(tkLParen, '(');
  argsHead := -1; lastArg := -1; n := 0;
  while CurTok.Kind <> tkRParen do
  begin
    ParseArgExpr;
    argNode := AllocNode(AN_ARG);
    ASTLeft[argNode] := CurASTNode;
    if argsHead = -1 then argsHead := argNode else ASTRight[lastArg] := argNode;
    lastArg := argNode;
    Inc(n);
    if CurTok.Kind = tkComma then Next else Break;
  end;
  Expect(tkRParen, ')');
  if n <> Procs[sigPi].ParamCount then
    Error('Nil Python: .' + fname + '() takes ' +
          PyIntLiteralText(Procs[sigPi].ParamCount) + ' argument(s)');
  Result := AllocNode(AN_CALL_IND);
  ASTLeft[Result]  := argsHead;
  ASTRight[Result] := fieldNode;
  ASTIVal[Result]  := sigPi;
  ASTTk[Result]    := Ord(Procs[sigPi].RetType);
  ASTSLen[Result]  := 0;

  { A Callable field may hold a pyeval closure (uforth's VARIABLE/CONSTANT native
    words) rather than a compiled function address; branch at runtime. Only the
    1-arg `-> None` shape (every uforth native word: `native(vm)`) is wrapped. }
  if (n = 1) and (Procs[sigPi].RetType = tyInteger) then
    Result := PyWrapClosureFieldCall(fieldNode, ASTLeft[argsHead], Result);
end;

{ `w.meth(args)` where `w` is a VARIANT — a for-in loop variable, a list/dict
  element, anything living in a 16-byte variant slot. Python dispatches on the
  RUNTIME type; pxx resolves methods against the receiver's STATIC class, and a
  variant slot records no class identity, so the form used to be a parse error
  (bug-a-nilpy-method-call-on-variant-receiver) and "iterate a list of objects,
  call a method" — an utterly ordinary Python shape — was unavailable.

  Resolution is by METHOD NAME across the declared classes: the slot's VT_OBJECT
  payload is the instance pointer (unboxed with pylib's pyvarobj) and is hard-cast
  to the one class that declares `mname`. When several unrelated classes declare
  the same name the call is genuinely ambiguous without a runtime class tag in the
  slot, and that is an error telling the user to annotate a typed local. A method
  declared once and INHERITED is not ambiguous — the candidates then agree on one
  proc index, and a virtual method still dispatches through the VMT at runtime,
  so a subclass instance in the slot runs its own override. }
{ Is `ci` one of pylib's built-in container classes (list/dict/bytes)? Used to
  break a variant-method tie toward a USER class. }
function PyIsPylibContainerCi(ci: Integer): Boolean;
begin
  Result := (ci = FindUClass('TPyList')) or (ci = FindUClass('TPyDict')) or
            (ci = FindUClass('TPyBytes'));
end;

{ Does proc mpi declare a parameter with this name? Slot 0 is Self on a method,
  so the scan starts at 1 — `self=` is not bindable by name. }
function PyProcParamNamed(mpi: Integer; const nm: AnsiString): Boolean;
var i: Integer;
begin
  Result := False;
  if mpi < 0 then Exit;
  for i := 1 to Procs[mpi].ParamCount - 1 do
    if CaseEqual(Procs[mpi].Params[i].Name, nm) then
    begin
      Result := True;
      Exit;
    end;
end;

{ `<class expr>.name(args)` where the receiver's class is KNOWN — the suffix a
  fresh construction needs (`NoteCountingDetector().analyze(chords, fn)`).
  ParseFactorCore handles this for an IDENT receiver, but a construction leaves
  the core through the ctor intercept, so the postfix never ran and
  `Cls().m()` was a parse error (bug-nilpy-method-call-on-fresh-construction).
  CurTok is the '(' and the method name has been consumed. }
{ Does this class have a parent, or any subclass? Only then does a virtual call
  mean anything for a receiver of exactly this class. }
function PyClassInHierarchy(ci: Integer): Boolean;
var i: Integer;
begin
  Result := UClsParent[ci] >= 0;
  if Result then Exit;
  for i := 0 to UClsCount - 1 do
    if UClsParent[i] = ci then
    begin
      Result := True;
      Exit;
    end;
end;

{ Find an overload of `nm` whose every parameter is ALREADY tyVariant --
  i.e. one that dispatches correctly regardless of what shape the argument
  actually is at runtime, the way `len`'s `(const v: Variant): Integer`
  overload does. FindProc alone is first-match, arity-blind: `len`'s FIRST
  declared overload is `(b: TPyBytes): Integer`, so a naive
  `FindProc('len')` used as `f = len; f("hi")` would silently misread a
  string as a TPyBytes handle. Only the return type may still be non-Variant
  (that half is what PyGetOrMakeCallableWrapper adapts).
  feature-nilpy-callable-value-unified-dispatch }
function PyFindVariantParamOverload(const nm: AnsiString; wantArity: Integer): Integer;
var i, j: Integer; ok: Boolean;
begin
  Result := -1;
  for i := 0 to ProcCount - 1 do
  begin
    if not CaseEqual(Procs[i].Name, nm) then Continue;
    if Procs[i].ParamCount <> wantArity then Continue;
    ok := True;
    for j := 0 to wantArity - 1 do
      if Procs[i].Params[j].TypeKind <> tyVariant then begin ok := False; Break; end;
    if ok then begin Result := i; Exit; end;
  end;
end;

{ TRUE for a return type that is meaningful to box into a Variant result --
  a genuine scalar/string value a real FUNCTION computed. A `-> None` def
  (or any procedure with nothing to return) types tyUnknown here, and
  wrapping THAT crashed: `def hit(vm) -> None: print(...)` used as a
  dataclass field value (`native=hit`) got wrapped, the wrapper's
  `return hit(a0)` tried to store hit's (nonexistent) result into
  $pyresult, and calling it through the field (`w.native(x)`) segfaulted
  right after hit's own body ran. A void proc already has a working
  calling convention through the EXISTING mechanisms (PyWrapClosureFieldCall
  and friends); only a genuine value-returning non-Variant result needs
  this wrapper at all.
  feature-nilpy-callable-value-unified-dispatch }
function PyScalarWrappableRetType(tk: TTypeKind): Boolean;
begin
  Result := tk in [tyInteger, tyInt64, tyDouble, tySingle, tyExtended,
                   tyBoolean, tyAnsiString, tyString, tyChar];
end;

{ realPi already has an all-Variant PARAMETER list (the caller found it via
  PyFindVariantParamOverload, or it is a NilPy-source def PyDefUsedAsValue
  already normalised) but its RETURN type is not tyVariant -- a plain Pascal
  scalar/string/class result, returned in a register or via its OWN type's
  convention, not the Variant hidden-destination-pointer one every callable-
  value dispatcher (pyvar_callv1, PyCallKey1, pycallback_call1, ...) assumes.
  Synthesizes (and caches, by NAME, so repeated captures of the same proc
  share one wrapper) a `function $pycallwrap_N(const a0: Variant): Variant`
  whose body is `return realPi(a0)` -- built as AST, not parsed source, by
  PyCompileLambdaBody's bStart=-1 branch, queued on the SAME lambda-body
  queue (same timing requirement: compiled once CurProc is safely
  restorable). The ordinary call-argument coercion (Variant -> whatever
  realPi's own param type is) and return coercion (whatever it returns ->
  Variant) apply completely unchanged; nothing here does any unboxing
  itself. Only arity 1 today -- covers `key=`/`cmp=`-shaped single-argument
  callables, which is everything this ticket's own repro and the sorted()
  fix need; a multi-arg builtin captured as a bare value still gets the
  unsafe direct address (unchanged pre-existing behaviour) rather than a
  half-finished wrapper.
  feature-nilpy-callable-value-unified-dispatch }
function PyGetOrMakeCallableWrapper(realPi: Integer): Integer;
var wrapName: AnsiString; wrapPi: Integer;
    pnames: array[0..0] of AnsiString; ptypes: array[0..0] of TTypeKind;
begin
  wrapName := '$pycallwrap_' + AIntToStr(realPi);
  wrapPi := FindProc(wrapName);
  if wrapPi >= 0 then begin Result := wrapPi; Exit; end;
  pnames[0] := 'a0';
  ptypes[0] := tyVariant;
  wrapPi := RegisterProc(wrapName, True, tyVariant, 1, pnames, ptypes);
  Procs[wrapPi].BodyAddr := -1;
  if PyPendLamCount >= PY_MAX_NESTED then
    Error('Nil Python: too many pending callable-value wrappers/lambdas');
  PyPendLamTok[PyPendLamCount] := -1;    { sentinel: hand-built body, not parsed }
  PyPendLamProc[PyPendLamCount] := wrapPi;
  PyPendLamWrapReal[PyPendLamCount] := realPi;
  Inc(PyPendLamCount);
  Result := wrapPi;
end;

function PyMakeFuncValue: Integer;
{ A bare def NAME in a value position — `w.bind(seq, on_plain)`, `sorted(l,
  key=cmp)`. Python's function object; NilPy already builds one for a bound
  METHOD (pybound_new with the receiver), so a plain def is the same pair with
  a nil receiver and every consumer (pycallback_call*, the tkinter dispatcher)
  handles both. Returns -1 when the token is not a def name, so callers fall
  through to their existing handling. CurTok is the identifier. }
var pi, procAddr, argA, argB, callNode, nilNode, boundPi, altPi, wpj: Integer;
    paramsAllVariant: Boolean;
begin
  Result := -1;
  if not isNilPy then Exit;
  if CurTok.Kind <> tkIdent then Exit;
  if (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) then Exit;  { a CALL }
  if FindSym(CurTok.SVal) >= 0 then Exit;                                 { a variable }
  { A NESTED def is registered under its enclosing qualifier (`A.build.on_resize`),
    so an unqualified FindProc lands on the bodyless shell the pre-pass made —
    and its address is a plausible-looking pointer one byte below the entry
    point, which crashes the first time the callback fires. Look up the
    qualified name first. }
  pi := -1;
  if PyNestPrefix <> '' then pi := FindProc(PyNestPrefix + '.' + CurTok.SVal);
  if pi < 0 then pi := FindProc(CurTok.SVal);
  if pi < 0 then Exit;
  { The first FindProc match may not be the SAFE overload: `len`'s first
    declared one takes a TPyBytes, not a Variant, and a wrapper built around
    the wrong overload would silently misread a string argument as a bytes
    handle. Prefer a same-arity, all-Variant-parameter overload of the same
    name if one exists (a NilPy-source def has only one registration, so
    this is a no-op for it). If its return isn't ALSO already tyVariant --
    the shape a plain Pascal builtin like `len` always has, since the
    Variant-hidden-destination-pointer convention every callable-value
    dispatcher assumes is a NilPy-def-only convention -- synthesize a
    wrapper that adapts just the return side. A proc with no all-Variant-
    parameter overload at all (or the wrong arity) is left exactly as
    before: still the pre-existing, unwrapped, possibly-unsafe value.
    feature-nilpy-callable-value-unified-dispatch }
  altPi := PyFindVariantParamOverload(CurTok.SVal, Procs[pi].ParamCount);
  if altPi >= 0 then pi := altPi;
  if Procs[pi].RetType <> tyVariant then
  begin
    paramsAllVariant := True;
    for wpj := 0 to Procs[pi].ParamCount - 1 do
      if Procs[pi].Params[wpj].TypeKind <> tyVariant then
      begin
        paramsAllVariant := False;
        Break;
      end;
    if paramsAllVariant and (Procs[pi].ParamCount = 1) and
       Procs[pi].IsFunc and PyScalarWrappableRetType(Procs[pi].RetType) then
      pi := PyGetOrMakeCallableWrapper(pi);
  end;
  boundPi := FindProc('pybound_new');
  if boundPi < 0 then Exit;
  procAddr := AllocNode(AN_PROCADDR);
  ASTIVal[procAddr] := pi;
  ASTTk[procAddr] := Ord(tyPointer);
  nilNode := AllocNode(AN_INT_LIT);
  ASTIVal[nilNode] := 0;
  ASTTk[nilNode] := Ord(tyPointer);
  argA := AllocNode(AN_ARG); ASTLeft[argA] := procAddr;
  argB := AllocNode(AN_ARG); ASTLeft[argB] := nilNode; ASTRight[argB] := -1;
  ASTRight[argA] := argB;
  callNode := AllocNode(AN_CALL);
  ASTIVal[callNode] := boundPi;
  ASTTk[callNode] := Ord(tyVariant);
  ASTLeft[callNode] := argA;
  Next;                      { consume the name }
  Result := callNode;
end;

function PyEvalOnce(node: Integer): Integer;
{ Bind an expression to a hidden temp through a hoisted assignment and yield the
  temp. For a value used in more than one place: the AST is a TREE, so a node
  referenced twice is EMITTED twice — a call receiver in a chain ran its call
  once per link (`b.add(2).add(3)` performed add(2) twice). The temp also pins
  Python's evaluation order: the receiver is computed before the member. }
var sym, asgn: Integer;
begin
  PyEvalOnce := node;
  if node < 0 then Exit;
  sym := AllocVar(PyHiddenName('recv'), IntToTypeKind(ASTTk[node]));
  Syms[sym].RecName := ResolveNodeRec(node);
  asgn := AllocNode(AN_ASSIGN);
  ASTLeft[asgn] := PyMakeIdent(sym);
  ASTRight[asgn] := node;
  PyHoistStmt(asgn);
  PyEvalOnce := PyMakeIdent(sym);
end;

function PyDynAttrEverAssigned(const nm: AnsiString): Boolean;
{ Does the module write `<expr>.nm = ...` anywhere, or call setattr at all? Then
  `nm` may legitimately be a DYNAMIC attribute on an instance — Python adds them
  at run time — and a call through it cannot be refused at compile time. Used the
  other way round from PyMethodUsedAsValue: this one licenses a name the class
  does not declare, that one detects a value use of one it does. }
var j: Integer;
begin
  Result := False;
  j := 1;
  while j < MainProgramTokCount do
  begin
    if (Tokens[j].Kind = tkIdent) and CaseEqual(GetTokenStr(j), 'setattr') then
    begin
      Result := True;
      Exit;
    end;
    if (Tokens[j].Kind = tkIdent) and (Tokens[j - 1].Kind = tkDot) and
       (j + 1 < MainProgramTokCount) and (Tokens[j + 1].Kind = tkAssign) and
       CaseEqual(GetTokenStr(j), nm) then
    begin
      Result := True;
      Exit;
    end;
    Inc(j);
  end;
end;

function PyMethodUsedAsValue(const nm: AnsiString): Boolean;
{ True iff the module reads `<something>.nm` WITHOUT calling it — `cb = self.on_key`,
  `root.after(50, self.tick)`. That is a bound-method value, and calling one back
  goes through the function-object ABI (variant parameters, variant result), the
  same normalisation PyDefUsedAsValue applies to a plain def. Without it the pair
  carried a method whose result came back in a register while the caller expected
  the hidden-destination convention: a bound method returning a value crashed,
  and one returning None happened to work.

  Keyed on the NAME alone, not on the class, which is what keeps an override and
  its base in step — both are normalised or neither is. A same-named ATTRIBUTE
  read elsewhere in the module normalises a method that did not need it; the cost
  is boxing, and the two passes still agree, so it stays correct. }
var j: Integer;
begin
  Result := False;
  if nm = '' then Exit;
  j := 1;
  while j < MainProgramTokCount do
  begin
    if (Tokens[j].Kind = tkIdent) and (Tokens[j - 1].Kind = tkDot) and
       CaseEqual(GetTokenStr(j), nm) then
    begin
      { a CALL (`o.m(...)`) or an attribute STORE (`o.m = x`) is not a value read }
      if (j + 1 >= MainProgramTokCount) or
         (not (Tokens[j + 1].Kind in [tkLParen, tkAssign])) then
      begin
        Result := True;
        Exit;
      end;
    end;
    Inc(j);
  end;
end;

function PyNoClassDeclares(const mname: AnsiString): Boolean;
{ True when no declared class has a method of this name. }
var ci: Integer;
begin
  Result := True;
  for ci := 0 to UClsCount - 1 do
    if (not UClsIsRecord[ci]) and (FindUMeth(ci, mname) >= 0) then
    begin
      Result := False;
      Exit;
    end;
end;

function PyPromoteOverloadByKw(ci, mmi: Integer; const mname: AnsiString): Integer;
{ Pick the same-class OVERLOAD a keyword argument names. `Widget.bind(seq,
  script)` and `Widget.bind(seq, callback, add)` are two methods of one name, and
  FindUMeth hands back whichever was declared first; a call written
  `bind(seq, cb, add="+")` then failed with "no parameter named add". The
  keyword identifies the intended signature, exactly as it does for the
  across-classes promotion in PyParseVariantMethod.

  CurTok is the '(' of the call. Returns the better mmi, or the one given. }
var k, depth, di, cand, curr: Integer; pname: AnsiString;
begin
  Result := mmi;
  if (ci < 0) or (mmi < 0) or (CurTok.Kind <> tkLParen) then Exit;
  k := TokPos; depth := 1;
  while (k < TokCount) and (depth > 0) do
  begin
    if Tokens[k].Kind = tkLParen then Inc(depth)
    else if Tokens[k].Kind = tkRParen then Dec(depth)
    else if (depth = 1) and (Tokens[k].Kind = tkIdent) and (k + 1 < TokCount) and
            (Tokens[k + 1].Kind = tkAssign) and
            (not PyProcParamNamed(UMthProc_[Result], GetTokenStr(k))) then
    begin
      pname := GetTokenStr(k);
      { up the PARENT CHAIN too: a NilPy class that subclasses a façade widget
        inherits both overloads, and only the base declares them. }
      curr := ci;
      while curr >= 0 do
      begin
        for di := 0 to UClsMCount[curr] - 1 do
        begin
          cand := UClsMBase[curr] + di;
          if UNameMatch(UMthNOff[cand], UMthNLen[cand], ULower(mname)) and
             PyProcParamNamed(UMthProc_[cand], pname) then
          begin
            Result := cand;
            curr := -1;
            Break;
          end;
        end;
        if curr >= 0 then curr := UClsParent[curr];
      end;
    end;
    Inc(k);
  end;
end;

{ `obj.m(*xs)` — a STARRED argument in a method call, expanded into the callee's
  remaining declared parameters. Unlike the free-function forwarding path
  (PyStarForwardCall in parser.inc, which dispatches on len(args) at run time to
  keep defaults working), the arity here is settled at compile time: each
  remaining parameter becomes one pystar_arg(list, k) read into a hidden variant
  local, guarded by a single pystar_check_arity. A callee with DEFAULTS in the
  starred range is refused rather than filled with None — silently dropping a
  default would be wrong output, not a missing feature.
  `selfSlots` is 1 for a method (Self is parameter 0), 0 for a plain proc;
  `given` is the number of arguments already parsed, and is advanced.
  The caller has NOT yet consumed the '*'. }
{ The star operand as a TPyList. A VARIANT holding a list must be UNBOXED
  first: stored straight into a class slot it lands there as the variant's raw
  tag+payload, and the arity guard then read a nonsense count
  (`forwarded call got -2102166800 arguments`). `*ast.literal_eval(...)` is the
  shape — anything dynamic is a variant, and only a statically-typed list
  worked. }
function PyStarOperandAsList(node, listCi: Integer): Integer;
var unboxArg, unboxCall: Integer;
begin
  if IntToTypeKind(ASTTk[node]) <> tyVariant then
  begin
    PyStarOperandAsList := node;
    Exit;
  end;
  unboxArg := AllocNode(AN_ARG);
  ASTLeft[unboxArg] := node;
  ASTRight[unboxArg] := -1;
  unboxCall := AllocNode(AN_CALL);
  ASTIVal[unboxCall] := FindProc('pyvarobj');
  if ASTIVal[unboxCall] < 0 then Error('Nil Python: pylib (pyvarobj) not loaded');
  ASTTk[unboxCall] := Ord(tyPointer);
  ASTLeft[unboxCall] := unboxArg;
  PyStarOperandAsList := AllocNode(AN_CLASS_CAST);
  ASTLeft[PyStarOperandAsList] := unboxCall;
  ASTIVal[PyStarOperandAsList] := listCi;
  ASTTk[PyStarOperandAsList] := Ord(tyClass);
end;

procedure PyStarExpandCallArgs(procIdx, firstSlot: Integer;
                               var headArg, lastArg: Integer);
var listCi, listSym, asgn, total, required, wanted, k: Integer;
    slotSym, elemNode, idxArg, callNode, argNode, a2, a3, chkArg: Integer;
begin
  listCi := FindUClass('TPyList');
  if listCi < 0 then Error('Nil Python: pylib (TPyList) not loaded');
  Next;                          { the '*' }
  PyParseBoolExpr;
  listSym := AllocVar(PyHiddenName('starl'), tyClass);
  Syms[listSym].RecName := REC_UCLASS_BASE + listCi;
  asgn := AllocNode(AN_ASSIGN);
  ASTLeft[asgn] := PyMakeIdent(listSym);
  ASTRight[asgn] := PyStarOperandAsList(CurASTNode, listCi);
  PyHoistStmt(asgn);

  total := Procs[procIdx].ParamCount;
  required := total;
  while (required > 0) and (required - 1 < MAX_PROC_PARAMS) and
        ProcParamHasDefault[procIdx * MAX_PROC_PARAMS + (required - 1)] do
    Dec(required);
  wanted := total - firstSlot;
  if wanted <= 0 then
    Error('Nil Python: *unpacking has no parameter left to fill in .'
          + Procs[procIdx].Name + '()');
  if required < total then
    Error('Nil Python: *unpacking into ' + Procs[procIdx].Name
          + ' is not supported — it has parameters with defaults, whose values '
          + 'a compile-time expansion cannot preserve');

  { one guard: the list must hold exactly the slots being filled }
  chkArg := AllocNode(AN_ARG);
  ASTLeft[chkArg] := PyMakeIdent(listSym);
  a2 := AllocNode(AN_ARG);
  ASTLeft[a2] := AllocNode(AN_INT_LIT);
  ASTIVal[ASTLeft[a2]] := wanted;
  ASTTk[ASTLeft[a2]] := Ord(tyInteger);
  a3 := AllocNode(AN_ARG);
  ASTLeft[a3] := AllocNode(AN_INT_LIT);
  ASTIVal[ASTLeft[a3]] := wanted;
  ASTTk[ASTLeft[a3]] := Ord(tyInteger);
  ASTRight[chkArg] := a2;
  ASTRight[a2] := a3;
  callNode := AllocNode(AN_CALL);
  ASTIVal[callNode] := FindProc('pystar_check_arity');
  if ASTIVal[callNode] < 0 then Error('Nil Python: pylib (pystar_check_arity) not loaded');
  ASTTk[callNode] := Ord(tyInteger);
  ASTLeft[callNode] := chkArg;
  PyHoistStmt(callNode);

  for k := 0 to wanted - 1 do
  begin
    slotSym := AllocVar(PyHiddenName('stara'), tyVariant);
    elemNode := AllocNode(AN_ARG);
    ASTLeft[elemNode] := PyMakeIdent(listSym);
    idxArg := AllocNode(AN_ARG);
    ASTLeft[idxArg] := AllocNode(AN_INT_LIT);
    ASTIVal[ASTLeft[idxArg]] := k;
    ASTTk[ASTLeft[idxArg]] := Ord(tyInteger);
    ASTRight[elemNode] := idxArg;
    callNode := AllocNode(AN_CALL);
    ASTIVal[callNode] := FindProc('pystar_arg');
    if ASTIVal[callNode] < 0 then Error('Nil Python: pylib (pystar_arg) not loaded');
    ASTTk[callNode] := Ord(tyVariant);
    ASTLeft[callNode] := elemNode;
    asgn := AllocNode(AN_ASSIGN);
    ASTLeft[asgn] := PyMakeIdent(slotSym);
    ASTRight[asgn] := callNode;
    PyHoistStmt(asgn);

    argNode := AllocNode(AN_ARG);
    ASTLeft[argNode] := PyMakeIdent(slotSym);
    ASTIVal[argNode] := 0;
    ASTRight[argNode] := -1;
    if lastArg < 0 then headArg := argNode else ASTRight[lastArg] := argNode;
    if headArg < 0 then headArg := argNode;
    lastArg := argNode;
  end;
end;

{ Is there a top-level `*expr` (single star, not `**`) left in the argument list
  being parsed? Scanned from the current token to the ')' that closes it, so a
  star anywhere in the list — not only in first position — routes the whole call
  through the unpacking path. }
function PyStarArgAhead: Boolean;
var i, depth: Integer;
begin
  Result := (CurTok.Kind = tkStar) and (TokPos < TokCount) and
            (Tokens[TokPos].Kind <> tkStar);
  if Result then Exit;
  depth := 0;
  i := TokPos;
  while i < TokCount do
  begin
    if Tokens[i].Kind in [tkLParen, tkLBrack, tkBegin] then Inc(depth)
    else if Tokens[i].Kind in [tkRBrack, tkEnd] then Dec(depth)
    else if Tokens[i].Kind = tkRParen then
    begin
      if depth = 0 then Exit;
      Dec(depth);
    end
    else if (depth = 0) and (Tokens[i].Kind = tkStar) and
            (i + 1 < TokCount) and (Tokens[i + 1].Kind <> tkStar) and
            (i > 0) and (Tokens[i - 1].Kind in [tkComma, tkLParen]) then
    begin
      Result := True;
      Exit;
    end;
    Inc(i);
  end;
end;

{ A METHOD call whose argument list contains a `*expr` unpack. The arity-driven
  Pascal loop in parser.inc cannot parse it (a star is not an expression), so it
  hands the whole list here — the mirror of PyParseStarMethodArgs, which does the
  same for a callee that DECLARES *args. }
procedure PyStarUnpackMethodArgs(mpi, mcallNode: Integer; var mlastArg, mai: Integer);
var argNode, kwIdx, head, cnt: Integer;
begin
  head := ASTLeft[mcallNode];
  cnt := 1;                          { Self occupies parameter 0 }
  while CurTok.Kind <> tkRParen do
  begin
    if (CurTok.Kind = tkStar) and (TokPos < TokCount) and
       (Tokens[TokPos].Kind <> tkStar) then
    begin
      PyStarExpandCallArgs(mpi, cnt, head, mlastArg);
      cnt := Procs[mpi].ParamCount;
      if CurTok.Kind = tkComma then
        Error('Nil Python: an argument after *unpacking is not supported yet');
      Break;
    end;
    kwIdx := PyKwArgIndex(mpi, 1);
    ParseArgExpr;
    argNode := AllocNode(AN_ARG);
    ASTLeft[argNode] := CurASTNode;
    ASTIVal[argNode] := kwIdx;
    ASTRight[argNode] := -1;
    if mlastArg < 0 then ASTLeft[mcallNode] := argNode
    else ASTRight[mlastArg] := argNode;
    if head < 0 then head := argNode;
    mlastArg := argNode;
    Inc(cnt);
    if CurTok.Kind = tkComma then Next else Break;
  end;
  ASTLeft[mcallNode] := head;
  mai := Procs[mpi].ParamCount;
end;

function PyParseClassMethodCall(baseNode, ci: Integer; const mname: AnsiString): Integer;
var mmi, mpi, selfArg, lastArg, argNode, callNode, n, k, kwIdx: Integer;
    anyKw: Boolean;
begin
  mmi := FindUMeth(ci, mname);
  if mmi < 0 then
    Error('Nil Python: ' + PyRawName(UClsNOff[ci], UClsNLen[ci]) + ' has no method .' + mname + '()');
  mmi := PyPromoteOverloadByKw(ci, mmi, mname);
  selfArg := AllocNode(AN_ARG);
  ASTLeft[selfArg] := baseNode;
  ASTRight[selfArg] := -1;
  lastArg := selfArg;
  mpi := UMthProc_[mmi];
  Expect(tkLParen, '(');
  n := 0;
  anyKw := False;
  while CurTok.Kind <> tkRParen do
  begin
    { keyword arguments here too — `WeightedDetector().analyze(rs, weights=w)`.
      Slot 0 is Self, so the name scan starts at 1, exactly as the ordinary
      method path does. }
    { `c.setStrokeColorRGB(*rgb)` — a starred argument is not an expression, so
      it is diverted before ParseArgExpr ever sees the '*'. }
    if (CurTok.Kind = tkStar) and (TokPos < TokCount) and
       (Tokens[TokPos].Kind <> tkStar) and (ProcPyStarIdx[mpi] < 0) then
    begin
      k := selfArg;
      PyStarExpandCallArgs(mpi, n + 1, k, lastArg);
      n := Procs[mpi].ParamCount - 1;
      Break;
    end;
    kwIdx := PyKwArgIndex(mpi, 1);
    if kwIdx <> 0 then anyKw := True;
    ParseArgExpr;
    argNode := AllocNode(AN_ARG);
    ASTLeft[argNode] := CurASTNode;
    ASTIVal[argNode] := kwIdx;
    ASTRight[argNode] := -1;
    ASTRight[lastArg] := argNode;
    lastArg := argNode;
    Inc(n);
    if CurTok.Kind = tkComma then Next else Break;
  end;
  Expect(tkRParen, ')');
  { `*args` / `**kwargs` on a METHOD: pack the surplus arguments before the
    keyword bind, exactly as the top-level call path does. Self occupies slot 0
    of the parameter list, so the counter is passed INCLUDING it and the
    argument count is re-derived afterwards. }
  if (ProcPyStarIdx[mpi] >= 0) or (ProcPyKwIdx[mpi] >= 0) then
  begin
    n := n + 1;
    PyPackStarArgs(mpi, selfArg, lastArg, n);
    if n > 0 then Dec(n);
    anyKw := False;   { the packing consumed every keyword argument }
  end;
  if anyKw then
  begin
    n := 0;
    PyBindKwArgs(mpi, selfArg, lastArg, n);
    if n > 0 then Dec(n);                { drop Self from the argument count }
  end;
  { pick the overload by the argument count written, then fill the callee's
    remaining DEFAULTED parameters, exactly as the ordinary call path does }
  k := FindUMethArity(ci, mname, n);
  if k >= 0 then mmi := k;
  mpi := UMthProc_[mmi];
  k := n + 1;
  while (k < Procs[mpi].ParamCount) and (k < MAX_PROC_PARAMS) and
        ProcParamHasDefault[mpi * MAX_PROC_PARAMS + k] do
  begin
    argNode := AllocNode(AN_ARG);
    ASTLeft[argNode] := DefaultArgValueNode(mpi, k);
    ASTRight[argNode] := -1;
    ASTRight[lastArg] := argNode;
    lastArg := argNode;
    Inc(k);
  end;
  { VIRTUAL dispatch only when the class actually participates in a hierarchy.
    NilPy classes that merely SHARE a method name (songformatter has eight
    unrelated detector classes each declaring analyze) still get virtual slots,
    which costs a VMT indirection for nothing. For a receiver whose exact class is
    known and that has neither parent nor children, a DIRECT call is what Python
    means anyway: the method is resolved on that very type. }
  if (UMthVirSlot[mmi] >= 0) and PyClassInHierarchy(ci) then
  begin
    callNode := AllocNode(AN_VIRTUAL_CALL);
    ASTRight[callNode] := UMthVirSlot[mmi];
  end
  else
    callNode := AllocNode(AN_CALL);
  ASTIVal[callNode] := mpi;
  ASTTk[callNode] := Ord(Procs[mpi].RetType);
  { ASTRight is NOT the place for the return's rec id here: on an
    AN_VIRTUAL_CALL it holds the VMT SLOT, and writing the rec id over it sent
    the call through a garbage slot — `A().make()` returning a class segfaulted
    while the bound-variable form was fine. ResolveNodeRec already reads a
    call's class from ProcRetRecId, so nothing needs to be stored. }
  ASTLeft[callNode] := selfArg;
  Result := callNode;
end;

function PyParseVariantMethod(baseNode: Integer; const mname: AnsiString): Integer;
var ci, mmi, mpi, i, k, unboxArg, unboxCall, castNode: Integer;
    selfArg, lastArg, argNode, callNode, hitCi, hitMmi, hitPi: Integer;
    smPName: AnsiString; smTk: TTypeKind; smArgs: Integer;
    dualPi, dcall, dself, dcast, tern, pairN, condN: Integer;
    { room for a real class hierarchy: songformatter has EIGHT detector classes
      all declaring analyze(), and the cap of three turned that into "too many
      candidate classes to dispatch at runtime" }
    dualCis, dualMmis: array[0..15] of Integer;
    nDual, di, kwIdx, kwDepth, swapCi, swapMmi, dualArgs: Integer;
    anyKw: Boolean; dualRetMixed: Boolean;
    argExprs: array[0..15] of Integer;
    smTmpSym, smAsgn, smGuardArg, smGuardCall, smNotNode, smNameArg,
    smArg1, smArg2, smRaiseCall, smIfNode, smPairNode: Integer;
begin
  { A receiver that came from an optional module which did not resolve — the
    name itself, or anything assigned from it. Checked BEFORE class dispatch:
    otherwise a same-named method on an unrelated class captures the call
    (`img.save(buf, format="PNG")` bound to the reportlab shim's Canvas.save),
    which is a wrong binding, not a missing one. }
  if PyIsOptionalMissingNode(baseNode) then
  begin
    Result := PyMakeOptionalMissingCall(PyOptionalMissingName(baseNode) + '.' + mname);
    Exit;
  end;
  { A STR method on a variant receiver — `for s in ["ab"]: s.upper()`, where the
    loop variable is a variant holding a string. Render the receiver with
    pystr_of (which spells every tag Python's way) and hand it to the ordinary
    str-method desugar, rather than looking for a class that declares `upper`.

    But ONLY when the receiver's runtime tag actually IS a string: pystr_of
    also spells None/int/float/bool as plausible TEXT ('None', '5', ...), so
    unconditionally stringifying first turned `None.upper()` into `'NONE'`
    instead of raising AttributeError
    (bug-nilpy-missing-attribute-yields-none-instead-of-attributeerror).
    baseNode is hoisted into a hidden temp first since it is now read TWICE
    (once for the tag guard, once for the str conversion) and may not be
    side-effect-free (`d.get(k).upper()`). }
  if PyStrMethodInfo(mname, smPName, smTk, smArgs) and
     not PyStrMethodLosesToClass(mname) then
  begin
    smTmpSym := AllocVar(PyHiddenName('sm'), tyVariant);
    smAsgn := AllocNode(AN_ASSIGN);
    ASTLeft[smAsgn] := PyMakeIdent(smTmpSym);
    ASTRight[smAsgn] := baseNode;
    PyHoistStmt(smAsgn);
    baseNode := PyMakeIdent(smTmpSym);

    i := FindProc('pyvar_is_strtag');
    if i < 0 then Error('Nil Python: pylib (pyvar_is_strtag) not loaded');
    smGuardArg := AllocNode(AN_ARG); ASTLeft[smGuardArg] := PyMakeIdent(smTmpSym);
    smGuardCall := AllocNode(AN_CALL);
    ASTIVal[smGuardCall] := i; ASTTk[smGuardCall] := Ord(tyBoolean);
    ASTLeft[smGuardCall] := smGuardArg;
    smNotNode := AllocNode(AN_NOT);
    ASTLeft[smNotNode] := smGuardCall; ASTTk[smNotNode] := Ord(tyBoolean);

    i := FindProc('pydynattr_no_method');
    if i < 0 then Error('Nil Python: pylib (pydynattr_no_method) not loaded');
    smNameArg := AllocNode(AN_STR_LIT);
    ASTSOffset[smNameArg] := PyStoredName(mname);
    ASTSLen[smNameArg] := Length(mname);
    ASTTk[smNameArg] := Ord(tyString);
    smArg2 := AllocNode(AN_ARG); ASTLeft[smArg2] := smNameArg; ASTRight[smArg2] := -1;
    smArg1 := AllocNode(AN_ARG); ASTLeft[smArg1] := PyMakeIdent(smTmpSym); ASTRight[smArg1] := smArg2;
    smRaiseCall := AllocNode(AN_CALL);
    ASTIVal[smRaiseCall] := i; ASTTk[smRaiseCall] := Ord(tyUnknown);
    ASTLeft[smRaiseCall] := smArg1;

    smIfNode := AllocNode(AN_IF);
    ASTLeft[smIfNode] := smNotNode;
    smPairNode := AllocNode(AN_PAIR);
    ASTLeft[smPairNode] := smRaiseCall; ASTRight[smPairNode] := -1;
    ASTRight[smIfNode] := smPairNode;
    PyHoistStmt(smIfNode);

    i := FindProc('pystr_of');
    if i < 0 then Error('Nil Python: pylib (pystr_of) not loaded');
    unboxArg := AllocNode(AN_ARG);
    ASTLeft[unboxArg] := baseNode;
    unboxCall := AllocNode(AN_CALL);
    ASTIVal[unboxCall] := i;
    ASTTk[unboxCall] := Ord(tyAnsiString);
    ASTLeft[unboxCall] := unboxArg;
    Result := PyParseStrMethod(unboxCall, mname);
    Exit;
  end;
  { Python's dict views on a VARIANT receiver. The typed path (parser.inc's
    member access) already maps items/keys/values onto pylib's itemlist /
    keylist / vallist — names chosen to dodge the default `Items[]` property —
    but a variant receiver never reaches it: the candidate scan below found no
    class declaring `values`, and the call fell through to the pyeval dynamic
    dispatch, which has no TPyDict branch and jumped through a nil host-call
    slot. See bug-nilpy-dict-values-on-variant-receiver. }
  if (mname = 'values') and (FindUClass('TPyDict') >= 0) then
  begin
    Result := PyParseVariantMethod(baseNode, 'vallist');
    Exit;
  end;
  if (mname = 'keys') and (FindUClass('TPyDict') >= 0) then
  begin
    Result := PyParseVariantMethod(baseNode, 'keylist');
    Exit;
  end;
  if (mname = 'items') and (FindUClass('TPyDict') >= 0) then
  begin
    Result := PyParseVariantMethod(baseNode, 'itemlist');
    Exit;
  end;
  { `w.destroy()` on a dynamically-typed widget — see the typed path in
    parser.inc: Pascal reserves `destroy` for the destructor. }
  if mname = 'destroy' then
  begin
    for ci := 0 to UClsCount - 1 do
      if (not UClsIsRecord[ci]) and (FindUMeth(ci, 'destroy_') >= 0) then
      begin
        Result := PyParseVariantMethod(baseNode, 'destroy_');
        Exit;
      end;
  end;
  { A Python method name Pascal RESERVES — the library convention is a trailing
    underscore (`set_`, `destroy_`). If nothing declares the name as written but
    something declares the underscored one, that is the method meant:
    configparser's `cfg.set(section, key, value)` on a dynamically-typed
    receiver. The typed path in parser.inc does the same. }
  if PyNoClassDeclares(mname) and (not PyNoClassDeclares(mname + '_')) then
  begin
    Result := PyParseVariantMethod(baseNode, mname + '_');
    Exit;
  end;
  { candidate scan — one entry per class whose method set answers to mname }
  hitCi := -1; hitMmi := -1; hitPi := -1;
  nDual := 0;
  for ci := 0 to UClsCount - 1 do
  begin
    if UClsIsRecord[ci] then Continue;
    mmi := FindUMeth(ci, mname);
    if mmi < 0 then Continue;
    mpi := UMthProc_[mmi];
    if hitCi < 0 then begin hitCi := ci; hitMmi := mmi; hitPi := mpi; end
    else if mpi <> hitPi then
    begin
      { An OVERRIDE is not an ambiguity: keep the ancestor's declaration so the
        call goes through that VMT slot and the runtime instance picks its own
        override. Only two UNRELATED classes are genuinely undecidable. }
      if IsSubclassOf(hitCi, ci) then
        { ci is the ANCESTOR — its slot is the one to dispatch through }
        begin hitCi := ci; hitMmi := mmi; hitPi := mpi; end
      else if (ci = FindUClass('TPyBytes')) or (hitCi = FindUClass('TPyBytes')) then
      begin
        { NARROW, DELIBERATE PREFERENCE, not a general tie-break: TPyList and
          TPyBytes both legitimately declare append/extend (Python has both
          list.append and bytearray.append), so neither can be renamed the way
          TPyList.get was. On a receiver with no static class, prefer the LIST:
          its parameter is a Variant and therefore accepts anything, while
          TPyBytes takes an Integer, and a bytearray receiver is almost always
          a statically-typed local (which never reaches this path).
          The correct fix is runtime dispatch on the receiver's class —
          feature-nilpy-runtime-method-dispatch-on-variant. }
        if ci <> FindUClass('TPyBytes') then
          begin hitCi := ci; hitMmi := mmi; hitPi := mpi; end;
      end
      else if PyIsPylibContainerCi(hitCi) and not PyIsPylibContainerCi(ci) then
      begin
        { the other candidate is a pylib container (list/dict/bytes), this one a
          USER class: hold the USER class statically but remember the container
          for a RUNTIME is-test branch — `vm.pop()` on a variant param means
          VM.pop, while `pending.pop()` on a variant LIST must reach
          TPyList.pop (the static pick alone called VM.pop on a list and
          jumped through garbage — uforth END-STRUCTURE). }
        if nDual <= High(dualCis) then
        begin
          dualCis[nDual] := hitCi; dualMmis[nDual] := hitMmi; Inc(nDual);
        end;
        hitCi := ci; hitMmi := mmi; hitPi := mpi;
      end
      else if PyIsPylibContainerCi(ci) and not PyIsPylibContainerCi(hitCi) then
      begin
        { keep the user-class candidate; remember the container for the branch }
        if nDual <= High(dualCis) then
        begin
          dualCis[nDual] := ci; dualMmis[nDual] := mmi; Inc(nDual);
        end;
      end
      else if PyIsPylibContainerCi(ci) and PyIsPylibContainerCi(hitCi) then
      begin
        { TWO containers declare it (list.pop and dict.pop): keep the current
          hit, branch on the other at runtime too }
        if nDual <= High(dualCis) then
        begin
          dualCis[nDual] := ci; dualMmis[nDual] := mmi; Inc(nDual);
        end;
      end
      else if not IsSubclassOf(ci, hitCi) then
      begin
        { Two UNRELATED USER classes declare the name. This used to be a hard
          error; it is now the same RUNTIME dispatch the container/user split
          above gets, only with an is-test on the receiver's actual class rather
          than a variant tag test — the receiver carries VT_OBJECT plus a real
          class pointer, so the test costs one compare per extra candidate and
          only on calls that are genuinely ambiguous.
          (feature-nilpy-runtime-method-dispatch-on-variant. songformatter's
          key_analysis.py has three unrelated dataclasses declaring to_text().) }
        if nDual <= High(dualCis) then
        begin
          dualCis[nDual] := ci; dualMmis[nDual] := mmi; Inc(nDual);
        end
        else
          Error('Nil Python: .' + mname + '() on a dynamically-typed value has '
            + 'too many candidate classes to dispatch at runtime — assign to an '
            + 'annotated local first');
      end;
    end;
  end;
  if hitCi < 0 then
  begin
    { Not a method — but it may be a procedural FIELD holding a function value,
      which is how a dispatch table is written (`w.native(vm)`). Resolve the
      field the same way, by name across the declared classes, and call through
      it (feature-nilpy-function-values). }
    for ci := 0 to UClsCount - 1 do
    begin
      if UClsIsRecord[ci] then Continue;
      mmi := FindUField(ci, mname);
      if mmi < 0 then Continue;
      if UFldProcSig[mmi] < 0 then Continue;
      if hitCi < 0 then begin hitCi := ci; hitMmi := mmi; end
      else if UFldProcSig[mmi] <> UFldProcSig[hitMmi] then
        Error('Nil Python: .' + mname + '() on a dynamically-typed value is '
          + 'ambiguous (several classes declare that field) — assign to an '
          + 'annotated local first');
    end;
    if hitCi >= 0 then
    begin
      Result := PyMakeVariantFieldCall(baseNode, hitCi, mname, UFldProcSig[hitMmi]);
      Exit;
    end;
    { The receiver is a name bound to None because its optional import did not
      resolve — `Image.open(...)` after `try: from PIL import Image` failed.
      CPython compiles that file and raises only if the call runs, which is
      what the application's own HAVE_PIL guard relies on. Emit the same shape:
      a call that raises, naming the module. }
    if PyIsOptionalMissingNode(baseNode) then
    begin
      Result := PyMakeOptionalMissingCall(PyOptionalMissingName(baseNode) + '.' + mname);
      Exit;
    end;
    { …and anything else dynamically typed, ONCE this program is known to have
      an optional import that did not resolve. A value taken from such a module
      spreads through locals (`img = Image.open(f)` then `img.resize(...)`),
      and NilPy parses a body more than once, so tracking the taint statement
      by statement does not hold. Closed-world dispatch stays a compile error
      for every program WITHOUT such an import — which is all of them until one
      says `try: import X / except ImportError:` — so typo detection is
      unchanged there. feature-nilpy-fallback-import. }
    if (PyOptMissingCount > 0) and
       (IntToTypeKind(ASTTk[baseNode]) = tyVariant) then
    begin
      Result := PyMakeOptionalMissingCall('.' + mname + ' (an optional module)');
      Exit;
    end;
    Error('Nil Python: no class declares a method or callable field .'
          + mname + '()');
  end;

  { Which candidate does the CALL name? With several classes declaring the
    method, the static pick so far is just the first one found — but a KEYWORD
    argument names a parameter, and that identifies the intended signature.
    Scan the argument list's `ident =` pairs before parsing them and promote the
    candidate that has those parameters; the demoted one stays as a runtime arm.
    key_analysis.py's `detector.to_text(verbose=True)` needs exactly this: the
    first class found declares `to_text()` with no parameters at all. }
  if (nDual > 0) and (CurTok.Kind = tkLParen) then
  begin
    k := TokPos; kwDepth := 1;
    while (k < TokCount) and (kwDepth > 0) do
    begin
      if Tokens[k].Kind = tkLParen then Inc(kwDepth)
      else if Tokens[k].Kind = tkRParen then Dec(kwDepth)
      else if (kwDepth = 1) and (Tokens[k].Kind = tkIdent) and (k + 1 < TokCount)
              and (Tokens[k + 1].Kind = tkAssign)
              and (not PyProcParamNamed(hitPi, GetTokenStr(k))) then
      begin
        smPName := GetTokenStr(k);
        for di := 0 to nDual - 1 do
          if (dualMmis[di] >= 0) and PyProcParamNamed(UMthProc_[dualMmis[di]], smPName) then
          begin
            swapCi := hitCi; swapMmi := hitMmi;
            hitCi := dualCis[di]; hitMmi := dualMmis[di]; hitPi := UMthProc_[hitMmi];
            dualCis[di] := swapCi; dualMmis[di] := swapMmi;
            Break;
          end;
      end;
      Inc(k);
    end;
  end;

  { Same question, but for OVERLOADS OF ONE CLASS. The candidate scan keeps one
    entry per class, so `Widget.bind(seq, script)` and `Widget.bind(seq,
    callback, add)` collapse to whichever was declared first — and a keyword
    argument the chosen one does not have was then a hard error
    (`bind(..., add="+")`, which is what songformatter writes). The keyword
    names the signature here just as it does across classes above. }
  if hitCi >= 0 then
  begin
    hitMmi := PyPromoteOverloadByKw(hitCi, hitMmi, mname);
    if hitMmi >= 0 then hitPi := UMthProc_[hitMmi];
  end;

  { VT_OBJECT payload -> instance pointer -> hard cast to the owning class }
  unboxArg := AllocNode(AN_ARG);
  ASTLeft[unboxArg] := baseNode;
  unboxCall := AllocNode(AN_CALL);
  ASTIVal[unboxCall] := FindProc('pyvarobj');
  if ASTIVal[unboxCall] < 0 then Error('Nil Python: pylib (pyvarobj) not loaded');
  ASTTk[unboxCall] := Ord(tyPointer);
  ASTLeft[unboxCall] := unboxArg;
  castNode := AllocNode(AN_CLASS_CAST);
  ASTLeft[castNode] := unboxCall;
  ASTIVal[castNode] := hitCi;
  ASTTk[castNode]   := Ord(tyClass);

  selfArg := AllocNode(AN_ARG);
  ASTLeft[selfArg] := castNode;
  lastArg := selfArg;

  Expect(tkLParen, '(');
  i := 0;
  anyKw := False;
  while CurTok.Kind <> tkRParen do
  begin
    { Keyword arguments here too — `detector.to_text(verbose=True)` on a
      dynamically-typed receiver. They bind against the STATICALLY chosen
      method; a runtime candidate re-uses the reordered argument list, which is
      right as long as the candidates agree on parameter order, and they do
      when they agree on the name and arity that got them here. }
    { a starred argument on a dynamically-dispatched receiver — same expansion
      as the statically-bound method path above }
    if (CurTok.Kind = tkStar) and (TokPos < TokCount) and
       (Tokens[TokPos].Kind <> tkStar) and (ProcPyStarIdx[hitPi] < 0) then
    begin
      kwIdx := selfArg;
      PyStarExpandCallArgs(hitPi, i + 1, kwIdx, lastArg);
      i := Procs[hitPi].ParamCount - 1;
      Break;
    end;
    kwIdx := PyKwArgIndex(hitPi, 1);
    if kwIdx <> 0 then anyKw := True;
    ParseArgExpr;
    argNode := AllocNode(AN_ARG);
    ASTLeft[argNode] := CurASTNode;
    ASTIVal[argNode] := kwIdx;
    ASTRight[lastArg] := argNode;
    lastArg := argNode;
    Inc(i);
    if CurTok.Kind = tkComma then Next
    else Break;
  end;
  Expect(tkRParen, ')');
  { `*args` / `**kwargs` on a METHOD: pack the surplus arguments before the
    keyword bind, exactly as the top-level call path does. Self occupies slot 0
    of the parameter list, so the counter is passed INCLUDING it and the
    argument count is re-derived afterwards. }
  if (ProcPyStarIdx[hitPi] >= 0) or (ProcPyKwIdx[hitPi] >= 0) then
  begin
    i := i + 1;
    PyPackStarArgs(hitPi, selfArg, lastArg, i);
    if i > 0 then Dec(i);
    anyKw := False;   { the packing consumed every keyword argument }
  end;
  if anyKw then
  begin
    { PyBindKwArgs orders the chain (self is slot 0, exactly as the ordinary
      method path uses it) and fills omitted defaults, so `i` is re-derived from
      the bound chain rather than from how many arguments were written. }
    i := 0;
    PyBindKwArgs(hitPi, selfArg, lastArg, i);
    if i > 0 then Dec(i);          { drop self from the argument count }
  end;
  { the per-argument nodes the runtime-dispatch arms re-use, in bound order }
  argNode := ASTRight[selfArg];
  k := 0;
  while (argNode >= 0) and (k <= High(argExprs)) do
  begin
    argExprs[k] := ASTLeft[argNode];
    Inc(k);
    argNode := ASTRight[argNode];
  end;

  { Overload selection by the ACTUAL argument count. The candidate scan above
    picked the first method named `mname`; a class like TPyDict declares `get(k)`
    AND `get(k, d)` as overloads, so a 2-arg `.get(key, default)` on a variant
    receiver would otherwise bind to the 1-arg body and pass a stray argument
    (crash). Re-resolve within the chosen class by arity now that `i` is known. }
  if hitCi >= 0 then
  begin
    mmi := FindUMethArity(hitCi, mname, i);
    if mmi >= 0 then begin hitMmi := mmi; hitPi := UMthProc_[mmi]; end;
  end;

  mpi := hitPi;
  { Fill the callee's remaining DEFAULTED parameters. The runtime arms below do
    this; the STATIC arm did not, so a dispatched `det.analyze(chords, fn)`
    against `analyze(self, chords, fn, sections=None)` called a 4-parameter
    method with 3 and the callee read an uninitialised slot — it crashed only
    when the receiver was dynamically typed, which is what made it look like a
    dispatch bug rather than a missing fill. }
  k := i + 1;
  while (k < Procs[mpi].ParamCount) and (k < MAX_PROC_PARAMS) and
        ProcParamHasDefault[mpi * MAX_PROC_PARAMS + k] do
  begin
    argNode := AllocNode(AN_ARG);
    ASTLeft[argNode] := DefaultArgValueNode(mpi, k);
    ASTRight[argNode] := -1;
    ASTRight[lastArg] := argNode;
    lastArg := argNode;
    Inc(k);
  end;
  if UMthVirSlot[hitMmi] >= 0 then
  begin
    callNode := AllocNode(AN_VIRTUAL_CALL);
    ASTRight[callNode] := UMthVirSlot[hitMmi];
  end
  else
    callNode := AllocNode(AN_CALL);
  ASTIVal[callNode] := mpi;
  ASTTk[callNode] := Ord(Procs[mpi].RetType);
  ASTLeft[callNode] := selfArg;
  LastExprTk := Procs[mpi].RetType;
  Result := callNode;

  { Do the candidates agree on a return type? Computed ONCE, before any arm is
    built — see the note where it is used. }
  dualRetMixed := False;
  for di := 0 to nDual - 1 do
  begin
    mmi := FindUMethArity(dualCis[di], mname, i);
    if mmi < 0 then mmi := dualMmis[di];
    if mmi < 0 then Continue;
    { The KIND is not enough: two candidates can both return tyClass and return
      DIFFERENT classes (`beginText` gives the reportlab shim's PDFTextObject or
      render_backend's _TkTextObject). Typed from the static pick, the next
      method call on the result compiled as a STATIC call into the wrong class
      and jumped through its layout — songformatter's preview died on
      `tx.setFont(...)` that way. Compare the returned RECORD too. }
    if (Procs[UMthProc_[mmi]].RetType <> Procs[mpi].RetType) or
       (ProcRetRecId[UMthProc_[mmi]] <> ProcRetRecId[mpi]) then dualRetMixed := True;
  end;

  { RUNTIME dual dispatch: the receiver may be one of the remembered pylib
    CONTAINERS rather than the statically-preferred class. For each container
    candidate, wrap: `pyvar_holds(recv, k) ? <container call> : <fallback>` —
    recv/arg expression nodes are shared across arms (side-effect-free in the
    corpus; the b346 re-emission caveat applies). }
  if (nDual > 0) and (i <= High(argExprs) + 1) then
    for di := 0 to nDual - 1 do
    begin
      mmi := FindUMethArity(dualCis[di], mname, i);
      if mmi < 0 then mmi := dualMmis[di];
      if mmi < 0 then Continue;
      dualPi := UMthProc_[mmi];
      { The runtime candidate may declare MORE parameters than the call wrote,
        with defaults — `to_text(self, verbose=False)` reached by a bare
        `it.to_text()`. The arm builds its own argument chain, so it never passes
        through the shared fill; without this the callee read an uninitialised
        slot and crashed. A candidate that cannot be completed is dropped rather
        than called short. }
      dualArgs := i;
      k := dualArgs + 1;
      while (k < Procs[dualPi].ParamCount) and (k < MAX_PROC_PARAMS) and
            ProcParamHasDefault[dualPi * MAX_PROC_PARAMS + k] do
      begin
        Inc(dualArgs);
        Inc(k);
      end;
      if dualArgs + 1 <> Procs[dualPi].ParamCount then Continue;
      unboxArg := AllocNode(AN_ARG);
      ASTLeft[unboxArg] := baseNode;
      unboxCall := AllocNode(AN_CALL);
      ASTIVal[unboxCall] := FindProc('pyvarobj');
      ASTTk[unboxCall] := Ord(tyPointer);
      ASTLeft[unboxCall] := unboxArg;
      dcast := AllocNode(AN_CLASS_CAST);
      ASTLeft[dcast] := unboxCall;
      ASTIVal[dcast] := dualCis[di];
      ASTTk[dcast] := Ord(tyClass);
      dself := AllocNode(AN_ARG);
      ASTLeft[dself] := dcast;
      lastArg := dself;
      for k := 0 to i - 1 do
      begin
        argNode := AllocNode(AN_ARG);
        ASTLeft[argNode] := argExprs[k];
        ASTRight[lastArg] := argNode;
        lastArg := argNode;
      end;
      for k := i to dualArgs - 1 do
      begin
        argNode := AllocNode(AN_ARG);
        ASTLeft[argNode] := DefaultArgValueNode(dualPi, k + 1);
        ASTRight[lastArg] := argNode;
        lastArg := argNode;
      end;
      if UMthVirSlot[mmi] >= 0 then
      begin
        dcall := AllocNode(AN_VIRTUAL_CALL);
        ASTRight[dcall] := UMthVirSlot[mmi];
      end
      else
        dcall := AllocNode(AN_CALL);
      ASTIVal[dcall] := dualPi;
      ASTTk[dcall] := Ord(Procs[dualPi].RetType);
      ASTLeft[dcall] := dself;

      if PyIsPylibContainerCi(dualCis[di]) then
      begin
        { cond: pyvar_holds(recv, kind) }
        unboxArg := AllocNode(AN_ARG);
        ASTLeft[unboxArg] := baseNode;
        condN := AllocNode(AN_INT_LIT);
        if dualCis[di] = FindUClass('TPyList') then ASTIVal[condN] := 1
        else if dualCis[di] = FindUClass('TPyDict') then ASTIVal[condN] := 2
        else ASTIVal[condN] := 3;
        ASTTk[condN] := Ord(tyInt64);
        unboxCall := AllocNode(AN_ARG);
        ASTLeft[unboxCall] := condN;
        ASTRight[unboxArg] := unboxCall;
        condN := AllocNode(AN_CALL);
        ASTIVal[condN] := FindProc('pyvar_holds');
        if ASTIVal[condN] < 0 then Error('Nil Python: pylib (pyvar_holds) not loaded');
        ASTTk[condN] := Ord(tyBoolean);
        ASTLeft[condN] := unboxArg;
      end
      else
      begin
        { cond: pyvarobj(recv) is <that user class> — the same test isinstance
          lowers to, which is what makes an unrelated-user-class candidate
          dispatchable at all. }
        unboxArg := AllocNode(AN_ARG);
        ASTLeft[unboxArg] := baseNode;
        unboxCall := AllocNode(AN_CALL);
        ASTIVal[unboxCall] := FindProc('pyvarobj');
        if ASTIVal[unboxCall] < 0 then Error('Nil Python: pylib (pyvarobj) not loaded');
        ASTTk[unboxCall] := Ord(tyPointer);
        ASTLeft[unboxCall] := unboxArg;
        condN := AllocNode(AN_IS_TEST);
        ASTLeft[condN] := unboxCall;
        ASTIVal[condN] := dualCis[di];
        ASTTk[condN] := Ord(tyBoolean);
      end;

      pairN := AllocNode(AN_PAIR);
      ASTLeft[pairN] := dcall;
      ASTRight[pairN] := Result;
      tern := AllocNode(AN_TERNARY);
      ASTLeft[tern] := condN;
      ASTRight[tern] := pairN;
      { The type of the WHOLE chain, not of this arm: if ANY candidate returns
        something else, the expression is dynamic. Set per-arm, one arm that
        happened to agree with the static pick re-typed the chain — a variant
        LIST coming back from TPyDict.get was then assigned into an AnsiString
        and stringified to nothing, while an int survived (it stringifies to
        its digits). `d.get(k)` on a json value silently returned '' in any
        program that also imported a module exporting `get`. }
      if dualRetMixed then
        ASTTk[tern] := Ord(tyVariant)
      else
        ASTTk[tern] := Ord(Procs[mpi].RetType);
      LastExprTk := IntToTypeKind(ASTTk[tern]);
      Result := tern;
    end;
end;

{ A bare tuple display — `return a, b` or `x = 1, 2` — built from an ALREADY
  parsed first element, then the comma-separated rest. A tuple is a TPyList here
  (the representation isinstance and the annotation path already use), so this is
  the list-literal lowering with the brackets implied: bind a hidden temp, append
  onto it through hoisted statements, yield the temp as the expression. Keeping
  the temp is what lets the value be borrowed and reclaimed like any literal.

  Mutability and hashability are the documented differences from CPython; see the
  tuple annotation note in PyAnnTypeTermAt. }
function PyMakeTupleFrom(firstNode: Integer): Integer;
var ci, recId, node, argNode, sizeNode, callNode, selfArg, valArg, mmi, mpi,
    tmpSym, asgn, elemNode: Integer;
begin
  ci := FindUClass('TPyList');
  if ci < 0 then Error('Nil Python: pylib (TPyList) not loaded');
  recId := REC_UCLASS_BASE + ci;
  node := AllocNode(AN_CALL);
  ASTIVal[node] := -Ord(tkGetMem);
  ASTTk[node] := Ord(tyClass);
  ASTRight[node] := recId;
  sizeNode := AllocNode(AN_INT_LIT);
  ASTIVal[sizeNode] := RecSize(recId);
  ASTTk[sizeNode] := Ord(tyInteger);
  argNode := AllocNode(AN_ARG);
  ASTLeft[argNode] := sizeNode;
  ASTLeft[node] := argNode;
  tmpSym := AllocVar(PyHiddenName('tup'), tyClass);
  Syms[tmpSym].RecName := recId;
  asgn := AllocNode(AN_ASSIGN);
  ASTLeft[asgn] := PyMakeIdent(tmpSym);
  ASTRight[asgn] := node;
  PyHoistStmt(asgn);
  mmi := FindUMeth(ci, 'append');
  if mmi < 0 then Error('Nil Python: TPyList.append not found');
  mpi := UMthProc_[mmi];
  elemNode := firstNode;
  while True do
  begin
    valArg := AllocNode(AN_ARG);
    ASTLeft[valArg] := elemNode;
    selfArg := AllocNode(AN_ARG);
    ASTLeft[selfArg] := PyMakeIdent(tmpSym);
    ASTRight[selfArg] := valArg;
    callNode := AllocNode(AN_CALL);
    ASTIVal[callNode] := mpi;
    ASTTk[callNode] := Ord(tyClass);
    ASTLeft[callNode] := selfArg;
    PyHoistStmt(callNode);
    if CurTok.Kind <> tkComma then Break;
    Next;
    { a trailing comma closes the tuple: `return x,` is a 1-tuple }
    if CurTok.Kind in [tkNewline, tkDedent, tkEOF, tkRParen, tkRBrack] then Break;
    if CurTok.Kind = tkNil then
    begin
      Next;
      elemNode := PyMakeNone;
    end
    else
    begin
      PyParseBoolExpr;
      elemNode := CurASTNode;
    end;
  end;
  { Mark it a TUPLE, for rendering. A tuple and a list are the same TPyList here,
    so `print((1, 2))` printed `[1, 2]` — the one visible place the shared
    representation leaks (bug-nilpy-str-of-tuple-is-empty). The flag is set on
    the temp, so every later read of it renders with parentheses. }
  mpi := FindProc('pylist_mark_tuple');
  if mpi >= 0 then
  begin
    selfArg := AllocNode(AN_ARG);
    ASTLeft[selfArg] := PyMakeIdent(tmpSym);
    ASTRight[selfArg] := -1;
    callNode := AllocNode(AN_CALL);
    ASTIVal[callNode] := mpi;
    ASTTk[callNode] := Ord(tyClass);
    ASTLeft[callNode] := selfArg;
    PyHoistStmt(callNode);
  end;
  Result := PyMakeIdent(tmpSym);
end;

{ A None VALUE: pylib's pynone() yields a variant tagged VT_EMPTY. }
{ Is the CURRENT token a `None` that stands alone — nothing after it that could
  continue an expression? A dozen sites substitute PyMakeNone the moment they
  see tkNil and consume it unconditionally, which is why `None == 0`,
  `None or "n"` and friends died with "unexpected token" while the identical
  expression one paren deeper parsed fine: the token was eaten before the
  operator could be seen. ParseFactor now yields the None VALUE itself under
  PyExprMode, so those sites only need to keep their shortcut for the bare case
  and hand anything else to the ordinary expression parser
  (bug-nilpy-none-equals-zero-is-true). }
{ Is this node a CALLABLE value — a bound method, a lifted lambda, a pyeval
  closure, a boxed function value or a bare code address? Used to refuse one
  where a STRING parameter is declared: the variant a bound method produces
  coerces into an AnsiString without complaint, and the {code, receiver} pair
  then travelled on as text. Tk was handed that as a script and evaluated
  garbage on every scroll update — a HANG inside root.update(), four layers from
  the cause, with no diagnostic anywhere
  (bug-nilpy-bound-method-coerced-to-string). }
function PyNodeIsCallableValue(n: Integer): Boolean;
var nm: AnsiString;
begin
  PyNodeIsCallableValue := False;
  if n < 0 then Exit;
  if ASTKind[n] = AN_PROCADDR then
  begin
    PyNodeIsCallableValue := True;
    Exit;
  end;
  if ASTKind[n] <> AN_CALL then Exit;
  if ASTIVal[n] < 0 then Exit;
  nm := LowerCase(Procs[ASTIVal[n]].Name);
  PyNodeIsCallableValue :=
    (nm = 'pybound_new') or (nm = 'pyvar_of_callable') or
    (nm = 'pyclosure_src_new') or (nm = 'pyclosure_src_cap') or
    (nm = 'pyboundfn_new') or (nm = 'pyboundfn_bind') or
    (nm = 'pyboundfn_setown') or
    (nm = 'pyboundfn_bind_var') or (nm = 'pyboundfn_bind_obj');
end;

function PyBareNoneHere: Boolean;
begin
  PyBareNoneHere := False;
  if CurTok.Kind <> tkNil then Exit;
  if TokPos >= TokCount then begin PyBareNoneHere := True; Exit; end;
  PyBareNoneHere := Tokens[TokPos].Kind in
    [tkNewline, tkDedent, tkIndent, tkEOF, tkComma, tkRParen, tkRBrack,
     tkEnd, tkColon, tkSemicolon];
end;

function PyMakeNone: Integer;
var procIdx: Integer;
begin
  procIdx := FindProc('pynone');
  if procIdx < 0 then Error('Nil Python: pylib (pynone) not loaded');
  Result := AllocNode(AN_CALL);
  ASTIVal[Result] := procIdx;
  ASTTk[Result] := Ord(tyVariant);
  ASTLeft[Result] := -1;
end;

{ An empty TPyList / TPyDict bound to a hidden temp, built by HOISTED statements
  the way the literal parsers do (see PyParseListLiteralT for why the temp owns
  the construction ref). Returns the temp SYMBOL — the callers below append or
  store onto it and then yield PyMakeIdent(sym). }
function PyNewContainerTemp(const clsName, tag: AnsiString): Integer;
var ci, recId, node, argNode, sizeNode, tmpSym, asgn: Integer;
begin
  ci := FindUClass(clsName);
  if ci < 0 then Error('Nil Python: pylib (' + clsName + ') not loaded');
  recId := REC_UCLASS_BASE + ci;
  node := AllocNode(AN_CALL);
  ASTIVal[node] := -Ord(tkGetMem);
  ASTTk[node] := Ord(tyClass);
  ASTRight[node] := recId;
  sizeNode := AllocNode(AN_INT_LIT);
  ASTIVal[sizeNode] := RecSize(recId);
  ASTTk[sizeNode] := Ord(tyInteger);
  argNode := AllocNode(AN_ARG);
  ASTLeft[argNode] := sizeNode;
  ASTLeft[node] := argNode;
  tmpSym := AllocVar(PyHiddenName(tag), tyClass);
  Syms[tmpSym].RecName := recId;
  asgn := AllocNode(AN_ASSIGN);
  ASTLeft[asgn] := PyMakeIdent(tmpSym);
  ASTRight[asgn] := node;
  PyHoistStmt(asgn);
  Result := tmpSym;
end;

{ One hoisted `tmp.<meth>(a [, b])` on a container temp. }
procedure PyContainerCall1(tmpSym: Integer; const clsName, meth: AnsiString;
                           argA, argB: Integer);
var ci, mmi, mpi, selfArg, aArg, bArg, callNode: Integer;
begin
  ci := FindUClass(clsName);
  if ci < 0 then Error('Nil Python: pylib (' + clsName + ') not loaded');
  mmi := FindUMeth(ci, meth);
  if mmi < 0 then Error('Nil Python: ' + clsName + '.' + meth + ' not found');
  mpi := UMthProc_[mmi];
  aArg := AllocNode(AN_ARG);
  ASTLeft[aArg] := argA;
  if argB >= 0 then
  begin
    bArg := AllocNode(AN_ARG);
    ASTLeft[bArg] := argB;
    ASTRight[aArg] := bArg;
  end;
  selfArg := AllocNode(AN_ARG);
  ASTLeft[selfArg] := PyMakeIdent(tmpSym);
  ASTRight[selfArg] := aArg;
  callNode := AllocNode(AN_CALL);
  ASTIVal[callNode] := mpi;
  ASTTk[callNode] := Ord(tyClass);
  ASTLeft[callNode] := selfArg;
  PyHoistStmt(callNode);
end;

{ `get(*args, **kwargs)` FORWARDED into a callee with ORDINARY parameters — the
  third rung of feature-nilpy-star-args-kwargs, and what songformatter's
  settings.py getF/getI need. There is no static answer: the argument count is
  only known at run time. So this is a DESUGARING, not a runtime feature — a
  dispatch on len(args) over the arities the callee actually accepts:

      pystar_check_arity(args, required, total)      (hoisted, fails loudly)
      pystar_no_kwargs(kwargs)                       (hoisted, ditto)
      len(args) = 3 ? f(args[0], args[1], args[2])
                    : f(args[0], args[1])            ... down to the required count

  Each argument is `args.at(k)`, a variant, coerced to the parameter's declared
  type. A parameter type with no coercion is refused rather than passed raw.
  Keyword forwarding is checked at run time and refused: binding a runtime dict
  onto named parameters needs a call protocol NilPy does not have. }
function PyStarForwardCall(procIdx, listNode, dictNode: Integer): Integer;
var required, total, n, k, i, argNode, lastArg, callNode, elemNode: Integer;
    lenNode, cntNode, condNode, pairNode, ternNode, chkArg, a2, a3: Integer;
    listSym, dictSym, asgn, listCi, dictCi: Integer;
    slotSyms: array[0..15] of Integer;
    ptk: TTypeKind;
begin
  listCi := FindUClass('TPyList');
  dictCi := FindUClass('TPyDict');
  if listCi < 0 then Error('Nil Python: pylib (TPyList) not loaded');
  { bind both containers to temps: each arm reads the list again, and the
    expression must not be rebuilt per arm }
  listSym := AllocVar(PyHiddenName('fwd'), tyClass);
  Syms[listSym].RecName := REC_UCLASS_BASE + listCi;
  asgn := AllocNode(AN_ASSIGN);
  ASTLeft[asgn] := PyMakeIdent(listSym);
  ASTRight[asgn] := listNode;
  PyHoistStmt(asgn);
  dictSym := -1;
  if (dictNode >= 0) and (dictCi >= 0) then
  begin
    dictSym := AllocVar(PyHiddenName('fwdkw'), tyClass);
    Syms[dictSym].RecName := REC_UCLASS_BASE + dictCi;
    asgn := AllocNode(AN_ASSIGN);
    ASTLeft[asgn] := PyMakeIdent(dictSym);
    ASTRight[asgn] := dictNode;
    PyHoistStmt(asgn);
  end;

  total := Procs[procIdx].ParamCount;
  required := total;
  while (required > 0) and (required - 1 < MAX_PROC_PARAMS) and
        ProcParamHasDefault[procIdx * MAX_PROC_PARAMS + (required - 1)] do
    Dec(required);

  { the two runtime guards }
  chkArg := AllocNode(AN_ARG);
  ASTLeft[chkArg] := PyMakeIdent(listSym);
  a2 := AllocNode(AN_ARG);
  ASTLeft[a2] := AllocNode(AN_INT_LIT);
  ASTIVal[ASTLeft[a2]] := required;
  ASTTk[ASTLeft[a2]] := Ord(tyInteger);
  a3 := AllocNode(AN_ARG);
  ASTLeft[a3] := AllocNode(AN_INT_LIT);
  ASTIVal[ASTLeft[a3]] := total;
  ASTTk[ASTLeft[a3]] := Ord(tyInteger);
  ASTRight[chkArg] := a2;
  ASTRight[a2] := a3;
  callNode := AllocNode(AN_CALL);
  ASTIVal[callNode] := FindProc('pystar_check_arity');
  if ASTIVal[callNode] < 0 then Error('Nil Python: pylib (pystar_check_arity) not loaded');
  ASTTk[callNode] := Ord(tyInteger);
  ASTLeft[callNode] := chkArg;
  PyHoistStmt(callNode);
  if dictSym >= 0 then
  begin
    chkArg := AllocNode(AN_ARG);
    ASTLeft[chkArg] := PyMakeIdent(dictSym);
    callNode := AllocNode(AN_CALL);
    ASTIVal[callNode] := FindProc('pystar_no_kwargs');
    if ASTIVal[callNode] < 0 then Error('Nil Python: pylib (pystar_no_kwargs) not loaded');
    ASTTk[callNode] := Ord(tyInteger);
    ASTLeft[callNode] := chkArg;
    PyHoistStmt(callNode);
  end;

  { Every slot the widest arity could use, read ONCE into a hidden variant local.
    The arms are alternatives but the reads are not — a ternary arm cannot carry
    hoisted setup — so pystar_arg yields None past the end instead of an index
    error, and a variant PARAMETER (which is by-reference) gets a real lvalue to
    bind rather than a call result. }
  if total > 16 then
    Error('Nil Python: cannot forward *args into a callee with more than 16 parameters');
  for k := 0 to total - 1 do
  begin
    slotSyms[k] := AllocVar(PyHiddenName('fwda'), tyVariant);
    elemNode := AllocNode(AN_ARG);
    ASTLeft[elemNode] := PyMakeIdent(listSym);
    argNode := AllocNode(AN_ARG);
    ASTLeft[argNode] := AllocNode(AN_INT_LIT);
    ASTIVal[ASTLeft[argNode]] := k;
    ASTTk[ASTLeft[argNode]] := Ord(tyInteger);
    ASTRight[elemNode] := argNode;
    callNode := AllocNode(AN_CALL);
    ASTIVal[callNode] := FindProc('pystar_arg');
    if ASTIVal[callNode] < 0 then Error('Nil Python: pylib (pystar_arg) not loaded');
    ASTTk[callNode] := Ord(tyVariant);
    ASTLeft[callNode] := elemNode;
    asgn := AllocNode(AN_ASSIGN);
    ASTLeft[asgn] := PyMakeIdent(slotSyms[k]);
    ASTRight[asgn] := callNode;
    PyHoistStmt(asgn);
  end;

  { one call per accepted arity, folded into a ternary chain from the top down;
    the LOWEST arity is the final else, which the arity guard has made safe }
  Result := -1;
  for n := required to total do
  begin
    lastArg := -1;
    callNode := AllocNode(AN_CALL);
    ASTIVal[callNode] := procIdx;
    ASTTk[callNode] := Ord(Procs[procIdx].RetType);
    for k := 0 to n - 1 do
    begin
      elemNode := PyMakeIdent(slotSyms[k]);
      ptk := Procs[procIdx].Params[k].TypeKind;
      if ptk = tyVariant then
        { pass the variant straight through }
      else if PyIsStrBaseTk(ptk) or (ptk = tyAnsiString) then
      begin
        i := FindProc('pystr_of');
        if i < 0 then Error('Nil Python: pylib (pystr_of) not loaded');
        argNode := AllocNode(AN_ARG);
        ASTLeft[argNode] := elemNode;
        elemNode := AllocNode(AN_CALL);
        ASTIVal[elemNode] := i;
        ASTTk[elemNode] := Ord(tyAnsiString);
        ASTLeft[elemNode] := argNode;
      end
      else
        Error('Nil Python: cannot forward *args into ' + Procs[procIdx].Name
          + ' — parameter ' + Procs[procIdx].Params[k].Name
          + ' has a type no runtime argument can be coerced to');
      argNode := AllocNode(AN_ARG);
      ASTLeft[argNode] := elemNode;
      if lastArg < 0 then ASTLeft[callNode] := argNode
      else ASTRight[lastArg] := argNode;
      lastArg := argNode;
    end;
    if n = required then
    begin
      Result := callNode;
      Continue;
    end;
    { cond: pylist.count = n }
    lenNode := PyCallMeth1(listCi, 'count', PyMakeIdent(listSym), -1);
    if lenNode < 0 then Error('Nil Python: pylib (TPyList.count) not loaded');
    cntNode := AllocNode(AN_INT_LIT);
    ASTIVal[cntNode] := n;
    ASTTk[cntNode] := Ord(tyInteger);
    condNode := AllocNode(AN_BINOP);
    ASTIVal[condNode] := Ord(tkEq);
    ASTLeft[condNode] := lenNode;
    ASTRight[condNode] := cntNode;
    ASTTk[condNode] := Ord(tyBoolean);
    pairNode := AllocNode(AN_PAIR);
    ASTLeft[pairNode] := callNode;
    ASTRight[pairNode] := Result;
    ternNode := AllocNode(AN_TERNARY);
    ASTLeft[ternNode] := condNode;
    ASTRight[ternNode] := pairNode;
    ASTTk[ternNode] := Ord(Procs[procIdx].RetType);
    Result := ternNode;
  end;
end;

{ Pack a call's surplus arguments into the callee's `*args` list and `**kwargs`
  dict, so the rest of the call machinery sees an ORDINARY argument list of
  exactly the declared arity (feature-nilpy-star-args-kwargs rung 1).

  Runs on the parsed AN_ARG chain, just before PyBindKwArgs:
  - positional arguments at or past the star parameter's index become
    `tmp.append(v)` on a hidden TPyList;
  - keyword arguments PyKwArgIndex could not match a parameter (marked with a
    negative ASTIVal carrying their key literal) become `tmp.setitem(k, v)` on a
    hidden TPyDict;
  - the two temps are then spliced in at their parameter positions, AFTER the
    kept positionals and BEFORE any matched keyword argument, so PyBindKwArgs
    still sees positionals first.
  The containers are always passed, empty when nothing was collected, which is
  what keeps the callee's arity fixed.

  No-op — chain untouched — for any callee without a star parameter, which is
  every Pascal call and almost every NilPy one. }
{ The Pascal-side method-call loops are ARITY-DRIVEN: they parse exactly the
  parameters the callee declares, demanding a comma between them. A method with
  `*args` / `**kwargs` has no fixed arity, so those loops either demanded an
  argument that was never written or left surplus ones for the `)` to choke on
  (`def drawImage(self, img, x, y, width=0, ..., **kw)` — songformatter's
  render backend — failed on every call). Parse the list Python-style instead,
  then hand it to the same packing the top-level def path uses.

  On entry the cursor sits just past `(` and the AN_ARG chain already holds
  Self at slot 0, which is what makes the parameter indices line up. }
procedure PyParseStarMethodArgs(mpi, mcallNode: Integer; var mlastArg, mai: Integer);
var argNode, kwIdx, head, cnt: Integer;
begin
  head := ASTLeft[mcallNode];
  cnt := 1;                          { Self }
  while CurTok.Kind <> tkRParen do
  begin
    kwIdx := PyKwArgIndex(mpi, 1);
    ParseArgExpr;
    argNode := AllocNode(AN_ARG);
    ASTLeft[argNode] := CurASTNode;
    ASTIVal[argNode] := kwIdx;
    ASTRight[argNode] := -1;
    if mlastArg < 0 then ASTLeft[mcallNode] := argNode
    else ASTRight[mlastArg] := argNode;
    if head < 0 then head := argNode;
    mlastArg := argNode;
    Inc(cnt);
    if CurTok.Kind = tkComma then Next else Break;
  end;
  PyPackStarArgs(mpi, head, mlastArg, cnt);
  PyBindKwArgs(mpi, head, mlastArg, cnt);
  ASTLeft[mcallNode] := head;
  { every declared parameter is now present, so the caller's arity loop has
    nothing left to do }
  mai := Procs[mpi].ParamCount;
end;

procedure PyPackStarArgs(mpi: Integer; var argsHead, lastArg, nArgs: Integer);
var si, ki, n, nxt, pos, listSym, dictSym, keyNode, argNode: Integer;
    posHead, posLast, kwHead, kwLast: Integer;
begin
  si := ProcPyStarIdx[mpi];
  ki := ProcPyKwIdx[mpi];
  if (si < 0) and (ki < 0) then Exit;
  listSym := -1; dictSym := -1;
  posHead := -1; posLast := -1; kwHead := -1; kwLast := -1;
  pos := 0;
  n := argsHead;
  while n >= 0 do
  begin
    nxt := ASTRight[n];
    ASTRight[n] := -1;
    if ASTIVal[n] < 0 then
    begin
      if dictSym < 0 then dictSym := PyNewContainerTemp('TPyDict', 'kwargs');
      keyNode := (-ASTIVal[n]) - 1;
      PyContainerCall1(dictSym, 'TPyDict', 'setitem', keyNode, ASTLeft[n]);
    end
    else if ASTIVal[n] > 0 then
    begin
      { a keyword argument that DID match a declared parameter — kept, and it
        must stay after the positionals PyBindKwArgs counts }
      if kwHead < 0 then kwHead := n else ASTRight[kwLast] := n;
      kwLast := n;
    end
    else
    begin
      if (si >= 0) and (pos >= si) then
      begin
        if listSym < 0 then listSym := PyNewContainerTemp('TPyList', 'starargs');
        PyContainerCall1(listSym, 'TPyList', 'append', ASTLeft[n], -1);
      end
      else
      begin
        if posHead < 0 then posHead := n else ASTRight[posLast] := n;
        posLast := n;
      end;
      Inc(pos);
    end;
    n := nxt;
  end;
  if si >= 0 then
  begin
    if listSym < 0 then listSym := PyNewContainerTemp('TPyList', 'starargs');
    argNode := AllocNode(AN_ARG);
    ASTLeft[argNode] := PyMakeIdent(listSym);
    if posHead < 0 then posHead := argNode else ASTRight[posLast] := argNode;
    posLast := argNode;
  end;
  if ki >= 0 then
  begin
    if dictSym < 0 then dictSym := PyNewContainerTemp('TPyDict', 'kwargs');
    argNode := AllocNode(AN_ARG);
    ASTLeft[argNode] := PyMakeIdent(dictSym);
    if posHead < 0 then posHead := argNode else ASTRight[posLast] := argNode;
    posLast := argNode;
  end;
  if kwHead >= 0 then
  begin
    if posHead < 0 then posHead := kwHead else ASTRight[posLast] := kwHead;
    posLast := kwLast;
  end;
  argsHead := posHead;
  lastArg := posLast;
  nArgs := 0;
  n := posHead;
  while n >= 0 do
  begin
    Inc(nArgs);
    n := ASTRight[n];
  end;
end;

{ List literal [a, b, c] -> TPyList create + chained .append() calls, one
  expression tree (append returns Self). Reached from ParseFactor's PyExprMode
  tkLBrack branch, so nested literals in argument positions work too. }
procedure PyParseListLiteralT(opener, closer: TTokenKind; dedup: Boolean);
{ dedup = this is a SET literal. A set is a TPyList here, and TPyList.add is the
  method that carries the set contract (append only when absent) — but the
  literal built the list directly with append, so `{1, 2, 2, 3}` kept its
  duplicate while `set().add(2)` twice did not. The design was intact and one
  construction path skipped it (bug-nilpy-set-literal-does-not-deduplicate). }
var ci, recId, node, argNode, sizeNode, callNode, selfArg, valArg, mmi, mpi,
    tmpSym, asgn, starExt: Integer;
begin
  Expect(opener, '[');
  ci := FindUClass('TPyList');
  if ci < 0 then Error('Nil Python: pylib (TPyList) not loaded');
  recId := REC_UCLASS_BASE + ci;
  node := AllocNode(AN_CALL);
  ASTIVal[node] := -Ord(tkGetMem);
  ASTTk[node] := Ord(tyClass);
  ASTRight[node] := recId;
  sizeNode := AllocNode(AN_INT_LIT);
  ASTIVal[sizeNode] := RecSize(recId);
  ASTTk[sizeNode] := Ord(tyInteger);
  argNode := AllocNode(AN_ARG);
  ASTLeft[argNode] := sizeNode;
  ASTLeft[node] := argNode;
  { BIND the construction to a hidden temp and append onto the temp IDENT via
    hoisted statements, yielding the ident as the expression — instead of the
    old Self-returning call chain whose result doubled as the receiver. The
    temp OWNS the construction ref (rebind ARC), the scope-exit release drops
    it, and every consumer of the literal sees a borrowable lvalue — which is
    what lets arg-position literals reclaim (exec(src, {...}) leaked one
    container per call) (feature-nilpy-object-reclamation). The comprehension
    hoist already runs this same statement-queue in every statement context. }
  tmpSym := AllocVar(PyHiddenName('lit'), tyClass);
  Syms[tmpSym].RecName := recId;
  asgn := AllocNode(AN_ASSIGN);
  ASTLeft[asgn] := PyMakeIdent(tmpSym);
  ASTRight[asgn] := node;
  PyHoistStmt(asgn);
  if dedup then
  begin
    mmi := FindUMeth(ci, 'add');
    if mmi < 0 then Error('Nil Python: TPyList.add not found');
  end
  else
  begin
    mmi := FindUMeth(ci, 'append');
    if mmi < 0 then Error('Nil Python: TPyList.append not found');
  end;
  mpi := UMthProc_[mmi];
  while CurTok.Kind <> closer do
  begin
    { `None` as an ELEMENT is a real value in Python, and the slot can hold it —
      VT_EMPTY. Parsed as a nil literal everywhere else, it would box as integer
      0 (feature-nilpy-none-variant). }
    { `*xs` INSIDE a literal — `(family, -px, *styles)` splices the sequence in
      rather than adding it as one element. Python's iterable unpacking; unlike
      the call-argument form this works on ANY sequence, because the target is
      built at run time and can simply be EXTENDED. }
    if (CurTok.Kind = tkStar) and (TokPos < TokCount) and
       (Tokens[TokPos].Kind <> tkStar) then
    begin
      Next;
      PyParseBoolExpr;
      starExt := PyCallMeth1(ci, 'extend', PyMakeIdent(tmpSym), CurASTNode);
      if starExt < 0 then Error('Nil Python: pylib TPyList.extend not loaded');
      PyHoistStmt(starExt);
      if not Eat(tkComma) then break;
      Continue;
    end;
    if PyBareNoneHere then
    begin
      Next;
      CurASTNode := PyMakeNone;
    end
    else
      PyParseBoolExpr;
    valArg := AllocNode(AN_ARG);
    ASTLeft[valArg] := CurASTNode;
    selfArg := AllocNode(AN_ARG);
    ASTLeft[selfArg] := PyMakeIdent(tmpSym);
    ASTRight[selfArg] := valArg;
    callNode := AllocNode(AN_CALL);
    ASTIVal[callNode] := mpi;
    ASTTk[callNode] := Ord(tyClass);
    ASTLeft[callNode] := selfArg;
    PyHoistStmt(callNode);
    if not Eat(tkComma) then break;
  end;
  Expect(closer, ']/}');
  { A parenthesised display is a TUPLE, and a tuple is the same TPyList as a
    list here — so the only thing that can tell them apart when rendering is a
    flag set now, at the one place the syntax is still visible. Without it
    `print((1, 2))` printed `[1, 2]`
    (bug-nilpy-str-of-tuple-is-empty). Set-literal braces stay lists. }
  if opener = tkLParen then
  begin
    mpi := FindProc('pylist_mark_tuple');
    if mpi >= 0 then
    begin
      selfArg := AllocNode(AN_ARG);
      ASTLeft[selfArg] := PyMakeIdent(tmpSym);
      ASTRight[selfArg] := -1;
      callNode := AllocNode(AN_CALL);
      ASTIVal[callNode] := mpi;
      ASTTk[callNode] := Ord(tyClass);
      ASTLeft[callNode] := selfArg;
      PyHoistStmt(callNode);
    end;
  end;
  CurASTNode := PyMakeIdent(tmpSym);
end;

procedure PyParseListLiteral;
begin
  PyParseListLiteralT(tkLBrack, tkRBrack, False);
end;

{ `{a, b}` set literal — desugared to a TPyList (the corpus uses sets only
  for string membership via `in`; TPySet with real set semantics is a later
  rung). Dict literals will be distinguished by a ':' after the first key. }
(* A brace-delimited key/value literal lowers to
   TPyDict.Create.setitem(k, v).setitem(...) — the chained shape TPyList
   literals already use, so the whole literal is ONE expression node and needs
   no statement context. *)
procedure PyParseDictLiteral;
var ci, recId, node, argNode, sizeNode, callNode, selfArg, keyArg, valArg,
    mmi, mpi, keyNode, tmpSym, asgn: Integer;
begin
  Expect(tkBegin, 'open brace');
  ci := FindUClass('TPyDict');
  if ci < 0 then Error('Nil Python: pylib (TPyDict) not loaded');
  recId := REC_UCLASS_BASE + ci;
  node := AllocNode(AN_CALL);
  ASTIVal[node] := -Ord(tkGetMem);
  ASTTk[node] := Ord(tyClass);
  ASTRight[node] := recId;
  sizeNode := AllocNode(AN_INT_LIT);
  ASTIVal[sizeNode] := RecSize(recId);
  ASTTk[sizeNode] := Ord(tyInteger);
  argNode := AllocNode(AN_ARG);
  ASTLeft[argNode] := sizeNode;
  ASTLeft[node] := argNode;
  { bind-then-setitem via hoisted statements — see PyParseListLiteralT }
  tmpSym := AllocVar(PyHiddenName('lit'), tyClass);
  Syms[tmpSym].RecName := recId;
  asgn := AllocNode(AN_ASSIGN);
  ASTLeft[asgn] := PyMakeIdent(tmpSym);
  ASTRight[asgn] := node;
  PyHoistStmt(asgn);
  mmi := FindUMeth(ci, 'setitem');
  if mmi < 0 then Error('Nil Python: TPyDict.setitem not found');
  mpi := UMthProc_[mmi];
  while CurTok.Kind <> tkEnd do
  begin
    { `{**a, **b}` — dict SPREAD. Each `**expr` copies that dict's pairs into
      the literal being built, later keys winning, which is Python's merge rule.
      songformatter writes `{**major_scales, **minor_scales}.items()`.
      `**` arrives as two tkStar (the NilPy lexer has no `**` token). }
    if (CurTok.Kind = tkStar) and (TokPos < TokCount) and
       (Tokens[TokPos].Kind = tkStar) then
    begin
      Next; Next;
      PyParseBoolExpr;
      valArg := AllocNode(AN_ARG);
      ASTLeft[valArg] := CurASTNode;
      selfArg := AllocNode(AN_ARG);
      ASTLeft[selfArg] := PyMakeIdent(tmpSym);
      ASTRight[selfArg] := valArg;
      callNode := AllocNode(AN_CALL);
      ASTIVal[callNode] := FindProc('pydict_merge');
      if ASTIVal[callNode] < 0 then Error('Nil Python: pylib (pydict_merge) not loaded');
      ASTTk[callNode] := Ord(tyInteger);
      ASTLeft[callNode] := selfArg;
      PyHoistStmt(callNode);
      if not Eat(tkComma) then break;
      Continue;
    end;
    PyParseBoolExpr;
    keyNode := CurASTNode;
    Expect(tkColon, ':');
    { `None` as a VALUE is a real value in Python (VT_EMPTY) — parsed as a nil
      literal it boxes as integer 0, `is None` tag-tests false, and the usual
      `if d[k] is None:` miss-branch is skipped (same fix the list-literal
      element path carries, feature-nilpy-none-variant). }
    if PyBareNoneHere then
    begin
      Next;
      CurASTNode := PyMakeNone;
    end
    else
      PyParseBoolExpr;
    valArg := AllocNode(AN_ARG);
    ASTLeft[valArg] := CurASTNode;
    keyArg := AllocNode(AN_ARG);
    ASTLeft[keyArg] := keyNode;
    ASTRight[keyArg] := valArg;
    selfArg := AllocNode(AN_ARG);
    ASTLeft[selfArg] := PyMakeIdent(tmpSym);
    ASTRight[selfArg] := keyArg;
    callNode := AllocNode(AN_CALL);
    ASTIVal[callNode] := mpi;
    ASTTk[callNode] := Ord(tyClass);
    ASTLeft[callNode] := selfArg;
    PyHoistStmt(callNode);
    if not Eat(tkComma) then break;
  end;
  Expect(tkEnd, 'close brace');
  CurASTNode := PyMakeIdent(tmpSym);
end;

procedure PyParseSetLiteral;
begin
  if PyDictLiteralAhead then PyParseDictLiteral
  else PyParseListLiteralT(tkBegin, tkEnd, True);
end;

procedure PyCoerceAssignmentRHS(lhsTk: TTypeKind; rhsNode: Integer);
begin
  { Numeric casts are not represented by a shared AST node yet. For widened
    Double slots, rewrite integer literals at parse time so the ordinary
    floating store receives IEEE bits instead of an integer payload. }
  if (lhsTk = tyDouble) and (ASTKind[rhsNode] = AN_INT_LIT) and
     TypeIsOrdinal(IntToTypeKind(ASTTk[rhsNode])) then
  begin
    ASTKind[rhsNode] := AN_FLOAT_LIT;
    ASTIVal[rhsNode] := StrToDoubleBits(PyIntLiteralText(ASTIVal[rhsNode]));
    ASTTk[rhsNode] := Ord(tyDouble);
  end;
end;

function PyParseBlock: Integer; forward;
function PyMakeSuperCall(const name: AnsiString): Integer;
{ `super().<name>(args)` — Pascal's `inherited <name>(args)`. CurTok is the '('
  that opens the argument list; the caller has consumed `super ( ) . name`.
  Extracted from PyParseStatement so the EXPRESSION position can build the same
  node: `super()` was recognised in statement position only, so
  `return "B" + super().who()` died with "undefined variable (super)" — the two
  spellings Python offers for reaching an overridden method, and one of them
  parsed (bug-nilpy-super-and-unbound-parent-method-calls). }
var symIdx, ci, mmi, mpi, selfArg, lastArg, argNode, node, kwIdx, j, k: Integer;
begin
  { A REAL inherited call — Pascal's `inherited M(args)`. `super().__init__(p)`
    is how a class that extends a library widget gets built (songformatter's
    SettingsEditor extends tk.Frame), and discarding it left the base's own
    fields unset: the Tk path was empty, so every later command addressed a
    widget that had never been created. Direct call (not virtual): `super()`
    names the PARENT's body, which is what inherited means. }
  symIdx := PyProgSym('self');
  ci := -1;
  if CurSelfClass >= REC_UCLASS_BASE then ci := UClsParent[CurSelfClass - REC_UCLASS_BASE];
  if (ci >= 0) and (symIdx >= 0) then
  begin
    mmi := FindUMeth(ci, PyMethodName(name));
    if mmi >= 0 then
    begin
      mpi := UMthProc_[mmi];
      selfArg := AllocNode(AN_ARG);
      ASTLeft[selfArg] := PyMakeIdent(symIdx);
      ASTRight[selfArg] := -1;
      lastArg := selfArg;
      k := 1;
      while CurTok.Kind <> tkRParen do
      begin
        kwIdx := PyKwArgIndex(mpi, 1);
        PyParseBoolExpr;
        argNode := AllocNode(AN_ARG);
        ASTLeft[argNode] := CurASTNode;
        ASTIVal[argNode] := kwIdx;
        ASTRight[argNode] := -1;
        ASTRight[lastArg] := argNode;
        lastArg := argNode;
        Inc(k);
        if CurTok.Kind = tkComma then Next else Break;
      end;
      Expect(tkRParen, ')');
      j := 0;
      PyBindKwArgs(mpi, selfArg, lastArg, j);
      if j > 0 then k := j;
      { the base's remaining defaulted parameters }
      while (k < Procs[mpi].ParamCount) and (k < MAX_PROC_PARAMS) and
            ProcParamHasDefault[mpi * MAX_PROC_PARAMS + k] do
      begin
        argNode := AllocNode(AN_ARG);
        ASTLeft[argNode] := DefaultArgValueNode(mpi, k);
        ASTRight[argNode] := -1;
        ASTRight[lastArg] := argNode;
        lastArg := argNode;
        Inc(k);
      end;
      node := AllocNode(AN_CALL);
      ASTIVal[node] := mpi;
      ASTTk[node] := Ord(Procs[mpi].RetType);
      ASTLeft[node] := selfArg;
      Result := node;
      Exit;
    end;
  end;
  { fallback: no such method on the parent — consume and discard, as before }
  ci := 1;
  while (ci > 0) and (CurTok.Kind <> tkEOF) do
  begin
    if CurTok.Kind = tkLParen then Inc(ci)
    else if CurTok.Kind = tkRParen then Dec(ci);
    Next;
  end;
  Result := -1;
end;

function PyParseStatement: Integer; forward;
procedure PyParseImportRun; forward;   { `import` / `from ... import`, wherever it appears (pyparser.inc) }
procedure PyParseOneImport; forward;   { ONE import statement, inside a block (pyparser.inc) }

{ Spill incoming integer args into their frame slots, following the internal
  x86-64 call convention: up to 6 params arrive in rdi rsi rdx rcx r8 r9;
  a proc with MORE than 6 params receives ALL of them on the caller's stack,
  pushed left-to-right, so param i sits at [rbp+16+(nparams-1-i)*8]. }
{ Store rax into [rbp+off] with the width of the given size (1/2/4/8 bytes).
  A too-wide store would clobber the neighbouring 1-byte/2-byte slots (a bool
  param spilled as a dword smashed the adjacent param — silent wrong values,
  then SIGSEGV once the clobber reached self). }
procedure PyEmitStoreRaxWidth(off, size: Integer);
begin
  case size of
    1: begin EmitB($88); EmitB($85); end;               { mov [rbp+off], al }
    2: begin EmitB($66); EmitB($89); EmitB($85); end;   { mov [rbp+off], ax }
    4: begin EmitB($89); EmitB($85); end;               { mov [rbp+off], eax }
    else begin EmitB($48); EmitB($89); EmitB($85); end; { mov [rbp+off], rax }
  end;
  EmitI32(off);
end;

procedure PyEmitParamSpills(procIdx, nparams: Integer);
var i, idx, sz: Integer;
begin
  for i := 0 to nparams - 1 do
  begin
    idx := Procs[procIdx].Params[i].SymIdx;
    { a BY-REF param holds an ADDRESS, whatever it points at: spilling it at the
      pointee's width truncated a 64-bit stack address to 32 bits and the first
      write through it faulted (a `nonlocal` capture of an int local). }
    if Syms[idx].IsRef then sz := 8 else sz := TypeSize(Syms[idx].TypeKind);
    if nparams > 6 then
    begin
      { all-stack convention: load via rax }
      EmitB($48); EmitB($8B); EmitB($85); EmitI32(16 + 8 * (nparams - 1 - i));
    end
    else
    begin
      { mov rax, <arg reg i> }
      case i of
        0: begin EmitB($48); EmitB($89); EmitB($F8); end; { mov rax, rdi }
        1: begin EmitB($48); EmitB($89); EmitB($F0); end; { mov rax, rsi }
        2: begin EmitB($48); EmitB($89); EmitB($D0); end; { mov rax, rdx }
        3: begin EmitB($48); EmitB($89); EmitB($C8); end; { mov rax, rcx }
        4: begin EmitB($4C); EmitB($89); EmitB($C0); end; { mov rax, r8 }
        else begin EmitB($4C); EmitB($89); EmitB($C8); end; { mov rax, r9 }
      end;
    end;
    PyEmitStoreRaxWidth(Syms[idx].Offset, sz);
  end;
end;

{ Is this a `list * int` pair (either operand order)? }
function PyNodeIsPyList(n: Integer): Boolean;
var listCi: Integer;
begin
  Result := False;
  if n < 0 then Exit;
  if IntToTypeKind(ASTTk[n]) <> tyClass then Exit;
  listCi := FindUClass('TPyList');
  Result := (listCi >= 0) and (ResolveNodeRec(n) = REC_UCLASS_BASE + listCi);
end;

function PyListRepeatPair(a, b: Integer): Boolean;
begin
  Result := (PyNodeIsPyList(a) and TypeIsOrdinal(IntToTypeKind(ASTTk[b]))) or
            (PyNodeIsPyList(b) and TypeIsOrdinal(IntToTypeKind(ASTTk[a])));
end;

function PyNodeIsPyBytes(n: Integer): Boolean;
var byCi: Integer;
begin
  Result := False;
  if n < 0 then Exit;
  if IntToTypeKind(ASTTk[n]) <> tyClass then Exit;
  byCi := FindUClass('TPyBytes');
  Result := (byCi >= 0) and (ResolveNodeRec(n) = REC_UCLASS_BASE + byCi);
end;

{ `bytes([...]) * n` / `n * b` — Python bytes repetition (uforth's FILL:
  `bytes([ch]) * u`). Same shape as the list-repeat pair. }
function PyBytesRepeatPair(a, b: Integer): Boolean;
begin
  Result := (PyNodeIsPyBytes(a) and TypeIsOrdinal(IntToTypeKind(ASTTk[b]))) or
            (PyNodeIsPyBytes(b) and TypeIsOrdinal(IntToTypeKind(ASTTk[a])));
end;

{ helper-call builder for bytes binary ops (concat, eq) }
function PyMakeBytesBinCall(const fname: AnsiString; a, b: Integer; retTk: TTypeKind): Integer;
var procIdx, arg0, arg1: Integer;
begin
  procIdx := FindProc(fname);
  if procIdx < 0 then Error('Nil Python: pylib (' + fname + ') not loaded');
  arg0 := AllocNode(AN_ARG); ASTLeft[arg0] := a;
  arg1 := AllocNode(AN_ARG); ASTLeft[arg1] := b;
  ASTRight[arg0] := arg1;
  Result := AllocNode(AN_CALL);
  ASTIVal[Result] := procIdx;
  ASTTk[Result] := Ord(retTk);
  ASTLeft[Result] := arg0;
end;

{ list binop helper call, tagging the result with TPyList class identity so
  len()/subscript/iteration resolve on it. }
function PyMakeListBinCall(const fname: AnsiString; a, b: Integer): Integer;
var procIdx, arg0, arg1, ci: Integer;
begin
  procIdx := FindProc(fname);
  if procIdx < 0 then Error('Nil Python: pylib (' + fname + ') not loaded');
  arg0 := AllocNode(AN_ARG); ASTLeft[arg0] := a;
  arg1 := AllocNode(AN_ARG); ASTLeft[arg1] := b;
  ASTRight[arg0] := arg1;
  Result := AllocNode(AN_CALL);
  ASTIVal[Result] := procIdx;
  ASTTk[Result] := Ord(tyClass);
  ASTLeft[Result] := arg0;
  ci := FindUClass('TPyList');
  if ci >= 0 then ASTRight[Result] := REC_UCLASS_BASE + ci;
end;

function PyMakeBytesRepeat(a, b: Integer): Integer;
var byNode, cntNode, procIdx, arg0, arg1: Integer;
begin
  if PyNodeIsPyBytes(a) then begin byNode := a; cntNode := b; end
  else begin byNode := b; cntNode := a; end;
  procIdx := FindProc('pybytes_repeat');
  if procIdx < 0 then Error('Nil Python: pylib (pybytes_repeat) not loaded');
  arg0 := AllocNode(AN_ARG); ASTLeft[arg0] := byNode;
  arg1 := AllocNode(AN_ARG); ASTLeft[arg1] := cntNode;
  ASTRight[arg0] := arg1;
  Result := AllocNode(AN_CALL);
  ASTIVal[Result] := procIdx;
  ASTTk[Result] := Ord(tyClass);
  ASTLeft[Result] := arg0;
end;

{ Build pylist_repeat(list, count) for `xs * n` / `n * xs`. }
function PyMakeListRepeat(a, b: Integer): Integer;
var listNode, cntNode, procIdx, arg0, arg1: Integer;
begin
  if PyNodeIsPyList(a) then begin listNode := a; cntNode := b; end
  else begin listNode := b; cntNode := a; end;
  procIdx := FindProc('pylist_repeat');
  if procIdx < 0 then Error('Nil Python: pylib (pylist_repeat) not loaded');
  arg0 := AllocNode(AN_ARG); ASTLeft[arg0] := listNode;
  arg1 := AllocNode(AN_ARG); ASTLeft[arg1] := cntNode;
  ASTRight[arg0] := arg1;
  Result := AllocNode(AN_CALL);
  ASTIVal[Result] := procIdx;
  ASTTk[Result] := Ord(tyClass);
  ASTLeft[Result] := arg0;
end;

{ `<str> % <args>` — Python's printf-style interpolation, lowered to the pylib
  formatter. The argument travels as a VARIANT, which is what lets one helper
  take both shapes Python allows: a single value, or the TPyList a written tuple
  builds (bug-nilpy-percent-string-format-garbage). }
function PyMakePercentFormat(fmtNode, argsNode: Integer): Integer;
var procIdx, arg0, arg1: Integer;
begin
  procIdx := FindProc('pypercent_format');
  if procIdx < 0 then Error('Nil Python: pylib (pypercent_format) not loaded');
  arg0 := AllocNode(AN_ARG); ASTLeft[arg0] := fmtNode;
  arg1 := AllocNode(AN_ARG); ASTLeft[arg1] := argsNode; ASTRight[arg1] := -1;
  ASTRight[arg0] := arg1;
  Result := AllocNode(AN_CALL);
  ASTIVal[Result] := procIdx;
  ASTTk[Result] := Ord(tyAnsiString);
  ASTLeft[Result] := arg0;
end;

{ Wrap a TPyList / TPyDict expression in the pylib repr call, so it prints as
  Python spells a container. Anything else is returned unchanged. }
function PyReprContainer(n: Integer): Integer;
var rec, listCi, dictCi, procIdx, argNode, callNode: Integer; pname: AnsiString;
    excCi, argCi, fieldNode, mmi: Integer;
begin
  Result := n;
  if n < 0 then Exit;
  { a variant/Any arg may hold a container at runtime; route it through a runtime
    dispatcher (container -> repr, scalar -> str) so it never reaches the backend
    `<object>` placeholder (bug-nilpy-print-variant-holding-list). }
  if IntToTypeKind(ASTTk[n]) = tyVariant then
  begin
    procIdx := FindProc('pyvar_print_of');
    if procIdx < 0 then Exit;
    argNode := AllocNode(AN_ARG);
    ASTLeft[argNode] := n;
    callNode := AllocNode(AN_CALL);
    ASTIVal[callNode] := procIdx;
    ASTTk[callNode] := Ord(tyAnsiString);
    ASTLeft[callNode] := argNode;
    Result := callNode;
    Exit;
  end;
  if IntToTypeKind(ASTTk[n]) <> tyClass then Exit;
  rec := ResolveNodeRec(n);
  if rec < REC_UCLASS_BASE then Exit;
  { print(e) of an Exception (or subclass) shows its message, like Python's
    str(e) — read the `msg` field instead of the instance pointer
    (feature-nilpy-exception-message). }
  excCi := FindUClass('Exception');
  argCi := rec - REC_UCLASS_BASE;
  if (excCi >= 0) and ((argCi = excCi) or IsSubclassOf(argCi, excCi)) then
  begin
    fieldNode := AllocNode(AN_FIELD);
    ASTLeft[fieldNode] := n;
    ASTSOffset[fieldNode] := PyStoredName('msg');
    ASTSLen[fieldNode] := 3;
    ASTTk[fieldNode] := Ord(tyAnsiString);
    Result := fieldNode;
    Exit;
  end;
  { A class that defines `__str__` is rendered BY IT — Python's own rule, and
    what makes a shim class printable at all: without it `str(Path("a/b"))`
    printed the instance POINTER, silently. Checked before the pylib containers
    so a user class can override even those. }
  mmi := FindUMeth(argCi, '__str__');
  if mmi < 0 then mmi := FindUMeth(argCi, '__repr__');
  if mmi >= 0 then
  begin
    Result := PyCallMeth1(argCi, PyRawName(UMthNOff[mmi], UMthNLen[mmi]), n, -1);
    if Result < 0 then Result := n;
    Exit;
  end;
  listCi := FindUClass('TPyList');
  dictCi := FindUClass('TPyDict');
  if (listCi >= 0) and (rec = REC_UCLASS_BASE + listCi) then pname := 'pylist_repr'
  else if (dictCi >= 0) and (rec = REC_UCLASS_BASE + dictCi) then pname := 'pydict_repr'
  { bytes prints as b'...' like CPython — it fell through to the integer path
    and printed the instance pointer (bug-nilpy-user-class-bytes-method-loses-
    identity: the visible half; the annotated form hit this too). }
  else if (PyBytesCi >= 0) and (rec = REC_UCLASS_BASE + PyBytesCi) then pname := 'pybytes_repr'
  else Exit;
  procIdx := FindProc(pname);
  if procIdx < 0 then Exit;   { pylib not loaded — leave the old behaviour }
  argNode := AllocNode(AN_ARG);
  ASTLeft[argNode] := n;
  callNode := AllocNode(AN_CALL);
  ASTIVal[callNode] := procIdx;
  ASTTk[callNode] := Ord(tyAnsiString);
  ASTLeft[callNode] := argNode;
  Result := callNode;
end;

{ Which print KEYWORD ARGUMENT is at CurTok, or '' for a positional one.
  `print` is a builtin, not a def, so it never goes through the parameter-name
  matching that def/method keyword arguments use — it needs its own fixed set.
  (`end` is safe to spell: the NilPy lexer maps only a fixed keyword list and
  `end` is not on it, so it arrives as a plain tkIdent.) }
function PyPrintKwargAt: AnsiString;
var nm: AnsiString;
begin
  Result := '';
  { Keyed on the token TEXT, not its kind: `file` lexes as Pascal's tkFile
    keyword, and `end`/`sep` are only tkIdent by luck of the keyword list.
    Reading the text is robust to all of that. }
  if (TokPos < TokCount) and (Tokens[TokPos].Kind = tkAssign) and (TokPos >= 1) then
  begin
    nm := LowerCase(GetTokenStr(TokPos - 1));
    if (nm = 'sep') or (nm = 'end') or (nm = 'file') or (nm = 'flush') then
      Result := nm;
  end;
end;

{ `file=sys.stderr` -> the fd threaded into AN_WRITE/AN_WRITELN's ival slot,
  which is the same mechanism Pascal's `writeln(StdErr, ..)` already uses.
  Only the two standard streams are accepted; a real file object would need a
  file model NilPy does not have yet, and silently writing it to stdout would
  be worse than refusing. }
function PyParsePrintFile: Integer;
begin
  { sys.stdout / sys.stderr resolve to their fd as an ordinary expression (see
    PyParseSysStream), so this just parses one and reads the constant back.
    Only the two standard streams are accepted: a real file object needs a file
    model NilPy does not have, and quietly writing it to stdout would be worse
    than refusing. }
  PyParseBoolExpr;
  if (CurASTNode < 0) or (ASTKind[CurASTNode] <> AN_INT_LIT) or
     ((ASTIVal[CurASTNode] <> 1) and (ASTIVal[CurASTNode] <> 2)) then
    Error('Nil Python: print file= expects sys.stdout or sys.stderr');
  Result := ASTIVal[CurASTNode];
end;

function PyParsePrint: Integer;
var node, argNode, lastArg, sepLit, noneLit, endLit, writeFd: Integer;
    starProc, starArg, leadLit: Integer;
    kw, endText: AnsiString;
    haveEnd, isStar, sawStar: Boolean;
    pargTmp, pargAsgn: Integer;
    pargTk: TTypeKind;
begin
  Next;
  Expect(tkLParen, '(');
  node := AllocNode(AN_WRITELN);
  lastArg := -1;
  writeFd := 0;                { 0 = the default, which lowering reads as stdout }
  haveEnd := False;
  sawStar := False;
  endText := '';
  if CurTok.Kind <> tkRParen then
    repeat
      kw := PyPrintKwargAt;
      if kw <> '' then
      begin
        Next;                  { the keyword name }
        Expect(tkAssign, '=');
        if kw = 'flush' then
          { Accepted and IGNORED, deliberately: output is already emitted per
            statement, so there is nothing to flush. Consumed as an expression
            so the argument parses; the value is unused. }
          PyParseBoolExpr
        else if kw = 'file' then
          writeFd := PyParsePrintFile
        else if kw = 'sep' then
          { No censused use, and it cannot be done honestly here: separators are
            injected DURING the argument loop, while a keyword argument is only
            seen after it. Refused rather than silently ignored. }
          Error('Nil Python: print sep= is not supported yet')
        else
        begin
          if CurTok.Kind <> tkString then
            Error('Nil Python: print end= needs a literal string');
          endText := CurTok.SVal;
          haveEnd := True;
          Next;
        end;
        Continue;              { a keyword argument prints nothing itself }
      end;
      { `print(*xs)` — the argument list is UNPACKED from a list at run time, so
        its length (and therefore how many separators it contributes) is not a
        compile-time fact. pyprint_star renders the whole run into one string,
        separators included, which is why the synthetic space below is skipped
        for it. An argument AFTER a starred one is refused rather than
        approximated: the space between them exists only if the list was
        non-empty, and printing a stray one would be silently wrong output.
        (feature-nilpy-star-args-kwargs rung 2.) }
      isStar := CurTok.Kind = tkStar;
      if sawStar then
        Error('Nil Python: print() takes no further argument after *unpacking');
      { Python print separates successive arguments with a single space.
        Inject a synthetic space char arg before every argument after the
        first (a tyChar AN_INT_LIT writes the byte, not a number). This is the
        .npy print path only; Pascal writeln keeps its no-separator semantics. }
      if (lastArg >= 0) and (not isStar) then
      begin
        sepLit := AllocNode(AN_INT_LIT);
        ASTIVal[sepLit] := 32;
        ASTTk[sepLit] := Ord(tyChar);
        argNode := AllocNode(AN_ARG);
        ASTLeft[argNode] := sepLit;
        ASTRight[argNode] := -1;
        ASTIVal[argNode] := 0;
        ASTSOffset[argNode] := -2;
        ASTRight[lastArg] := argNode;
        lastArg := argNode;
      end;
      { A bare `None` prints as None, like CPython — the literal is a nil/zero
        value everywhere else, which printed as 0 (feature-nilpy-none-variant).
        A None-VALUED VARIANT is handled in the writer instead, since its tag is
        only known at run time. }
      if isStar then
      begin
        sawStar := True;
        Next;                  { the '*' }
        PyParseBoolExpr;
        if IntToTypeKind(ASTTk[CurASTNode]) <> tyClass then
          Error('Nil Python: print(*x) needs a list; got a value of another type');
        starProc := FindProc('pyprint_star');
        if starProc < 0 then Error('Nil Python: pylib (pyprint_star) not loaded');
        starArg := AllocNode(AN_ARG);
        ASTLeft[starArg] := CurASTNode;
        leadLit := AllocNode(AN_INT_LIT);
        if lastArg >= 0 then ASTIVal[leadLit] := 1 else ASTIVal[leadLit] := 0;
        ASTTk[leadLit] := Ord(tyBoolean);
        argNode := AllocNode(AN_ARG);
        ASTLeft[argNode] := leadLit;
        ASTRight[starArg] := argNode;
        CurASTNode := AllocNode(AN_CALL);
        ASTIVal[CurASTNode] := starProc;
        ASTTk[CurASTNode] := Ord(tyAnsiString);
        ASTLeft[CurASTNode] := starArg;
      end
      else if PyBareNoneHere then
      begin
        Next;
        noneLit := AllocNode(AN_STR_LIT);
        ASTSOffset[noneLit] := PyStoredName('None');
        ASTSLen[noneLit] := 4;
        ASTTk[noneLit] := Ord(tyString);
        CurASTNode := noneLit;
      end
      else
        PyParseBoolExpr;
      { A container argument prints its ELEMENTS (`['a', 'b']`), like Python.
        Without this it fell through to the integer path and printed the
        TPyList/TPyDict instance pointer — silently, in the single most natural
        debugging line there is (bug-a-nilpy-print-of-a-list-prints-a-pointer). }
      CurASTNode := PyReprContainer(CurASTNode);
      { A FLOAT argument goes through pystr_of too, for the same reason the
        container line above exists: otherwise print reaches the BACKEND float
        writer (EmitWriteFloatNat, hand-written per target) while `str()` uses
        FloatToStr, and the two disagree. They did — `print(1e19)` wrote
        `9223372036854775809.o72036854775808`, a byte that is not a digit,
        while `print(str(1e19))` was already correct
        (bug-nilpy-print-of-a-float-bypasses-str-formatting). Routing here fixes
        every target at once and makes print(x) and print(str(x)) agree by
        construction, which is Python's actual rule. }
      if (IntToTypeKind(ASTTk[CurASTNode]) = tyDouble) or
         (IntToTypeKind(ASTTk[CurASTNode]) = tySingle) then
      begin
        starProc := IRFindProc1ByArgTk('pystr_of', tyDouble);
        if starProc >= 0 then
        begin
          starArg := AllocNode(AN_ARG);
          ASTLeft[starArg] := CurASTNode;
          CurASTNode := AllocNode(AN_CALL);
          ASTIVal[CurASTNode] := starProc;
          ASTTk[CurASTNode] := Ord(tyAnsiString);
          ASTLeft[CurASTNode] := starArg;
        end;
      end;
      { Evaluate this argument into a hidden temp NOW, rather than letting
        AN_WRITELN's own lowering evaluate-and-emit each argument in turn.
        Python evaluates every argument before print writes anything; pxx
        wrote each one as it was computed, so `print("label =", str(3 % 0))`
        raising on its SECOND argument left the first already on stdout, and
        the handler's own fallback print appended to it instead of replacing
        it (bug-nilpy-print-emits-arguments-before-evaluating-later-ones).
        Hoisted (run before this whole print statement, in the same
        left-to-right order the arguments are parsed in), so by the time
        AN_WRITELN's lowering runs, every value is already sitting in a slot
        and nothing it does can raise. }
      pargTk := IntToTypeKind(ASTTk[CurASTNode]);
      pargTmp := AllocVar(PyHiddenName('parg'), pargTk);
      if pargTk = tyClass then Syms[pargTmp].RecName := ResolveNodeRec(CurASTNode);
      pargAsgn := AllocNode(AN_ASSIGN);
      ASTLeft[pargAsgn] := PyMakeIdent(pargTmp);
      ASTRight[pargAsgn] := CurASTNode;
      PyHoistStmt(pargAsgn);
      CurASTNode := PyMakeIdent(pargTmp);

      argNode := AllocNode(AN_ARG);
      ASTLeft[argNode] := CurASTNode;
      ASTRight[argNode] := -1;
      ASTIVal[argNode] := 0;     { field width: 0 = none }
      ASTSOffset[argNode] := -2; { decimals: -2 = Python-natural float format (EmitWriteFloatNat) }
      if lastArg < 0 then ASTLeft[node] := argNode
      else ASTRight[lastArg] := argNode;
      lastArg := argNode;
    until not Eat(tkComma);
  Expect(tkRParen, ')');
  { `end=` decides the STATEMENT KIND, not an argument: AN_WRITELN already
    appends the newline, so any other terminator means AN_WRITE (no newline)
    plus, when the terminator is non-empty, one more argument carrying it.
    end="\n" is exactly the default and stays a writeln. This matters for
    output correctness in uforth, not just tidiness: a Forth EMIT that appends
    a newline produces the wrong transcript against the CPython oracle. }
  if haveEnd and (endText <> #10) then
  begin
    ASTKind[node] := AN_WRITE;
    if endText <> '' then
    begin
      endLit := AllocNode(AN_STR_LIT);
      ASTSOffset[endLit] := PyStoredName(endText);
      ASTSLen[endLit] := Length(endText);
      ASTTk[endLit] := Ord(tyString);
      argNode := AllocNode(AN_ARG);
      ASTLeft[argNode] := endLit;
      ASTRight[argNode] := -1;
      ASTIVal[argNode] := 0;
      ASTSOffset[argNode] := -2;
      if lastArg < 0 then ASTLeft[node] := argNode
      else ASTRight[lastArg] := argNode;
      lastArg := argNode;
    end;
  end;
  ASTIVal[node] := writeFd;
  Result := node;
end;

{ A suite is either an INDENTED BLOCK or a one-line body on the same line as
  the header (`if not token: return None`). Python allows both everywhere a
  suite is legal, and uforth uses the one-line form heavily for guard clauses.
  Semicolon-separated statements are accepted in the one-line form, as Python
  does. }
function PyParseSuite: Integer;
var stmt, seq: Integer;
begin
  if CurTok.Kind = tkNewline then
  begin
    Expect(tkNewline, 'newline');
    Expect(tkIndent, 'indent');
    Result := PyParseBlock;
    Expect(tkDedent, 'dedent');
    Exit;
  end;
  seq := -1;
  repeat
    stmt := PyParseStatement;
    seq := PyFlushHoist(seq);
    seq := PySeqAppend(seq, stmt);
  until not Eat(tkSemicolon);
  if CurTok.Kind = tkNewline then Next;
  Result := seq;
end;

function PyParseIf: Integer;
var node, pairNode, condNode, thenNode, elseNode, condHoist: Integer;
begin
  Next;
  PyParseBoolExpr;
  condNode := PyMakeTruthy(CurASTNode);
  { protect the condition's hoisted setup from the nested suites' flush }
  condHoist := PyHoistHead; PyHoistHead := -1;
  Expect(tkColon, ':');
  thenNode := PyParseSuite;
  elseNode := -1;
  if PyIsIdent('elif') then
    elseNode := PyParseIf()
  else if CurTok.Kind = tkElse then
  begin
    Next;
    Expect(tkColon, ':');
    elseNode := PyParseSuite;
  end;
  PyHoistPrepend(condHoist);
  pairNode := AllocNode(AN_PAIR);
  ASTLeft[pairNode] := thenNode;
  ASTRight[pairNode] := elseNode;
  node := AllocNode(AN_IF);
  ASTLeft[node] := condNode;
  ASTRight[node] := pairNode;
  Result := node;
end;

{ Nil Python's `Exception` root. It is registered lazily — as an empty shell —
  because nothing declares it: a user writes `class ForthThrow(Exception)` or
  `except Exception:` and expects the base to already be there. Both sites call
  this so the class index is the same one either way. }
function PyEnsureExceptionClass: Integer;
var k: Integer;
begin
  PyEnsureExceptionClass := FindUClass('Exception');
  if PyEnsureExceptionClass < 0 then
  begin
    k := PyStoredName('Exception');
    AddUClass(k, 9);
    PyEnsureExceptionClass := FindUClass('Exception');
  end;
end;

{ `try:` / `except [Class [as name]]:` / `finally:` -> the shared AN_TRY_EXCEPT
  and AN_TRY_FINALLY nodes Pascal already lowers, so this is frontend shape
  only, no new runtime.

  Python allows except AND finally on one try; Pascal's nodes carry one or the
  other, so a try with both nests as TRY_FINALLY(TRY_EXCEPT(body, handlers),
  finalizer) — which is exactly Python's ordering (the handler runs first, the
  finalizer runs on every path out).

  A bare `except:` is the untyped catch-all (handler class -1); `except Class:`
  matches Class and its descendants, the same chain `on E: TFoo do` uses. The
  binder in `except Class as e:` becomes an ordinary local typed as the class,
  which is what makes `except ForthThrow as e: ... e.code` work. }
{ Is this `try:` the FALLBACK-IMPORT idiom — a block of nothing but imports,
  guarded by `except ImportError:` whose body is also nothing but imports? That
  shape is the most common portability construct in real Python, and under
  NilPy it is answered at COMPILE time: a module that does not resolve is not a
  runtime error we could catch, it is an import that cannot be compiled, so the
  frontend takes the other branch instead. CurTok is on `try`.
  feature-nilpy-fallback-import. }
function PyImportOnlyBlockAt(var k: Integer): Boolean;
{ k enters on the INDENT of a block; on True it leaves just past the matching
  DEDENT and every statement in between was an import. }
var stmtStart: Boolean;
begin
  PyImportOnlyBlockAt := False;
  if (k >= TokCount) or (Tokens[k].Kind <> tkIndent) then Exit;
  Inc(k);
  stmtStart := True;
  while k < TokCount do
  begin
    if Tokens[k].Kind = tkDedent then
    begin
      Inc(k);
      PyImportOnlyBlockAt := True;
      Exit;
    end;
    { a nested block cannot be a plain import run }
    if Tokens[k].Kind = tkIndent then Exit;
    if Tokens[k].Kind = tkNewline then stmtStart := True
    else if stmtStart then
    begin
      if not ((Tokens[k].Kind = tkUses) or
              ((Tokens[k].Kind = tkIdent) and CaseEqual(GetTokenStr(k), 'from'))) then Exit;
      stmtStart := False;
    end;
    Inc(k);
  end;
end;

{ Advance k from the INDENT of a block to just past its matching DEDENT. }
function PySkipToMatchingDedent(var k: Integer): Boolean;
var depth: Integer;
begin
  PySkipToMatchingDedent := False;
  if (k >= TokCount) or (Tokens[k].Kind <> tkIndent) then Exit;
  depth := 0;
  while k < TokCount do
  begin
    if Tokens[k].Kind = tkIndent then Inc(depth)
    else if Tokens[k].Kind = tkDedent then
    begin
      Dec(depth);
      if depth = 0 then begin Inc(k); PySkipToMatchingDedent := True; Exit; end;
    end;
    Inc(k);
  end;
end;

function PyIsFallbackImportTry: Boolean;
var i, blockAt: Integer;
begin
  PyIsFallbackImportTry := False;
  i := TokPos;                    { the ':' after `try` }
  if (i + 1 >= TokCount) or (Tokens[i].Kind <> tkColon) or
     (Tokens[i + 1].Kind <> tkNewline) then Exit;
  Inc(i, 2);
  while (i < TokCount) and (Tokens[i].Kind = tkNewline) do Inc(i);
  { the block must OPEN with an import — that is what makes the branch a
    resolution question rather than a runtime one }
  if (i >= TokCount) or (Tokens[i].Kind <> tkIndent) then Exit;
  blockAt := i;                   { the INDENT, for the block skip below }
  Inc(i);
  while (i < TokCount) and (Tokens[i].Kind = tkNewline) do Inc(i);
  if (i >= TokCount) then Exit;
  if not ((Tokens[i].Kind = tkUses) or
          ((Tokens[i].Kind = tkIdent) and CaseEqual(GetTokenStr(i), 'from'))) then Exit;
  { and the handler must be `except ImportError`, not a general one }
  i := blockAt;
  if not PySkipToMatchingDedent(i) then Exit;
  while (i < TokCount) and (Tokens[i].Kind = tkNewline) do Inc(i);
  if (i + 1 >= TokCount) or (Tokens[i].Kind <> tkExcept) then Exit;
  if (Tokens[i + 1].Kind <> tkIdent) or
     not CaseEqual(GetTokenStr(i + 1), 'ImportError') then Exit;
  PyIsFallbackImportTry := True;
end;

{ Consume the remainder of the block the parser is inside, stopping ON its
  DEDENT (which the caller consumes). }
procedure PySkipRestOfBlock;
var depth: Integer;
begin
  depth := 0;
  while CurTok.Kind <> tkEOF do
  begin
    if CurTok.Kind = tkIndent then Inc(depth)
    else if CurTok.Kind = tkDedent then
    begin
      if depth = 0 then Exit;
      Dec(depth);
    end;
    Next;
  end;
end;

{ Skip an indented block whole, without parsing it — the branch not taken. }
procedure PySkipIndentedBlock;
var depth: Integer;
begin
  Expect(tkIndent, 'indent');
  depth := 1;
  while (depth > 0) and (CurTok.Kind <> tkEOF) do
  begin
    if CurTok.Kind = tkIndent then Inc(depth)
    else if CurTok.Kind = tkDedent then Dec(depth);
    Next;
  end;
end;

{ `try: <imports> except ImportError: <imports>` resolved at compile time. The
  try-branch imports are attempted with the resolver in soft mode; if every
  module resolves, the except branch is skipped, and if any one misses, the
  except branch is compiled instead. Under CPython the same source prefers the
  try branch, so the file stays ordinary Python.

  A module that DID resolve before the missing one stays loaded. Python would
  have discarded that binding; here it costs an unused unit in the binary and
  nothing else, because unit scope is flat and the fallback branch rebinds the
  names it needs. }
function PyParseFallbackImportTry: Integer;
{ `try: <imports> ... except ImportError: ...` resolved at COMPILE time. An
  unresolvable module is not a runtime condition that could be caught — there is
  no code to run — so the frontend decides the branch instead: the try block's
  leading imports are attempted with the resolver in soft mode, and if any module
  is missing the whole try block is skipped and the handler compiled in its
  place. Under CPython the same source is ordinary Python and prefers the try
  branch, which is the point of the idiom.

  Two honest differences from CPython, both a consequence of deciding early:
  statements in the try block BEFORE the failing import do not run (here nothing
  in the block runs at all), and a module that resolved before the failing one
  stays loaded — an unused unit in the binary, since the handler rebinds whatever
  it needs. feature-nilpy-fallback-import. }
var body, savedHoist: Integer;
begin
  savedHoist := PyHoistHead;
  Next;                                { `try` }
  Expect(tkColon, ':');
  Expect(tkNewline, 'newline');
  PySkipNewlines;
  Expect(tkIndent, 'indent');
  SoftUnitResolve := True;
  SoftUnitMissed := False;
  PyParseImportRun;
  SoftUnitResolve := False;
  if SoftUnitMissed then
  begin
    { drop the rest of the try block: it depends on what did not resolve.
      Anything the IMPORT RUN itself queued as a hoisted setup statement goes
      with it — the block is not being compiled, so a setup for it would be
      emitted into the enclosing body naming symbols that block never
      allocated (render_backend's PIL guard did exactly this: a stray IR_LEA of
      a rolled-back temp, reported at the module's last line). }
    PyHoistHead := savedHoist;
    PySkipRestOfBlock;
    Expect(tkDedent, 'dedent');
    PySkipNewlines;
    Expect(tkExcept, 'except');
    Next;                              { ImportError }
    if PyIsIdent('as') then begin Next; Next; end;
    Expect(tkColon, ':');
    Expect(tkNewline, 'newline');
    PySkipNewlines;
    Expect(tkIndent, 'indent');
    body := PyParseBlock;
    Expect(tkDedent, 'dedent');
  end
  else
  begin
    body := PyParseBlock;              { the rest of the try block }
    Expect(tkDedent, 'dedent');
    PySkipNewlines;
    Expect(tkExcept, 'except');
    Next;                              { ImportError }
    if PyIsIdent('as') then begin Next; Next; end;
    Expect(tkColon, ':');
    Expect(tkNewline, 'newline');
    PySkipNewlines;
    PySkipIndentedBlock;               { the handler cannot be reached }
  end;
  { This statement consumed its own indented block(s) — and the DEDENT that
    closed the last one — exactly as a nested def does, so tell the block
    parser rather than leaving it to demand a newline that is gone.
    Without this a fallback-import inside a FUNCTION body made the next
    statement read as a continuation. }
  PyStmtAteBlock := True;
  PyParseFallbackImportTry := body;
end;

function PyParseTry: Integer;
var node, innerNode, trySeq, finSeq, handlerHead, lastHandler, handlerNode: Integer;
    actionSeq, handlerVar, ci, recId: Integer;
    handlerName, className: AnsiString;
    excRecs: array[0..15] of Integer; nExc, ei: Integer;   { except (A, B, ...) tuple }
begin
  Inc(GenTryDepth);
  Next;                                { `try` }
  Expect(tkColon, ':');
  Expect(tkNewline, 'newline');
  Expect(tkIndent, 'indent');
  trySeq := PyParseBlock;
  Expect(tkDedent, 'dedent');
  PySkipNewlines;

  handlerHead := -1;
  lastHandler := -1;
  while CurTok.Kind = tkExcept do
  begin
    Next;
    recId := -1;
    handlerVar := -1;
    nExc := 0;
    if CurTok.Kind <> tkColon then
    begin
      { `except Class:` OR `except (A, B, C):` — a tuple catches any of them.
        A tuple becomes one handler node per class, sharing the action and the
        binder (Python binds `e` to whichever was caught). }
      if CurTok.Kind = tkLParen then
      begin
        Next;
        while CurTok.Kind <> tkRParen do
        begin
          if CurTok.Kind <> tkIdent then Error('Nil Python: except: expected an exception class');
          className := CurTok.SVal;
          Next;
          { a QUALIFIED class inside the tuple too — `except (OSError,
            json.JSONDecodeError):` is how a file read is guarded. The single
            form below has taken this since tk.TclError; the tuple form did not,
            and reported the MODULE name as an unknown exception class. }
          if (CurTok.Kind = tkDot) and (TokPos < TokCount) and
             (Tokens[TokPos].Kind = tkIdent) then
          begin
            Next;
            className := CurTok.SVal;
            Next;
          end;
          if CaseEqual(className, 'Exception') then ci := PyEnsureExceptionClass
          else ci := FindUClass(className);
          if ci < 0 then Error('Nil Python: unknown exception class ' + className);
          if nExc > 15 then Error('Nil Python: too many exception classes in one except');
          excRecs[nExc] := REC_UCLASS_BASE + ci; Inc(nExc);
          if not Eat(tkComma) then Break;
        end;
        Expect(tkRParen, ')');
        recId := excRecs[0];
      end
      else
      begin
        if CurTok.Kind <> tkIdent then Error('Nil Python: except: expected an exception class');
        className := CurTok.SVal;
        Next;
        { `except tk.TclError:` — a QUALIFIED class. Unit scope is flat, so the
          member name alone resolves; the qualifier just has to be consumed. }
        if (CurTok.Kind = tkDot) and (TokPos < TokCount) and
           (Tokens[TokPos].Kind = tkIdent) then
        begin
          Next;
          className := CurTok.SVal;
          Next;
        end;
        if CaseEqual(className, 'Exception') then ci := PyEnsureExceptionClass
        else ci := FindUClass(className);
        if ci < 0 then Error('Nil Python: unknown exception class ' + className);
        recId := REC_UCLASS_BASE + ci;
        excRecs[0] := recId; nExc := 1;
      end;
      if PyIsIdent('as') then
      begin
        Next;
        if CurTok.Kind <> tkIdent then Error('Nil Python: except ... as: expected a name');
        handlerName := CurTok.SVal;
        Next;
        handlerVar := AllocVar(handlerName, tyClass);
        Syms[handlerVar].RecName := recId;   { the first listed class }
      end;
    end;
    Expect(tkColon, ':');
    Expect(tkNewline, 'newline');
    Expect(tkIndent, 'indent');
    Inc(ExceptionHandlerParseDepth);
    actionSeq := PyParseBlock;
    Dec(ExceptionHandlerParseDepth);
    Expect(tkDedent, 'dedent');
    PySkipNewlines;
    { one handler node per listed class (>=1); a bare `except:` has nExc=0 and
      still emits a single catch-all (recId -1). }
    ei := 0;
    repeat
      handlerNode := AllocNode(AN_EXC_HANDLER);
      if nExc = 0 then ASTIVal[handlerNode] := -1
      else ASTIVal[handlerNode] := excRecs[ei];
      ASTSOffset[handlerNode] := handlerVar;
      ASTLeft[handlerNode] := actionSeq;
      if handlerHead = -1 then handlerHead := handlerNode
      else ASTRight[lastHandler] := handlerNode;
      lastHandler := handlerNode;
      Inc(ei);
    until ei >= nExc;
  end;

  finSeq := -1;
  if CurTok.Kind = tkFinally then
  begin
    Next;
    Expect(tkColon, ':');
    Expect(tkNewline, 'newline');
    Expect(tkIndent, 'indent');
    finSeq := PyParseBlock;
    Expect(tkDedent, 'dedent');
  end;

  if (handlerHead = -1) and (finSeq = -1) then
    Error('Nil Python: try: needs an except: or a finally:');

  innerNode := trySeq;
  if handlerHead >= 0 then
  begin
    node := AllocNode(AN_TRY_EXCEPT);
    ASTLeft[node] := trySeq;
    ASTRight[node] := handlerHead;
    innerNode := node;
  end;
  if finSeq >= 0 then
  begin
    node := AllocNode(AN_TRY_FINALLY);
    ASTLeft[node] := innerNode;
    ASTRight[node] := finSeq;
    innerNode := node;
  end;
  Dec(GenTryDepth);
  PyParseTry := innerNode;
end;

function PyParseWhile: Integer;
var node, condHoist: Integer;
begin
  Next;
  PyParseBoolExpr;
  node := AllocNode(AN_WHILE);
  ASTLeft[node] := PyMakeTruthy(CurASTNode);
  { see PyParseIf: keep the condition's hoisted setup for the ENCLOSING
    flush. NOTE a literal in a while CONDITION is built once, before the
    loop — CPython rebuilds it per test; acceptable divergence, the pattern
    is `while x in ("a","b")` membership against constants. }
  condHoist := PyHoistHead; PyHoistHead := -1;
  Expect(tkColon, ':');
  ASTRight[node] := PyParseSuite;
  PyHoistPrepend(condHoist);
  Result := node;
end;

{ `with EXPR as VAR:` — desugared to `VAR = EXPR` followed by the body. The
  context-manager protocol (__enter__/__exit__) is not modelled: the only
  censused use is `with open(...) as f`, and pyopen reads the whole file
  eagerly, so there is nothing to close. A `with` without `as` runs the body
  after evaluating EXPR for its effect. }
function PyParseWith: Integer;
var exprNode, node, seq, symIdx: Integer; varName: AnsiString;
begin
  Next;                                  { consume `with` }
  PyParseBoolExpr;
  exprNode := CurASTNode;
  seq := -1;
  if PyIsIdent('as') then
  begin
    Next;
    if CurTok.Kind <> tkIdent then Error('Nil Python: with ... as: expected a name');
    varName := CurTok.SVal;
    Next;
    symIdx := PyProgSym(varName);
    if symIdx < 0 then symIdx := AllocVar(varName, IntToTypeKind(ASTTk[exprNode]));
    if IntToTypeKind(ASTTk[exprNode]) = tyClass then
      Syms[symIdx].RecName := ResolveNodeRec(exprNode);
    node := AllocNode(AN_ASSIGN);
    ASTLeft[node] := PyMakeIdent(symIdx);
    ASTRight[node] := exprNode;
    seq := PySeqAppend(seq, node);
  end
  else
    seq := PySeqAppend(seq, exprNode);   { evaluate for effect }
  Expect(tkColon, ':');
  seq := PySeqAppend(seq, PyParseSuite);
  PyStmtAteBlock := True;                 { consumed our own body block }
  Result := seq;
end;

{ A distinct name per hidden loop temp, so nested for-in loops do not share
  an index or a container slot. }
function PyHiddenName(const stem: AnsiString): AnsiString;
begin
  Inc(PyHiddenSeq);
  Result := '__py_' + stem + '_' + PyIntLiteralText(PyHiddenSeq);
end;

{ Rewrite every identifier token spelled `oldName` within [lo, hi) to
  `newName`. Used to give a comprehension's loop variable its OWN hidden
  binding: a comprehension's target is scoped to itself in Python (unlike a
  plain `for`, which deliberately leaks into the enclosing scope), and this
  compiler has no real block-scoping to fall back on, so the loop variable's
  references are re-spelled to a fresh hidden name instead
  (bug-nilpy-comprehension-variable-leaks-and-clobbers-the-enclosing-scope). }
procedure PyRenameIdentRange(lo, hi: Integer; const oldName, newName: AnsiString);
{ A raw token (TRawToken) has no string field of its own — its text is
  SOffset/SLen into the shared TokChars buffer, which existing tokens' bytes
  may overlap or alias. Point a matching token at a FRESH copy of `newName`
  interned via PyStoredName (memoised: every renamed token in this range
  shares the one copy) rather than writing through a field that does not
  exist on the raw token record. }
var k, newOff: Integer;
begin
  if (lo < 0) or (hi < 0) then Exit;
  newOff := -1;
  for k := lo to hi - 1 do
    if (Tokens[k].Kind = tkIdent) and (Tokens[k].SLen = Length(oldName)) and
       (GetTokenStrFromRaw(Tokens[k].SOffset, Tokens[k].SLen) = oldName) then
    begin
      if newOff < 0 then newOff := PyStoredName(newName);
      Tokens[k].SOffset := newOff;
      Tokens[k].SLen := Length(newName);
    end;
end;

{ A comprehension's loop-variable hidden name must be STABLE across repeated
  parses of the same source tokens: the typing pre-pass
  (PyCollectModuleLocalsAST) and the real pass both call PyParseForIn over
  the SAME token stream, and PyRenameIdentRange's rewrite of the identifier
  tokens is a PERMANENT mutation (raw tokens have no independent text of
  their own, see PyRenameIdentRange) — so a counter-based name (PyHiddenName)
  would rename 'x' to, say, '__py_x_2' on the pre-pass, then find no more
  literal 'x' tokens to rename on the real pass (they already read
  '__py_x_2') while allocating a DIFFERENT symbol name for that pass,
  leaving the token pointing at a symbol from the discarded pre-pass table
  ("undefined variable"). Deriving the name from the `for` token's own
  position instead of a counter makes the rename idempotent: pass two sees
  the token already renamed, matches nothing, and simply allocates its own
  fresh symbol under the same deterministic name the token already reads. }
function PyCompHiddenLoopName(tokIdx, slot: Integer): AnsiString;
begin
  Result := '__py_cv' + PyIntLiteralText(tokIdx) + '_' + PyIntLiteralText(slot);
end;

{ Find the depth-0 closing bracket of a comprehension/filter header starting
  at `fromTok`, tracking nested brackets so an inner `[...]`/`{...}` isn't
  mistaken for the outer one's closer. Also records the first depth-0 `if`
  (a filter clause) into `filtIdx`, without stopping there — the real closer
  sits AFTER the filter condition. }
function PyCompFindClose(fromTok: Integer; var filtIdx: Integer): Integer;
var fj, fdepth: Integer;
begin
  fj := fromTok;
  fdepth := 0;
  filtIdx := -1;
  Result := -1;
  while fj < TokCount do
  begin
    case Tokens[fj].Kind of
      tkLParen, tkLBrack, tkBegin: Inc(fdepth);
      tkRParen, tkRBrack, tkEnd:
        begin
          if fdepth = 0 then begin Result := fj; Exit; end;
          Dec(fdepth);
        end;
      tkNewline, tkEOF: Exit;
      tkIf: if (fdepth = 0) and (filtIdx < 0) then filtIdx := fj;
    end;
    Inc(fj);
  end;
end;

{ Build `container.<meth>(args...)` as an AN_CALL, given the container's class
  index. Returns -1 when the method is absent. }
function PyNodeListCi(n: Integer): Integer;
{ The TPyList class index when n is a list, else -1. `xs += ys` on lists is
  Python's IN-PLACE extend; lowering it as `xs := xs + ys` added the two class
  HANDLES and crashed (bug-a-nilpy-list-augmented-add-segfaults). }
var ci, rec: Integer;
begin
  PyNodeListCi := -1;
  if n < 0 then Exit;
  if IntToTypeKind(ASTTk[n]) <> tyClass then Exit;
  ci := FindUClass('TPyList');
  if ci < 0 then Exit;
  rec := ResolveNodeRec(n);
  if rec = REC_UCLASS_BASE + ci then PyNodeListCi := ci;
end;

function PyCallMeth1(ci: Integer; const mname: AnsiString;
                     selfNode, argNode: Integer): Integer;
var mmi, mpi, selfArg, valArg: Integer;
begin
  Result := -1;
  mmi := FindUMeth(ci, mname);
  if mmi < 0 then Exit;
  mpi := UMthProc_[mmi];
  selfArg := AllocNode(AN_ARG);
  ASTLeft[selfArg] := selfNode;
  if argNode >= 0 then
  begin
    valArg := AllocNode(AN_ARG);
    ASTLeft[valArg] := argNode;
    ASTRight[selfArg] := valArg;
  end;
  Result := AllocNode(AN_CALL);
  ASTIVal[Result] := mpi;
  ASTTk[Result] := Ord(Procs[mpi].RetType);
  ASTLeft[Result] := selfArg;
end;

function PyCallMeth2(ci: Integer; const mname: AnsiString;
                     selfNode, arg1, arg2: Integer): Integer;
var mmi, mpi, selfArg, a1, a2: Integer;
begin
  Result := -1;
  if ci < 0 then Exit;
  mmi := FindUMeth(ci, mname);
  if mmi < 0 then Exit;
  mpi := UMthProc_[mmi];
  selfArg := AllocNode(AN_ARG); ASTLeft[selfArg] := selfNode;
  a1 := AllocNode(AN_ARG); ASTLeft[a1] := arg1;
  a2 := AllocNode(AN_ARG); ASTLeft[a2] := arg2;
  ASTRight[selfArg] := a1;
  ASTRight[a1] := a2;
  Result := AllocNode(AN_CALL);
  ASTIVal[Result] := mpi;
  ASTTk[Result] := Ord(Procs[mpi].RetType);
  ASTLeft[Result] := selfArg;
end;

{ `for x in <list|set|dict|str>:` — desugared to a counted while loop:

      __py_c = <container>          (evaluated ONCE)
      __py_n = len(__py_c)
      __py_i = 0
      while __py_i < __py_n:
          x = __py_c[__py_i]
          <body>
          __py_i = __py_i + 1

  The container goes into a hidden local rather than being referenced three
  times: an IR value node is a SUBTREE, so reusing one RE-EMITS the expression
  (project_case_selector_reeval_and_fuzzer_narrowness) — here that would
  re-evaluate the container once per iteration.

  A dict iterates its KEYS, like Python, via keylist. A str yields 1-character
  strings. Everything else is a list-shaped TPyList.

  The loop variable is a Variant for a container and a str for a string; a
  body that only passes it along or prints it is correct today. Consuming one
  AS A SCALAR is bug-a-nilpy-variant-element-not-usable-as-scalar, which is
  Track A and predates this. }
{ Index of the '.' in a trailing `.items()` before the loop's ':', or -1. The
  suffix has to be recognised at TOKEN level: parsing it as an expression would
  look for a TPyDict method that does not exist, and inventing one would need a
  tuple type the two-name loop does not require. }
function PyItemsSuffixAhead: Integer;
var i, depth: Integer;
begin
  Result := -1;
  i := TokPos - 1;
  depth := 0;
  while i < TokCount do
  begin
    { The header ends at the loop's colon — OR, in a comprehension, at the
      closing brace or bracket (a comp has no colon). At depth 0 a tkEnd or
      tkRBrack IS that terminator; check for the .items() suffix before it. }
    if (depth = 0) and (Tokens[i].Kind in [tkColon, tkEnd, tkRBrack]) then
    begin
      if (i >= 4) and (Tokens[i - 4].Kind = tkDot) and
         (Tokens[i - 3].Kind = tkIdent) and (GetTokenStr(i - 3) = 'items') and
         (Tokens[i - 2].Kind = tkLParen) and (Tokens[i - 1].Kind = tkRParen) then
        Result := i - 4;
      Exit;
    end
    else if Tokens[i].Kind in [tkLParen, tkLBrack, tkBegin] then Inc(depth)
    else if Tokens[i].Kind in [tkRParen, tkRBrack, tkEnd] then Dec(depth)
    else if Tokens[i].Kind in [tkNewline, tkEOF] then Exit;
    Inc(i);
  end;
end;

{ Is the token stream at `[ EXPR for VAR in ...` — a list comprehension?
  CurTok is the '['. Scans at bracket depth 1 for a `for` keyword, the same
  disambiguation PyDictLiteralAt uses for ':'. }
{ Is the argument starting at CurTok a BARE generator expression — an EXPR
  followed by `for` before the argument ends (a depth-0 ',' or ')')? Used to
  divert to the comprehension desugar BEFORE the EXPR is parsed, because the
  EXPR references the loop variable, which is not in scope until the `for`. }
function PyBareGenExprAhead: Boolean;
var i, depth: Integer;
begin
  Result := False;
  i := TokPos - 1;                 { CurTok's index — first arg token }
  depth := 0;
  while i < TokCount do
  begin
    if Tokens[i].Kind in [tkLBrack, tkLParen, tkBegin] then Inc(depth)
    else if Tokens[i].Kind in [tkRBrack, tkRParen, tkEnd] then
    begin
      if depth = 0 then Exit;      { end of the call arg list }
      Dec(depth);
    end
    else if (depth = 0) and (Tokens[i].Kind = tkComma) then Exit
    else if (depth = 0) and (Tokens[i].Kind = tkIdent) and
            (LowerCase(GetTokenStr(i)) = 'for') then
    begin
      Result := True;
      Exit;
    end;
    Inc(i);
  end;
end;

function PyIsListCompAhead: Boolean;
var i, depth: Integer;
begin
  Result := False;
  if CurTok.Kind <> tkLBrack then Exit;
  { CurTok is the '[' (= Tokens[TokPos-1]); the first token inside it is
    Tokens[TokPos]. Scan Tokens[i] from there. }
  i := TokPos;
  depth := 1;
  while i < TokCount do
  begin
    if Tokens[i].Kind in [tkLBrack, tkLParen, tkBegin] then Inc(depth)
    else if Tokens[i].Kind in [tkRBrack, tkRParen, tkEnd] then
    begin
      Dec(depth);
      if depth = 0 then Exit;
    end
    else if (depth = 1) and (Tokens[i].Kind = tkFor) then
    begin
      Result := True;
      Exit;
    end
    else if (depth = 1) and (Tokens[i].Kind = tkIdent) and
            (LowerCase(GetTokenStr(i)) = 'for') then
    begin
      { NilPy lexes `for` as a plain ident, not tkFor (see PyParseFor's
        PyIsIdent('for')), so a comprehension's `for` is an ident here. }
      Result := True;
      Exit;
    end;
    Inc(i);
  end;
end;

{ Is the token stream at a brace-comprehension with a colon — a DICT
  comprehension (KEY colon VALUE for ...)? CurTok is the opening brace
  (tkBegin). A depth-1 `for` makes it a comprehension; a depth-1 ':' BEFORE
  that for makes it a dict one (a set comprehension has no colon). }
{ `( EXPR for VAR in ITER )` — a generator expression in its own parentheses,
  which is how it is written when it is not the only argument:
  `next((c for c in cs if p(c)), default)`. The bare form (no parens) is
  PyBareGenExprAhead; the bracketed form is PyIsListCompAhead. }
{ A SET comprehension — a brace group holding EXPR then `for`, with no depth-1
  ':' before that `for` (a ':' would make it a dict comprehension instead). }
function PyIsSetCompAhead: Boolean;
var i, depth: Integer;
begin
  Result := False;
  if CurTok.Kind <> tkBegin then Exit;
  i := TokPos;
  depth := 1;
  while i < TokCount do
  begin
    if Tokens[i].Kind in [tkLBrack, tkLParen, tkBegin] then Inc(depth)
    else if Tokens[i].Kind in [tkRBrack, tkRParen, tkEnd] then
    begin
      Dec(depth);
      if depth = 0 then Exit;
    end
    else if (depth = 1) and (Tokens[i].Kind = tkColon) then Exit   { a dict comp }
    else if (depth = 1) and (Tokens[i].Kind = tkIdent) and
            (LowerCase(GetTokenStr(i)) = 'for') then
    begin
      Result := True;
      Exit;
    end;
    Inc(i);
  end;
end;

function PyIsParenCompAhead: Boolean;
var i, depth: Integer;
begin
  Result := False;
  if CurTok.Kind <> tkLParen then Exit;
  i := TokPos;
  depth := 1;
  while i < TokCount do
  begin
    if Tokens[i].Kind in [tkLBrack, tkLParen, tkBegin] then Inc(depth)
    else if Tokens[i].Kind in [tkRBrack, tkRParen, tkEnd] then
    begin
      Dec(depth);
      if depth = 0 then Exit;
    end
    else if (depth = 1) and (Tokens[i].Kind = tkIdent) and
            (LowerCase(GetTokenStr(i)) = 'for') then
    begin
      Result := True;
      Exit;
    end;
    Inc(i);
  end;
end;

{ Is the argument of the `next(` at CurTok a SEQUENCE rather than an iterator
  object? A generator expression (bare or parenthesised) and a list literal are
  sequences; a plain name is only assumed to be one when it is a list-typed
  local. Anything else keeps the ordinary overload path, which is where
  itertools' counter lives. }
function PyNextOverListAhead: Boolean;
var i, depth, si: Integer;
begin
  Result := False;
  i := TokPos;                       { the '(' after `next` }
  if (i < TokCount) and (Tokens[i].Kind in [tkLParen, tkLBrack]) then
  begin
    { `next((x for x in xs), d)` / `next([...])` — the argument opens its own
      bracket; a `for` inside it at depth 1 makes it a generator. }
    depth := 0;
    while i < TokCount do
    begin
      if Tokens[i].Kind in [tkLParen, tkLBrack, tkBegin] then Inc(depth)
      else if Tokens[i].Kind in [tkRParen, tkRBrack, tkEnd] then
      begin
        Dec(depth);
        if depth = 0 then Break;
      end
      else if (depth = 2) and (Tokens[i].Kind = tkIdent) and
              (LowerCase(GetTokenStr(i)) = 'for') then
      begin
        Result := True;
        Exit;
      end;
      Inc(i);
    end;
  end;
  { a bare generator: `next(x for x in xs)` }
  i := TokPos + 1;
  depth := 1;
  while i < TokCount do
  begin
    if Tokens[i].Kind in [tkLParen, tkLBrack, tkBegin] then Inc(depth)
    else if Tokens[i].Kind in [tkRParen, tkRBrack, tkEnd] then
    begin
      Dec(depth);
      if depth = 0 then Break;
    end
    else if (depth = 1) and (Tokens[i].Kind = tkIdent) and
            (LowerCase(GetTokenStr(i)) = 'for') then
    begin
      Result := True;
      Exit;
    end;
    Inc(i);
  end;
  { a NAME that is a list-typed local }
  if (TokPos + 1 < TokCount) and (Tokens[TokPos + 1].Kind = tkIdent) then
  begin
    si := PyProgSym(GetTokenStr(TokPos + 1));
    if (si >= 0) and (Syms[si].TypeKind = tyClass) and
       (Syms[si].RecName = REC_UCLASS_BASE + FindUClass('TPyList')) then
      Result := True;
  end;
end;

function PyIsDictCompAhead: Boolean;
var i, depth: Integer; sawColon: Boolean;
begin
  Result := False;
  if CurTok.Kind <> tkBegin then Exit;
  i := TokPos; depth := 1; sawColon := False;
  while i < TokCount do
  begin
    if Tokens[i].Kind in [tkLBrack, tkLParen, tkBegin] then Inc(depth)
    else if Tokens[i].Kind in [tkRBrack, tkRParen, tkEnd] then
    begin
      Dec(depth);
      if depth = 0 then Exit;
    end
    else if (depth = 1) and (Tokens[i].Kind = tkColon) then sawColon := True
    else if (depth = 1) and (Tokens[i].Kind = tkIdent) and
            (LowerCase(GetTokenStr(i)) = 'for') then
    begin
      Result := sawColon;
      Exit;
    end;
    Inc(i);
  end;
end;

function PyParseForIn(const name: AnsiString; const name2: AnsiString; enumMode: Boolean;
                       forTokIdx: Integer): Integer;
var contNode, ci, dictCi, listCi, symIdx, cSym, iSym, nSym: Integer;
    sym2, vSym, vListNode, itemsDot: Integer;   { two-name target: `for k, v in d.items()` }
    elemNode, lenNode, node, cmpNode, incNode, bodyNode, seq, whileNode: Integer;
    compSaved, keyN, savedHoist, innerHoist: Integer;
    filtIdx, fj, fdepth, filtPair, filtN, closerPos: Integer;  { comprehension `if` filter }
    isStr, pairMode: Boolean; contTk, tk: TTypeKind;
    elemNode2, pairSym, plistSym, xi, nExtra, cci: Integer;
    extraSyms: array[0..5] of Integer;
    hName, hName2: AnsiString;
    hExtraNames: array[0..5] of AnsiString;
begin
  pairMode := False;
  { A comprehension filter — `[EXPR for V in ITER if COND]` — must not let the
    ITER expression parser see the `if`: it parses as a ternary head and dies
    on the missing else. Hide the depth-0 `if` behind a fake ':' while ITER
    parses (the .items() trick below); the body build restores and consumes
    it (feature-nilpy-comprehension-if-filter). Also locates the header's real
    closing bracket (AFTER the filter, not at it) so the loop-variable rename
    below can cover the filter condition too. }
  filtIdx := -1;
  closerPos := -1;
  if PyCompTarget >= 0 then
  begin
    fj := TokPos - 1;                  { CurTok's index = first ITER token }
    fdepth := 0;
    while fj < TokCount do
    begin
      case Tokens[fj].Kind of
        tkLParen, tkLBrack, tkBegin: Inc(fdepth);
        tkRParen, tkRBrack, tkEnd:
          begin
            if fdepth = 0 then begin closerPos := fj; break; end;  { the comprehension's own closer }
            Dec(fdepth);
          end;
        tkNewline, tkEOF: break;
        tkIf: if (fdepth = 0) and (filtIdx < 0) then filtIdx := fj;
      end;
      Inc(fj);
    end;
    if filtIdx >= 0 then Tokens[filtIdx].Kind := tkColon;
  end;
  { Give the comprehension's loop variable(s) their OWN hidden binding rather
    than reusing/creating a program symbol under the user's spelled name:
    Python scopes a comprehension's target to itself, so an outer `x` must
    survive `[x for x in ...]` untouched. Re-spell every reference to the
    name within the ELEMENT expression (before the `for`) and the filter
    condition (if any) to a fresh hidden name, then bind THAT name below —
    see PyRenameIdentRange
    (bug-nilpy-comprehension-variable-leaks-and-clobbers-the-enclosing-scope). }
  if PyCompTarget >= 0 then
  begin
    hName := PyCompHiddenLoopName(forTokIdx, 0);
    PyRenameIdentRange(PyCompExprStart, forTokIdx, name, hName);
    if filtIdx >= 0 then PyRenameIdentRange(filtIdx + 1, closerPos, name, hName);
    if name2 <> '' then
    begin
      hName2 := PyCompHiddenLoopName(forTokIdx, 1);
      PyRenameIdentRange(PyCompExprStart, forTokIdx, name2, hName2);
      if filtIdx >= 0 then PyRenameIdentRange(filtIdx + 1, closerPos, name2, hName2);
    end;
    for xi := 0 to PyForExtraCount - 1 do
    begin
      hExtraNames[xi] := PyCompHiddenLoopName(forTokIdx, 2 + xi);
      PyRenameIdentRange(PyCompExprStart, forTokIdx, PyForExtraName[xi], hExtraNames[xi]);
      if filtIdx >= 0 then
        PyRenameIdentRange(filtIdx + 1, closerPos, PyForExtraName[xi], hExtraNames[xi]);
    end;
  end;
  { `d.items()`: hide the suffix behind a fake ':' so the expression parser stops
    at the dict, then step over the four suffix tokens and restore. }
  itemsDot := -1;
  if (name2 <> '') and not enumMode then itemsDot := PyItemsSuffixAhead;
  if itemsDot >= 0 then Tokens[itemsDot].Kind := tkColon;
  { `for pfx in ("a", "b"):` — a TUPLE to iterate, built as the same TPyList a
    `[...]` literal produces, exactly as the `in` OPERATOR does. }
  if PyTupleParenAhead then
    PyParseListLiteralT(tkLParen, tkRParen, False)
  else
    PyParseBoolExpr;
  if itemsDot >= 0 then
  begin
    Tokens[itemsDot].Kind := tkDot;
    TokPos := itemsDot + 4;
    Next;
  end;
  if enumMode then Expect(tkRParen, ')');
  if filtIdx >= 0 then Tokens[filtIdx].Kind := tkIf;   { un-hide the filter }
  contNode := CurASTNode;
  { enumerate() over a STRING trips an inline-placeholder leak in the element
    tree (AN_INLINE_PARAM reaching IRLowerAST) — filed separately rather than
    worked around here, since a wrong lowering is worse than a clear refusal
    (bug-a-nilpy-enumerate-over-str-inline-param-leak). }
  if enumMode and ((IntToTypeKind(ASTTk[contNode]) = tyString) or
                   (IntToTypeKind(ASTTk[contNode]) = tyAnsiString)) then
    Error('Nil Python: enumerate() over a str is not supported yet — ' +
          'enumerate(list(s)) works');
  contTk := IntToTypeKind(ASTTk[contNode]);
  isStr := (contTk = tyString) or (contTk = tyAnsiString);
  listCi := FindUClass('TPyList');
  dictCi := FindUClass('TPyDict');
  { A VARIANT container — `for n in num` where num is Any — is unboxed to
    TPyList via pylib pylist_v. The corpus reaches this only under an
    `isinstance(num, list)` guard, so the value really is a list at run time;
    pylist_v raises if it is not. Without this the loop refused an untyped
    container (bug-nilpy-for-in-over-variant). }
  { A two-name target over a VARIANT is a DICT — `for option, value in
    options.items()` where options came out of another dict, which is exactly
    songformatter's DEFAULT_SETTINGS (a dict of dicts). Unboxed to TPyDict
    rather than to TPyList, and pydict_v raises if the value is not one. }
  if (not isStr) and (contTk = tyVariant) and (name2 <> '') and (not enumMode) then
  begin
    vSym := FindProc('pydict_v');
    if vSym < 0 then Error('Nil Python: pylib (pydict_v) not loaded');
    vListNode := AllocNode(AN_ARG);
    ASTLeft[vListNode] := contNode;
    ASTRight[vListNode] := -1;
    contNode := AllocNode(AN_CALL);
    ASTIVal[contNode] := vSym;
    ASTTk[contNode] := Ord(tyClass);
    ASTLeft[contNode] := vListNode;
    ASTRight[contNode] := REC_UCLASS_BASE + dictCi;
    contTk := tyClass;
  end
  else if (not isStr) and ((contTk = tyVariant) or (contTk = tyUnknown)) then
  begin
    { tyUNKNOWN too: a field read on a dynamically-typed receiver
      (`for c in result.candidates` where result came out of a list) has no
      static type at all, and refusing it read as "for-in needs a list, set,
      dict or str (got something untyped)". pylist_v decides at run time and
      raises if the value is not a sequence, which is the honest answer when
      the type genuinely is not known until then. }
    vSym := FindProc('pylist_v');
    if vSym < 0 then Error('Nil Python: pylib (pylist_v) not loaded');
    vListNode := AllocNode(AN_ARG);
    ASTLeft[vListNode] := contNode;
    ASTRight[vListNode] := -1;
    contNode := AllocNode(AN_CALL);
    ASTIVal[contNode] := vSym;
    ASTTk[contNode] := Ord(tyClass);
    ASTLeft[contNode] := vListNode;
    ASTRight[contNode] := REC_UCLASS_BASE + listCi;
    contTk := tyClass;
  end;
  ci := -1;
  if not isStr then
  begin
    ci := ResolveNodeRec(contNode);
    if ci >= REC_UCLASS_BASE then ci := ci - REC_UCLASS_BASE else ci := -1;
    if ci < 0 then
    begin
      { A class-typed expression with no CLASS IDENTITY — a field read on a
        dynamically-typed receiver, `for c in result.candidates` where `result`
        came out of a list. Refusing it read as "got something untyped"; unbox
        through pylist_v instead and let the run time decide, which is what the
        variant container path does and is the honest answer when the type is
        genuinely unknown until then. }
      vSym := FindProc('pylist_v');
      if vSym < 0 then Error('Nil Python: pylib (pylist_v) not loaded');
      vListNode := AllocNode(AN_ARG);
      ASTLeft[vListNode] := contNode;
      ASTRight[vListNode] := -1;
      contNode := AllocNode(AN_CALL);
      ASTIVal[contNode] := vSym;
      ASTTk[contNode] := Ord(tyClass);
      ASTLeft[contNode] := vListNode;
      ASTRight[contNode] := REC_UCLASS_BASE + listCi;
      ci := listCi;
    end;
    if (PyForExtraCount > 0) and (dictCi >= 0) and (ci = dictCi) then
      Error('Nil Python: a dict for-target takes two names');
    if (dictCi >= 0) and (ci = dictCi) then
    begin
      { A two-name target reads the dict's parallel VALUE list by the same
        index; a single name iterates its KEYS, as Python does. }
      if name2 <> '' then
      begin
        vSym := AllocVar(PyHiddenName('v'), tyClass);
        Syms[vSym].RecName := REC_UCLASS_BASE + listCi;
        vListNode := PyCallMeth1(dictCi, 'vallist', contNode, -1);
        if vListNode < 0 then Error('Nil Python: pylib (TPyDict.vallist) not loaded');
      end;
      contNode := PyCallMeth1(dictCi, 'keylist', contNode, -1);
      if contNode < 0 then Error('Nil Python: pylib (TPyDict.keylist) not loaded');
      ci := listCi;
    end
    else if (name2 <> '') and not enumMode then
      { `for key, score in pairs:` over a LIST — each element is itself a
        2-sequence and is UNPACKED into the two names, which is ordinary Python
        and what `sorted(d.items(), ...)` hands back. Only a dict and enumerate()
        were handled before. }
      pairMode := True;
  end
  else if (name2 <> '') and not enumMode then
    Error('Nil Python: a two-name for target needs a dict (.items()) or enumerate()');

  { Feed the loop target's element type into the SAME whole-program widening
    table a bare assignment feeds via PyNoteLocalType — only during a typing
    pre-pass round, never the real pass. Without this, a name already bound
    to a SCALAR (`c = 5`) that is later used as a `for c in <string>:` target
    kept its scalar slot forever: the pre-pass token scanner only recognises
    bare `name = expr` assignments as note-worthy, so it never learned that
    `c` also needs to hold a str, and the real pass created `c` as tyInteger
    at its first (and only, as far as the scanner knew) assignment. Widening
    the SLOT after code already targets it corrupts what is in the slot (two
    naive attempts at exactly that were tried and reverted — see the ticket) ;
    feeding the WHOLE-PROGRAM inference before either statement is really
    compiled is what already makes an ordinary `c = "x"; c = 5` rebind widen
    to a variant correctly, and the for-loop target was simply invisible to
    that mechanism
    (bug-nilpy-for-variable-reused-after-a-non-string-binding-iterates-garbage). }
  { A comprehension's loop variable is a fresh hidden binding (see above), not
    the spelled `name` at all, so it must not feed the whole-program widening
    table under the outer name — that would widen an outer binding of the
    same spelling based on the comprehension's own internal usage. }
  if PyTypingPass and (PyCompTarget < 0) then
  begin
    if enumMode then
    begin
      PyNoteLocalType(name, tyInteger, REC_NONE);
      if name2 <> '' then
      begin
        if isStr then PyNoteLocalType(name2, tyAnsiString, REC_NONE)
        else PyNoteLocalType(name2, tyVariant, REC_NONE);
      end;
    end
    else if pairMode then
    begin
      PyNoteLocalType(name, tyVariant, REC_NONE);
      if name2 <> '' then PyNoteLocalType(name2, tyVariant, REC_NONE);
    end
    else if isStr then
      PyNoteLocalType(name, tyAnsiString, REC_NONE)
    else
    begin
      PyNoteLocalType(name, tyVariant, REC_NONE);
      if name2 <> '' then PyNoteLocalType(name2, tyVariant, REC_NONE);  { dict values }
    end;
  end;

  { a comprehension ends its header at ']', not ':' — the body is synthetic }
  if PyCompTarget < 0 then Expect(tkColon, ':');
  { body suite (indented block or one-liner) is parsed below, after the
    hidden loop locals are allocated. }

  { hidden locals first, so the loop variable keeps the name the user wrote }
  if isStr then cSym := AllocVar(PyHiddenName('c'), tyAnsiString)
  else cSym := AllocVar(PyHiddenName('c'), tyClass);
  if not isStr then Syms[cSym].RecName := REC_UCLASS_BASE + ci;
  nSym := AllocVar(PyHiddenName('n'), tyInteger);
  iSym := AllocVar(PyHiddenName('i'), tyInteger);
  if PyCompTarget >= 0 then
  begin
    { A fresh hidden symbol every time — never reused across comprehensions,
      never resolved via PyProgSym — so the loop variable cannot clobber (or
      be clobbered by) any outer binding of the same spelled name. }
    if enumMode then tk := tyInteger
    else if isStr then tk := tyAnsiString
    else tk := tyVariant;
    symIdx := AllocVar(hName, tk);
  end
  else
  begin
    symIdx := PyProgSym(name);
    if symIdx < 0 then
    begin
      if enumMode then tk := tyInteger
      else if isStr then tk := tyAnsiString
      else tk := tyVariant;
      { A MODULE-level for-target created here for the first time must consult
        the whole-program widening table too, exactly like a bare assignment
        does a few lines up in PyParseStatement — otherwise the ORDER the two
        binding forms happen to appear in decides the outcome: `for c in "ab":
        pass` before `c = 5` created `c` as tyAnsiString right here (ignoring
        that PyModuleLocals already knows `c` is also assigned an int later),
        and the later `c = 5` stored a scalar int into a managed-string slot —
        SIGSEGV on release. Function-local targets do not need this: every
        local is pre-seeded from the converged PyLocals table before the body's
        real parse begins (see the `for i := 0 to PyLocalCount - 1` loop next to
        each PyCollectLocalsAST call), so `symIdx` is essentially never < 0
        there for a name the pre-pass already saw.
        (bug-nilpy-for-variable-reused-after-a-non-string-binding-iterates-garbage) }
      if CurProc < 0 then
      begin
        cci := PyFindModuleConstraint(name);
        if cci >= 0 then tk := PyWiden(tk, PyModuleLocals[cci].TypeKind);
      end;
      symIdx := AllocVar(name, tk);
    end;
  end;
  nExtra := PyForExtraCount;
  for xi := 0 to nExtra - 1 do
  begin
    if PyCompTarget >= 0 then
      extraSyms[xi] := AllocVar(hExtraNames[xi], tyVariant)
    else
    begin
      extraSyms[xi] := PyProgSym(PyForExtraName[xi]);
      if extraSyms[xi] < 0 then extraSyms[xi] := AllocVar(PyForExtraName[xi], tyVariant);
    end;
  end;
  sym2 := -1;
  if name2 <> '' then
  begin
    if PyCompTarget >= 0 then
    begin
      if isStr then sym2 := AllocVar(hName2, tyAnsiString)
      else sym2 := AllocVar(hName2, tyVariant);
    end
    else
    begin
      sym2 := PyProgSym(name2);
      if sym2 < 0 then
      begin
        { enumerate over a STRING yields 1-character strs, like the single-name
          str loop; a container yields variant slots }
        if isStr then sym2 := AllocVar(name2, tyAnsiString)
        else sym2 := AllocVar(name2, tyVariant);
      end;
    end;
  end;

  { An expression-position comprehension used AS the iterable hoists its build
    loop onto PyHoistHead. Drain it NOW, into this desugar's own init
    sequence: the body's PyParseSuite below also flushes the hoist, so leaving
    it pending moved the one-shot build INSIDE the loop body — the container
    temp was nil on the first iteration (len on nil = SIGSEGV)
    (bug-nilpy-comprehension-as-for-iterable-segfaults). }
  { __py_c := container }
  seq := PyFlushHoist(-1);
  node := AllocNode(AN_ASSIGN);
  ASTLeft[node] := PyMakeIdent(cSym);
  ASTRight[node] := contNode;
  seq := PySeqAppend(seq, node);
  { the dict form's parallel VALUE list — enumerate has no second container, and
    reading vSym/vListNode there took an UNINITIALISED node index, which landed
    in the retained-inline AST region and surfaced as "could not lower AST node
    (kind 78)" at the end of the program }
  if (sym2 >= 0) and (not enumMode) and (not pairMode) then
  begin
    { ...and pairMode is the third form with no second container: the pairs come
      from ONE list whose elements are unpacked, so reading vSym/vListNode here
      hit the same uninitialised-node trap this comment was written for. }
    node := AllocNode(AN_ASSIGN);
    ASTLeft[node] := PyMakeIdent(vSym);
    ASTRight[node] := vListNode;
    seq := PySeqAppend(seq, node);
  end;

  { __py_n := len(__py_c) }
  if isStr then
  begin
    lenNode := AllocNode(AN_CALL);
    ASTIVal[lenNode] := FindProc('pystr_len');
    if ASTIVal[lenNode] < 0 then Error('Nil Python: pylib (pystr_len) not loaded');
    ASTTk[lenNode] := Ord(tyInteger);
    node := AllocNode(AN_ARG);
    ASTLeft[node] := PyMakeIdent(cSym);
    ASTLeft[lenNode] := node;
  end
  else
  begin
    lenNode := PyCallMeth1(ci, 'count', PyMakeIdent(cSym), -1);
    if lenNode < 0 then Error('Nil Python: pylib (count) not loaded');
  end;
  node := AllocNode(AN_ASSIGN);
  ASTLeft[node] := PyMakeIdent(nSym);
  ASTRight[node] := lenNode;
  seq := PySeqAppend(seq, node);

  { __py_i := -1. The index starts BEFORE the first element and is advanced at
    the TOP of the body, so `continue` still advances it — with the increment
    at the bottom, `continue` skipped it and the loop hung. The condition
    tests the NEXT index for the same reason. }
  node := AllocNode(AN_ASSIGN);
  ASTLeft[node] := PyMakeIdent(iSym);
  elemNode := AllocNode(AN_INT_LIT);
  ASTIVal[elemNode] := -1;
  ASTTk[elemNode] := Ord(tyInteger);
  ASTRight[node] := elemNode;
  seq := PySeqAppend(seq, node);

  { body: __py_i := __py_i + 1 ; x := __py_c[__py_i] ; <user body> }
  incNode := AllocNode(AN_BINOP);
  ASTIVal[incNode] := Ord(tkPlus);
  ASTLeft[incNode] := PyMakeIdent(iSym);
  elemNode := AllocNode(AN_INT_LIT);
  ASTIVal[elemNode] := 1;
  ASTTk[elemNode] := Ord(tyInteger);
  ASTRight[incNode] := elemNode;
  ASTTk[incNode] := Ord(tyInteger);
  node := AllocNode(AN_ASSIGN);
  ASTLeft[node] := PyMakeIdent(iSym);
  ASTRight[node] := incNode;
  bodyNode := PySeqAppend(-1, node);

  if isStr then
  begin
    elemNode := PyMakeStrIndex(PyMakeIdent(cSym), PyMakeIdent(iSym));
    { pystr_at yields a Char; the loop variable is a 1-character str }
    node := AllocNode(AN_CALL);
    ASTIVal[node] := FindProc('pystr_ofchar');
    if ASTIVal[node] < 0 then Error('Nil Python: pylib (pystr_ofchar) not loaded');
    ASTTk[node] := Ord(tyAnsiString);
    cmpNode := AllocNode(AN_ARG);
    ASTLeft[cmpNode] := elemNode;
    ASTLeft[node] := cmpNode;
    elemNode := node;
  end
  else
  begin
    elemNode := PyCallMeth1(ci, 'at', PyMakeIdent(cSym), PyMakeIdent(iSym));
    if elemNode < 0 then Error('Nil Python: pylib (get) not loaded');
  end;
  if enumMode then
  begin
    { i := __py_i ; v := __py_c[__py_i] }
    node := AllocNode(AN_ASSIGN);
    ASTLeft[node] := PyMakeIdent(symIdx);
    ASTRight[node] := PyMakeIdent(iSym);
    bodyNode := PySeqAppend(bodyNode, node);
    node := AllocNode(AN_ASSIGN);
    ASTLeft[node] := PyMakeIdent(sym2);
    ASTRight[node] := elemNode;
    bodyNode := PySeqAppend(bodyNode, node);
  end
  else if pairMode then
  begin
    { name1 := elem[0]; name2 := elem[1]. The element is bound to a hidden local
      FIRST: reusing the element expression twice duplicated the inlined body of
      TPyList.at and leaked an AN_INLINE_PARAM placeholder into lowering
      (IR_UNSUPPORTED). One read, two indexes. }
    pairSym := AllocVar(PyHiddenName('pair'), tyVariant);
    elemNode2 := AllocNode(AN_ASSIGN);
    ASTLeft[elemNode2] := PyMakeIdent(pairSym);
    ASTRight[elemNode2] := elemNode;
    bodyNode := PySeqAppend(bodyNode, elemNode2);
    { Indexed through pylib's pyvar_getitem, NOT through TPyList.at: `at` is an
      INLINED method, and an inlined body reached from here leaked its
      AN_INLINE_PARAM placeholder into lowering (IR_UNSUPPORTED). pyvar_getitem
      is an ordinary function and takes the variant as it stands, so no unbox is
      needed either. }
    node := PyPairItem(PyMakeIdent(pairSym), 0);
    elemNode2 := AllocNode(AN_ASSIGN);
    ASTLeft[elemNode2] := PyMakeIdent(symIdx);
    ASTRight[elemNode2] := node;
    bodyNode := PySeqAppend(bodyNode, elemNode2);
    node := PyPairItem(PyMakeIdent(pairSym), 1);
    elemNode2 := AllocNode(AN_ASSIGN);
    ASTLeft[elemNode2] := PyMakeIdent(sym2);
    ASTRight[elemNode2] := node;
    bodyNode := PySeqAppend(bodyNode, elemNode2);
    { and any names past the second — `for anchor, weight, label in triples:` }
    for xi := 0 to nExtra - 1 do
    begin
      node := PyPairItem(PyMakeIdent(pairSym), xi + 2);
      elemNode2 := AllocNode(AN_ASSIGN);
      ASTLeft[elemNode2] := PyMakeIdent(extraSyms[xi]);
      ASTRight[elemNode2] := node;
      bodyNode := PySeqAppend(bodyNode, elemNode2);
    end;
  end
  else
  begin
    node := AllocNode(AN_ASSIGN);
    ASTLeft[node] := PyMakeIdent(symIdx);
    ASTRight[node] := elemNode;
    bodyNode := PySeqAppend(bodyNode, node);
  end;

  { the value name reads the parallel list at the same index }
  if (sym2 >= 0) and (not enumMode) and (not pairMode) then
  begin
    elemNode := PyCallMeth1(listCi, 'at', PyMakeIdent(vSym), PyMakeIdent(iSym));
    if elemNode < 0 then Error('Nil Python: pylib (get) not loaded');
    node := AllocNode(AN_ASSIGN);
    ASTLeft[node] := PyMakeIdent(sym2);
    ASTRight[node] := elemNode;
    bodyNode := PySeqAppend(bodyNode, node);
  end;

  if PyCompTarget >= 0 then
  begin
    { comprehension body: `target.append(EXPR)`. EXPR sits BEFORE the `for`, so
      jump back to it, parse it with the loop variable now in scope, then
      restore the cursor (the `]` the header stopped at). The `TokPos := k;
      Next` idiom re-reads a token to restore CurTok, as the factory-default
      re-parse does. }
    { NESTED comprehension: the element expression may itself be one, and it
      HOISTS its own build loop. Those statements must land INSIDE this loop,
      not in front of it — in front, the inner loop runs before this loop's
      variable is bound, which is why
      `{k: [f(x) for x in g(k)] for k in ks}` reported `undefined variable (k)`.
      So the hoist queue is swapped out around the element parse and whatever it
      collected is spliced into the body ahead of the append
      (feature-nilpy-nested-comprehension). }
    savedHoist := PyHoistHead;
    PyHoistHead := -1;
    compSaved := TokPos - 1;              { index of CurTok (the closing bracket) }
    TokPos := PyCompExprStart; Next;      { CurTok := first EXPR token }
    if PyCompIsDict then
    begin
      { element region is KEY colon VALUE -> target.store(KEY, VALUE) }
      PyParseBoolExpr;
      keyN := CurASTNode;
      Expect(tkColon, ':');
      PyParseBoolExpr;
      node := PyCallMeth2(FindUClass('TPyDict'), 'store',
                          PyMakeIdent(PyCompTarget), keyN, CurASTNode);
      if node < 0 then Error('Nil Python: pylib TPyDict.store not loaded');
    end
    else
    begin
      PyParseBoolExpr;
      if PyCompIsSet then
        node := PyCallMeth1(PyNodeListCi(PyMakeIdent(PyCompTarget)), 'add',
                            PyMakeIdent(PyCompTarget), CurASTNode)
      else
        node := PyCallMeth1(PyNodeListCi(PyMakeIdent(PyCompTarget)), 'append',
                            PyMakeIdent(PyCompTarget), CurASTNode);
      if node < 0 then Error('Nil Python: pylib TPyList.append/add not loaded');
    end;
    TokPos := compSaved; Next;            { restore to the closing bracket }
    { `... if COND]`: parse the filter (loop variable now in scope) and gate
      the append on it. The cursor lands on the real closer for the caller. }
    if CurTok.Kind = tkIf then
    begin
      Next;
      PyParseBoolExpr;
      filtN := AllocNode(AN_IF);
      ASTLeft[filtN] := PyMakeTruthy(CurASTNode);
      filtPair := AllocNode(AN_PAIR);
      ASTLeft[filtPair] := node;
      ASTRight[filtPair] := -1;
      ASTRight[filtN] := filtPair;
      node := filtN;
    end;
    { splice the element's own hoisted setup in FIRST, then restore the
      enclosing statement's queue }
    innerHoist := PyHoistHead;
    PyHoistHead := savedHoist;
    while innerHoist >= 0 do
    begin
      bodyNode := PySeqAppend(bodyNode, ASTLeft[innerHoist]);
      innerHoist := ASTRight[innerHoist];
    end;
  end
  else
    node := PyParseSuite;

  bodyNode := PySeqAppend(bodyNode, node);

  { while __py_i + 1 < __py_n }
  incNode := AllocNode(AN_BINOP);
  ASTIVal[incNode] := Ord(tkPlus);
  ASTLeft[incNode] := PyMakeIdent(iSym);
  elemNode := AllocNode(AN_INT_LIT);
  ASTIVal[elemNode] := 1;
  ASTTk[elemNode] := Ord(tyInteger);
  ASTRight[incNode] := elemNode;
  ASTTk[incNode] := Ord(tyInteger);
  cmpNode := AllocNode(AN_BINOP);
  ASTIVal[cmpNode] := Ord(tkLt);
  ASTLeft[cmpNode] := incNode;
  ASTRight[cmpNode] := PyMakeIdent(nSym);
  ASTTk[cmpNode] := Ord(tyBoolean);
  whileNode := AllocNode(AN_WHILE);
  ASTLeft[whileNode] := cmpNode;
  ASTRight[whileNode] := bodyNode;
  { A desugared `for` returns an AN_SEQ (init statements + the while), not an
    AN_WHILE, so PyParseBlock's "this statement consumed its own indented
    block" check — which matches on node KIND — did not recognise it, and any
    statement following a for inside a def died with "expected newline after
    statement". Reuse the flag nested defs already use to say the same thing.
    (bug-nilpy-statement-after-for-in-a-def) }
  PyStmtAteBlock := True;
  Result := PySeqAppend(seq, whileNode);
end;

{ `target = [ EXPR for VAR in ITER ]`. Desugars to: create a fresh TPyList in
  `target`, then a for-loop over ITER whose body is `target.append(EXPR)`.
  Reuses PyParseForIn for the iteration itself (range / list / variant unbox all
  come free) via PyCompTarget/PyCompExprStart; see those globals. CurTok is the
  '[' and `targetSym` is the already-declared destination local. Returns the
  statement sequence; PyStmtAteBlock is left set by PyParseForIn. }

{ Shared comprehension core: emit `targetSym := TPyList.Create` then the
  appending loop. CurTok must be AT the `for` (an ident); `exprStart` is the
  token index of the element EXPR (which sits before the `for`). Returns the
  statement sequence. Does NOT consume a trailing `]` — the caller does that
  for a bracketed comprehension; a bare genexpr has none. }
{ Advance to THIS comprehension's `for`, skipping any nested one. The scan used
  to stop at the first `for` it saw, so `[[c for c in k] for k in ks]` split at
  the INNER for: the outer comprehension took `[c` as its element and
  `for c in k` as its header, and `k` was undefined because the outer loop
  variable had not been introduced yet. Bracket depth is what tells them apart —
  a nested comprehension is always inside its own brackets or parens.
  (feature-nilpy-nested-comprehension) }
procedure PyScanToCompFor;
var depth: Integer;
begin
  depth := 0;
  while CurTok.Kind <> tkEOF do
  begin
    case CurTok.Kind of
      tkLBrack, tkLParen, tkBegin: Inc(depth);
      tkRBrack, tkRParen, tkEnd:
        begin
          if depth = 0 then Break;      { our own closer — malformed, caller reports }
          Dec(depth);
        end;
    end;
    if (depth = 0) and PyIsIdent('for') then Exit;
    Next;
  end;
end;

function PyBuildComp(targetSym, exprStart: Integer): Integer;
var seq, node, sizeNode, createNode, aSeq, savedTarget, savedStart, listCiN: Integer;
    buildSym: Integer;
begin
  if PyCompIsDict then listCiN := FindUClass('TPyDict')
  else listCiN := FindUClass('TPyList');
  if listCiN < 0 then Error('Nil Python: pylib (TPyList/TPyDict) not loaded');
  createNode := AllocNode(AN_CALL);
  ASTIVal[createNode] := -Ord(tkGetMem);
  ASTTk[createNode] := Ord(tyClass);
  ASTRight[createNode] := REC_UCLASS_BASE + listCiN;
  sizeNode := AllocNode(AN_INT_LIT);
  ASTIVal[sizeNode] := RecSize(REC_UCLASS_BASE + listCiN);
  ASTTk[sizeNode] := Ord(tyInteger);
  aSeq := AllocNode(AN_ARG);
  ASTLeft[aSeq] := sizeNode;
  ASTLeft[createNode] := aSeq;
  Syms[targetSym].RecName := REC_UCLASS_BASE + listCiN;
  { Build into a HIDDEN list and assign it at the end. Emptying the target
    first is fatal when the target is also the SOURCE — `lines = [l.strip()
    for l in lines]` re-binds a name Python evaluates on the right first, and
    building in place cleared the list the loop was about to read, so the
    comprehension always produced []. }
  buildSym := AllocVar(PyHiddenName('comp'), tyClass);
  Syms[buildSym].RecName := REC_UCLASS_BASE + listCiN;
  node := AllocNode(AN_ASSIGN);
  ASTLeft[node] := PyMakeIdent(buildSym);
  ASTRight[node] := createNode;
  seq := PySeqAppend(-1, node);

  savedTarget := PyCompTarget;
  savedStart := PyCompExprStart;
  PyCompTarget := buildSym;
  PyCompExprStart := exprStart;
  node := PyParseFor;               { range/container both honour PyCompTarget }
  PyCompTarget := savedTarget;
  PyCompExprStart := savedStart;    { a NESTED build clobbers it otherwise }
  seq := PySeqAppend(seq, node);
  node := AllocNode(AN_ASSIGN);
  ASTLeft[node] := PyMakeIdent(targetSym);
  ASTRight[node] := PyMakeIdent(buildSym);
  seq := PySeqAppend(seq, node);
  { PyParseFor sets PyStmtAteBlock (it normally eats an indented block); a
    comprehension is a one-line expression, so clear it. }
  PyStmtAteBlock := False;
  Result := seq;
end;

{ Statement-level `target = [EXPR for VAR in ITER]`. CurTok is the '['. }
function PyParseListComp(targetSym: Integer): Integer;
var exprStart: Integer;
begin
  Next;                                { consume '[' — CurTok = first EXPR token }
  exprStart := TokPos - 1;
  PyScanToCompFor;
  if not PyIsIdent('for') then Error('Nil Python: malformed list comprehension');
  Result := PyBuildComp(targetSym, exprStart);
  Expect(tkRBrack, ']');
end;

{ Statement-level dict comprehension (target = brace KEY colon VALUE for VAR in
  ITER brace). CurTok is the opening brace. The element region KEY colon VALUE
  is re-parsed in the loop body as target.store(KEY, VALUE) (PyCompIsDict). }
function PyParseDictComp(targetSym: Integer): Integer;
var exprStart: Integer;
begin
  Next;                                { consume the opening brace; CurTok = KEY }
  exprStart := TokPos - 1;
  PyScanToCompFor;
  if not PyIsIdent('for') then Error('Nil Python: malformed dict comprehension');
  PyCompIsDict := True;
  Result := PyBuildComp(targetSym, exprStart);
  PyCompIsDict := False;
  Expect(tkEnd, 'close brace');
end;

{ Expression-position comprehension/genexpr — `[EXPR for x in it]` as a call
  argument, or a bare `EXPR for x in it` genexpr. Allocates a hidden temp,
  HOISTS the build loop to run before the enclosing statement, and yields the
  temp. `bracketed` says whether a '[' (and closing ']') delimits it; a bare
  genexpr has neither. CurTok is the '[' (bracketed) or the first EXPR token
  (bare). Returns the temp's ident node. }
function PyParseCompExprValue(bracketed: Boolean): Integer;
var tmpSym, exprStart, seq: Integer; savedDict: Boolean;
begin
  { A LIST comprehension nested inside a DICT one must not inherit dict mode:
    PyCompIsDict is global, so `{k: [c for c in k] for k in ks}` built the inner
    comprehension as a dict and died on the missing `:`
    (feature-nilpy-nested-comprehension). }
  savedDict := PyCompIsDict;
  PyCompIsDict := False;
  tmpSym := AllocVar(PyHiddenName('gx'), tyClass);
  if bracketed then Next;              { consume '[' }
  exprStart := TokPos - 1;             { first EXPR token }
  PyScanToCompFor;
  if not PyIsIdent('for') then Error('Nil Python: malformed comprehension');
  seq := PyBuildComp(tmpSym, exprStart);
  PyCompIsDict := savedDict;
  if bracketed then Expect(tkRBrack, ']');
  { each build statement runs before the current one }
  while seq >= 0 do
  begin
    PyHoistStmt(ASTLeft[seq]);
    seq := ASTRight[seq];
  end;
  Result := PyMakeIdent(tmpSym);
end;

{ The SET comprehension: the same build, with braces as delimiters and `add`
  as the insert. }
function PyParseSetComp: Integer;
var tmpSym, exprStart, seq: Integer; savedDict, savedSet: Boolean;
begin
  savedDict := PyCompIsDict; savedSet := PyCompIsSet;
  PyCompIsDict := False; PyCompIsSet := True;
  tmpSym := AllocVar(PyHiddenName('gs'), tyClass);
  Next;                                { consume the opening brace — NOT written
                                         as a quoted character: this dialect
                                         nests brace comments, so even a quoted
                                         brace inside one opens a nested comment }
  exprStart := TokPos - 1;
  PyScanToCompFor;
  if not PyIsIdent('for') then Error('Nil Python: malformed set comprehension');
  seq := PyBuildComp(tmpSym, exprStart);
  PyCompIsDict := savedDict; PyCompIsSet := savedSet;
  Expect(tkEnd, 'close brace');
  while seq >= 0 do
  begin
    PyHoistStmt(ASTLeft[seq]);
    seq := ASTRight[seq];
  end;
  Result := PyMakeIdent(tmpSym);
end;

{ The parenthesised generator expression: same build as the bracketed one, with
  '(' and ')' as its delimiters. }
function PyParseParenComp: Integer;
var tmpSym, exprStart, seq: Integer; savedDict: Boolean;
begin
  savedDict := PyCompIsDict;
  PyCompIsDict := False;
  tmpSym := AllocVar(PyHiddenName('gp'), tyClass);
  Next;                                { consume '(' }
  exprStart := TokPos - 1;
  PyScanToCompFor;
  if not PyIsIdent('for') then Error('Nil Python: malformed generator expression');
  seq := PyBuildComp(tmpSym, exprStart);
  PyCompIsDict := savedDict;
  Expect(tkRParen, ')');
  while seq >= 0 do
  begin
    PyHoistStmt(ASTLeft[seq]);
    seq := ASTRight[seq];
  end;
  Result := PyMakeIdent(tmpSym);
end;

{ Expression-position DICT comprehension — the brace twin of
  PyParseCompExprValue, used when a dict comp appears where a value is expected
  (a field/subscript target's RHS, a call argument). Builds into a hidden
  TPyDict temp, hoists the build loop, and yields the temp. CurTok is the
  opening brace. }
function PyParseDictCompExprValue: Integer;
var tmpSym, exprStart, seq: Integer; savedDict: Boolean;
begin
  savedDict := PyCompIsDict;
  tmpSym := AllocVar(PyHiddenName('gd'), tyClass);
  Syms[tmpSym].RecName := REC_UCLASS_BASE + FindUClass('TPyDict');
  Next;                                { consume the opening brace; CurTok = KEY }
  exprStart := TokPos - 1;
  PyScanToCompFor;
  if not PyIsIdent('for') then Error('Nil Python: malformed dict comprehension');
  PyCompIsDict := True;
  seq := PyBuildComp(tmpSym, exprStart);
  PyCompIsDict := savedDict;
  Expect(tkEnd, 'close brace');
  while seq >= 0 do
  begin
    PyHoistStmt(ASTLeft[seq]);
    seq := ASTRight[seq];
  end;
  Result := PyMakeIdent(tmpSym);
end;

{ `for x, y in zip(A, B):` — iterate two containers in parallel. Desugared to a
  counted while loop over min(len(A), len(B)), binding x=A[i], y=B[i]. CurTok is
  at `zip`; the two names are already parsed. }
function PyZipAsList(n: Integer): Integer;
{ zip's desugar walks its operands as TPyList — hidden tyClass locals, then
  TPyList.count and TPyList.at. A STRING operand is not one: its handle landed
  in a tyClass slot and `count` read it as a list, so `zip(xs, "abc")` produced
  NO iterations at all, and with any earlier loop in the program it SEGFAULTED
  (bug-nilpy-zip-over-a-string-yields-nothing-or-segfaults).

  Python's zip takes any iterable, so convert instead of rejecting: a string
  goes through pylib's `list(AnsiString)` — the same conversion `list("abc")`
  already uses, one character per element — and a VARIANT through pylist_v,
  which dispatches on the run-time tag. Anything already a list is returned
  untouched, so the common path is unchanged. }
var pi, argN, callN: Integer;
begin
  Result := n;
  if n < 0 then Exit;
  pi := -1;
  if IntToTypeKind(ASTTk[n]) in [tyString, tyAnsiString, tyShortString, tyFixedString] then
  begin
    pi := IRFindProc1ByArgTk('list', tyAnsiString);
    if pi < 0 then pi := IRFindProc1ByArgTk('list', tyString);
  end
  else if IntToTypeKind(ASTTk[n]) = tyVariant then
    pi := IRFindProc1ByArgTk('pylist_v', tyVariant);
  if pi < 0 then Exit;
  argN := AllocNode(AN_ARG);
  ASTLeft[argN] := n;
  callN := AllocNode(AN_CALL);
  ASTIVal[callN] := pi;
  ASTLeft[callN] := argN;
  ASTTk[callN] := Ord(tyClass);
  Result := callN;
end;

function PyParseForZip(const name, name2: AnsiString): Integer;
var listCi, caSym, cbSym, caN, cbN, nSym, iSym, xSym, ySym: Integer;
    aNode, bNode, node, cnd, thenElse, seq, bodyNode, whileNode, incN, oneN: Integer;
begin
  listCi := FindUClass('TPyList');
  if listCi < 0 then Error('Nil Python: pylib (TPyList) not loaded');
  Next; Expect(tkLParen, '(');           { consume `zip` and `(` }
  PyParseBoolExpr; aNode := PyZipAsList(CurASTNode);
  Expect(tkComma, ',');
  PyParseBoolExpr; bNode := PyZipAsList(CurASTNode);
  Expect(tkRParen, ')');
  Expect(tkColon, ':');

  { hidden container / length / index locals }
  caSym := AllocVar(PyHiddenName('za'), tyClass); Syms[caSym].RecName := REC_UCLASS_BASE + listCi;
  cbSym := AllocVar(PyHiddenName('zb'), tyClass); Syms[cbSym].RecName := REC_UCLASS_BASE + listCi;
  caN := AllocVar(PyHiddenName('zna'), tyInteger);
  cbN := AllocVar(PyHiddenName('znb'), tyInteger);
  nSym := AllocVar(PyHiddenName('zn'), tyInteger);
  iSym := AllocVar(PyHiddenName('zi'), tyInteger);
  xSym := PyProgSym(name);  if xSym < 0 then xSym := AllocVar(name, tyVariant);
  ySym := PyProgSym(name2); if ySym < 0 then ySym := AllocVar(name2, tyVariant);

  { drain a comp-iterable's hoisted build before the loop — see PyParseForIn }
  seq := PyFlushHoist(-1);
  { za = A; zb = B }
  node := AllocNode(AN_ASSIGN); ASTLeft[node] := PyMakeIdent(caSym); ASTRight[node] := aNode;
  seq := PySeqAppend(seq, node);
  node := AllocNode(AN_ASSIGN); ASTLeft[node] := PyMakeIdent(cbSym); ASTRight[node] := bNode;
  seq := PySeqAppend(seq, node);
  { zna = len(za); znb = len(zb) }
  node := AllocNode(AN_ASSIGN); ASTLeft[node] := PyMakeIdent(caN);
  ASTRight[node] := PyCallMeth1(listCi, 'count', PyMakeIdent(caSym), -1);
  seq := PySeqAppend(seq, node);
  node := AllocNode(AN_ASSIGN); ASTLeft[node] := PyMakeIdent(cbN);
  ASTRight[node] := PyCallMeth1(listCi, 'count', PyMakeIdent(cbSym), -1);
  seq := PySeqAppend(seq, node);
  { zn = zna if zna < znb else znb  (ternary over idents, no subtree reuse) }
  cnd := AllocNode(AN_BINOP); ASTIVal[cnd] := Ord(tkLt);
  ASTLeft[cnd] := PyMakeIdent(caN); ASTRight[cnd] := PyMakeIdent(cbN); ASTTk[cnd] := Ord(tyBoolean);
  thenElse := AllocNode(AN_PAIR); ASTLeft[thenElse] := PyMakeIdent(caN); ASTRight[thenElse] := PyMakeIdent(cbN);
  node := AllocNode(AN_TERNARY); ASTLeft[node] := cnd; ASTRight[node] := thenElse; ASTTk[node] := Ord(tyInteger);
  incN := AllocNode(AN_ASSIGN); ASTLeft[incN] := PyMakeIdent(nSym); ASTRight[incN] := node;
  seq := PySeqAppend(seq, incN);
  { zi = 0 }
  oneN := AllocNode(AN_INT_LIT); ASTIVal[oneN] := 0; ASTTk[oneN] := Ord(tyInteger);
  node := AllocNode(AN_ASSIGN); ASTLeft[node] := PyMakeIdent(iSym); ASTRight[node] := oneN;
  seq := PySeqAppend(seq, node);

  { loop body: x = za[zi]; y = zb[zi]; <body>; zi += 1 }
  bodyNode := -1;
  node := AllocNode(AN_ASSIGN); ASTLeft[node] := PyMakeIdent(xSym);
  ASTRight[node] := PyCallMeth1(listCi, 'at', PyMakeIdent(caSym), PyMakeIdent(iSym));
  bodyNode := PySeqAppend(bodyNode, node);
  node := AllocNode(AN_ASSIGN); ASTLeft[node] := PyMakeIdent(ySym);
  ASTRight[node] := PyCallMeth1(listCi, 'at', PyMakeIdent(cbSym), PyMakeIdent(iSym));
  bodyNode := PySeqAppend(bodyNode, node);
  Expect(tkNewline, 'newline'); Expect(tkIndent, 'indent');
  bodyNode := PySeqAppend(bodyNode, PyParseBlock);
  Expect(tkDedent, 'dedent');
  { zi = zi + 1 }
  oneN := AllocNode(AN_INT_LIT); ASTIVal[oneN] := 1; ASTTk[oneN] := Ord(tyInteger);
  incN := AllocNode(AN_BINOP); ASTIVal[incN] := Ord(tkPlus);
  ASTLeft[incN] := PyMakeIdent(iSym); ASTRight[incN] := oneN; ASTTk[incN] := Ord(tyInteger);
  node := AllocNode(AN_ASSIGN); ASTLeft[node] := PyMakeIdent(iSym); ASTRight[node] := incN;
  bodyNode := PySeqAppend(bodyNode, node);

  { while zi < zn }
  cnd := AllocNode(AN_BINOP); ASTIVal[cnd] := Ord(tkLt);
  ASTLeft[cnd] := PyMakeIdent(iSym); ASTRight[cnd] := PyMakeIdent(nSym); ASTTk[cnd] := Ord(tyBoolean);
  whileNode := AllocNode(AN_WHILE); ASTLeft[whileNode] := cnd; ASTRight[whileNode] := bodyNode;
  seq := PySeqAppend(seq, whileNode);
  PyStmtAteBlock := True;
  Result := seq;
end;

function PyParseFor: Integer;
var name, name2: AnsiString;
    enumMode: Boolean; symIdx, node, lhsNode, startNode, stopNode, stepNode: Integer;
    pair1, pair2, pair3, bodyNode, oneNode, limitNode, compSaved: Integer;
    rngStep, cmpNode, incNode, whileNode, keyN, hoistPre: Integer;
    parenTarget: Boolean; pDepth, pScan: Integer;
    forTokIdx: Integer;   { token index of the `for` keyword itself }
    hName: AnsiString; ifCondStart, closerPos2, filtDummy: Integer;
begin
  forTokIdx := TokPos - 1;   { CurTok is `for` at entry }
  Next;
  { A PARENTHESISED target list — `for (x, y, text, font, pf) in self.lines:`.
    Python allows the parens and songformatter's render backend writes them;
    they carry no meaning, so they are consumed here and the name list below is
    unchanged. Only taken when the matching `)` is followed by `in`, so a
    generator target or a parenthesised expression is left alone. }
  parenTarget := False;
  if CurTok.Kind = tkLParen then
  begin
    pDepth := 1;
    pScan := TokPos;
    while (pScan < TokCount) and (pDepth > 0) do
    begin
      if Tokens[pScan].Kind = tkLParen then Inc(pDepth)
      else if Tokens[pScan].Kind = tkRParen then Dec(pDepth);
      Inc(pScan);
    end;
    if (pDepth = 0) and (pScan < TokCount) and (Tokens[pScan].Kind = tkIn) then
    begin
      parenTarget := True;
      Next;
    end;
  end;
  if CurTok.Kind <> tkIdent then Error('Nil Python: expected loop variable after for');
  name := CurTok.SVal;
  Next;
  { `for k, v in d.items():` — a two-name target, which only a dict serves
    today (feature-nilpy-tuple-unpack). No tuple type is invented for it: the
    two names read the dict's parallel key and value lists by the same index. }
  name2 := '';
  PyForExtraCount := 0;
  if CurTok.Kind = tkComma then
  begin
    Next;
    if CurTok.Kind <> tkIdent then Error('Nil Python: expected a second loop variable');
    name2 := CurTok.SVal;
    Next;
    { and any further names: `for anchor, weight, label in (...)` }
    while CurTok.Kind = tkComma do
    begin
      Next;
      if CurTok.Kind <> tkIdent then Error('Nil Python: expected a loop variable after ,');
      if PyForExtraCount > High(PyForExtraName) then
        Error('Nil Python: too many names in a for target');
      PyForExtraName[PyForExtraCount] := CurTok.SVal;
      Inc(PyForExtraCount);
      Next;
    end;
  end;
  if parenTarget then Expect(tkRParen, ')');
  Expect(tkIn, 'in');
  if (PyForExtraCount > 0) and PyIsIdent('zip') then
    Error('Nil Python: zip() with more than two loop variables is not supported yet');
  { `for x, y in zip(A, B):` — parallel iteration over two containers. }
  if (name2 <> '') and PyIsIdent('zip') and (TokPos < TokCount) and
     (Tokens[TokPos].Kind = tkLParen) then
  begin
    Result := PyParseForZip(name, name2);
    Exit;
  end;
  { `for x in range(...)` keeps the counted-loop lowering below; anything else
    is a container and goes through the desugar. }
  if not (PyIsIdent('range') and (TokPos < TokCount) and
          (Tokens[TokPos].Kind = tkLParen)) then
  begin
    { `for i, v in enumerate(xs):` — the first name is the INDEX the counted-loop
      desugar already keeps, so enumerate needs no iterator and no tuple; it is
      recognised here and its argument becomes the container. }
      enumMode := False;
      if PyIsIdent('enumerate') and (TokPos < TokCount) and
         (Tokens[TokPos].Kind = tkLParen) then
      begin
        if name2 = '' then Error('Nil Python: enumerate() needs two loop variables');
        enumMode := True;
        Next; Expect(tkLParen, '(');
      end;
    Result := PyParseForIn(name, name2, enumMode, forTokIdx);
    Exit;
  end;
  if name2 <> '' then Error('Nil Python: a two-name for target needs a dict (.items())');
  if PyCompTarget >= 0 then
  begin
    { Same hidden-binding treatment as PyParseForIn: a comprehension over
      range() must not clobber an outer binding of the same spelled name
      (bug-nilpy-comprehension-variable-leaks-and-clobbers-the-enclosing-scope).
      Deterministic name (see PyCompHiddenLoopName) — stable across the
      typing pre-pass and the real pass over the same tokens. }
    hName := PyCompHiddenLoopName(forTokIdx, 0);
    symIdx := AllocVar(hName, tyInteger);
  end
  else
  begin
    symIdx := PyProgSym(name);
    if symIdx < 0 then symIdx := AllocVar(name, tyInteger);
  end;
  PyExpectIdent('range');
  Expect(tkLParen, '(');
  PyParseBoolExpr;
  startNode := CurASTNode;
  if Eat(tkComma) then
  begin
    stopNode := startNode;
    PyParseBoolExpr;
    startNode := stopNode;
    stopNode := CurASTNode;
  end
  else
  begin
    stopNode := startNode;
    startNode := AllocNode(AN_INT_LIT);
    ASTIVal[startNode] := 0;
    ASTTk[startNode] := Ord(tyInteger);
  end;
  rngStep := -1;                       { -1 = no explicit step (i.e. step 1) }
  if Eat(tkComma) then
  begin
    PyParseBoolExpr;
    rngStep := CurASTNode;
  end;
  { drain a hoisted comp build inside the range() arguments before the body
    parse flushes it INTO the loop body — see PyParseForIn }
  hoistPre := PyFlushHoist(-1);
  Expect(tkRParen, ')');
  if PyCompTarget >= 0 then
  begin
    { comprehension over range: body is target.append(EXPR) — or, for a dict
      comprehension, target.store(KEY, VALUE). EXPR re-parsed from before the
      `for`, the same shape PyParseForIn uses. Header ends at a bracket. }
    compSaved := TokPos - 1;
    { Rename BOTH the element expression and the filter condition (if any)
      BEFORE parsing either — same order PyParseForIn uses. Renaming the
      filter lazily, only once its own `if` is reached (after the element
      expression has already been parsed and compiled), let some interposed
      hidden-temp bookkeeping between the two steps invalidate the loop
      variable's slot for a NEVER-otherwise-bound name specifically
      (measured: reordering to rename both up front, mirroring the container
      path, fixed it — see
      bug-nilpy-comprehension-variable-leaks-and-clobbers-the-enclosing-scope). }
    PyRenameIdentRange(PyCompExprStart, forTokIdx, name, hName);
    if Tokens[compSaved].Kind = tkIf then
    begin
      ifCondStart := compSaved + 1;
      closerPos2 := PyCompFindClose(ifCondStart, filtDummy);
      PyRenameIdentRange(ifCondStart, closerPos2, name, hName);
    end;
    TokPos := PyCompExprStart; Next;
    if PyCompIsDict then
    begin
      PyParseBoolExpr;
      keyN := CurASTNode;
      Expect(tkColon, ':');
      PyParseBoolExpr;
      bodyNode := PyCallMeth2(FindUClass('TPyDict'), 'store',
                              PyMakeIdent(PyCompTarget), keyN, CurASTNode);
      if bodyNode < 0 then Error('Nil Python: pylib TPyDict.store not loaded');
    end
    else
    begin
      PyParseBoolExpr;
      bodyNode := PyCallMeth1(PyNodeListCi(PyMakeIdent(PyCompTarget)), 'append',
                             PyMakeIdent(PyCompTarget), CurASTNode);
      if bodyNode < 0 then Error('Nil Python: pylib TPyList.append not loaded');
    end;
    TokPos := compSaved; Next;
    { `... if COND]`: gate the append on the filter — the range path sees the
      `if` directly (no ITER expression ahead of it), same wrap as the
      container path (feature-nilpy-comprehension-if-filter). Tokens were
      already renamed above; just parse. }
    if CurTok.Kind = tkIf then
    begin
      Next;
      PyParseBoolExpr;
      node := AllocNode(AN_IF);
      ASTLeft[node] := PyMakeTruthy(CurASTNode);
      pair1 := AllocNode(AN_PAIR);
      ASTLeft[pair1] := bodyNode;
      ASTRight[pair1] := -1;
      ASTRight[node] := pair1;
      bodyNode := node;
    end;
  end
  else
  begin
    Expect(tkColon, ':');
    Expect(tkNewline, 'newline');
    Expect(tkIndent, 'indent');
    bodyNode := PyParseBlock;
    Expect(tkDedent, 'dedent');
  end;

  { A pre-existing VARIANT loop variable (x was a container-loop target
    earlier) must not be driven raw by the counted-for/while lowering: an
    untagged integer written into the variant slot left a stale tag, so
    `x > 2` matched nothing and `x % 2` raised "expected a number, got str".
    Count with a hidden int and box it into the variant at the top of each
    iteration (bug-nilpy-range-for-variant-loop-var). }
  if Syms[symIdx].TypeKind = tyVariant then
  begin
    keyN := AllocVar(PyHiddenName('i'), tyInteger);
    node := AllocNode(AN_ASSIGN);              { x = __py_i (boxes the int) }
    ASTLeft[node] := PyMakeIdent(symIdx);
    ASTRight[node] := PyMakeIdent(keyN);
    incNode := PySeqAppend(-1, node);
    bodyNode := PySeqAppend(incNode, bodyNode);
    symIdx := keyN;
  end;

  if rngStep >= 0 then
  begin
    { An explicit step -> a while-loop desugar (general, handles a negative
      step): `i = start; while i </> stop: body; i = i + step`. The direction
      of the guard depends on the step's SIGN, known for a literal step (every
      censused use, e.g. range(n-1, -1, -1)); a non-literal step assumes
      ascending. }
    node := AllocNode(AN_ASSIGN);                { i = start }
    ASTLeft[node] := PyMakeIdent(symIdx);
    ASTRight[node] := startNode;
    Result := PySeqAppend(-1, node);

    cmpNode := AllocNode(AN_BINOP);              { i < stop  or  i > stop }
    { a negative step (`-1` is AN_NEG over a literal; a bare negative literal is
      AN_INT_LIT<0) counts DOWN, so the guard flips to `>` }
    if (ASTKind[rngStep] = AN_NEG) or
       ((ASTKind[rngStep] = AN_INT_LIT) and (ASTIVal[rngStep] < 0)) then
      ASTIVal[cmpNode] := Ord(tkGt)
    else
      ASTIVal[cmpNode] := Ord(tkLt);
    ASTLeft[cmpNode] := PyMakeIdent(symIdx);
    ASTRight[cmpNode] := stopNode;
    ASTTk[cmpNode] := Ord(tyBoolean);

    incNode := AllocNode(AN_BINOP);              { i + step }
    ASTIVal[incNode] := Ord(tkPlus);
    ASTLeft[incNode] := PyMakeIdent(symIdx);
    ASTRight[incNode] := rngStep;
    ASTTk[incNode] := Ord(tyInteger);
    node := AllocNode(AN_ASSIGN);                { i = i + step }
    ASTLeft[node] := PyMakeIdent(symIdx);
    ASTRight[node] := incNode;
    { append the increment as the last statement of the body. The parsed block
      is already an AN_SEQ chain; a comprehension body is a single node that
      must be wrapped into a chain first, or PySeqAppend walks a non-sequence. }
    if ASTKind[bodyNode] <> AN_SEQ then bodyNode := PySeqAppend(-1, bodyNode);
    bodyNode := PySeqAppend(bodyNode, node);

    whileNode := AllocNode(AN_WHILE);
    ASTLeft[whileNode] := cmpNode;
    ASTRight[whileNode] := bodyNode;
    Result := PySeqAppend(Result, whileNode);
    if hoistPre >= 0 then Result := PySeqAppend(hoistPre, Result);
    PyStmtAteBlock := True;
    Exit;
  end;

  oneNode := AllocNode(AN_INT_LIT);
  ASTIVal[oneNode] := 1;
  ASTTk[oneNode] := Ord(tyInteger);
  limitNode := AllocNode(AN_BINOP);
  ASTIVal[limitNode] := Ord(tkMinus);
  ASTLeft[limitNode] := stopNode;
  ASTRight[limitNode] := oneNode;
  ASTTk[limitNode] := Ord(tyInteger);
  lhsNode := PyMakeIdent(symIdx);
  pair1 := AllocNode(AN_PAIR);
  ASTLeft[pair1] := startNode;
  ASTRight[pair1] := limitNode;
  stepNode := AllocNode(AN_INT_LIT);
  ASTIVal[stepNode] := 0;
  ASTTk[stepNode] := Ord(tyInteger);
  pair2 := AllocNode(AN_PAIR);
  ASTLeft[pair2] := stepNode;
  ASTRight[pair2] := bodyNode;
  pair3 := AllocNode(AN_PAIR);
  ASTLeft[pair3] := pair1;
  ASTRight[pair3] := pair2;
  node := AllocNode(AN_FOR);
  ASTLeft[node] := lhsNode;
  ASTRight[node] := pair3;
  if hoistPre >= 0 then
  begin
    PyStmtAteBlock := True;
    node := PySeqAppend(hoistPre, node);
  end;
  Result := node;
end;

{ Map an augmented-assignment token to its binary operator, tkEOF if none. }
function PyAugBinTok(k: TTokenKind): TTokenKind;
begin
  case k of
    tkPlusEq:  Result := tkPlus;
    tkMinusEq: Result := tkMinus;
    tkStarEq:  Result := tkStar;
    tkSlashEq: Result := tkDiv;   { //= — integer division, like // }
    tkTrueDivEq: Result := tkSlash;   { /= — true division, like / }
    tkModEq:   Result := tkMod;
    tkAmpEq:   Result := tkAnd;
    tkPipeEq:  Result := tkOr;
    tkXorEq:   Result := tkXor;
    tkShlEq:   Result := tkShl;
    tkShrEq:   Result := tkShr;
    else Result := tkEOF;
  end;
end;

{ Register a nested def's SHELL and queue its body for later compilation.
  Returns an empty statement: the def itself produces no code where it stands.
  The typing pre-pass trial-parses the enclosing body too, so this must stay
  idempotent — a shell already carrying a BodyAddr means the real parse already
  compiled it, and re-registering would give the enclosing calls a second,
  bodyless Proc. }
{ The name a call inside a nested def should actually look up. A def nested in
  another def registers as `outer.inner`; inside the enclosing body it is called
  unqualified. Walks the qualifier outwards — `a.b.c` then `a.b` then `a` — so an
  inner sibling shadows an outer one, like Python's scope chain. Returns the name
  unchanged when nothing qualified exists, which is every ordinary global call. }
function PyQualifyNested(const name: AnsiString): AnsiString;
var pfx: AnsiString; cut, i: Integer;
begin
  Result := name;
  pfx := PyNestPrefix;
  while pfx <> '' do
  begin
    { Only a nested DEF qualifies. A CLASS prefix must not: Python reaches a
      method through `self.` and never by a bare name, so inside a method the
      unqualified call names the module-level function even when the class has
      one of the same name — songformatter's `def select_image(self):
      select_image()` delegates exactly that way, and qualifying turned it into
      a call of ITSELF with no arguments. }
    if (FindProc(pfx + '.' + name) >= 0) and (FindUClass(pfx) < 0) then
    begin
      Result := pfx + '.' + name;
      Exit;
    end;
    cut := 0;
    for i := 1 to Length(pfx) do
      if pfx[i] = '.' then cut := i;
    if cut = 0 then pfx := '' else pfx := Copy(pfx, 1, cut - 1);
  end;
end;

{ Does the body span declare `nonlocal <name>`? Scanned from tokens, like the
  capture scan itself, because the body is not parsed until later. A `global`
  declaration is NOT this: that one names a module global, which the nested body
  already reaches directly. }
function PyBodyDeclaresNonlocal(bodyStart, bodyEnd: Integer;
                                const nm: AnsiString): Boolean;
var i: Integer;
begin
  Result := False;
  i := bodyStart;
  while i < bodyEnd do
  begin
    if (Tokens[i].Kind = tkIdent) and (GetTokenStr(i) = 'nonlocal') then
    begin
      Inc(i);
      while (i < bodyEnd) and (Tokens[i].Kind = tkIdent) do
      begin
        if GetTokenStr(i) = nm then begin Result := True; Exit; end;
        Inc(i);
        if (i < bodyEnd) and (Tokens[i].Kind = tkComma) then Inc(i) else Break;
      end;
    end
    else
      Inc(i);
  end;
end;

{ The token index of a sibling nested `def <nm>` that appears LATER in the
  enclosing body. Scanned exactly like PyEnclosingAssigns — forward from fromTok
  until the enclosing block's own DEDENT — so it never leaves the scope. -1 when
  the enclosing body has no such def ahead. }
function PyFindSiblingDefTok(fromTok: Integer; const nm: AnsiString): Integer;
var i, depth: Integer;
begin
  PyFindSiblingDefTok := -1;
  i := fromTok;
  while (i < MainProgramTokCount) and (Tokens[i].Kind in [tkDedent, tkNewline]) do Inc(i);
  depth := 0;
  while i < MainProgramTokCount do
  begin
    if Tokens[i].Kind = tkIndent then Inc(depth)
    else if Tokens[i].Kind = tkDedent then
    begin
      Dec(depth);
      if depth < 0 then Exit;          { left the enclosing body }
    end
    else if (depth = 0) and (Tokens[i].Kind = tkFunction) and
            (i + 1 < MainProgramTokCount) and (Tokens[i + 1].Kind = tkIdent) and
            (GetTokenStr(i + 1) = nm) then
    begin
      PyFindSiblingDefTok := i;
      Exit;
    end;
    Inc(i);
  end;
end;

{ The INDENT that opens the body of the def whose `def` keyword is at defTok —
  the same index PyParseDefHeader leaves behind, so PyFindBodyEnd agrees. }
function PySiblingDefBodyStart(defTok: Integer): Integer;
var i, depth: Integer;
begin
  PySiblingDefBodyStart := -1;
  i := defTok;
  depth := 0;
  while i < MainProgramTokCount do
  begin
    if Tokens[i].Kind in [tkLParen, tkLBrack] then Inc(depth)
    else if Tokens[i].Kind in [tkRParen, tkRBrack] then Dec(depth)
    else if (depth = 0) and (Tokens[i].Kind = tkIndent) then
    begin
      PySiblingDefBodyStart := i;
      Exit;
    end;
    Inc(i);
  end;
end;

{ The names a call to nested def `calleeName` must forward, into PyFwdCapNm.
  Why this is not simply `PyCapName[FindProc(callee)]`: a nested def's capture
  set is read when the CALLER is queued, and the callee may not be registered
  yet — it is defined later in the same body — so the set read was empty and the
  forwarded arguments were missing, making a legal program compile or fail on
  definition ORDER alone. Worse, the chain is multi-level (a lambda inside one
  sibling calling another), so one parse round per level never settles it.
  This walks the transitive closure of sibling-def bodies from tokens in one go:
  a registered callee contributes its final set, an unregistered one contributes
  its body's free names and queues the siblings IT calls. The caller filters
  every name against the enclosing scope, so over-collecting a name that is not
  an enclosing local costs nothing (bug-nilpy-nested-def-capture-sets-are-not-final). }
procedure PyCollectCalleeCaps(const calleeName: AnsiString; searchFrom: Integer);
const PAR_MAX = 32;
var wlAt, i, j, k, q, pi, dt, bS, bE, depth, nPar: Integer;
    pars: array[0..PAR_MAX-1] of AnsiString;
    nm, s, c: AnsiString; dup: Boolean;
begin
  PyFwdCapN := 0;
  PyFwdWlN := 1; PyFwdWl[0] := calleeName;
  wlAt := 0;
  while wlAt < PyFwdWlN do
  begin
    nm := PyFwdWl[wlAt];
    Inc(wlAt);
    { already registered — its capture set is final, take it verbatim }
    pi := FindProc(PyQualifyNested(nm));
    if (pi >= 0) and (PyCapCount[pi] > 0) then
    begin
      for k := 0 to PyCapCount[pi] - 1 do
      begin
        c := PyCapName[pi * PY_MAX_CAPS + k];
        dup := False;
        for q := 0 to PyFwdCapN - 1 do
          if PyFwdCapNm[q] = c then dup := True;
        if (not dup) and (PyFwdCapN < PY_MAX_CAPS) then
        begin
          PyFwdCapNm[PyFwdCapN] := c;
          Inc(PyFwdCapN);
        end;
      end;
      Continue;
    end;
    if pi >= 0 then Continue;          { registered and captures nothing }
    dt := PyFindSiblingDefTok(searchFrom, nm);
    if dt < 0 then Continue;
    bS := PySiblingDefBodyStart(dt);
    if bS < 0 then Continue;
    bE := PyFindBodyEnd(bS);
    { the callee's OWN parameters are bound at its call site, never captured }
    nPar := 0;
    i := dt + 2;                       { past `def` `name` }
    depth := 0;
    while i < bS do
    begin
      if Tokens[i].Kind = tkLParen then Inc(depth)
      else if Tokens[i].Kind = tkRParen then
      begin
        Dec(depth);
        if depth = 0 then Break;
      end
      else if (depth = 1) and (Tokens[i].Kind = tkIdent) and
              (Tokens[i - 1].Kind in [tkLParen, tkComma]) then
      begin
        if nPar < PAR_MAX then
        begin
          pars[nPar] := GetTokenStr(i);
          Inc(nPar);
        end;
      end;
      Inc(i);
    end;
    for i := bS to bE - 1 do
      if (Tokens[i].Kind = tkIdent) and (Tokens[i - 1].Kind <> tkDot) then
      begin
        s := GetTokenStr(i);
        if s = nm then Continue;
        dup := False;
        for j := 0 to nPar - 1 do
          if pars[j] = s then dup := True;
        if dup then Continue;
        { a name that is itself a sibling def: what IT captures must travel too }
        if (FindProc(PyQualifyNested(s)) >= 0) or
           (PyFindSiblingDefTok(searchFrom, s) >= 0) then
        begin
          dup := False;
          for q := 0 to PyFwdWlN - 1 do
            if PyFwdWl[q] = s then dup := True;
          if (not dup) and (PyFwdWlN <= 15) then
          begin
            PyFwdWl[PyFwdWlN] := s;
            Inc(PyFwdWlN);
          end;
        end
        else
        begin
          dup := False;
          for q := 0 to PyFwdCapN - 1 do
            if PyFwdCapNm[q] = s then dup := True;
          if (not dup) and (PyFwdCapN < PY_MAX_CAPS) then
          begin
            PyFwdCapNm[PyFwdCapN] := s;
            Inc(PyFwdCapN);
          end;
        end;
      end;
  end;
end;

function PyQueueNestedDef: Integer;
var defTok, procIdx, bodyStart, bodyEnd, i, j, k, nCaps, nOwn, csym, csym2, capCi: Integer;
    qname, cname, cn2: AnsiString; already: Boolean;
    capNames: array[0..PY_MAX_CAPS-1] of AnsiString;
    capTypes: array[0..PY_MAX_CAPS-1] of TTypeKind;
    capRecs: array[0..PY_MAX_CAPS-1] of Integer;
begin
  defTok := TokPos - 1;
  PyParseDefHeader;
  qname := PyHdrName;
  if PyNestPrefix <> '' then qname := PyNestPrefix + '.' + qname;
  bodyStart := TokPos - 1;
  bodyEnd := PyFindBodyEnd(bodyStart);
  { CAPTURE: every enclosing local/parameter the body mentions becomes a
    trailing by-value parameter, filled in at each call site. Scanned from the
    body's tokens because the body itself is not parsed until later — a name is
    captured when it resolves to a local or parameter of the ENCLOSING scope and
    is not one of this def's own parameters. A name the body ASSIGNS before
    reading is captured too and simply overwritten, which lands on Python's
    answer anyway (there it would be a plain local). }
  nCaps := 0;
  if PyNestPrefix <> '' then
    for i := bodyStart to bodyEnd - 1 do
      if Tokens[i].Kind = tkIdent then
      begin
        cname := GetTokenStr(i);
        already := False;
        for j := 0 to PyHdrNParams - 1 do
          if PyHdrPNames[j] = cname then already := True;
        for j := 0 to nCaps - 1 do
          if capNames[j] = cname then already := True;
        if not already then
        begin
          csym := FindSym(cname);
          { assigned LATER in the enclosing body — materialise it now so it is
            captured like any other name }
          if (csym < 0) and PyEnclosingAssigns(bodyEnd, cname) then
            csym := AllocVar(cname, tyVariant);
          if (csym >= 0) and (Syms[csym].Kind in [skLocal, skParam]) and
             not Syms[csym].IsArray and
             (Syms[csym].TypeKind <> tyRecord) then
          begin
            if nCaps >= PY_MAX_CAPS then
              Error('Nil Python: a nested def may capture at most 8 enclosing names');
            capNames[nCaps] := cname;
            capTypes[nCaps] := Syms[csym].TypeKind;
            { A captured CLASS/RECORD-ID object must keep its class identity, or
              inside the nested body `obj.field` cannot resolve and every value
              read off it defaults to Integer (slices/methods on it then fail to
              parse). TParam carries no rec id, so carry it through capRecs ->
              ProcParamRecId (the persistent per-proc-param rec store). }
            if Syms[csym].TypeKind = tyClass then
              capRecs[nCaps] := Syms[csym].RecName
            else
              capRecs[nCaps] := REC_NONE;
            Inc(nCaps);
          end
          else
          begin
            { TRANSITIVE capture: the name is a SIBLING nested def that itself
              captures enclosing locals not in scope inside a THIRD sibling.
              CPython binds those at the sibling's def site; pxx flattens, so
              this def must forward them. Pull each of the callee's captures
              that resolves in the CURRENT enclosing scope into our own set
              (uforth's _open_file_common -> _file_open_mode -> FAM_RO).
              Filed decide-nilpy-transitive-nested-def-capture. }
            csym := FindProc(PyQualifyNested(cname));
            if (csym >= 0) or (PyFindSiblingDefTok(bodyEnd, cname) >= 0) then
            begin
              PyCollectCalleeCaps(cname, bodyEnd);
              for k := 0 to PyFwdCapN - 1 do
              begin
                cn2 := PyFwdCapNm[k];
                already := False;
                for j := 0 to PyHdrNParams - 1 do
                  if PyHdrPNames[j] = cn2 then already := True;
                for j := 0 to nCaps - 1 do
                  if capNames[j] = cn2 then already := True;
                if not already then
                begin
                  csym2 := FindSym(cn2);
                  if (csym2 >= 0) and (Syms[csym2].Kind in [skLocal, skParam]) and
                     not Syms[csym2].IsArray and (Syms[csym2].TypeKind <> tyRecord) then
                  begin
                    if nCaps >= PY_MAX_CAPS then
                      Error('Nil Python: a nested def may capture at most 8 enclosing names');
                    capNames[nCaps] := cn2;
                    capTypes[nCaps] := Syms[csym2].TypeKind;
                    if Syms[csym2].TypeKind = tyClass then
                      capRecs[nCaps] := Syms[csym2].RecName
                    else
                      capRecs[nCaps] := REC_NONE;
                    Inc(nCaps);
                  end;
                end;
              end;
            end;
          end;
        end;
      end;
  if PxxDbgEnabled('n.caps') then
  begin
    Write('PXXDBG n.caps def ', qname, ' caps=');
    for j := 0 to nCaps - 1 do Write(capNames[j], ' ');
    WriteLn;
  end;
  procIdx := FindProc(qname);
  if procIdx < 0 then
  begin
    nOwn := PyHdrNParams;
    for j := 0 to nCaps - 1 do
    begin
      if PyHdrNParams >= 32 then Error('Nil Python: too many parameters after capture');
      PyHdrPNames[PyHdrNParams] := capNames[j];
      PyHdrPTypes[PyHdrNParams] := capTypes[j];
      if (capTypes[j] = tyClass) and (capRecs[j] >= REC_UCLASS_BASE) then
        PyHdrPCis[PyHdrNParams] := capRecs[j] - REC_UCLASS_BASE
      else
        PyHdrPCis[PyHdrNParams] := -1;
      PyHdrDefHas[PyHdrNParams] := False;
      Inc(PyHdrNParams);
    end;
    procIdx := RegisterProc(qname, not PyHdrIsProc, PyHdrRetType, PyHdrNParams,
                            PyHdrPNames, PyHdrPTypes);
    PyApplyDefSignature(procIdx);
    Procs[procIdx].BodyAddr := -1;
    { A captured parameter is never written at the call site by the user, so
      overload matching must accept a call that supplies only the declared
      arguments — the same "trailing params may be omitted" rule defaults use.
      The call site then appends the captured actuals. }
    PyCapCount[procIdx] := nCaps;
    for j := 0 to nCaps - 1 do
    begin
      PyCapName[procIdx * PY_MAX_CAPS + j] := capNames[j];
      if nOwn + j < MAX_PROC_PARAMS then
      begin
        ProcParamHasDefault[procIdx * MAX_PROC_PARAMS + nOwn + j] := True;
        { persist the captured object's class so the deferred body parse can
          restore PyHdrPCis (TParam has no rec-id field of its own) }
        if capRecs[j] >= REC_UCLASS_BASE then
          ProcParamRecId[procIdx * MAX_PROC_PARAMS + nOwn + j] := capRecs[j];
        { `nonlocal x` in the body means a WRITE must land in the enclosing
          frame. A capture is normally a by-VALUE trailing parameter, so the
          write went to the callee's copy and the enclosing local never changed
          (songformatter's parseParams set `song_title`, and the renderer still
          saw None). Declaring THAT parameter by-ref makes the store write
          through to the enclosing local the call site passes. }
        if PyBodyDeclaresNonlocal(bodyStart, bodyEnd, capNames[j]) then
        begin
          Procs[procIdx].Params[nOwn + j].IsRef := True;
          ProcParamCapRef[procIdx * MAX_PROC_PARAMS + nOwn + j] := True;
        end;
      end;
    end;
  end;
  { record the def's token position: a nested def taken AS A VALUE re-lowers
    from this span as a value-binding closure (see PyNestedDefClosureValue) }
  PyDefTokOf[procIdx] := defTok + 1;
  { skip the body: PyParseDefHeader stopped on the INDENT that opens it }
  { land ON the DEDENT that closes the nested body, then consume it, so the
    enclosing block resumes at the statement after the def }
  TokPos := bodyEnd;
  Next;
  if CurTok.Kind = tkDedent then Next;
  PySkipNewlines;
  PyStmtAteBlock := True;
  if not PyTypingPass then
  begin
    if PyPendNestCount >= PY_MAX_NESTED then
      Error('Nil Python: too many nested defs in one body');
    PyPendNestTok[PyPendNestCount] := defTok;
    PyPendNestPfx[PyPendNestCount] := PyNestPrefix;
    Inc(PyPendNestCount);
  end;
  Result := -1;
end;

{ ONE store of an unpacking assignment: a plain NAME (created on first
  assignment, as everywhere in NilPy), a declared ATTRIBUTE `obj.field`, or an
  attribute the class never declared — Python creates that on assignment, and
  it goes through the same dynamic store `obj.name = v` already uses. `newTk`
  is the type a freshly created plain name takes. }
function PyUnpackTargetStore(const nm, fld: AnsiString; valNode: Integer;
                            newTk: TTypeKind): Integer;
var symIdx, ci, fi, lhs: Integer;
begin
  symIdx := PyProgSym(nm);
  if fld = '' then
  begin
    if symIdx < 0 then symIdx := AllocVar(nm, newTk);
    lhs := PyMakeIdent(symIdx);
  end
  else
  begin
    if symIdx < 0 then
      Error('Nil Python: ' + nm + ' is not defined, so ' + nm + '.' + fld
            + ' cannot be assigned');
    ci := -1;
    if (Syms[symIdx].TypeKind = tyClass) and (Syms[symIdx].RecName >= REC_UCLASS_BASE) then
      ci := Syms[symIdx].RecName - REC_UCLASS_BASE;
    fi := -1;
    if ci >= 0 then fi := FindUField(ci, fld);
    if fi < 0 then
    begin
      { NOT a declared field — Python creates the attribute on assignment, and
        the ordinary `obj.name = v` path already stores it dynamically }
      PyUnpackTargetStore := PyMakeDynAttrSet(PyMakeIdent(symIdx), fld, valNode);
      Exit;
    end;
    lhs := AllocNode(AN_FIELD);
    ASTLeft[lhs] := PyMakeIdent(symIdx);
    ASTSOffset[lhs] := PyStoredName(fld);
    ASTSLen[lhs] := Length(fld);
    ASTTk[lhs] := UFldTk[fi];
  end;
  PyUnpackTargetStore := AllocNode(AN_ASSIGN);
  ASTLeft[PyUnpackTargetStore] := lhs;
  ASTRight[PyUnpackTargetStore] := valNode;
end;

{ `a, b = x, y` — SIMULTANEOUS assignment. Every right-hand side is evaluated
  into a hidden temp before ANY target is stored, which is the whole reason this
  is not just a sequence of assignments: `a, b = b, a` would otherwise become
  `a = b; b = a` and lose the old `a` (feature-nilpy-tuple-unpack). }
function PyParseUnpackAssign: Integer;
var names: array[0..7] of AnsiString;
    flds: array[0..7] of AnsiString;    { attribute target, or '' for a plain name }
    tmps: array[0..7] of Integer;
    nTargets, nValues, i, symIdx, node, seq, tk: Integer;
    unpCi, unpIdx, unpElem: Integer;
begin
  nTargets := 0;
  repeat
    if CurTok.Kind <> tkIdent then Error('Nil Python: expected a name in the assignment target');
    if nTargets >= 8 then Error('Nil Python: at most 8 unpacking targets');
    names[nTargets] := CurTok.SVal;
    flds[nTargets] := '';
    Next;
    { An ATTRIBUTE target — `self.x, self.y = x, y`, which is how a class
      records a position in one line. Only the object.field shape is taken;
      anything deeper reports its own error. }
    if (CurTok.Kind = tkDot) and (TokPos < TokCount) and (Tokens[TokPos].Kind = tkIdent) then
    begin
      Next;
      flds[nTargets] := CurTok.SVal;
      Next;
    end;
    Inc(nTargets);
  until not Eat(tkComma);
  Expect(tkAssign, '=');

  { values into temps, left to right }
  seq := -1;
  nValues := 0;
  repeat
    PyParseBoolExpr;
    if nValues >= nTargets then
      Error('Nil Python: too many values to unpack');
    tk := ASTTk[CurASTNode];
    if IntToTypeKind(tk) = tyString then tk := Ord(tyAnsiString);
    tmps[nValues] := AllocVar(PyHiddenName('unp'), IntToTypeKind(tk));
    if IntToTypeKind(tk) = tyClass then
      Syms[tmps[nValues]].RecName := ResolveNodeRec(CurASTNode);
    node := AllocNode(AN_ASSIGN);
    ASTLeft[node] := PyMakeIdent(tmps[nValues]);
    ASTRight[node] := CurASTNode;
    seq := PySeqAppend(seq, node);
    Inc(nValues);
  until not Eat(tkComma);
  { `pfx, content = cs` — ONE value for several targets means the value is a
    SEQUENCE to be indexed, not a shortfall. Our tuples are TPyLists, so this
    is the shape a function returning a tuple produces. }
  if (nValues = 1) and (nTargets > 1) then
  begin
    unpCi := PyNodeListCi(PyMakeIdent(tmps[0]));
    { A VARIANT value (e.g. `k, v = stack.pop()` — pop yields a variant holding a
      pair) is indexed at run time via pyvar_getitem, which unboxes to the list
      it holds. A static list uses TPyList.at. }
    if (unpCi < 0) and (IntToTypeKind(ASTTk[PyMakeIdent(tmps[0])]) <> tyVariant) then
      Error('Nil Python: cannot unpack this value into several names — it is '
            + 'not a list, tuple or variant');
    for i := 0 to nTargets - 1 do
    begin
      unpIdx := AllocNode(AN_INT_LIT);
      ASTIVal[unpIdx] := i;
      ASTTk[unpIdx] := Ord(tyInteger);
      if unpCi >= 0 then
      begin
        unpElem := PyCallMeth1(unpCi, 'at', PyMakeIdent(tmps[0]), unpIdx);
        if unpElem < 0 then Error('Nil Python: pylib (TPyList.at) not loaded');
      end
      else
        unpElem := PyMakeVariantGetItem(PyMakeIdent(tmps[0]), unpIdx);
      node := PyUnpackTargetStore(names[i], flds[i], unpElem, tyVariant);
      seq := PySeqAppend(seq, node);
    end;
    Result := seq;
    Exit;
  end;
  if nValues <> nTargets then
    Error('Nil Python: not enough values to unpack');

  { then the stores }
  for i := 0 to nTargets - 1 do
  begin
    node := PyUnpackTargetStore(names[i], flds[i], PyMakeIdent(tmps[i]),
                                Syms[tmps[i]].TypeKind);
    seq := PySeqAppend(seq, node);
  end;
  Result := seq;
end;

{ Does an `a, b = ...` target list start here? Only a bare comma-separated name
  list followed by `=` qualifies — anything else is left to the ordinary paths. }
function PyUnpackTargetAhead: Boolean;
var i: Integer;
begin
  Result := False;
  if CurTok.Kind <> tkIdent then Exit;
  i := TokPos;                    { the token AFTER the current ident }
  { an ATTRIBUTE target counts as one name — `self.x, self.y = x, y` }
  if (i + 1 < TokCount) and (Tokens[i].Kind = tkDot) and
     (Tokens[i + 1].Kind = tkIdent) then Inc(i, 2);
  if (i >= TokCount) or (Tokens[i].Kind <> tkComma) then Exit;
  while i < TokCount do
  begin
    if Tokens[i].Kind = tkComma then
    begin
      Inc(i);
      if (i >= TokCount) or (Tokens[i].Kind <> tkIdent) then Exit;
      Inc(i);
      if (i + 1 < TokCount) and (Tokens[i].Kind = tkDot) and
         (Tokens[i + 1].Kind = tkIdent) then Inc(i, 2);
    end
    else if Tokens[i].Kind = tkAssign then begin Result := True; Exit; end
    else Exit;
  end;
end;

function PyParseStatement: Integer;
var name: AnsiString; symIdx, lhsNode, node, ci, rhsNode, annIdx, delBase: Integer; tk: TTypeKind;
    annSig: Integer;   { Callable signature of an annotated target, or -1 }
    augTk: TTokenKind;
    mmi, mpi, selfArg, lastArg, argNode, kwIdx, j, k: Integer;   { inherited (super()) call }
    cmpTmp, cmpSeq, cmpAsgn: Integer;   { comprehension into a non-list target }
    cmpExisted: Boolean;
begin
  Result := -1;
  PyStmtAteBlock := False;
  PyExprHadOptionalMissing := False;
  { `nonlocal x, y` / `global x, y` — a scope DECLARATION, parsed and skipped.
    The nested-def capture already exposes the enclosing name for reading; a
    WRITE does not yet propagate back to the enclosing frame (capture is
    by-value) — filed as feature-nilpy-nonlocal-write-propagation. }
  if PyIsIdent('nonlocal') or PyIsIdent('global') then
  begin
    Next;
    while CurTok.Kind = tkIdent do
    begin
      Next;
      if not Eat(tkComma) then Break;
    end;
    Result := -1;
    Exit;
  end;
  if PyUnpackTargetAhead then begin Result := PyParseUnpackAssign; Exit; end;
  { Nested `def`: register the shell here (the enclosing body's calls resolve
    against it), remember where the body starts, and skip it — PyParseDef
    compiles the queued bodies after its own epilogue, because emitting one in
    place would drop it into the middle of the enclosing routine's code
    (feature-nilpy-nested-defs). }
  if CurTok.Kind = tkFunction then begin Result := PyQueueNestedDef; Exit; end;
  if CurTok.Kind = tkIf then begin Result := PyParseIf; Exit; end;
  if CurTok.Kind = tkWhile then begin Result := PyParseWhile; Exit; end;
  if CurTok.Kind = tkTry then
  begin
    { the fallback-import idiom is decided at compile time, not caught at
      runtime — see PyParseFallbackImportTry }
    if PyIsFallbackImportTry then Result := PyParseFallbackImportTry
    else Result := PyParseTry;
    Exit;
  end;
  if PyIsIdent('with') then begin Result := PyParseWith; Exit; end;
  { `raise <expr>` and bare `raise` (re-raise inside a handler). }
  if CurTok.Kind = tkRaise then
  begin
    Next;
    node := AllocNode(AN_RAISE);
    if CurTok.Kind in [tkNewline, tkDedent, tkEOF] then
      ASTLeft[node] := -1
    else
    begin
      PyParseBoolExpr;
      ASTLeft[node] := CurASTNode;
      { `raise X from e` — PEP 3134 exception chaining. The cause is metadata
        (it sets __cause__ for the traceback); the raise itself is unchanged, so
        `from EXPR` is consumed and dropped. }
      if PyIsIdent('from') then
      begin
        Next;
        PyParseBoolExpr;
      end;
    end;
    Result := node;
    Exit;
  end;
  if (CurTok.Kind = tkFor) or PyIsIdent('for') then begin Result := PyParseFor; Exit; end;
  if PyIsIdent('pass') then begin Next; Exit; end;
  { `break` / `continue`. The lexer already maps break to tkBreak, but no
    statement rule ever consumed either, so both died as "expected expression"
    INSIDE a loop that otherwise worked — including a plain while. }
  if (CurTok.Kind = tkBreak) or PyIsIdent('break') then
  begin
    Next;
    Result := AllocNode(AN_BREAK);
    Exit;
  end;
  if (CurTok.Kind = tkContinue) or PyIsIdent('continue') then
  begin
    Next;
    Result := AllocNode(AN_CONTINUE);
    Exit;
  end;
  { `del d[k]` -> d.remove(k). Only the dict-subscript form is supported; the
    other censused use is `del lst[a:]`, which needs slices and is not this
    ticket. Parsed as a statement rather than through the expression grammar
    because `d[k]` on its own would compile to a subscript READ. }
  { An `import` in the body — Python allows one anywhere, and a real file puts a
    block of them after its docstring or a try/except. Same code as the leading
    run (PyParseImportRun); before this they were consumed and dropped. }
  if (CurTok.Kind = tkUses) or (PyIsIdent('from') and (TokPos < TokCount) and
      (Tokens[TokPos].Kind = tkIdent)) then
  begin
    { ONE import statement, not a run: inside a block the trailing NEWLINE
      terminates the statement and belongs to the block parser, while
      PyParseImportRun skips newlines to reach the next import — which made the
      following line read as a continuation. The unit is registered exactly as
      the run would; only the newline handling differs.
      bug-nilpy-function-level-import-drops-body. }
    PyParseOneImport;
    Result := -1;
    Exit;
  end;
  if PyIsIdent('del') then
  begin
    Next;
    { `del name` on a plain LOCAL is accepted and emits nothing. Python unbinds
      the name, so a later read raises NameError; NilPy has no binding to remove
      and does not diagnose that later read — laxity in the same direction as
      the keyword-only marker (we accept programs CPython rejects, and run every
      program we accept the same way). The censused use is `del sections` as an
      explicit "this parameter is deliberately unused". }
    if (CurTok.Kind = tkIdent) and (TokPos < TokCount) and
       (Tokens[TokPos].Kind in [tkNewline, tkDedent, tkEOF]) and
       (FindSym(CurTok.SVal) >= 0) then
    begin
      Next;
      Result := -1;
      Exit;
    end;
    { Parse the whole `d[k]` normally — it lowers to TPyDict.fetch(d, k) via
      the default indexed property — then REWRITE that call to .remove(d, k).
      Parsing the base and the subscript separately would mean re-implementing
      the postfix grammar (`del vm.file_handles[fid]` has a field base), which
      is exactly the duplication this frontend keeps getting bitten by. }
    PyParseBoolExpr;
    delBase := CurASTNode;
    { `del l[lo:hi]` — the read lowered to a pylist_slice COPY; swap the proc to
      the in-place delete (same l, lo, hi arguments). }
    if (ASTKind[delBase] = AN_CALL) and (FindProc('pylist_slice') >= 0) and
       (ASTIVal[delBase] = FindProc('pylist_slice')) then
    begin
      symIdx := FindProc('pylist_del_slice');
      if symIdx < 0 then Error('Nil Python: pylib (pylist_del_slice) not loaded');
      ASTIVal[delBase] := symIdx;
      ASTTk[delBase] := Ord(Procs[symIdx].RetType);
      Result := delBase;
      Exit;
    end;
    ci := FindUClass('TPyDict');
    symIdx := -1;
    if ci >= 0 then symIdx := FindUMeth(ci, 'fetch');
    if (symIdx < 0) or (ASTKind[delBase] <> AN_CALL) or
       (ASTIVal[delBase] <> UMthProc_[symIdx]) then
      Error('Nil Python: del is supported on a dict subscript or a list slice (del d[k], del l[a:b])');
    symIdx := FindUMeth(ci, 'remove');
    if symIdx < 0 then Error('Nil Python: TPyDict.remove not found');
    ASTIVal[delBase] := UMthProc_[symIdx];
    ASTTk[delBase] := Ord(Procs[UMthProc_[symIdx]].RetType);
    Result := delBase;
    Exit;
  end;
  if CurTok.Kind = tkExit then
  begin
    Next;
    node := AllocNode(AN_EXIT);
    if not (CurTok.Kind in [tkNewline, tkDedent, tkEOF]) then
    begin
      if (CurTok.Kind = tkNil) and (CurProc >= 0) and
         (Procs[CurProc].RetSymIdx >= 0) and
         (Syms[Procs[CurProc].RetSymIdx].TypeKind = tyVariant) and
         ((TokPos >= TokCount) or
          (Tokens[TokPos].Kind in [tkNewline, tkDedent, tkEOF, tkSemicolon])) then
      begin
        { `return None` from a variant-returning def hands back a real None
          (VT_EMPTY): the nil literal lowers to integer 0 elsewhere, so the
          caller's `is None` tag test failed on every guard-path return —
          uforth's _parse_number returned 0 for a junk token, which was PUSHED
          instead of raising THROW -13
          (bug-nilpy-uforth-exceptiontest-source-unlink). Non-variant results
          keep the documented 0/nil sentinel mapping. }
        Next;
        ASTLeft[node] := PyMakeNone;
      end
      else
      begin
        PyParseBoolExpr;
        if CurTok.Kind = tkComma then
          { `return a, b` returns a tuple, which is a TPyList here }
          ASTLeft[node] := PyMakeTupleFrom(CurASTNode)
        else
          { `return inner` — a nested def taken as a VALUE lowers to a heap
            object pointer (pyboundfn_new + binds), and a raw pointer stored in
            the Variant result is not a callable to the caller: `mk(100)(1)`
            answered None with no diagnostic. Box it exactly as `g = lambda...`
            does (bug-nilpy-returning-a-nested-def-yields-none). }
          ASTLeft[node] := PyBoxCallableValue(CurASTNode);
      end;
    end;
    Result := node;
    Exit;
  end;
  if PyIsIdent('print') or (CurTok.Kind = tkwriteln) then
  begin
    Result := PyParsePrint;
    Exit;
  end;
  if PyIsIdent('super') and (TokPos < TokCount) and
     (Tokens[TokPos].Kind = tkLParen) then
  begin
    Next; Expect(tkLParen, '('); Expect(tkRParen, ')');
    Expect(tkDot, '.');
    if CurTok.Kind <> tkIdent then Error('Nil Python: expected method after super().');
    name := CurTok.SVal;
    Next;
    Expect(tkLParen, '(');
    { super().__init__(msg) in an Exception-descended class STORES the message
      (self.msg := msg): Python keeps it as args[0] and str(e) / f"{e}" read it
      back — discarding it left every user exception with an empty text
      (feature-nilpy-exception-message-text). Any other super() call keeps the
      v1 discard below (args unevaluated). }
    ci := -1;
    if CaseEqual(name, '__init__') and (CurSelfClass >= REC_UCLASS_BASE) and
       (CurTok.Kind <> tkRParen) then
    begin
      ci := FindUClass('Exception');
      if (ci >= 0) and (CurSelfClass - REC_UCLASS_BASE <> ci) and
         (not IsSubclassOf(CurSelfClass - REC_UCLASS_BASE, ci)) then ci := -1;
      if ci >= 0 then
      begin
        symIdx := PyProgSym('self');
        if symIdx < 0 then ci := -1;
      end;
    end;
    if ci >= 0 then
    begin
      PyParseBoolExpr;
      rhsNode := CurASTNode;
      Expect(tkRParen, ')');
      lhsNode := AllocNode(AN_FIELD);
      ASTLeft[lhsNode] := PyMakeIdent(symIdx);
      ASTSOffset[lhsNode] := PyStoredName('msg');
      ASTSLen[lhsNode] := 3;
      ASTTk[lhsNode] := Ord(tyAnsiString);
      node := AllocNode(AN_ASSIGN);
      ASTLeft[node] := lhsNode;
      ASTRight[node] := rhsNode;
      Result := node;
      Exit;
    end;
    { The inherited call itself — shared with the EXPRESSION position, where
      `return "B" + super().who()` needs the identical node. }
    Result := PyMakeSuperCall(name);
    Exit;
  end;
  if (CurTok.Kind = tkIdent) and (TokPos < TokCount) and
     (Tokens[TokPos].Kind = tkDot) then
  begin
    PyParseBoolExpr;
    lhsNode := CurASTNode;
    { tkSemicolon ends a statement too — `if c: xs.append(1); i += 2` puts a
      method-call expression statement before a ';' on a one-line suite. }
    if CurTok.Kind in [tkNewline, tkDedent, tkEOF, tkSemicolon] then
    begin
      Result := lhsNode;   { expression statement, e.g. obj.method() }
      Exit;
    end;
    { `self.x: T = expr` — an annotated FIELD assignment. The annotation was
      already consumed by the class field pre-pass, which is what decides the
      field's type; skip it here so the assignment itself parses. Without this
      the idiomatic annotated ctor body died on Expect(tkAssign). }
    if CurTok.Kind = tkColon then
    begin
      annIdx := TokPos;              { first annotation token }
      tk := PyAnnTypeAt(annIdx);     { advances annIdx past the annotation }
      TokPos := annIdx;
      Next;                          { CurTok = the '=' }
    end;
    augTk := PyAugBinTok(CurTok.Kind);
    if augTk <> tkEOF then
    begin
      Next;
      PyParseBoolExpr;
      if (augTk = tkPlus) and (PyNodeListCi(lhsNode) >= 0) then
      begin
        { list += list is in-place extend, and the whole statement IS the call }
        Result := PyCallMeth1(PyNodeListCi(lhsNode), 'extend', lhsNode, CurASTNode);
        if Result < 0 then Error('Nil Python: pylib TPyList.extend not loaded');
        Exit;
      end;
      node := AllocNode(AN_BINOP); ASTIVal[node] := Ord(augTk);
      ASTLeft[node] := lhsNode; ASTRight[node] := CurASTNode;
      { `l += y` where l's STATIC type is a variant (an unannotated parameter,
        a list out of a list/dict, ...): PyNodeListCi above only recognises a
        STATICALLY tyClass/TPyList target, so this is the variant case the
        in-place `extend` above cannot reach. Mark the node so the IR's
        variant-dispatch arm for `+` picks pyaugadd_v, which extends IN PLACE
        when the runtime value turns out to hold a list (mutating the object
        every alias shares) and otherwise behaves exactly like pyadd_v
        (bug-nilpy-augmented-add-on-variant-list-is-not-in-place). }
      if (augTk = tkPlus) and (IntToTypeKind(ASTTk[lhsNode]) = tyVariant) then
        ASTSLen[node] := PY_BINOP_AUGADD;
      { `/=` is TRUE division: always a float, regardless of operand types
        (`4 /= 2` is 2.0, not 2) -- same rule the plain `/` binop already has
        via FloatBinopResultTk. Falling through to the generic PyWiden below
        (as every other augmented op does) would keep an int-typed node
        storing a float bit pattern: the same class of bug as
        bug-nilpy-str-of-mixed-mod-prints-double-bits, just for `/=`.
        feature-nilpy-power-operator-and-divmod }
      if augTk = tkSlash then
      begin
        { a bare-NAME target reuses its EXISTING symbol rather than allocating
          a fresh one, so the widening harvest (which unions types across
          MULTIPLE Syms[] entries for the same name) never learns this name
          needs to be a float -- see the twin name-fast-path site's note. }
        if PyTypingPass and (ASTKind[lhsNode] = AN_IDENT) and
           (Syms[Integer(ASTIVal[lhsNode])].TypeKind <> tyDouble) then
          PyNoteLocalType(Syms[Integer(ASTIVal[lhsNode])].Name,
                          FloatBinopResultTk(IntToTypeKind(ASTTk[lhsNode]),
                                             IntToTypeKind(ASTTk[CurASTNode])),
                          REC_NONE);
        ASTTk[node] := Ord(FloatBinopResultTk(IntToTypeKind(ASTTk[lhsNode]),
                                              IntToTypeKind(ASTTk[CurASTNode])));
      end
      else
        { widen, don't copy the lhs type: `n -= 0x10000000000000000` on an int
          target must type the binop PROMO or the wide literal is machine-lowered
          (out of range); the promo->int store then narrows mod 2^64 }
        ASTTk[node] := Ord(PyWiden(IntToTypeKind(ASTTk[lhsNode]),
                                   IntToTypeKind(ASTTk[CurASTNode])));
      rhsNode := node;
    end
    else
    begin
      Expect(tkAssign, '=');
      { `d[k] = None` / `o.f = None` stores a real None (VT_EMPTY), not the
        integer 0 the nil literal lowers to elsewhere
        (feature-nilpy-none-variant) — UNLESS the target is a scalar-numeric
        field (`self.x: Optional[int] = None`), where Optional[int] mapped to
        tyInt64 and None is that type's 0 sentinel. Storing a variant None there
        would coerce via pyvar_to_int and raise 'expected a number'. }
      if PyBareNoneHere then
      begin
        Next;
        if PyNumeric(IntToTypeKind(ASTTk[lhsNode])) then
        begin
          rhsNode := AllocNode(AN_INT_LIT);
          ASTIVal[rhsNode] := 0;
          ASTTk[rhsNode] := ASTTk[lhsNode];
        end
        else if IntToTypeKind(ASTTk[lhsNode]) in [tyAnsiString, tyString] then
        begin
          { str-typed target: the None sentinel is a NIL handle (what
            pystr_is_none tests and `if self.f` must see as falsy). The
            variant-None route below would coerce through variant->string and
            store the TEXT 'None' — truthy, and `is None` false
            (bug-nilpy-none-into-str-field-stores-text). }
          rhsNode := AllocNode(AN_CALL);
          ASTIVal[rhsNode] := FindProc('pystr_none');
          if ASTIVal[rhsNode] < 0 then Error('Nil Python: pylib (pystr_none) not loaded');
          ASTTk[rhsNode] := Ord(tyAnsiString);
        end
        else
          rhsNode := PyMakeNone;
      end
      else if PyIsEmptySetCall then
        rhsNode := PyParseEmptySet
      else if PyIsCountCall then
        rhsNode := PyParseCountCreate
      else
      begin
        PyParseBoolExpr;
        rhsNode := CurASTNode;
      end;
    end;
    { `self.memory[a:b] = src` — the lhs parsed as a pybytes_slice READ; turn
      it into the setter call, which IS the whole statement. }
    if PyIsBytesSliceCall(lhsNode) then
    begin
      Result := PyRewriteSliceAssign(lhsNode, rhsNode);
      Exit;
    end;
    { `Word._xt_counter = _count(1)`: a class-static (AN_IDENT of the
      backing global) learns its class from a class-typed rhs. }
    if (ASTKind[lhsNode] = AN_IDENT) and
       (ASTKind[rhsNode] = AN_CALL) and (ASTIVal[rhsNode] = -Ord(tkGetMem)) then
      Syms[ASTIVal[lhsNode]].RecName := ASTRight[rhsNode]
    { ...and from an ordinary CALL that returns a class: `c = Counter()` left the
      local tyClass with NO class identity, so every later `c.method(...)` went
      through the DYNAMIC receiver path instead of a direct call. Correctness now
      rests elsewhere (the wild dereference this was first written to chase was
      really [[bug-nativeuint-cast-widens-load]]); what it buys is the direct
      call and the class identity a later field access needs.

      NOT guarded on RecName already being REC_NONE (the original form of this
      rule): a name REBOUND to a call returning a DIFFERENT class kept its
      stale identity from an earlier binding — `with open(p,"w") as f: ...`
      then a later plain `f = open(p, "r")` left f's RecName at TPyFile while
      the runtime value was now a TPyList, so `f.readlines()` / `len(f)`
      dispatched against the wrong class and read the wrong memory (the same
      RTTI-blob disclosure shape as
      bug-nilpy-file-write-drops-data-and-read-to-print-dumps-rtti-memory, via
      a different trigger). A genuine class-returning call always wins. }
    else if (ASTKind[lhsNode] = AN_IDENT) and
            (ASTKind[rhsNode] = AN_CALL) and (Integer(ASTIVal[rhsNode]) >= 0) and
            (Integer(ASTIVal[rhsNode]) < ProcCount) and
            (IntToTypeKind(ASTTk[rhsNode]) = tyClass) and
            (ProcRetRecId[Integer(ASTIVal[rhsNode])] >= REC_UCLASS_BASE) then
      Syms[ASTIVal[lhsNode]].RecName := ProcRetRecId[Integer(ASTIVal[rhsNode])];
    { Storing a VARIANT (dict/list element, dynamically typed) into a tyClass slot
      must unbox to the instance pointer — otherwise the raw variant overwrites the
      8-byte class slot and the object reads as garbage / loses identity. }
    if (IntToTypeKind(ASTTk[lhsNode]) = tyClass) and
       (IntToTypeKind(ASTTk[rhsNode]) = tyVariant) and
       (ResolveNodeRec(lhsNode) >= REC_UCLASS_BASE) then
      rhsNode := PyUnboxVariantToClass(rhsNode, ResolveNodeRec(lhsNode) - REC_UCLASS_BASE);
    node := AllocNode(AN_ASSIGN);
    ASTLeft[node] := lhsNode;
    ASTRight[node] := rhsNode;
    Result := node;
    Exit;
  end;
  if (CurTok.Kind = tkIdent) and (TokPos < TokCount) and
     (PyAugBinTok(Tokens[TokPos].Kind) <> tkEOF) then
  begin
    name := CurTok.SVal;
    symIdx := PyProgSym(name);
    if symIdx < 0 then
      Error('Nil Python: augmented assignment to undefined name ' + name);
    Next;
    augTk := PyAugBinTok(CurTok.Kind);
    Next;
    PyParseBoolExpr;
    if (augTk = tkPlus) and (PyNodeListCi(PyMakeIdent(symIdx)) >= 0) then
    begin
      Result := PyCallMeth1(PyNodeListCi(PyMakeIdent(symIdx)), 'extend',
                            PyMakeIdent(symIdx), CurASTNode);
      if Result < 0 then Error('Nil Python: pylib TPyList.extend not loaded');
      Exit;
    end;
    { `n = 7; n /= 2` -- unlike a plain rebind (`n = n / 2`), an augmented
      assignment reuses the EXISTING symIdx rather than allocating a fresh
      Syms[] entry, so the widening harvest in PyCollectLocalsAST/
      PyCollectModuleLocalsAST -- which unions types by seeing MULTIPLE
      entries for the same name -- never learns `n` needs to be a float:
      the frame slot stayed Int64 and `print(n)` read the Double's raw bits
      through an integer formatter. Note the constraint explicitly, the same
      way a for-loop target does, so the target's OWN declared type widens
      across trial-parse rounds rather than only the local node's.
      feature-nilpy-power-operator-and-divmod }
    if PyTypingPass and (augTk = tkSlash) and (Syms[symIdx].TypeKind <> tyDouble) then
      PyNoteLocalType(name, FloatBinopResultTk(Syms[symIdx].TypeKind,
                                               IntToTypeKind(ASTTk[CurASTNode])), REC_NONE);
    PyNoteOptionalTaint(symIdx, CurASTNode);
    PyCoerceAssignmentRHS(Syms[symIdx].TypeKind, CurASTNode);
    node := AllocNode(AN_BINOP); ASTIVal[node] := Ord(augTk);
    ASTLeft[node] := PyMakeIdent(symIdx); ASTRight[node] := CurASTNode;
    { see the twin lhs-expression site's note: a variant target's `+=` must
      extend a runtime list IN PLACE rather than rebind
      (bug-nilpy-augmented-add-on-variant-list-is-not-in-place). }
    if (augTk = tkPlus) and (Syms[symIdx].TypeKind = tyVariant) then
      ASTSLen[node] := PY_BINOP_AUGADD;
    { `/=` is always a float (see the twin lhs-expression site's note); widen,
      don't copy the target type otherwise: `n -= 0x10000000000000000` on an
      int target must type the binop PROMO (see the twin lhs-expression site) }
    if augTk = tkSlash then
      ASTTk[node] := Ord(FloatBinopResultTk(Syms[symIdx].TypeKind,
                                            IntToTypeKind(ASTTk[CurASTNode])))
    else
      ASTTk[node] := Ord(PyWiden(Syms[symIdx].TypeKind,
                                 IntToTypeKind(ASTTk[CurASTNode])));
    rhsNode := node;
    node := AllocNode(AN_ASSIGN);
    ASTLeft[node] := PyMakeIdent(symIdx);
    ASTRight[node] := rhsNode;
    Result := node;
    Exit;
  end;
  { Annotated assignment `NAME : ann = expr`.

    The annotation goes through PyAnnTypeAt, the same grammar a FIELD or a
    parameter gets. It used to be read by PyTypeFromTokenIndex and the match
    required the '=' to sit exactly two tokens after the name — so the
    annotation had to be a SINGLE token, and `d: Dict[str, int] = {}` at
    module or function scope failed while the identical `self.d: Dict[...]`
    worked. Same class of bug as the method-parameter one: two readers for one
    grammar, and the narrow one wins wherever it is still wired up. }
  if (CurTok.Kind = tkIdent) and (TokPos + 2 < TokCount) and
     (Tokens[TokPos].Kind = tkColon) then
  begin
    annIdx := TokPos + 1;
    tk := PyAnnTypeAt(annIdx);
    ci := PyAnnLastCi;
    annSig := PyAnnLastProcSig;
    if (tk <> tyUnknown) and (annIdx < TokCount) and
       (Tokens[annIdx].Kind = tkAssign) then
    begin
      name := CurTok.SVal;
      TokPos := annIdx;
      Next;                      { CurTok = '=' }
      Expect(tkAssign, '=');
      PyParseBoolExpr;
      symIdx := PyProgSym(name);
      if symIdx < 0 then
      begin
        { `s: str` means an UNBOUNDED Python string, so the local is managed —
          tyString is the frozen kind and truncated at 255 characters, silently
          (bug-nilpy-string-local-truncates-at-255). Class FIELDS have mapped
          str this way all along; locals now agree with them. }
        if tk = tyString then tk := tyAnsiString;
        symIdx := AllocVar(name, tk);
        if (tk = tyClass) and (ci >= 0) then
          Syms[symIdx].RecName := REC_UCLASS_BASE + ci;
        if annSig >= 0 then SymProcSig[symIdx] := annSig;
      end;
      lhsNode := PyMakeIdent(symIdx);
      PyNoteOptionalTaint(symIdx, CurASTNode);
    PyCoerceAssignmentRHS(Syms[symIdx].TypeKind, CurASTNode);
      node := AllocNode(AN_ASSIGN);
      ASTLeft[node] := lhsNode;
      ASTRight[node] := CurASTNode;
      Result := node;
      Exit;
    end;
  end;
  if (CurTok.Kind = tkIdent) and (TokPos < TokCount) and
     (Tokens[TokPos].Kind = tkAssign) then
  begin
    name := CurTok.SVal;
    symIdx := PyProgSym(name);
    Next;
    Expect(tkAssign, '=');
    { `target = [EXPR for VAR in ITER]` — a list comprehension. Desugared to an
      empty-list init plus an appending loop, so the whole statement IS that
      sequence, not an ordinary assignment. }
    if PyIsListCompAhead then
    begin
      { A name being introduced HERE is born as the list itself; only a name
        that already exists with some other type needs the detour below. }
      cmpExisted := symIdx >= 0;
      if symIdx < 0 then symIdx := AllocVar(name, tyClass);
      if cmpExisted and (PyNodeListCi(PyMakeIdent(symIdx)) < 0) then
      begin
        { The name already exists with a type that is not a list — a variant
          PARAMETER being rebound is the common case, and songformatter writes
          exactly that (`fret_positions = [... for fret in fret_positions]`).
          The loop appends INTO the target, so a non-list target left the
          append with no class to resolve against and the whole comprehension
          failed with a misleading "pylib TPyList.append/add not loaded".
          Build into a hidden list and assign it across instead. }
        cmpTmp := AllocVar(PyHiddenName('comp'), tyClass);
        Syms[cmpTmp].RecName := REC_UCLASS_BASE + FindUClass('TPyList');
        cmpSeq := PyParseListComp(cmpTmp);
        cmpAsgn := AllocNode(AN_ASSIGN);
        ASTLeft[cmpAsgn] := PyMakeIdent(symIdx);
        ASTRight[cmpAsgn] := PyMakeIdent(cmpTmp);
        Result := PySeqAppend(cmpSeq, cmpAsgn);
        Exit;
      end;
      Result := PyParseListComp(symIdx);
      Exit;
    end;
    { a brace comprehension with a colon key — a dict comprehension. }
    if PyIsDictCompAhead then
    begin
      if symIdx < 0 then symIdx := AllocVar(name, tyClass);
      Syms[symIdx].RecName := REC_UCLASS_BASE + FindUClass('TPyDict');
      Result := PyParseDictComp(symIdx);
      Exit;
    end;
    { `res = None` stores a real None (VT_EMPTY), exactly as the `self.x = None`
      and `d[k] = None` routes already did. Without it the nil literal lowered
      to a plain zero, so the local was born non-variant and the very next
      `res = <int>` failed to widen — "annotate the type / too dynamic" on the
      ordinary Python idiom of seeding a result with None
      (bug-nilpy-none-assign-to-plain-local). Sibling branches again. }
    if PyBareNoneHere then
    begin
      Next;
      rhsNode := PyMakeNone;
    end
    else if (CurTok.Kind = tkIdent) and IsClassType(CurTok.SVal) and
       (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) and
       (not PyCtorSuffixAhead) then
      { ...but `x = Cls().method(...)` is not a construction ASSIGNMENT: the
        construction is the RECEIVER. Leave it to the expression parser, whose
        factor path builds the construction and then applies the method suffix
        (bug-nilpy-method-call-on-fresh-construction). }
      rhsNode := PyClassCreate
    else if PyIsEmptySetCall then
      rhsNode := PyParseEmptySet
    else if PyIsCountCall then
      rhsNode := PyParseCountCreate
    else
    begin
      { `cb = handler` — a bare def NAME as the whole right-hand side is
        Python's function object, the same value an ARGUMENT position already
        builds (PyMakeFuncValue: a pybound_new pair, tyVariant). Parsed as an
        ordinary read the local came out non-variant, so the later `cb(...)`
        never reached the dynamic-call path and the call did nothing at all.
        PyMakeFuncValue returns -1 (consuming nothing) unless the token really
        is a def name in a value position. }
      rhsNode := -1;
      if (CurTok.Kind = tkIdent) and (TokPos < TokCount) and
         (Tokens[TokPos].Kind in [tkNewline, tkDedent, tkEOF]) then
        rhsNode := PyMakeFuncValue;
      if rhsNode < 0 then
      begin
        PyParseBoolExpr;
        rhsNode := CurASTNode;
        { `g = lambda ...`: box the closure/bound-fn pointer so the name is a
          variant and `g(...)` reaches the dynamic-call path at all. }
        rhsNode := PyBoxCallableValue(rhsNode);
      end;
    end;
    if symIdx < 0 then
    begin
      tk := IntToTypeKind(ASTTk[rhsNode]);
      if CurProc < 0 then
      begin
        ci := PyFindModuleConstraint(name);
        if ci >= 0 then tk := PyModuleLocals[ci].TypeKind;
      end;
      { see the annotated branch above: a NilPy string variable is managed }
      if tk = tyString then tk := tyAnsiString;
      symIdx := AllocVar(name, tk);
    end;
    if (ASTKind[rhsNode] = AN_CALL) and (ASTIVal[rhsNode] = -Ord(tkGetMem)) then
      Syms[symIdx].RecName := ASTRight[rhsNode]
    else if (ASTKind[rhsNode] = AN_CALL) and (ASTIVal[rhsNode] >= 0) and
            (Procs[ASTIVal[rhsNode]].RetType = tyClass) then
      { class-returning call (e.g. a chained list-literal append): carry the
        result class so methods/subscripts on the variable resolve }
      Syms[symIdx].RecName := ProcRetRecId[ASTIVal[rhsNode]]
    else if (Syms[symIdx].TypeKind = tyClass) and
            (ResolveNodeRec(rhsNode) >= REC_UCLASS_BASE) then
      { any other class-valued RHS — notably a FIELD access, `x = o.inner`.
        Without this the local was declared tyClass with no RecName, so the
        later `x.name` had no class to resolve against and read the object
        pointer as the field (bug-nilpy-class-typed-field-loses-identity). }
      Syms[symIdx].RecName := ResolveNodeRec(rhsNode);

    { Trial parse: every assignment widens the local, not just the first one
      (the symbol only remembers the first). }
    if PyTypingPass then
    begin
      PyNoteLocalType(name, IntToTypeKind(ASTTk[rhsNode]), ResolveNodeRec(rhsNode));
    end;
    lhsNode := PyMakeIdent(symIdx);
    PyNoteOptionalTaint(symIdx, rhsNode);
    PyCoerceAssignmentRHS(Syms[symIdx].TypeKind, rhsNode);
    node := AllocNode(AN_ASSIGN);
    ASTLeft[node] := lhsNode;
    ASTRight[node] := rhsNode;
    Result := node;
    Exit;
  end;
  PyParseBoolExpr;
  { `buf[a:b] = src` on a plain local. Unlike `self.buf[a:b] = src` this never
    reaches an assignment route: a slice is not an ordinary lvalue, so the
    expression path returned the READ call and left the '=' sitting there. }
  if PyIsBytesSliceCall(CurASTNode) and (CurTok.Kind = tkAssign) then
  begin
    lhsNode := CurASTNode;
    Next;
    PyParseBoolExpr;
    Result := PyRewriteSliceAssign(lhsNode, CurASTNode);
    Exit;
  end;
  Result := CurASTNode;
end;

function PyParseBlock: Integer;
var stmt: Integer;
begin
  Result := -1;
  PySkipNewlines;
  while not (CurTok.Kind in [tkDedent, tkEOF]) do
  begin
    stmt := PyParseStatement;
    Result := PyFlushHoist(Result);
    Result := PySeqAppend(Result, stmt);
    { `u = int(vm.pop()); addr = int(vm.pop())` — Python allows several simple
      statements on one line, separated by ';'. Consumed here so the newline
      check below still applies to the LAST one on the line. }
    while CurTok.Kind = tkSemicolon do
    begin
      Next;
      if CurTok.Kind in [tkNewline, tkDedent, tkEOF] then Break;  { trailing ';' }
      stmt := PyParseStatement;
      Result := PyFlushHoist(Result);
      Result := PySeqAppend(Result, stmt);
    end;
    if CurTok.Kind = tkNewline then PySkipNewlines
    else if (stmt >= 0) and (ASTKind[stmt] in [AN_IF, AN_WHILE, AN_FOR,
                                               AN_TRY_EXCEPT, AN_TRY_FINALLY]) then
      continue
    else if PyStmtAteBlock then
    begin
      { a nested `def`: like if/while/for it consumed its own indented block
        (and the DEDENT that closes it), but it produces no statement node
        (feature-nilpy-nested-defs) }
      PyStmtAteBlock := False;
      continue;
    end
    else if not (CurTok.Kind in [tkDedent, tkEOF]) then
      Error('Nil Python: expected newline after statement');
  end;
end;

{ Type a body's implicit locals by PARSING it, not by scanning its tokens.

  Python declares a local by assigning to it, and a local's type can WIDEN
  across branches (`x = 1` then `x = "s"` -> variant), so the frame cannot be
  laid out until every assignment has been seen. That constraint is real; the
  old answer to it was not. PyCollectLocals met it with a token scanner
  (PyInferExprType and friends) that re-implemented expression typing a second
  time and drifted from the parser that actually builds the call — a str method
  returning a class was invisible to it, and `"a,b".split(",")` was invisible
  because the scan only inspected IDENT tokens.

  So: keep the pre-pass, drop the scanner. Parse the body to AST in a scratch
  scope and let the ordinary assignment path type each local from ASTTk of the
  node it just built (pyparser's `symIdx < 0` branch already does exactly
  that — this only gives it a second look at the body). Then throw the scratch
  AST and scratch symbols away and keep the widened name->type table. Nothing
  here can drift from the real parse because it IS the real parse — the same
  shape rparser.inc:RParseLet and zparser.inc:ZParseVarDecl already use.

  Iterated to a fixed point: round 1 types `x` from its FIRST assignment, so a
  `y = x + 1` between two assignments to `x` still sees the pre-widening `x`.
  Re-seeding the scratch scope from the widened table and re-parsing settles
  it. PyWiden only ever widens, so the loop is monotone; PY_INFER_ROUNDS caps
  it anyway rather than trusting that forever.

  Safe to run over the same tokens repeatedly: NilPy statement and expression
  parsing allocates AST nodes and scope-local symbols and emits NO code (the
  prologue is emitted by the caller, after this returns), and both allocations
  are rolled back here. }
const PY_INFER_ROUNDS = 4;

{ PXXDBG=n.locals — the inferred local table, after the fixed-point rounds.
  The other probe hand-patched during the same hunt: "what type did NilPy
  actually give this local" was previously unanswerable without a rebuild. }
procedure PyDbgDumpLocals(const whose: AnsiString);
var i: Integer;
begin
  if not PxxDbgEnabled('n.locals') then Exit;
  for i := 0 to PyLocalCount - 1 do
    WriteLn('PXXDBG n.locals ', whose, ' ', PyLocals[i].Name,
            ' tk=', Ord(PyLocals[i].TypeKind), ' rec=', PyLocals[i].RecCi);
end;

procedure PyCollectLocalsAST(bodyStart: Integer);
var rnd, i, si, savedTok, savedAST, savedSC, savedCur, savedFS: Integer;
    changed: Boolean;
    tk, w: TTypeKind;
    nm: AnsiString;
begin
  PyLocalCount := 0;
  rnd := 0;
  repeat
    changed := False;
    PyTypingChanged := False;
    PyTypingPass := True;
    savedTok := TokPos;
    savedAST := ASTNodeCount;
    savedCur := CurASTNode;
    savedSC := SymCount;
    savedFS := FrameSize;
    { seed the scratch scope with what the previous round learned }
    for i := 0 to PyLocalCount - 1 do
      if PyProgSym(PyLocals[i].Name) < 0 then
      begin
        si := AllocVar(PyLocals[i].Name, PyLocals[i].TypeKind);
        if (PyLocals[i].TypeKind = tyClass) and (PyLocals[i].RecCi >= 0) then
          Syms[si].RecName := REC_UCLASS_BASE + PyLocals[i].RecCi;
      end;
    TokPos := bodyStart;
    Next;
    PyParseBlock;
    { harvest every symbol the body declared, widening against the table }
    for i := savedSC to SymCount - 1 do
    begin
      nm := Syms[i].Name;
      if nm = '' then Continue;
      { Hidden for-in temps are re-created by the real parse with fresh
        serials, so harvesting the trial pass's ones would reserve frame slots
        that nothing ever reads — one wasted triple per loop per round. }
      if Copy(nm, 1, 5) = '__py_' then Continue;
      tk := Syms[i].TypeKind;
      si := PyFindConstraint(nm);
      if si < 0 then
      begin
        if PyLocalCount >= PY_MAX_LOCALS then
          Error('Nil Python: too many inferred locals');
        PyLocals[PyLocalCount].Name := nm;
        PyLocals[PyLocalCount].TypeKind := tk;
        if Syms[i].RecName >= REC_UCLASS_BASE then
          PyLocals[PyLocalCount].RecCi := Syms[i].RecName - REC_UCLASS_BASE
        else
          PyLocals[PyLocalCount].RecCi := -1;
        Inc(PyLocalCount);
        changed := True;
      end
      else
      begin
        w := PyWiden(PyLocals[si].TypeKind, tk);
        if w <> PyLocals[si].TypeKind then
        begin
          PyLocals[si].TypeKind := w;
          changed := True;
        end;
        { NOT guarded on RecCi already being SET (the original form of this
          rule): a name reassigned across ROUNDS to a call returning a
          DIFFERENT class kept its FIRST round's class identity forever, so
          `with open(p,"w") as f: ...` then a later plain `f = open(p, "r")`
          left f dispatching as a TPyFile while it now held a TPyList --
          .readlines() / len() read the wrong class's layout and printed the
          RTTI blob (the same disclosure shape as
          bug-nilpy-file-write-drops-data-and-read-to-print-dumps-rtti-memory,
          via a different trigger than that ticket's write() overload). Take
          the latest resolved class whenever it differs. }
        if (Syms[i].RecName >= REC_UCLASS_BASE) and
           (PyLocals[si].RecCi <> Syms[i].RecName - REC_UCLASS_BASE) then
        begin
          PyLocals[si].RecCi := Syms[i].RecName - REC_UCLASS_BASE;
          changed := True;
        end;
      end;
    end;
    PyTypingPass := False;
    if PyTypingChanged then changed := True;
    SymRollbackTo(savedSC);
    ASTNodeCount := savedAST;
    FrameSize := savedFS;
    CurASTNode := savedCur;
    { hoisted setup statements queued during the TRIAL parse reference AST
      nodes the rollback just discarded — flushing them into the real parse
      lowered recycled node ids (IR_UNSUPPORTED kind 9 after a multi-expr
      f-string, once the literal bind-then-append hoist landed). Nothing can
      be legitimately pending here: trials start at statement boundaries,
      where the suite builders have already flushed. }
    PyHoistHead := -1;
    { Re-READ the saved token rather than restoring a saved copy of CurTok:
      Next does SetLength(CurTok.SVal, ...) in place, so a record copy taken
      before the trial parse shares that buffer and comes back holding whatever
      token the trial stopped on (a compiler segfault, not a subtle wrong
      type). Tokens[] is the only trustworthy source. }
    TokPos := savedTok - 1;
    Next;
    Inc(rnd);
  until (not changed) or (rnd >= PY_INFER_ROUNDS);
end;

{ Type MODULE-level names by PARSING the module body, the same way
  PyCollectLocalsAST types a function's locals.

  The token-scanning version this replaces (PyCollectModuleLocals, and
  PyInferExprType under it) was the last of the eight scanners: a second
  implementation of expression typing that drifted from the parser which
  actually builds the call. It could not see a brace literal as a dict, a str
  method returning a class, or anything whose type came from a real overload.

  Why this could not be done until now: a module statement can call a def
  declared further down the file, and until PyRegisterDefShells there was no
  Proc to resolve against, so a trial parse would have failed on ordinary
  Python. With the signatures registered up front, the module body parses.

  The scan starts at the CURRENT cursor — the real parser is positioned just
  past the imports when this runs, which is exactly the module body — and
  skips `def` and `class` spans, since PyParseStatement cannot parse those and
  their bodies are not module scope anyway.

  Rolls back the AST, the symbols, the frame and BSSSize: a module-level
  AllocVar allocates a BSS global, so without the BSSSize restore every
  iteration would leak the whole module's globals again. }
procedure PyCollectModuleLocalsAST;
var rnd, i, si, depth, bodyIx, forJ, forCi: Integer;
    savedTok, savedAST, savedSC, savedCur, savedFS, savedBSS: Integer;
    changed, savedExprMode: Boolean;
    tk, w, forElemTk: TTypeKind;
    nm, forName: AnsiString;
    blockIsDef: array[0..255] of Boolean;   { blockIsDef[d] = body at depth d is a def/class, not if/for/while/with/try }
    pendingDefClass: Boolean;
    blkJ: Integer; blkTk: TTypeKind; blkName: AnsiString;
begin
  PyLocalCount := 0;
  rnd := 0;
  repeat
    changed := False;
    PyTypingChanged := False;
    savedTok := TokPos;
    savedAST := ASTNodeCount;
    savedCur := CurASTNode;
    savedSC := SymCount;
    savedFS := FrameSize;
    savedBSS := BSSSize;
    for i := 0 to PyLocalCount - 1 do
      if PyProgSym(PyLocals[i].Name) < 0 then
      begin
        si := AllocVar(PyLocals[i].Name, PyLocals[i].TypeKind);
        if (PyLocals[i].TypeKind = tyClass) and (PyLocals[i].RecCi >= 0) then
          Syms[si].RecName := REC_UCLASS_BASE + PyLocals[i].RecCi;
      end;
    PyTypingPass := True;
    { The real parser turns PyExprMode on only AFTER this pre-pass, but a
      trial parse needs it: without it `a and b` / `not x` take Pascal's
      precedence and `print(2 > 1 and 3 > 2)` fails to close its paren. }
    savedExprMode := PyExprMode;
    PyExprMode := True;
    i := savedTok - 1;
    depth := 0;
    pendingDefClass := False;
    blockIsDef[0] := False;
    while i < MainProgramTokCount do
    begin
      { Track, for the block about to be entered, whether its HEADER was
        `def`/`class` (a real new scope: names bound inside are NOT module
        globals) versus `if`/`for`/`while`/`with`/`try`/… (control flow only:
        Python has no block scope, so a name bound inside IS the same module
        global a statement after the block reads). Reset at every statement
        BOUNDARY so it reflects the line about to end, then pushed the
        moment its INDENT actually arrives — a one-line-ahead flag, not a
        parse of anything. }
      if (i = PyScanLo) or (Tokens[i - 1].Kind in [tkNewline, tkIndent, tkDedent, tkSemicolon]) then
        pendingDefClass := (Tokens[i].Kind = tkFunction) or (Tokens[i].Kind = tkClass);
      if Tokens[i].Kind = tkIndent then
      begin
        Inc(depth);
        if depth <= 255 then blockIsDef[depth] := pendingDefClass;
      end
      else if Tokens[i].Kind = tkDedent then Dec(depth)
      { No explicit skip for `def` / `class`: their bodies raise depth, and a
        def or class HEADER is not tkIdent-then-assign, so neither can match
        the statement tests below. Skipping them with PyFindBodyEnd instead
        cost an O(n) scan per construct — quadratic on a real file, and
        uforth.py went from an instant parse error to 107 seconds. }
      else if (depth > 0) and (depth <= 255) and (not blockIsDef[depth]) and
              (Tokens[i].Kind = tkIdent) and
              (i + 1 < MainProgramTokCount) and (Tokens[i + 1].Kind = tkAssign) and
              ((Tokens[i - 1].Kind in [tkNewline, tkIndent, tkDedent, tkSemicolon])) then
      begin
        { `if/for/while/with/try: ... name = <safe-shape>` — a name FIRST
          bound inside a control-flow block, read by a LATER top-level
          bare-name assignment's RHS
          (bug-nilpy-module-level-name-bound-in-a-block-is-invisible-to-a-
          later-assignment). The depth=0 branch below safely TRIAL-PARSES a
          bare assignment's RHS (PyParseStatement) to learn its type — unsafe
          to do here: this name's own block has not run for real yet, so
          referencing anything the pre-pass cannot ALSO see would call
          Error() and Halt the whole compile, the same landmine documented
          on the `for`-loop branch below. Only the same handful of SAFE,
          non-parsing shapes that branch already trusts: a literal, or a
          name already resolvable to a type. Anything else (a call —
          including the ticket's own motivating `json.load(f)`) is left
          alone; the deeper fix (a pre-pass that does not Halt on an
          as-yet-unseen name) is a separate, larger change. }
        blkName := GetTokenStr(i);
        blkJ := i + 2;
        blkTk := tyUnknown;
        if (blkJ < MainProgramTokCount) and (Tokens[blkJ].Kind = tkString) then
          blkTk := tyAnsiString
        else if (blkJ < MainProgramTokCount) and (Tokens[blkJ].Kind = tkInteger) then
          blkTk := tyInt64
        else if (blkJ < MainProgramTokCount) and
                (Tokens[blkJ].Kind in [tkLBrack, tkBegin]) then
          blkTk := tyVariant
        else if (blkJ < MainProgramTokCount) and (Tokens[blkJ].Kind = tkIdent) and
                (blkJ + 1 < MainProgramTokCount) and
                (Tokens[blkJ + 1].Kind in [tkNewline, tkDedent]) then
        begin
          if PyFindModuleConstraint(GetTokenStr(blkJ)) >= 0 then
            blkTk := tyVariant
          else if PyProgSym(GetTokenStr(blkJ)) >= 0 then
          begin
            si := PyProgSym(GetTokenStr(blkJ));
            if Syms[si].TypeKind in [tyString, tyAnsiString] then blkTk := tyAnsiString
            else blkTk := tyVariant;
          end;
        end;
        if blkTk <> tyUnknown then
        begin
          PyNoteLocalType(blkName, blkTk, REC_NONE);
          { Noting it only records it for the NEXT round's seeding loop (see
            the annotated-assignment branch's own note just below) -- a
            LATER statement in THIS SAME round's linear scan (`documents =
            payload + 1`, right after `payload`'s own block in the same
            file) trial-parses before that seeding ever runs, and died
            "undefined variable" before this. }
          if PyProgSym(blkName) < 0 then si := AllocVar(blkName, blkTk);
        end;
      end
      else if (depth = 0) and (Tokens[i].Kind = tkIdent) and
              (i + 3 < MainProgramTokCount) and (Tokens[i + 1].Kind = tkColon) then
      begin
        { ANNOTATED `name: T = expr`. The annotation is authoritative — it is
          in Python too — so it is read directly and the RHS is never parsed.
          That keeps annotation working as the ESCAPE HATCH for anything this
          pre-pass cannot yet resolve, which is the same role it had under the
          token scanner. }
        bodyIx := i + 2;
        tk := PyAnnTypeAt(bodyIx);
        if tk <> tyUnknown then
        begin
          if PyAnnLastCi >= 0 then
            PyNoteLocalType(GetTokenStr(i), tk, REC_UCLASS_BASE + PyAnnLastCi)
          else
            PyNoteLocalType(GetTokenStr(i), tk, REC_NONE);
          { …and put it in THIS round's scratch scope too. Noting it only
            records it for the NEXT round's seeding loop, so a later statement
            in the SAME round that trial-parses an expression mentioning the
            name died with "undefined variable" — and that error is fatal, so
            round 2 never ran. Every module-level assignment whose right-hand
            side read an annotated global failed that way, while `print(pe)`
            and `pe[k] = v` (which are not trial-parsed) were fine
            (bug-nilpy-annotated-module-global-invisible-in-kwarg). }
          if PyProgSym(GetTokenStr(i)) < 0 then
          begin
            si := AllocVar(GetTokenStr(i), tk);
            if PyAnnLastCi >= 0 then
              Syms[si].RecName := REC_UCLASS_BASE + PyAnnLastCi;
          end;
          while (bodyIx < MainProgramTokCount) and
                not (Tokens[bodyIx].Kind in [tkNewline, tkDedent]) do Inc(bodyIx);
          i := bodyIx;
          continue;
        end;
      end
      else if (depth = 0) and (Tokens[i].Kind = tkIdent) and
              (i + 1 < MainProgramTokCount) and (Tokens[i + 1].Kind = tkAssign) and
              { …and at a STATEMENT BOUNDARY. Parentheses do not change `depth`
                (only INDENT/DEDENT do), so a KEYWORD ARGUMENT spelled at the
                top level of a call — `menu.add_command(label="x",
                command=lambda: f())` — looked exactly like `command = <lambda>`
                and made a module local out of the keyword's NAME. Two such
                calls with different argument kinds then "widened" that
                phantom local from a procedure pointer to a variant and the
                file was rejected as too dynamic. }
              ((i = PyScanLo) or (Tokens[i - 1].Kind in [tkNewline, tkIndent,
                                                         tkDedent, tkSemicolon])) then
      begin
        { Only a BARE-NAME assignment is trial-parsed: it is the only form
          that declares a module local, and staying off the others keeps the
          pre-pass away from statements it cannot yet resolve — a module-level
          call to a class METHOD, whose Proc is not registered until
          PyParseClass reaches it. Hoisting class members the way def
          signatures are now hoisted is the remaining half of
          feature-n-nilpy-ast-typing-module-scope; until then such an
          assignment needs the annotated form above. }
        { A method call on a NAME used to be skipped here because class
          members were not registered until PyParseClass reached the class.
          The member pre-pass now hoists method signatures (PyMembersHoisted),
          so `x = c.two(1)` trial-parses and types x from the method's real
          return type — which is what lets `raw = a.mk(); zz = raw` resolve
          AND keeps raw's class identity (a tyVariant fallback mis-tagged a
          bytes result VT_INT64: bug-nilpy-method-result-copied-to-var-
          undefined). }
        TokPos := i;
        Next;
        PyParseStatement;
        i := TokPos - 1;      { the statement's terminating token }
        continue;
      end
      else if (depth = 0) and
              ((Tokens[i].Kind = tkFor) or
               ((Tokens[i].Kind = tkIdent) and CaseEqual(GetTokenStr(i), 'for'))) and
              { a STATEMENT BOUNDARY, exactly like the bare-assignment match
                above — a comprehension/generator's inline `for` (`next((c for
                c in cs if ...), ...)`) is the SAME token at depth 0 (parens
                do not change depth) but mid-expression, not a new statement. }
              ((i = PyScanLo) or (Tokens[i - 1].Kind in [tkNewline, tkIndent,
                                                         tkDedent, tkSemicolon])) and
              (i + 2 < MainProgramTokCount) and (Tokens[i + 1].Kind = tkIdent) and
              (Tokens[i + 2].Kind = tkIn) then
      begin
        { `for name in ITER:` at module level: fold the loop TARGET's element
          type into the SAME whole-program widening table a bare assignment
          feeds via PyNoteLocalType. Without this, a name already bound to a
          SCALAR elsewhere (`c = 5`) and later used as a for-TARGET over a
          STRING (or any element-typed container) never got that binding's
          type folded in — the flat scanner only recognises `name = expr`,
          and `for` is a different shape entirely. The real pass then created
          the name from its ONLY known assignment (the scalar one) and the
          loop stored a str/variant element into that fixed scalar slot
          (bug-nilpy-for-variable-reused-after-a-non-string-binding-iterates-garbage).

          Deliberately NOT a trial-parse of the statement (unlike the bare-
          assignment branch above): `Error` calls `Halt` directly, so a real
          PyParseStatement/PyParseForIn call here that referenced a name only
          a construct this scanner does not enter (`with`, `if`, `try`, a
          class body — anything but a bare assignment) would abort the WHOLE
          COMPILE the instant the pre-pass reached it, not just skip the one
          statement — hit immediately by `test_nilpy_file_open.npy`'s
          `with open(...) as f: lines = [...]` followed by `for ln in
          lines:`. So this only ever PEEKS at tokens and never calls into the
          parser: only the two cheap, safe-to-recognise iterable shapes get
          noted (a string literal, or a name already resolvable to a type);
          anything else — a call, a subscript, `d.items()`, a comprehension —
          is silently left alone, same as before this fix, and the real pass
          (which runs after every earlier statement has actually executed)
          sorts it out as it always did. Single-name targets only — a
          two-name target (dict.items()/enumerate/pair-unpack) is rarer for
          this specific conflict and stays unhandled rather than guessed at. }
        forName := GetTokenStr(i + 1);
        forJ := i + 3;
        forElemTk := tyUnknown;
        if (forJ < MainProgramTokCount) and (Tokens[forJ].Kind = tkString) then
          forElemTk := tyAnsiString
        else if (forJ < MainProgramTokCount) and
                (Tokens[forJ].Kind in [tkLBrack, tkBegin]) then
          forElemTk := tyVariant
        else if (forJ < MainProgramTokCount) and (Tokens[forJ].Kind = tkIdent) and
                (forJ + 1 < MainProgramTokCount) and
                (Tokens[forJ + 1].Kind in [tkColon, tkNewline]) then
        begin
          forCi := PyFindModuleConstraint(GetTokenStr(forJ));
          if forCi >= 0 then
          begin
            if PyModuleLocals[forCi].TypeKind in [tyString, tyAnsiString] then
              forElemTk := tyAnsiString
            else
              forElemTk := tyVariant;
          end
          else if PyProgSym(GetTokenStr(forJ)) >= 0 then
          begin
            si := PyProgSym(GetTokenStr(forJ));
            if Syms[si].TypeKind in [tyString, tyAnsiString] then
              forElemTk := tyAnsiString
            else
              forElemTk := tyVariant;
          end;
        end;
        if forElemTk <> tyUnknown then PyNoteLocalType(forName, forElemTk, REC_NONE);
      end;
      Inc(i);
    end;
    PyTypingPass := False;
    PyExprMode := savedExprMode;
    if PyTypingChanged then changed := True;
    for i := savedSC to SymCount - 1 do
    begin
      nm := Syms[i].Name;
      if nm = '' then Continue;
      tk := Syms[i].TypeKind;
      si := PyFindConstraint(nm);
      if si < 0 then
      begin
        if PyLocalCount >= PY_MAX_LOCALS then
          Error('Nil Python: too many inferred module locals');
        PyLocals[PyLocalCount].Name := nm;
        PyLocals[PyLocalCount].TypeKind := tk;
        if Syms[i].RecName >= REC_UCLASS_BASE then
          PyLocals[PyLocalCount].RecCi := Syms[i].RecName - REC_UCLASS_BASE
        else
          PyLocals[PyLocalCount].RecCi := -1;
        Inc(PyLocalCount);
        changed := True;
      end
      else
      begin
        w := PyWiden(PyLocals[si].TypeKind, tk);
        if w <> PyLocals[si].TypeKind then
        begin
          PyLocals[si].TypeKind := w;
          changed := True;
        end;
        { NOT guarded on RecCi already being SET (the original form of this
          rule): a name reassigned across ROUNDS to a call returning a
          DIFFERENT class kept its FIRST round's class identity forever, so
          `with open(p,"w") as f: ...` then a later plain `f = open(p, "r")`
          left f dispatching as a TPyFile while it now held a TPyList --
          .readlines() / len() read the wrong class's layout and printed the
          RTTI blob (the same disclosure shape as
          bug-nilpy-file-write-drops-data-and-read-to-print-dumps-rtti-memory,
          via a different trigger than that ticket's write() overload). Take
          the latest resolved class whenever it differs. }
        if (Syms[i].RecName >= REC_UCLASS_BASE) and
           (PyLocals[si].RecCi <> Syms[i].RecName - REC_UCLASS_BASE) then
        begin
          PyLocals[si].RecCi := Syms[i].RecName - REC_UCLASS_BASE;
          changed := True;
        end;
      end;
    end;
    SymRollbackTo(savedSC);
    ASTNodeCount := savedAST;
    FrameSize := savedFS;
    BSSSize := savedBSS;
    CurASTNode := savedCur;
    PyHoistHead := -1;   { discard trial-queued hoists — see PyCollectLocalsAST }
    TokPos := savedTok - 1;
    Next;
    Inc(rnd);
  until (not changed) or (rnd >= PY_INFER_ROUNDS);
  PyModuleLocalCount := PyLocalCount;
  for i := 0 to PyLocalCount - 1 do
    PyModuleLocals[i] := PyLocals[i];
end;

{ Parse one `def` header into the PyHdr* globals, leaving the cursor just
  past the `:` NEWLINE INDENT that opens the body. The single implementation
  of the header grammar — see the PyHdr* declaration for why that matters. }
function PyInferDefRetType(methodStart: Integer; var retRec: Integer): TTypeKind; forward; { defined with the pre-pass helpers below }
function PyDefHasValueReturn(defIdx: Integer): Boolean; forward; { lying `-> None` detector (with the pre-pass helpers) }

function PyDefUsedAsValue(const nm: AnsiString): Boolean;
{ True iff the module mentions `nm` as a VALUE (a bare name that is not being
  called and is not the `def` line or an attribute) — i.e. the routine is
  passed around as a function object, typically into a `Callable[...]`
  parameter.

  An IMPORT statement does not count. `from m import run2` names the def with a
  bare identifier, which used to make every def an imported module exports take
  the function-object ABI — variant result AND every parameter boxed. For most
  parameter types that is only wasteful; for a `Callable[...]` parameter it is
  fatal, since the callee then holds a variant (by reference) where the caller
  passed a function VALUE and `call_ind` jumped to the variant's tag word
  (bug-nilpy-import-name-forces-function-object-abi). The scan is NOT narrowed
  to the current unit instead: a def defined in a module and passed as a value
  by the main program is the genuine case, and that lives outside PyScanLo.

  Such a def must use the one ABI every Callable signature marshals against.
  A `Callable[..., R]` cannot know which def it will receive, so both sides are
  normalised to the VARIANT (hidden-destination) result convention here and in
  PyAnnTypeAt's 'callable' branch. Without that, a def whose body infers a
  variant result (`return d.get(k, [])`) handed to a `Callable[[str], list[str]]`
  parameter returned through the hidden-destination convention while the
  indirect call site expected a register result — the callee then wrote its
  variant through whatever the caller happened to leave in the destination
  register. See bug-nilpy-callable-return-abi-mismatch. }
var j: Integer;
    atStmtStart, inImport: Boolean;
begin
  Result := False;
  j := 0;
  atStmtStart := True;
  inImport := False;
  while j < MainProgramTokCount do
  begin
    if Tokens[j].Kind in [tkNewline, tkIndent, tkDedent, tkSemicolon] then
    begin
      atStmtStart := True;
      inImport := False;
    end
    else if atStmtStart then
    begin
      inImport := (Tokens[j].Kind = tkUses) or
                  ((Tokens[j].Kind = tkIdent) and CaseEqual(GetTokenStr(j), 'from'));
      atStmtStart := False;
    end;
    if (not inImport) and
       (Tokens[j].Kind = tkIdent) and CaseEqual(GetTokenStr(j), nm) then
    begin
      if not (((j + 1 < MainProgramTokCount) and (Tokens[j + 1].Kind = tkLParen)) or
              ((j > 0) and (Tokens[j - 1].Kind = tkDot)) or
              ((j > 0) and (Tokens[j - 1].Kind = tkFunction))) then
      begin
        Result := True;
        Exit;
      end;
    end;
    Inc(j);
  end;
end;

procedure PyParseDefHeader;
var annIdx, hdrDefIdx, hdrRetRec, starCi: Integer;
    isKwParam: Boolean;
begin
  if CurTok.Kind <> tkFunction then Error('Nil Python: expected def');
  hdrDefIdx := TokPos - 1;          { the `def` token, for return inference }
  Next;
  if CurTok.Kind <> tkIdent then Error('Nil Python: expected function name');
  PyHdrName := CurTok.SVal;
  Next;
  Expect(tkLParen, '(');
  PyHdrNParams := 0;
  PyHdrStarIdx := -1;
  PyHdrKwIdx := -1;
  while CurTok.Kind <> tkRParen do
  begin
    if PyHdrNParams >= 32 then Error('Nil Python: too many parameters');
    { A bare `*` marks the parameters after it keyword-only (PEP 3102). It is a
      MARKER, not a parameter: consumed and dropped, so the ones after it are
      ordinary parameters here. The DIFFERENCE from CPython is laxity — a
      keyword-only parameter can also be passed positionally in NilPy, which
      accepts programs CPython would reject but runs every program it accepts
      the same way. songformatter's analyze_key(chords, *, chord_to_notes=...)
      is the shape that needs it. `*args` / `**kwargs` proper are
      feature-nilpy-star-args-kwargs. }
    if (CurTok.Kind = tkStar) and (TokPos < TokCount) and
       (Tokens[TokPos].Kind = tkComma) then
    begin
      Next;              { the '*' }
      Next;              { the ',' }
      Continue;
    end;
    { `*args` / `**kwargs` — the COLLECTION side (feature-nilpy-star-args-kwargs
      rung 1). The callee is ordinary: `*args` is ONE TPyList parameter and
      `**kwargs` ONE TPyDict, so the body indexes, iterates and len()s them with
      the machinery lists and dicts already have. Each CALL site packs its
      surplus positional arguments into the list and its unmatched keyword
      arguments into the dict — see PyPackStarArgs. `**` reaches here as two
      tkStar tokens, since the NilPy lexer has no `**` token. }
    if CurTok.Kind = tkStar then
    begin
      Next;                                   { the '*' }
      isKwParam := CurTok.Kind = tkStar;
      if isKwParam then Next;                 { the second '*' of `**` }
      if CurTok.Kind <> tkIdent then
        Error('Nil Python: expected a name after * in the parameter list');
      if (isKwParam and (PyHdrKwIdx >= 0)) or ((not isKwParam) and (PyHdrStarIdx >= 0)) then
        Error('Nil Python: ' + PyHdrName + '() has more than one * parameter of the same kind');
      PyHdrPNames[PyHdrNParams] := CurTok.SVal;
      Next;
      { `*args: str` annotates the ELEMENT type; the parameter itself is still a
        list, so the annotation is parsed (to consume it) and dropped. }
      if CurTok.Kind = tkColon then
      begin
        annIdx := TokPos - 1;
        PyAnnTypeAt(annIdx);
        TokPos := annIdx;
        Next;
      end;
      if isKwParam then starCi := FindUClass('TPyDict')
      else starCi := FindUClass('TPyList');
      if starCi < 0 then Error('Nil Python: pylib (TPyList/TPyDict) not loaded');
      PyHdrPTypes[PyHdrNParams] := tyClass;
      PyHdrPCis[PyHdrNParams] := starCi;
      PyHdrPSigs[PyHdrNParams] := -1;
      PyHdrDefHas[PyHdrNParams] := False;
      if isKwParam then PyHdrKwIdx := PyHdrNParams
      else PyHdrStarIdx := PyHdrNParams;
      Inc(PyHdrNParams);
      if not Eat(tkComma) then break;
      Continue;
    end;
    if CurTok.Kind <> tkIdent then Error('Nil Python: expected parameter name');
    PyHdrPNames[PyHdrNParams] := CurTok.SVal;
    Next;
    if CurTok.Kind <> tkColon then
    begin
      { UNANNOTATED parameter — Python does not require a type. Defaults to Any
        (variant), the same fallback an unannotated local gets. uforth's native
        word bodies are all `def w(vm):`. }
      PyHdrPTypes[PyHdrNParams] := tyVariant;
      PyHdrPCis[PyHdrNParams] := -1;
      PyHdrPSigs[PyHdrNParams] := -1;
    end
    else
    begin
      Expect(tkColon, ':');
      { same full annotation grammar as a method parameter }
      annIdx := TokPos - 1;
      PyHdrPTypes[PyHdrNParams] := PyAnnTypeAt(annIdx);
      PyHdrPCis[PyHdrNParams] := PyAnnLastCi;
      PyHdrPSigs[PyHdrNParams] := PyAnnLastProcSig;
      if PyHdrPTypes[PyHdrNParams] = tyUnknown then
        ErrorAt(Tokens[annIdx].Line,
                'Nil Python: parameter ' + PyHdrPNames[PyHdrNParams]
                + ' has an unsupported type annotation');
      TokPos := annIdx;
      Next;
    end;
    PyHdrDefHas[PyHdrNParams] := False;
    if CurTok.Kind = tkAssign then
    begin
      annIdx := TokPos;
      PyHdrDefHas[PyHdrNParams] := True;
      PyHdrDefVal[PyHdrNParams] :=
        PyParamDefaultAt(annIdx, PyHdrPNames[PyHdrNParams],
                         PyHdrDefIsStr[PyHdrNParams],
                         PyHdrDefSOff[PyHdrNParams],
                         PyHdrDefSLen[PyHdrNParams]);
      PyHdrDefIsNone[PyHdrNParams] := PyDefaultWasNone;
      PyHdrDefIsFloat[PyHdrNParams] := PyDefaultWasFloat;
      TokPos := annIdx;
      Next;
    end;
    Inc(PyHdrNParams);
    if not Eat(tkComma) then break;
  end;
  Expect(tkRParen, ')');
  PyHdrRetCi := -1;
  if CurTok.Kind <> tkMinus then
  begin
    { NO return annotation. Python does not require one, and 15 of uforth's
      defs omit it. Registered exactly as the member PRE-PASS already does for
      this case (PyMethodRetType yields tyUnknown, which it maps to tyInteger)
      — the two MUST agree, since the pre-pass decides the signature and this
      decides the frame, and a disagreement is a silent ABI mismatch. Kept a
      FUNCTION rather than a proc so `return <value>` still has a Result. }
    PyHdrIsProc := False;
    PyHdrRetType := PyInferDefRetType(hdrDefIdx, hdrRetRec);
    if PyHdrRetType = tyClass then
      PyHdrRetCi := hdrRetRec - REC_UCLASS_BASE;
  end
  else
  begin
    Expect(tkMinus, '- in ->');
    Expect(tkGt, '> in ->');
    { `-> None` declares a procedure (no Result) — UNLESS the body returns a
      value anyway (CPython ignores annotations; uforth's finalize_definition
      lies). Then the annotation loses and the type is inferred, or the caller
      reads a discarded Result as garbage. }
    PyHdrIsProc := CurTok.Kind = tkNil;
    if PyHdrIsProc and PyDefHasValueReturn(hdrDefIdx) then
    begin
      PyHdrIsProc := False;
      Next;   { the None }
      PyHdrRetType := PyInferDefRetType(hdrDefIdx, hdrRetRec);
      if PyHdrRetType = tyClass then
        PyHdrRetCi := hdrRetRec - REC_UCLASS_BASE;
    end
    else if PyHdrIsProc then begin PyHdrRetType := tyInteger; Next; end
    else
    begin
      PyAnnRetScope := True;
      PyHdrRetType := PyParseType;
      PyAnnRetScope := False;
      PyHdrRetCi := PyLastTypeCi;
    end;
  end;
  { `-> str` is an unbounded Python string, so the Result var is MANAGED — the
    method path has mapped it this way all along, and a def returning a string
    built past 255 characters truncated silently without it
    (bug-nilpy-string-local-truncates-at-255). }
  if PyHdrRetType = tyString then PyHdrRetType := tyAnsiString;
  { A def that is also used as a VALUE returns through the function-object ABI
    (see PyDefUsedAsValue): variant result, so every `Callable[...]` call site
    marshals the same way whichever def it received. A procedure stays a
    procedure — there is no result to disagree about. }
  if PyDefUsedAsValue(PyHdrName) then
  begin
    if (not PyHdrIsProc) and (PyHdrRetType <> tyVariant) then
    begin
      PyHdrRetType := tyVariant;
      PyHdrRetCi := -1;
    end;
    { ...and its parameters, for the same reason (see PyAnnTypeAt's 'callable'
      branch). `*args` / `**kwargs` are already packed containers and keep their
      own types. }
    for hdrRetRec := 0 to PyHdrNParams - 1 do
      if (hdrRetRec <> PyHdrStarIdx) and (hdrRetRec <> PyHdrKwIdx) then
      begin
        PyHdrPTypes[hdrRetRec] := tyVariant;
        PyHdrPCis[hdrRetRec] := -1;
      end;
  end;
  Expect(tkColon, ':');
  Expect(tkNewline, 'newline');
  Expect(tkIndent, 'indent');
end;

{ Copy the parsed header's defaults and result class onto a registered Proc. }
procedure PyApplyDefSignature(procIdx: Integer);
var i: Integer;
begin
  { A class-returning def must record WHICH class, or the call site has a
    tyClass value with no identity and a later field access reads the object
    POINTER (test_nilpy_class_return). }
  if (PyHdrRetType = tyClass) and (PyHdrRetCi >= 0) then
    ProcRetRecId[procIdx] := REC_UCLASS_BASE + PyHdrRetCi;
  { which parameter is `*args` / `**kwargs`, for the call-site packing. The rec
    id is recorded too: a param symbol is reused once the callee's scope closes,
    so overload matching reads the class from ProcParamRecId. }
  ProcPyStarIdx[procIdx] := PyHdrStarIdx;
  ProcPyKwIdx[procIdx] := PyHdrKwIdx;
  if (PyHdrStarIdx >= 0) and (PyHdrStarIdx < MAX_PROC_PARAMS) then
    ProcParamRecId[procIdx * MAX_PROC_PARAMS + PyHdrStarIdx] :=
      REC_UCLASS_BASE + PyHdrPCis[PyHdrStarIdx];
  if (PyHdrKwIdx >= 0) and (PyHdrKwIdx < MAX_PROC_PARAMS) then
    ProcParamRecId[procIdx * MAX_PROC_PARAMS + PyHdrKwIdx] :=
      REC_UCLASS_BASE + PyHdrPCis[PyHdrKwIdx];
  for i := 0 to PyHdrNParams - 1 do
    if PyHdrDefHas[i] and (i < MAX_PROC_PARAMS) then
    begin
      ProcParamHasDefault[procIdx * MAX_PROC_PARAMS + i] := True;
      ProcParamDefaultVal[procIdx * MAX_PROC_PARAMS + i] := PyHdrDefVal[i];
      ProcParamDefaultIsStr[procIdx * MAX_PROC_PARAMS + i] := PyHdrDefIsStr[i];
      ProcParamDefaultIsNone[procIdx * MAX_PROC_PARAMS + i] := PyHdrDefIsNone[i];
      ProcParamDefaultIsFloat[procIdx * MAX_PROC_PARAMS + i] := PyHdrDefIsFloat[i];
      ProcParamDefaultSOff[procIdx * MAX_PROC_PARAMS + i] := PyHdrDefSOff[i];
      ProcParamDefaultSLen[procIdx * MAX_PROC_PARAMS + i] := PyHdrDefSLen[i];
    end;
end;

{ Register every TOP-LEVEL def's SIGNATURE before anything is typed or
  compiled.

  PyDefReturnType used to answer "what does this def return?" with its own
  token scan, because module-local inference runs before any def body is
  parsed and therefore before any Proc exists. That is the same parse-it-twice
  drift the local-typing pre-pass had, and it only ever recovered the return
  TYPE — not the result class, not the parameter defaults, not the signature
  for a forward call.

  Parse each header ONCE here instead, with the real header parser, and
  register the Proc. From then on inference and codegen both just call
  FindProc. Bodies are skipped by span, so this emits no code and allocates no
  symbols. }
procedure PyRegisterDefShells;
var savedTok, i, depth, procIdx, savedHoist: Integer;
begin
  savedTok := TokPos;
  { This pass parses HEADERS ONLY, but a header can queue a hoisted setup
    statement (a default's value, an inferred return's trial parse), and the
    hoist queue is global. Left queued, that node was flushed into whatever
    statement came next — in a MODULE, after the symbols it names had been
    rolled back, which the IR verifier then rejected at the module's last line
    with nothing there to explain it. Nothing this pass queues is wanted: it
    emits no code and the real parse builds its own. }
  savedHoist := PyHoistHead;
  i := PyScanLo;
  depth := 0;
  while i < MainProgramTokCount do
  begin
    if Tokens[i].Kind = tkIndent then Inc(depth)
    else if Tokens[i].Kind = tkDedent then Dec(depth)
    else if (depth = 0) and (Tokens[i].Kind = tkFunction) then
    begin
      TokPos := i;
      Next;                      { CurTok = 'def' }
      PyParseDefHeader;
      if FindProc(PyHdrName) < 0 then
      begin
        procIdx := RegisterProc(PyHdrName, not PyHdrIsProc, PyHdrRetType,
                                PyHdrNParams, PyHdrPNames, PyHdrPTypes);
        PyApplyDefSignature(procIdx);
      end;
      { Resume at the body's INDENT, not past it. After PyParseDefHeader the
        cursor sits on the first BODY token, so TokPos-2 is the INDENT and the
        loop's own Inc(i) must land ON it — resuming at TokPos-2 skipped it,
        depth never rose, and every method inside a later class then looked
        top-level (a `self` parameter with no annotation, reported as a stray
        token 40 lines away). }
      i := TokPos - 3;
    end;
    Inc(i);
  end;
  PyHoistHead := savedHoist;
  { Re-READ the saved token rather than restoring a copy of CurTok: Next
    rewrites CurTok.SVal in place
    (project_curtok_record_copy_shares_sval_landmine). }
  TokPos := savedTok - 1;
  Next;
end;

{ Compile a LIFTED lambda's body: the queued proc's frame, then one
  `return <expr>` parsed from the body's token span. Mirrors PyParseDef's body
  half — a lambda has no statements, no locals and no nested defs, so what is
  left is the prologue, the expression, and the epilogue.
  (feature-nilpy-lambda-compiled-closure) }
procedure PyCompileLambdaBody(procIdx, bStart, realProcIdx: Integer);
var i, idx, patchPos, savedSC, savedFS, nparams, node, seqNode, exitNode,
    wArgSeq, wArgLast, wArgNode, wIdentNode, wCallNode: Integer;
    savedExprMode: Boolean;
begin
  { NilPy expression rules must be ON while this body parses — the module-level
    drain runs after ParsePyProgram turned them off, and without them a `.name`
    read off a VARIANT parameter fell through to a raw field read at offset 0
    (it printed the variant's TYPE TAG instead of the attribute). }
  savedExprMode := PyExprMode;
  PyExprMode := True;
  nparams := Procs[procIdx].ParamCount;
  savedSC := SymCount;
  savedFS := FrameSize;
  FrameSize := 0;
  CurProc := procIdx;
  Procs[procIdx].ScopeBase := SymCount;
  for i := 0 to nparams - 1 do
  begin
    idx := AllocParam(Procs[procIdx].Params[i].Name, Procs[procIdx].Params[i].TypeKind,
                      Procs[procIdx].Params[i].TypeKind = tyVariant, False);
    Procs[procIdx].Params[i].SymIdx := idx;
    Procs[procIdx].Params[i].IsRef := Procs[procIdx].Params[i].TypeKind = tyVariant;
    if i < MAX_PROC_PARAMS then
      ProcParamIsConst[procIdx * MAX_PROC_PARAMS + i] :=
        Procs[procIdx].Params[i].TypeKind = tyVariant;
    { AllocParam seeds RecName from LastTypeRecId — the type the parser last
      saw ANYWHERE — and this body is compiled far from its own header, so the
      leftover made every variant param look like a class instance and
      `event.width` reported "no such member" instead of reading a dynamic
      attribute. Set the class identity explicitly, or clear it. }
    if (Procs[procIdx].Params[i].TypeKind = tyClass) and (i < MAX_PROC_PARAMS) and
       (ProcParamRecId[procIdx * MAX_PROC_PARAMS + i] >= REC_UCLASS_BASE) then
      Syms[idx].RecName := ProcParamRecId[procIdx * MAX_PROC_PARAMS + i]
    else
      Syms[idx].RecName := REC_NONE;
  end;
  { A lifted lambda RETURNS a variant, because every bridge that invokes one
    (pyboundfn_call_ptr, pyvar_callv*) declares the callee that way — a Variant
    result rides a hidden destination the caller allocates AND comes back as a
    pointer in the result register. Compiled as a procedure, that register held
    whatever the body's last call left there, and the caller's `rv := f(...)`
    dereferenced it: `lambda x: body()` crashed the moment the def it called
    took no arguments, and survived by luck when it took one. The Result slot is
    zero-initialised, so a lambda whose value nobody reads yields None. }
  if Procs[procIdx].RetType = tyVariant then
  begin
    idx := AllocVar('$pyresult', tyVariant);
    Procs[procIdx].RetSymIdx := idx;
    Syms[idx].Kind := skLocal;       { gates the prologue zero-init }
    if RetViaHiddenDest(tyVariant) then
    begin
      idx := AllocVar('', tyPointer);
      ProcAggregateDestSym[procIdx] := idx;
    end;
  end;
  Procs[procIdx].BodyAddr := CodeLen;
  patchPos := EmitProcPrologue;
  Procs[procIdx].FramePatch := patchPos;
  { Stash the hidden destination pointer the caller passed for the Variant
    result. Every other NilPy body path emits this; the lambda path did not, so
    the epilogue's 16-byte result copy went to whatever stale stack bytes sat in
    the dest slot. The text segment is writable, so on the first call that
    garbage happened to be a RETURN ADDRESS and the copy zeroed 16 bytes of the
    runtime's own code (pynone's); the program then died on the NEXT call into
    the clobbered routine, arbitrarily far from here — which is why this read as
    "a lambda crashes the second time it runs"
    (bug-nilpy-nested-def-capture-sets-are-not-final, face 2). }
  EmitAggregateDestStash(procIdx);
  PyEmitParamSpills(procIdx, nparams);
  PyInitVariantLocals(Procs[procIdx].ScopeBase);
  EmitManagedLocalsZeroInit(Procs[procIdx].ScopeBase);
  if bStart = -1 then
  begin
    { A CALLABLE-VALUE WRAPPER (feature-nilpy-callable-value-unified-dispatch):
      no source span to parse -- hand-build `return REALPROC(a0, a1, ...)`,
      one AN_IDENT per own Variant parameter feeding the real proc's call
      exactly the way a genuine `return realproc(a0)` would parse, so the
      ordinary argument/return coercion (Variant param -> the real proc's
      actual param type, and back) applies unchanged. }
    wArgSeq := -1; wArgLast := -1;
    for i := 0 to nparams - 1 do
    begin
      wIdentNode := AllocNode(AN_IDENT);
      ASTIVal[wIdentNode] := Procs[procIdx].Params[i].SymIdx;
      ASTTk[wIdentNode] := Ord(tyVariant);
      wArgNode := AllocNode(AN_ARG);
      ASTLeft[wArgNode] := wIdentNode; ASTRight[wArgNode] := -1;
      if wArgLast < 0 then wArgSeq := wArgNode else ASTRight[wArgLast] := wArgNode;
      wArgLast := wArgNode;
    end;
    wCallNode := AllocNode(AN_CALL);
    ASTIVal[wCallNode] := realProcIdx;
    ASTTk[wCallNode] := Ord(Procs[realProcIdx].RetType);
    ASTRight[wCallNode] := ProcRetRecId[realProcIdx];
    ASTLeft[wCallNode] := wArgSeq;
    CurASTNode := wCallNode;
  end
  else
  begin
    TokPos := bStart;
    Next;
    PyParseBoolExpr;
  end;
  { the expression IS the whole lambda body, so its VALUE is what the lambda
    evaluates to -- wrap it in a real AN_EXIT (exactly what a written
    `return <expr>` produces) so it stores into $pyresult through the SAME
    coercion CompileAST already gives every other `return`, rather than being
    evaluated for its side effect alone and thrown away. Before this, ANY
    lifted lambda whose value was actually read back answered None
    unconditionally -- `h = lambda s: len(s); h("abcde")` -- since nothing
    ever wrote $pyresult; only a lambda used purely for its side effect (the
    shape the lifter was first built for) happened to look correct.

    EXCLUDES a tyClass/tyRecord result: `lambda s: log.append(s)` (append
    returns Self) boxed into $pyresult and released by a caller that discards
    it drove the SAME captured `log` to refcount 0 and freed it out from under
    the enclosing scope that still owned it (traced with -dPXX_OBJTRACE: 4
    retains/5 releases where the scalar/string case balances at 2/2) --
    an aliased captured object's ownership around the bound-fn bridge is not
    accounted for correctly here, and is the ARC gap
    bug-nilpy-bound-fn-closure-objects-are-never-freed already tracks. Keep
    the old discard-only behaviour for that shape rather than risk it; every
    scalar and managed-STRING result (checked with -dPXX_OBJTRACE too, and
    balances) is fixed.
    bug-nilpy-lifted-lambda-discards-its-return-value }
  if IntToTypeKind(ASTTk[CurASTNode]) in [tyClass, tyRecord] then
    node := CurASTNode
  else
  begin
    exitNode := AllocNode(AN_EXIT);
    ASTLeft[exitNode] := CurASTNode;
    node := exitNode;
  end;
  { any temporaries the expression hoisted must be emitted before it, and
    CompileAST wants a BLOCK the way every other body path hands it one }
  node := PySeqAppend(PyFlushHoist(-1), node);
  seqNode := AllocNode(AN_BLOCK);
  ASTLeft[seqNode] := node;
  ASTTk[seqNode] := Ord(tyUnknown);
  CompileAST(seqNode);
  EmitProcEpilog(Procs[procIdx].RetSymIdx);
  PatchProcPrologue(patchPos, FrameSize);
    ProcBodyEnd[procIdx] := CodeLen;   { DWARF -g — see PyParseDef's note }
  ProcDbgMain[procIdx] := DbgTokIsDebuggable(TokPos);
  if DebugInfo and ProcDbgMain[procIdx] then DbgCaptureProcLocals(procIdx);
  SymRollbackTo(savedSC);
  FrameSize := savedFS;
  CurProc := -1;
  PyExprMode := savedExprMode;
end;

{ Drain the lambda bodies queued while compiling the routine that just ended,
  back to the mark it took on entry — the same discipline the nested-def queue
  follows, and for the same reason: a lambda inside a lifted lambda would queue
  onto this list too. }
procedure PyDrainPendingLambdas(mark: Integer);
var savedTok: Integer;
begin
  while PyPendLamCount > mark do
  begin
    Dec(PyPendLamCount);
    savedTok := TokPos;
    PyCompileLambdaBody(PyPendLamProc[PyPendLamCount], PyPendLamTok[PyPendLamCount],
                        PyPendLamWrapReal[PyPendLamCount]);
    TokPos := savedTok - 1;
    Next;
  end;
end;

procedure PyParseDef;
var name, savedPfx, savedPfx2: AnsiString;
    nparams, i, procIdx, idx, savedSC, savedFS, patchPos, bodyStart, bodyNode: Integer;
    savedNest, savedTok, savedLam, savedHoist: Integer;
    retType: TTypeKind; isProc, capByRef: Boolean;
begin
  savedHoist := PyHoistHead;
  PyParseDefHeader;
  name := PyHdrName;
  nparams := PyHdrNParams;
  isProc := PyHdrIsProc;
  retType := PyHdrRetType;
  bodyStart := TokPos - 1;

  { Reuse the shell PyRegisterDefShells registered for this def. A shell has
    BodyAddr = -1; anything else means the name is being DEFINED AGAIN, which
    Python allows, so that gets its own Proc rather than overwriting the first
    one's body address out from under earlier callers -- UNLESS the new def
    has the SAME arity as the existing one (below), in which case it is the
    SAME name bound to a new value (Python has no function declarations, only
    assignments), and it must WIN: FindProc's hash chain returns the OLDEST
    registration for a name, so a second same-arity Proc is one no call site
    can ever reach, and every call kept running the FIRST body forever
    (bug-nilpy-redefining-a-def-is-ignored-the-first-body-still-runs). A
    DIFFERENT arity is left to the existing path (its own Proc): that shape
    already resolves correctly today, by whatever call-site arity matching
    picks it out from the chain, and must keep working. }
  { A NESTED def registers under its enclosing def's qualifier, which is what
    PyParseStatement already put in the queue entry — see PyNestPrefix. }
  if PyNestPrefix <> '' then name := PyNestPrefix + '.' + name;
  procIdx := FindProc(name);
  if (procIdx >= 0) and (Procs[procIdx].BodyAddr >= 0) and
     (Procs[procIdx].ParamCount = nparams) then
  begin
    for i := 0 to nparams - 1 do
    begin
      Procs[procIdx].Params[i].Name := PyHdrPNames[i];
      Procs[procIdx].Params[i].TypeKind := PyHdrPTypes[i];
    end;
    Procs[procIdx].RetType := retType;
    Procs[procIdx].IsFunc := not isProc;
    PyApplyDefSignature(procIdx);
  end
  else if (procIdx < 0) or (Procs[procIdx].BodyAddr >= 0) then
  begin
    procIdx := RegisterProc(name, not isProc, retType, nparams,
                            PyHdrPNames, PyHdrPTypes);
    PyApplyDefSignature(procIdx);
  end;
  { The BODY must build the frame the registered SIGNATURE describes, not what
    a second inference pass makes of the same header. The two can disagree: the
    shell pass runs before any def is compiled, so a return expression it cannot
    type comes back dynamic, while the same expression re-inferred here may type
    concretely. Callers use the signature. When they disagreed, a variant-
    returning def got NO hidden destination slot (`RetViaHiddenDest(retType)`
    below tested the re-inferred type) and wrote its result through an
    uninitialised pointer — `def s(a, b=2): return a + b` segfaulted ON RETURN,
    and only when a parameter carried a default, which is what made it look like
    a defaults bug. }
  if Procs[procIdx].BodyAddr < 0 then retType := Procs[procIdx].RetType;

  { A nested def's shell carries MORE parameters than its header: the trailing
    ones stand for the enclosing locals it captures. Take the count from the
    Proc, or the captured names get no frame slot and the body reports them as
    undefined variables (feature-nilpy-nested-defs). }
  if Procs[procIdx].ParamCount > nparams then
  begin
    for i := nparams to Procs[procIdx].ParamCount - 1 do
    begin
      PyHdrPNames[i] := Procs[procIdx].Params[i].Name;
      PyHdrPTypes[i] := Procs[procIdx].Params[i].TypeKind;
      { restore a captured object's class id (stashed at capture time) so
        `obj.field` resolves inside the body — else it reads as Integer }
      if (Procs[procIdx].Params[i].TypeKind = tyClass) and
         (i < MAX_PROC_PARAMS) and
         (ProcParamRecId[procIdx * MAX_PROC_PARAMS + i] >= REC_UCLASS_BASE) then
        PyHdrPCis[i] := ProcParamRecId[procIdx * MAX_PROC_PARAMS + i] - REC_UCLASS_BASE
      else
        PyHdrPCis[i] := -1;
      PyHdrPSigs[i] := -1;
    end;
    nparams := Procs[procIdx].ParamCount;
  end;
  { NOTE: BodyAddr is recorded at the PROLOGUE below, not here. Between this
    point and the prologue sits the local-typing pre-pass, which trial-parses
    the body — and a body containing an `import` compiles that unit right
    there, emitting the whole unit's code into the gap. A BodyAddr taken here
    then pointed at the imported unit's first routine instead of this def:
    calling `def w(): try: import math ...` ran math's code and returned its
    pi, with the def's own body never entered and no diagnostic
    (bug-nilpy-import-inside-def-clobbers-proc-context). }
  { Defs nested in THIS body qualify with this def's own (already qualified)
    name, so `outer.inner.deeper` stays unique at any depth. Set BEFORE the
    local-typing pre-pass: that pre-pass trial-parses the body, so it meets the
    nested defs too and must register their shells under the same qualifier the
    real parse will look for. }
  savedPfx := PyNestPrefix;
  savedNest := PyPendNestCount;
  savedLam := PyPendLamCount;
  PyNestPrefix := name;
  savedSC := SymCount;
  savedFS := FrameSize;
  FrameSize := 0;
  CurProc := procIdx;
  Procs[procIdx].ScopeBase := SymCount;
  for i := 0 to nparams - 1 do
  begin
    { Any/variant params are const-by-ref (the internal convention passes a
      variant's ADDRESS), so the 8-byte slot holds the pointer }
    { a `nonlocal` capture is by-ref whatever its type — see ProcParamCapRef }
    capByRef := (PyHdrPTypes[i] = tyVariant) or
                ((i < MAX_PROC_PARAMS) and
                 ProcParamCapRef[procIdx * MAX_PROC_PARAMS + i]);
    idx := AllocParam(PyHdrPNames[i], PyHdrPTypes[i], capByRef, False);
    Procs[procIdx].Params[i].SymIdx := idx;
    Procs[procIdx].Params[i].IsRef := capByRef;
    if i < MAX_PROC_PARAMS then
      ProcParamIsConst[procIdx * MAX_PROC_PARAMS + i] := PyHdrPTypes[i] = tyVariant;
    if (PyHdrPTypes[i] = tyClass) and (PyHdrPCis[i] >= 0) then
      Syms[idx].RecName := REC_UCLASS_BASE + PyHdrPCis[i];
    { A `Callable[...]` parameter is callable INSIDE the body, and its bare name
      at a CALL SITE must become the routine's address rather than a call — both
      need the signature on the symbol (feature-nilpy-function-values). }
    if PyHdrPSigs[i] >= 0 then SymProcSig[idx] := PyHdrPSigs[i];
  end;
  if not isProc then
  begin
    { NOT literally 'Result': Pascal's implicit result variable is case-insensitive,
      and `for result in detector_results:` is ordinary Python (songformatter's
      key_analysis writes it). Spelled that way, the loop variable RESOLVED to the
      function's result and the def returned the last element instead of what it
      computed. `return` targets RetSymIdx by index, never by name, so a name no
      Python source can spell keeps the two apart.
      See bug-nilpy-local-named-result-aliases-the-function-result. }
    idx := AllocVar('$pyresult', retType);
    Procs[procIdx].RetSymIdx := idx;
    Syms[idx].Kind := skLocal;   { gates prologue zero-init -- see the method path }
    if (retType = tyClass) and (PyHdrRetCi >= 0) then
      Syms[idx].RecName := REC_UCLASS_BASE + PyHdrRetCi;
    if RetViaHiddenDest(retType) then
    begin
      { variant (Any) results ride the hidden-destination convention }
      idx := AllocVar('', tyPointer);
      ProcAggregateDestSym[procIdx] := idx;
    end;
  end;
  PyCollectLocalsAST(bodyStart);
  PyDbgDumpLocals(Procs[procIdx].Name);
  for i := 0 to PyLocalCount - 1 do
    if PyProgSym(PyLocals[i].Name) < 0 then
    begin
      idx := AllocVar(PyLocals[i].Name, PyLocals[i].TypeKind);
      if (PyLocals[i].TypeKind = tyClass) and (PyLocals[i].RecCi >= 0) then
        Syms[idx].RecName := REC_UCLASS_BASE + PyLocals[i].RecCi;
    end;

  Procs[procIdx].BodyAddr := CodeLen;   { see the note above: AFTER the pre-pass }
  patchPos := EmitProcPrologue;
  Procs[procIdx].FramePatch := patchPos;
  EmitAggregateDestStash(procIdx);
  PyEmitParamSpills(procIdx, nparams);
  PyInitVariantLocals(Procs[procIdx].ScopeBase);
  { Managed locals must start nil, exactly as in the Pascal routine body — a
    NilPy string local is a MANAGED AnsiString now, and without this the first
    assignment released stale stack bytes (`decq -0x10(%rax)` on garbage). }
  EmitManagedLocalsZeroInit(Procs[procIdx].ScopeBase);
  bodyNode := PyParseBlock;
  Expect(tkDedent, 'dedent');
  bodyNode := PyPrependResultZero(procIdx, bodyNode);
  CompileAST(bodyNode);
  EmitProcEpilog(Procs[procIdx].RetSymIdx);
  PatchProcPrologue(patchPos, FrameSize);
    { DWARF -g: same three lines every Pascal routine body ends with
    (parser.inc's routine-body tail). Without them a NilPy def had NO
    DW_TAG_subprogram at all — `break combine` in gdb answered "Function not
    defined", so the frontend where the hard bugs live was the one frontend you
    could not debug. ProcBodyEnd must be taken here, after the epilogue, and
    the locals snapshot before the scope is rolled back. }
  ProcBodyEnd[procIdx] := CodeLen;
  ProcDbgMain[procIdx] := DbgTokIsDebuggable(TokPos);
  if DebugInfo and ProcDbgMain[procIdx] then DbgCaptureProcLocals(procIdx);
  SymRollbackTo(savedSC);
  { Anything the BODY left on the hoist queue names this routine's locals, and
    they have just been rolled back. The queue is global, so the residue was
    flushed into whatever statement came next — inside a module that is the
    import-time init, which then loaded a symbol index past SymCount and the IR
    verifier rejected the whole compile at the module's LAST line, naming a
    `def` header 1700 lines earlier only in the DWARF line. A body's own hoists
    are flushed by its statement loop; whatever is left is stale by
    construction. }
  PyHoistHead := savedHoist;
  FrameSize := savedFS;
  CurProc := -1;
  PyNestPrefix := savedPfx;
  { Now that the enclosing routine's code is complete, compile the bodies its
    statement parser queued — each re-enters here at its own `def` token, with
    the qualifier it registered its shell under. Draining back to savedNest
    keeps nesting depth honest: a nested def's own nested defs are queued and
    drained by its own invocation. }
  while PyPendNestCount > savedNest do
  begin
    Dec(PyPendNestCount);
    savedTok := TokPos;
    savedPfx2 := PyNestPrefix;
    PyNestPrefix := PyPendNestPfx[PyPendNestCount];
    TokPos := PyPendNestTok[PyPendNestCount];
    Next;
    PyParseDef;
    PyNestPrefix := savedPfx2;
    TokPos := savedTok - 1;
    Next;
  end;
  PyDrainPendingLambdas(savedLam);
end;

{ Is the `def` at token index defIdx decorated with @property or @x.setter?
  Returns the prefix its method name must be MANGLED with, or '' for a plain
  method.

  Python names the getter and the setter identically (`base` twice), which
  Pascal cannot hold, so each accessor becomes a distinct hidden method and the
  PROPERTY keeps the plain name. The member pre-pass and PyParseMethod both
  call this one helper, deliberately: they derive the name independently and a
  disagreement between them is a silent ABI mismatch. }
function PyPropAccessorPrefixAt(defIdx: Integer): AnsiString;
var i: Integer;
begin
  Result := '';
  i := defIdx - 1;
  while (i >= 0) and (Tokens[i].Kind in [tkNewline, tkIndent, tkDedent]) do Dec(i);
  if i < 1 then Exit;
  if (Tokens[i - 1].Kind = tkAt) and (LowerCase(GetTokenStr(i)) = 'property') then
  begin
    Result := '__prop_get_';
    Exit;
  end;
  if (i >= 3) and (Tokens[i - 3].Kind = tkAt) and (Tokens[i - 1].Kind = tkDot) and
     (LowerCase(GetTokenStr(i)) = 'setter') then
    Result := '__prop_set_';
end;

function PyMethodName(const name: AnsiString): AnsiString;
begin
  if name = '__init__' then Result := 'create' else Result := name;
end;

{ Is `name` one of this method's parameters at all — annotated or not? Used to
  tell "assigned from an unannotated parameter" (fine, the field becomes a
  variant) from "assigned from something we could not type" (still an error). }
function PyHeaderHasParam(methodStart, stopIdx: Integer; const name: AnsiString): Boolean;
var i, depth: Integer;
begin
  Result := False;
  depth := 0;
  for i := methodStart to stopIdx - 1 do
  begin
    if Tokens[i].Kind = tkLParen then Inc(depth)
    else if Tokens[i].Kind = tkRParen then
    begin
      Dec(depth);
      if depth <= 0 then Exit;         { past the parameter list }
    end
    else if (depth = 1) and (Tokens[i].Kind = tkIdent) and
            (GetTokenStr(i) = name) then
    begin
      { a parameter NAME sits right after '(' or a ',' }
      if (Tokens[i - 1].Kind = tkLParen) or (Tokens[i - 1].Kind = tkComma) then
      begin
        Result := True;
        Exit;
      end;
    end;
  end;
end;

function PyHeaderParamType(methodStart, stopIdx: Integer; const name: AnsiString): TTypeKind;
{ The full annotation grammar, not the single-token reader: a ctor parameter may
  be annotated `Callable[[VM], None]` / `Optional[T]` / `List[T]` just like any
  other, and reading only one token typed the field tyUnknown and errored with
  "annotate it" on an annotation that was already there
  (feature-nilpy-function-values). PyAnnLastProcSig is left set for the caller,
  which is how a Callable FIELD gets its call signature. }
var i, k: Integer;
begin
  Result := tyUnknown;
  PyAnnLastProcSig := -1;
  for i := methodStart to stopIdx - 2 do
    if (Tokens[i].Kind = tkIdent) and (GetTokenStr(i) = name) and
       (Tokens[i + 1].Kind = tkColon) then
    begin
      k := i + 2;
      Result := PyAnnTypeAt(k);
      Exit;
    end;
end;

{ The CLASS a type-annotation token names, as a rec id (REC_NONE if it is not a
  user class). PyTypeFromTokenIndex reports tyClass but throws the identity
  away, and a tyClass field stored with REC_NONE cannot resolve its own members —
  `o.inner.name` fell back to Integer and printed the raw object pointer,
  silently (bug-nilpy-class-typed-field-loses-identity). The dataclass path
  already did this via PyAnnLastCi; these two give the __init__-annotation path
  the same.

  Fixes the direct chain only, which is the parser path. Two siblings are STILL
  broken and tracked in that ticket, both blocked on the same ordering problem:
  PyCollectModuleLocals runs BEFORE any class member is registered
  (PyRegisterClassShells registers names only), so at module-local inference
  time every class has zero fields —
    x = o.inner   (local hop)   the local cannot learn the field's class
    o.inner.m()   (method call) returns garbage
  Do not "fix" those by walking fields during inference; there is nothing to
  walk yet. }
function PyRecFromTokenIndex(i: Integer): Integer;
var ci: Integer;
begin
  Result := REC_NONE;
  if (i < 0) or (i >= TokCount) then Exit;
  if Tokens[i].Kind <> tkIdent then Exit;
  ci := FindUClass(GetTokenStr(i));
  if ci >= 0 then Result := REC_UCLASS_BASE + ci;
end;

function PyHeaderParamRec(methodStart, stopIdx: Integer; const name: AnsiString): Integer;
var i: Integer;
begin
  Result := REC_NONE;
  for i := methodStart to stopIdx - 2 do
    if (Tokens[i].Kind = tkIdent) and (GetTokenStr(i) = name) and
       (Tokens[i + 1].Kind = tkColon) then
    begin
      Result := PyRecFromTokenIndex(i + 2);
      Exit;
    end;
end;

function PyTypeName(tk: TTypeKind): AnsiString;
begin
  if tk = tyAnsiString then PyTypeName := 'str'
  else if tk = tyVariant then PyTypeName := 'Any'
  else PyTypeName := 'that type';
end;

{ A method's declared `-> TYPE`. PyRegisterClassMembers used to register every
  method with a hardcoded tyInteger return type, so only `-> int` worked by
  luck: `-> str` returned garbage, `-> float` returned 0, `-> bool` printed 1
  (bug-nilpy-method-returning-str-garbage). PyDefReturnType covers TOP-LEVEL
  defs only (it scans at depth 0), which is why methods were missed.
  Returns tyUnknown for `-> None` and for an unannotated method; the caller
  keeps tyInteger there, preserving today's behaviour for those. }
{ The return type of a def with NO `-> ret`, inferred from the FIRST
  `return <expr>` in its body. Defaulting such a def to tyInteger — which is
  what the pre-pass did while the annotation was still mandatory — silently
  truncates anything else: `return (a, b)` builds a TPyList and handed back its
  pointer as an integer, printing garbage. A def with no value-returning
  `return` is tyInteger, which is the harmless case.

  Shared by PyMethodRetType and PyParseDefHeader on purpose: the pre-pass
  decides the registered signature and the header decides the frame, so the two
  must reach the same answer or the mismatch is a silent ABI bug. }
{ The return type of a def NESTED in the body being scanned. Only top-level
  defs are hoisted (PyRegisterDefShells scans at depth 0), so a call to a nested
  helper has no registered signature when the ENCLOSING def's signature is
  decided — and falling back to the Integer default made the enclosing function
  hand a string result back as a number, silently.
  bug-nilpy-nested-def-nonint-result-garbage. }
function PyNestedDefRetType(scanFrom, scanTo: Integer; const nm: AnsiString;
                            var retRec: Integer): TTypeKind;
var i: Integer;
begin
  PyNestedDefRetType := tyUnknown;
  retRec := REC_NONE;
  for i := scanFrom to scanTo - 2 do
    if (Tokens[i].Kind = tkFunction) and (Tokens[i + 1].Kind = tkIdent) and
       CaseEqual(GetTokenStr(i + 1), nm) then
    begin
      PyNestedDefRetType := PyInferDefRetType(i, retRec);
      Exit;
    end;
end;

function PyInferDefRetType(methodStart: Integer; var retRec: Integer): TTypeKind;
var j, pdepth, bdepth, e, k, e2, rec2, bodyScanStart, curRec: Integer;
    tupDepth: Integer;
    t2, cur, chainCur: TTypeKind;
    seenAny, tupComma: Boolean;
begin
  Result := tyInteger;
  retRec := REC_NONE;
  rec2 := -1;
  seenAny := False;
  j := methodStart + 2;
  pdepth := 0;
  while j < TokCount do
  begin
    if Tokens[j].Kind = tkLParen then Inc(pdepth)
    else if Tokens[j].Kind = tkRParen then
    begin
      Dec(pdepth);
      if pdepth = 0 then begin Inc(j); Break; end;
    end;
    Inc(j);
  end;
  bodyScanStart := j;
  bdepth := 0;
  while j < TokCount do
  begin
    if Tokens[j].Kind = tkIndent then Inc(bdepth)
    else if Tokens[j].Kind = tkDedent then
    begin
      Dec(bdepth);
      if bdepth <= 0 then Exit;              { end of this def's body }
    end
    else if Tokens[j].Kind = tkFunction then
    begin
      { A nested def: SKIP its body and keep scanning this one. Stopping here
        meant the enclosing def's own `return` was never seen when a helper was
        declared above it, so the type fell to the Integer default and a string
        result came back as a number — silently
        (bug-nilpy-nested-def-nonint-result-garbage). The nested def's own
        returns must not be read as this def's, hence skip rather than descend. }
      { step past the nested def's INDENT..matching DEDENT }
      k := j;
      while (k < TokCount) and (Tokens[k].Kind <> tkIndent) do Inc(k);
      e2 := 0;
      while k < TokCount do
      begin
        if Tokens[k].Kind = tkIndent then Inc(e2)
        else if Tokens[k].Kind = tkDedent then
        begin
          Dec(e2);
          if e2 = 0 then begin Inc(k); Break; end;
        end;
        Inc(k);
      end;
      j := k;
      Continue;
    end
    else if (Tokens[j].Kind = tkExit) and (bdepth >= 1) then
    begin
      if j + 1 >= TokCount then Exit;
      { A BARE `return` is exactly `return None` in Python, so it says nothing
        about the type either -- keep scanning, the same way the None case
        below does. Exiting here let the value-less default (tyInteger) win
        over the REAL returns that followed it, so

            if n == 0:
                return
            return "str"

        handed the string back as an address, and a later `return [1]` came
        back as one too. A later `return 5` survived only by coincidence
        (bug-nilpy-return-type-inference-mistypes-several-expression-shapes).
        A def whose returns are ALL value-less still ends at the DEDENT below
        with the tyInteger default intact, which is the harmless case the
        comment above describes. }
      if Tokens[j + 1].Kind in [tkNewline, tkDedent, tkEOF] then
      begin
        Inc(j);
        Continue;
      end;
      { `return None` says nothing about the type — None is compatible with
        every result — so keep scanning for a return that does. uforth's
        _parse_compound_string returns None on its guard paths and the TUPLE
        only at the end; taking the first return typed it as an integer and
        the tuple came back truncated. }
      if (Tokens[j + 1].Kind = tkNil) and (j + 2 < TokCount) and
         (Tokens[j + 2].Kind in [tkNewline, tkDedent, tkEOF]) then
      begin
        Inc(j);
        Continue;
      end;
      e := j + 1;
      while (e < TokCount) and not (Tokens[e].Kind in [tkNewline, tkDedent, tkEOF]) do
        Inc(e);
      { `return a, b` is a TUPLE, which is a TPyList here (see PyMakeTupleFrom).
        Detected before the general inference, which would otherwise type the
        def by the FIRST element — `return 5,` came back as an integer, so the
        caller could not even len() it. Depth-tracked so a comma inside a call
        or a subscript does not count. }
      tupDepth := 0;
      tupComma := False;
      for k := j + 1 to e - 1 do
      begin
        if Tokens[k].Kind in [tkLParen, tkLBrack, tkBegin] then Inc(tupDepth)
        else if Tokens[k].Kind in [tkRParen, tkRBrack, tkEnd] then Dec(tupDepth)
        else if (Tokens[k].Kind = tkComma) and (tupDepth = 0) then tupComma := True;
      end;
      if tupComma then
      begin
        cur := tyClass;
        PyInferLastCi := FindUClass('TPyList');
        if PyInferLastCi < 0 then Error('Nil Python: pylib (TPyList) not loaded');
      end
      { `return lambda ...` is a CALLABLE VALUE, which travels as a variant.
        The scanner had no case for it and fell to the Integer default, so the
        boxed callable was converted to a number on the way out and the caller
        could not call what it got back. It only showed when the lambda
        captures NOTHING — a capturing one reaches the variant answer by
        another route — which is why the ticket had this recorded as being
        about the enclosing def's empty parameter list
        (bug-nilpy-function-value-call-gaps). }
      else if (Tokens[j + 1].Kind = tkIdent) and
              CaseEqual(GetTokenStr(j + 1), 'lambda') then
        cur := tyVariant
      else
        cur := PyInferExprType(j + 1, e);
      { `return w` — a bare ident the scanner cannot type: chase the ident's
        ASSIGNMENT earlier in the body and infer from its right-hand side
        (uforth's finalize_definition: `w = self.define_word(...)`, whose
        annotated Word return carries the class). Last well-typed assignment
        wins. }
      { PROMO also re-chases: PyInferExprType consults PyLocals for a bare
        ident, and a local widened to promo by the body is only visible in the
        HEADER pass (the pre-pass has no PyLocals) — trusting it here made the
        two passes infer different return types, a silent ABI mismatch. The
        token-only chase below gives both passes the same answer. }
      rec2 := -1;
      { tyVARIANT re-chases too, and that is the whole point: in the BODY pass
        PyInferExprType can see PyLocals and answers `variant` for a bare ident,
        while the SHELL pre-pass has no locals, chases the assignment and answers
        (say) `str`. The two passes then registered DIFFERENT return types for
        the same def — the silent ABI mismatch this comment warns about — and a
        def returning `s` where `s = str(x)` crashed on return. The token-only
        chase gives both passes the same answer, so it must run in both. }
      if ((cur = tyUnknown) or (cur = tyInteger) or (cur = tyVariant) or
          TypeIsPromoInt(cur)) and
         (e = j + 2) and (Tokens[j + 1].Kind = tkIdent) then
      begin
        chainCur := tyUnknown;
        for k := bodyScanStart to j - 1 do
          if (Tokens[k].Kind = tkIdent) and (k + 1 < TokCount) and
             (Tokens[k + 1].Kind = tkAssign) and
             CaseEqual(GetTokenStr(k), GetTokenStr(j + 1)) then
          begin
            e2 := k + 2;
            while (e2 < TokCount) and not (Tokens[e2].Kind in [tkNewline, tkDedent, tkEOF]) do
              Inc(e2);
            t2 := PyInferExprType(k + 2, e2);
            { Self-referential accumulator (`acc = acc + chr(97)`): this raw
              re-scan has no PyLocals here, so the leading `acc` on the RHS
              resolves to tyUnknown and contributes nothing, and the type comes
              from the REST of the expression alone — `acc + chr(97)` inferred
              tyChar from chr() and threw away that acc already held a string
              built up by an earlier assignment, truncating the returned value
              to one byte
              (bug-nilpy-return-type-inference-mistypes-several-expression-shapes).
              Fold in the type accumulated across the chain so far instead. }
            if (chainCur <> tyUnknown) and (k + 2 < e2) and
               (Tokens[k + 2].Kind = tkIdent) and
               CaseEqual(GetTokenStr(k + 2), GetTokenStr(j + 1)) then
              t2 := PyWiden(chainCur, t2);
            if (t2 <> tyUnknown) and (t2 <> tyInteger) and (t2 <> tyVariant) then
            begin
              cur := t2;
              chainCur := t2;
              rec2 := PyInferLastCi;
            end;
          end;
        if (cur = tyClass) and (rec2 >= 0) then
          PyInferLastCi := rec2;
      end;
      { A return EXPRESSION the scanner cannot type is DYNAMIC, not an integer.
        `def g(a): return a` with an untyped parameter is the plain case, and
        typing it tyInteger made the result a number: `g("a b").split(" ")`
        had a string method applied to an "integer" and did not parse, and
        anything that consumed the value read a string handle as a number.
        A def with NO value-returning return stays tyInteger — that is the
        harmless case this rule was written for, and it is decided elsewhere. }
      { `return inner()` / `s = inner(); return s` where `inner` is a def
        NESTED in this body: it has no registered signature yet, so the scans
        above answer Integer by default and the enclosing function then hands a
        string result back as a number. Find the nested def and take ITS type.
        bug-nilpy-nested-def-nonint-result-garbage. }
      if ((cur = tyUnknown) or (cur = tyInteger)) and (j + 2 < TokCount) and
         (Tokens[j + 1].Kind = tkIdent) and (Tokens[j + 2].Kind = tkLParen) and
         (FindProc(GetTokenStr(j + 1)) < 0) then
      begin
        t2 := PyNestedDefRetType(bodyScanStart, j, GetTokenStr(j + 1), rec2);
        if t2 <> tyUnknown then
        begin
          cur := t2;
          if (t2 = tyClass) and (rec2 >= REC_UCLASS_BASE) then
            PyInferLastCi := rec2 - REC_UCLASS_BASE;
        end;
      end;
      { the same through a local: `s = inner()` then `return s` }
      if ((cur = tyUnknown) or (cur = tyInteger)) and
         (e = j + 2) and (Tokens[j + 1].Kind = tkIdent) then
        for k := bodyScanStart to j - 1 do
          if (Tokens[k].Kind = tkIdent) and (k + 3 < TokCount) and
             (Tokens[k + 1].Kind = tkAssign) and
             (Tokens[k + 2].Kind = tkIdent) and (Tokens[k + 3].Kind = tkLParen) and
             CaseEqual(GetTokenStr(k), GetTokenStr(j + 1)) and
             (FindProc(GetTokenStr(k + 2)) < 0) then
          begin
            t2 := PyNestedDefRetType(bodyScanStart, k, GetTokenStr(k + 2), rec2);
            if t2 <> tyUnknown then
            begin
              cur := t2;
              if (t2 = tyClass) and (rec2 >= REC_UCLASS_BASE) then
                PyInferLastCi := rec2 - REC_UCLASS_BASE;
            end;
          end;
      { NOTE tyInteger, not tyVariant. Making an untypable return DYNAMIC is
        the honest answer and was tried (0843fbb7) — but a variant-returning
        def returns through a hidden destination, and a def whose parameters
        carry DEFAULTS then segfaults ON RETURN (`def s(a, b=2): return a + b`,
        called with both arguments written). That is a codegen gap, not an
        inference question, and it is filed as
        bug-nilpy-variant-return-with-defaulted-param-segfaults; flip this line
        back when it is fixed. The shape 0843fbb7 was written for —
        `get(a,b,c).split("x")` — keeps working through the runtime-dispatch
        suffix loop that commit added, which does not depend on this. }
      if cur = tyUnknown then cur := tyVariant;
      if cur = tyString then cur := tyAnsiString;
      { A PROMOTABLE INT cannot cross the call boundary raw: its rvalue is the
        frame SLOT ADDRESS and the frame dies at return — the caller read a
        stack address as the value (uforth /STRING returned garbage and the
        word list was walked through it -> wild jump). Box to a variant
        (inline -> VT_INT64, heap -> VT_PROMO), which the Result store and
        every caller already handle. }
      if TypeIsPromoInt(cur) then cur := tyVariant;
      curRec := REC_NONE;
      if (cur = tyClass) and (PyInferLastCi >= 0) then
        curRec := REC_UCLASS_BASE + PyInferLastCi;
      { Merge with the other returns instead of taking the first and exiting:
        a def whose arms return DIFFERENT kinds (`return "pos"` / `return 42`)
        must produce a VARIANT result — the first-return rule stored the int
        as a string handle and the consumer crashed on it
        (bug-nilpy-mixed-str-int-return-segfault). Identical kinds (and the
        single-return case) keep exactly the old answer. }
      if not seenAny then
      begin
        seenAny := True;
        Result := cur;
        retRec := curRec;
      end
      else if (Result <> cur) or
              ((Result = tyClass) and (retRec <> curRec)) then
      begin
        Result := tyVariant;
        retRec := REC_NONE;
      end;
      j := e;
      Continue;
    end;
    Inc(j);
  end;
end;

{ Does the def's body contain a VALUE-bearing `return`? (`return` bare and
  `return None` do not count.) Used to override a LYING `-> None` annotation:
  CPython ignores annotations entirely, and uforth's finalize_definition is
  annotated `-> None` yet returns the new Word — trusting the annotation
  compiled it as a procedure and the caller read garbage (the :NONAME xt). }
function PyMethodReturnsSelf(defIdx: Integer): Boolean;
{ Does this method's body `return self`? That is the fluent-builder idiom —
  `def add(self, x): ...; return self` — and its result type is the method's own
  class. Inferred by the scanner alone: `self` is a parameter whose class only
  the enclosing class knows, so the general expression inference answers unknown,
  the method registered an Integer result, and the SECOND link of a chain
  (`B().add(1).add(2)`) had no class to resolve against — "expected expression"
  (bug-nilpy-method-chaining-on-a-call-result). Nested defs are skipped, as in
  PyDefHasValueReturn, so an inner helper's `return self` is not read as this
  method's. }
var j, pdepth, bdepth, k, e2: Integer;
begin
  Result := False;
  j := defIdx + 2;
  pdepth := 0;
  while j < TokCount do
  begin
    if Tokens[j].Kind = tkLParen then Inc(pdepth)
    else if Tokens[j].Kind = tkRParen then
    begin
      Dec(pdepth);
      if pdepth = 0 then begin Inc(j); Break; end;
    end;
    Inc(j);
  end;
  bdepth := 0;
  while j < TokCount do
  begin
    if Tokens[j].Kind = tkIndent then Inc(bdepth)
    else if Tokens[j].Kind = tkDedent then
    begin
      Dec(bdepth);
      if bdepth <= 0 then Exit;
    end
    else if Tokens[j].Kind = tkFunction then
    begin
      k := j;
      while (k < TokCount) and (Tokens[k].Kind <> tkIndent) do Inc(k);
      e2 := 0;
      while k < TokCount do
      begin
        if Tokens[k].Kind = tkIndent then Inc(e2)
        else if Tokens[k].Kind = tkDedent then
        begin
          Dec(e2);
          if e2 = 0 then begin Inc(k); Break; end;
        end;
        Inc(k);
      end;
      j := k;
      Continue;
    end
    else if (Tokens[j].Kind = tkExit) and (bdepth >= 1) then
    begin
      if (j + 2 < TokCount) and (Tokens[j + 1].Kind = tkIdent) and
         CaseEqual(GetTokenStr(j + 1), 'self') and
         (Tokens[j + 2].Kind in [tkNewline, tkDedent, tkEOF]) then
      begin
        Result := True;
        Exit;
      end;
    end;
    Inc(j);
  end;
end;

function PyDefHasValueReturn(defIdx: Integer): Boolean;
var j, pdepth, bdepth, k, e2: Integer;
begin
  Result := False;
  j := defIdx + 2;
  pdepth := 0;
  while j < TokCount do
  begin
    if Tokens[j].Kind = tkLParen then Inc(pdepth)
    else if Tokens[j].Kind = tkRParen then
    begin
      Dec(pdepth);
      if pdepth = 0 then begin Inc(j); Break; end;
    end;
    Inc(j);
  end;
  bdepth := 0;
  while j < TokCount do
  begin
    if Tokens[j].Kind = tkIndent then Inc(bdepth)
    else if Tokens[j].Kind = tkDedent then
    begin
      Dec(bdepth);
      if bdepth <= 0 then Exit;
    end
    else if Tokens[j].Kind = tkFunction then
    begin
      { A nested def: SKIP its body and keep scanning this one. Stopping here
        meant the enclosing def's own `return` was never seen when a helper was
        declared above it, so the type fell to the Integer default and a string
        result came back as a number — silently
        (bug-nilpy-nested-def-nonint-result-garbage). The nested def's own
        returns must not be read as this def's, hence skip rather than descend. }
      { step past the nested def's INDENT..matching DEDENT }
      k := j;
      while (k < TokCount) and (Tokens[k].Kind <> tkIndent) do Inc(k);
      e2 := 0;
      while k < TokCount do
      begin
        if Tokens[k].Kind = tkIndent then Inc(e2)
        else if Tokens[k].Kind = tkDedent then
        begin
          Dec(e2);
          if e2 = 0 then begin Inc(k); Break; end;
        end;
        Inc(k);
      end;
      j := k;
      Continue;
    end
    else if (Tokens[j].Kind = tkExit) and (bdepth >= 1) then
    begin
      if (j + 1 < TokCount) and
         not (Tokens[j + 1].Kind in [tkNewline, tkDedent, tkEOF]) and
         not ((Tokens[j + 1].Kind = tkNil) and (j + 2 < TokCount) and
              (Tokens[j + 2].Kind in [tkNewline, tkDedent, tkEOF])) then
      begin
        Result := True;
        Exit;
      end;
    end;
    Inc(j);
  end;
end;

function PyMethodRetType(methodStart: Integer; var retRec: Integer): TTypeKind;
var j, pdepth, k: Integer;
begin
  Result := tyUnknown;
  retRec := REC_NONE;
  j := methodStart + 2;
  pdepth := 0;
  while j < TokCount do
  begin
    if Tokens[j].Kind = tkLParen then Inc(pdepth)
    else if Tokens[j].Kind = tkRParen then
    begin
      Dec(pdepth);
      if pdepth = 0 then Break;
    end;
    Inc(j);
  end;
  if (j + 3 < TokCount) and (Tokens[j + 1].Kind = tkMinus) and
     (Tokens[j + 2].Kind = tkGt) then
  begin
    { The FULL annotation grammar, not the single-token reader: a return type
      may be `Optional[Word]` / `List[T]` / `Callable[...]` exactly as a
      parameter may. PyTypeFromTokenIndex saw only the leading `Optional` and
      dropped the class, so a local assigned from the call lost its identity
      and the next `.method()` on it did not resolve. Same "two readers for one
      grammar, and the narrow one wins wherever it is still wired up" bug the
      parameter path already carries a note about
      (bug-nilpy-optional-return-annotation-loses-the-class). }
    { the same lying `-> None` override as PyParseDefHeader — the pre-pass and
      the real parse MUST agree or the signature silently mismatches }
    if (Tokens[j + 3].Kind = tkNil) and PyDefHasValueReturn(methodStart) then
    begin
      Result := PyInferDefRetType(methodStart, retRec);
      Exit;
    end;
    k := j + 3;
    PyAnnRetScope := True;
    Result := PyAnnTypeAt(k);
    PyAnnRetScope := False;
    if (Result = tyClass) and (PyAnnLastCi >= 0) then
      retRec := REC_UCLASS_BASE + PyAnnLastCi
    else
      retRec := REC_NONE;
  end
  else
    { no annotation: infer from the body rather than defaulting to Integer }
    Result := PyInferDefRetType(methodStart, retRec);
end;

{ fieldsOnly = the PRE-PASS: register this class's FIELDS and nothing else.
  PyCollectModuleLocals runs before the main loop that parses classes, so
  without a pre-pass every class has zero fields during module-local inference
  and `x = o.inner` cannot learn the field's class
  (bug-nilpy-class-typed-field-loses-identity). Sharing one procedure keeps the
  field rules in ONE place instead of a drifting copy.
  The later real call resets UClsFBase/UClsFCount on entry, so it rebuilds the
  window from scratch and the pre-pass entries are simply orphaned — which also
  means the dataclass duplicate-field check cannot see them and mis-fire. }
procedure PyRegisterClassMembers(ci, bodyStart, bodyEnd: Integer; isDC: Boolean;
                                 fieldsOnly: Boolean);
var i, j, k, depth, methodStart, nparams, procIdx, mmi, inhMmi, slot, curOff, align, sz: Integer;
    ovMmi, ovPi: Integer;   { the inherited method an override must match }
    fldAnn, rhsAt, k2, fldSig: Integer;
    origName, name, fullName, rhsName: AnsiString; isCtor: Boolean;
    fldRec, mRetRec, pri: Integer; mRet: TTypeKind;
    mStarIdx, mKwIdx, starCi: Integer;   { `*args` / `**kwargs` parameter slots }
    pnames: array[0..15] of AnsiString; ptypes: array[0..15] of TTypeKind;
    pdefHas: array[0..15] of Boolean; pdefIsStr: array[0..15] of Boolean;
    pdefIsNone: array[0..15] of Boolean; pdefIsFloat: array[0..15] of Boolean;
    pdefVal: array[0..15] of Int64;
    pdefSOff: array[0..15] of Integer; pdefSLen: array[0..15] of Integer;
    tk: TTypeKind; defKind: Integer; defIVal: Int64; defSOff, defSLen: Integer;
begin
  UClsFBase[ci] := UFldCount;
  UClsFCount[ci] := 0;
  UClsMBase[ci] := UMthCount;
  UClsMCount[ci] := 0;
  UClsPBase[ci] := UPropCount;
  UClsPCount[ci] := 0;
  { A SUBCLASS continues the parent's layout: its own fields start past the
    parent's instance size and its virtual slots past the parent's slot count.
    Starting both at zero made `class B(A)` overlay B's fields on A's and reuse
    A's VMT slots, so an INHERITED method silently ran a subclass method with
    the same slot number (bug-a-nilpy-subclass-overlays-parent-layout). }
  curOff := 8;
  if UClsParent[ci] >= 0 then
  begin
    curOff := UClsSize_[UClsParent[ci]];
    if curOff < 8 then curOff := 8;
    UClsVirtCount[ci] := UClsVirtCount[UClsParent[ci]];
  end;
  align := 8;
  depth := 0;
  i := bodyStart;
  while i < bodyEnd do
  begin
    if Tokens[i].Kind = tkIndent then Inc(depth)
    else if Tokens[i].Kind = tkDedent then Dec(depth)
    else if (depth = 0) and (Tokens[i].Kind = tkIdent) and
            (i + 2 < bodyEnd) and (Tokens[i + 1].Kind = tkAssign) and
            ((i = bodyStart) or
             (Tokens[i - 1].Kind in [tkNewline, tkIndent, tkDedent])) and
            (Tokens[i + 2].Kind in [tkInteger, tkFloat, tkString, tkTrue, tkFalse, tkNil]) then
    begin
      { A CLASS ATTRIBUTE — `name = "note_counting"`, unannotated, at class
        level. Held as a per-class compile-time constant (see the PyClsAttr*
        note in defs.inc): the read `self.name` becomes the literal, and an
        assignment to it is refused rather than pretending Python's shared
        class attribute exists. Registered in the pre-pass with everything
        else, so a method body parsed later can already see it. }
      { The attribute is a real FIELD on the instance (typed from its literal),
        so reads and the construction-time store go through the ordinary field
        path. Registered here in the pre-pass, before any method body is parsed. }
      if FindUField(ci, GetTokenStr(i)) < 0 then
      begin
        case Tokens[i + 2].Kind of
          tkInteger:      tk := tyInt64;
          tkFloat:        tk := tyDouble;
          tkString:       tk := tyAnsiString;
          tkTrue, tkFalse: tk := tyBoolean;
        else
          tk := tyVariant;
        end;
        sz := TypeSize(tk);
        curOff := AlignTo(curOff, TypeAlign(tk));
        AddUField(ci, Tokens[i].SOffset, Tokens[i].SLen, curOff, Ord(tk), REC_NONE);
        Inc(curOff, sz);
      end;
      if PyClsAttrCount < 256 then
      begin
        PyClsAttrCi[PyClsAttrCount]   := ci;
        PyClsAttrNOff[PyClsAttrCount] := Tokens[i].SOffset;
        PyClsAttrNLen[PyClsAttrCount] := Tokens[i].SLen;
        PyClsAttrSOff[PyClsAttrCount] := 0;
        PyClsAttrSLen[PyClsAttrCount] := 0;
        PyClsAttrIVal[PyClsAttrCount] := 0;
        case Tokens[i + 2].Kind of
          tkInteger: begin PyClsAttrKind[PyClsAttrCount] := PYDC_INT;
                           PyClsAttrIVal[PyClsAttrCount] := Tokens[i + 2].IVal; end;
          tkFloat:   begin PyClsAttrKind[PyClsAttrCount] := PYDC_FLOAT;
                           PyClsAttrIVal[PyClsAttrCount] := Tokens[i + 2].IVal; end;
          tkString:  begin PyClsAttrKind[PyClsAttrCount] := PYDC_STR;
                           PyClsAttrSOff[PyClsAttrCount] := Tokens[i + 2].SOffset;
                           PyClsAttrSLen[PyClsAttrCount] := Tokens[i + 2].SLen; end;
          tkTrue:    begin PyClsAttrKind[PyClsAttrCount] := PYDC_BOOL;
                           PyClsAttrIVal[PyClsAttrCount] := 1; end;
          tkFalse:   begin PyClsAttrKind[PyClsAttrCount] := PYDC_BOOL; end;
        else
          PyClsAttrKind[PyClsAttrCount] := PYDC_NIL;
        end;
        Inc(PyClsAttrCount);
      end;
      while (i < bodyEnd) and (Tokens[i].Kind <> tkNewline) do Inc(i);
      Inc(i);
      continue;
    end
    else if (depth = 0) and (Tokens[i].Kind = tkIdent) and
            (i + 2 < bodyEnd) and (Tokens[i + 1].Kind = tkAssign) and
            ((i = bodyStart) or
             (Tokens[i - 1].Kind in [tkNewline, tkIndent, tkDedent])) then
    begin
      { A class attribute whose initialiser is NOT a literal — `mode = Inner()`,
        the attribute-namespace idiom (songformatter's render backend declares
        reportlab's blend modes exactly this way). The literal branch above
        cannot hold it: there is no constant to fold. Registered here as an
        ordinary FIELD, and PyParseClass evaluates the expression ONCE into a
        hidden global that construction copies in — so every instance shares the
        one object, as Python's class attribute does.

        Before this, the line matched no branch at all: no field, no constant,
        and `self.mode.NORMAL` then compiled against nothing and SEGFAULTED at
        run time (bug-nilpy-class-attr-instance-traversal-crashes). }
      if FindUField(ci, GetTokenStr(i)) < 0 then
      begin
        tk := tyVariant;
        k := REC_NONE;
        { `name = Cls(...)` — the field carries Cls's identity, which is what
          makes the traversal `self.name.attr` resolve to a real field. }
        if (Tokens[i + 2].Kind = tkIdent) and (i + 3 < bodyEnd) and
           (Tokens[i + 3].Kind = tkLParen) then
        begin
          j := FindUClass(GetTokenStr(i + 2));
          if j >= 0 then begin tk := tyClass; k := REC_UCLASS_BASE + j; end;
        end;
        sz := TypeSize(tk);
        curOff := AlignTo(curOff, TypeAlign(tk));
        AddUField(ci, Tokens[i].SOffset, Tokens[i].SLen, curOff, Ord(tk), k);
        Inc(curOff, sz);
      end;
      while (i < bodyEnd) and (Tokens[i].Kind <> tkNewline) do Inc(i);
      Inc(i);
      continue;
    end
    else if isDC and (depth = 0) and (Tokens[i].Kind = tkIdent) and
            (i + 2 < bodyEnd) and (Tokens[i + 1].Kind = tkColon) and
            ((i = bodyStart) or
             (Tokens[i - 1].Kind in [tkNewline, tkIndent, tkDedent])) then
    begin
      { line-start guard: a method header's `-> bool:` return annotation
        would otherwise re-match as a field named 'bool' }
      { ClassVar annotation: a class-level static — register it as a class
        variable (the same registry Pascal `class var` uses, so
        ClassName.name resolves through FindClassVar). Typed tyClass; the
        assignment that populates it fixes RecName (see PyParseStatement). }
      if (Tokens[i + 2].Kind = tkIdent) and
         CaseEqual(GetTokenStr(i + 2), 'ClassVar') then
      begin
        if ClassVarCount >= MAX_TYPEALIAS then Error('too many class variables');
        k := AllocVar('', tyClass);
        ClassVarCi[ClassVarCount]   := ci;
        ClassVarNOff[ClassVarCount] := Tokens[i].SOffset;
        ClassVarNLen[ClassVarCount] := Tokens[i].SLen;
        ClassVarSym[ClassVarCount]  := k;
        Inc(ClassVarCount);
        while (i < bodyEnd) and (Tokens[i].Kind <> tkNewline) do Inc(i);
        Inc(i);
        continue;
      end;
      { @dataclass field: name : annotation [= literal-default] }
      j := i + 2;
      tk := PyAnnTypeAt(j);
      { Captured HERE, before the default-value scan below can clobber it: a
        `Callable[...]` field carries a procedural signature, and AddUField
        reads it from LastTypeProcSig. Without it the field was registered as
        a plain pointer and `w.native(vm)` was not recognised as a call at all
        — the parse stopped before the '(' (bug-nilpy-dataclass-callable-field). }
      fldSig := PyAnnLastProcSig;
      if tk = tyUnknown then
        Error('Nil Python: unsupported dataclass field type for ' +
              GetTokenStr(i));
      { A tyString FIELD means inline `string[N]` to the shared store path
        (capacity-clamped content copy); NilPy str is pointer-semantics, so
        class fields hold managed strings instead. }
      if tk = tyString then tk := tyAnsiString;
      defKind := PYDC_NONE; defIVal := 0; defSOff := 0; defSLen := 0;
      if (j < bodyEnd) and (Tokens[j].Kind = tkAssign) then
      begin
        Inc(j);
        case Tokens[j].Kind of
          tkInteger: begin defKind := PYDC_INT; defIVal := Tokens[j].IVal; end;
          tkFloat:   begin defKind := PYDC_FLOAT; defIVal := Tokens[j].IVal; end;
          tkString:  begin defKind := PYDC_STR;
                           defSOff := Tokens[j].SOffset;
                           defSLen := Tokens[j].SLen; end;
          tkTrue:    begin defKind := PYDC_BOOL; defIVal := 1; end;
          tkFalse:   begin defKind := PYDC_BOOL; defIVal := 0; end;
          tkNil:     begin defKind := PYDC_NIL; defIVal := 0; end;
          tkIdent:
          begin
            { field(default_factory=list) -> fresh empty list per construction }
            if CaseEqual(GetTokenStr(j), 'field') and (j + 4 < bodyEnd) and
               (Tokens[j + 1].Kind = tkLParen) and
               (Tokens[j + 2].Kind = tkIdent) and
               CaseEqual(GetTokenStr(j + 2), 'default_factory') and
               (Tokens[j + 3].Kind = tkAssign) and
               (Tokens[j + 4].Kind = tkIdent) and
               (CaseEqual(GetTokenStr(j + 4), 'list') or
                CaseEqual(GetTokenStr(j + 4), 'dict')) and
               (j + 5 < bodyEnd) and (Tokens[j + 5].Kind = tkRParen) then
            begin
              if CaseEqual(GetTokenStr(j + 4), 'dict') then
                defKind := PYDC_FACTORY_DICT
              else
                defKind := PYDC_FACTORY_LIST;
              j := j + 5;   { onto ')'; the common Inc(j) below steps past it }
            end
            else if CaseEqual(GetTokenStr(j), 'field') and (j + 6 < bodyEnd) and
               (Tokens[j + 1].Kind = tkLParen) and
               (Tokens[j + 2].Kind = tkIdent) and
               CaseEqual(GetTokenStr(j + 2), 'default_factory') and
               (Tokens[j + 3].Kind = tkAssign) and
               (Tokens[j + 4].Kind = tkIdent) and
               CaseEqual(GetTokenStr(j + 4), 'lambda') and
               (Tokens[j + 5].Kind = tkColon) then
            begin
              { zero-arg lambda: capture the body's token span; the matching
                ')' closes field( — track bracket depth from that paren }
              defKind := PYDC_FACTORY_EXPR;
              defIVal := j + 6;         { body start token index }
              j := j + 6; defSLen := 1; { depth inside field( }
              while (j < bodyEnd) and (defSLen > 0) do
              begin
                if Tokens[j].Kind = tkLParen then Inc(defSLen)
                else if Tokens[j].Kind = tkRParen then
                begin
                  Dec(defSLen);
                  if defSLen = 0 then break;
                end;
                Inc(j);
              end;
              defSOff := j;             { body end (the closing paren) }
              defSLen := 0;
            end
            else
              Error('Nil Python: unsupported dataclass field default (field(default_factory=list), field(default_factory=dict) and a zero-arg lambda are the supported forms)');
          end;
          tkMinus:
          begin
            Inc(j);
            if Tokens[j].Kind = tkInteger then
            begin defKind := PYDC_INT; defIVal := -Tokens[j].IVal; end
            else if Tokens[j].Kind = tkFloat then
            begin defKind := PYDC_FLOAT;
                  { negate an IEEE double by flipping its sign bit }
                  defIVal := Tokens[j].IVal xor (Int64(1) shl 63); end
            else Error('Nil Python: unsupported dataclass field default');
          end;
          else Error('Nil Python: unsupported dataclass field default (scalar literal only)');
        end;
        Inc(j);
      end;
      if (defKind = PYDC_INT) and (tk = tyDouble) then
      begin
        defKind := PYDC_FLOAT;
        defIVal := StrToDoubleBits(PyIntLiteralText(defIVal));
      end;
      if FindUField(ci, GetTokenStr(i)) >= 0 then
        Error('Nil Python: duplicate dataclass field ' + GetTokenStr(i));
      sz := TypeSize(tk);
      curOff := AlignTo(curOff, TypeAlign(tk));
      LastTypeProcSig := fldSig;   { procedural field — see the capture above }
      if (tk = tyClass) and (PyAnnLastCi >= 0) then
        AddUField(ci, Tokens[i].SOffset, Tokens[i].SLen, curOff, Ord(tk),
                  REC_UCLASS_BASE + PyAnnLastCi)
      else
        AddUField(ci, Tokens[i].SOffset, Tokens[i].SLen, curOff, Ord(tk), REC_NONE);
      LastTypeProcSig := -1;
      Inc(curOff, sz);
      if not fieldsOnly then
      begin
      if PyDcCount >= PY_MAX_DC_FIELDS then
        Error('Nil Python: too many dataclass fields');
      PyDcCi[PyDcCount] := ci;
      PyDcKind[PyDcCount] := defKind;
      PyDcIVal[PyDcCount] := defIVal;
      PyDcSOff[PyDcCount] := defSOff;
      PyDcSLen[PyDcCount] := defSLen;
      Inc(PyDcCount);
      end;
      i := j;
      while (i < bodyEnd) and (Tokens[i].Kind <> tkNewline) do Inc(i);
    end
    else if (depth = 0) and (Tokens[i].Kind = tkFunction) then
    begin
      methodStart := i;
      origName := GetTokenStr(i + 1);
      name := PyMethodName(origName);
      if PyPropAccessorPrefixAt(i) <> '' then
        name := PyPropAccessorPrefixAt(i) + origName;
      isCtor := name = 'create';
      nparams := 0;
      for k := 0 to 15 do pdefHas[k] := False;
      j := i + 3;
      mStarIdx := -1; mKwIdx := -1;
      while Tokens[j].Kind <> tkRParen do
      begin
        { `*` / `*args` / `**kwargs` in a METHOD header. The top-level def path
          (PyParseDefHeader) has taken these since feature-nilpy-star-args-kwargs;
          the method path never did, so `def drawImage(self, ..., **kw)` failed
          to parse while the identical free function compiled. Both passes need
          it and both must agree, since the pre-pass decides the registered
          signature and PyParseMethod builds the frame from it. }
        if Tokens[j].Kind = tkStar then
        begin
          Inc(j);
          { a BARE `*` is the keyword-only marker — no parameter of its own }
          if Tokens[j].Kind = tkComma then
          begin
            Inc(j);
            Continue;
          end;
          if Tokens[j].Kind = tkStar then
          begin
            mKwIdx := nparams;
            Inc(j);
          end
          else mStarIdx := nparams;
          pnames[nparams] := GetTokenStr(j);
          Inc(j);
          { `*args: str` annotates the ELEMENT; the parameter stays a list }
          if Tokens[j].Kind = tkColon then
          begin
            Inc(j);
            PyAnnTypeAt(j);
            Inc(j);
          end;
          ptypes[nparams] := tyClass;
          Inc(nparams);
          if Tokens[j].Kind = tkComma then Inc(j);
          Continue;
        end;
        pnames[nparams] := GetTokenStr(j);
        if (nparams = 0) and (pnames[nparams] = 'self') then
        begin
          ptypes[nparams] := tyClass;
          Inc(j);
        end
        else
        begin
          Inc(j);
          if Tokens[j].Kind <> tkColon then
          begin
            { UNANNOTATED parameter — defaults to Any (variant), matching
              PyParseDefHeader. Must agree with the header parse or the
              registered signature and the frame disagree. }
            ptypes[nparams] := tyVariant;
          end
          else
          begin
          Inc(j);
          { PyAnnTypeAt, not PyTypeFromTokenIndex: a method parameter takes
            the SAME annotation grammar as a field or a dataclass member —
            List/Dict/set/Optional/Callable/Any/forward refs. The narrow
            single-token reader here meant a method could not accept a
            container, which is most of uforth's method signatures, and it
            reported the failure with no line of its own. }
          ptypes[nparams] := PyAnnTypeAt(j);
          if ptypes[nparams] = tyUnknown then
            ErrorAt(Tokens[j].Line,
                    'Nil Python: parameter ' + pnames[nparams]
                    + ' has an unsupported type annotation');
          end;
          if Tokens[j].Kind = tkAssign then
          begin
            Inc(j);
            pdefHas[nparams] := True;
            pdefVal[nparams] := PyParamDefaultAt(j, pnames[nparams],
                                                 pdefIsStr[nparams],
                                                 pdefSOff[nparams],
                                                 pdefSLen[nparams]);
            pdefIsNone[nparams] := PyDefaultWasNone;
            pdefIsFloat[nparams] := PyDefaultWasFloat;
          end;
        end;
        Inc(nparams);
        if Tokens[j].Kind = tkComma then Inc(j);
      end;
      fullName := PyRawName(UClsNOff[ci], UClsNLen[ci]);
      AppendChar(fullName, '.');
      for k := 1 to Length(name) do AppendChar(fullName, name[k]);
      mRet := PyMethodRetType(methodStart, mRetRec);
      if mRet = tyUnknown then mRet := tyInteger;   { `-> None` / unannotated }
      { `return self` types the method as its OWN class — the fluent-builder
        idiom, and the only way a chain's second link has something to resolve
        against. The scanner cannot get there on its own: `self` is a parameter
        whose class only this pre-pass knows. }
      if (not fieldsOnly) and (not isCtor) and PyMethodReturnsSelf(methodStart) then
      begin
        mRet := tyClass;
        mRetRec := REC_UCLASS_BASE + ci;
      end;
      { An OVERRIDE takes the base method's signature. Python overrides need no
        annotations, so `def optionxform(self, s): return s` infers a variant
        result — but the inherited method occupies a VMT slot with the base's
        types, and the base's own body calls THROUGH that slot. The two must
        agree or the base reads the override's result as the wrong kind
        (configparser's optionxform, overridden by every case-preserving
        subclass, returned a variant where an AnsiString was expected). The
        base's parameter types come with it, for the same reason. }
      if (not fieldsOnly) and (not isCtor) and (UClsParent[ci] >= 0) then
      begin
        ovMmi := FindUMeth(UClsParent[ci], name);
        if ovMmi >= 0 then
        begin
          ovPi := UMthProc_[ovMmi];
          if (ovPi >= 0) and (Procs[ovPi].ParamCount = nparams) then
          begin
            mRet := Procs[ovPi].RetType;
            mRetRec := ProcRetRecId[ovPi];
            for k := 1 to nparams - 1 do
              ptypes[k] := Procs[ovPi].Params[k].TypeKind;
          end;
        end;
      end;
      { str is managed here as everywhere else in NilPy }
      if mRet = tyString then mRet := tyAnsiString;
      if mRet <> tyClass then mRetRec := REC_NONE;
      { A method taken as a BOUND VALUE (`cb = self.on_key`) is called back
        through the function-object ABI, so it is normalised exactly as
        PyDefUsedAsValue normalises a def: variant result, variant parameters.
        Without it the pair held a method returning in a register while
        pybound_callv* passed a hidden destination — a value-returning bound
        method crashed, a `-> None` one worked, which is why this looked like a
        receiver bug rather than an ABI one. Applied AFTER the override block so
        a normalised base and its override still agree (both share the name, so
        both normalise). }
      if (not fieldsOnly) and (not isCtor) and PyMethodUsedAsValue(origName) then
      begin
        if mRet <> tyVariant then begin mRet := tyVariant; mRetRec := REC_NONE; end;
        for k := 1 to nparams - 1 do
          if (k <> mStarIdx) and (k <> mKwIdx) then ptypes[k] := tyVariant;
      end;
      { An aggregate/managed return from a METHOD is not wired up: a managed
        str return segfaults and a hidden-destination return has no caller-side
        destination. Reject with a diagnostic rather than ship the silent
        garbage this used to produce (bug-nilpy-method-returning-str-garbage) —
        before the return type was honoured at all, `-> str` printed an integer.
        Scalars (int, bool, float) and class returns are unaffected and now DO
        honour their annotation, which is what fixed `-> bool` printing 1 and
        `-> float` returning 0. A top-level `def` returning str works; only
        methods are limited. }
      { tyVariant is NO LONGER in this restriction: variant-returning routines
        got the record-style hidden-dest treatment, so a method can return Any
        the same way a top-level def already could. The guard still stands for
        the string/record kinds it was written for. }
      if (not fieldsOnly) and (not isCtor) and
         (RetViaHiddenDest(mRet)) and (mRet <> tyVariant) then
        { ErrorAt with the DEF's own line: plain Error here printed the line of
          whatever the parser cursor was on, which for a class pre-pass is the
          `class` header — so every one of a class's offending methods reported
          the same line and no way to tell them apart. }
        ErrorAt(Tokens[methodStart].Line,
                'Nil Python: method ' + origName + ' returns ' + PyTypeName(mRet)
                + ', which is not supported yet '
                + '(bug-nilpy-method-returning-str-garbage); '
                + 'a top-level def returning it works, or return it through a field');
      if fieldsOnly then procIdx := -1
      else
      begin
        procIdx := RegisterProc(fullName, not isCtor, mRet, nparams, pnames, ptypes);
        if mRetRec >= REC_UCLASS_BASE then ProcRetRecId[procIdx] := mRetRec;
        { the call-site packing reads these two, and overload matching reads the
          parameter's class out of ProcParamRecId — same wiring the def path
          does at the end of PyParseDefHeader }
        ProcPyStarIdx[procIdx] := mStarIdx;
        ProcPyKwIdx[procIdx] := mKwIdx;
        if (mStarIdx >= 0) and (mStarIdx < MAX_PROC_PARAMS) then
        begin
          starCi := FindUClass('TPyList');
          if starCi < 0 then Error('Nil Python: pylib (TPyList) not loaded');
          ProcParamRecId[procIdx * MAX_PROC_PARAMS + mStarIdx] :=
            REC_UCLASS_BASE + starCi;
        end;
        if (mKwIdx >= 0) and (mKwIdx < MAX_PROC_PARAMS) then
        begin
          starCi := FindUClass('TPyDict');
          if starCi < 0 then Error('Nil Python: pylib (TPyDict) not loaded');
          ProcParamRecId[procIdx * MAX_PROC_PARAMS + mKwIdx] :=
            REC_UCLASS_BASE + starCi;
        end;
        { Trailing constant defaults. The shared call path already fills
          omitted trailing args from these arrays (symtab.inc), so a NilPy
          method with defaults needs no call-site work of its own. }
        for k := 0 to nparams - 1 do
          if pdefHas[k] and (k < MAX_PROC_PARAMS) then
          begin
            ProcParamHasDefault[procIdx * MAX_PROC_PARAMS + k] := True;
            ProcParamDefaultVal[procIdx * MAX_PROC_PARAMS + k] := pdefVal[k];
            ProcParamDefaultIsStr[procIdx * MAX_PROC_PARAMS + k] := pdefIsStr[k];
            ProcParamDefaultIsNone[procIdx * MAX_PROC_PARAMS + k] := pdefIsNone[k];
            ProcParamDefaultIsFloat[procIdx * MAX_PROC_PARAMS + k] := pdefIsFloat[k];
            ProcParamDefaultSOff[procIdx * MAX_PROC_PARAMS + k] := pdefSOff[k];
            ProcParamDefaultSLen[procIdx * MAX_PROC_PARAMS + k] := pdefSLen[k];
          end;
      end;
      if fieldsOnly then
        { skip method/property registration entirely; fall through to the ctor
          field scan below, which is the only thing the pre-pass wants }
      else if isCtor then
      begin
        k := PyStoredName('create');
        AddUMeth(ci, k, 6, procIdx);
        { mark it a real constructor, like the Pascal declaration does — the
          metaclass and ctor-overload paths test UMthIsCtor, not the name }
        UMthIsCtor[UMthCount - 1] := True;
      end
      else if PyPropAccessorPrefixAt(methodStart) <> '' then
      begin
        { the accessor is registered under its MANGLED name, matching the proc
          RegisterProc just made; AddUMeth otherwise keys on the raw source
          token, leaving the method called `base` while the property looks for
          `__prop_get_base`. }
        AddUMeth(ci, PyStoredName(name), Length(name), procIdx);
        { The PROPERTY is registered HERE, in the pre-pass, and not when the
          decorated def is later parsed: a method defined EARLIER in the class
          may already use `self.base`, and it is parsed before the accessor's
          own def is reached. }
        if not fieldsOnly then
        begin
          pri := FindUProp(ci, origName);
          if pri < 0 then
          begin
            pri := AddUProperty(ci, PyStoredName(origName), Length(origName),
                                Ord(mRet), mRetRec);
            UPropPub[pri] := 1;
          end;
          if PyPropAccessorPrefixAt(methodStart) = '__prop_set_' then
          begin
            UPropWriteMOff[pri] := PyStoredName(name);
            UPropWriteMLen[pri] := Length(name);
          end
          else
          begin
            { the getter defines the property's TYPE }
            UPropReadMOff[pri] := PyStoredName(name);
            UPropReadMLen[pri] := Length(name);
            UPropTk[pri] := Ord(mRet);
            UPropRec[pri] := mRetRec;
          end;
        end;
      end
      else
        AddUMeth(ci, Tokens[i + 1].SOffset, Tokens[i + 1].SLen, procIdx);
      if not fieldsOnly then
      begin
        mmi := UMthCount - 1;
        if not isCtor then
        begin
          { An OVERRIDE takes the slot the parent already assigned to that name,
            so a base-typed reference to a subclass instance dispatches to the
            override. A new name gets the next free slot. }
          slot := -1;
          if UClsParent[ci] >= 0 then
          begin
            inhMmi := FindUMeth(UClsParent[ci],
                                PyRawName(Tokens[i + 1].SOffset, Tokens[i + 1].SLen));
            if inhMmi >= 0 then slot := UMthVirSlot[inhMmi];
          end;
          if slot < 0 then
          begin
            slot := UClsVirtCount[ci];
            UClsVirtCount[ci] := UClsVirtCount[ci] + 1;
          end;
          UMthVirSlot[mmi] := slot;
        end;
      end;
      { `self.name = ...` declares a field — in ANY method, not only the
        constructor. Python creates the attribute wherever the assignment runs,
        and real classes split their setup: songformatter's SettingsFrame builds
        its widgets in `_build_layout`, so restricting this scan to `__init__`
        left `self.canvas` unregistered and every use of it fell through to the
        dynamic-attribute path (no class identity, no keyword arguments, no
        method resolution). The scan only ADDS fields, and a name already
        registered by an earlier method keeps its first type. }
      begin
        while (j < bodyEnd) and (Tokens[j].Kind <> tkIndent) do Inc(j);
        Inc(j);
        while (j + 4 < bodyEnd) and (Tokens[j].Kind <> tkDedent) do
        begin
          { Both `self.NAME = expr` and `self.NAME: ann = expr` declare a
            field. The annotated form used to be invisible here — the match
            required '=' at j+3 — so a class that annotates its ctor fields
            (the idiomatic Python form, and the one the uforth VM uses)
            registered NO fields at all and every later `self.x` mis-resolved
            against an empty class. }
          fldAnn := -1;
          fldSig := -1;
          if (Tokens[j].Kind = tkIdent) and (GetTokenStr(j) = 'self') and
             (Tokens[j + 1].Kind = tkDot) and (Tokens[j + 2].Kind = tkIdent) then
          begin
            if Tokens[j + 3].Kind = tkAssign then fldAnn := 0
            else if Tokens[j + 3].Kind = tkColon then fldAnn := j + 4;
          end;
          if fldAnn >= 0 then
          begin
            if fldAnn > 0 then
            begin
              { annotated: the annotation IS the type, exactly as for a
                dataclass field — same PyAnnTypeAt grammar (Optional/Any/
                List/Callable/forward refs). }
              k2 := fldAnn;
              tk := PyAnnTypeAt(k2);
              fldSig := PyAnnLastProcSig;
              fldRec := REC_NONE;
              if (tk = tyClass) and (PyAnnLastCi >= 0) then
                fldRec := REC_UCLASS_BASE + PyAnnLastCi;
            end
            else
            begin
              rhsAt := j + 4;
              { A QUALIFIED construction first — `self.canvas = tk.Canvas(root)`.
                Reading the type off the FIRST token would resolve the module
                alias `tk`, and a class may well be named for it (tkinter's own
                `Tk` root window, matched case-insensitively): the field was then
                recorded as a Tk, so `self.canvas.create_text(...)` found no such
                method and fell through to the dynamic-attribute path — which
                cannot bind keyword arguments. }
              tk := tyUnknown;
              fldRec := REC_NONE;
              if (rhsAt + 3 < bodyEnd) and (Tokens[rhsAt].Kind = tkIdent) and
                 (Tokens[rhsAt + 1].Kind = tkDot) and (Tokens[rhsAt + 2].Kind = tkIdent) and
                 (Tokens[rhsAt + 3].Kind = tkLParen) and
                 (FindUClass(GetTokenStr(rhsAt + 2)) >= 0) then
              begin
                tk := tyClass;
                fldRec := REC_UCLASS_BASE + FindUClass(GetTokenStr(rhsAt + 2));
              end;
              { A bare identifier that names a PARAMETER of this method is a
                VALUE, and that reading has to win before the type scanners see
                it. PyTypeFromTokenIndex maps an identifier that names a class
                to tyClass, case-INSENSITIVELY (Pascal rules), so in

                    class Node:
                        def __init__(self, node: int):
                            self.node = node

                the right-hand `node` matched the class `Node` and the field was
                registered as an instance of its own class. `str(self.node)`
                then took the object route and dispatched __str__ on the
                integer, which SEGFAULTED — with the name being the only
                trigger, so the identical class called `A` with a field `v` was
                fine (bug-nilpy-str-of-object-segfaults-when-dunder-builds-a-
                string). Any field whose name matches ANY class name, not only
                its own, hit it.

                Order only: a right-hand side that is not a parameter still
                falls through to exactly the scanners it used before. }
              if (tk = tyUnknown) and (Tokens[rhsAt].Kind = tkIdent) then
              begin
                rhsName := GetTokenStr(rhsAt);
                tk := PyHeaderParamType(methodStart, j, rhsName);
                fldSig := PyAnnLastProcSig;
                fldRec := PyHeaderParamRec(methodStart, j, rhsName);
              end;
              if tk = tyUnknown then
              begin
                tk := PyTypeFromTokenIndex(rhsAt);
                fldRec := PyRecFromTokenIndex(rhsAt);
              end;
              if tk = tyUnknown then
              begin
                { Anything richer than a literal or a bare parameter — a list
                  literal (`self.base_stack = [10]`), a call, a construction.
                  One scanner already knows how to type an expression; reuse
                  it rather than erroring or growing a second half-scanner
                  here. }
                k2 := rhsAt;
                while (k2 < bodyEnd) and
                      not (Tokens[k2].Kind in [tkNewline, tkDedent]) do Inc(k2);
                tk := PyInferExprType(rhsAt, k2);
                if (tk = tyClass) and (PyInferLastCi >= 0) then
                  fldRec := REC_UCLASS_BASE + PyInferLastCi;
              end;
            end;
            if tk = tyUnknown then
            begin
              { Assigned from a bare ctor PARAMETER that carries no annotation:
                `def __init__(self, parent, on_next)` then `self.on_next =
                on_next`. Python does not require the annotation and neither can
                we — that is the shape of an ordinary class, and erroring here
                rejected whole modules over it (songformatter's FormatText).
                The field takes the variant type, which is what an unannotated
                LOCAL already gets, so the value keeps its runtime tag.

                Only for that case: a right-hand side the scanners could not
                type at all still errors, because guessing there would hide a
                real mistake. }
              if ((Tokens[j + 4].Kind = tkIdent) and
                  PyHeaderHasParam(methodStart, j, GetTokenStr(j + 4))) or
                 (Tokens[j + 4].Kind = tkNil) then
              begin
                { ...or assigned None outright: `self.file_path = None`, which is
                  how Python declares a field that gets a value later. There is
                  no type to read off None, and demanding an annotation for it
                  rejected the class. Variant, so the tag is whatever is stored
                  next. }
                tk := tyVariant;
                fldRec := REC_NONE;
                fldSig := -1;
              end
              else if not isCtor then
                { OUTSIDE the constructor an unreadable right-hand side is not a
                  diagnostic: `self.items = self.load()` in a helper is ordinary
                  Python, and the field is already declared (or will be) where
                  its type IS readable. The variant keeps the runtime tag; only
                  the ctor, where a field is normally introduced, still insists
                  on something it can type. }
                tk := tyVariant
              else
                ErrorAt(Tokens[j].Line,
                        'Nil Python: cannot infer the type of field self.'
                        + GetTokenStr(j + 2) + ' - annotate it (self.'
                        + GetTokenStr(j + 2) + ': int = ...)');
            end;
            { see the dataclass branch: str fields are managed, not string[N] }
            if tk = tyString then tk := tyAnsiString;
            if tk <> tyClass then fldRec := REC_NONE;
            if FindUField(ci, GetTokenStr(j + 2)) < 0 then
            begin
              sz := TypeSize(tk);
              curOff := AlignTo(curOff, TypeAlign(tk));
              { AddUField reads LastTypeProcSig for a procedural field, which is
                what makes `w.native(vm)` lower to an indirect call rather than
                "field is not callable" (feature-nilpy-function-values). }
              LastTypeProcSig := fldSig;
              AddUField(ci, Tokens[j + 2].SOffset, Tokens[j + 2].SLen, curOff, Ord(tk), fldRec);
              LastTypeProcSig := -1;
              Inc(curOff, sz);
            end;
          end;
          Inc(j);
        end;
      end;
    end;
    Inc(i);
  end;
  if isDC and not fieldsOnly then
  begin
    { Synthesize the create ctor: self + one param per field, in order. }
    if UClsFCount[ci] > 15 then
      Error('Nil Python: too many dataclass fields for the ctor');
    pnames[0] := 'self'; ptypes[0] := tyClass;
    nparams := 1;
    for k := UClsFBase[ci] to UClsFBase[ci] + UClsFCount[ci] - 1 do
    begin
      pnames[nparams] := PyRawName(UFldNOff[k], UFldNLen[k]);
      ptypes[nparams] := IntToTypeKind(UFldTk[k]);
      Inc(nparams);
    end;
    fullName := PyRawName(UClsNOff[ci], UClsNLen[ci]);
    AppendChar(fullName, '.');
    name := 'create';
    for k := 1 to Length(name) do AppendChar(fullName, name[k]);
    procIdx := RegisterProc(fullName, False, tyInteger, nparams, pnames, ptypes);
    k := PyStoredName('create');
    AddUMeth(ci, k, 6, procIdx);
  end;
  UClsSize_[ci] := AlignTo(curOff, align);
  { RTTI backlink word (VMT-8) + LAYOUT backlink word (VMT-16) before the VMT —
    same layout the Pascal path reserves, so an instance can reach its class RTTI
    at [[instance+0] - 8] and its managed-field layout at [[instance+0] - 16].
    Keep the two in step. }
  for i := 0 to 15 do
  begin
    Data[DataLen] := 0;
    Inc(DataLen);
  end;
  UClsVMTOffset[ci] := DataLen;
  for i := 0 to UClsVirtCount[ci] * 8 - 1 do
  begin
    Data[DataLen] := 0;
    Inc(DataLen);
  end;
  for i := UClsMBase[ci] to UClsMBase[ci] + UClsMCount[ci] - 1 do
    if UMthVirSlot[i] >= 0 then
    begin
      MethodFixups[MethodFixCount].DataPos := UClsVMTOffset[ci] + UMthVirSlot[i] * 8;
      MethodFixups[MethodFixCount].ProcIdx := UMthProc_[i];
      Inc(MethodFixCount);
    end;
  { INHERITED slots this class does not override still need an entry: the VMT is
    per-class and starts zeroed, so an un-filled slot is a call through NIL. Walk
    the ancestor chain nearest-first and take the first method holding the slot. }
  for slot := 0 to UClsVirtCount[ci] - 1 do
  begin
    inhMmi := -1;
    for i := UClsMBase[ci] to UClsMBase[ci] + UClsMCount[ci] - 1 do
      if UMthVirSlot[i] = slot then inhMmi := i;
    if inhMmi < 0 then
    begin
      k := UClsParent[ci];
      while (k >= 0) and (inhMmi < 0) do
      begin
        for i := UClsMBase[k] to UClsMBase[k] + UClsMCount[k] - 1 do
          if UMthVirSlot[i] = slot then inhMmi := i;
        k := UClsParent[k];
      end;
      if inhMmi >= 0 then
      begin
        MethodFixups[MethodFixCount].DataPos := UClsVMTOffset[ci] + slot * 8;
        MethodFixups[MethodFixCount].ProcIdx := UMthProc_[inhMmi];
        Inc(MethodFixCount);
      end;
    end;
  end;
end;

procedure PyParseMethod(ci: Integer);
var savedHoist: Integer; clsAttrSeq: Integer;
    origName, name, fullName: AnsiString; procIdx, i, idx, nparams, savedSC, savedFS,
    savedSelf, patchPos, bodyNode, bodyStart, annIdx: Integer; pnames: array[0..15] of AnsiString;
    ptypes: array[0..15] of TTypeKind; pcis: array[0..15] of Integer;
    psigs: array[0..15] of Integer;   { Callable signature per parameter, or -1 }
    isCtor: Boolean; isKwP: Boolean; starCi: Integer;
    savedNest, savedTok, savedLam: Integer; savedPfx, savedPfx2: AnsiString;
begin
  savedHoist := PyHoistHead;
  Expect(tkFunction, 'def');
  origName := CurTok.SVal; name := PyMethodName(origName);
  { same mangling the pre-pass applied. TokPos-2 is the `def`, since CurTok is
    the name that follows it. }
  if PyPropAccessorPrefixAt(TokPos - 2) <> '' then
    name := PyPropAccessorPrefixAt(TokPos - 2) + origName;
  Next;
  isCtor := name = 'create';
  Expect(tkLParen, '(');
  nparams := 0;
  while CurTok.Kind <> tkRParen do
  begin
    { `*` / `*args` / `**kwargs` — mirrors the member pre-pass above; the two
      must produce the same parameter list or the frame and the registered
      signature disagree. }
    if CurTok.Kind = tkStar then
    begin
      Next;
      if CurTok.Kind = tkComma then     { bare `*`: keyword-only marker }
      begin
        Next;
        Continue;
      end;
      isKwP := CurTok.Kind = tkStar;
      if isKwP then Next;
      pnames[nparams] := CurTok.SVal; Next;
      if CurTok.Kind = tkColon then
      begin
        annIdx := TokPos - 1;
        Inc(annIdx);
        PyAnnTypeAt(annIdx);
        TokPos := annIdx;
        Next;
      end;
      if isKwP then starCi := FindUClass('TPyDict')
      else starCi := FindUClass('TPyList');
      if starCi < 0 then Error('Nil Python: pylib (TPyList/TPyDict) not loaded');
      ptypes[nparams] := tyClass;
      pcis[nparams] := starCi;
      psigs[nparams] := -1;
      Inc(nparams);
      if not Eat(tkComma) then break;
      Continue;
    end;
    pnames[nparams] := CurTok.SVal; Next;
    psigs[nparams] := -1;
    if (nparams = 0) and (pnames[nparams] = 'self') then
    begin ptypes[nparams] := tyClass; pcis[nparams] := ci; end
    else if CurTok.Kind <> tkColon then
    begin
      { UNANNOTATED parameter -> Any (variant); must match the pre-pass. }
      ptypes[nparams] := tyVariant; pcis[nparams] := -1;
      if CurTok.Kind = tkAssign then
      begin
        Next;
        if CurTok.Kind = tkMinus then Next;
        Next;
      end;
    end
    else
    begin
      Expect(tkColon, ':');
      { PyAnnTypeAt, bridged onto the cursor, so the header accepts exactly
        what the class pre-pass accepted — List/Dict/set/Optional/Callable.
        The two must agree: the pre-pass decides the registered signature and
        this decides the frame, and a disagreement is a silent ABI mismatch. }
      annIdx := TokPos - 1;
      ptypes[nparams] := PyAnnTypeAt(annIdx);
      pcis[nparams] := PyAnnLastCi;
      { A `Callable[...]` parameter carries a procedural SIGNATURE, and without
        it the name is not callable inside the body — the def path has recorded
        this since function values landed, the METHOD path never did, so
        `def analyze(self, chord_to_notes: Callable[[str], list[str]])` compiled
        but `chord_to_notes(chord)` did not parse (feature-nilpy-function-values,
        the method half). }
      psigs[nparams] := PyAnnLastProcSig;
      TokPos := annIdx;
      Next;
      if CurTok.Kind = tkAssign then
      begin
        { the default VALUE was recorded by the pre-pass, which is what the
          call path reads; here it only has to be stepped over }
        Next;
        if CurTok.Kind = tkMinus then Next;
        Next;
      end;
    end;
    Inc(nparams);
    if not Eat(tkComma) then break;
  end;
  Expect(tkRParen, ')');
  { the annotation is OPTIONAL — see PyParseDefHeader for why the default here
    has to match the pre-pass exactly }
  if CurTok.Kind = tkMinus then
  begin
    Expect(tkMinus, '- in ->'); Expect(tkGt, '> in ->');
  { `-> None` on a NON-ctor method: accept it. Only the ctor was allowed to
    say None, so an ordinary `def m(self) -> None:` died in PyParseType with
    "expected type annotation" — while the identical top-level def has worked
    since day one (PyParseDef's isProc path). PyMethodRetType already maps the
    None annotation to tyInteger for registration, so nothing downstream
    changes; the header parse was simply stricter than the pre-pass. }
    if isCtor then Expect(tkNil, 'None')
    else if CurTok.Kind = tkNil then Next
    else PyParseType;
  end
  { An UNANNOTATED `__init__` is ordinary Python — `def __init__(self, parent):`
    is what songformatter's SettingsEditor writes — and it registers exactly as
    the annotated form does: PyMethodRetType yields tyUnknown for both, which
    the member pre-pass maps to tyInteger, so accepting it here changes no
    signature. The requirement was a syntax rule with nothing behind it. }
  Expect(tkColon, ':'); Expect(tkNewline, 'newline'); Expect(tkIndent, 'indent');
  bodyStart := TokPos - 1;
  fullName := PyRawName(UClsNOff[ci], UClsNLen[ci]); AppendChar(fullName, '.');
  for i := 1 to Length(name) do AppendChar(fullName, name[i]);
  procIdx := FindProc(fullName);
  { An OVERRIDE's parameters take the BASE method's types — the member pre-pass
    did the same when it registered this signature (see PyRegisterClassMembers),
    and the two passes MUST agree or the frame disagrees with the signature.
    Python overrides carry no annotations, so without this
    `def optionxform(self, s)` bound a variant parameter to an AnsiString slot
    and the inherited caller read the wrong kind. }
  if procIdx >= 0 then
    for i := 1 to nparams - 1 do
      if i < Procs[procIdx].ParamCount then ptypes[i] := Procs[procIdx].Params[i].TypeKind;
  savedSC := SymCount; savedFS := FrameSize; savedSelf := CurSelfClass;
  FrameSize := 0; CurProc := procIdx; CurSelfClass := REC_UCLASS_BASE + ci;
  Procs[procIdx].ScopeBase := SymCount;
  for i := 0 to nparams - 1 do
  begin
    idx := AllocParam(pnames[i], ptypes[i], ptypes[i] = tyVariant, False);
    Procs[procIdx].Params[i].SymIdx := idx;
    Procs[procIdx].Params[i].IsRef := ptypes[i] = tyVariant;
    if i < MAX_PROC_PARAMS then
      ProcParamIsConst[procIdx * MAX_PROC_PARAMS + i] := ptypes[i] = tyVariant;
    if (ptypes[i] = tyClass) and (pcis[i] >= 0) then
      Syms[idx].RecName := REC_UCLASS_BASE + pcis[i];
    if psigs[i] >= 0 then SymProcSig[idx] := psigs[i];   { Callable parameter }
  end;
  if not isCtor then
  begin
    { see the note in the def path — a Python local may be named `result` }
    idx := AllocVar('$pyresult', Procs[procIdx].RetType);
    Procs[procIdx].RetSymIdx := idx;
    { skLocal is what gates the prologue zero-init (IR_ZERO_SYM checks it), and
      the Pascal path sets it. Without it a MANAGED Result slot held stack
      garbage, so the first `Result := ...` released a wild handle -- a method
      returning str segfaulted, and only when the layout happened to leave
      non-zero there, which is why it needed a ctor to reproduce
      (bug-nilpy-method-returning-str-garbage). }
    Syms[idx].Kind := skLocal;
    if RetViaHiddenDest(Procs[procIdx].RetType) then
    begin
      idx := AllocVar('', tyPointer);
      ProcAggregateDestSym[procIdx] := idx;
    end;
  end;
  { Methods used to have NO local pre-pass at all: a method local took the type
    of its FIRST assignment and never widened, so `x = 1` then `x = "s"` in a
    method was an Integer local silently holding a string handle — the same
    def/method asymmetry that made `-> str` methods a separate bug from `-> str`
    defs. One pre-pass now serves both. }
  PyCollectLocalsAST(bodyStart);
  PyDbgDumpLocals(Procs[procIdx].Name);
  for i := 0 to PyLocalCount - 1 do
    if PyProgSym(PyLocals[i].Name) < 0 then
    begin
      idx := AllocVar(PyLocals[i].Name, PyLocals[i].TypeKind);
      if (PyLocals[i].TypeKind = tyClass) and (PyLocals[i].RecCi >= 0) then
        Syms[idx].RecName := REC_UCLASS_BASE + PyLocals[i].RecCi;
    end;
  Procs[procIdx].BodyAddr := CodeLen;
  { A method may contain nested defs (`def helper(): ...` inside it). They queue
    their bodies just like a plain def's do, so the method must set the nest
    prefix (for capture + qualified registration) and drain the queue after its
    epilogue — otherwise the shells stay forward-declared and never link
    (feature-nilpy-nested-defs-in-methods). }
  savedPfx := PyNestPrefix; PyNestPrefix := fullName;
  savedNest := PyPendNestCount;
  savedLam := PyPendLamCount;
  patchPos := EmitProcPrologue; Procs[procIdx].FramePatch := patchPos;
  EmitAggregateDestStash(procIdx);
  PyEmitParamSpills(procIdx, nparams);
  PyInitVariantLocals(Procs[procIdx].ScopeBase);
  { Managed locals must start nil, exactly as in the Pascal routine body — a
    NilPy string local is a MANAGED AnsiString now, and without this the first
    assignment released stale stack bytes (`decq -0x10(%rax)` on garbage). }
  EmitManagedLocalsZeroInit(Procs[procIdx].ScopeBase);
  bodyNode := PyParseBlock; Expect(tkDedent, 'dedent');
  bodyNode := PyPrependResultZero(procIdx, bodyNode);
  { A CONSTRUCTOR applies the class attributes first — see PyClassAttrInitSeq.
    Prepended to the body so `__init__`'s own writes win, as in Python. }
  if isCtor and (nparams > 0) then
  begin
    clsAttrSeq := PyClassAttrInitSeq(ci, Procs[procIdx].Params[0].SymIdx);
    if clsAttrSeq >= 0 then bodyNode := PySeqAppend(clsAttrSeq, bodyNode);
  end;
  CompileAST(bodyNode); EmitProcEpilog(Procs[procIdx].RetSymIdx); PatchProcPrologue(patchPos, FrameSize);
    ProcBodyEnd[procIdx] := CodeLen;   { DWARF -g — see PyParseDef's note }
  ProcDbgMain[procIdx] := DbgTokIsDebuggable(TokPos);
  if DebugInfo and ProcDbgMain[procIdx] then DbgCaptureProcLocals(procIdx);
  SymRollbackTo(savedSC); FrameSize := savedFS; CurProc := -1; CurSelfClass := savedSelf;
  { Whatever the BODY left queued names this method's locals, which the
    rollback above has just discarded. The queue is global, so the residue was
    flushed into the next statement — at module level that is the import-time
    body, which then referenced a symbol that no longer existed. A body's own
    hoists are flushed by its statement loop; the rest is stale by
    construction. Same rule as PyParseDef. }
  PyHoistHead := savedHoist;
  PyNestPrefix := savedPfx;
  { drain the nested-def bodies this method queued — each re-enters PyParseDef at
    its own `def` token under the qualifier it registered with. }
  while PyPendNestCount > savedNest do
  begin
    Dec(PyPendNestCount);
    savedTok := TokPos;
    savedPfx2 := PyNestPrefix;
    PyNestPrefix := PyPendNestPfx[PyPendNestCount];
    TokPos := PyPendNestTok[PyPendNestCount];
    Next;
    PyParseDef;
    PyNestPrefix := savedPfx2;
    TokPos := savedTok - 1;
    Next;
  end;
  PyDrainPendingLambdas(savedLam);
end;

{ Emit the synthesized @dataclass ctor body: spill params, then
  self.field_i := param_i for every field, via the ordinary AST path. }
{ An AST node for type tk's zero value, or -1 if tk isn't one of the plain
  scalar kinds this covers (see PyPrependResultZero). }
function PyZeroLitFor(tk: TTypeKind): Integer;
var node: Integer;
begin
  case tk of
    tyInteger, tyInt8, tyUInt8, tyInt16, tyUInt16, tyInt32, tyUInt32,
    tyInt64, tyUInt64, tyNativeInt, tyNativeUInt:
      begin
        node := AllocNode(AN_INT_LIT);
        ASTIVal[node] := 0;
        ASTTk[node] := Ord(tk);
        Result := node;
      end;
    tyBoolean:
      begin
        node := AllocNode(AN_BOOL_LIT);
        ASTIVal[node] := 0;
        ASTTk[node] := Ord(tyBoolean);
        Result := node;
      end;
    tySingle, tyDouble:
      begin
        node := AllocNode(AN_FLOAT_LIT);
        ASTIVal[node] := 0;
        ASTTk[node] := Ord(tk);
        Result := node;
      end;
  else
    Result := -1;
  end;
end;

{ Zero (or otherwise deterministically init) a Result slot at body entry.

  A method's Result is allocated by the class-member pre-pass, where CurProc is
  not yet set, so AllocVar marks it skGlobal -- and IR_ZERO_SYM's codegen only
  zeroes skLocal. The slot therefore kept stale stack bytes, and the first
  `Result := <str>` released that garbage as if it were a string handle:
  `decq -0x10(%rax)` on a wild pointer. It only reproduced when the frame
  happened to hold something non-zero there, which is why a class needed a
  constructor before `-> str` crashed (bug-nilpy-method-returning-str-garbage).

  Emitting an ordinary AN_VAR_DECL at the head of the body reuses the normal
  local zero-init path for the managed kinds (AnsiString/Variant).

  A plain SCALAR Result (Integer/Boolean/Float) that falls off the end with no
  explicit return used to be left alone here on the theory that reading stale
  stack bytes was "harmless" — measured (not assumed) to be false: it is
  genuine uninitialized-read undefined behaviour, and an unrelated later
  change (a sibling proc using more registers before this one runs) turned a
  reliably-looking `0` into an arbitrary garbage integer with no visible cause
  (bug-nilpy-implicit-return-is-0-and-math-floor-returns-a-float). An explicit
  `Result := 0`-shaped assignment closes exactly that gap, prepended the same
  way the managed-kind AN_VAR_DECL is. }
function PyPrependResultZero(procIdx, bodyNode: Integer): Integer;
var rs, declNode, seqNode, rtk, zeroNode, assignNode: Integer;
begin
  PyPrependResultZero := bodyNode;
  rs := Procs[procIdx].RetSymIdx;
  if rs < 0 then Exit;
  rtk := Ord(Syms[rs].TypeKind);
  if (rtk = Ord(tyAnsiString)) or (rtk = Ord(tyVariant)) then
  begin
    Syms[rs].Kind := skLocal;      { it IS a frame slot; the pre-pass mislabelled it }
    declNode := AllocNode(AN_VAR_DECL);
    ASTIVal[declNode] := rs;
    ASTLeft[declNode] := -1;
    seqNode := AllocNode(AN_SEQ);
    ASTLeft[seqNode] := declNode;
    ASTRight[seqNode] := AllocNode(AN_SEQ);
    ASTLeft[ASTRight[seqNode]] := bodyNode;
    PyPrependResultZero := seqNode;
    Exit;
  end;
  zeroNode := PyZeroLitFor(Syms[rs].TypeKind);
  if zeroNode < 0 then Exit;
  Syms[rs].Kind := skLocal;
  assignNode := AllocNode(AN_ASSIGN);
  ASTLeft[assignNode] := PyMakeIdent(rs);
  ASTRight[assignNode] := zeroNode;
  seqNode := AllocNode(AN_SEQ);
  ASTLeft[seqNode] := assignNode;
  ASTRight[seqNode] := AllocNode(AN_SEQ);
  ASTLeft[ASTRight[seqNode]] := bodyNode;
  PyPrependResultZero := seqNode;
end;

procedure PyEmitDataclassCtor(ci: Integer);
var fullName, name: AnsiString;
    procIdx, i, k, idx, nparams, savedSC, savedFS, savedSelf, patchPos: Integer;
    selfNode, fieldNode, paramNode, assignNode, seqHead: Integer;
begin
  fullName := PyRawName(UClsNOff[ci], UClsNLen[ci]);
  AppendChar(fullName, '.');
  name := 'create';
  for k := 1 to Length(name) do AppendChar(fullName, name[k]);
  procIdx := FindProc(fullName);
  if procIdx < 0 then Error('Nil Python: internal: dataclass ctor not registered');
  savedSC := SymCount; savedFS := FrameSize; savedSelf := CurSelfClass;
  FrameSize := 0; CurProc := procIdx; CurSelfClass := REC_UCLASS_BASE + ci;
  Procs[procIdx].ScopeBase := SymCount;
  nparams := Procs[procIdx].ParamCount;
  for i := 0 to nparams - 1 do
  begin
    if i = 0 then name := 'self'
    else name := PyRawName(UFldNOff[UClsFBase[ci] + i - 1],
                           UFldNLen[UClsFBase[ci] + i - 1]);
    idx := AllocParam(name, Procs[procIdx].Params[i].TypeKind, False, False);
    Procs[procIdx].Params[i].SymIdx := idx;
    if i = 0 then Syms[idx].RecName := REC_UCLASS_BASE + ci
    else if Procs[procIdx].Params[i].TypeKind = tyClass then
      Syms[idx].RecName := UFldRec_[UClsFBase[ci] + i - 1];
  end;
  Procs[procIdx].BodyAddr := CodeLen;
  patchPos := EmitProcPrologue; Procs[procIdx].FramePatch := patchPos;
  PyEmitParamSpills(procIdx, nparams);
  seqHead := -1;
  for i := 1 to nparams - 1 do
  begin
    k := UClsFBase[ci] + i - 1;
    selfNode := AllocNode(AN_IDENT);
    ASTIVal[selfNode] := Procs[procIdx].Params[0].SymIdx;
    ASTTk[selfNode] := Ord(tyClass);
    fieldNode := AllocNode(AN_FIELD);
    ASTLeft[fieldNode] := selfNode;
    ASTSOffset[fieldNode] := UFldNOff[k];
    ASTSLen[fieldNode] := UFldNLen[k];
    ASTTk[fieldNode] := UFldTk[k];
    paramNode := PyMakeIdent(Procs[procIdx].Params[i].SymIdx);
    assignNode := AllocNode(AN_ASSIGN);
    ASTLeft[assignNode] := fieldNode;
    ASTRight[assignNode] := paramNode;
    seqHead := PySeqAppend(seqHead, assignNode);
  end;
  CompileAST(seqHead);
  EmitProcEpilog(Procs[procIdx].RetSymIdx);
  PatchProcPrologue(patchPos, FrameSize);
    ProcBodyEnd[procIdx] := CodeLen;   { DWARF -g — see PyParseDef's note }
  ProcDbgMain[procIdx] := DbgTokIsDebuggable(TokPos);
  if DebugInfo and ProcDbgMain[procIdx] then DbgCaptureProcLocals(procIdx);
  SymRollbackTo(savedSC); FrameSize := savedFS; CurProc := -1; CurSelfClass := savedSelf;
end;

{ FIELD pre-pass. PyRegisterClassShells registers class NAMES only, and
  PyCollectModuleLocals runs before the main loop that parses class bodies — so
  without this every class has zero fields during module-local inference and a
  module-level `x = o.inner` cannot learn the field's class
  (bug-nilpy-class-typed-field-loses-identity).

  Walks the raw token stream for `class NAME ...:` headers, locates each body
  the same way PyParseClass does (the tkIndent after the header, then
  PyFindBodyEnd) and registers that class's FIELDS via the shared
  PyRegisterClassMembers in fieldsOnly mode — so the field rules live in one
  place. isDC is read off a preceding @dataclass decorator.

  The real pass later resets each class's field window and rebuilds it, so
  these entries are orphaned rather than duplicated. }
procedure PyRegisterClassFieldsPrepass;
var i, j, k, ci, bs, be, depth, baseCi: Integer;
    isDC, hoist: Boolean;
begin
  i := PyScanLo;
  while i < MainProgramTokCount - 2 do
  begin
    if (Tokens[i].Kind = tkClass) and (Tokens[i + 1].Kind = tkIdent) then
    begin
      ci := FindUClass(GetTokenStr(i + 1));
      if ci >= 0 then
      begin
        { @dataclass on the line(s) before the header }
        isDC := False;
        j := i - 1;
        while (j >= 1) and (Tokens[j].Kind in [tkNewline, tkIndent, tkDedent]) do Dec(j);
        if (j >= 1) and (Tokens[j].Kind = tkIdent) and
           CaseEqual(GetTokenStr(j), 'dataclass') and (Tokens[j - 1].Kind = tkAt) then
          isDC := True;
        { The FULL registration (methods included) needs the parent link set
          first — a subclass's field offsets and virtual slots continue the
          parent's layout. Resolve the base list here, exactly as PyParseClass
          does (including the auto-shelled Exception base). If the base cannot
          be resolved yet, fall back to fields-only and let PyParseClass do
          the full run as before. }
        hoist := True;
        if Tokens[i + 2].Kind = tkLParen then
        begin
          baseCi := -1;
          if Tokens[i + 3].Kind = tkIdent then
          begin
            baseCi := FindUClass(GetTokenStr(i + 3));
            if (baseCi < 0) and CaseEqual(GetTokenStr(i + 3), 'Exception') then
            begin
              k := PyStoredName('Exception');
              AddUClass(k, 9);
              baseCi := FindUClass('Exception');
            end;
          end;
          if baseCi >= 0 then
            UClsParent[ci] := baseCi
          else
            hoist := False;
        end;
        { skip the header to its tkIndent, honouring a parenthesised base list }
        j := i + 2;
        depth := 0;
        while j < MainProgramTokCount do
        begin
          if Tokens[j].Kind = tkLParen then Inc(depth)
          else if Tokens[j].Kind = tkRParen then Dec(depth)
          else if (Tokens[j].Kind = tkIndent) and (depth = 0) then Break;
          Inc(j);
        end;
        if j < MainProgramTokCount then
        begin
          bs := j + 1;   { first BODY token, matching PyParseClass's bodyStart
                           (it takes TokPos-1 after Expect(tkIndent)) }
          be := PyFindBodyEnd(bs);
          { Full members when the parent is settled: methods registered here
            let the module-collect trial parse resolve `x = obj.method()`.
            PyParseClass skips its own (second) full run via the flag — the
            append-only PyDc* default tables must be filled exactly once. }
          PyRegisterClassMembers(ci, bs, be, isDC, not hoist);
          if hoist then PyMembersHoisted[ci] := True;
        end;
      end;
    end;
    Inc(i);
  end;
end;

procedure PyParseClass(isDC: Boolean);
var ci, bodyStart, bodyEnd, baseCi, k: Integer;
    propName: AnsiString;
begin
  Expect(tkClass, 'class');
  ci := FindUClass(CurTok.SVal); Next;
  if CurTok.Kind = tkLParen then
  begin
    { base class: class Name(Base): — Exception is auto-registered as an
      empty shell (the try/except semantics rung is its own ticket) }
    Next;
    if CurTok.Kind <> tkIdent then Error('Nil Python: expected a base class name');
    { A DOTTED base — `class Cfg(configparser.ConfigParser)` — names the module
      it came from. Unit scope is flat here (an `import X` is a `uses X`, and its
      symbols resolve unqualified), so the qualifier is consumed and the LAST
      segment is the class. Without this, subclassing anything imported was
      impossible: the parser took `configparser` as the base name and reported
      it unknown. }
    while (TokPos < TokCount) and (Tokens[TokPos].Kind = tkDot) do
    begin
      Next;                { onto the '.' }
      Next;                { onto the segment after it }
      if CurTok.Kind <> tkIdent then
        Error('Nil Python: expected a class name after . in the base class');
    end;
    baseCi := FindUClass(CurTok.SVal);
    if (baseCi < 0) and CaseEqual(CurTok.SVal, 'Exception') then
    begin
      k := PyStoredName('Exception');
      AddUClass(k, 9);
      baseCi := FindUClass('Exception');
    end;
    if baseCi < 0 then
      Error('Nil Python: unknown base class ' + CurTok.SVal);
    UClsParent[ci] := baseCi;
    Next;
    Expect(tkRParen, ')');
  end;
  Expect(tkColon, ':'); Expect(tkNewline, 'newline'); Expect(tkIndent, 'indent');
  bodyStart := TokPos - 1; bodyEnd := PyFindBodyEnd(bodyStart);
  { The member pre-pass may have already done the FULL registration (methods
    + fields + PyDc* defaults) so the module-collect trial parse could resolve
    method calls; re-running it would duplicate the append-only defaults and
    re-register every method proc. }
  if not PyMembersHoisted[ci] then
    PyRegisterClassMembers(ci, bodyStart, bodyEnd, isDC, False);
  if isDC and (ci < PY_MAX_DC_FIELDS) then PyDcClassIsDc[ci] := True;
  PySkipNewlines;
  while CurTok.Kind <> tkDedent do
  begin
    if CurTok.Kind = tkString then
    begin
      { class docstring }
      Next;
      PySkipNewlines;
    end
    else if PyIsIdent('pass') then
    begin
      { `class Foo(Exception): pass` -- a whole-body `pass` (no fields, no
        methods) fell into the unconditional PyParseMethod branch below and
        errored "expected def"; every OTHER `pass` site in the grammar already
        has its own skip (see the statement-level one a few hundred lines up).
        bug-nilpy-class-with-pass-body-fails-to-parse }
      Next;
      PySkipNewlines;
    end
    else if isDC and (CurTok.Kind = tkIdent) then
    begin
      { dataclass field line — already registered; skip to end of line }
      while not (CurTok.Kind in [tkNewline, tkDedent, tkEOF]) do Next;
      PySkipNewlines;
    end
    else if (CurTok.Kind = tkIdent) and (TokPos < TokCount) and
            (Tokens[TokPos].Kind = tkAssign) then
    begin
      { class-attribute line. A LITERAL one is already a folded constant from
        the pre-pass and only has to be stepped over; anything else — `mode =
        Inner()` — is evaluated HERE, at the point the class statement runs,
        which is where Python evaluates a class body too. The value goes into a
        hidden global named after the class and the attribute, and construction
        copies it into the instance field the pre-pass registered, so every
        instance shares the one object. }
      if PyClsAttrExprAhead then PyEmitClassAttrExpr(ci)
      else
      begin
        while not (CurTok.Kind in [tkNewline, tkDedent, tkEOF]) do Next;
      end;
      PySkipNewlines;
    end
    else if CurTok.Kind = tkAt then
    begin
      { @property / @<name>.setter. The accessors were name-mangled and the
        property registered by the member pre-pass, so this only has to consume
        the decorator and parse the def that follows. }
      Next;
      if CurTok.Kind <> tkIdent then
        Error('Nil Python: unsupported decorator inside class (only @property and @<name>.setter)');
      propName := CurTok.SVal;
      Next;
      if CurTok.Kind = tkDot then
      begin
        Next;
        if (CurTok.Kind <> tkIdent) or (LowerCase(CurTok.SVal) <> 'setter') then
          Error('Nil Python: unsupported decorator inside class (only @property and @<name>.setter)');
        Next;
      end
      else if LowerCase(propName) <> 'property' then
        Error('Nil Python: unsupported decorator inside class (only @property and @<name>.setter)');
      PySkipNewlines;
      if CurTok.Kind <> tkFunction then
        Error('Nil Python: @property must be followed by a def');
      PyParseMethod(ci);
      PySkipNewlines;
    end
    else if CurTok.Kind = tkClass then
    begin
      { A class NESTED in a class body — songformatter's render backend declares
        a small `class _BlendModes:` holding two constants, which is how a
        Python file writes an attribute namespace. Parsed as an ordinary class:
        the class namespace is flat here, so the inner one is simply registered
        under its own name and the enclosing body continues.
        (That flatness is the subject of
        decide-unit-local-names-leak-to-global-scope; a nested class SHOULD be
        scoped to its outer one, and today it is not.) }
      PyParseClass(False);
      PySkipNewlines;
    end
    else
    begin
      PyParseMethod(ci);
      PySkipNewlines;
    end;
  end;
  Expect(tkDedent, 'dedent');
  if isDC then PyEmitDataclassCtor(ci);
end;

{ One run of `import` / `from ... import` statements, wherever they appear.
  Extracted from ParsePyProgram's leading-import loop so that an import which is
  NOT at the top of the file is handled by the SAME code. Python allows an import
  anywhere, and songformatter's convertrawtext.py puts a whole block of them
  after a try/except — those were silently IGNORED (no error, no registration),
  which surfaced much later as `undefined variable (tempfile)` at the first use.
  Silently dropping an import is the worst shape a gap can take. }
{ Consume a module path — `reportlab` or `reportlab.pdfgen` — and return the
  UNIT name it maps to: the dots become underscores, so `reportlab.lib.colors`
  is the unit `reportlab_lib_colors` (and, failing that, `mimic_reportlab_lib_
  colors`, which the resolver falls back to). A Pascal unit name cannot hold a
  dot and a package DIRECTORY would buy nothing here, so the mangling is the
  whole of it. rootName gets the first segment, which is what the
  consume-and-defer stdlib checks are about (`import os.path` is as skipped as
  `import os`). feature-nilpy-dotted-package-imports. }
function PyConsumeDottedModule(var rootName: AnsiString): AnsiString;
begin
  rootName := CurTok.SVal;
  Result := CurTok.SVal;
  Next;
  while (CurTok.Kind = tkDot) and (TokPos < TokCount) and
        (Tokens[TokPos].Kind = tkIdent) do
  begin
    Next;
    Result := Result + '_' + CurTok.SVal;
    Next;
  end;
end;

{ A single `import X [as Y]` / `from X import a, b` statement, leaving the
  parser ON the terminating newline. Shares the resolver with PyParseImportRun;
  see the note at the statement-level call site for why the newline matters. }
procedure PyParseOneImport;
var impName, impAlias, impRoot: AnsiString; aStrIdx, realStrIdx: Integer;
begin
  { SoftUnitMissed describes THIS import, and nothing else. It is a global, and
    a soft miss recorded by an earlier one — a module's own `try: from PIL
    import Image / except ImportError:` — used to still be set here: the alias
    for a LATER import was then skipped and its name bound to None, so
    `from tkinter import ttk` left `ttk` unbound and every `ttk.Widget(...)`
    raised at RUN time with no diagnostic. Clear it at the start of each
    import; the fallback-import path sets it again for the block it guards. }
  SoftUnitMissed := False;
  if PyIsIdent('from') then
  begin
    Next;
    if CurTok.Kind <> tkIdent then
      Error('Nil Python: expected a module name after from');
    impName := PyConsumeDottedModule(impRoot);
    if CurTok.Kind <> tkUses then
      Error('Nil Python: expected import after from ' + impName);
    Next;
    if not (CaseEqual(impRoot, 'dataclasses') or CaseEqual(impRoot, 'typing') or
            CaseEqual(impRoot, 'itertools') or CaseEqual(impRoot, 'collections')) then
      ParseUsesUnit(impName);
    while CurTok.Kind = tkIdent do
    begin
      Next;
      if PyIsIdent('as') then
      begin
        Next;
        if CurTok.Kind = tkIdent then Next;
      end;
      if not Eat(tkComma) then Break;
    end;
  end
  else
  begin
    Next;
    while CurTok.Kind = tkIdent do
    begin
      impName := PyConsumeDottedModule(impRoot);
      if not (CaseEqual(impRoot, 'sys') or CaseEqual(impRoot, 'os') or
              CaseEqual(impRoot, 'textwrap') or CaseEqual(impRoot, 'select') or
              CaseEqual(impRoot, 'itertools')) then
        ParseUsesUnit(impName);
      if PyIsIdent('as') then
      begin
        Next;
        if CurTok.Kind <> tkIdent then
          Error('Nil Python: expected a name after `as` in an import');
        aStrIdx := InternStr(LowerCase(CurTok.SVal));
        realStrIdx := InternStr(LowerCase(impName));
        if (UnitAliasCount < MAX_UNIT_ALIASES) and (aStrIdx <> realStrIdx) then
        begin
          UnitAliasName[UnitAliasCount] := aStrIdx;
          UnitAliasReal[UnitAliasCount] := realStrIdx;
          Inc(UnitAliasCount);
        end;
        Next;
      end;
      if not Eat(tkComma) then Break;
    end;
  end;
end;

procedure PyParseImportRun;
var impName, impAlias, impRoot: AnsiString; isCount: Boolean; aStrIdx, realStrIdx, optSym: Integer;
begin
  while (CurTok.Kind = tkUses) or PyIsIdent('from') do
  begin
    if PyIsIdent('from') then
    begin
      Next;
      if CurTok.Kind <> tkIdent then
        Error('Nil Python: expected a module name after from');
      impName := PyConsumeDottedModule(impRoot);
      if CurTok.Kind <> tkUses then
        Error('Nil Python: expected import after from ' + impName);
      Next;
      { itertools is consumed-but-unresolved for now: uforth only needs
        count(); its use sites wall visibly until a shim lands (Track B). }
      { `collections` joins these: the names it exports that we support are
        ordinary pylib symbols (Counter -> pylib's TPyCounter constructors), so
        consuming the from-import is enough — an unsupported name from it walls
        visibly at its use site as an undefined variable, same as itertools. }
      if CaseEqual(impRoot, 'dataclasses') or CaseEqual(impRoot, 'typing') or
         CaseEqual(impRoot, 'itertools') or CaseEqual(impRoot, 'collections') then
      begin
        while CurTok.Kind = tkIdent do
        begin
          isCount := CaseEqual(impRoot, 'itertools') and
                     CaseEqual(CurTok.SVal, 'count');
          if isCount then PyCountAlias := CurTok.SVal;
          Next;
          if PyIsIdent('as') then
          begin
            Next;
            if CurTok.Kind = tkIdent then
            begin
              if isCount then PyCountAlias := CurTok.SVal;
              Next;
            end;
          end;
          if not Eat(tkComma) then Break;
        end;
      end
      else
      begin
        { `from X import a, b` where X is a resolvable UNIT: pull the unit and
          let the names resolve unqualified, which is how `import X` already
          works (unit scope is flat). This is the form real code uses to reach a
          shim — `from configparser import ConfigParser`. An unknown module still
          fails, with the unit resolver's own "unit source not found: X". }
        ParseUsesUnit(impName);
        while CurTok.Kind = tkIdent do
        begin
          { Record the name against the IMPORTING module (ParseUsesUnit has
            restored CurrentUnitIdx by now), so a builtin spelling it shadows
            is shadowed here and nowhere else. `as` rebinds it, so the ALIAS is
            the name in scope. }
          impAlias := CurTok.SVal;
          Next;
          if PyIsIdent('as') then
          begin
            Next;
            if CurTok.Kind = tkIdent then
            begin
              impAlias := CurTok.SVal;
              Next;
            end;
          end;
          { A from-imported name may be a SUBMODULE rather than a value —
            `from reportlab.pdfgen import canvas` then `canvas.Canvas(...)`,
            `from tkinter import ttk` then `ttk.Notebook(...)`. Point the name
            at the unit that answered the import so the qualifier resolves; a
            name that is a plain value never gets qualified, so this is inert
            for it. Skipped when a real unit already carries the name, which is
            the only way this could hijack a genuine qualifier. }
          { …but NOT for a name that is a CLASS: `from tkinter import Canvas`
            imports a class, and the alias table folds case, so it claimed the
            name `canvas` and beat the MODULE of that name imported later by
            `from reportlab.pdfgen import canvas`. Python keeps them apart
            because it is case-sensitive; here the class is the one that is
            certainly not a submodule, so it is the one that does not register. }
          if (UnitAliasCount < MAX_UNIT_ALIASES) and (not SoftUnitMissed) and
             (FindCompiledUnit(impAlias) < 0) and
             (not UnitDeclaresClassExactly(impAlias, FindCompiledUnit(impName))) then
          begin
            UnitAliasName[UnitAliasCount] := InternStr(LowerCase(impAlias));
            UnitAliasReal[UnitAliasCount] := InternStr(LowerCase(impName));
            Inc(UnitAliasCount);
          end;
          { The module did not resolve and we are inside a `try:` whose handler
            will be compiled instead — bind what it would have imported to
            None, so code that references the name COMPILES and fails when it
            RUNS. CPython raises NameError there; either way the failure is at
            use, not at import, which is the whole point of the guard the
            application wraps around such calls (`if not HAVE_PIL: return`).
            A variant global is born VT_EMPTY, which IS None. }
          if SoftUnitMissed then
          begin
            if PyProgSym(impAlias) < 0 then optSym := AllocVar(impAlias, tyVariant);
            PyNoteOptionalMissingName(impAlias);
          end;
          if PyImpNameCount < 256 then
          begin
            PyImpName[PyImpNameCount] := InternStr(LowerCase(impAlias));
            PyImpNameUnit[PyImpNameCount] := CurrentUnitIdx;
            Inc(PyImpNameCount);
          end;
          if not Eat(tkComma) then Break;
        end;
      end;
      PySkipNewlines;
    end
    else
    begin
      Next;
      while CurTok.Kind = tkIdent do
      begin
        { Python stdlib modules without a shim yet: consume-and-defer, use
          sites wall visibly (same policy as itertools above). Everything
          else goes through the unit resolver (sqlite3, C headers, ...). }
        impName := PyConsumeDottedModule(impRoot);
        if CaseEqual(impRoot, 'sys') or CaseEqual(impRoot, 'os') or
           CaseEqual(impRoot, 'textwrap') or CaseEqual(impRoot, 'select') or
           CaseEqual(impRoot, 'itertools') then
          { skip }
        else
          ParseUsesUnit(impName);
        { `import X as Y` — Python's module alias, and the same thing a Pascal
          `uses X as Y` already does (feature-uses-alias-as): register the alias
          with the unit resolver so a `Y.Sym` qualifier resolves onto X's
          symbols. Unqualified names keep working either way, since unit scope
          is flat — the alias only has to make the PREFIX acceptable.
          `import tkinter as tk` is the shape songformatter uses. }
        if PyIsIdent('as') then
        begin
          Next;
          if CurTok.Kind <> tkIdent then
            Error('Nil Python: expected a name after `as` in an import');
          aStrIdx := InternStr(LowerCase(CurTok.SVal));
          realStrIdx := InternStr(LowerCase(impName));
          if (UnitAliasCount < MAX_UNIT_ALIASES) and (aStrIdx <> realStrIdx) then
          begin
            UnitAliasName[UnitAliasCount] := aStrIdx;
            UnitAliasReal[UnitAliasCount] := realStrIdx;
            Inc(UnitAliasCount);
          end;
          Next;
        end;
        if not Eat(tkComma) then Break;
      end;
      PySkipNewlines;
    end;
  end;
end;

{ Every TOP-LEVEL import in the file, wherever it sits. The leading run handles
  the ones before the first statement; this one exists because Python allows an
  import anywhere and real files use that — songformatter's convertrawtext.py has
  a block of them after a try/except. Those were silently DROPPED: no error, no
  registration, and the first use failed much later as `undefined variable`.

  It has to run BEFORE the module-local pre-pass, not at statement level: that
  pre-pass trial-parses the whole body, so it meets the use site before the body
  parse would ever reach the import. Imports are re-encountered by the body parse
  and handled there too (PyParseStatement); registering a unit twice is a no-op. }
{ Imports at ANY depth are pulled HERE, before any body is parsed. A unit pull
  APPENDS the unit's tokens to the stream, and a body whose extent was already
  measured (PyFindBodyEnd) then ran past its end — the enclosing function
  silently produced nothing, which is what an in-body `import` used to do. The
  statement itself is still parsed later; the unit is compiled by then, so the
  pull is a no-op and appends nothing.

  EXCEPT inside a `try:`, where an import must stay soft: that is the
  fallback-import idiom (`try: import reportlab / except ImportError:`), whose
  whole point is that the module may be absent. Those are decided when the
  block is parsed. }
procedure PyPreScanImports;
var i, depth, savedTok, tryAt, j: Integer;
begin
  savedTok := TokPos;
  i := PyScanLo;
  depth := 0;
  tryAt := -1;
  while i < MainProgramTokCount do
  begin
    if Tokens[i].Kind = tkIndent then Inc(depth)
    else if Tokens[i].Kind = tkDedent then
    begin
      Dec(depth);
      { Left the try STATEMENT — not merely its first block: an `except` or
        `finally` block is a sibling at the same depth and its imports are just
        as soft (the fallback idiom's handler is `from pxxpdf import canvas`).
        Look past the newlines for the clause that follows. }
      if (tryAt >= 0) and (depth <= tryAt) then
      begin
        j := i + 1;
        while (j < MainProgramTokCount) and (Tokens[j].Kind = tkNewline) do Inc(j);
        if (j >= MainProgramTokCount) or
           not (Tokens[j].Kind in [tkExcept, tkFinally, tkElse]) then tryAt := -1;
      end;
    end
    else if (Tokens[i].Kind = tkTry) and (tryAt < 0) then
      tryAt := depth
    else if (tryAt < 0) and
            ((Tokens[i].Kind = tkUses) or
             ((Tokens[i].Kind = tkIdent) and CaseEqual(GetTokenStr(i), 'from') and
              (i + 1 < MainProgramTokCount) and (Tokens[i + 1].Kind = tkIdent))) and
            ((i = PyScanLo) or (Tokens[i - 1].Kind in [tkNewline, tkIndent, tkDedent])) then
    begin
      TokPos := i;
      Next;
      PyParseImportRun;
      i := TokPos - 2;
    end;
    Inc(i);
  end;
  TokPos := savedTok - 1;
  Next;
end;

{ A `.py` MODULE, pulled in by an import (`from settings import get`,
  `import key_analysis`). Parsed with the same frontend as a program, but its
  declarations land in a UNIT: ParseUsesUnit has already set CurrentUnitIdx, so
  every proc, class and module-level variable registered here is tagged with it
  and scoped like a Pascal unit's — which is what keeps `settings.get` from
  colliding with an importer's own `get`.

  A module's top-level STATEMENTS are its import-time code (settings.py runs
  `ensure_default_settings()` there, and the importer depends on it having run),
  so they compile into an `__init_<module>` proc registered in InitProcs — the
  same place a Pascal unit's `initialization` section goes, run in dependency
  order before the program body. They are PARSED with CurProc = -1, exactly as a
  program's top-level statements are, so the names they bind stay module-level
  variables rather than becoming locals of the init proc.
  (feature-nilpy-py-module-loader) }
{ Create every module-level name the type pre-pass found, BEFORE any def or
  class body is parsed. Python binds a global at CALL time, so a function may
  read a name the module assigns further down the file — songformatter's menu
  callbacks all reach for widgets built at the bottom of SongFormatter.py. The
  pre-pass types these names but rolls its symbols back, and the real symbol was
  created only when the assignment statement was reached, i.e. AFTER the def
  that used it: the body reported "undefined variable" for an ordinary global.
  Pre-creating them changes nothing about the assignment itself — it stores into
  the same symbol either way. }
{ Is `nm` a target of a module-level UNPACKING assignment (`a, b = f()`)? The
  type pre-pass does not model those, and the type it happens to record for one
  is not the value it receives — creating the global from it turned
  `a, b = two()` into a store of a string into an integer slot. Such a name is
  left to the unpack path, which creates it from the actual value. }
function PyIsModuleUnpackTarget(const nm: AnsiString): Boolean;
var i, j, depth: Integer; sawName, sawComma: Boolean;
begin
  Result := False;
  depth := 0;
  i := PyScanLo;
  while i < MainProgramTokCount do
  begin
    if Tokens[i].Kind = tkIndent then Inc(depth)
    else if Tokens[i].Kind = tkDedent then Dec(depth)
    else if (depth = 0) and (Tokens[i].Kind = tkIdent) and
            (i + 1 < MainProgramTokCount) and (Tokens[i + 1].Kind = tkComma) and
            { at a STATEMENT boundary. Without this, `Button(x, textvariable=v,
              command=f)` matched: `v , command =` is an identifier, a comma and
              an `=`, and the whole module global was then skipped. }
            ((i = 0) or (Tokens[i - 1].Kind in [tkNewline, tkIndent, tkDedent,
                                                tkSemicolon, tkEOF])) then
    begin
      { scan the comma-separated name list; it is an unpack target only if it
        ends at `=` }
      j := i;
      sawName := False;
      sawComma := False;
      while j < MainProgramTokCount do
      begin
        if Tokens[j].Kind = tkIdent then
        begin
          sawName := True;
          Inc(j);
          { an ATTRIBUTE target counts as one name }
          if (j + 1 < MainProgramTokCount) and (Tokens[j].Kind = tkDot) and
             (Tokens[j + 1].Kind = tkIdent) then Inc(j, 2);
        end
        else if Tokens[j].Kind = tkComma then
        begin
          sawComma := True;
          Inc(j);
        end
        else Break;
      end;
      if sawName and sawComma and (j < MainProgramTokCount) and
         (Tokens[j].Kind = tkAssign) then
      begin
        j := i;
        while (j < MainProgramTokCount) and (Tokens[j].Kind <> tkAssign) do
        begin
          if (Tokens[j].Kind = tkIdent) and (GetTokenStr(j) = nm) then
          begin
            Result := True;
            Exit;
          end;
          Inc(j);
        end;
      end;
    end;
    Inc(i);
  end;
end;

procedure PyAllocModuleGlobals;
const PY_ALLOCMOD_MAXDEPTH = 255;
var i, j, k, depth, idx, ci: Integer; nm: AnsiString; usedEarlier, pendingDef: Boolean;
    inDefStack: array[0..PY_ALLOCMOD_MAXDEPTH] of Boolean;
begin
  { ONLY the names a routine ABOVE them reads — the shape that fails outright:
    `def refresh(): bpm_label.set(...)` at the top of the file,
    `bpm_label = tk.StringVar(...)` at the bottom. Everything else keeps being
    created by its own assignment, with the concrete type that gives it:
    pre-creating every module name from the type pre-pass instead was tried and
    is too eager — the pre-pass's guess is not always the assignment's type, and
    a name it typed one way then took stores of another. }
  depth := 0;
  i := PyScanLo;
  while i < MainProgramTokCount do
  begin
    if Tokens[i].Kind = tkIndent then Inc(depth)
    else if Tokens[i].Kind = tkDedent then Dec(depth)
    else if (depth = 0) and (Tokens[i].Kind = tkIdent) and
            (i + 1 < MainProgramTokCount) and (Tokens[i + 1].Kind = tkAssign) and
            { a STATEMENT BOUNDARY — see the note in PyCollectModuleLocalsAST:
              a keyword argument inside a call is not an assignment }
            ((i = PyScanLo) or (Tokens[i - 1].Kind in [tkNewline, tkIndent,
                                                       tkDedent, tkSemicolon])) then
    begin
      nm := GetTokenStr(i);
      if (PyProgSym(nm) < 0) and not PyIsModuleUnpackTarget(nm) then
      begin
        { the read has to be INSIDE A DEF (a routine), not merely inside any
          indented block: a module-level use before the assignment is a
          genuine "used before defined", and pre-creating the symbol would
          hide it — but plain generic indent-depth tracking (k > 0) also
          counts an `if`/`while`/`for`/`with` suite, which indents exactly
          like a def body does. `with open(p, "w") as f: f.write(...)`
          followed later at module level by `f = open(p, "r")` then read
          the WITH block's own `f` reference as "used earlier", pre-created
          `f` as a bare tyVariant BEFORE the with-statement's real parse ever
          ran, and PyParseWith stored the raw TPyFile pointer into that
          variant slot with no boxing — write() dispatched against garbage
          and silently wrote nothing
          (bug-nilpy-file-write-drops-data-and-read-to-print-dumps-rtti-memory,
          a second trigger for the same disclosure shape). Track which
          indent levels actually descend from a `def` header, not just any
          block. }
        usedEarlier := False;
        k := 0;
        pendingDef := False;
        inDefStack[0] := False;
        for j := PyScanLo to i - 1 do
        begin
          if Tokens[j].Kind = tkFunction then pendingDef := True
          else if Tokens[j].Kind = tkIndent then
          begin
            if k < PY_ALLOCMOD_MAXDEPTH then
            begin
              if pendingDef then inDefStack[k + 1] := True
              else if k > 0 then inDefStack[k + 1] := inDefStack[k]
              else inDefStack[k + 1] := False;
            end;
            Inc(k);
            pendingDef := False;
          end
          else if Tokens[j].Kind = tkDedent then Dec(k)
          else if (k > 0) and (k <= PY_ALLOCMOD_MAXDEPTH) and inDefStack[k] and
                  (Tokens[j].Kind = tkIdent) and (GetTokenStr(j) = nm) then
          begin
            usedEarlier := True;
            Break;
          end;
        end;
        if usedEarlier then
        begin
          ci := AllocVar(nm, tyVariant);
          Syms[ci].RecName := REC_NONE;
        end;
      end;
    end;
    Inc(i);
  end;
end;

procedure ParsePyUnit(const uname: AnsiString);
var stmt, seqNode, lastSeq, procIdx, patchPos, savedSC, savedFS: Integer;
    dbgI: Integer;
    savedScanLo, savedMainTok, savedNest, savedLam, savedHoist, savedFloor: Integer;
    savedExprMode: Boolean;
    dummyNames: array[0..0] of AnsiString;
    dummyTypes: array[0..0] of TTypeKind;
begin
  savedScanLo := PyScanLo;
  savedMainTok := MainProgramTokCount;
  savedExprMode := PyExprMode;
  savedNest := PyPendNestCount;
  savedLam := PyPendLamCount;
  { the pre-passes below scan "the compilation unit": for a module that is its
    own token span, not the program's }
  PyScanLo := TokPos - 1;
  MainProgramTokCount := TokCount;

  { The pre-passes TRIAL-PARSE: they emit no code, and anything they queue on
    the global hoist list is a leftover of a parse that is about to be redone.
    Left queued, such a node was flushed into a later statement — in a MODULE,
    after the symbols it names had been rolled back with the scope that made
    them, so the IR verifier rejected the compile at the module's LAST line
    with nothing there to explain it. Drop the queue instead. }
  savedHoist := PyHoistHead;
  PyRegisterClassShells;          { the class ROWS the field pre-pass fills in }
  PyPreScanImports;
  PyRegisterClassFieldsPrepass;
  PyRegisterDefShells;
  PyCollectModuleLocalsAST;
  PyAllocModuleGlobals;           { a def may read a global assigned further down }
  PyHoistHead := savedHoist;
  PyExprMode := True;

  seqNode := AllocNode(AN_SEQ);
  lastSeq := seqNode;
  { From here this module's import-time statement list is LIVE across the whole
    file, and parsing it compiles other units whose per-body resets would hand
    these nodes out again — see ASTArenaFloor in defs.inc. }
  savedFloor := ASTArenaFloor;
  ASTArenaFloor := ASTNodeCount;
  PySkipNewlines;
  while CurTok.Kind <> tkEOF do
  begin
    if CurTok.Kind = tkClass then PyParseClass(False)
    else if CurTok.Kind = tkAt then
    begin
      Next;
      if not PyIsIdent('dataclass') then
        Error('Nil Python: unsupported decorator (only @dataclass)');
      Next;
      if CurTok.Kind = tkLParen then begin Next; Expect(tkRParen, ')'); end;
      Expect(tkNewline, 'newline');
      PySkipNewlines;
      if CurTok.Kind <> tkClass then
        Error('Nil Python: @dataclass must precede a class');
      PyParseClass(True);
    end
    else if CurTok.Kind = tkFunction then PyParseDef
    else
    begin
      stmt := PyParseStatement;
      stmt := PySeqAppend(PyFlushHoist(-1), stmt);
      if stmt >= 0 then
      begin
        if ASTLeft[lastSeq] = -1 then ASTLeft[lastSeq] := stmt
        else
        begin
          ASTRight[lastSeq] := AllocNode(AN_SEQ);
          lastSeq := ASTRight[lastSeq];
          ASTLeft[lastSeq] := stmt;
        end;
      end;
      ASTArenaFloor := ASTNodeCount;   { see the note at the loop head }
    end;
    PySkipNewlines;
  end;

  { the module's import-time code, as this unit's initialization section }
  procIdx := RegisterProc('__init_' + uname, False, tyInteger, 0,
                          dummyNames, dummyTypes);
  Procs[procIdx].BodyAddr := CodeLen;
  savedSC := SymCount;
  savedFS := FrameSize;
  FrameSize := 0;
  CurProc := procIdx;
  Procs[procIdx].ScopeBase := SymCount;
  patchPos := EmitProcPrologue;
  Procs[procIdx].FramePatch := patchPos;
  CompileAST(seqNode);
  EmitProcEpilog(-1);
  { DWARF -g: the module's import-time body is a real proc, so give it a
    subprogram DIE too — without one gdb showed the outermost NilPy frame as
    `?? ()` and no module-level name was in scope anywhere. Its own top-level
    names are GLOBALS (Python module scope), recorded as CU-level variable DIEs
    exactly like a Pascal program's globals. Main module only: an imported .py
    lexes past DbgMainTokEnd, and the Tier 1 line table describes one file. }
  ProcBodyEnd[procIdx] := CodeLen;
  ProcDbgMain[procIdx] := DbgTokIsDebuggable(TokPos);
  { NOT DbgMainBodyStart/End: those drive a SECOND, anonymous program-body
    subprogram in DbgEmitSubprograms, which would overlap this proc's DIE on
    the same address range. The named proc DIE is the better of the two. }
  if DebugInfo and ProcDbgMain[procIdx] then
    for dbgI := savedSC to SymCount - 1 do
      if Syms[dbgI].Kind = skGlobal then DbgRecordVar(-1, dbgI, True);
  PatchProcPrologue(patchPos, FrameSize);
  { The symbols this body allocated are NOT rolled back. The IR it emitted
    still names them, and the IR buffer outlives the proc — a later verify then
    met an index past SymCount and rejected the whole compile
    ("invalid IR symbol reference in load_sym" at the module's last line, with
    nothing at that line to explain it). A module's import-time code runs once
    at start-up and its temps are module-lifetime anyway, so keeping them costs
    symbol slots and nothing else. }
  FrameSize := savedFS;
  CurProc := -1;
  if InitProcCount < 256 then
  begin
    InitProcs[InitProcCount] := procIdx;
    Inc(InitProcCount);
  end;

  { bodies queued while compiling this module (nested defs, lifted lambdas) }
  PyDrainPendingLambdas(savedLam);
  while PyPendNestCount > savedNest do
  begin
    Dec(PyPendNestCount);
    stmt := TokPos;
    PyNestPrefix := PyPendNestPfx[PyPendNestCount];
    TokPos := PyPendNestTok[PyPendNestCount];
    Next;
    PyParseDef;
    PyNestPrefix := '';
    TokPos := stmt - 1;
    Next;
  end;

  ASTArenaFloor := savedFloor;
  PyExprMode := savedExprMode;
  MainProgramTokCount := savedMainTok;
  PyScanLo := savedScanLo;
end;

procedure ParsePyProgram;
var mainNode, stmt, blockNode, jmpPatch, i, savedUnitIdx: Integer; needsBuiltin: Boolean;
    pyHasExceptions: Boolean;
    dummyNames: array[0..3] of AnsiString;
    dummyTypes: array[0..3] of TTypeKind;
    impName: AnsiString; isCount: Boolean;
    aStrIdx, realStrIdx: Integer;
begin
  needsBuiltin := True;
  pyHasExceptions := False;
  for i := 0 to MainProgramTokCount - 1 do
  begin
    if (Tokens[i].Kind = tkIdent) and (i + 1 < MainProgramTokCount) and
       (Tokens[i + 1].Kind = tkLParen) and
       (CaseEqual(GetTokenStr(i), 'str') or CaseEqual(GetTokenStr(i), 'val')) then
      needsBuiltin := True;
    { `try` / `raise` anywhere in the program pulls in the exception runtime
      (setjmp/longjmp helpers, the unwind globals). The Pascal driver has the
      same pre-scan; this driver had none, so a .npy try emitted an
      IR_EXC_ENTER whose `call ExcSetJmpAddr` went to address 0 — an instant
      stack-smash segfault with no output, not a diagnostic. }
    if Tokens[i].Kind in [tkTry, tkRaise] then pyHasExceptions := True;
  end;
  PyCountAlias := '';
  PyImpNameCount := 0;
  PyOptMissingCount := 0;
  PyExprHadOptionalMissing := False;
  PyDcCount := 0;
  for i := 0 to PY_MAX_DC_FIELDS - 1 do PyDcClassIsDc[i] := False;
  for i := 0 to MAX_UCLASS - 1 do PyMembersHoisted[i] := False;
  PyRegisterClassShells;
  BSS_INITIAL_RSP := BSSSize; Inc(BSSSize, 8);
  BSS_HEAP_PTR    := BSSSize; Inc(BSSSize, 8);
  BSS_HEAP_END    := BSSSize; Inc(BSSSize, 8);
  BSS_FREE_LIST   := BSSSize; Inc(BSSSize, 8);
  BSS_HEAP_LOCK   := BSSSize; Inc(BSSSize, 8);
  EmitB($48); EmitB($89); EmitB($24); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);
  MovRsiImm(HEAP_ARENA_SIZE);
  EmitMmapArena;
  EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_HEAP_PTR);
  EmitB($48); EmitB($89); EmitB($C2);
  EmitB($48); EmitB($81); EmitB($C2); EmitI32(HEAP_ARENA_SIZE);
  EmitB($48); EmitB($89); EmitB($14); EmitB($25); EmitGlobRef(BSS_HEAP_END);
  EmitB($E9); jmpPatch := CodeLen; EmitI32(0);
  { Integer div-by-zero abort stub — same latent hole as the C driver: a
    builtinheap div site compiled before PXXDivZero registers fell back to a
    zero Div0StubAddr. Python '//'/'%' always need the check; unconditional. }
  if TargetArch = TARGET_X86_64 then EmitDiv0Stub;
  { Bitwise-on-float TypeError abort stub — EmitVarBinOp's double path calls it
    when a bitwise op has a float variant operand (Python raises, we abort like
    pylib's PyTypeError). bug-nilpy-bitwise-on-float-variant-truncates. }
  if TargetArch = TARGET_X86_64 then EmitPyBitFloatErrStub;
  if pyHasExceptions then EnableExceptionRuntime;
  { Forward-declare the builtin heap allocator before emitting the string
    runtime, which calls Alloc. The unit body (compiled by ParseUsesUnit below)
    fills these in. Mirrors the Pascal ParseProgram path; without it a .npy that
    touches the heap fails FindProc('PXXAlloc') during EmitAnsiStringRuntime. }
  savedUnitIdx := CurrentUnitIdx;
  CurrentUnitIdx := InternStr('builtinheap');
  dummyNames[0] := 'size';  dummyTypes[0] := tyNativeInt;
  dummyNames[1] := 'align'; dummyTypes[1] := tyInteger;
  i := RegisterProc('PXXAlloc', True, tyPointer, 2, dummyNames, dummyTypes);
  dummyNames[0] := 'p';     dummyTypes[0] := tyPointer;
  i := RegisterProc('PXXFree', False, tyPointer, 1, dummyNames, dummyTypes);
  { the emitted obj blobs call these (feature-nilpy-object-reclamation) }
  i := RegisterProc('PXXObjRetain', False, tyPointer, 1, dummyNames, dummyTypes);
  i := RegisterProc('PXXObjRelease', False, tyPointer, 1, dummyNames, dummyTypes);
  dummyNames[0] := 'p';     dummyTypes[0] := tyPointer;
  dummyNames[1] := 'newSize'; dummyTypes[1] := tyNativeInt;
  dummyNames[2] := 'align'; dummyTypes[2] := tyInteger;
  i := RegisterProc('PXXRealloc', True, tyPointer, 3, dummyNames, dummyTypes);
  dummyNames[0] := 'len';   dummyTypes[0] := tyNativeInt;
  dummyNames[1] := 'src';   dummyTypes[1] := tyPointer;
  i := RegisterProc('PXXStrFromLit', True, tyPointer, 2, dummyNames, dummyTypes);
  dummyNames[0] := 'lenA';  dummyTypes[0] := tyNativeInt;
  dummyNames[1] := 'srcA';  dummyTypes[1] := tyPointer;
  dummyNames[2] := 'srcB';  dummyTypes[2] := tyPointer;
  dummyNames[3] := 'lenB';  dummyTypes[3] := tyNativeInt;
  i := RegisterProc('PXXStrConcat', True, tyPointer, 4, dummyNames, dummyTypes);
  dummyNames[0] := 'path';  dummyTypes[0] := tyPointer;
  i := RegisterProc('PXXStrLoadFile', True, tyPointer, 1, dummyNames, dummyTypes);
  CurrentUnitIdx := savedUnitIdx;
  EmitAnsiStringRuntime;
  { builtinheap declares TInterfacedObject/IInterface, whose signatures name
    TGuid and TObject — register the builtin rows first (idempotent), exactly
    like the Pascal and C paths. }
  RegisterBuiltinTGuid;
  RegisterBuiltinTObject;
  ParseUsesUnit('builtinheap');
  if needsBuiltin then ParseUsesUnit('builtin');
  { Resolve TVarRec now that builtinheap declared it, exactly as ParseProgram
    does. Without this TVarRecId stayed REC_NONE for .npy programs, so ANY unit
    an import pulls in that takes an `array of const` parameter was rejected with
    "array of const requires the builtinheap unit" — while builtinheap was in
    fact loaded. That blocked every RTL unit reaching sysutils (Format), which is
    most of them, and is what `import json` actually died on. A .npy program has
    no uses clause of its own, so it could not work around it. }
  FixupTVarRecLayout;
  ParseUsesUnit('pylib');
  ParseUsesUnit('pyeval');
  { Only NOW: the units above are ORDINARY PASCAL and their own div/mod must
    keep truncating semantics. Setting this at entry rewrote pylib's own
    `a div b` into a call to the helper being defined. }
  PyProgramMode := True;
  PyCompTarget := -1;   { no comprehension in progress by default }
  PyHoistHead := -1;    { no pending hoisted statements }
  PySkipNewlines;
  { A leading module docstring may precede the imports; consume it. }
  if (CurTok.Kind = tkString) and (TokPos < TokCount) and
     (Tokens[TokPos].Kind = tkNewline) then
  begin
    Next;
    PySkipNewlines;
  end;
  { Nil Python `import name[, name]` maps each module onto the same unit
    resolver as a Pascal `uses` clause, so a C header in /usr/include
    (e.g. sqlite3) is imported and dynamically linked identically. The
    lexer rewrites `import` to tkUses; leading imports are processed before
    the program body so their symbols are registered for the main code.
    `from dataclasses|typing import ...` is consumed and ignored (those
    names are built in); any other from-import is a clean unsupported. }
  PyParseImportRun;

  { Module-local type collection runs AFTER the units above so proc return
    types (len, VariantToStr, pylib methods) resolve during inference. }
  PyPreScanImports;               { every top-level import, not just the leading ones }
  PyRegisterClassFieldsPrepass;   { fields must exist before local inference }
  PyRegisterDefShells;            { def signatures must exist before it too }
  PyCollectModuleLocalsAST;
  PyAllocModuleGlobals;           { a def may read a global assigned further down }
  PyExprMode := True;   { Pascal RTL units are loaded; from here on, .npy expression
                          parsing uses Python and/or/not precedence }
  { -g: module-level names declared from here on are the PROGRAM's own globals,
    not the runtime units' — the same boundary Pascal's DbgGlobalScopeBase
    marks. PyAllocModuleGlobals runs first because the names it pre-creates are
    the program's too. }
  DbgGlobalScopeBase := SymCount;
  mainNode := -1;
  PySkipNewlines;
  { The program's own statement list is live until the body is compiled at the
    end of this routine, and parsing it compiles units whose per-body resets
    would hand these nodes out again — the same hazard ParsePyUnit guards, and
    the program's nodes sit just ABOVE the reserve, so they are the first to be
    recycled. See ASTArenaFloor in defs.inc. }
  ASTArenaFloor := ASTNodeCount;
  while CurTok.Kind <> tkEOF do
  begin
    if CurTok.Kind = tkClass then PyParseClass(False)
    else if CurTok.Kind = tkAt then
    begin
      Next;
      if not PyIsIdent('dataclass') then
        Error('Nil Python: unsupported decorator (only @dataclass)');
      Next;
      if CurTok.Kind = tkLParen then begin Next; Expect(tkRParen, ')'); end;
      Expect(tkNewline, 'newline');
      PySkipNewlines;
      if CurTok.Kind <> tkClass then
        Error('Nil Python: @dataclass must precede a class');
      PyParseClass(True);
    end
    else if CurTok.Kind = tkFunction then PyParseDef
    else
    begin
      stmt := PyParseStatement;
      mainNode := PyFlushHoist(mainNode);
      mainNode := PySeqAppend(mainNode, stmt);
      { the list just grew — everything it now holds must sit BELOW the floor,
        or the next unit compile hands those nodes out again }
      ASTArenaFloor := ASTNodeCount;
      { several simple statements on one line, as in PyParseBlock }
      while CurTok.Kind = tkSemicolon do
      begin
        Next;
        if CurTok.Kind in [tkNewline, tkDedent, tkEOF] then Break;
        stmt := PyParseStatement;
        mainNode := PyFlushHoist(mainNode);
        mainNode := PySeqAppend(mainNode, stmt);
        ASTArenaFloor := ASTNodeCount;
      end;
    end;
    PySkipNewlines;
  end;
  Patch32(jmpPatch, CodeLen - (jmpPatch + 4));
  { Unit INITIALISATION, in dependency order, before the program's own body —
    the same thing ParseProgram does for Pascal. An imported `.py` module's
    top-level code lives in one of these (`settings.py` runs
    `ensure_default_settings()` there, and a module-level name has no value
    until it has run), so without this an importer read zeroes and crashed on
    the first module-level list (feature-nilpy-py-module-loader). }
  { -g: the module's own top-level code is the program body — the range that
    becomes the main DW_TAG_subprogram. Without it gdb had no subprogram
    covering module-level addresses, so a breakpoint there reported `?? ()`
    and no module-level name was in scope. The main module is compiled INLINE
    here (ParsePyUnit handles imported .py files), which is why the def/method
    wiring alone did not cover it. }
  DbgMainBodyStart := CodeLen;
  for i := 0 to InitProcCount - 1 do
    EmitCallProc(InitProcs[i]);
  blockNode := AllocNode(AN_BLOCK);
  ASTLeft[blockNode] := mainNode;
  ASTTk[blockNode] := Ord(tyUnknown);
  PyExprMode := False;
  CompileAST(blockNode);
  { Unit FINALIZATION, in reverse init order, after the program body — like
    Pascal's driver, and like FPC. `atexit.register(fn)` is a finalization
    handler, so without this an imported module's exit code never ran. }
  if (FiniProcCount > 0) or (FiniRunnerProc >= 0) then
    EmitCallProc(GetFiniRunnerProc);
  EmitExit(0);
  DbgMainBodyEnd := CodeLen;
  { -g: the program's module-level names, as CU-level globals (Python module
    scope IS global scope). Same snapshot Pascal's ParseProgram takes. }
  if DebugInfo then
    for i := DbgGlobalScopeBase to SymCount - 1 do
      if Syms[i].Kind = skGlobal then DbgRecordVar(-1, i, True);
  { A lambda LIFTED at module level queues its body like one inside a def does,
    and nothing else drains the module's queue. Emitted after the exit on
    purpose: the code below is only ever reached by a call, and EmitExit never
    falls through into it. }
  PyDrainPendingLambdas(0);
  { Patch forward proc-call placeholders (e.g. the builtin heap allocator,
    whose body is compiled after the string runtime that calls it). Pascal
    ParseProgram does this; .npy needs it too now that string/variant codegen
    calls PXXAlloc. }
  EmitFinalizerRunnerBody;   { resolve any Halt-site __pxx_run_finalizers forward calls }
  ApplyCallFixups;
end;
