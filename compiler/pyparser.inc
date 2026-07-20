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
  PyHdrPNames: array[0..15] of AnsiString;
  PyHdrPTypes: array[0..15] of TTypeKind;
  PyHdrPCis: array[0..15] of Integer;
  PyHdrDefHas: array[0..15] of Boolean;
  PyHdrDefIsStr: array[0..15] of Boolean;
  PyHdrDefVal: array[0..15] of Int64;
  PyHdrDefSOff: array[0..15] of Integer;
  PyHdrDefSLen: array[0..15] of Integer;
  { @dataclass field defaults, appended in declaration order per class ci.
    Looked up positionally by PyClassCreate to fill omitted trailing args. }
  PyDcCi:   array[0..PY_MAX_DC_FIELDS-1] of Integer;
  PyDcKind: array[0..PY_MAX_DC_FIELDS-1] of Integer;
  PyDcIVal: array[0..PY_MAX_DC_FIELDS-1] of Int64;
  PyDcSOff: array[0..PY_MAX_DC_FIELDS-1] of Integer;
  PyDcSLen: array[0..PY_MAX_DC_FIELDS-1] of Integer;
  PyDcCount: Integer;
  PyDcClassIsDc: array[0..PY_MAX_DC_FIELDS-1] of Boolean;  { indexed by ci }

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
      if lo = 'int' then Result := tyInteger
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

function PyDictLiteralAhead: Boolean;
begin
  Result := PyDictLiteralAt(TokPos - 1);   (* TokPos-1 = the opening brace *)
end;

var
  PyLastTypeCi: Integer;  { class index when PyParseType returned tyClass }
  PyAnnLastCi: Integer;   { class index when PyAnnTypeAt returned tyClass }
  PyCountAlias: AnsiString;  { local name bound to itertools.count ('' = none) }

{ Token-index annotation parser for the richer grammar dataclass fields use:
    NAME | NAME '[' ann {',' ann} ']' | "ForwardRef" | None
  v1 mapping (uforth rung): Optional[X] -> X with nil/0 for None (an
  Optional[int] whose legit value could be 0 would alias the sentinel — noted
  in the ticket; honest variant-tagged fields come later), Callable[...] ->
  tyPointer, Any -> tyVariant, container types (List/Dict/Tuple/Set) remain a
  clean unsupported error. Advances i past the annotation. }
function PyAnnTypeAt(var i: Integer): TTypeKind;
var lo: AnsiString; depth: Integer;
begin
  Result := tyUnknown;
  PyAnnLastCi := -1;
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
  if lo = 'int' then begin Result := tyInteger; Inc(i); Exit; end;
  if lo = 'float' then begin Result := tyDouble; Inc(i); Exit; end;
  if lo = 'bool' then begin Result := tyBoolean; Inc(i); Exit; end;
  if lo = 'str' then begin Result := tyString; Inc(i); Exit; end;
  if lo = 'any' then begin Result := tyVariant; Inc(i); Exit; end;
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
    end;
    Exit;
  end;
  if lo = 'callable' then
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
  if (a = tyVariant) or (b = tyVariant) then
  begin
    if ((a = tyVariant) or PyVariantScalar(a)) and
       ((b = tyVariant) or PyVariantScalar(b)) then
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

    tyString wins, deliberately. The token scanner typed EVERY string
    expression tyString by construction, so that is the storage model NilPy
    locals have always had and the one the RTL paths are exercised against;
    picking tyAnsiString here instead silently converted every inferred string
    local to a managed one and produced heap corruption in test_nilpy_str_param
    (a `-> str` def returning a char, followed by a def with managed locals).
    Moving NilPy to managed strings is its own ticket, not a side effect of
    changing where the type comes from. }
  if ((a = tyString) or (a = tyAnsiString)) and
     ((b = tyString) or (b = tyAnsiString)) then
  begin
    Result := tyString;
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
      term := OrJoin(OrJoin(TagEq(VT_INT), TagEq(VT_INT64)), TagEq(VT_BOOL))
    else if nm = 'float' then term := TagEq(VT_DOUBLE)
    else if nm = 'str' then term := TagEq(VT_STRING)
    else if nm = 'bool' then term := TagEq(VT_BOOL)
    else
    begin
      ci := FindUClass(CurTok.SVal);
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
var left, right, node: Integer; op: TTokenKind;
begin
  PyParseBitOperand;
  left := CurASTNode;
  while (CurTok.Kind = tkShl) or (CurTok.Kind = tkShr) do
  begin
    op := CurTok.Kind;
    PyBitGuard(left); Next; PyParseBitOperand; right := CurASTNode; PyBitGuard(right);
    node := AllocNode(AN_BINOP); ASTIVal[node] := Ord(op);
    ASTLeft[node] := left; ASTRight[node] := right;
    ASTTk[node] := Ord(PyWiden(IntToTypeKind(ASTTk[left]), IntToTypeKind(ASTTk[right])));
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
      else if ResolveNodeRec(right) = REC_UCLASS_BASE + FindUClass('TPyDict') then
        node := FindProc('pydictcontains')
      else
        node := FindProc('pycontains');
      if node < 0 then Error('Nil Python: pylib (pycontains) not loaded');
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
var node, zeroNode, operand: Integer; opTk: TTypeKind;
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
      keep AN_NOT, where it is already logical. Non-ordinals (a string, a
      class, a variant) still go through AN_NOT unchanged — `not <container>`
      is its own question, filed separately rather than guessed at here. }
    if (opTk = tyBoolean) or not PyNumeric(opTk) then
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
    node := AllocNode(AN_BINOP); ASTIVal[node] := Ord(tkAnd);
    ASTLeft[node] := left; ASTRight[node] := right; ASTTk[node] := Ord(tyBoolean);
    left := node;
  end;
  CurASTNode := left;
end;

procedure PyParseBoolExpr;
var left, right, node: Integer;
begin
  PyParseBoolAnd;
  left := CurASTNode;
  while CurTok.Kind = tkOr do
  begin
    Next;
    PyParseBoolAnd;
    right := CurASTNode;
    node := AllocNode(AN_BINOP); ASTIVal[node] := Ord(tkOr);
    ASTLeft[node] := left; ASTRight[node] := right; ASTTk[node] := Ord(tyBoolean);
    left := node;
  end;
  CurASTNode := left;
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
  else if CaseEqual(mname, 'strip') then pname := 'pystr_strip'
  else if CaseEqual(mname, 'lstrip') then pname := 'pystr_lstrip'
  else if CaseEqual(mname, 'rstrip') then pname := 'pystr_rstrip'
  else if CaseEqual(mname, 'startswith') then
    begin pname := 'pystr_startswith'; retTk := tyBoolean; wantArgs := 1; end
  else if CaseEqual(mname, 'endswith') then
    begin pname := 'pystr_endswith'; retTk := tyBoolean; wantArgs := 1; end
  else if CaseEqual(mname, 'find') then
    begin pname := 'pystr_find'; retTk := tyInteger; wantArgs := 1; end
  else if CaseEqual(mname, 'isspace') then
    begin pname := 'pystr_isspace'; retTk := tyBoolean; end
  else if CaseEqual(mname, 'join') then
    begin pname := 'pystr_join'; wantArgs := 1; end
  else if CaseEqual(mname, 'split') then
    { 0 or 1 args, and the two forms are DIFFERENT algorithms — see pylib.
      PyParseStrMethod picks the concrete function from the arg count. }
    begin pname := 'pystr_split_sep'; retTk := tyClass; wantArgs := -1; end
  else if CaseEqual(mname, 'splitlines') then
    begin pname := 'pystr_splitlines'; retTk := tyClass; end
  else
  begin
    pname := '';
    Result := False;
  end;
end;

function PyInferExprType(startIdx, endIdx: Integer): TTypeKind;
var i, ci, si, procIdx, depth, smArgs, fci, fi: Integer; tk: TTypeKind;
    name, lo, smPName: AnsiString;
begin
  Result := tyUnknown;
  PyInferLastCi := -1;
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
          si := FindSym(name);
          if si >= 0 then tk := Syms[si].TypeKind;
        end;
        { obj.method(...) on a class-typed name: the expression's type is the
          METHOD's return type; skip the whole postfix chain. }
        if (tk = tyClass) and (ci >= 0) and (PyLocals[ci].RecCi >= 0) and
           (i + 3 < endIdx) and (Tokens[i + 1].Kind = tkDot) and
           (Tokens[i + 2].Kind = tkIdent) and (Tokens[i + 3].Kind = tkLParen) then
        begin
          si := FindUMeth(PyLocals[ci].RecCi, GetTokenStr(i + 2));
          if si >= 0 then
          begin
            tk := Procs[UMthProc_[si]].RetType;
            if tk = tyClass then PyInferLastCi := ProcRetRecId[UMthProc_[si]];
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
  ErrorAt(Tokens[j].Line,
          'Nil Python: the default for parameter ' + pname
          + ' must be a constant (None, True, False, an integer or a string)');
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

function PyClassCreate: Integer;
var name: AnsiString; ci, recId, node, argNode, lastArg, sizeNode: Integer;
    nArgs, i, k, dcBase, valNode, tkNode, ctorMi, ctorPi: Integer; tkF: TTypeKind;
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
  while CurTok.Kind <> tkRParen do
  begin
    PyParseBoolExpr;
    argNode := AllocNode(AN_ARG);
    ASTLeft[argNode] := CurASTNode;
    ASTRight[lastArg] := argNode;
    lastArg := argNode;
    Inc(nArgs);
    if not Eat(tkComma) then break;
  end;
  Expect(tkRParen, ')');
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
        i := dcBase + nArgs;
        if (i >= PyDcCount) or (PyDcCi[i] <> ci) or (PyDcKind[i] = PYDC_NONE) then
          Error('Nil Python: missing argument for dataclass field without default: ' + name);
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
    procIdx, callNode, argNode, lastArg, i, wantArgs: Integer;
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
  while CurTok.Kind <> tkRParen do
  begin
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
  if wantArgs < 0 then
  begin
    { optional-argument form: split() and split(sep) are separate functions }
    if i = 0 then pname := 'pystr_split_ws'
    else if i <> 1 then
      Error('Nil Python: str method .' + mname + '() takes at most one argument');
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

function PyParsePrint: Integer;
var node, argNode, lastArg, sepLit: Integer;
begin
  Next;
  Expect(tkLParen, '(');
  node := AllocNode(AN_WRITELN);
  lastArg := -1;
  if CurTok.Kind <> tkRParen then
    repeat
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
      PyParseBoolExpr;
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
  Result := node;
end;

function PyParseIf: Integer;
var node, pairNode, condNode, thenNode, elseNode: Integer;
begin
  Next;
  PyParseBoolExpr;
  condNode := CurASTNode;
  Expect(tkColon, ':');
  Expect(tkNewline, 'newline');
  Expect(tkIndent, 'indent');
  thenNode := PyParseBlock;
  Expect(tkDedent, 'dedent');
  elseNode := -1;
  if PyIsIdent('elif') then
    elseNode := PyParseIf()
  else if CurTok.Kind = tkElse then
  begin
    Next;
    Expect(tkColon, ':');
    Expect(tkNewline, 'newline');
    Expect(tkIndent, 'indent');
    elseNode := PyParseBlock;
    Expect(tkDedent, 'dedent');
  end;
  pairNode := AllocNode(AN_PAIR);
  ASTLeft[pairNode] := thenNode;
  ASTRight[pairNode] := elseNode;
  node := AllocNode(AN_IF);
  ASTLeft[node] := condNode;
  ASTRight[node] := pairNode;
  Result := node;
end;

function PyParseWhile: Integer;
var node: Integer;
begin
  Next;
  PyParseBoolExpr;
  node := AllocNode(AN_WHILE);
  ASTLeft[node] := CurASTNode;
  Expect(tkColon, ':');
  Expect(tkNewline, 'newline');
  Expect(tkIndent, 'indent');
  ASTRight[node] := PyParseBlock;
  Expect(tkDedent, 'dedent');
  Result := node;
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
function PyParseForIn(const name: AnsiString): Integer;
var contNode, ci, dictCi, listCi, symIdx, cSym, iSym, nSym: Integer;
    elemNode, lenNode, node, cmpNode, incNode, bodyNode, seq, whileNode: Integer;
    isStr: Boolean; contTk: TTypeKind;
begin
  PyParseBoolExpr;
  contNode := CurASTNode;
  contTk := IntToTypeKind(ASTTk[contNode]);
  isStr := (contTk = tyString) or (contTk = tyAnsiString);
  listCi := FindUClass('TPyList');
  dictCi := FindUClass('TPyDict');
  ci := -1;
  if not isStr then
  begin
    ci := ResolveNodeRec(contNode);
    if ci >= REC_UCLASS_BASE then ci := ci - REC_UCLASS_BASE else ci := -1;
    if ci < 0 then
      Error('Nil Python: for-in needs a list, set, dict or str (got something untyped)');
    if (dictCi >= 0) and (ci = dictCi) then
    begin
      { iterate a dict's KEYS, as Python does }
      contNode := PyCallMeth1(dictCi, 'keylist', contNode, -1);
      if contNode < 0 then Error('Nil Python: pylib (TPyDict.keylist) not loaded');
      ci := listCi;
    end;
  end;

  Expect(tkColon, ':');
  Expect(tkNewline, 'newline');
  Expect(tkIndent, 'indent');

  { hidden locals first, so the loop variable keeps the name the user wrote }
  if isStr then cSym := AllocVar(PyHiddenName('c'), tyAnsiString)
  else cSym := AllocVar(PyHiddenName('c'), tyClass);
  if not isStr then Syms[cSym].RecName := REC_UCLASS_BASE + ci;
  nSym := AllocVar(PyHiddenName('n'), tyInteger);
  iSym := AllocVar(PyHiddenName('i'), tyInteger);
  symIdx := FindSym(name);
  if symIdx < 0 then
  begin
    if isStr then symIdx := AllocVar(name, tyAnsiString)
    else symIdx := AllocVar(name, tyVariant);
  end;

  { __py_c := container }
  seq := -1;
  node := AllocNode(AN_ASSIGN);
  ASTLeft[node] := PyMakeIdent(cSym);
  ASTRight[node] := contNode;
  seq := PySeqAppend(seq, node);

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
    elemNode := PyCallMeth1(ci, 'get', PyMakeIdent(cSym), PyMakeIdent(iSym));
    if elemNode < 0 then Error('Nil Python: pylib (get) not loaded');
  end;
  node := AllocNode(AN_ASSIGN);
  ASTLeft[node] := PyMakeIdent(symIdx);
  ASTRight[node] := elemNode;
  bodyNode := PySeqAppend(bodyNode, node);

  node := PyParseBlock;
  Expect(tkDedent, 'dedent');
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
  Result := PySeqAppend(seq, whileNode);
end;

function PyParseFor: Integer;
var name: AnsiString; symIdx, node, lhsNode, startNode, stopNode, stepNode: Integer;
    pair1, pair2, pair3, bodyNode, oneNode, limitNode: Integer;
begin
  Next;
  if CurTok.Kind <> tkIdent then Error('Nil Python: expected loop variable after for');
  name := CurTok.SVal;
  Next;
  Expect(tkIn, 'in');
  { `for x in range(...)` keeps the counted-loop lowering below; anything else
    is a container and goes through the desugar. }
  if not (PyIsIdent('range') and (TokPos < TokCount) and
          (Tokens[TokPos].Kind = tkLParen)) then
  begin
    Result := PyParseForIn(name);
    Exit;
  end;
  symIdx := FindSym(name);
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
  if Eat(tkComma) then
  begin
    PyParseBoolExpr;
    stepNode := CurASTNode;
    if (ASTKind[stepNode] <> AN_INT_LIT) or (ASTIVal[stepNode] <> 1) then
      Error('Nil Python: range step other than 1 is not supported in v1');
  end;
  Expect(tkRParen, ')');
  Expect(tkColon, ':');
  Expect(tkNewline, 'newline');
  Expect(tkIndent, 'indent');
  bodyNode := PyParseBlock;
  Expect(tkDedent, 'dedent');

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

function PyParseStatement: Integer;
var name: AnsiString; symIdx, lhsNode, node, ci, rhsNode, annIdx, delBase: Integer; tk: TTypeKind;
    augTk: TTokenKind;
begin
  Result := -1;
  if CurTok.Kind = tkIf then begin Result := PyParseIf; Exit; end;
  if CurTok.Kind = tkWhile then begin Result := PyParseWhile; Exit; end;
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
    ci := FindUClass('TPyDict');
    symIdx := -1;
    if ci >= 0 then symIdx := FindUMeth(ci, 'fetch');
    if (symIdx < 0) or (ASTKind[delBase] <> AN_CALL) or
       (ASTIVal[delBase] <> UMthProc_[symIdx]) then
      Error('Nil Python: del is supported on a dict subscript only (del d[k])');
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
    { v1: super().__init__(...) is consumed and DISCARDED (args unevaluated).
      The Exception base is an empty shell until the try/except rung lands;
      argument side effects would be lost — none in the censused corpus. }
    Next; Expect(tkLParen, '('); Expect(tkRParen, ')');
    Expect(tkDot, '.');
    if CurTok.Kind <> tkIdent then Error('Nil Python: expected method after super().');
    Next;
    Expect(tkLParen, '(');
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
    if CurTok.Kind in [tkNewline, tkDedent, tkEOF] then
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
      ASTTk[node] := ASTTk[lhsNode];
      rhsNode := node;
    end
    else
    begin
      Expect(tkAssign, '=');
      if PyIsEmptySetCall then
        rhsNode := PyParseEmptySet
      else if PyIsCountCall then
        rhsNode := PyParseCountCreate
      else
      begin
        PyParseBoolExpr;
        rhsNode := CurASTNode;
      end;
    end;
    { `Word._xt_counter = _count(1)`: a class-static (AN_IDENT of the
      backing global) learns its class from a class-typed rhs. }
    if (ASTKind[lhsNode] = AN_IDENT) and
       (ASTKind[rhsNode] = AN_CALL) and (ASTIVal[rhsNode] = -Ord(tkGetMem)) then
      Syms[ASTIVal[lhsNode]].RecName := ASTRight[rhsNode];
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
    symIdx := FindSym(name);
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
    ASTTk[node] := Ord(Syms[symIdx].TypeKind);
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
    if (tk <> tyUnknown) and (annIdx < TokCount) and
       (Tokens[annIdx].Kind = tkAssign) then
    begin
      name := CurTok.SVal;
      TokPos := annIdx;
      Next;                      { CurTok = '=' }
      Expect(tkAssign, '=');
      PyParseBoolExpr;
      symIdx := FindSym(name);
      if symIdx < 0 then
      begin
        symIdx := AllocVar(name, tk);
        if (tk = tyClass) and (ci >= 0) then
          Syms[symIdx].RecName := REC_UCLASS_BASE + ci;
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
    symIdx := FindSym(name);
    Next;
    Expect(tkAssign, '=');
    if (CurTok.Kind = tkIdent) and IsClassType(CurTok.SVal) and
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
    Result := PySeqAppend(Result, stmt);
    if CurTok.Kind = tkNewline then PySkipNewlines
    else if (stmt >= 0) and (ASTKind[stmt] in [AN_IF, AN_WHILE, AN_FOR]) then
      continue
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
      if FindSym(PyLocals[i].Name) < 0 then
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
      if FindSym(PyLocals[i].Name) < 0 then
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
        { A method call on a NAME is skipped, not parsed: class members are not
          registered until PyParseClass reaches the class, so trial-parsing
          `x = c.two(1)` here would fail on a method that is perfectly valid a
          moment later. Skipping costs nothing — the real parse declares the
          local from the same AST rule — it only forgoes WIDENING for that
          name, which is what the annotated form is for. A method call on a
          literal (`"a,b".split(",")`) is not affected: its base is not an
          identifier. }
        bodyIx := i + 2;
        while (bodyIx + 2 < MainProgramTokCount) and
              not (Tokens[bodyIx].Kind in [tkNewline, tkDedent]) do
        begin
          if (Tokens[bodyIx].Kind = tkIdent) and
             (Tokens[bodyIx + 1].Kind = tkDot) and
             (Tokens[bodyIx + 2].Kind = tkIdent) and
             (bodyIx + 3 < MainProgramTokCount) and
             (Tokens[bodyIx + 3].Kind = tkLParen) then Break;
          Inc(bodyIx);
        end;
        if (bodyIx + 2 < MainProgramTokCount) and
           (Tokens[bodyIx].Kind = tkIdent) and (Tokens[bodyIx + 1].Kind = tkDot) then
        begin
          while (bodyIx < MainProgramTokCount) and
                not (Tokens[bodyIx].Kind in [tkNewline, tkDedent]) do Inc(bodyIx);
          i := bodyIx;
          continue;
        end;
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
procedure PyParseDefHeader;
var annIdx: Integer;
begin
  if CurTok.Kind <> tkFunction then Error('Nil Python: expected def');
  Next;
  if CurTok.Kind <> tkIdent then Error('Nil Python: expected function name');
  PyHdrName := CurTok.SVal;
  Next;
  Expect(tkLParen, '(');
  PyHdrNParams := 0;
  while CurTok.Kind <> tkRParen do
  begin
    if PyHdrNParams >= 16 then Error('Nil Python: too many parameters');
    if CurTok.Kind <> tkIdent then Error('Nil Python: expected parameter name');
    PyHdrPNames[PyHdrNParams] := CurTok.SVal;
    Next;
    Expect(tkColon, ':');
    { same full annotation grammar as a method parameter }
    annIdx := TokPos - 1;
    PyHdrPTypes[PyHdrNParams] := PyAnnTypeAt(annIdx);
    PyHdrPCis[PyHdrNParams] := PyAnnLastCi;
    if PyHdrPTypes[PyHdrNParams] = tyUnknown then
      ErrorAt(Tokens[annIdx].Line,
              'Nil Python: parameter ' + PyHdrPNames[PyHdrNParams]
              + ' has an unsupported type annotation');
    TokPos := annIdx;
    Next;
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
  Expect(tkMinus, '- in ->');
  Expect(tkGt, '> in ->');
  { `-> None` declares a procedure (no Result). }
  PyHdrIsProc := CurTok.Kind = tkNil;
  PyHdrRetCi := -1;
  if PyHdrIsProc then begin PyHdrRetType := tyInteger; Next; end
  else begin PyHdrRetType := PyParseType; PyHdrRetCi := PyLastTypeCi; end;
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
var name: AnsiString;
    nparams, i, procIdx, idx, savedSC, savedFS, patchPos, bodyStart, bodyNode: Integer;
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
  procIdx := FindProc(name);
  if (procIdx < 0) or (Procs[procIdx].BodyAddr >= 0) then
  begin
    procIdx := RegisterProc(name, not isProc, retType, nparams,
                            PyHdrPNames, PyHdrPTypes);
    PyApplyDefSignature(procIdx);
  end;
  Procs[procIdx].BodyAddr := CodeLen;
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
    if FindSym(PyLocals[i].Name) < 0 then
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
  bodyNode := PyParseBlock;
  Expect(tkDedent, 'dedent');
  CompileAST(bodyNode);
  EmitProcEpilog(Procs[procIdx].RetSymIdx);
  PatchProcPrologue(patchPos, FrameSize);
  SymRollbackTo(savedSC);
  FrameSize := savedFS;
  CurProc := -1;
end;

function PyMethodName(const name: AnsiString): AnsiString;
begin
  if name = '__init__' then Result := 'create' else Result := name;
end;

function PyHeaderParamType(methodStart, stopIdx: Integer; const name: AnsiString): TTypeKind;
var i: Integer;
begin
  Result := tyUnknown;
  for i := methodStart to stopIdx - 2 do
    if (Tokens[i].Kind = tkIdent) and (GetTokenStr(i) = name) and
       (Tokens[i + 1].Kind = tkColon) then
    begin
      Result := PyTypeFromTokenIndex(i + 2);
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
function PyMethodRetType(methodStart: Integer; var retRec: Integer): TTypeKind;
var j, pdepth: Integer;
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
    Result := PyTypeFromTokenIndex(j + 3);
    retRec := PyRecFromTokenIndex(j + 3);
  end;
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
var i, j, k, depth, methodStart, nparams, procIdx, mmi, slot, curOff, align, sz: Integer;
    fldAnn, rhsAt, k2: Integer;
    origName, name, fullName, rhsName: AnsiString; isCtor: Boolean;
    fldRec, mRetRec: Integer; mRet: TTypeKind;
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
  curOff := 8;
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
      if (tk = tyClass) and (PyAnnLastCi >= 0) then
        AddUField(ci, Tokens[i].SOffset, Tokens[i].SLen, curOff, Ord(tk),
                  REC_UCLASS_BASE + PyAnnLastCi)
      else
        AddUField(ci, Tokens[i].SOffset, Tokens[i].SLen, curOff, Ord(tk), REC_NONE);
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
            ErrorAt(Tokens[j].Line,
                    'Nil Python: parameter ' + pnames[nparams]
                    + ' needs a type annotation');
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
      if (not fieldsOnly) and (not isCtor) and
         (RetViaHiddenDest(mRet)) then
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
      else
        AddUMeth(ci, Tokens[i + 1].SOffset, Tokens[i + 1].SLen, procIdx);
      if not fieldsOnly then
      begin
        mmi := UMthCount - 1;
        if not isCtor then
        begin
          slot := UClsVirtCount[ci];
          UClsVirtCount[ci] := UClsVirtCount[ci] + 1;
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
              AddUField(ci, Tokens[j + 2].SOffset, Tokens[j + 2].SLen, curOff, Ord(tk), fldRec);
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
end;

procedure PyParseMethod(ci: Integer);
var origName, name, fullName: AnsiString; procIdx, i, idx, nparams, savedSC, savedFS,
    savedSelf, patchPos, bodyNode, bodyStart, annIdx: Integer; pnames: array[0..15] of AnsiString;
    ptypes: array[0..15] of TTypeKind; pcis: array[0..15] of Integer;
    isCtor: Boolean;
begin
  Expect(tkFunction, 'def');
  origName := CurTok.SVal; name := PyMethodName(origName); Next;
  isCtor := name = 'create';
  Expect(tkLParen, '(');
  nparams := 0;
  while CurTok.Kind <> tkRParen do
  begin
    pnames[nparams] := CurTok.SVal; Next;
    if (nparams = 0) and (pnames[nparams] = 'self') then
    begin ptypes[nparams] := tyClass; pcis[nparams] := ci; end
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
  Expect(tkRParen, ')'); Expect(tkMinus, '- in ->'); Expect(tkGt, '> in ->');
  { `-> None` on a NON-ctor method: accept it. Only the ctor was allowed to
    say None, so an ordinary `def m(self) -> None:` died in PyParseType with
    "expected type annotation" — while the identical top-level def has worked
    since day one (PyParseDef's isProc path). PyMethodRetType already maps the
    None annotation to tyInteger for registration, so nothing downstream
    changes; the header parse was simply stricter than the pre-pass. }
  if isCtor then Expect(tkNil, 'None')
  else if CurTok.Kind = tkNil then Next
  else PyParseType;
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
    if FindSym(PyLocals[i].Name) < 0 then
    begin
      idx := AllocVar(PyLocals[i].Name, PyLocals[i].TypeKind);
      if (PyLocals[i].TypeKind = tyClass) and (PyLocals[i].RecCi >= 0) then
        Syms[idx].RecName := REC_UCLASS_BASE + PyLocals[i].RecCi;
    end;
  Procs[procIdx].BodyAddr := CodeLen;
  patchPos := EmitProcPrologue; Procs[procIdx].FramePatch := patchPos;
  EmitAggregateDestStash(procIdx);
  PyEmitParamSpills(procIdx, nparams);
  PyInitVariantLocals(Procs[procIdx].ScopeBase);
  bodyNode := PyParseBlock; Expect(tkDedent, 'dedent');
  bodyNode := PyPrependResultZero(procIdx, bodyNode);
  CompileAST(bodyNode); EmitProcEpilog(Procs[procIdx].RetSymIdx); PatchProcPrologue(patchPos, FrameSize);
  SymRollbackTo(savedSC); FrameSize := savedFS; CurProc := -1; CurSelfClass := savedSelf;
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
var i, j, ci, bs, be, depth: Integer;
    isDC: Boolean;
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
          PyRegisterClassMembers(ci, bs, be, isDC, True);
        end;
      end;
    end;
    Inc(i);
  end;
end;

procedure PyParseClass(isDC: Boolean);
var ci, bodyStart, bodyEnd, baseCi, k: Integer;
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
      Error('Nil Python: unsupported decorator inside class (only @dataclass on classes)')
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
    dummyNames: array[0..3] of AnsiString;
    dummyTypes: array[0..3] of TTypeKind;
    impName: AnsiString; isCount: Boolean;
begin
  needsBuiltin := True;
  for i := 0 to MainProgramTokCount - 1 do
  begin
    if (Tokens[i].Kind = tkIdent) and (i + 1 < MainProgramTokCount) and
       (Tokens[i + 1].Kind = tkLParen) and
       (CaseEqual(GetTokenStr(i), 'str') or CaseEqual(GetTokenStr(i), 'val')) then
      needsBuiltin := True;
  end;
  PyCountAlias := '';
  PyDcCount := 0;
  for i := 0 to PY_MAX_DC_FIELDS - 1 do PyDcClassIsDc[i] := False;
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
  { Only NOW: the units above are ORDINARY PASCAL and their own div/mod must
    keep truncating semantics. Setting this at entry rewrote pylib's own
    `a div b` into a call to the helper being defined. }
  PyProgramMode := True;
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
      mainNode := PySeqAppend(mainNode, stmt);
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
