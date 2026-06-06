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
  end;

var
  PyLocals: array[0..PY_MAX_LOCALS-1] of TPyLocalConstraint;
  PyLocalCount: Integer;
  PyModuleLocals: array[0..PY_MAX_LOCALS-1] of TPyLocalConstraint;
  PyModuleLocalCount: Integer;

function PyIsIdent(const s: AnsiString): Boolean;
begin
  Result := (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, s);
end;

procedure PyValidateOperators;
var i: Integer;
begin
  for i := 0 to MainProgramTokCount - 1 do
    if Tokens[i].Kind = tkSlash then
    begin
      CurTok.Line := Tokens[i].Line;
      Error('Nil Python: unsupported operator /; use // for integer division');
    end;
end;

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
      else if lo = 'str' then Result := tyString;
    end;
  end;
end;

function PyParseType: TTypeKind;
begin
  Result := PyTypeFromTokenIndex(TokPos - 1);
  if Result = tyUnknown then
    Error('Nil Python: expected type annotation (int, float, bool, or str)');
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
    Error('Nil Python: annotate the type / too dynamic');
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
  if PyVariantScalar(a) and PyVariantScalar(b) then
  begin
    Result := tyVariant;
    Exit;
  end;
  Error('Nil Python: annotate the type / too dynamic');
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
    ParseExpr;   { comparison + arithmetic atom }
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
var i, ci, si, pi, depth: Integer; tk: TTypeKind; name: AnsiString;
begin
  Result := tyUnknown;
  if (startIdx < endIdx) and (Tokens[startIdx].Kind = tkIdent) and
     IsClassType(GetTokenStr(startIdx)) and (startIdx + 1 < endIdx) and
     (Tokens[startIdx + 1].Kind = tkLParen) then
  begin
    Result := tyClass;
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
          pi := FindProc(name);
          if pi >= 0 then tk := Procs[pi].RetType
          else tk := PyDefReturnType(name);
          if tk = tyUnknown then tk := tyVariant;
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
      j := i + 2;
      while (j < bodyEnd) and not (Tokens[j].Kind in [tkNewline, tkDedent]) do Inc(j);
      tk := PyInferExprType(i + 2, j);
      if tk = tyUnknown then
        Error('Nil Python: cannot infer local type for ' + name);
      ci := PyFindConstraint(name);
      if ci < 0 then
      begin
        if PyLocalCount >= PY_MAX_LOCALS then Error('Nil Python: too many inferred locals');
        PyLocals[PyLocalCount].Name := name;
        PyLocals[PyLocalCount].TypeKind := tk;
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
    if Tokens[i].Kind = tkFunction then
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
    else if (skipDepth < 0) and (Tokens[i].Kind = tkIdent) and
            (i + 1 < MainProgramTokCount) and (Tokens[i + 1].Kind = tkAssign) then
    begin
      name := GetTokenStr(i);
      j := i + 2;
      while (j < MainProgramTokCount) and not (Tokens[j].Kind in [tkNewline, tkDedent]) do Inc(j);
      tk := PyInferExprType(i + 2, j);
      if tk = tyUnknown then
        Error('Nil Python: cannot infer module local type for ' + name);
      ci := PyFindConstraint(name);
      if ci < 0 then
      begin
        if PyLocalCount >= PY_MAX_LOCALS then Error('Nil Python: too many inferred module locals');
        PyLocals[PyLocalCount].Name := name;
        PyLocals[PyLocalCount].TypeKind := tk;
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
  while CurTok.Kind <> tkRParen do
  begin
    PyParseBoolExpr;
    argNode := AllocNode(AN_ARG);
    ASTLeft[argNode] := CurASTNode;
    ASTRight[lastArg] := argNode;
    lastArg := argNode;
    if not Eat(tkComma) then break;
  end;
  Expect(tkRParen, ')');
  Result := node;
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
    elseNode := PyParseIf
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

function PyParseStatement: Integer;
var name: AnsiString; symIdx, lhsNode, node, ci, rhsNode: Integer; tk: TTypeKind;
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
    Expect(tkAssign, '=');
    PyParseBoolExpr;
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
      Syms[symIdx].RecName := ASTRight[rhsNode];
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
    nparams, i, pi, idx, savedSC, savedFS, patchPos, bodyStart, bodyEnd, bodyNode: Integer;
    retType: TTypeKind;
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
    Inc(nparams);
    if not Eat(tkComma) then break;
  end;
  Expect(tkRParen, ')');
  Expect(tkMinus, '- in ->');
  Expect(tkGt, '> in ->');
  retType := PyParseType;
  Expect(tkColon, ':');
  Expect(tkNewline, 'newline');
  Expect(tkIndent, 'indent');
  bodyStart := TokPos - 1;
  bodyEnd := PyFindBodyEnd(bodyStart);

  pi := RegisterProc(name, True, retType, nparams, pnames, ptypes);
  Procs[pi].BodyAddr := CodeLen;
  savedSC := SymCount;
  savedFS := FrameSize;
  FrameSize := 0;
  CurProc := pi;
  Procs[pi].ScopeBase := SymCount;
  for i := 0 to nparams - 1 do
  begin
    idx := AllocParam(pnames[i], ptypes[i], False, False);
    Procs[pi].Params[i].SymIdx := idx;
  end;
  idx := AllocVar('Result', retType);
  Procs[pi].RetSymIdx := idx;
  PyCollectLocals(bodyStart, bodyEnd);
  for i := 0 to PyLocalCount - 1 do
    if FindSym(PyLocals[i].Name) < 0 then AllocVar(PyLocals[i].Name, PyLocals[i].TypeKind);

  patchPos := EmitProcPrologue;
  Procs[pi].FramePatch := patchPos;
  for i := 0 to nparams - 1 do
  begin
    idx := Procs[pi].Params[i].SymIdx;
    EmitB($89);
    case i of
      0: EmitB($BD);
      1: EmitB($B5);
      2: EmitB($95);
      3: EmitB($8D);
      else Error('Nil Python: more than four parameters are not supported in v1');
    end;
    EmitI32(Syms[idx].Offset);
  end;
  PyInitVariantLocals(Procs[pi].ScopeBase);
  bodyNode := PyParseBlock;
  Expect(tkDedent, 'dedent');
  CompileAST(bodyNode);
  EmitProcEpilog(Procs[pi].RetSymIdx);
  PatchProcPrologue(patchPos, FrameSize);
  SymCount := savedSC;
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

procedure PyRegisterClassMembers(ci, bodyStart, bodyEnd: Integer);
var i, j, k, depth, methodStart, nparams, pi, mmi, slot, curOff, align, sz: Integer;
    origName, name, fullName, rhsName: AnsiString; isCtor: Boolean;
    pnames: array[0..15] of AnsiString; ptypes: array[0..15] of TTypeKind;
    tk: TTypeKind;
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
      pi := RegisterProc(fullName, not isCtor, tyInteger, nparams, pnames, ptypes);
      if isCtor then
      begin
        k := PyStoredName('create');
        AddUMeth(ci, k, 6, pi);
      end
      else
        AddUMeth(ci, Tokens[i + 1].SOffset, Tokens[i + 1].SLen, pi);
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
  UClsSize_[ci] := AlignTo(curOff, align);
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
var origName, name, fullName: AnsiString; pi, i, idx, nparams, savedSC, savedFS,
    savedSelf, patchPos, bodyNode: Integer; pnames: array[0..15] of AnsiString;
    ptypes: array[0..15] of TTypeKind; isCtor: Boolean;
begin
  Expect(tkFunction, 'def');
  origName := CurTok.SVal; name := PyMethodName(origName); Next;
  isCtor := name = 'create';
  Expect(tkLParen, '(');
  nparams := 0;
  while CurTok.Kind <> tkRParen do
  begin
    pnames[nparams] := CurTok.SVal; Next;
    if (nparams = 0) and (pnames[nparams] = 'self') then ptypes[nparams] := tyClass
    else begin Expect(tkColon, ':'); ptypes[nparams] := PyParseType; end;
    Inc(nparams);
    if not Eat(tkComma) then break;
  end;
  Expect(tkRParen, ')'); Expect(tkMinus, '- in ->'); Expect(tkGt, '> in ->');
  if isCtor then begin Expect(tkNil, 'None'); end else PyParseType;
  Expect(tkColon, ':'); Expect(tkNewline, 'newline'); Expect(tkIndent, 'indent');
  fullName := PyRawName(UClsNOff[ci], UClsNLen[ci]); AppendChar(fullName, '.');
  for i := 1 to Length(name) do AppendChar(fullName, name[i]);
  pi := FindProc(fullName);
  savedSC := SymCount; savedFS := FrameSize; savedSelf := CurSelfClass;
  FrameSize := 0; CurProc := pi; CurSelfClass := REC_UCLASS_BASE + ci;
  Procs[pi].ScopeBase := SymCount;
  for i := 0 to nparams - 1 do
  begin
    idx := AllocParam(pnames[i], ptypes[i], False, False);
    Procs[pi].Params[i].SymIdx := idx;
    if i = 0 then Syms[idx].RecName := REC_UCLASS_BASE + ci;
  end;
  if not isCtor then begin idx := AllocVar('Result', Procs[pi].RetType); Procs[pi].RetSymIdx := idx; end;
  Procs[pi].BodyAddr := CodeLen;
  patchPos := EmitProcPrologue; Procs[pi].FramePatch := patchPos;
  for i := 0 to nparams - 1 do
  begin
    idx := Procs[pi].Params[i].SymIdx;
    if TypeSize(Syms[idx].TypeKind) = 8 then EmitB($48);
    EmitB($89);
    case i of 0: EmitB($BD); 1: EmitB($B5); 2: EmitB($95); 3: EmitB($8D); end;
    EmitI32(Syms[idx].Offset);
  end;
  PyInitVariantLocals(Procs[pi].ScopeBase);
  bodyNode := PyParseBlock; Expect(tkDedent, 'dedent');
  CompileAST(bodyNode); EmitProcEpilog(Procs[pi].RetSymIdx); PatchProcPrologue(patchPos, FrameSize);
  SymCount := savedSC; FrameSize := savedFS; CurProc := -1; CurSelfClass := savedSelf;
end;

procedure PyParseClass;
var ci, bodyStart, bodyEnd: Integer;
begin
  Expect(tkClass, 'class');
  ci := FindUClass(CurTok.SVal); Next;
  Expect(tkColon, ':'); Expect(tkNewline, 'newline'); Expect(tkIndent, 'indent');
  bodyStart := TokPos - 1; bodyEnd := PyFindBodyEnd(bodyStart);
  PyRegisterClassMembers(ci, bodyStart, bodyEnd);
  PySkipNewlines;
  while CurTok.Kind <> tkDedent do begin PyParseMethod(ci); PySkipNewlines; end;
  Expect(tkDedent, 'dedent');
end;

procedure ParsePyProgram;
var mainNode, stmt, blockNode, jmpPatch, i, savedUnitIdx: Integer; needsBuiltin: Boolean;
    dummyNames: array[0..3] of AnsiString;
    dummyTypes: array[0..3] of TTypeKind;
begin
  needsBuiltin := True;
  for i := 0 to MainProgramTokCount - 1 do
  begin
    if (Tokens[i].Kind = tkIdent) and (i + 1 < MainProgramTokCount) and
       (Tokens[i + 1].Kind = tkLParen) and
       (CaseEqual(GetTokenStr(i), 'str') or CaseEqual(GetTokenStr(i), 'val')) then
      needsBuiltin := True;
  end;
  PyValidateOperators;
  PyRegisterClassShells;
  PyCollectModuleLocals;
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
  { Forward-declare the builtin heap allocator before emitting the string
    runtime, which calls Alloc. The unit body (compiled by ParseUsesUnit below)
    fills these in. Mirrors the Pascal ParseProgram path; without it a .npy that
    touches the heap fails FindProc('PXXAlloc') during EmitAnsiStringRuntime. }
  savedUnitIdx := CurrentUnitIdx;
  CurrentUnitIdx := InternStr('builtin');
  dummyNames[0] := 'size';  dummyTypes[0] := tyInt64;
  dummyNames[1] := 'align'; dummyTypes[1] := tyInteger;
  i := RegisterProc('PXXAlloc', True, tyPointer, 2, dummyNames, dummyTypes);
  dummyNames[0] := 'p';     dummyTypes[0] := tyPointer;
  i := RegisterProc('PXXFree', False, tyPointer, 1, dummyNames, dummyTypes);
  dummyNames[0] := 'p';     dummyTypes[0] := tyPointer;
  dummyNames[1] := 'newSize'; dummyTypes[1] := tyInt64;
  dummyNames[2] := 'align'; dummyTypes[2] := tyInteger;
  i := RegisterProc('PXXRealloc', True, tyPointer, 3, dummyNames, dummyTypes);
  CurrentUnitIdx := savedUnitIdx;
  EmitAnsiStringRuntime;
  if needsBuiltin then ParseUsesUnit('builtin');
  PySkipNewlines;
  { Nil Python `import name[, name]` maps each module onto the same unit
    resolver as a Pascal `uses` clause, so a C header in /usr/include
    (e.g. sqlite3) is imported and dynamically linked identically. The
    lexer rewrites `import` to tkUses; leading imports are processed before
    the program body so their symbols are registered for the main code. }
  while CurTok.Kind = tkUses do
  begin
    Next;
    while CurTok.Kind = tkIdent do
    begin
      ParseUsesUnit(CurTok.SVal);
      Next;
      if not Eat(tkComma) then Break;
    end;
    PySkipNewlines;
  end;
  PyExprMode := True;   { Pascal RTL units are loaded; from here on, .npy expression
                          parsing uses Python and/or/not precedence }
  mainNode := -1;
  PySkipNewlines;
  while CurTok.Kind <> tkEOF do
  begin
    if CurTok.Kind = tkClass then PyParseClass
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
end;
