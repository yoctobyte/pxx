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
  PY_MAX_LOCALS = 128;

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
  PyHdrDefVal: array[0..31] of Int64;
  PyHdrDefSOff: array[0..31] of Integer;
  PyHdrDefSLen: array[0..31] of Integer;
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
function PyBuildComp(targetSym, exprStart: Integer): Integer; forward; { comprehension core (pyparser.inc) }
function PyMakeIdent(symIdx: Integer): Integer; forward; { (pyparser.inc) }
function PyParseFor: Integer; forward;
function PyBareGenExprAhead: Boolean; forward; { bare genexpr as a call arg (pyparser.inc) }

{ Queue a setup statement to run before the current one — see PyHoistHead. }
procedure PyHoistStmt(node: Integer);
begin
  PyHoistHead := PySeqAppend(PyHoistHead, node);
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
function PyAnnTypeAt(var i: Integer): TTypeKind;
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
          sigPTypes[sigN] := PyAnnTypeAt(i);
          if sigPTypes[sigN] = tyUnknown then
            Error('Nil Python: unsupported Callable parameter type');
          sigPCis[sigN] := PyAnnLastCi;
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
        if not sigIsFunc then sigRet := tyInteger;
      end;
      if (i < MainProgramTokCount) and (Tokens[i].Kind = tkRBrack) then Inc(i);
    end;
    sigPi := RegisterProc('$proctype', sigIsFunc, sigRet, sigN, sigPNames, sigPTypes);
    Procs[sigPi].BodyAddr := -1;
    for depth := 0 to sigN - 1 do
      if (sigPTypes[depth] = tyClass) and (sigPCis[depth] >= 0) then
        Syms[Procs[sigPi].Params[depth].SymIdx].RecName :=
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
    { ErrorAt, not Error: this runs in a TOKEN-INDEX pre-pass with no parser
      cursor, so plain Error reports whatever line the cursor happens to sit
      on — for uforth that was line 26, ~180 lines from the actual
      annotation. The token we are looking at knows its own line. }
    ErrorAt(Tokens[i].Line,
            'Nil Python: tuple types are not supported yet (' + lo + ')');
  if IsClassType(GetTokenStr(i)) then
  begin
    Result := tyClass;
    PyAnnLastCi := FindUClass(GetTokenStr(i));
    Inc(i);
    Exit;
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
  PyInferLastCi: Integer;   { class index of the last tyClass inference result }

function PyWidenErr: AnsiString;
begin
  Result := 'Nil Python: annotate the type / too dynamic';
  if PyInferName <> '' then Result := Result + ' (inferring ' + PyInferName + ')';
end;

function PyWiden(a, b: TTypeKind): TTypeKind;
begin
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
  if PyVariantScalar(a) and PyVariantScalar(b) then
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

{ isinstance(x, T) / isinstance(x, (T1, T2, ...)) — desugared to tag checks
  on variants (int also accepts bool, like CPython) and closed-world
  AN_IS_TEST class checks; a variant operand is unboxed via pylib pyvarobj.
  The operand subtree is re-emitted per OR term (pure idents in the corpus;
  a side-effecting operand would double-evaluate — b346 family, noted). }
procedure PyParseIsinstance;
var xNode, node, left, term, callN, argN, tagCall: Integer;
    isVar: Boolean; nm: AnsiString; ci: Integer;

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
  if CurTok.Kind = tkLParen then Next;   { optional tuple of types }
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
  if CurTok.Kind = tkRParen then
  begin
    Next;   { tuple close }
    if CurTok.Kind = tkRParen then Next   { call close }
  end;
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
var left, right, node, i, j: Integer; neg: Boolean; rTk: TTypeKind;
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
      if CurTok.Kind = tkNil then
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
        PyParseListLiteralT(tkLParen, tkRParen)
      else
        PyParseBitOr;
      right := CurASTNode;
      { The container decides the helper, and getting it wrong is not a type
        error but a CRASH: pycontains would scan a TPyDict's or a string's
        header words as if they were variant slots.
          dict   -> key membership
          str    -> SUBSTRING containment, which is what `in` means in Python
          else   -> list element membership }
      rTk := IntToTypeKind(ASTTk[right]);
      if (rTk = tyString) or (rTk = tyAnsiString) then
        node := FindProc('pystr_contains')
      else if rTk = tyVariant then
        { container type known only at run time (a dict/list slot value) —
          unbox and dispatch inside pyvar_contains. }
        node := FindProc('pyvar_contains')
      else if ResolveNodeRec(right) = REC_UCLASS_BASE + FindUClass('TPyDict') then
        node := FindProc('pydictcontains')
      else
        node := FindProc('pycontains');
      if node < 0 then Error('Nil Python: pylib (pycontains) not loaded');
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
    PyParseBoolNot;
    right := CurASTNode;
    if PyBoolOpReturnsOperand(left, right) then
      node := PyMakeBoolOpValue(left, right, False)
    else
    begin
      node := AllocNode(AN_BINOP); ASTIVal[node] := Ord(tkAnd);
      ASTLeft[node] := left; ASTRight[node] := right; ASTTk[node] := Ord(tyBoolean);
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
function PyUnboxVariantToClass(varNode, ci: Integer): Integer;
var unboxArg, unboxCall, castNode: Integer;
begin
  unboxArg := AllocNode(AN_ARG); ASTLeft[unboxArg] := varNode; ASTRight[unboxArg] := -1;
  unboxCall := AllocNode(AN_CALL);
  ASTIVal[unboxCall] := FindProc('pyvarobj');
  if ASTIVal[unboxCall] < 0 then Error('Nil Python: pylib (pyvarobj) not loaded');
  ASTTk[unboxCall] := Ord(tyPointer);
  ASTLeft[unboxCall] := unboxArg;
  castNode := AllocNode(AN_CLASS_CAST);
  ASTLeft[castNode] := unboxCall;
  ASTIVal[castNode] := ci;
  ASTTk[castNode]   := Ord(tyClass);
  Result := castNode;
end;


function PyMakeTruthy(n: Integer): Integer;
var procIdx, argNode, rec, lenNode, zeroNode, node: Integer;
    nilNode, guardNode, falseNode, pairNode, ternNode: Integer;
begin
  Result := n;
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
function PyBoolOpReturnsOperand(a, b: Integer): Boolean;
var ta, tb: TTypeKind;
begin
  ta := IntToTypeKind(ASTTk[a]); tb := IntToTypeKind(ASTTk[b]);
  Result := (ta = tyVariant) or (tb = tyVariant) or (ta = tyClass) or (tb = tyClass);
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
  if PyIsStrBaseTk(ta) or PyIsStrBaseTk(tb) then
    ASTTk[node] := Ord(tyAnsiString)
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
    PyParseBoolAnd;
    right := CurASTNode;
    if PyBoolOpReturnsOperand(left, right) then
      node := PyMakeBoolOpValue(left, right, True)
    else
    begin
      node := AllocNode(AN_BINOP); ASTIVal[node] := Ord(tkOr);
      ASTLeft[node] := left; ASTRight[node] := right; ASTTk[node] := Ord(tyBoolean);
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
    if CurTok.Kind = tkNil then
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
    if PyIsStrBaseTk(IntToTypeKind(ASTTk[left])) or
       PyIsStrBaseTk(IntToTypeKind(ASTTk[elseNode])) then
      ASTTk[node] := Ord(tyAnsiString)
    else
      ASTTk[node] := ASTTk[left];
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
var si: Integer;
begin
  si := FindSym(name);
  if (si >= 0) and (SymUnitIdx[si] <> -1) then si := -1;
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
  else if CaseEqual(mname, 'isspace') then
    begin pname := 'pystr_isspace'; retTk := tyBoolean; end
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
  else
  begin
    pname := '';
    Result := False;
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
  if (startIdx < endIdx) and (Tokens[startIdx].Kind = tkIdent) and
     IsClassType(GetTokenStr(startIdx)) and (startIdx + 1 < endIdx) and
     (Tokens[startIdx + 1].Kind = tkLParen) then
  begin
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
    if tk = tyUnknown then
    begin
      if Tokens[i].Kind = tkIdent then
      begin
        name := GetTokenStr(i);
        { Call form `name(...)`: take the callee's return type and skip the
          whole argument group so arg tokens do not pollute the widening. }
        if (i + 1 < endIdx) and (Tokens[i + 1].Kind = tkLParen) and
           not IsClassType(name) then
        begin
          { Shared-parser builtins are not Procs; without this they would fall
            through to tyVariant and poison the local's type (a variant local
            scalar-loaded on `return` yields its TAG, not the value). }
          lo := LowerCase(name);
          if (lo = 'length') or (lo = 'ord') or (lo = 'pos') then tk := tyInteger
          else if lo = 'chr' then tk := tyChar
          else if lo = 'copy' then tk := tyString
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
  for i := 0 to MainProgramTokCount - 2 do
    if (Tokens[i].Kind = tkClass) and (Tokens[i + 1].Kind = tkIdent) and
       (FindUClass(GetTokenStr(i + 1)) < 0) then
      AddUClass(Tokens[i + 1].SOffset, Tokens[i + 1].SLen);
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

function PyClassCreate: Integer; forward;

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
  case Tokens[j].Kind of
    tkNil:     begin Inc(j); Exit; end;
    tkTrue:    begin Result := 1; Inc(j); Exit; end;
    tkFalse:   begin Inc(j); Exit; end;
    tkInteger: begin Result := Tokens[j].IVal; Inc(j); Exit; end;
    tkString:
      begin
        isStr := True;
        sOff := Tokens[j].SOffset;
        sLen := Tokens[j].SLen;
        Inc(j);
        Exit;
      end;
    tkMinus:
      if Tokens[j + 1].Kind = tkInteger then
      begin
        Result := -Tokens[j + 1].IVal;
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

function PyIsEmptySetCall: Boolean;
begin
  Result := (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'set') and
            (TokPos + 1 < TokCount) and (Tokens[TokPos].Kind = tkLParen) and
            (Tokens[TokPos + 1].Kind = tkRParen);
end;

function PyParseEmptySet: Integer;
var ci, recId, sizeNode, argNode: Integer;
begin
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
    kwAny: Boolean; kwSlot: array[0..PY_MAX_DC_KW - 1] of Integer;
begin
  name := CurTok.SVal;
  ci := FindUClass(name);
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
      kwFld := FindUField(ci, kwName);
      if kwFld < 0 then
        Error('Nil Python: ' + name + ' has no field named ''' + kwName + '''');
      kwFld := kwFld - UClsFBase[ci];      { absolute -> field INDEX }
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
        argNode := kwSlot[kwI]
      else
      begin
        kwDcBase := -1;
        for kwJ := 0 to PyDcCount - 1 do
          if PyDcCi[kwJ] = ci then begin kwDcBase := kwJ; break; end;
        if kwDcBase < 0 then
          Error('Nil Python: ' + name + '() needs a value for every field before the last one given');
        argNode := AllocNode(AN_ARG);
        ASTLeft[argNode] := PyDcDefaultNode(ci, kwDcBase, kwI);
        ASTRight[argNode] := -1;
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
    i: Integer;
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
      + 'join, split, splitlines)');

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
  else if wantArgs = -2 then
  begin
    { width plus an OPTIONAL fill character — rjust }
    if i = 2 then pname := pname + '_c'
    else if i <> 1 then
      Error('Nil Python: str method .' + mname + '() takes one or two arguments');
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
    tkSlashEq: Result := '/=';
    tkModEq:   Result := '%=';
    tkAmpEq:   Result := '&=';
    tkPipeEq:  Result := '|=';
    tkXorEq:   Result := '^=';
  else
    Error('Nil Python: this token is not supported in a lambda/closure body yet');
    Result := '';
  end;
end;

procedure PyParseLambdaStub;
var depth, bStart, bEnd, i, j, pi, capPi, symIdx: Integer;
    params, src, nm: AnsiString;
    pNames: array[0..7] of AnsiString;
    nParams: Integer;
    node, argA, argB, capNode: Integer;
    dup: Boolean;
begin
  Next;                                { consume `lambda` }
  params := '';
  nParams := 0;
  while (CurTok.Kind <> tkColon) and (CurTok.Kind <> tkEOF) do
  begin
    if CurTok.Kind = tkIdent then
    begin
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

function PyNestedDefClosureValue(procIdx: Integer): Integer;
var defTok, i, j, k, depth: Integer;
    pNames: array[0..15] of AnsiString;
    pDefS, pDefE: array[0..15] of Integer;
    nP, nDef, nOwn, bindIdx, savedTok: Integer;
    node, argA, argB, argC, vNode, newPi, bindPi, varBindPi, symIdx: Integer;
    nm: AnsiString;
    anyBind: Boolean;

  { chain one pyboundfn_bind / _bind_var call: node := bind(node, idx, valNode) }
  procedure ChainBind(valNode: Integer; isVar: Boolean);
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
    if isVar then ASTIVal[node] := varBindPi else ASTIVal[node] := bindPi;
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
  { the bridge passes exactly ONE user argument before the bound values }
  if nOwn <> 1 then Exit;
  if nDef + PyCapCount[procIdx] > 12 then Exit;
  { defaulted params must come after the single own param (Python guarantees) }

  { every capture must resolve to a value symbol we can bind }
  for j := 0 to PyCapCount[procIdx] - 1 do
  begin
    nm := PyCapName[procIdx * PY_MAX_CAPS + j];
    symIdx := PyProgSym(nm);
    if symIdx < 0 then Exit;
    if not (Syms[symIdx].Kind in [skGlobal, skLocal, skParam]) then Exit;
    if (Syms[symIdx].TypeKind = tyAnsiString) or (Syms[symIdx].TypeKind = tyString) then Exit;
    if Syms[symIdx].IsArray or (Syms[symIdx].TypeKind = tyRecord) then Exit;
  end;

  { pyboundfn_new(addr, n, a0var) — a0var says whether the single own param
    is a VARIANT (unannotated) and must travel by address }
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
  if (Procs[procIdx].ParamCount > 0) and
     (Procs[procIdx].Params[0].TypeKind = tyVariant) then
    ASTIVal[node] := 1
  else
    ASTIVal[node] := 0;
  ASTTk[node] := Ord(tyInt64);
  ASTLeft[argC] := node;
  ASTRight[argB] := argC;
  node := AllocNode(AN_CALL);
  ASTIVal[node] := newPi; ASTLeft[node] := argA; ASTTk[node] := Ord(tyPointer);
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
      ChainBind(k, (bindIdx + 1 < Procs[procIdx].ParamCount) and
                   (Procs[procIdx].Params[bindIdx + 1].TypeKind = tyVariant));
    end;

  { then each scanned CAPTURE, by current value }
  for j := 0 to PyCapCount[procIdx] - 1 do
  begin
    nm := PyCapName[procIdx * PY_MAX_CAPS + j];
    symIdx := PyProgSym(nm);
    ChainBind(PyMakeIdent(symIdx),
              (bindIdx + 1 < Procs[procIdx].ParamCount) and
              (Procs[procIdx].Params[bindIdx + 1].TypeKind = tyVariant));
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

{ `obj.name` (dynamic attribute read) -> pydynattr_get(obj, "name"). }
function PyMakeDynAttrGet(baseNode: Integer; const fname: AnsiString): Integer;
var procIdx, a0, a1, nameNode: Integer;
begin
  procIdx := FindProc('pydynattr_get');
  if procIdx < 0 then Error('Nil Python: pylib (pydynattr_get) not loaded');
  nameNode := AllocNode(AN_STR_LIT);
  ASTSOffset[nameNode] := PyStoredName(fname);
  ASTSLen[nameNode] := Length(fname);
  ASTTk[nameNode] := Ord(tyString);
  a0 := AllocNode(AN_ARG); ASTLeft[a0] := PyMakeObjPtr(baseNode);
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

{ `v[key] = val` on a variant -> pyvar_setitem(v, key, val), a statement. }
function PyMakeVariantSetItem(baseNode, idxNode, valNode: Integer): Integer;
var procIdx, a0, a1, a2: Integer;
begin
  procIdx := FindProc('pyvar_setitem');
  if procIdx < 0 then Error('Nil Python: pylib (pyvar_setitem) not loaded');
  a0 := AllocNode(AN_ARG); ASTLeft[a0] := baseNode;
  a1 := AllocNode(AN_ARG); ASTLeft[a1] := idxNode;
  a2 := AllocNode(AN_ARG); ASTLeft[a2] := valNode;
  ASTRight[a0] := a1; ASTRight[a1] := a2; ASTRight[a2] := -1;
  Result := AllocNode(AN_CALL);
  ASTIVal[Result] := procIdx;
  ASTTk[Result] := Ord(tyUnknown);
  ASTLeft[Result] := a0;
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
var hiNode: Integer;
begin
  Next;                              { consume ':' }
  if loNode < 0 then loNode := PySliceOmitNode;
  if CurTok.Kind = tkRBrack then
    hiNode := PySliceOmitNode        { `b[lo:]` }
  else
  begin
    PyParseBoolExpr;
    hiNode := CurASTNode;
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
    Result := (nm = 'stdout') or (nm = 'stderr') or (nm = 'stdin') or (nm = 'argv')
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
  else if dotted = 'os.remove' then Result := 'pyos_remove'
  else if dotted = 'os.rename' then Result := 'pyos_rename'
  else if dotted = 'os.stat' then Result := 'pyos_stat'
  else if dotted = 'sys.exit' then Result := 'pysys_exit'
  else if dotted = 'sys.stdin.read' then Result := 'pystdin_read'
  else if dotted = 'sys.stdin.readline' then Result := 'pystdin_readline'
  else if dotted = 'sys.stdin.isatty' then Result := 'pystdin_isatty'
  else if dotted = 'select.select' then Result := 'pyselect_select'
  else if dotted = 'textwrap.dedent' then Result := 'pytextwrap_dedent'
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
     (base <> 'select') then Exit;
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
var procIdx, callNode, argNode, lastArg, i: Integer;
begin
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
    until not Eat(tkComma);
  Expect(tkRParen, ')');
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
function PyMakeVariantField(baseNode: Integer; const fname: AnsiString;
                            var tk: TTypeKind; var recName: Integer): Integer;
var ci, fi, hitCi, hitFi, unboxArg, unboxCall, castNode: Integer;
begin
  Result := -1;
  hitCi := -1; hitFi := -1;
  for ci := 0 to UClsCount - 1 do
  begin
    if UClsIsRecord[ci] then Continue;
    fi := FindUField(ci, fname);
    if fi < 0 then Continue;
    if hitCi < 0 then begin hitCi := ci; hitFi := fi; end
    else if (UFldTk[fi] <> UFldTk[hitFi]) or (UFldOff_[fi] <> UFldOff_[hitFi]) then
      Error('Nil Python: .' + fname + ' on a dynamically-typed value is '
        + 'ambiguous (several classes declare it at different offsets) — '
        + 'assign to an annotated local first');
  end;
  if hitCi < 0 then Exit;
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
  Result := AllocNode(AN_FIELD);
  ASTLeft[Result] := castNode;
  ASTSOffset[Result] := PyStoredName(fname);
  ASTSLen[Result] := Length(fname);
  ASTTk[Result] := UFldTk[hitFi];
  tk := IntToTypeKind(UFldTk[hitFi]);
  recName := UFldRec_[hitFi];
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

{ `<value>(args)` where the value is a VARIANT holding a callable — the function
  `exec()` stored in a namespace dict, called as `ns["__body__"]()`. Unbox the
  variant to its payload (the code pointer) and emit an indirect call with a
  synthetic all-variant signature. CurTok is the '('. }
function PyMakeDynCall(baseNode: Integer): Integer;
var unboxArg, unboxCall, argsHead, lastArg, argNode, n, sigPi: Integer;
begin
  { the callee code address = the variant's payload as a pointer }
  unboxArg := AllocNode(AN_ARG);
  ASTLeft[unboxArg] := baseNode;
  ASTRight[unboxArg] := -1;
  unboxCall := AllocNode(AN_CALL);
  ASTIVal[unboxCall] := FindProc('pyvarobj');
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
  if n = 1 then
    Result := PyWrapClosureDynCall(baseNode, ASTLeft[argsHead], Result);
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

function PyParseVariantMethod(baseNode: Integer; const mname: AnsiString): Integer;
var ci, mmi, mpi, i, k, unboxArg, unboxCall, castNode: Integer;
    selfArg, lastArg, argNode, callNode, hitCi, hitMmi, hitPi: Integer;
    smPName: AnsiString; smTk: TTypeKind; smArgs: Integer;
    dualPi, dcall, dself, dcast, tern, pairN, condN: Integer;
    dualCis, dualMmis: array[0..2] of Integer;
    nDual, di: Integer;
    argExprs: array[0..15] of Integer;
begin
  { A STR method on a variant receiver — `for s in ["ab"]: s.upper()`, where the
    loop variable is a variant holding a string. Render the receiver with
    pystr_of (which spells every tag Python's way) and hand it to the ordinary
    str-method desugar, rather than looking for a class that declares `upper`. }
  if PyStrMethodInfo(mname, smPName, smTk, smArgs) then
  begin
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
        Error('Nil Python: .' + mname + '() on a dynamically-typed value is '
          + 'ambiguous (several classes declare it) — assign to an annotated '
          + 'local first');
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
    Error('Nil Python: no class declares a method or callable field .'
          + mname + '()');
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
  while CurTok.Kind <> tkRParen do
  begin
    ParseArgExpr;
    if i <= High(argExprs) then argExprs[i] := CurASTNode;
    argNode := AllocNode(AN_ARG);
    ASTLeft[argNode] := CurASTNode;
    ASTRight[lastArg] := argNode;
    lastArg := argNode;
    Inc(i);
    if CurTok.Kind = tkComma then Next
    else Break;
  end;
  Expect(tkRParen, ')');

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

      pairN := AllocNode(AN_PAIR);
      ASTLeft[pairN] := dcall;
      ASTRight[pairN] := Result;
      tern := AllocNode(AN_TERNARY);
      ASTLeft[tern] := condN;
      ASTRight[tern] := pairN;
      if Procs[dualPi].RetType = Procs[mpi].RetType then
        ASTTk[tern] := Ord(Procs[mpi].RetType)
      else
        ASTTk[tern] := Ord(tyVariant);
      LastExprTk := IntToTypeKind(ASTTk[tern]);
      Result := tern;
    end;
end;

{ A None VALUE: pylib's pynone() yields a variant tagged VT_EMPTY. }
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

{ List literal [a, b, c] -> TPyList create + chained .append() calls, one
  expression tree (append returns Self). Reached from ParseFactor's PyExprMode
  tkLBrack branch, so nested literals in argument positions work too. }
procedure PyParseListLiteralT(opener, closer: TTokenKind);
var ci, recId, node, argNode, sizeNode, callNode, selfArg, valArg, mmi, mpi: Integer;
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
  mmi := FindUMeth(ci, 'append');
  if mmi < 0 then Error('Nil Python: TPyList.append not found');
  mpi := UMthProc_[mmi];
  while CurTok.Kind <> closer do
  begin
    { `None` as an ELEMENT is a real value in Python, and the slot can hold it —
      VT_EMPTY. Parsed as a nil literal everywhere else, it would box as integer
      0 (feature-nilpy-none-variant). }
    if CurTok.Kind = tkNil then
    begin
      Next;
      CurASTNode := PyMakeNone;
    end
    else
      PyParseBoolExpr;
    valArg := AllocNode(AN_ARG);
    ASTLeft[valArg] := CurASTNode;
    selfArg := AllocNode(AN_ARG);
    ASTLeft[selfArg] := node;
    ASTRight[selfArg] := valArg;
    callNode := AllocNode(AN_CALL);
    ASTIVal[callNode] := mpi;
    ASTTk[callNode] := Ord(tyClass);
    ASTLeft[callNode] := selfArg;
    node := callNode;
    if not Eat(tkComma) then break;
  end;
  Expect(closer, ']/}');
  { mark the outermost node so assignment RecName wiring sees a list; a
    chained append is an ordinary AN_CALL whose result class is TPyList }
  CurASTNode := node;
end;

procedure PyParseListLiteral;
begin
  PyParseListLiteralT(tkLBrack, tkRBrack);
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
    mmi, mpi, keyNode: Integer;
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
  mmi := FindUMeth(ci, 'setitem');
  if mmi < 0 then Error('Nil Python: TPyDict.setitem not found');
  mpi := UMthProc_[mmi];
  while CurTok.Kind <> tkEnd do
  begin
    PyParseBoolExpr;
    keyNode := CurASTNode;
    Expect(tkColon, ':');
    { `None` as a VALUE is a real value in Python (VT_EMPTY) — parsed as a nil
      literal it boxes as integer 0, `is None` tag-tests false, and the usual
      `if d[k] is None:` miss-branch is skipped (same fix the list-literal
      element path carries, feature-nilpy-none-variant). }
    if CurTok.Kind = tkNil then
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
    ASTLeft[selfArg] := node;
    ASTRight[selfArg] := keyArg;
    callNode := AllocNode(AN_CALL);
    ASTIVal[callNode] := mpi;
    ASTTk[callNode] := Ord(tyClass);
    ASTLeft[callNode] := selfArg;
    node := callNode;
    if not Eat(tkComma) then break;
  end;
  Expect(tkEnd, 'close brace');
  CurASTNode := node;
end;

procedure PyParseSetLiteral;
begin
  if PyDictLiteralAhead then PyParseDictLiteral
  else PyParseListLiteralT(tkBegin, tkEnd);
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
function PyParseStatement: Integer; forward;

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
    sz := TypeSize(Syms[idx].TypeKind);
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

{ Wrap a TPyList / TPyDict expression in the pylib repr call, so it prints as
  Python spells a container. Anything else is returned unchanged. }
function PyReprContainer(n: Integer): Integer;
var rec, listCi, dictCi, procIdx, argNode, callNode: Integer; pname: AnsiString;
    excCi, argCi, fieldNode: Integer;
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
    kw, endText: AnsiString;
    haveEnd: Boolean;
begin
  Next;
  Expect(tkLParen, '(');
  node := AllocNode(AN_WRITELN);
  lastArg := -1;
  writeFd := 0;                { 0 = the default, which lowering reads as stdout }
  haveEnd := False;
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
      { Python print separates successive arguments with a single space.
        Inject a synthetic space char arg before every argument after the
        first (a tyChar AN_INT_LIT writes the byte, not a number). This is the
        .npy print path only; Pascal writeln keeps its no-separator semantics. }
      if lastArg >= 0 then
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
      if CurTok.Kind = tkNil then
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
var node, pairNode, condNode, thenNode, elseNode: Integer;
begin
  Next;
  PyParseBoolExpr;
  condNode := PyMakeTruthy(CurASTNode);
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
var node: Integer;
begin
  Next;
  PyParseBoolExpr;
  node := AllocNode(AN_WHILE);
  ASTLeft[node] := PyMakeTruthy(CurASTNode);
  Expect(tkColon, ':');
  ASTRight[node] := PyParseSuite;
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

function PyParseForIn(const name: AnsiString; const name2: AnsiString; enumMode: Boolean): Integer;
var contNode, ci, dictCi, listCi, symIdx, cSym, iSym, nSym: Integer;
    sym2, vSym, vListNode, itemsDot: Integer;   { two-name target: `for k, v in d.items()` }
    elemNode, lenNode, node, cmpNode, incNode, bodyNode, seq, whileNode: Integer;
    compSaved, keyN: Integer;
    isStr: Boolean; contTk: TTypeKind;
begin
  { `d.items()`: hide the suffix behind a fake ':' so the expression parser stops
    at the dict, then step over the four suffix tokens and restore. }
  itemsDot := -1;
  if (name2 <> '') and not enumMode then itemsDot := PyItemsSuffixAhead;
  if itemsDot >= 0 then Tokens[itemsDot].Kind := tkColon;
  { `for pfx in ("a", "b"):` — a TUPLE to iterate, built as the same TPyList a
    `[...]` literal produces, exactly as the `in` OPERATOR does. }
  if PyTupleParenAhead then
    PyParseListLiteralT(tkLParen, tkRParen)
  else
    PyParseBoolExpr;
  if itemsDot >= 0 then
  begin
    Tokens[itemsDot].Kind := tkDot;
    TokPos := itemsDot + 4;
    Next;
  end;
  if enumMode then Expect(tkRParen, ')');
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
  if (not isStr) and (contTk = tyVariant) then
  begin
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
      Error('Nil Python: for-in needs a list, set, dict or str (got something untyped)');
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
      Error('Nil Python: a two-name for target needs a dict (.items()) or enumerate()');
  end
  else if (name2 <> '') and not enumMode then
    Error('Nil Python: a two-name for target needs a dict (.items()) or enumerate()');

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
  symIdx := PyProgSym(name);
  if symIdx < 0 then
  begin
    if enumMode then symIdx := AllocVar(name, tyInteger)
    else if isStr then symIdx := AllocVar(name, tyAnsiString)
    else symIdx := AllocVar(name, tyVariant);
  end;
  sym2 := -1;
  if name2 <> '' then
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

  { __py_c := container }
  seq := -1;
  node := AllocNode(AN_ASSIGN);
  ASTLeft[node] := PyMakeIdent(cSym);
  ASTRight[node] := contNode;
  seq := PySeqAppend(seq, node);
  { the dict form's parallel VALUE list — enumerate has no second container, and
    reading vSym/vListNode there took an UNINITIALISED node index, which landed
    in the retained-inline AST region and surfaced as "could not lower AST node
    (kind 78)" at the end of the program }
  if (sym2 >= 0) and not enumMode then
  begin
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
  else
  begin
    node := AllocNode(AN_ASSIGN);
    ASTLeft[node] := PyMakeIdent(symIdx);
    ASTRight[node] := elemNode;
    bodyNode := PySeqAppend(bodyNode, node);
  end;

  { the value name reads the parallel list at the same index }
  if (sym2 >= 0) and not enumMode then
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
      node := PyCallMeth1(PyNodeListCi(PyMakeIdent(PyCompTarget)), 'append',
                          PyMakeIdent(PyCompTarget), CurASTNode);
      if node < 0 then Error('Nil Python: pylib TPyList.append not loaded');
    end;
    TokPos := compSaved; Next;            { restore to the closing bracket }
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
function PyBuildComp(targetSym, exprStart: Integer): Integer;
var seq, node, sizeNode, createNode, aSeq, savedTarget, listCiN: Integer;
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
  node := AllocNode(AN_ASSIGN);
  ASTLeft[node] := PyMakeIdent(targetSym);
  ASTRight[node] := createNode;
  seq := PySeqAppend(-1, node);

  savedTarget := PyCompTarget;
  PyCompTarget := targetSym;
  PyCompExprStart := exprStart;
  node := PyParseFor;               { range/container both honour PyCompTarget }
  PyCompTarget := savedTarget;
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
  while not (PyIsIdent('for') or (CurTok.Kind = tkEOF)) do Next;
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
  while not (PyIsIdent('for') or (CurTok.Kind = tkEOF)) do Next;
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
var tmpSym, exprStart, seq: Integer;
begin
  tmpSym := AllocVar(PyHiddenName('gx'), tyClass);
  if bracketed then Next;              { consume '[' }
  exprStart := TokPos - 1;             { first EXPR token }
  while not (PyIsIdent('for') or (CurTok.Kind = tkEOF)) do Next;
  if not PyIsIdent('for') then Error('Nil Python: malformed comprehension');
  seq := PyBuildComp(tmpSym, exprStart);
  if bracketed then Expect(tkRBrack, ']');
  { each build statement runs before the current one }
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
var tmpSym, exprStart, seq: Integer;
begin
  tmpSym := AllocVar(PyHiddenName('gd'), tyClass);
  Syms[tmpSym].RecName := REC_UCLASS_BASE + FindUClass('TPyDict');
  Next;                                { consume the opening brace; CurTok = KEY }
  exprStart := TokPos - 1;
  while not (PyIsIdent('for') or (CurTok.Kind = tkEOF)) do Next;
  if not PyIsIdent('for') then Error('Nil Python: malformed dict comprehension');
  PyCompIsDict := True;
  seq := PyBuildComp(tmpSym, exprStart);
  PyCompIsDict := False;
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
function PyParseForZip(const name, name2: AnsiString): Integer;
var listCi, caSym, cbSym, caN, cbN, nSym, iSym, xSym, ySym: Integer;
    aNode, bNode, node, cnd, thenElse, seq, bodyNode, whileNode, incN, oneN: Integer;
begin
  listCi := FindUClass('TPyList');
  if listCi < 0 then Error('Nil Python: pylib (TPyList) not loaded');
  Next; Expect(tkLParen, '(');           { consume `zip` and `(` }
  PyParseBoolExpr; aNode := CurASTNode;
  Expect(tkComma, ',');
  PyParseBoolExpr; bNode := CurASTNode;
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

  seq := -1;
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
    rngStep, cmpNode, incNode, whileNode, keyN: Integer;
begin
  Next;
  if CurTok.Kind <> tkIdent then Error('Nil Python: expected loop variable after for');
  name := CurTok.SVal;
  Next;
  { `for k, v in d.items():` — a two-name target, which only a dict serves
    today (feature-nilpy-tuple-unpack). No tuple type is invented for it: the
    two names read the dict's parallel key and value lists by the same index. }
  name2 := '';
  if CurTok.Kind = tkComma then
  begin
    Next;
    if CurTok.Kind <> tkIdent then Error('Nil Python: expected a second loop variable');
    name2 := CurTok.SVal;
    Next;
  end;
  Expect(tkIn, 'in');
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
    Result := PyParseForIn(name, name2, enumMode);
    Exit;
  end;
  if name2 <> '' then Error('Nil Python: a two-name for target needs a dict (.items())');
  symIdx := PyProgSym(name);
  if symIdx < 0 then symIdx := AllocVar(name, tyInteger);
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
  Expect(tkRParen, ')');
  if PyCompTarget >= 0 then
  begin
    { comprehension over range: body is target.append(EXPR) — or, for a dict
      comprehension, target.store(KEY, VALUE). EXPR re-parsed from before the
      `for`, the same shape PyParseForIn uses. Header ends at a bracket. }
    compSaved := TokPos - 1;
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
  end
  else
  begin
    Expect(tkColon, ':');
    Expect(tkNewline, 'newline');
    Expect(tkIndent, 'indent');
    bodyNode := PyParseBlock;
    Expect(tkDedent, 'dedent');
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
    if FindProc(pfx + '.' + name) >= 0 then
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
            if (csym >= 0) and (PyCapCount[csym] > 0) then
              for k := 0 to PyCapCount[csym] - 1 do
              begin
                cn2 := PyCapName[csym * PY_MAX_CAPS + k];
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

{ `a, b = x, y` — SIMULTANEOUS assignment. Every right-hand side is evaluated
  into a hidden temp before ANY target is stored, which is the whole reason this
  is not just a sequence of assignments: `a, b = b, a` would otherwise become
  `a = b; b = a` and lose the old `a` (feature-nilpy-tuple-unpack). }
function PyParseUnpackAssign: Integer;
var names: array[0..7] of AnsiString;
    tmps: array[0..7] of Integer;
    nTargets, nValues, i, symIdx, node, seq, tk: Integer;
    unpCi, unpIdx, unpElem: Integer;
begin
  nTargets := 0;
  repeat
    if CurTok.Kind <> tkIdent then Error('Nil Python: expected a name in the assignment target');
    if nTargets >= 8 then Error('Nil Python: at most 8 unpacking targets');
    names[nTargets] := CurTok.SVal;
    Inc(nTargets);
    Next;
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
      symIdx := PyProgSym(names[i]);
      if symIdx < 0 then symIdx := AllocVar(names[i], tyVariant);
      node := AllocNode(AN_ASSIGN);
      ASTLeft[node] := PyMakeIdent(symIdx);
      ASTRight[node] := unpElem;
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
    symIdx := PyProgSym(names[i]);
    if symIdx < 0 then symIdx := AllocVar(names[i], Syms[tmps[i]].TypeKind);
    node := AllocNode(AN_ASSIGN);
    ASTLeft[node] := PyMakeIdent(symIdx);
    ASTRight[node] := PyMakeIdent(tmps[i]);
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
  if (i >= TokCount) or (Tokens[i].Kind <> tkComma) then Exit;
  while i < TokCount do
  begin
    if Tokens[i].Kind = tkComma then
    begin
      Inc(i);
      if (i >= TokCount) or (Tokens[i].Kind <> tkIdent) then Exit;
      Inc(i);
    end
    else if Tokens[i].Kind = tkAssign then begin Result := True; Exit; end
    else Exit;
  end;
end;

function PyParseStatement: Integer;
var name: AnsiString; symIdx, lhsNode, node, ci, rhsNode, annIdx, delBase: Integer; tk: TTypeKind;
    annSig: Integer;   { Callable signature of an annotated target, or -1 }
    augTk: TTokenKind;
begin
  Result := -1;
  PyStmtAteBlock := False;
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
  if CurTok.Kind = tkTry then begin Result := PyParseTry; Exit; end;
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
  if PyIsIdent('del') then
  begin
    Next;
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
      PyParseBoolExpr;
      ASTLeft[node] := CurASTNode;
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
    { v1 fallback: the call is consumed and DISCARDED (args unevaluated) —
      argument side effects would be lost; none in the censused corpus. }
    ci := 1;
    while (ci > 0) and (CurTok.Kind <> tkEOF) do
    begin
      if CurTok.Kind = tkLParen then Inc(ci)
      else if CurTok.Kind = tkRParen then Dec(ci);
      Next;
    end;
    Result := -1;
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
      if CurTok.Kind = tkNil then
      begin
        Next;
        if PyNumeric(IntToTypeKind(ASTTk[lhsNode])) then
        begin
          rhsNode := AllocNode(AN_INT_LIT);
          ASTIVal[rhsNode] := 0;
          ASTTk[rhsNode] := ASTTk[lhsNode];
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
      Syms[ASTIVal[lhsNode]].RecName := ASTRight[rhsNode];
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
    PyCoerceAssignmentRHS(Syms[symIdx].TypeKind, CurASTNode);
    node := AllocNode(AN_BINOP); ASTIVal[node] := Ord(augTk);
    ASTLeft[node] := PyMakeIdent(symIdx); ASTRight[node] := CurASTNode;
    { widen, don't copy the target type: `n -= 0x10000000000000000` on an int
      target must type the binop PROMO (see the twin lhs-expression site) }
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
      if symIdx < 0 then symIdx := AllocVar(name, tyClass);
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
    if CurTok.Kind = tkNil then
    begin
      Next;
      rhsNode := PyMakeNone;
    end
    else if (CurTok.Kind = tkIdent) and IsClassType(CurTok.SVal) and
       (TokPos < TokCount) and (Tokens[TokPos].Kind = tkLParen) then
      rhsNode := PyClassCreate
    else if PyIsEmptySetCall then
      rhsNode := PyParseEmptySet
    else if PyIsCountCall then
      rhsNode := PyParseCountCreate
    else
    begin
      PyParseBoolExpr;
      rhsNode := CurASTNode;
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
      PyNoteLocalType(name, IntToTypeKind(ASTTk[rhsNode]), ResolveNodeRec(rhsNode));
    lhsNode := PyMakeIdent(symIdx);
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
        if (PyLocals[si].RecCi < 0) and (Syms[i].RecName >= REC_UCLASS_BASE) then
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
var rnd, i, si, depth, bodyIx: Integer;
    savedTok, savedAST, savedSC, savedCur, savedFS, savedBSS: Integer;
    changed, savedExprMode: Boolean;
    tk, w: TTypeKind;
    nm: AnsiString;
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
    while i < MainProgramTokCount do
    begin
      if Tokens[i].Kind = tkIndent then Inc(depth)
      else if Tokens[i].Kind = tkDedent then Dec(depth)
      { No explicit skip for `def` / `class`: their bodies raise depth, and a
        def or class HEADER is not tkIdent-then-assign, so neither can match
        the statement tests below. Skipping them with PyFindBodyEnd instead
        cost an O(n) scan per construct — quadratic on a real file, and
        uforth.py went from an instant parse error to 107 seconds. }
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
          while (bodyIx < MainProgramTokCount) and
                not (Tokens[bodyIx].Kind in [tkNewline, tkDedent]) do Inc(bodyIx);
          i := bodyIx;
          continue;
        end;
      end
      else if (depth = 0) and (Tokens[i].Kind = tkIdent) and
              (i + 1 < MainProgramTokCount) and (Tokens[i + 1].Kind = tkAssign) then
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
        if (PyLocals[si].RecCi < 0) and (Syms[i].RecName >= REC_UCLASS_BASE) then
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

procedure PyParseDefHeader;
var annIdx, hdrDefIdx, hdrRetRec: Integer;
begin
  if CurTok.Kind <> tkFunction then Error('Nil Python: expected def');
  hdrDefIdx := TokPos - 1;          { the `def` token, for return inference }
  Next;
  if CurTok.Kind <> tkIdent then Error('Nil Python: expected function name');
  PyHdrName := CurTok.SVal;
  Next;
  Expect(tkLParen, '(');
  PyHdrNParams := 0;
  while CurTok.Kind <> tkRParen do
  begin
    if PyHdrNParams >= 32 then Error('Nil Python: too many parameters');
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
  for i := 0 to PyHdrNParams - 1 do
    if PyHdrDefHas[i] and (i < MAX_PROC_PARAMS) then
    begin
      ProcParamHasDefault[procIdx * MAX_PROC_PARAMS + i] := True;
      ProcParamDefaultVal[procIdx * MAX_PROC_PARAMS + i] := PyHdrDefVal[i];
      ProcParamDefaultIsStr[procIdx * MAX_PROC_PARAMS + i] := PyHdrDefIsStr[i];
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
var savedTok, i, depth, procIdx: Integer;
begin
  savedTok := TokPos;
  i := 0;
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
  { Re-READ the saved token rather than restoring a copy of CurTok: Next
    rewrites CurTok.SVal in place
    (project_curtok_record_copy_shares_sval_landmine). }
  TokPos := savedTok - 1;
  Next;
end;

procedure PyParseDef;
var name, savedPfx, savedPfx2: AnsiString;
    nparams, i, procIdx, idx, savedSC, savedFS, patchPos, bodyStart, bodyNode: Integer;
    savedNest, savedTok: Integer;
    retType: TTypeKind; isProc: Boolean;
begin
  PyParseDefHeader;
  name := PyHdrName;
  nparams := PyHdrNParams;
  isProc := PyHdrIsProc;
  retType := PyHdrRetType;
  bodyStart := TokPos - 1;

  { Reuse the shell PyRegisterDefShells registered for this def. A shell has
    BodyAddr = -1; anything else means the name is being DEFINED AGAIN, which
    Python allows, so that gets its own Proc rather than overwriting the first
    one's body address out from under earlier callers. }
  { A NESTED def registers under its enclosing def's qualifier, which is what
    PyParseStatement already put in the queue entry — see PyNestPrefix. }
  if PyNestPrefix <> '' then name := PyNestPrefix + '.' + name;
  procIdx := FindProc(name);
  if (procIdx < 0) or (Procs[procIdx].BodyAddr >= 0) then
  begin
    procIdx := RegisterProc(name, not isProc, retType, nparams,
                            PyHdrPNames, PyHdrPTypes);
    PyApplyDefSignature(procIdx);
  end;
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
  Procs[procIdx].BodyAddr := CodeLen;
  { Defs nested in THIS body qualify with this def's own (already qualified)
    name, so `outer.inner.deeper` stays unique at any depth. Set BEFORE the
    local-typing pre-pass: that pre-pass trial-parses the body, so it meets the
    nested defs too and must register their shells under the same qualifier the
    real parse will look for. }
  savedPfx := PyNestPrefix;
  savedNest := PyPendNestCount;
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
    idx := AllocParam(PyHdrPNames[i], PyHdrPTypes[i],
                      PyHdrPTypes[i] = tyVariant, False);
    Procs[procIdx].Params[i].SymIdx := idx;
    Procs[procIdx].Params[i].IsRef := PyHdrPTypes[i] = tyVariant;
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
    idx := AllocVar('Result', retType);
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
  for i := 0 to PyLocalCount - 1 do
    if PyProgSym(PyLocals[i].Name) < 0 then
    begin
      idx := AllocVar(PyLocals[i].Name, PyLocals[i].TypeKind);
      if (PyLocals[i].TypeKind = tyClass) and (PyLocals[i].RecCi >= 0) then
        Syms[idx].RecName := REC_UCLASS_BASE + PyLocals[i].RecCi;
    end;

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
  CompileAST(bodyNode);
  EmitProcEpilog(Procs[procIdx].RetSymIdx);
  PatchProcPrologue(patchPos, FrameSize);
  SymRollbackTo(savedSC);
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
function PyInferDefRetType(methodStart: Integer; var retRec: Integer): TTypeKind;
var j, pdepth, bdepth, e, k, e2, rec2, bodyScanStart: Integer;
    t2: TTypeKind;
begin
  Result := tyInteger;
  retRec := REC_NONE;
  rec2 := -1;
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
    else if Tokens[j].Kind = tkFunction then Exit   { a nested def: stop }
    else if (Tokens[j].Kind = tkExit) and (bdepth >= 1) then
    begin
      if (j + 1 >= TokCount) or
         (Tokens[j + 1].Kind in [tkNewline, tkDedent, tkEOF]) then Exit;
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
      Result := PyInferExprType(j + 1, e);
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
      if ((Result = tyUnknown) or (Result = tyInteger) or TypeIsPromoInt(Result)) and
         (e = j + 2) and (Tokens[j + 1].Kind = tkIdent) then
      begin
        for k := bodyScanStart to j - 1 do
          if (Tokens[k].Kind = tkIdent) and (k + 1 < TokCount) and
             (Tokens[k + 1].Kind = tkAssign) and
             CaseEqual(GetTokenStr(k), GetTokenStr(j + 1)) then
          begin
            e2 := k + 2;
            while (e2 < TokCount) and not (Tokens[e2].Kind in [tkNewline, tkDedent, tkEOF]) do
              Inc(e2);
            t2 := PyInferExprType(k + 2, e2);
            if (t2 <> tyUnknown) and (t2 <> tyInteger) then
            begin
              Result := t2;
              rec2 := PyInferLastCi;
            end;
          end;
        if (Result = tyClass) and (rec2 >= 0) then
          PyInferLastCi := rec2;
      end;
      if Result = tyUnknown then Result := tyInteger;
      if Result = tyString then Result := tyAnsiString;
      { A PROMOTABLE INT cannot cross the call boundary raw: its rvalue is the
        frame SLOT ADDRESS and the frame dies at return — the caller read a
        stack address as the value (uforth /STRING returned garbage and the
        word list was walked through it -> wild jump). Box to a variant
        (inline -> VT_INT64, heap -> VT_PROMO), which the Result store and
        every caller already handle. }
      if TypeIsPromoInt(Result) then Result := tyVariant;
      if (Result = tyClass) and (PyInferLastCi >= 0) then
        retRec := REC_UCLASS_BASE + PyInferLastCi;
      Exit;
    end;
    Inc(j);
  end;
end;

{ Does the def's body contain a VALUE-bearing `return`? (`return` bare and
  `return None` do not count.) Used to override a LYING `-> None` annotation:
  CPython ignores annotations entirely, and uforth's finalize_definition is
  annotated `-> None` yet returns the new Word — trusting the annotation
  compiled it as a procedure and the caller read garbage (the :NONAME xt). }
function PyDefHasValueReturn(defIdx: Integer): Boolean;
var j, pdepth, bdepth: Integer;
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
    else if Tokens[j].Kind = tkFunction then Exit   { a nested def: stop }
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
    fldAnn, rhsAt, k2, fldSig: Integer;
    origName, name, fullName, rhsName: AnsiString; isCtor: Boolean;
    fldRec, mRetRec, pri: Integer; mRet: TTypeKind;
    pnames: array[0..15] of AnsiString; ptypes: array[0..15] of TTypeKind;
    pdefHas: array[0..15] of Boolean; pdefIsStr: array[0..15] of Boolean;
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
               CaseEqual(GetTokenStr(j + 4), 'list') and
               (j + 5 < bodyEnd) and (Tokens[j + 5].Kind = tkRParen) then
            begin
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
              Error('Nil Python: unsupported dataclass field default (field(default_factory=list) and a zero-arg lambda are the supported forms)');
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
      while Tokens[j].Kind <> tkRParen do
      begin
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
      { str is managed here as everywhere else in NilPy }
      if mRet = tyString then mRet := tyAnsiString;
      if mRet <> tyClass then mRetRec := REC_NONE;
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
        { Trailing constant defaults. The shared call path already fills
          omitted trailing args from these arrays (symtab.inc), so a NilPy
          method with defaults needs no call-site work of its own. }
        for k := 0 to nparams - 1 do
          if pdefHas[k] and (k < MAX_PROC_PARAMS) then
          begin
            ProcParamHasDefault[procIdx * MAX_PROC_PARAMS + k] := True;
            ProcParamDefaultVal[procIdx * MAX_PROC_PARAMS + k] := pdefVal[k];
            ProcParamDefaultIsStr[procIdx * MAX_PROC_PARAMS + k] := pdefIsStr[k];
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
      { Constructor assignments define fields: self.name = annotated_param. }
      if isCtor then
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
              tk := PyTypeFromTokenIndex(rhsAt);
              fldRec := PyRecFromTokenIndex(rhsAt);
              if (tk = tyUnknown) and (Tokens[rhsAt].Kind = tkIdent) then
              begin
                rhsName := GetTokenStr(rhsAt);
                tk := PyHeaderParamType(methodStart, j, rhsName);
                fldSig := PyAnnLastProcSig;
                fldRec := PyHeaderParamRec(methodStart, j, rhsName);
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
              ErrorAt(Tokens[j].Line,
                      'Nil Python: cannot infer the type of field self.'
                      + GetTokenStr(j + 2) + ' - annotate it (self.'
                      + GetTokenStr(j + 2) + ': int = ...)');
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
var origName, name, fullName: AnsiString; procIdx, i, idx, nparams, savedSC, savedFS,
    savedSelf, patchPos, bodyNode, bodyStart, annIdx: Integer; pnames: array[0..15] of AnsiString;
    ptypes: array[0..15] of TTypeKind; pcis: array[0..15] of Integer;
    isCtor: Boolean;
    savedNest, savedTok: Integer; savedPfx, savedPfx2: AnsiString;
begin
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
    pnames[nparams] := CurTok.SVal; Next;
    if (nparams = 0) and (pnames[nparams] = 'self') then
    begin ptypes[nparams] := tyClass; pcis[nparams] := ci; end
    else if CurTok.Kind <> tkColon then
    begin
      { UNANNOTATED parameter -> Any (variant); must match the pre-pass. }
      ptypes[nparams] := tyVariant; pcis[nparams] := -1;
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
  else if isCtor then
    Error('Nil Python: __init__ must be annotated -> None');
  Expect(tkColon, ':'); Expect(tkNewline, 'newline'); Expect(tkIndent, 'indent');
  bodyStart := TokPos - 1;
  fullName := PyRawName(UClsNOff[ci], UClsNLen[ci]); AppendChar(fullName, '.');
  for i := 1 to Length(name) do AppendChar(fullName, name[i]);
  procIdx := FindProc(fullName);
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
  end;
  if not isCtor then
  begin
    idx := AllocVar('Result', Procs[procIdx].RetType);
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
  CompileAST(bodyNode); EmitProcEpilog(Procs[procIdx].RetSymIdx); PatchProcPrologue(patchPos, FrameSize);
  SymRollbackTo(savedSC); FrameSize := savedFS; CurProc := -1; CurSelfClass := savedSelf;
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
end;

{ Emit the synthesized @dataclass ctor body: spill params, then
  self.field_i := param_i for every field, via the ordinary AST path. }
{ Zero a MANAGED Result slot at body entry.

  A method's Result is allocated by the class-member pre-pass, where CurProc is
  not yet set, so AllocVar marks it skGlobal -- and IR_ZERO_SYM's codegen only
  zeroes skLocal. The slot therefore kept stale stack bytes, and the first
  `Result := <str>` released that garbage as if it were a string handle:
  `decq -0x10(%rax)` on a wild pointer. It only reproduced when the frame
  happened to hold something non-zero there, which is why a class needed a
  constructor before `-> str` crashed (bug-nilpy-method-returning-str-garbage).

  Emitting an ordinary AN_VAR_DECL at the head of the body reuses the normal
  local zero-init path rather than adding a second mechanism. Managed kinds
  only: an integer Result reading stale bytes is harmless and zeroing it would
  change existing output. }
function PyPrependResultZero(procIdx, bodyNode: Integer): Integer;
var rs, declNode, seqNode, rtk: Integer;
begin
  PyPrependResultZero := bodyNode;
  rs := Procs[procIdx].RetSymIdx;
  if rs < 0 then Exit;
  rtk := Ord(Syms[rs].TypeKind);
  if (rtk <> Ord(tyAnsiString)) and (rtk <> Ord(tyVariant)) then Exit;
  Syms[rs].Kind := skLocal;      { it IS a frame slot; the pre-pass mislabelled it }
  declNode := AllocNode(AN_VAR_DECL);
  ASTIVal[declNode] := rs;
  ASTLeft[declNode] := -1;
  seqNode := AllocNode(AN_SEQ);
  ASTLeft[seqNode] := declNode;
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
  i := 0;
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
    else if isDC and (CurTok.Kind = tkIdent) then
    begin
      { dataclass field line — already registered; skip to end of line }
      while not (CurTok.Kind in [tkNewline, tkDedent, tkEOF]) do Next;
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
    else
    begin
      PyParseMethod(ci);
      PySkipNewlines;
    end;
  end;
  Expect(tkDedent, 'dedent');
  if isDC then PyEmitDataclassCtor(ci);
end;

procedure ParsePyProgram;
var mainNode, stmt, blockNode, jmpPatch, i, savedUnitIdx: Integer; needsBuiltin: Boolean;
    pyHasExceptions: Boolean;
    dummyNames: array[0..3] of AnsiString;
    dummyTypes: array[0..3] of TTypeKind;
    impName: AnsiString; isCount: Boolean;
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
  while (CurTok.Kind = tkUses) or PyIsIdent('from') do
  begin
    if PyIsIdent('from') then
    begin
      Next;
      if CurTok.Kind <> tkIdent then
        Error('Nil Python: expected a module name after from');
      impName := CurTok.SVal;
      Next;
      if CurTok.Kind <> tkUses then
        Error('Nil Python: expected import after from ' + impName);
      Next;
      { itertools is consumed-but-unresolved for now: uforth only needs
        count(); its use sites wall visibly until a shim lands (Track B). }
      if CaseEqual(impName, 'dataclasses') or CaseEqual(impName, 'typing') or
         CaseEqual(impName, 'itertools') then
      begin
        while CurTok.Kind = tkIdent do
        begin
          isCount := CaseEqual(impName, 'itertools') and
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
        Error('Nil Python: from-import of module ' + impName + ' is not supported yet');
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
        if CaseEqual(CurTok.SVal, 'sys') or CaseEqual(CurTok.SVal, 'os') or
           CaseEqual(CurTok.SVal, 'textwrap') or CaseEqual(CurTok.SVal, 'select') or
           CaseEqual(CurTok.SVal, 'itertools') then
          { skip }
        else
          ParseUsesUnit(CurTok.SVal);
        Next;
        if not Eat(tkComma) then Break;
      end;
      PySkipNewlines;
    end;
  end;
  { Module-local type collection runs AFTER the units above so proc return
    types (len, VariantToStr, pylib methods) resolve during inference. }
  PyRegisterClassFieldsPrepass;   { fields must exist before local inference }
  PyRegisterDefShells;            { def signatures must exist before it too }
  PyCollectModuleLocalsAST;
  PyExprMode := True;   { Pascal RTL units are loaded; from here on, .npy expression
                          parsing uses Python and/or/not precedence }
  mainNode := -1;
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
      mainNode := PyFlushHoist(mainNode);
      mainNode := PySeqAppend(mainNode, stmt);
      { several simple statements on one line, as in PyParseBlock }
      while CurTok.Kind = tkSemicolon do
      begin
        Next;
        if CurTok.Kind in [tkNewline, tkDedent, tkEOF] then Break;
        stmt := PyParseStatement;
        mainNode := PyFlushHoist(mainNode);
        mainNode := PySeqAppend(mainNode, stmt);
      end;
    end;
    PySkipNewlines;
  end;
  Patch32(jmpPatch, CodeLen - (jmpPatch + 4));
  blockNode := AllocNode(AN_BLOCK);
  ASTLeft[blockNode] := mainNode;
  ASTTk[blockNode] := Ord(tyUnknown);
  PyExprMode := False;
  CompileAST(blockNode);
  EmitExit(0);
  { Patch forward proc-call placeholders (e.g. the builtin heap allocator,
    whose body is compiled after the string runtime that calls it). Pascal
    ParseProgram does this; .npy needs it too now that string/variant codegen
    calls PXXAlloc. }
  ApplyCallFixups;
end;
