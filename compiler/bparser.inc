{ ===== BASIC Parser ===== }

function ParseBStatement: Integer; forward;
function ParseBBlock(endKind1, endKind2: TTokenKind): Integer; forward;

function ParseBPrint: Integer;
var
  node, argNode, lastArg, exprNode: Integer;
begin
  node := AllocNode(AN_WRITE);
  ASTKind[node] := AN_WRITELN;
  
  lastArg := -1;
  repeat
    ParseExpr;
    exprNode := CurASTNode;
    argNode := AllocNode(AN_ARG);
    ASTLeft[argNode] := exprNode;
    ASTRight[argNode] := -1;
    
    if lastArg = -1 then
      ASTLeft[node] := argNode
    else
      ASTRight[lastArg] := argNode;
    lastArg := argNode;
  until not Eat(tkComma);
  
  Result := node;
end;

function ParseBStatement: Integer;
var
  stmtNode: Integer;
  vname: AnsiString;
  symIdx: Integer;
  lhsNode, rhsNode: Integer;
  vtype: TTypeKind;
  condNode, thenNode, elseNode, pairNode: Integer;
  bodyNode, whileNode: Integer;
  initNode, limitNode: Integer;
  stepVal: Int64;
  bodySeq: Integer;
  lhsValNode, lhsIncNode, stepConstNode, lhsValIncNode, addNode, incAssignNode, initAssignNode, curr: Integer;
  pi: Integer;
begin
  stmtNode := -1;

  if CurTok.Kind = tkUses then
  begin
    Next;
    if CurTok.Kind <> tkIdent then Error('BASIC uses: expected unit name');
    vname := CurTok.SVal;
    Next;
    ParseUsesUnit(vname);
  end
  else if CurTok.Kind = tkVar then
  begin
    Next;
    if CurTok.Kind <> tkIdent then Error('Expected identifier');
    vname := CurTok.SVal;
    Next;
    if CurTok.Kind <> tkEq then Error('Expected =');
    Next;
    ParseExpr;
    rhsNode := CurASTNode;
    
    symIdx := FindSym(vname);
    if symIdx < 0 then
    begin
      vtype := tyInteger;
      if ASTTk[rhsNode] = Ord(tyString) then
        vtype := tyString;
      symIdx := AllocVar(vname, vtype);
    end;
    
    lhsNode := AllocNode(AN_IDENT);
    ASTIVal[lhsNode] := symIdx;
    ASTTk[lhsNode] := Ord(Syms[symIdx].TypeKind);

    stmtNode := AllocNode(AN_ASSIGN);
    ASTLeft[stmtNode] := lhsNode;
    ASTRight[stmtNode] := rhsNode;
    ASTTk[stmtNode] := Ord(tyUnknown);
  end
  else if CurTok.Kind = tkwriteln then
  begin
    Next;
    stmtNode := ParseBPrint;
  end
  else if CurTok.Kind = tkIf then
  begin
    Next;
    ParseExpr;
    condNode := CurASTNode;
    Expect(tkThen, 'THEN');
    thenNode := ParseBStatement;
    elseNode := -1;
    if Eat(tkElse) then
      elseNode := ParseBStatement;
      
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
    bodyNode := ParseBBlock(tkEnd, tkEOF);
    Expect(tkEnd, 'WEND');
    
    stmtNode := AllocNode(AN_WHILE);
    ASTLeft[stmtNode] := condNode;
    ASTRight[stmtNode] := bodyNode;
    ASTTk[stmtNode] := Ord(tyUnknown);
  end
  else if CurTok.Kind = tkFor then
  begin
    Next;
    if CurTok.Kind <> tkIdent then Error('Expected identifier after FOR');
    vname := CurTok.SVal;
    Next;
    
    symIdx := FindSym(vname);
    if symIdx < 0 then
      symIdx := AllocVar(vname, tyInteger);
      
    Expect(tkEq, '=');
    ParseExpr;
    initNode := CurASTNode;
    
    Expect(tkTo, 'TO');
    ParseExpr;
    limitNode := CurASTNode;
    
    stepVal := 1;
    if Eat(tkTo) then
    begin
      if CurTok.Kind <> tkInteger then Error('Expected step integer');
      stepVal := CurTok.IVal;
      Next;
    end;
    
    bodySeq := ParseBBlock(tkEnd, tkEOF);
    Expect(tkEnd, 'NEXT');
    if CurTok.Kind = tkIdent then Next;
    
    lhsNode := AllocNode(AN_IDENT);
    ASTIVal[lhsNode] := symIdx;
    ASTTk[lhsNode] := Ord(Syms[symIdx].TypeKind);
    
    initAssignNode := AllocNode(AN_ASSIGN);
    ASTLeft[initAssignNode] := lhsNode;
    ASTRight[initAssignNode] := initNode;
    ASTTk[initAssignNode] := Ord(tyUnknown);
    
    lhsValNode := AllocNode(AN_IDENT);
    ASTIVal[lhsValNode] := symIdx;
    ASTTk[lhsValNode] := Ord(Syms[symIdx].TypeKind);
    
    condNode := AllocNode(AN_BINOP);
    ASTIVal[condNode] := Ord(tkLe);
    ASTLeft[condNode] := lhsValNode;
    ASTRight[condNode] := limitNode;
    ASTTk[condNode] := Ord(tyBoolean);
    
    lhsIncNode := AllocNode(AN_IDENT);
    ASTIVal[lhsIncNode] := symIdx;
    ASTTk[lhsIncNode] := Ord(Syms[symIdx].TypeKind);
    
    stepConstNode := AllocNode(AN_INT_LIT);
    ASTIVal[stepConstNode] := stepVal;
    ASTTk[stepConstNode] := Ord(tyInteger);
    
    lhsValIncNode := AllocNode(AN_IDENT);
    ASTIVal[lhsValIncNode] := symIdx;
    ASTTk[lhsValIncNode] := Ord(Syms[symIdx].TypeKind);
    
    addNode := AllocNode(AN_BINOP);
    ASTIVal[addNode] := Ord(tkPlus);
    ASTLeft[addNode] := lhsValIncNode;
    ASTRight[addNode] := stepConstNode;
    ASTTk[addNode] := Ord(tyInteger);
    
    incAssignNode := AllocNode(AN_ASSIGN);
    ASTLeft[incAssignNode] := lhsIncNode;
    ASTRight[incAssignNode] := addNode;
    ASTTk[incAssignNode] := Ord(tyUnknown);
    
    if bodySeq = -1 then
      bodySeq := incAssignNode
    else
    begin
      curr := bodySeq;
      while ASTRight[curr] <> -1 do
        curr := ASTRight[curr];
      ASTRight[curr] := AllocNode(AN_SEQ);
      curr := ASTRight[curr];
      ASTLeft[curr] := incAssignNode;
      ASTRight[curr] := -1;
    end;
    
    whileNode := AllocNode(AN_WHILE);
    ASTLeft[whileNode] := condNode;
    ASTRight[whileNode] := bodySeq;
    ASTTk[whileNode] := Ord(tyUnknown);
    
    stmtNode := AllocNode(AN_SEQ);
    ASTLeft[stmtNode] := initAssignNode;
    ASTRight[stmtNode] := AllocNode(AN_SEQ);
    ASTLeft[ASTRight[stmtNode]] := whileNode;
    ASTRight[ASTRight[stmtNode]] := -1;
  end
  else if CurTok.Kind = tkEnd then
  begin
    Next;
    stmtNode := AllocNode(AN_HALT);
    ASTTk[stmtNode] := Ord(tyUnknown);
  end
  else if CurTok.Kind = tkHalt then
  begin
    Next;
    if CurTok.Kind = tkInteger then Next; { skip line number target }
    stmtNode := AllocNode(AN_HALT);
    ASTTk[stmtNode] := Ord(tyUnknown);
  end
  else if CurTok.Kind = tkExit then
  begin
    Next;
    stmtNode := AllocNode(AN_EXIT);
    ASTTk[stmtNode] := Ord(tyUnknown);
  end;
  
  if stmtNode = -1 then
  begin
    if CurTok.Kind = tkIdent then
    begin
      vname := CurTok.SVal;
      symIdx := FindSym(vname);
      if symIdx < 0 then
      begin
        pi := FindProc(vname);
        if pi >= 0 then
        begin
          ParseExpr;
          stmtNode := CurASTNode;
        end
        else
        begin
          if (TokPos + 1 < TokCount) and (Tokens[TokPos + 1].Kind = tkEq) then
          begin
            Next;
            Next;
            ParseExpr;
            rhsNode := CurASTNode;
            vtype := tyInteger;
            if ASTTk[rhsNode] = Ord(tyString) then
              vtype := tyString;
            symIdx := AllocVar(vname, vtype);
            
            lhsNode := AllocNode(AN_IDENT);
            ASTIVal[lhsNode] := symIdx;
            ASTTk[lhsNode] := Ord(Syms[symIdx].TypeKind);

            stmtNode := AllocNode(AN_ASSIGN);
            ASTLeft[stmtNode] := lhsNode;
            ASTRight[stmtNode] := rhsNode;
            ASTTk[stmtNode] := Ord(tyUnknown);
          end
          else
            Error('Undefined variable or procedure: ' + vname);
        end;
      end
      else
      begin
        Next;
        if CurTok.Kind <> tkEq then Error('Expected =');
        Next;
        ParseExpr;
        rhsNode := CurASTNode;

        lhsNode := AllocNode(AN_IDENT);
        ASTIVal[lhsNode] := symIdx;
        ASTTk[lhsNode] := Ord(Syms[symIdx].TypeKind);

        stmtNode := AllocNode(AN_ASSIGN);
        ASTLeft[stmtNode] := lhsNode;
        ASTRight[stmtNode] := rhsNode;
        ASTTk[stmtNode] := Ord(tyUnknown);
      end;
    end;
  end;
  
  Result := stmtNode;
end;

function ParseBBlock(endKind1, endKind2: TTokenKind): Integer;
var
  stmtList, lastStmt, stmtNode: Integer;
begin
  stmtList := -1;
  lastStmt := -1;
  while (CurTok.Kind <> tkEOF) and (TokPos - 1 < MainProgramTokCount) and (CurTok.Kind <> endKind1) and (CurTok.Kind <> endKind2) do
  begin
    if (CurTok.Kind = tkSemicolon) or (CurTok.Kind = tkInteger) then
    begin
      Next;
    end
    else
    begin
      stmtNode := ParseBStatement;
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
  end;
  Result := stmtList;
end;

procedure ParseBProgram;
var
  stmtList: Integer;
  jmpPatch: Integer;
begin
  BSS_INITIAL_RSP := BSSSize; Inc(BSSSize, 8);

  EmitB($48); EmitB($89); EmitB($24); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);
  EmitB($E9); jmpPatch := CodeLen; EmitI32(0);

  stmtList := ParseBBlock(tkEOF, tkEOF);
  
  Patch32(jmpPatch, CodeLen - (jmpPatch + 4));

  CurASTNode := AllocNode(AN_BLOCK);
  ASTLeft[CurASTNode] := stmtList;
  ASTTk[CurASTNode] := Ord(tyUnknown);

  CompileAST(CurASTNode);
  EmitExit(0);
end;
