{ SPDX-License-Identifier: MPL-2.0 }
{ ===== Ada Parser (skeleton) =====
  Hand-builds AST directly (AllocNode/ASTLeft/ASTRight/ASTTk), same technique
  as bparser.inc, reusing the shared ParseExpr for every expression and the
  shared AN_* node kinds for every statement shape -- no new AST nodes, no
  new IR, no backend work. v1 subset: a single top-level `procedure Name is
  <declarations> begin <statements> end [Name];` program (Ada's normal
  "main program" shape), variable declarations (Integer/Boolean/String),
  assignment, if/elsif/else/end if, while/loop/end loop, for-in-range loop,
  exit / exit when, and a Put_Line builtin lowering onto the same AN_WRITELN
  node BASIC's PRINT and Pascal's writeln already use.
  See devdocs/progress/backlog/feature-esoteric-ada.md for the full scope
  and explicit non-goals (no packages/tasking/full generics/exceptions yet --
  this file is sub-ticket 1, the skeleton only). }

function ParseAStatement: Integer; forward;
function ParseABlock: Integer; forward;

function AIntToStr(n: Integer): AnsiString;
var rev, res: AnsiString; i: Integer;
begin
  rev := '';
  if n = 0 then AppendChar(rev, '0')
  else
    while n > 0 do
    begin
      AppendChar(rev, Chr(Ord('0') + (n mod 10)));
      n := n div 10;
    end;
  res := '';
  for i := Length(rev) downto 1 do AppendChar(res, rev[i]);
  Result := res;
end;

{ case-insensitive compare against the current token's text -- used for the
  handful of keywords left as plain tkIdent (is/elsif/when/Put_Line) rather
  than given their own reused token kind. }
function ACurIs(const kw: AnsiString): Boolean;
var lower: AnsiString; i: Integer;
begin
  if CurTok.Kind <> tkIdent then begin Result := False; Exit; end;
  SetLength(lower, Length(CurTok.SVal));
  for i := 1 to Length(CurTok.SVal) do
  begin
    if CurTok.SVal[i] in ['A'..'Z'] then lower[i] := Chr(Ord(CurTok.SVal[i]) + 32)
    else lower[i] := CurTok.SVal[i];
  end;
  Result := lower = kw;
end;

function AMapTypeName: TTypeKind;
begin
  Result := tyInteger;
  if ACurIs('boolean') then Result := tyBoolean
  else if ACurIs('string') then Result := tyString
  else if ACurIs('integer') then Result := tyInteger;
  Next;
end;

{ Put_Line(expr) -- same AN_WRITE/AN_WRITELN/AN_ARG shape as BASIC's PRINT. }
function ParseAPutLine: Integer;
var node, argNode, exprNode: Integer;
begin
  node := AllocNode(AN_WRITE);
  ASTKind[node] := AN_WRITELN;
  Next; { consume 'Put_Line' }
  Expect(tkLParen, '(');
  ParseExpr;
  exprNode := CurASTNode;
  Expect(tkRParen, ')');
  argNode := AllocNode(AN_ARG);
  ASTLeft[argNode] := exprNode;
  ASTRight[argNode] := -1;
  ASTLeft[node] := argNode;
  Result := node;
end;

function ParseAStatement: Integer;
var
  stmtNode, seqTail: Integer;
  vname: AnsiString;
  symIdx: Integer;
  lhsNode, rhsNode: Integer;
  condNode, thenNode, elseNode, pairNode: Integer;
  bodyNode: Integer;
  loNode, hiNode: Integer;
  vtype: TTypeKind;
begin
  stmtNode := -1;

  if ACurIs('put_line') then
    stmtNode := ParseAPutLine
  else if CurTok.Kind = tkIf then
  begin
    Next;
    ParseExpr;
    condNode := CurASTNode;
    Expect(tkThen, 'THEN');
    thenNode := ParseABlock;
    elseNode := -1;
    { elsif desugars to a nested if in the else branch -- no new AST shape. }
    if ACurIs('elsif') then
    begin
      elseNode := ParseAStatement(); { re-enter: current token is still 'elsif', handled below via the tkIf-shaped path }
    end
    else if CurTok.Kind = tkElse then
    begin
      Next;
      elseNode := ParseABlock;
    end;
    if CurTok.Kind = tkEnd then
    begin
      Next;
      Expect(tkIf, 'IF (closing "end if")');
      Expect(tkSemicolon, ';');
    end;
    stmtNode := AllocNode(AN_IF);
    ASTLeft[stmtNode] := condNode;
    pairNode := AllocNode(AN_PAIR);
    ASTLeft[pairNode] := thenNode;
    ASTRight[pairNode] := elseNode;
    ASTRight[stmtNode] := pairNode;
    ASTTk[stmtNode] := Ord(tyUnknown);
  end
  else if ACurIs('elsif') then
  begin
    { entered only via the recursive call above: treat exactly like `if` but
      the closing `end if;` belongs to the OUTERMOST if, so don't consume it
      here -- re-run the same shape and let the caller's Expect(tkEnd) fire. }
    Next;
    ParseExpr;
    condNode := CurASTNode;
    Expect(tkThen, 'THEN');
    thenNode := ParseABlock;
    elseNode := -1;
    if ACurIs('elsif') then
      elseNode := ParseAStatement()
    else if CurTok.Kind = tkElse then
    begin
      Next;
      elseNode := ParseABlock;
    end;
    stmtNode := AllocNode(AN_IF);
    ASTLeft[stmtNode] := condNode;
    pairNode := AllocNode(AN_PAIR);
    ASTLeft[pairNode] := thenNode;
    ASTRight[pairNode] := elseNode;
    ASTRight[stmtNode] := pairNode;
    ASTTk[stmtNode] := Ord(tyUnknown);
  end
  else if CurTok.Kind = tkWhile then
  begin
    Next;
    ParseExpr;
    condNode := CurASTNode;
    Expect(tkLoop, 'LOOP');
    bodyNode := ParseABlock;
    Expect(tkEnd, 'END');
    Expect(tkLoop, 'LOOP (closing "end loop")');
    Expect(tkSemicolon, ';');
    stmtNode := AllocNode(AN_WHILE);
    ASTLeft[stmtNode] := condNode;
    ASTRight[stmtNode] := bodyNode;
    ASTTk[stmtNode] := Ord(tyUnknown);
  end
  else if CurTok.Kind = tkLoop then
  begin
    { bare `loop ... end loop;` -- Ada's unconditional loop, exited only via
      `exit`/`exit when`. Desugar to `while True` -- same AN_WHILE shape,
      no new AST needed. }
    Next;
    condNode := AllocNode(AN_BOOL_LIT);
    ASTIVal[condNode] := 1;
    ASTTk[condNode] := Ord(tyBoolean);
    bodyNode := ParseABlock;
    Expect(tkEnd, 'END');
    Expect(tkLoop, 'LOOP (closing "end loop")');
    Expect(tkSemicolon, ';');
    stmtNode := AllocNode(AN_WHILE);
    ASTLeft[stmtNode] := condNode;
    ASTRight[stmtNode] := bodyNode;
    ASTTk[stmtNode] := Ord(tyUnknown);
  end
  else if CurTok.Kind = tkFor then
  begin
    Next;
    if CurTok.Kind <> tkIdent then Error('Ada: expected loop variable after FOR');
    vname := CurTok.SVal;
    Next;
    Expect(tkIn, 'IN');
    ParseExpr;
    loNode := CurASTNode;
    Expect(tkDotDot, '..');
    ParseExpr;
    hiNode := CurASTNode;
    Expect(tkLoop, 'LOOP');

    symIdx := FindSym(vname);
    if symIdx < 0 then symIdx := AllocVar(vname, tyInteger);

    bodyNode := ParseABlock;
    Expect(tkEnd, 'END');
    Expect(tkLoop, 'LOOP (closing "end loop")');
    Expect(tkSemicolon, ';');

    { desugar to: I := lo; while I <= hi do begin body; I := I + 1 end --
      identical shape to BASIC's FOR lowering (bparser.inc), reusing the
      same AN_ASSIGN/AN_WHILE/AN_BINOP/AN_SEQ nodes. }
    lhsNode := AllocNode(AN_IDENT);
    ASTIVal[lhsNode] := symIdx;
    ASTTk[lhsNode] := Ord(Syms[symIdx].TypeKind);
    stmtNode := AllocNode(AN_ASSIGN);
    ASTLeft[stmtNode] := lhsNode;
    ASTRight[stmtNode] := loNode;
    ASTTk[stmtNode] := Ord(tyUnknown);

    lhsNode := AllocNode(AN_IDENT);
    ASTIVal[lhsNode] := symIdx;
    ASTTk[lhsNode] := Ord(Syms[symIdx].TypeKind);
    condNode := AllocNode(AN_BINOP);
    ASTIVal[condNode] := Ord(tkLe);
    ASTLeft[condNode] := lhsNode;
    ASTRight[condNode] := hiNode;
    ASTTk[condNode] := Ord(tyBoolean);

    lhsNode := AllocNode(AN_IDENT);
    ASTIVal[lhsNode] := symIdx;
    ASTTk[lhsNode] := Ord(Syms[symIdx].TypeKind);
    rhsNode := AllocNode(AN_IDENT);
    ASTIVal[rhsNode] := symIdx;
    ASTTk[rhsNode] := Ord(Syms[symIdx].TypeKind);
    pairNode := AllocNode(AN_INT_LIT);
    ASTIVal[pairNode] := 1;
    ASTTk[pairNode] := Ord(tyInteger);
    thenNode := AllocNode(AN_BINOP);   { reuse thenNode as scratch: I + 1 }
    ASTIVal[thenNode] := Ord(tkPlus);
    ASTLeft[thenNode] := rhsNode;
    ASTRight[thenNode] := pairNode;
    ASTTk[thenNode] := Ord(tyInteger);
    elseNode := AllocNode(AN_ASSIGN);  { reuse elseNode as scratch: I := I + 1 }
    ASTLeft[elseNode] := lhsNode;
    ASTRight[elseNode] := thenNode;
    ASTTk[elseNode] := Ord(tyUnknown);

    if bodyNode = -1 then
      bodyNode := elseNode
    else
    begin
      seqTail := bodyNode;
      while ASTRight[seqTail] <> -1 do seqTail := ASTRight[seqTail];
      ASTRight[seqTail] := AllocNode(AN_SEQ);
      seqTail := ASTRight[seqTail];
      ASTLeft[seqTail] := elseNode;
      ASTRight[seqTail] := -1;
    end;

    pairNode := AllocNode(AN_WHILE);
    ASTLeft[pairNode] := condNode;
    ASTRight[pairNode] := bodyNode;
    ASTTk[pairNode] := Ord(tyUnknown);

    seqTail := AllocNode(AN_SEQ);
    ASTLeft[seqTail] := stmtNode;
    ASTRight[seqTail] := AllocNode(AN_SEQ);
    ASTLeft[ASTRight[seqTail]] := pairNode;
    ASTRight[ASTRight[seqTail]] := -1;
    stmtNode := seqTail;
  end
  else if CurTok.Kind = tkBreak then
  begin
    { Ada `exit`/`exit when` = break out of the enclosing loop -- AN_BREAK,
      NOT AN_EXIT (that's procedure/function exit, what BASIC's RETURN and
      Pascal's Exit use; conflating the two silently exits the whole
      procedure instead of just the loop -- caught by testing, not by
      inspection, see feature-esoteric-ada.md's log). }
    Next;
    if ACurIs('when') then
    begin
      Next;
      ParseExpr;
      condNode := CurASTNode;
      stmtNode := AllocNode(AN_IF);
      ASTLeft[stmtNode] := condNode;
      pairNode := AllocNode(AN_PAIR);
      ASTLeft[pairNode] := AllocNode(AN_BREAK);
      ASTTk[ASTLeft[pairNode]] := Ord(tyUnknown);
      ASTRight[pairNode] := -1;
      ASTRight[stmtNode] := pairNode;
      ASTTk[stmtNode] := Ord(tyUnknown);
    end
    else
    begin
      stmtNode := AllocNode(AN_BREAK);
      ASTTk[stmtNode] := Ord(tyUnknown);
    end;
    Expect(tkSemicolon, ';');
  end
  else if CurTok.Kind = tkIdent then
  begin
    vname := CurTok.SVal;
    symIdx := FindSym(vname);
    Next;
    if symIdx < 0 then Error('Ada: undefined variable: ' + vname);
    Expect(tkAssign, ':=');
    ParseExpr;
    rhsNode := CurASTNode;
    Expect(tkSemicolon, ';');

    lhsNode := AllocNode(AN_IDENT);
    ASTIVal[lhsNode] := symIdx;
    ASTTk[lhsNode] := Ord(Syms[symIdx].TypeKind);
    stmtNode := AllocNode(AN_ASSIGN);
    ASTLeft[stmtNode] := lhsNode;
    ASTRight[stmtNode] := rhsNode;
    ASTTk[stmtNode] := Ord(tyUnknown);
  end;

  { Put_Line(...) and the desugared `for` are statement-terminated already
    above except Put_Line, which still needs its trailing `;` consumed here
    to keep this dispatcher uniform. }
  if (stmtNode <> -1) and (ASTKind[stmtNode] = AN_WRITELN) then
    Expect(tkSemicolon, ';');

  Result := stmtNode;
end;

function ParseABlock: Integer;
var
  stmtList, lastStmt, stmtNode, guardPos: Integer;
begin
  stmtList := -1;
  lastStmt := -1;
  while (CurTok.Kind <> tkEOF) and (CurTok.Kind <> tkEnd) and
        (not ACurIs('elsif')) and (CurTok.Kind <> tkElse) do
  begin
    { Parser-hang guard: an unrecognized construct must not silently return
      -1 without consuming a token, or this loop spins forever (found the
      hard way testing a bare `loop` before that case existed above). }
    guardPos := TokPos;
    stmtNode := ParseAStatement;
    if TokPos = guardPos then
      Error('Ada: unexpected token in statement, line ' + AIntToStr(CurTok.Line));
    if stmtNode <> -1 then
    begin
      if stmtList = -1 then
      begin
        stmtList := AllocNode(AN_SEQ);
        ASTLeft[stmtList] := stmtNode;
        ASTRight[stmtList] := -1;
        lastStmt := stmtList;
      end
      else
      begin
        ASTRight[lastStmt] := AllocNode(AN_SEQ);
        lastStmt := ASTRight[lastStmt];
        ASTLeft[lastStmt] := stmtNode;
        ASTRight[lastStmt] := -1;
      end;
    end;
  end;
  Result := stmtList;
end;

procedure ParseAProgram;
var
  stmtList, declSeq, declTail, assignNode, lhsNode: Integer;
  vname: AnsiString;
  symIdx: Integer;
  vtype: TTypeKind;
  initNode: Integer;
begin
  if TargetArch <> TARGET_X86_64 then
    Error('Ada frontend: only the x86-64 target is supported by the skeleton (feature-esoteric-ada)');

  BSS_INITIAL_RSP := BSSSize; Inc(BSSSize, 8);
  EmitB($48); EmitB($89); EmitB($24); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);

  Expect(tkProcedure, 'PROCEDURE');
  if CurTok.Kind <> tkIdent then Error('Ada: expected procedure name');
  Next; { program name, e.g. "Hello" -- not otherwise used in the v1 skeleton }
  if not ACurIs('is') then Error('Ada: expected IS');
  Next;

  { declarative part: Ident : TypeName [:= expr]; ... until BEGIN. Each
    initializer becomes an ordinary assignment statement, collected into
    declSeq/declTail and prepended to the body below -- no new AST shape,
    same AN_SEQ/AN_ASSIGN nodes every statement already uses. }
  declSeq := -1; declTail := -1;
  while CurTok.Kind = tkIdent do
  begin
    vname := CurTok.SVal;
    Next;
    Expect(tkColon, ':');
    vtype := AMapTypeName;
    symIdx := AllocVar(vname, vtype);
    if CurTok.Kind = tkAssign then
    begin
      Next;
      ParseExpr;
      initNode := CurASTNode;
      lhsNode := AllocNode(AN_IDENT);
      ASTIVal[lhsNode] := symIdx;
      ASTTk[lhsNode] := Ord(Syms[symIdx].TypeKind);
      assignNode := AllocNode(AN_ASSIGN);
      ASTLeft[assignNode] := lhsNode;
      ASTRight[assignNode] := initNode;
      ASTTk[assignNode] := Ord(tyUnknown);
      if declSeq = -1 then
      begin
        declSeq := AllocNode(AN_SEQ);
        ASTLeft[declSeq] := assignNode;
        ASTRight[declSeq] := -1;
        declTail := declSeq;
      end
      else
      begin
        ASTRight[declTail] := AllocNode(AN_SEQ);
        declTail := ASTRight[declTail];
        ASTLeft[declTail] := assignNode;
        ASTRight[declTail] := -1;
      end;
    end;
    Expect(tkSemicolon, ';');
  end;

  Expect(tkBegin, 'BEGIN');
  stmtList := ParseABlock;
  Expect(tkEnd, 'END');
  if CurTok.Kind = tkIdent then Next; { optional trailing procedure name }
  Expect(tkSemicolon, ';');

  if declSeq <> -1 then
  begin
    ASTRight[declTail] := stmtList;
    stmtList := declSeq;
  end;

  CurASTNode := AllocNode(AN_BLOCK);
  ASTLeft[CurASTNode] := stmtList;
  ASTTk[CurASTNode] := Ord(tyUnknown);

  CompileAST(CurASTNode);
  EmitExit(0);
end;
