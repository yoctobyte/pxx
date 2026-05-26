{ ===== AST Code Generator ===== }

function GetASTStrVal(node: Integer): AnsiString;
var s: AnsiString; i, off, len, j: Integer;
begin
  s := '';
  off := ASTSOffset[node];
  len := ASTSLen[node];
  i := 0;
  while i < len do
  begin
    j := off + i;
    AppendChar(s, TokChars[j]);
    Inc(i);
  end;
  Result := s;
end;

function GetASTIdentName(node: Integer): AnsiString;
var s: AnsiString; i, off, len, j: Integer;
begin
  s := '';
  off := ASTSOffset[node];
  len := ASTSLen[node];
  i := 0;
  while i < len do
  begin
    j := off + i;
    AppendChar(s, TokChars[j]);
    Inc(i);
  end;
  Result := s;
end;

function ResolveNodeRec(node: Integer): Integer;
begin
  if ASTKind[node] = AN_IDENT then
    Result := Syms[ASTIVal[node]].RecName
  else if ASTKind[node] = AN_FIELD then
  begin
    Result := RecFieldRecId(ResolveNodeRec(ASTLeft[node]), GetASTIdentName(node));
  end
  else if ASTKind[node] = AN_INDEX then
  begin
    if ASTKind[ASTLeft[node]] = AN_IDENT then
      Result := Syms[ASTIVal[ASTLeft[node]]].ElemRecName
    else
      Result := REC_NONE;
  end
  else
    Result := REC_NONE;
end;

function IsNodeArray(node: Integer): Boolean;
begin
  Result := False;
  if ASTKind[node] = AN_IDENT then
    Result := Syms[ASTIVal[node]].IsArray
  else if ASTKind[node] = AN_FIELD then
    Result := RecFieldIsArray(ResolveNodeRec(ASTLeft[node]), GetASTIdentName(node));
end;

procedure GenAST(node: Integer); forward;
procedure GenLValueAddress(node: Integer; var tk: TTypeKind; var recName: Integer; derefClass: Boolean); forward;
procedure GenSpecialCall(specialId: Integer; argHead: Integer); forward;

procedure GenLValueAddress(node: Integer; var tk: TTypeKind; var recName: Integer; derefClass: Boolean);
var
  idx, offset, elemSize, lo, baseNode: Integer;
  fieldName: AnsiString;
  isArr: Boolean;
begin
  if ASTKind[node] = AN_IDENT then
  begin
    idx := ASTIVal[node];
    if Syms[idx].Kind = skGlobal then
    begin
      if (Syms[idx].TypeKind = tyClass) and derefClass then
      begin
        EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset);
      end
      else
      begin
        EmitB($48); EmitB($8D); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset);
      end;
    end
    else
    begin
      if ((Syms[idx].TypeKind = tyClass) and derefClass) or
         ((Syms[idx].Kind = skParam) and
          (Syms[idx].IsRef or Syms[idx].IsArray or (Syms[idx].TypeKind = tyString))) then
      begin
        EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[idx].Offset);
      end
      else
      begin
        EmitB($48); EmitB($8D); EmitB($85); EmitI32(Syms[idx].Offset);
      end;
    end;
    tk := Syms[idx].TypeKind;
    recName := Syms[idx].RecName;
  end
  else if ASTKind[node] = AN_INDEX then
  begin
    baseNode := ASTLeft[node];
    GenLValueAddress(baseNode, tk, recName, True);
    EmitB($50); { push rax -- base address }
    
    GenAST(ASTRight[node]); { rax = index }
    
    isArr := IsNodeArray(baseNode);
    if isArr then
    begin
      if ASTKind[baseNode] = AN_IDENT then
      begin
        if Syms[ASTIVal[baseNode]].RecName = REC_TPARAM then
        begin
          tk := tyRecord;
          recName := REC_TPARAM;
        end
        else
        begin
          tk := Syms[ASTIVal[baseNode]].ElemType;
          recName := Syms[ASTIVal[baseNode]].ElemRecName;
        end;
      end;
    end;
    
    if isArr or (tk = tyRecord) or (tk = tyString) then
    begin
      if (tk = tyString) and not isArr then
      begin
        EmitB($48); EmitB($05); EmitI32(7);
        EmitB($59); { pop rcx -- base address }
        EmitB($48); EmitB($01); EmitB($C8); { add rax, rcx }
        tk := tyChar;
        recName := REC_NONE;
      end
      else
      begin
        elemSize := 1;
        if tk in [tyInteger, tyBoolean, tyClass] then elemSize := 8
        else if tk = tyChar then elemSize := 1
        else if tk = tyString then
        begin
          if (ASTKind[baseNode] = AN_IDENT) and (Syms[ASTIVal[baseNode]].Kind = skGlobal) then
            elemSize := STRING_CAP + 8
          else
            elemSize := LOCAL_STR_CAP + 8;
        end
        else if tk = tyRecord then
        begin
          elemSize := RecSize(recName);
        end;
        
        if elemSize = 8 then
        begin
          EmitB($48); EmitB($C1); EmitB($E0); EmitB($03); { shl rax, 3 }
        end
        else if elemSize > 1 then
        begin
          EmitB($48); EmitB($C7); EmitB($C1); EmitI32(elemSize); { mov rcx, elemSize }
          EmitB($48); EmitB($0F); EmitB($AF); EmitB($C1); { imul rax, rcx }
        end;
        
        lo := 0;
        if ASTKind[baseNode] = AN_IDENT then
        begin
          if Syms[ASTIVal[baseNode]].RecName <> REC_TPARAM then
            lo := Syms[ASTIVal[baseNode]].ConstVal;
        end;
        
        if lo <> 0 then
        begin
          EmitB($48); EmitB($2D); EmitI32(lo * elemSize); { sub rax, lo*elemSize }
        end;
        
        EmitB($59); { pop rcx -- base address }
        EmitB($48); EmitB($01); EmitB($C8); { add rax, rcx }
      end;
    end
    else
      Error('subscripted value is not an array or string');
  end
  else if ASTKind[node] = AN_FIELD then
  begin
    baseNode := ASTLeft[node];
    GenLValueAddress(baseNode, tk, recName, True);
    
    fieldName := GetASTIdentName(node);
    offset := RecFieldOffset(recName, fieldName);
    EmitB($48); EmitB($05); EmitI32(offset); { add rax, offset }
    
    tk := RecFieldType(recName, fieldName);
    recName := RecFieldRecId(recName, fieldName);
  end;
end;

procedure GenSpecialCall(specialId: Integer; argHead: Integer);
var
  arg1, arg2, arg3, idx, pathIdx, dstIdx, lo, hi, nextJmp, falseJmp, trueCount, i, jbePatch: Integer;
  tk: TTypeKind; recName: Integer;
  trueJumps: array[0..127] of Integer;
  argNode, itemNode: Integer;
begin
  if specialId = Ord(tkLength) then
  begin
    GenLValueAddress(ASTLeft[argHead], tk, recName, False);
    EmitB($48); EmitB($8B); EmitB($00); { mov rax, [rax] }
  end
  else if specialId = Ord(tkSysOpen) then
  begin
    arg1 := argHead;
    arg2 := ASTRight[arg1];
    
    idx := ASTIVal[ASTLeft[arg1]];
    EmitTerminateString(idx);
    EmitLeaStrDataRdi(idx);
    
    GenAST(ASTLeft[arg2]);
    EmitB($48); EmitB($89); EmitB($C6); { mov rsi, rax }
    MovRaxImm(0); EmitB($48); EmitB($89); EmitB($C2);
    MovRaxImm(SYS_OPEN); EmitSyscall;
  end
  else if specialId = Ord(tkSysRead) then
  begin
    arg1 := argHead;
    arg2 := ASTRight[arg1];
    arg3 := ASTRight[arg2];
    
    GenAST(ASTLeft[arg1]);
    EmitB($48); EmitB($89); EmitB($C7); { mov rdi, rax }
    
    GenLValueAddress(ASTLeft[arg2], tk, recName, False);
    EmitB($48); EmitB($89); EmitB($C6); { mov rsi, rax }
    
    GenAST(ASTLeft[arg3]);
    EmitB($48); EmitB($89); EmitB($C2);
    
    MovRaxImm(SYS_READ); EmitSyscall;
  end
  else if specialId = Ord(tkSyswrite) then
  begin
    arg1 := argHead;
    arg2 := ASTRight[arg1];
    arg3 := ASTRight[arg2];
    
    GenAST(ASTLeft[arg1]);
    EmitB($48); EmitB($89); EmitB($C7); { mov rdi, rax }
    
    GenLValueAddress(ASTLeft[arg2], tk, recName, False);
    EmitB($48); EmitB($89); EmitB($C6); { mov rsi, rax }
    
    GenAST(ASTLeft[arg3]);
    EmitB($48); EmitB($89); EmitB($C2);
    
    MovRaxImm(1); EmitSyscall;
  end
  else if specialId = Ord(tkSysClose) then
  begin
    GenAST(ASTLeft[argHead]);
    EmitB($48); EmitB($89); EmitB($C7);
    MovRaxImm(SYS_CLOSE); EmitSyscall;
  end
  else if specialId = Ord(tkSysFchmod) then
  begin
    arg1 := argHead;
    arg2 := ASTRight[arg1];
    GenAST(ASTLeft[arg1]);
    EmitB($48); EmitB($89); EmitB($C7);
    GenAST(ASTLeft[arg2]);
    EmitB($48); EmitB($89); EmitB($C6);
    MovRaxImm(91); EmitSyscall;
  end
  else if specialId = Ord(tkArgCount) then
  begin
    EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);
    EmitB($48); EmitB($8B); EmitB($00);
    EmitB($48); EmitB($FF); EmitB($C8);
  end
  else if specialId = Ord(tkArgStr) then
  begin
    arg1 := argHead;
    arg2 := ASTRight[arg1];
    GenAST(ASTLeft[arg1]);
    idx := ASTIVal[ASTLeft[arg2]];
    EmitArgvToString(idx);
  end
  else if specialId = 100 then
  begin
    arg1 := argHead;
    arg2 := ASTRight[arg1];
    pathIdx := ASTIVal[ASTLeft[arg1]];
    dstIdx  := ASTIVal[ASTLeft[arg2]];
    EmitLoadFile(pathIdx, dstIdx);
  end
  else if specialId = 101 then
  begin
    arg1 := argHead;
    arg2 := ASTRight[arg1];
    idx := ASTIVal[ASTLeft[arg1]];
    GenAST(ASTLeft[arg2]);
    EmitStoreStrLen(idx);
  end
  else if specialId = SPECIAL_IN then
  begin
    GenAST(ASTLeft[argHead]);
    EmitB($48); EmitB($89); EmitB($C1); { mov rcx, rax }
    
    trueCount := 0;
    argNode := ASTRight[argHead];
    while argNode <> -1 do
    begin
      itemNode := ASTLeft[argNode];
      if ASTKind[itemNode] = AN_PAIR then
      begin
        lo := ASTIVal[ASTLeft[itemNode]];
        hi := ASTIVal[ASTRight[itemNode]];
        
        EmitB($48); EmitB($81); EmitB($F9); EmitI32(lo); { cmp rcx, lo }
        EmitB($0F); EmitB($8C); nextJmp := CodeLen; EmitI32(0); { jl next }
        EmitB($48); EmitB($81); EmitB($F9); EmitI32(hi); { cmp rcx, hi }
        EmitB($0F); EmitB($8E);
        if trueCount >= 128 then Error('set expression too large');
        trueJumps[trueCount] := CodeLen; Inc(trueCount);
        EmitI32(0);
        Patch32(nextJmp, CodeLen - (nextJmp + 4));
      end
      else
      begin
        lo := ASTIVal[itemNode];
        EmitB($48); EmitB($81); EmitB($F9); EmitI32(lo); { cmp rcx, lo }
        EmitB($0F); EmitB($84);
        if trueCount >= 128 then Error('set expression too large');
        trueJumps[trueCount] := CodeLen; Inc(trueCount);
        EmitI32(0);
      end;
      argNode := ASTRight[argNode];
    end;
    
    MovRaxImm(0);
    EmitB($E9); falseJmp := CodeLen; EmitI32(0);
    for i := 0 to trueCount-1 do
      Patch32(trueJumps[i], CodeLen - (trueJumps[i] + 4));
    MovRaxImm(1);
    Patch32(falseJmp, CodeLen - (falseJmp + 4));
  end
  else if (specialId = Ord(tkOrd)) or (specialId = Ord(tkChr)) or (specialId = Ord(tkInteger_T)) or (specialId = Ord(tkLongWord_T)) then
  begin
    GenAST(ASTLeft[argHead]);
  end
  else if specialId = Ord(tkGetMem) then
  begin
    { Evaluates size expression into rax and runs the bump allocator }
    GenAST(ASTLeft[argHead]);
    
    { Round size up to multiple of 8 for alignment }
    EmitB($48); EmitB($83); EmitB($C0); EmitB($07); { add rax, 7 }
    EmitB($48); EmitB($83); EmitB($E0); EmitB($F8); { and rax, -8 }
    
    { mov rbx, [BSS_HEAP_PTR] }
    EmitB($48); EmitB($8B); EmitB($1C); EmitB($25); EmitGlobRef(BSS_HEAP_PTR);
    
    { add rbx, rax }
    EmitB($48); EmitB($01); EmitB($C3);
    
    { cmp rbx, [BSS_HEAP_END] }
    EmitB($48); EmitB($3B); EmitB($1C); EmitB($25); EmitGlobRef(BSS_HEAP_END);
    
    { jbe skip_brk }
    EmitB($76); jbePatch := CodeLen; EmitB(0);
    
    { push rbx }
    EmitB($53);
    { mov rdi, rbx }
    EmitB($48); EmitB($89); EmitB($DF);
    { mov rax, SYS_BRK }
    MovRaxImm(SYS_BRK);
    { syscall }
    EmitSyscall;
    { pop rbx }
    EmitB($5B);
    { mov [BSS_HEAP_END], rax }
    EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_HEAP_END);
    
    { Patch short jump offset }
    Code[jbePatch] := Byte(CodeLen - (jbePatch + 1));
    
    { mov rax, [BSS_HEAP_PTR] }
    EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(BSS_HEAP_PTR);
    
    { mov [BSS_HEAP_PTR], rbx }
    EmitB($48); EmitB($89); EmitB($1C); EmitB($25); EmitGlobRef(BSS_HEAP_PTR);
  end;
end;

procedure GenAST(node: Integer);
var
  op: TTokenKind;
  pi, i, idx, dummyRec, limitIdx, loopTop, condJmp, exitJmp: Integer;
  thenJmp, elseJmp, pairNode, elseNode, lhsNode, pair3, pair1, pair2: Integer;
  initNode, limitNode, isDownNode, bodyNode, seqNode, argNode, exprNode: Integer;
  si, vidx, specialId, arg1, arg2, arg3, pathIdx, dstIdx, srcIdx, rhsNode, branchJeStart: Integer;
  lhsTk, rhsTk, dummyTk: TTypeKind;
  recName, rhsRecName: Integer;
  down: Boolean;
  jePositions : array[0..255] of Integer;
  jeCount     : Integer;
  jmpPositions: array[0..255] of Integer;
  jmpCount    : Integer;
  nextJmpPositions: array[0..255] of Integer;
  nextJmpCount    : Integer;
  branchSeq, branchPair, labelsHead, stmtNode, labelNode: Integer;
  cv: Int64;
begin
  if node = -1 then Exit;
  case ASTKind[node] of
    AN_INT_LIT:
    begin
      MovRaxImm(ASTIVal[node]);
    end;
    AN_BOOL_LIT:
    begin
      MovRaxImm(ASTIVal[node]);
    end;
    AN_STR_LIT:
    begin
      idx := InternStr(GetASTStrVal(node));
      EmitB($48); EmitB($B8); EmitDataRef(Strs[idx].Offset);
    end;
    AN_IDENT:
    begin
      idx := ASTIVal[node];
      if Syms[idx].Kind = skConst then
      begin
        MovRaxImm(Syms[idx].ConstVal);
      end
      else
      begin
        if (Syms[idx].TypeKind = tyString) or Syms[idx].IsArray then
        begin
          CompileLValueAddressInternal(idx, dummyTk, dummyRec);
        end
        else
          EmitLoadVar(idx);
      end;
    end;
    AN_INDEX, AN_FIELD:
    begin
      GenLValueAddress(node, dummyTk, dummyRec, False);
      if dummyTk = tyString then
        begin { address stays in rax } end
      else if dummyTk in [tyInteger, tyBoolean, tyClass] then
        begin EmitB($48); EmitB($8B); EmitB($00); end
      else if dummyTk = tyChar then
        begin EmitB($48); EmitB($0F); EmitB($B6); EmitB($00); end;
    end;
    AN_BINOP:
    begin
      GenAST(ASTLeft[node]);
      EmitB($50); { push rax }
      GenAST(ASTRight[node]);
      EmitB($48); EmitB($89); EmitB($C1); { mov rcx, rax }
      EmitB($58); { pop rax }
      
      op := IntToTokenKind(ASTIVal[node]);
      if (op = tkIdent) and (GetASTIdentName(node) = 'shr') then
      begin
        EmitB($48); EmitB($D3); EmitB($E8); { shr rax, cl }
      end
      else
      begin
        case op of
          tkStar: begin EmitB($48); EmitB($0F); EmitB($AF); EmitB($C1); end;
          tkDiv:  begin EmitB($48); EmitB($99); EmitB($48); EmitB($F7); EmitB($F9); end;
          tkMod:  begin EmitB($48); EmitB($99); EmitB($48); EmitB($F7); EmitB($F9);
                        EmitB($48); EmitB($89); EmitB($D0); end;
          tkAnd:  begin EmitB($48); EmitB($21); EmitB($C8); end;
          tkPlus:  begin EmitB($48); EmitB($01); EmitB($C8); end;
          tkMinus: begin EmitB($48); EmitB($29); EmitB($C8); end;
          tkOr:    begin EmitB($48); EmitB($09); EmitB($C8); end;
          
          tkEq, tkNeq, tkLt, tkLe, tkGt, tkGe:
          begin
            if (ASTTk[ASTLeft[node]] = Ord(tyString)) or (ASTTk[ASTRight[node]] = Ord(tyString)) then
            begin
              EmitStrCmpReg(op = tkEq);
            end
            else
            begin
              EmitB($48); EmitB($3B); EmitB($C1); { cmp rax, rcx }
              case op of
                tkEq:  begin EmitB($0F); EmitB($94); EmitB($C0); end;
                tkNeq: begin EmitB($0F); EmitB($95); EmitB($C0); end;
                tkLt:  begin EmitB($0F); EmitB($9C); EmitB($C0); end;
                tkLe:  begin EmitB($0F); EmitB($9E); EmitB($C0); end;
                tkGt:  begin EmitB($0F); EmitB($9F); EmitB($C0); end;
                tkGe:  begin EmitB($0F); EmitB($9D); EmitB($C0); end;
              end;
              EmitB($48); EmitB($0F); EmitB($B6); EmitB($C0);
            end;
          end;
        end;
      end;
    end;
    AN_NEG:
    begin
      GenAST(ASTLeft[node]);
      EmitB($48); EmitB($F7); EmitB($D8);
    end;
    AN_NOT:
    begin
      GenAST(ASTLeft[node]);
      EmitB($48); EmitB($83); EmitB($F0); EmitB($01);
    end;
    AN_CALL:
    begin
      pi := ASTIVal[node];
      if pi >= 0 then
      begin
        pathIdx := 0;
        argNode := ASTLeft[node];
        while argNode <> -1 do
        begin
          if Procs[pi].Params[pathIdx].IsRef then
          begin
            GenLValueAddress(ASTLeft[argNode], dummyTk, dummyRec, False);
          end
          else
          begin
            GenAST(ASTLeft[argNode]);
          end;
          EmitB($50);
          Inc(pathIdx);
          argNode := ASTRight[argNode];
        end;
        for i := Procs[pi].ParamCount-1 downto 0 do
          case i of
            0: EmitB($5F);
            1: EmitB($5E);
            2: EmitB($5A);
            3: EmitB($59);
            4: begin EmitB($41); EmitB($58); end;
            5: begin EmitB($41); EmitB($59); end;
          end;
        EmitCallProc(pi);
      end
      else
      begin
        GenSpecialCall(-pi, ASTLeft[node]);
      end;
    end;
    AN_ASSIGN:
    begin
      lhsNode := ASTLeft[node];
      rhsNode := ASTRight[node];
      
      if (ASTKind[lhsNode] = AN_IDENT) and (Syms[ASTIVal[lhsNode]].TypeKind = tyString) and not Syms[ASTIVal[lhsNode]].IsArray then
      begin
        dstIdx := ASTIVal[lhsNode];
        if ASTKind[rhsNode] = AN_STR_LIT then
        begin
          si := InternStr(GetASTStrVal(rhsNode));
          EmitStrAssignLiteral(dstIdx, Strs[si].Offset, Strs[si].Len);
        end
        else if (ASTKind[rhsNode] = AN_CALL) and (ASTIVal[rhsNode] = -Ord(tkArgStr)) then
        begin
          GenAST(ASTLeft[ASTLeft[rhsNode]]);
          EmitArgvToString(dstIdx);
        end
        else if (ASTKind[rhsNode] = AN_IDENT) and (Syms[ASTIVal[rhsNode]].TypeKind = tyString) and not Syms[ASTIVal[rhsNode]].IsArray then
        begin
          srcIdx := ASTIVal[rhsNode];
          EmitStrAssignVar(dstIdx, srcIdx);
        end
        else
        begin
          if ASTKind[rhsNode] = AN_CALL then
            GenAST(rhsNode)
          else
            GenLValueAddress(rhsNode, rhsTk, dummyRec, False);
          EmitB($50);
          CompileLValueAddressInternal(dstIdx, dummyTk, dummyRec);
          EmitB($48); EmitB($89); EmitB($C7);
          EmitB($5E);
          EmitB($48); EmitB($8B); EmitB($06);
          EmitB($48); EmitB($89); EmitB($07);
          EmitB($48); EmitB($89); EmitB($C1);
          EmitB($48); EmitB($83); EmitB($C6); EmitB($08);
          EmitB($48); EmitB($83); EmitB($C7); EmitB($08);
          EmitB($F3); EmitB($A4);
        end;
      end
      else
      begin
        GenLValueAddress(lhsNode, lhsTk, dummyRec, False);
        EmitB($50); { push rax }
        
        if lhsTk = tyString then
        begin
          if ASTKind[rhsNode] = AN_STR_LIT then
          begin
            si := InternStr(GetASTStrVal(rhsNode));
            EmitB($5F); { pop rdi }
            EmitB($48); EmitB($C7); EmitB($C0); EmitI32(Strs[si].Len);
            EmitB($48); EmitB($89); EmitB($07);
            EmitB($48); EmitB($BE); EmitDataRef(Strs[si].Offset + 8);
            EmitB($48); EmitB($89); EmitB($C1);
            EmitB($48); EmitB($83); EmitB($C7); EmitB($08);
            EmitB($F3); EmitB($A4);
          end
          else if (ASTKind[rhsNode] = AN_CALL) and (ASTIVal[rhsNode] = -Ord(tkArgStr)) then
          begin
            GenAST(ASTLeft[ASTLeft[rhsNode]]);
            EmitB($50);
            EmitB($5F);
            EmitB($58);
            EmitArgvToAddr;
          end
          else
          begin
            if ASTKind[rhsNode] = AN_CALL then
              GenAST(rhsNode)
            else
              GenLValueAddress(rhsNode, rhsTk, dummyRec, False);
            EmitB($5F);
            EmitB($48); EmitB($89); EmitB($C6);
            EmitB($48); EmitB($8B); EmitB($06);
            EmitB($48); EmitB($89); EmitB($07);
            EmitB($48); EmitB($89); EmitB($C1);
            EmitB($48); EmitB($83); EmitB($C6); EmitB($08);
            EmitB($48); EmitB($83); EmitB($C7); EmitB($08);
            EmitB($F3); EmitB($A4);
          end;
        end
        else
        begin
          GenAST(rhsNode);
          EmitB($59); { pop rcx }
          if lhsTk in [tyInteger, tyBoolean, tyClass] then
            begin EmitB($48); EmitB($89); EmitB($01); end
          else if lhsTk = tyChar then
            begin EmitB($88); EmitB($01); end;
        end;
      end;
    end;
    AN_IF:
    begin
      GenAST(ASTLeft[node]);
      EmitB($48); EmitB($85); EmitB($C0);
      EmitB($0F); EmitB($84); thenJmp := CodeLen; EmitI32(0);
      
      pairNode := ASTRight[node];
      GenAST(ASTLeft[pairNode]);
      
      elseNode := ASTRight[pairNode];
      if elseNode <> -1 then
      begin
        EmitB($E9); elseJmp := CodeLen; EmitI32(0);
        Patch32(thenJmp, CodeLen - (thenJmp + 4));
        GenAST(elseNode);
        Patch32(elseJmp, CodeLen - (elseJmp + 4));
      end
      else
        Patch32(thenJmp, CodeLen - (thenJmp + 4));
    end;
    AN_WHILE:
    begin
      loopTop := CodeLen;
      GenAST(ASTLeft[node]);
      EmitB($48); EmitB($85); EmitB($C0);
      EmitB($0F); EmitB($84); condJmp := CodeLen; EmitI32(0);
      
      GenAST(ASTRight[node]);
      EmitB($E9); EmitI32(loopTop - (CodeLen + 4));
      Patch32(condJmp, CodeLen - (condJmp + 4));
    end;
    AN_FOR:
    begin
      lhsNode := ASTLeft[node];
      pair3 := ASTRight[node];
      pair1 := ASTLeft[pair3];
      pair2 := ASTRight[pair3];
      
      initNode  := ASTLeft[pair1];
      limitNode := ASTRight[pair1];
      
      isDownNode := ASTLeft[pair2];
      bodyNode   := ASTRight[pair2];
      
      GenAST(initNode);
      idx := ASTIVal[lhsNode];
      EmitStoreVar(idx);
      
      GenAST(limitNode);
      limitIdx := AllocTemp;
      EmitStoreVar(limitIdx);
      
      loopTop := CodeLen;
      EmitLoadVar(idx);
      EmitCmpRaxVar(limitIdx);
      
      down := ASTIVal[isDownNode] = 1;
      EmitB($0F);
      if down then EmitB($8C) else EmitB($8F);
      exitJmp := CodeLen; EmitI32(0);
      
      GenAST(bodyNode);
      
      EmitLoadVar(idx);
      if down then
        begin EmitB($48); EmitB($FF); EmitB($C8); end
      else
        begin EmitB($48); EmitB($FF); EmitB($C0); end;
      EmitStoreVar(idx);
      
      EmitB($E9); EmitI32(loopTop - (CodeLen + 4));
      Patch32(exitJmp, CodeLen - (exitJmp + 4));
    end;
    AN_REPEAT:
    begin
      loopTop := CodeLen;
      GenAST(ASTLeft[node]);
      GenAST(ASTRight[node]);
      EmitB($48); EmitB($85); EmitB($C0);
      EmitB($0F); EmitB($84); EmitI32(loopTop - (CodeLen + 4));
    end;
    AN_CASE:
    begin
      GenAST(ASTLeft[node]);
      EmitB($48); EmitB($89); EmitB($C1);
      
      jeCount := 0;
      jmpCount := 0;
      nextJmpCount := 0;
      
      branchSeq := ASTRight[node];
      while branchSeq <> -1 do
      begin
        branchPair := ASTLeft[branchSeq];
        labelsHead := ASTLeft[branchPair];
        stmtNode   := ASTRight[branchPair];
        
        if labelsHead = -1 then
        begin
          if nextJmpCount > 0 then
          begin
            Patch32(nextJmpPositions[nextJmpCount-1], CodeLen - (nextJmpPositions[nextJmpCount-1] + 4));
            Dec(nextJmpCount);
          end;
          GenAST(stmtNode);
        end
        else
        begin
          if nextJmpCount > 0 then
          begin
            Patch32(nextJmpPositions[nextJmpCount-1], CodeLen - (nextJmpPositions[nextJmpCount-1] + 4));
            Dec(nextJmpCount);
          end;
          
          branchJeStart := jeCount;
          labelNode := labelsHead;
          while labelNode <> -1 do
          begin
            cv := ASTIVal[ASTLeft[labelNode]];
            EmitB($48); EmitB($81); EmitB($F9); EmitI32(cv);
            EmitB($0F); EmitB($84);
            if jeCount >= 256 then Error('case statement too large');
            jePositions[jeCount] := CodeLen; Inc(jeCount);
            EmitI32(0);
            labelNode := ASTRight[labelNode];
          end;
          
          EmitB($E9);
          if nextJmpCount >= 256 then Error('case statement too large');
          nextJmpPositions[nextJmpCount] := CodeLen; Inc(nextJmpCount);
          EmitI32(0);
          
          for i := branchJeStart to jeCount-1 do
            Patch32(jePositions[i], CodeLen - (jePositions[i] + 4));
            
          GenAST(stmtNode);
          
          EmitB($E9);
          if jmpCount >= 256 then Error('case statement too large');
          jmpPositions[jmpCount] := CodeLen; Inc(jmpCount);
          EmitI32(0);
        end;
        branchSeq := ASTRight[branchSeq];
      end;
      
      if nextJmpCount > 0 then
      begin
        Patch32(nextJmpPositions[nextJmpCount-1], CodeLen - (nextJmpPositions[nextJmpCount-1] + 4));
        Dec(nextJmpCount);
      end;
      
      for i := 0 to jmpCount-1 do
        Patch32(jmpPositions[i], CodeLen - (jmpPositions[i] + 4));
    end;
    AN_BLOCK:
    begin
      GenAST(ASTLeft[node]);
    end;
    AN_SEQ:
    begin
      seqNode := node;
      while seqNode <> -1 do
      begin
        GenAST(ASTLeft[seqNode]);
        seqNode := ASTRight[seqNode];
      end;
    end;
    AN_WRITELN, AN_WRITE:
    begin
      argNode := ASTLeft[node];
      while argNode <> -1 do
      begin
        exprNode := ASTLeft[argNode];
        if ASTKind[exprNode] = AN_STR_LIT then
        begin
          si := InternStr(GetASTStrVal(exprNode));
          if Strs[si].Len > 0 then EmitwriteSyscall(Strs[si].Offset + 8, Strs[si].Len);
        end
        else if ASTKind[exprNode] = AN_IDENT then
        begin
          vidx := ASTIVal[exprNode];
          if (vidx >= 0) and (Syms[vidx].TypeKind = tyString) and not Syms[vidx].IsArray then
          begin
            EmitwriteStrVar(vidx);
          end
          else if (vidx >= 0) and Syms[vidx].IsArray and (Syms[vidx].ElemType = tyChar) then
          begin
            GenAST(exprNode);
            EmitwriteChar;
          end
          else
          begin
            GenAST(exprNode);
            EmitwriteInt;
          end;
        end
        else
        begin
          GenAST(exprNode);
          if ASTTk[exprNode] = Ord(tyChar) then
            EmitwriteChar
          else if ASTTk[exprNode] = Ord(tyString) then
          begin
            EmitB($48); EmitB($89); EmitB($C6); { mov rsi, rax }
            EmitB($48); EmitB($8B); EmitB($10); { mov rdx, [rax] }
            EmitB($48); EmitB($83); EmitB($C6); EmitB($08); { add rsi, 8 }
            MovRaxImm(SYS_WRITE); MovRdiImm(STDOUT); EmitSyscall;
          end
          else
            EmitwriteInt;
        end;
        argNode := ASTRight[argNode];
      end;
      if ASTKind[node] = AN_WRITELN then
        EmitwriteSyscall(NEWLINE_OFFSET, 1);
    end;
    AN_HALT, AN_EXIT:
    begin
      exprNode := ASTLeft[node];
      if exprNode <> -1 then
      begin
        GenAST(exprNode);
        if ASTKind[node] = AN_HALT then
        begin
          EmitB($48); EmitB($89); EmitB($C7);
          MovRaxImm(SYS_EXIT);
          EmitSyscall;
        end
        else
        begin
          if CurProc >= 0 then
          begin
            if Procs[CurProc].RetSymIdx >= 0 then
              EmitStoreVar(Procs[CurProc].RetSymIdx);
            EmitProcEpilog(Procs[CurProc].RetSymIdx);
          end
          else EmitExit(0);
        end;
      end
      else
      begin
        if ASTKind[node] = AN_HALT then
          EmitExit(0)
        else
        begin
          if CurProc >= 0 then EmitProcEpilog(Procs[CurProc].RetSymIdx)
          else EmitExit(0);
        end;
      end;
    end;
  end;
end;

procedure CompileAST(node: Integer);
begin
  GenAST(node);
end;
