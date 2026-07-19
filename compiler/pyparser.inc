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

var
  PyLocals: array[0..PY_MAX_LOCALS-1] of TPyLocalConstraint;
  PyLocalCount: Integer;
  PyModuleLocals: array[0..PY_MAX_LOCALS-1] of TPyLocalConstraint;
  PyModuleLocalCount: Integer;
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

var
  PyLastTypeCi: Integer;  { class index when PyParseType returned tyClass }
  PyAnnLastCi: Integer;   { class index when PyAnnTypeAt returned tyClass }

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
  if (lo = 'dict') or (lo = 'tuple') or (lo = 'set') then
    Error('Nil Python: dict/tuple/set types are not supported yet');
  if IsClassType(GetTokenStr(i)) then
  begin
    Result := tyClass;
    PyAnnLastCi := FindUClass(GetTokenStr(i));
    Inc(i);
    Exit;
  end;
end;

function PyParseType: TTypeKind;
begin
  Result := PyTypeFromTokenIndex(TokPos - 1);
  if Result = tyUnknown then
    Error('Nil Python: expected type annotation (int, float, bool, str, or a class name)');
  if Result = tyClass then PyLastTypeCi := FindUClass(GetTokenStr(TokPos - 1))
  else PyLastTypeCi := -1;
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

{ Bitwise-not / comparison+arithmetic atom. `~` binds like a unary op. }
procedure PyParseBitOperand;
var node: Integer;
begin
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

procedure PyParseBoolNot;
var node: Integer;
begin
  if CurTok.Kind = tkNot then
  begin
    Next;
    PyParseBoolNot;
    node := AllocNode(AN_NOT);
    ASTLeft[node] := CurASTNode;
    ASTTk[node] := Ord(tyBoolean);
    CurASTNode := node;
  end
  else
    PyParseBitOr;   { bitwise chain over the comparison + arithmetic atom }
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

function PyFindModuleConstraint(const name: AnsiString): Integer;
var i: Integer;
begin
  for i := 0 to PyModuleLocalCount - 1 do
    if PyModuleLocals[i].Name = name then begin Result := i; Exit; end;
  Result := -1;
end;

{ Return type of a top-level `def name(...) -> TYPE` by scanning the program
  tokens. Used by inference when the callee is a Nil Python function not yet
  registered (module-local types are collected before defs are parsed).
  Depth-guarded to top level so class methods (bare-named) are not matched. }
function PyDefReturnType(const name: AnsiString): TTypeKind;
var i, j, depth, pdepth: Integer;
begin
  Result := tyUnknown;
  depth := 0;
  i := 0;
  while i < MainProgramTokCount do
  begin
    if Tokens[i].Kind = tkIndent then Inc(depth)
    else if Tokens[i].Kind = tkDedent then Dec(depth)
    else if (depth = 0) and (Tokens[i].Kind = tkFunction) and
            (i + 1 < MainProgramTokCount) and (Tokens[i + 1].Kind = tkIdent) and
            (GetTokenStr(i + 1) = name) and (i + 2 < MainProgramTokCount) and
            (Tokens[i + 2].Kind = tkLParen) then
    begin
      j := i + 2; pdepth := 0;
      while j < MainProgramTokCount do
      begin
        if Tokens[j].Kind = tkLParen then Inc(pdepth)
        else if Tokens[j].Kind = tkRParen then
        begin
          Dec(pdepth);
          if pdepth = 0 then Break;
        end;
        Inc(j);
      end;
      { after ')': expect `-> TYPE` }
      if (j + 3 < MainProgramTokCount) and (Tokens[j + 1].Kind = tkMinus) and
         (Tokens[j + 2].Kind = tkGt) then
        Result := PyTypeFromTokenIndex(j + 3);
      Exit;
    end;
    Inc(i);
  end;
end;

function PyInferExprType(startIdx, endIdx: Integer): TTypeKind;
var i, ci, si, procIdx, depth: Integer; tk: TTypeKind; name, lo: AnsiString;
begin
  Result := tyUnknown;
  PyInferLastCi := -1;
  if (startIdx < endIdx) and (Tokens[startIdx].Kind = tkLBrack) then
  begin
    Result := tyClass;   { list literal }
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
            procIdx := FindProc(name);
            if procIdx >= 0 then tk := Procs[procIdx].RetType
            else tk := PyDefReturnType(name);
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

procedure PyCollectLocals(bodyStart, bodyEnd: Integer);
var i, j, ci: Integer; name: AnsiString; tk: TTypeKind;
begin
  PyLocalCount := 0;
  i := bodyStart;
  while i < bodyEnd do
  begin
    if (Tokens[i].Kind = tkIdent) and (i + 1 < bodyEnd) and
       (Tokens[i + 1].Kind = tkAssign) then
    begin
      name := GetTokenStr(i);
      PyInferName := name;
      j := i + 2;
      while (j < bodyEnd) and not (Tokens[j].Kind in [tkNewline, tkDedent]) do Inc(j);
      tk := PyInferExprType(i + 2, j);
      PyInferName := '';
      if tk = tyUnknown then
        Error('Nil Python: cannot infer local type for ' + name);
      ci := PyFindConstraint(name);
      if ci < 0 then
      begin
        if PyLocalCount >= PY_MAX_LOCALS then Error('Nil Python: too many inferred locals');
        PyLocals[PyLocalCount].Name := name;
        PyLocals[PyLocalCount].TypeKind := tk;
        PyLocals[PyLocalCount].RecCi := PyInferLastCi;
        Inc(PyLocalCount);
      end
      else
        PyLocals[ci].TypeKind := PyWiden(PyLocals[ci].TypeKind, tk);
      i := j;
    end
    else
      Inc(i);
  end;
end;

procedure PyCollectModuleLocals;
var i, j, ci, depth, skipDepth: Integer; name: AnsiString; tk: TTypeKind;
    waitingForFunctionIndent: Boolean;
begin
  PyLocalCount := 0;
  depth := 0;
  skipDepth := -1;
  waitingForFunctionIndent := False;
  i := 0;
  while i < MainProgramTokCount do
  begin
    if (Tokens[i].Kind = tkFunction) or (Tokens[i].Kind = tkClass) then
      { class bodies are not module scope either: a class-level
        `name = ...` (or ClassVar line) must not become a module local }
      waitingForFunctionIndent := True
    else if Tokens[i].Kind = tkIndent then
    begin
      Inc(depth);
      if waitingForFunctionIndent then
      begin
        skipDepth := depth;
        waitingForFunctionIndent := False;
      end;
    end
    else if Tokens[i].Kind = tkDedent then
    begin
      if depth = skipDepth then skipDepth := -1;
      Dec(depth);
    end
    else if (depth = 0) and (skipDepth < 0) and (Tokens[i].Kind = tkIdent) and
            (i + 3 < MainProgramTokCount) and (Tokens[i + 1].Kind = tkColon) and
            (Tokens[i + 3].Kind = tkAssign) and
            (PyTypeFromTokenIndex(i + 2) <> tyUnknown) then
    begin
      { annotated module assignment: NAME : type = expr }
      name := GetTokenStr(i);
      tk := PyTypeFromTokenIndex(i + 2);
      ci := PyFindConstraint(name);
      if ci < 0 then
      begin
        if PyLocalCount >= PY_MAX_LOCALS then Error('Nil Python: too many inferred module locals');
        PyLocals[PyLocalCount].Name := name;
        PyLocals[PyLocalCount].TypeKind := tk;
        PyLocals[PyLocalCount].RecCi := PyInferLastCi;
        Inc(PyLocalCount);
      end
      else
        PyLocals[ci].TypeKind := tk;
      j := i + 4;
      while (j < MainProgramTokCount) and not (Tokens[j].Kind in [tkNewline, tkDedent]) do Inc(j);
      i := j - 1;
    end
    else if (depth = 0) and (skipDepth < 0) and (Tokens[i].Kind = tkIdent) and
            (i + 1 < MainProgramTokCount) and (Tokens[i + 1].Kind = tkAssign) then
    begin
      name := GetTokenStr(i);
      PyInferName := name;
      j := i + 2;
      while (j < MainProgramTokCount) and not (Tokens[j].Kind in [tkNewline, tkDedent]) do Inc(j);
      tk := PyInferExprType(i + 2, j);
      PyInferName := '';
      if tk = tyUnknown then
        Error('Nil Python: cannot infer module local type for ' + name);
      ci := PyFindConstraint(name);
      if ci < 0 then
      begin
        if PyLocalCount >= PY_MAX_LOCALS then Error('Nil Python: too many inferred module locals');
        PyLocals[PyLocalCount].Name := name;
        PyLocals[PyLocalCount].TypeKind := tk;
        PyLocals[PyLocalCount].RecCi := PyInferLastCi;
        Inc(PyLocalCount);
      end
      else
        PyLocals[ci].TypeKind := PyWiden(PyLocals[ci].TypeKind, tk);
      i := j - 1;
    end;
    Inc(i);
  end;
  PyModuleLocalCount := PyLocalCount;
  for i := 0 to PyLocalCount - 1 do
    PyModuleLocals[i] := PyLocals[i];
end;

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

function PyClassCreate: Integer;
var name: AnsiString; ci, recId, node, argNode, lastArg, sizeNode: Integer;
    nArgs, i, k, dcBase, valNode: Integer; tkF: TTypeKind;
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

{ List literal [a, b, c] -> TPyList create + chained .append() calls, one
  expression tree (append returns Self). Reached from ParseFactor's PyExprMode
  tkLBrack branch, so nested literals in argument positions work too. }
procedure PyParseListLiteral;
var ci, recId, node, argNode, sizeNode, callNode, selfArg, valArg, mmi, mpi: Integer;
begin
  Expect(tkLBrack, '[');
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
  while CurTok.Kind <> tkRBrack do
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
  Expect(tkRBrack, ']');
  { mark the outermost node so assignment RecName wiring sees a list; a
    chained append is an ordinary AN_CALL whose result class is TPyList }
  CurASTNode := node;
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

function PyParseFor: Integer;
var name: AnsiString; symIdx, node, lhsNode, startNode, stopNode, stepNode: Integer;
    pair1, pair2, pair3, bodyNode, oneNode, limitNode: Integer;
begin
  Next;
  if CurTok.Kind <> tkIdent then Error('Nil Python: expected loop variable after for');
  name := CurTok.SVal;
  symIdx := FindSym(name);
  if symIdx < 0 then symIdx := AllocVar(name, tyInteger);
  Next;
  Expect(tkIn, 'in');
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
var name: AnsiString; symIdx, lhsNode, node, ci, rhsNode: Integer; tk: TTypeKind;
    augTk: TTokenKind;
begin
  Result := -1;
  if CurTok.Kind = tkIf then begin Result := PyParseIf; Exit; end;
  if CurTok.Kind = tkWhile then begin Result := PyParseWhile; Exit; end;
  if (CurTok.Kind = tkFor) or PyIsIdent('for') then begin Result := PyParseFor; Exit; end;
  if PyIsIdent('pass') then begin Next; Exit; end;
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
    augTk := PyAugBinTok(CurTok.Kind);
    if augTk <> tkEOF then
    begin
      Next;
      PyParseBoolExpr;
      node := AllocNode(AN_BINOP); ASTIVal[node] := Ord(augTk);
      ASTLeft[node] := lhsNode; ASTRight[node] := CurASTNode;
      ASTTk[node] := ASTTk[lhsNode];
      rhsNode := node;
    end
    else
    begin
      Expect(tkAssign, '=');
      PyParseBoolExpr;
      rhsNode := CurASTNode;
    end;
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
  { annotated assignment: NAME : type = expr }
  if (CurTok.Kind = tkIdent) and (TokPos + 2 < TokCount) and
     (Tokens[TokPos].Kind = tkColon) and
     (Tokens[TokPos + 2].Kind = tkAssign) and
     (PyTypeFromTokenIndex(TokPos + 1) <> tyUnknown) then
  begin
    name := CurTok.SVal;
    Next;                      { onto ':' }
    Next;                      { onto the type token }
    tk := PyParseType;
    Expect(tkAssign, '=');
    PyParseBoolExpr;
    symIdx := FindSym(name);
    if symIdx < 0 then symIdx := AllocVar(name, tk);
    lhsNode := PyMakeIdent(symIdx);
    PyCoerceAssignmentRHS(Syms[symIdx].TypeKind, CurASTNode);
    node := AllocNode(AN_ASSIGN);
    ASTLeft[node] := lhsNode;
    ASTRight[node] := CurASTNode;
    Result := node;
    Exit;
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
      Syms[symIdx].RecName := ProcRetRecId[ASTIVal[rhsNode]];
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

procedure PyParseDef;
var name: AnsiString; pnames: array[0..15] of AnsiString;
    ptypes: array[0..15] of TTypeKind;
    pcis: array[0..15] of Integer;
    nparams, i, procIdx, idx, savedSC, savedFS, patchPos, bodyStart, bodyEnd, bodyNode: Integer;
    retType: TTypeKind; isProc: Boolean; retCi: Integer;
begin
  if CurTok.Kind <> tkFunction then Error('Nil Python: expected def');
  Next;
  if CurTok.Kind <> tkIdent then Error('Nil Python: expected function name');
  name := CurTok.SVal;
  Next;
  Expect(tkLParen, '(');
  nparams := 0;
  while CurTok.Kind <> tkRParen do
  begin
    if nparams >= 16 then Error('Nil Python: too many parameters');
    if CurTok.Kind <> tkIdent then Error('Nil Python: expected parameter name');
    pnames[nparams] := CurTok.SVal;
    Next;
    Expect(tkColon, ':');
    ptypes[nparams] := PyParseType;
    pcis[nparams] := PyLastTypeCi;
    Inc(nparams);
    if not Eat(tkComma) then break;
  end;
  Expect(tkRParen, ')');
  Expect(tkMinus, '- in ->');
  Expect(tkGt, '> in ->');
  { `-> None` declares a procedure (no Result). }
  isProc := CurTok.Kind = tkNil;
  retCi := -1;
  if isProc then begin retType := tyInteger; Next; end
  else begin retType := PyParseType; retCi := PyLastTypeCi; end;
  Expect(tkColon, ':');
  Expect(tkNewline, 'newline');
  Expect(tkIndent, 'indent');
  bodyStart := TokPos - 1;
  bodyEnd := PyFindBodyEnd(bodyStart);

  procIdx := RegisterProc(name, not isProc, retType, nparams, pnames, ptypes);
  Procs[procIdx].BodyAddr := CodeLen;
  savedSC := SymCount;
  savedFS := FrameSize;
  FrameSize := 0;
  CurProc := procIdx;
  Procs[procIdx].ScopeBase := SymCount;
  for i := 0 to nparams - 1 do
  begin
    idx := AllocParam(pnames[i], ptypes[i], False, False);
    Procs[procIdx].Params[i].SymIdx := idx;
    if (ptypes[i] = tyClass) and (pcis[i] >= 0) then
      Syms[idx].RecName := REC_UCLASS_BASE + pcis[i];
  end;
  if not isProc then
  begin
    idx := AllocVar('Result', retType);
    Procs[procIdx].RetSymIdx := idx;
    if (retType = tyClass) and (retCi >= 0) then
      Syms[idx].RecName := REC_UCLASS_BASE + retCi;
  end;
  PyCollectLocals(bodyStart, bodyEnd);
  for i := 0 to PyLocalCount - 1 do
    if FindSym(PyLocals[i].Name) < 0 then AllocVar(PyLocals[i].Name, PyLocals[i].TypeKind);

  patchPos := EmitProcPrologue;
  Procs[procIdx].FramePatch := patchPos;
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

procedure PyRegisterClassMembers(ci, bodyStart, bodyEnd: Integer; isDC: Boolean);
var i, j, k, depth, methodStart, nparams, procIdx, mmi, slot, curOff, align, sz: Integer;
    origName, name, fullName, rhsName: AnsiString; isCtor: Boolean;
    pnames: array[0..15] of AnsiString; ptypes: array[0..15] of TTypeKind;
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
            (i + 2 < bodyEnd) and (Tokens[i + 1].Kind = tkColon) then
    begin
      { ClassVar annotation: a class-level static, not an instance field.
        Skipped here; a later access through the class name is its own wall. }
      if (Tokens[i + 2].Kind = tkIdent) and
         CaseEqual(GetTokenStr(i + 2), 'ClassVar') then
      begin
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
      if PyDcCount >= PY_MAX_DC_FIELDS then
        Error('Nil Python: too many dataclass fields');
      PyDcCi[PyDcCount] := ci;
      PyDcKind[PyDcCount] := defKind;
      PyDcIVal[PyDcCount] := defIVal;
      PyDcSOff[PyDcCount] := defSOff;
      PyDcSLen[PyDcCount] := defSLen;
      Inc(PyDcCount);
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
      j := i + 3;
      while Tokens[j].Kind <> tkRParen do
      begin
        pnames[nparams] := GetTokenStr(j);
        if (nparams = 0) and (pnames[nparams] = 'self') then
          ptypes[nparams] := tyClass
        else
        begin
          Inc(j);
          if Tokens[j].Kind <> tkColon then Error('Nil Python: expected parameter type annotation');
          Inc(j);
          ptypes[nparams] := PyTypeFromTokenIndex(j);
          if ptypes[nparams] = tyUnknown then Error('Nil Python: expected parameter type annotation');
        end;
        Inc(nparams);
        Inc(j);
        if Tokens[j].Kind = tkComma then Inc(j);
      end;
      fullName := PyRawName(UClsNOff[ci], UClsNLen[ci]);
      AppendChar(fullName, '.');
      for k := 1 to Length(name) do AppendChar(fullName, name[k]);
      procIdx := RegisterProc(fullName, not isCtor, tyInteger, nparams, pnames, ptypes);
      if isCtor then
      begin
        k := PyStoredName('create');
        AddUMeth(ci, k, 6, procIdx);
      end
      else
        AddUMeth(ci, Tokens[i + 1].SOffset, Tokens[i + 1].SLen, procIdx);
      mmi := UMthCount - 1;
      if not isCtor then
      begin
        slot := UClsVirtCount[ci];
        UClsVirtCount[ci] := UClsVirtCount[ci] + 1;
        UMthVirSlot[mmi] := slot;
      end;
      { Constructor assignments define fields: self.name = annotated_param. }
      if isCtor then
      begin
        while (j < bodyEnd) and (Tokens[j].Kind <> tkIndent) do Inc(j);
        Inc(j);
        while (j + 4 < bodyEnd) and (Tokens[j].Kind <> tkDedent) do
        begin
          if (Tokens[j].Kind = tkIdent) and (GetTokenStr(j) = 'self') and
             (Tokens[j + 1].Kind = tkDot) and (Tokens[j + 2].Kind = tkIdent) and
             (Tokens[j + 3].Kind = tkAssign) then
          begin
            tk := PyTypeFromTokenIndex(j + 4);
            if (tk = tyUnknown) and (Tokens[j + 4].Kind = tkIdent) then
            begin
              rhsName := GetTokenStr(j + 4);
              tk := PyHeaderParamType(methodStart, j, rhsName);
            end;
            if tk = tyUnknown then Error('Nil Python: cannot infer class field type');
            { see the dataclass branch: str fields are managed, not string[N] }
            if tk = tyString then tk := tyAnsiString;
            if FindUField(ci, GetTokenStr(j + 2)) < 0 then
            begin
              sz := TypeSize(tk);
              curOff := AlignTo(curOff, TypeAlign(tk));
              AddUField(ci, Tokens[j + 2].SOffset, Tokens[j + 2].SLen, curOff, Ord(tk), REC_NONE);
              Inc(curOff, sz);
            end;
          end;
          Inc(j);
        end;
      end;
    end;
    Inc(i);
  end;
  if isDC then
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
    savedSelf, patchPos, bodyNode: Integer; pnames: array[0..15] of AnsiString;
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
      ptypes[nparams] := PyParseType;
      pcis[nparams] := PyLastTypeCi;
    end;
    Inc(nparams);
    if not Eat(tkComma) then break;
  end;
  Expect(tkRParen, ')'); Expect(tkMinus, '- in ->'); Expect(tkGt, '> in ->');
  if isCtor then begin Expect(tkNil, 'None'); end else PyParseType;
  Expect(tkColon, ':'); Expect(tkNewline, 'newline'); Expect(tkIndent, 'indent');
  fullName := PyRawName(UClsNOff[ci], UClsNLen[ci]); AppendChar(fullName, '.');
  for i := 1 to Length(name) do AppendChar(fullName, name[i]);
  procIdx := FindProc(fullName);
  savedSC := SymCount; savedFS := FrameSize; savedSelf := CurSelfClass;
  FrameSize := 0; CurProc := procIdx; CurSelfClass := REC_UCLASS_BASE + ci;
  Procs[procIdx].ScopeBase := SymCount;
  for i := 0 to nparams - 1 do
  begin
    idx := AllocParam(pnames[i], ptypes[i], False, False);
    Procs[procIdx].Params[i].SymIdx := idx;
    if (ptypes[i] = tyClass) and (pcis[i] >= 0) then
      Syms[idx].RecName := REC_UCLASS_BASE + pcis[i];
  end;
  if not isCtor then begin idx := AllocVar('Result', Procs[procIdx].RetType); Procs[procIdx].RetSymIdx := idx; end;
  Procs[procIdx].BodyAddr := CodeLen;
  patchPos := EmitProcPrologue; Procs[procIdx].FramePatch := patchPos;
  PyEmitParamSpills(procIdx, nparams);
  PyInitVariantLocals(Procs[procIdx].ScopeBase);
  bodyNode := PyParseBlock; Expect(tkDedent, 'dedent');
  CompileAST(bodyNode); EmitProcEpilog(Procs[procIdx].RetSymIdx); PatchProcPrologue(patchPos, FrameSize);
  SymRollbackTo(savedSC); FrameSize := savedFS; CurProc := -1; CurSelfClass := savedSelf;
end;

{ Emit the synthesized @dataclass ctor body: spill params, then
  self.field_i := param_i for every field, via the ordinary AST path. }
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

procedure PyParseClass(isDC: Boolean);
var ci, bodyStart, bodyEnd: Integer;
begin
  Expect(tkClass, 'class');
  ci := FindUClass(CurTok.SVal); Next;
  Expect(tkColon, ':'); Expect(tkNewline, 'newline'); Expect(tkIndent, 'indent');
  bodyStart := TokPos - 1; bodyEnd := PyFindBodyEnd(bodyStart);
  PyRegisterClassMembers(ci, bodyStart, bodyEnd, isDC);
  if isDC and (ci < PY_MAX_DC_FIELDS) then PyDcClassIsDc[ci] := True;
  PySkipNewlines;
  while CurTok.Kind <> tkDedent do
  begin
    if isDC and (CurTok.Kind = tkIdent) then
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
    impName: AnsiString;
begin
  needsBuiltin := True;
  for i := 0 to MainProgramTokCount - 1 do
  begin
    if (Tokens[i].Kind = tkIdent) and (i + 1 < MainProgramTokCount) and
       (Tokens[i + 1].Kind = tkLParen) and
       (CaseEqual(GetTokenStr(i), 'str') or CaseEqual(GetTokenStr(i), 'val')) then
      needsBuiltin := True;
  end;
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
  PyCollectModuleLocals;
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
