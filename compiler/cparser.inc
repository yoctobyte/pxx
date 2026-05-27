{ ===== C Parser ===== }

function ParseCBlockAST: Integer; forward;
function ParseCStatementAST: Integer; forward;

function IsCTypeTok: Boolean;
begin
  Result := CurTok.Kind in [tkInteger_T, tkChar_T];
end;

function ParseCPrintfAST: Integer;
var node, argNode, strNode: Integer;
begin
  Next; { skip 'printf' }
  Expect(tkLParen, '(');
  node := AllocNode(AN_WRITE);
  if CurTok.Kind = tkString then
  begin
    strNode := AllocNode(AN_STR_LIT);
    ASTSOffset[strNode] := Tokens[TokPos - 1].SOffset;
    ASTSLen[strNode] := Tokens[TokPos - 1].SLen;
    ASTTk[strNode] := Ord(tyString);
    Next;
    argNode := AllocNode(AN_ARG);
    ASTLeft[argNode] := strNode;
    ASTLeft[node] := argNode;
  end;
  { skip any remaining args }
  while (CurTok.Kind <> tkRParen) and (CurTok.Kind <> tkEOF) do Next;
  Expect(tkRParen, ')');
  Eat(tkSemicolon);
  Result := node;
end;

function ParseCStatementAST: Integer;
var node, exprNode: Integer;
begin
  Result := -1;
  if CurTok.Kind = tkEOF then Exit;

  { return expr; }
  if CurTok.Kind = tkExit then
  begin
    Next;
    node := AllocNode(AN_EXIT);
    ParseExpr;
    ASTLeft[node] := CurASTNode;
    Eat(tkSemicolon);
    Result := node;
    Exit;
  end;

  { printf(...) }
  if (CurTok.Kind = tkIdent) and (CurTok.SVal = 'printf') then
  begin
    Result := ParseCPrintfAST;
    Exit;
  end;

  { nested block }
  if CurTok.Kind = tkBegin then
  begin
    Result := ParseCBlockAST;
    Exit;
  end;

  { skip type declarations and unknown statements }
  while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEnd) and
        (CurTok.Kind <> tkEOF) do Next;
  Eat(tkSemicolon);
end;

function ParseCBlockAST: Integer;
var blockNode, seqNode, stmtNode, lastSeq: Integer;
begin
  Expect(tkBegin, '{');
  blockNode := AllocNode(AN_BLOCK);
  lastSeq := -1;
  while (CurTok.Kind <> tkEnd) and (CurTok.Kind <> tkEOF) do
  begin
    stmtNode := ParseCStatementAST;
    if stmtNode <> -1 then
    begin
      seqNode := AllocNode(AN_SEQ);
      ASTLeft[seqNode] := stmtNode;
      if lastSeq = -1 then
        ASTLeft[blockNode] := seqNode
      else
        ASTRight[lastSeq] := seqNode;
      lastSeq := seqNode;
    end;
  end;
  Expect(tkEnd, '}');
  Result := blockNode;
end;

procedure ParseCProgram;
var jmpPatch, node: Integer; name: AnsiString;
begin
  BSS_INITIAL_RSP := BSSSize; Inc(BSSSize, 8);

  EmitB($48); EmitB($89); EmitB($24); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);
  EmitB($E9); jmpPatch := CodeLen; EmitI32(0);

  { Scan top level for 'main' function definition }
  while CurTok.Kind <> tkEOF do
  begin
    if IsCTypeTok then
    begin
      Next;
      if CurTok.Kind = tkStar then Next;  { pointer return type }
      if CurTok.Kind = tkIdent then
      begin
        name := CurTok.SVal;
        Next;
        if CurTok.Kind = tkLParen then
        begin
          { skip parameter list }
          while (CurTok.Kind <> tkRParen) and (CurTok.Kind <> tkEOF) do Next;
          Expect(tkRParen, ')');
          if CurTok.Kind = tkBegin then
          begin
            if name = 'main' then
            begin
              Patch32(jmpPatch, CodeLen - (jmpPatch + 4));
              node := ParseCBlockAST;
              CompileAST(node);
              EmitExit(0);
              ApplyCallFixups;
              Exit;
            end
            else
            begin
              { skip non-main function bodies for now }
              node := ParseCBlockAST;
            end;
          end;
        end
        else
        begin
          { global variable declaration — skip to ; }
          while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
          Eat(tkSemicolon);
        end;
      end;
    end
    else
      Next;
  end;
  Error('main function not found');
end;

procedure ParseCSubroutine;
var
  retType: TTypeKind;
  name: AnsiString;
  isFunc: Boolean;
  nparams, pi, i, idx, patchPos, sz: Integer;
  ptypes: array[0..15] of TTypeKind;
  pnames: array[0..15] of AnsiString;
  savedSC, savedFS, node, savedCurProc: Integer;
begin
  retType := tyInteger;
  if CurTok.Kind = tkInteger_T then retType := tyInteger
  else if CurTok.Kind = tkChar_T then retType := tyChar;
  Next;
  
  if CurTok.Kind = tkStar then Next; { skip pointer type like int* }
  
  if CurTok.Kind <> tkIdent then
  begin
    while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
    Eat(tkSemicolon);
    Exit;
  end;
  name := CurTok.SVal;
  Next;

  if CurTok.Kind <> tkLParen then
  begin
    while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkEOF) do Next;
    Eat(tkSemicolon);
    Exit;
  end;
  Expect(tkLParen, '(');
  nparams := 0;
  while (CurTok.Kind <> tkRParen) and (CurTok.Kind <> tkEOF) do
  begin
    if IsCTypeTok then
    begin
      ptypes[nparams] := tyInteger;
      if CurTok.Kind = tkChar_T then ptypes[nparams] := tyChar;
      Next;

      if CurTok.Kind = tkStar then Next;

      if CurTok.Kind = tkIdent then
      begin
        pnames[nparams] := CurTok.SVal;
        Next;
      end
      else
      begin
        pnames[nparams] := 'arg0';
        pnames[nparams][4] := Chr(Ord('0') + nparams);
      end;
      Inc(nparams);
    end
    else
      Next;
    Eat(tkComma);
  end;
  Expect(tkRParen, ')');
  
  isFunc := True; { In C, everything is a function }
  
  { Register or locate Proc }
  pi := FindProc(name);
  if pi < 0 then
    pi := RegisterProc(name, isFunc, retType, nparams, pnames, ptypes);
  
  { If it is just a declaration (ends with ';'), we are done! }
  while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkBegin) and
        (CurTok.Kind <> tkEOF) do Next;
  if CurTok.Kind = tkSemicolon then
  begin
    ProcExternal[pi] := True;
    ProcLibrary[pi] := InternStr(CurrentCLibrary);
    Next;
    Exit;
  end;
  
  { Otherwise, it has a body! }
  ProcExternal[pi] := False;
  Procs[pi].BodyAddr := CodeLen;
  
  { Save scope }
  savedSC := SymCount;
  savedFS := FrameSize;
  FrameSize := 0;
  CurProc := pi;
  Procs[pi].ScopeBase := SymCount;
  
  { Allocate parameter slots }
  for i := 0 to nparams-1 do
  begin
    idx := AllocParam(pnames[i], ptypes[i], False, False);
    Procs[pi].Params[i].SymIdx := idx;
  end;
  
  { Return value slot }
  AllocVar('Result', retType);
  Procs[pi].RetSymIdx := SymCount - 1;
  Syms[SymCount-1].Kind := skLocal;
  
  { Prologue }
  patchPos := EmitProcPrologue;
  Procs[pi].FramePatch := patchPos;
  
  { Copy registers to stack params }
  for i := 0 to nparams-1 do
  begin
    idx := Procs[pi].Params[i].SymIdx;
    sz := ParamSize(idx);
    if i < 4 then
    begin
      if sz = 1 then
      begin
        if (i = 0) or (i = 1) then EmitB($40); { REX prefix for dil, sil }
        EmitB($88);
      end
      else if sz = 2 then
      begin
        EmitB($66); EmitB($89);
      end
      else if sz = 4 then
      begin
        EmitB($89);
      end
      else
      begin
        EmitB($48); EmitB($89);
      end;

      case i of
        0: EmitB($BD);   { rdi }
        1: EmitB($B5);   { rsi }
        2: EmitB($95);   { rdx }
        3: EmitB($8D);   { rcx }
      end;
      EmitI32(Syms[idx].Offset);
    end
    else if i = 4 then
    begin
      if sz = 1 then
      begin
        EmitB($44); EmitB($88); EmitB($85);
      end
      else if sz = 2 then
      begin
        EmitB($66); EmitB($44); EmitB($89); EmitB($85);
      end
      else if sz = 4 then
      begin
        EmitB($44); EmitB($89); EmitB($85);
      end
      else
      begin
        EmitB($4C); EmitB($89); EmitB($85);
      end;
      EmitI32(Syms[idx].Offset);
    end
    else if i = 5 then
    begin
      if sz = 1 then
      begin
        EmitB($44); EmitB($88); EmitB($8D);
      end
      else if sz = 2 then
      begin
        EmitB($66); EmitB($44); EmitB($89); EmitB($8D);
      end
      else if sz = 4 then
      begin
        EmitB($44); EmitB($89); EmitB($8D);
      end
      else
      begin
        EmitB($4C); EmitB($89); EmitB($8D);
      end;
      EmitI32(Syms[idx].Offset);
    end;
  end;
  
  { Parse & Compile Body }
  node := ParseCBlockAST;
  CompileAST(node);
  
  { Epilogue }
  EmitProcEpilog(Procs[pi].RetSymIdx);
  PatchProcPrologue(patchPos, FrameSize);
  
  { Restore scope }
  SymCount := savedSC;
  FrameSize := savedFS;
  CurProc := -1;
end;

procedure ParseCUnit;
begin
  while CurTok.Kind <> tkEOF do
  begin
    if IsCTypeTok then
      ParseCSubroutine
    else
      Next;
  end;
end;
