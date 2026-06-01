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

function PyIsIdent(const s: AnsiString): Boolean;
begin
  Result := (CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, s);
end;

procedure PyValidateOperators;
var i: Integer;
begin
  for i := 0 to TokCount - 1 do
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

function PyWiden(a, b: TTypeKind): TTypeKind;
begin
  if a = tyUnknown then begin Result := b; Exit; end;
  if b = tyUnknown then begin Result := a; Exit; end;
  if a = b then begin Result := a; Exit; end;
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
  { TODO(Phase 1): promote the function-scope slot to tyVariant here once the
    Variant backend lands. Keep this branch independent of tyVariant for now. }
  Error('Nil Python: type unification failed — tyVariant promotion pending (Phase 1)');
  Result := tyUnknown;
end;

function PyFindConstraint(const name: AnsiString): Integer;
var i: Integer;
begin
  for i := 0 to PyLocalCount - 1 do
    if PyLocals[i].Name = name then begin Result := i; Exit; end;
  Result := -1;
end;

function PyInferExprType(startIdx, endIdx: Integer): TTypeKind;
var i, ci, si: Integer; tk: TTypeKind; name: AnsiString;
begin
  Result := tyUnknown;
  i := startIdx;
  while i < endIdx do
  begin
    tk := PyTypeFromTokenIndex(i);
    if tk = tyUnknown then
    begin
      if Tokens[i].Kind = tkIdent then
      begin
        name := GetTokenStr(i);
        ci := PyFindConstraint(name);
        if ci >= 0 then tk := PyLocals[ci].TypeKind
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

function PyFindBodyEnd(bodyStart: Integer): Integer;
var i, depth: Integer;
begin
  depth := 1;
  i := bodyStart;
  while i < TokCount do
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
  Result := TokCount;
end;

function PyMakeIdent(symIdx: Integer): Integer;
begin
  Result := AllocNode(AN_IDENT);
  ASTIVal[Result] := symIdx;
  ASTTk[Result] := Ord(Syms[symIdx].TypeKind);
end;

function PyParseBlock: Integer; forward;
function PyParseStatement: Integer; forward;

function PyParsePrint: Integer;
var node, argNode, lastArg: Integer;
begin
  Next;
  Expect(tkLParen, '(');
  node := AllocNode(AN_WRITELN);
  lastArg := -1;
  if CurTok.Kind <> tkRParen then
    repeat
      ParseExpr;
      argNode := AllocNode(AN_ARG);
      ASTLeft[argNode] := CurASTNode;
      ASTRight[argNode] := -1;
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
  ParseExpr;
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
  ParseExpr;
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
  ParseExpr;
  startNode := CurASTNode;
  if Eat(tkComma) then
  begin
    stopNode := startNode;
    ParseExpr;
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
    ParseExpr;
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
var name: AnsiString; symIdx, lhsNode, node: Integer;
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
      ParseExpr;
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
     (Tokens[TokPos].Kind = tkAssign) then
  begin
    name := CurTok.SVal;
    symIdx := FindSym(name);
    Next;
    Expect(tkAssign, '=');
    ParseExpr;
    if symIdx < 0 then symIdx := AllocVar(name, IntToTypeKind(ASTTk[CurASTNode]));
    lhsNode := PyMakeIdent(symIdx);
    node := AllocNode(AN_ASSIGN);
    ASTLeft[node] := lhsNode;
    ASTRight[node] := CurASTNode;
    Result := node;
    Exit;
  end;
  ParseExpr;
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
  bodyNode := PyParseBlock;
  Expect(tkDedent, 'dedent');
  CompileAST(bodyNode);
  EmitProcEpilog(Procs[pi].RetSymIdx);
  PatchProcPrologue(patchPos, FrameSize);
  SymCount := savedSC;
  FrameSize := savedFS;
  CurProc := -1;
end;

procedure ParsePyProgram;
var mainNode, stmt, blockNode, jmpPatch: Integer;
begin
  PyValidateOperators;
  BSS_INITIAL_RSP := BSSSize; Inc(BSSSize, 8);
  EmitB($48); EmitB($89); EmitB($24); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);
  EmitB($E9); jmpPatch := CodeLen; EmitI32(0);
  mainNode := -1;
  PySkipNewlines;
  while CurTok.Kind <> tkEOF do
  begin
    if CurTok.Kind = tkFunction then PyParseDef
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
  CompileAST(blockNode);
  EmitExit(0);
end;
