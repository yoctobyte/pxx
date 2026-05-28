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
  else if (ASTKind[node] = AN_CALL) and (ASTIVal[node] = -Ord(tkGetMem)) then
    Result := ASTRight[node]
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

procedure EmitCodeCall(addr: Integer);
begin
  EmitB($E8);
  EmitI32(addr - (CodeLen + 4));
end;

procedure EmitExceptionRuntime;
var unhandledJmp, si: Integer;
begin
  { Save enough integer state to return from a raise into the protected frame. }
  ExcSetJmpAddr := CodeLen;
  EmitB($48); EmitB($89); EmitB($1F);                         { mov [rdi], rbx }
  EmitB($48); EmitB($89); EmitB($6F); EmitB($08);             { mov [rdi+8], rbp }
  EmitB($4C); EmitB($89); EmitB($67); EmitB($10);             { mov [rdi+16], r12 }
  EmitB($4C); EmitB($89); EmitB($6F); EmitB($18);             { mov [rdi+24], r13 }
  EmitB($4C); EmitB($89); EmitB($77); EmitB($20);             { mov [rdi+32], r14 }
  EmitB($4C); EmitB($89); EmitB($7F); EmitB($28);             { mov [rdi+40], r15 }
  EmitB($48); EmitB($8D); EmitB($44); EmitB($24); EmitB($08); { lea rax, [rsp+8] }
  EmitB($48); EmitB($89); EmitB($47); EmitB($30);             { mov [rdi+48], rax }
  EmitB($48); EmitB($8B); EmitB($04); EmitB($24);             { mov rax, [rsp] }
  EmitB($48); EmitB($89); EmitB($47); EmitB($38);             { mov [rdi+56], rax }
  EmitB($31); EmitB($C0);                                     { xor eax, eax }
  EmitB($C3);                                                  { ret }

  ExcLongJmpAddr := CodeLen;
  EmitB($48); EmitB($8B); EmitB($1F);                         { mov rbx, [rdi] }
  EmitB($48); EmitB($8B); EmitB($6F); EmitB($08);             { mov rbp, [rdi+8] }
  EmitB($4C); EmitB($8B); EmitB($67); EmitB($10);             { mov r12, [rdi+16] }
  EmitB($4C); EmitB($8B); EmitB($6F); EmitB($18);             { mov r13, [rdi+24] }
  EmitB($4C); EmitB($8B); EmitB($77); EmitB($20);             { mov r14, [rdi+32] }
  EmitB($4C); EmitB($8B); EmitB($7F); EmitB($28);             { mov r15, [rdi+40] }
  EmitB($48); EmitB($8B); EmitB($67); EmitB($30);             { mov rsp, [rdi+48] }
  EmitB($B8); EmitI32(1);                                     { mov eax, 1 }
  EmitB($FF); EmitB($67); EmitB($38);                         { jmp qword [rdi+56] }

  ExcRaiseAddr := CodeLen;
  EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_TOP);
  EmitB($48); EmitB($85); EmitB($C0);                         { test rax, rax }
  EmitB($0F); EmitB($84); unhandledJmp := CodeLen; EmitI32(0); { jz unhandled }
  EmitB($48); EmitB($8D); EmitB($78); EmitB(EXC_JMP_OFFSET);  { lea rdi, [rax+8] }
  EmitB($E9); EmitI32(ExcLongJmpAddr - (CodeLen + 4));        { jmp longjmp }
  Patch32(unhandledJmp, CodeLen - (unhandledJmp + 4));

  if not NoUnhandledHandler then
  begin
    si := InternStr('Unhandled exception');
    MovRaxImm(SYS_WRITE); MovRdiImm(2);
    EmitB($48); EmitB($BE); EmitDataRef(Strs[si].Offset + 8);
    MovRdxImm(Strs[si].Len); EmitSyscall;
    MovRaxImm(SYS_WRITE); MovRdiImm(2);
    EmitB($48); EmitB($BE); EmitDataRef(NEWLINE_OFFSET);
    MovRdxImm(1); EmitSyscall;
  end;
  EmitExit(1);
end;

procedure EmitUnlinkExceptionFrames(count: Integer);
var i: Integer;
begin
  for i := 1 to count do
  begin
    EmitB($48); EmitB($8B); EmitB($0C); EmitB($25); EmitGlobRef(BSS_EXC_TOP);
    EmitB($48); EmitB($8B); EmitB($09); { mov rcx, [rcx] }
    EmitB($48); EmitB($89); EmitB($0C); EmitB($25); EmitGlobRef(BSS_EXC_TOP);
  end;
end;

procedure EmitLeaveExceptionFrames(count: Integer);
var i: Integer;
begin
  for i := 1 to count do
  begin
    EmitB($48); EmitB($8B); EmitB($04); EmitB($24); { mov rax, [rsp] }
    EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_TOP);
    EmitB($48); EmitB($83); EmitB($C4); EmitB(EXC_FRAME_SIZE); { add rsp, frame }
  end;
end;

procedure EmitCleanupToDepth(targetDepth: Integer);
var current, bodyNode, savedDepth: Integer;
begin
  current := ExceptionCodegenDepth;
  while current > targetDepth do
  begin
    EmitLeaveExceptionFrames(1);
    bodyNode := ExceptionFinallyBody[current - 1];
    if bodyNode <> -1 then
    begin
      savedDepth := ExceptionCodegenDepth;
      ExceptionCodegenDepth := current - 1;
      GenAST(bodyNode);
      ExceptionCodegenDepth := savedDepth;
    end;
    Dec(current);
  end;
end;

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
        if tk = tyString then
        begin
          if (ASTKind[baseNode] = AN_IDENT) and (Syms[ASTIVal[baseNode]].Kind = skGlobal) then
            elemSize := STRING_CAP + 8
          else
            elemSize := LOCAL_STR_CAP + 8;
        end
        else if tk = tyRecord then
        begin
          elemSize := RecSize(recName);
        end
        else
        begin
          elemSize := TypeSize(tk);
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
  pi, i, idx, dummyRec, limitIdx, loopTop, condJmp, exitJmp, slot: Integer;
  thenJmp, elseJmp, pairNode, elseNode, lhsNode, pair3, pair1, pair2: Integer;
  initNode, limitNode, isDownNode, bodyNode, seqNode, argNode, exprNode: Integer;
  si, vidx, specialId, arg1, arg2, arg3, pathIdx, dstIdx, srcIdx, rhsNode, branchJeStart, wid: Integer;
  breakBase, continueBase, continueTarget: Integer;
  handlerNode, handlerNextJmp: Integer;
  lhsTk, rhsTk, dummyTk: TTypeKind;
  recName, rhsRecName, opOvrlIdx: Integer;
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
    AN_FLOAT_LIT:
    begin
      { align data to 8 bytes, embed IEEE 754 double bits, load into xmm0 }
      while (DataLen mod 8) <> 0 do
        begin if DataLen >= MAX_DATA then Error('data overflow'); Data[DataLen] := 0; Inc(DataLen); end;
      idx := DataLen;
      cv := ASTIVal[node];
      for i := 0 to 7 do
        begin if DataLen >= MAX_DATA then Error('data overflow'); Data[DataLen] := Byte((cv shr (i*8)) and $FF); Inc(DataLen); end;
      EmitB($48); EmitB($B8); EmitDataRef(idx);   { mov rax, <abs addr of float const> }
      EmitB($F2); EmitB($0F); EmitB($10); EmitB($00); { movsd xmm0, [rax] }
      LastExprTk := tyDouble;
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
      else if TypeIsFloat(dummyTk) then
      begin
        if dummyTk = tySingle then
          begin EmitB($F3); EmitB($0F); EmitB($10); EmitB($00); end  { movss xmm0, [rax] }
        else if dummyTk = tyExtended then
        begin
          EmitB($48); EmitB($83); EmitB($EC); EmitB($08);              { sub rsp, 8 }
          EmitB($DF); EmitB($28);                                       { fldt [rax] }
          EmitB($DD); EmitB($1C); EmitB($24);                          { fstpl [rsp] }
          EmitB($F2); EmitB($0F); EmitB($10); EmitB($04); EmitB($24); { movsd xmm0, [rsp] }
          EmitB($48); EmitB($83); EmitB($C4); EmitB($08);              { add rsp, 8 }
        end
        else
          begin EmitB($F2); EmitB($0F); EmitB($10); EmitB($00); end; { movsd xmm0, [rax] }
      end
      else
      begin
        i := TypeSize(dummyTk);
        if i = 1 then
        begin
          if TypeSigned(dummyTk) then
            begin EmitB($48); EmitB($0F); EmitB($BE); EmitB($00); end { movsx rax, byte [rax] }
          else
            begin EmitB($48); EmitB($0F); EmitB($B6); EmitB($00); end;{ movzx rax, byte [rax] }
        end
        else if i = 2 then
        begin
          if TypeSigned(dummyTk) then
            begin EmitB($48); EmitB($0F); EmitB($BF); EmitB($00); end { movsx rax, word [rax] }
          else
            begin EmitB($48); EmitB($0F); EmitB($B7); EmitB($00); end;{ movzx rax, word [rax] }
        end
        else if i = 4 then
        begin
          if TypeSigned(dummyTk) then
            begin EmitB($48); EmitB($63); EmitB($00); end { movsxd rax, dword [rax] }
          else
            begin EmitB($8B); EmitB($00); end;{ mov eax, dword [rax] }
        end
        else
          begin EmitB($48); EmitB($8B); EmitB($00); end; { mov rax, [rax] }
      end;
    end;
    AN_BINOP:
    begin
      op := IntToTokenKind(ASTIVal[node]);
      if (ASTTk[ASTLeft[node]] = Ord(tySingle)) or (ASTTk[ASTLeft[node]] = Ord(tyDouble)) or (ASTTk[ASTLeft[node]] = Ord(tyExtended)) or
         (ASTTk[ASTRight[node]] = Ord(tySingle)) or (ASTTk[ASTRight[node]] = Ord(tyDouble)) or (ASTTk[ASTRight[node]] = Ord(tyExtended)) or
         (op = tkSlash) then
      begin
        { Float path: xmm1 = left, xmm0 = right; integer ops convert first }
        GenAST(ASTLeft[node]);
        if not TypeIsFloat(IntToTypeKind(ASTTk[ASTLeft[node]])) then
          begin EmitB($F2); EmitB($48); EmitB($0F); EmitB($2A); EmitB($C0); end;  { cvtsi2sd xmm0, rax }
        EmitB($48); EmitB($83); EmitB($EC); EmitB($08);              { sub rsp, 8 }
        EmitB($F2); EmitB($0F); EmitB($11); EmitB($04); EmitB($24); { movsd [rsp], xmm0 }
        GenAST(ASTRight[node]);
        if not TypeIsFloat(IntToTypeKind(ASTTk[ASTRight[node]])) then
          begin EmitB($F2); EmitB($48); EmitB($0F); EmitB($2A); EmitB($C0); end;  { cvtsi2sd xmm0, rax }
        EmitB($F2); EmitB($0F); EmitB($10); EmitB($0C); EmitB($24); { movsd xmm1, [rsp] }
        EmitB($48); EmitB($83); EmitB($C4); EmitB($08);              { add rsp, 8 }
        { xmm1 = left, xmm0 = right }
        case op of
          tkPlus:  begin EmitB($F2); EmitB($0F); EmitB($58); EmitB($C1); end; { addsd xmm0, xmm1 }
          tkMinus:
            begin
              EmitB($F2); EmitB($0F); EmitB($5C); EmitB($C8); { subsd xmm1, xmm0 }
              EmitB($F2); EmitB($0F); EmitB($10); EmitB($C1); { movsd xmm0, xmm1 }
            end;
          tkStar:  begin EmitB($F2); EmitB($0F); EmitB($59); EmitB($C1); end; { mulsd xmm0, xmm1 }
          tkSlash:
            begin
              EmitB($F2); EmitB($0F); EmitB($5E); EmitB($C8); { divsd xmm1, xmm0 }
              EmitB($F2); EmitB($0F); EmitB($10); EmitB($C1); { movsd xmm0, xmm1 }
            end;
          tkEq, tkNeq, tkLt, tkLe, tkGt, tkGe:
            begin
              EmitB($66); EmitB($0F); EmitB($2E); EmitB($C8); { ucomisd xmm1, xmm0 }
              case op of
                tkEq:  begin EmitB($0F); EmitB($94); EmitB($C0); end; { sete al }
                tkNeq: begin EmitB($0F); EmitB($95); EmitB($C0); end; { setne al }
                tkLt:  begin EmitB($0F); EmitB($92); EmitB($C0); end; { setb al }
                tkLe:  begin EmitB($0F); EmitB($96); EmitB($C0); end; { setbe al }
                tkGt:  begin EmitB($0F); EmitB($97); EmitB($C0); end; { seta al }
                tkGe:  begin EmitB($0F); EmitB($93); EmitB($C0); end; { setae al }
              end;
              EmitB($48); EmitB($0F); EmitB($B6); EmitB($C0); { movzx rax, al }
            end;
        end;
      end
      else
      begin
      GenAST(ASTLeft[node]);
      EmitB($50); { push rax }
      GenAST(ASTRight[node]);
      EmitB($48); EmitB($89); EmitB($C1); { mov rcx, rax }
      EmitB($58); { pop rax }

      opOvrlIdx := FindOpOverload(Ord(op), ASTTk[ASTLeft[node]], ResolveNodeRec(ASTLeft[node]));
      if opOvrlIdx >= 0 then
      begin
        { rax = lhs, rcx = rhs — set rdi/rsi for System V AMD64 ABI call }
        EmitB($48); EmitB($89); EmitB($C7); { mov rdi, rax }
        EmitB($48); EmitB($89); EmitB($CE); { mov rsi, rcx }
        EmitCallProc(opOvrlIdx);
      end
      else if (ASTTk[node] = Ord(tyString)) and (op = tkPlus) then
      begin
        lhsTk := IntToTypeKind(ASTTk[ASTLeft[node]]);
        rhsTk := IntToTypeKind(ASTTk[ASTRight[node]]);
        
        { 0. mov r10, rcx (save rcx to r10) }
        EmitB($49); EmitB($89); EmitB($CA);
        
        { 1. sub rsp, 272 }
        EmitB($48); EmitB($81); EmitB($EC); EmitI32(272);
        { 2. mov r11, rsp }
        EmitB($49); EmitB($89); EmitB($E3);
        
        { 3. Copy LHS }
        if lhsTk = tyString then
        begin
          EmitB($4C); EmitB($8B); EmitB($00); { mov r8, [rax] }
          EmitB($48); EmitB($8D); EmitB($70); EmitB($08); { lea rsi, [rax+8] }
          EmitB($49); EmitB($8D); EmitB($7B); EmitB($08); { lea rdi, [r11+8] }
          EmitB($4C); EmitB($89); EmitB($C1); { mov rcx, r8 }
          
          { Copy loop }
          EmitB($48); EmitB($85); EmitB($C9); { test rcx, rcx }
          EmitB($74); EmitB(15); { jz done (+15 bytes) }
          EmitB($8A); EmitB($16); { mov dl, [rsi] }
          EmitB($88); EmitB($17); { mov [rdi], dl }
          EmitB($48); EmitB($FF); EmitB($C6); { inc rsi }
          EmitB($48); EmitB($FF); EmitB($C7); { inc rdi }
          EmitB($48); EmitB($FF); EmitB($C9); { dec rcx }
          EmitB($EB); EmitB(Byte(-20)); { jmp loop (-20 bytes) }
        end
        else
        begin
          EmitB($49); EmitB($C7); EmitB($C0); EmitI32(1); { mov r8, 1 }
          EmitB($41); EmitB($88); EmitB($43); EmitB($08); { mov [r11+8], al }
        end;
        
        { 4. Copy RHS }
        if rhsTk = tyString then
        begin
          EmitB($4D); EmitB($8B); EmitB($0A); { mov r9, [r10] }
          EmitB($49); EmitB($8D); EmitB($72); EmitB($08); { lea rsi, [r10+8] }
          EmitB($49); EmitB($8D); EmitB($7B); EmitB($08); { lea rdi, [r11+8] }
          EmitB($4C); EmitB($01); EmitB($C7); { add rdi, r8 }
          EmitB($4C); EmitB($89); EmitB($CA); { mov rdx, r9 }
          
          { Copy loop }
          EmitB($48); EmitB($85); EmitB($D2); { test rdx, rdx }
          EmitB($74); EmitB(15); { jz done (+15 bytes) }
          EmitB($8A); EmitB($06); { mov al, [rsi] }
          EmitB($88); EmitB($07); { mov [rdi], al }
          EmitB($48); EmitB($FF); EmitB($C6); { inc rsi }
          EmitB($48); EmitB($FF); EmitB($C7); { inc rdi }
          EmitB($48); EmitB($FF); EmitB($CA); { dec rdx }
          EmitB($EB); EmitB(Byte(-20)); { jmp loop (-20 bytes) }
        end
        else
        begin
          EmitB($49); EmitB($C7); EmitB($C1); EmitI32(1); { mov r9, 1 }
          EmitB($49); EmitB($8D); EmitB($7B); EmitB($08); { lea rdi, [r11+8] }
          EmitB($4C); EmitB($01); EmitB($C7); { add rdi, r8 }
          EmitB($44); EmitB($88); EmitB($17); { mov [rdi], r10b }
        end;
        
        { 5. Store total length }
        EmitB($4B); EmitB($8D); EmitB($04); EmitB($08); { lea rax, [r8+r9] }
        EmitB($48); EmitB($3D); EmitI32(256); { cmp rax, 256 }
        EmitB($7E); EmitB(7); { jle len_ok }
        EmitB($48); EmitB($C7); EmitB($C0); EmitI32(256); { mov rax, 256 }
        { len_ok: }
        EmitB($49); EmitB($89); EmitB($03); { mov [r11], rax }
        
        { 6. mov rax, r11 }
        EmitB($4C); EmitB($89); EmitB($D8); { mov rax, r11 }
      end
      else if (op = tkIdent) and (GetASTIdentName(node) = 'shr') then
      begin
        EmitB($48); EmitB($D3); EmitB($E8); { shr rax, cl }
      end
      else
      begin
        case op of
          tkStar: begin EmitB($48); EmitB($0F); EmitB($AF); EmitB($C1); end;
          tkDiv:
          begin
            if TypeDivideUnsigned(IntToTypeKind(ASTTk[ASTLeft[node]])) then
              begin EmitB($48); EmitB($31); EmitB($D2); EmitB($48); EmitB($F7); EmitB($F1); end
            else
              begin EmitB($48); EmitB($99); EmitB($48); EmitB($F7); EmitB($F9); end;
          end;
          tkMod:
          begin
            if TypeDivideUnsigned(IntToTypeKind(ASTTk[ASTLeft[node]])) then
              begin EmitB($48); EmitB($31); EmitB($D2); EmitB($48); EmitB($F7); EmitB($F1); end
            else
              begin EmitB($48); EmitB($99); EmitB($48); EmitB($F7); EmitB($F9); end;
            EmitB($48); EmitB($89); EmitB($D0);
          end;
          tkAnd:  begin EmitB($48); EmitB($21); EmitB($C8); end;
          tkPlus:  begin EmitB($48); EmitB($01); EmitB($C8); end;
          tkMinus: begin EmitB($48); EmitB($29); EmitB($C8); end;
          tkOr:    begin EmitB($48); EmitB($09); EmitB($C8); end;
          
          tkEq, tkNeq, tkLt, tkLe, tkGt, tkGe:
          begin
            if (ASTTk[ASTLeft[node]] = Ord(tyString)) and (ASTTk[ASTRight[node]] = Ord(tyChar)) then
            begin
              { String = Char: check len==1 and first byte matches }
              { rax = string struct, rcx = char ordinal }
              EmitB($51);                                                    { push rcx }
              EmitB($48); EmitB($8B); EmitB($08);                           { mov rcx, [rax] }
              EmitB($48); EmitB($83); EmitB($F9); EmitB($01);               { cmp rcx, 1 }
              EmitB($0F); EmitB($85); condJmp := CodeLen; EmitI32(0);       { jne not_equal }
              EmitB($48); EmitB($0F); EmitB($B6); EmitB($48); EmitB($08);   { movzx rcx, byte [rax+8] }
              EmitB($58);                                                    { pop rax }
              EmitB($48); EmitB($39); EmitB($C1);                           { cmp rcx, rax }
              if op = tkEq then begin EmitB($0F); EmitB($94); EmitB($C0); end
              else begin EmitB($0F); EmitB($95); EmitB($C0); end;
              EmitB($48); EmitB($0F); EmitB($B6); EmitB($C0);               { movzx rax, al }
              EmitB($E9); exitJmp := CodeLen; EmitI32(0);                   { jmp end }
              Patch32(condJmp, CodeLen - (condJmp + 4));
              EmitB($59);                                                    { pop rcx }
              if op = tkNeq then MovRaxImm(1) else MovRaxImm(0);
              Patch32(exitJmp, CodeLen - (exitJmp + 4));
            end
            else if (ASTTk[ASTLeft[node]] = Ord(tyChar)) and (ASTTk[ASTRight[node]] = Ord(tyString)) then
            begin
              { Char = String: check len==1 and first byte matches }
              { rax = char ordinal, rcx = string struct }
              EmitB($50);                                                    { push rax }
              EmitB($48); EmitB($8B); EmitB($01);                           { mov rax, [rcx] }
              EmitB($48); EmitB($83); EmitB($F8); EmitB($01);               { cmp rax, 1 }
              EmitB($0F); EmitB($85); condJmp := CodeLen; EmitI32(0);       { jne not_equal }
              EmitB($48); EmitB($0F); EmitB($B6); EmitB($41); EmitB($08);   { movzx rax, byte [rcx+8] }
              EmitB($5A);                                                    { pop rdx }
              EmitB($48); EmitB($39); EmitB($D0);                           { cmp rax, rdx }
              if op = tkEq then begin EmitB($0F); EmitB($94); EmitB($C0); end
              else begin EmitB($0F); EmitB($95); EmitB($C0); end;
              EmitB($48); EmitB($0F); EmitB($B6); EmitB($C0);               { movzx rax, al }
              EmitB($E9); exitJmp := CodeLen; EmitI32(0);                   { jmp end }
              Patch32(condJmp, CodeLen - (condJmp + 4));
              EmitB($5A);                                                    { pop rdx }
              if op = tkNeq then MovRaxImm(1) else MovRaxImm(0);
              Patch32(exitJmp, CodeLen - (exitJmp + 4));
            end
            else if (ASTTk[ASTLeft[node]] = Ord(tyString)) or (ASTTk[ASTRight[node]] = Ord(tyString)) then
            begin
              EmitStrCmpReg(op = tkEq);
            end
            else
            begin
              EmitB($48); EmitB($3B); EmitB($C1); { cmp rax, rcx }
              if TypeCompareUnsigned(IntToTypeKind(ASTTk[ASTLeft[node]]),
                                     IntToTypeKind(ASTTk[ASTRight[node]])) then
                case op of
                  tkEq:  begin EmitB($0F); EmitB($94); EmitB($C0); end;
                  tkNeq: begin EmitB($0F); EmitB($95); EmitB($C0); end;
                  tkLt:  begin EmitB($0F); EmitB($92); EmitB($C0); end;
                  tkLe:  begin EmitB($0F); EmitB($96); EmitB($C0); end;
                  tkGt:  begin EmitB($0F); EmitB($97); EmitB($C0); end;
                  tkGe:  begin EmitB($0F); EmitB($93); EmitB($C0); end;
                end
              else
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
      end;  { end integer path else }
    end;
    AN_NEG:
    begin
      GenAST(ASTLeft[node]);
      if TypeIsFloat(IntToTypeKind(ASTTk[ASTLeft[node]])) then
      begin
        { flip sign bit: movq rax,xmm0 → btc rax,63 → movq xmm0,rax }
        EmitB($66); EmitB($48); EmitB($0F); EmitB($7E); EmitB($C0); { movq rax, xmm0 }
        EmitB($48); EmitB($0F); EmitB($BA); EmitB($F8); EmitB($3F); { btc rax, 63 }
        EmitB($66); EmitB($48); EmitB($0F); EmitB($6E); EmitB($C0); { movq xmm0, rax }
      end
      else
        EmitB($48); EmitB($F7); EmitB($D8); { neg rax }
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
            if TypeIsFloat(Procs[pi].Params[pathIdx].TypeKind) then
              begin EmitB($66); EmitB($48); EmitB($0F); EmitB($7E); EmitB($C0); end; { movq rax, xmm0 }
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
      else if pi = -Ord(tkGetMem) then
      begin
        { Class instantiation }
        GenSpecialCall(Ord(tkGetMem), ASTLeft[node]);
        
        { Put instance pointer in rdi }
        EmitB($48); EmitB($89); EmitB($C7); { mov rdi, rax }
        
        { Initialize VMT pointer at offset 0 }
        idx := ASTRight[node];
        EmitB($48); EmitB($B8); EmitDataRef(UClsVMTOffset[idx - REC_UCLASS_BASE]); { mov rax, VMT_addr }
        EmitB($48); EmitB($89); EmitB($07); { mov [rdi], rax }
        
        { Find constructor 'Create' of this class }
        slot := FindUMeth(idx - REC_UCLASS_BASE, 'create');
        if slot >= 0 then
        begin
          pi := UMthProc_[slot];
          
          { Push Self first }
          EmitB($57); { push rdi }
          
          { Push explicit constructor arguments }
          initNode := ASTLeft[node];
          pathIdx := 1;
          argNode := ASTRight[initNode];
          while argNode <> -1 do
          begin
            if Procs[pi].Params[pathIdx].IsRef then
              GenLValueAddress(ASTLeft[argNode], dummyTk, dummyRec, False)
            else
              GenAST(ASTLeft[argNode]);
            EmitB($50);
            Inc(pathIdx);
            argNode := ASTRight[argNode];
          end;
          
          { Pop args into SysV ABI registers }
          for i := Procs[pi].ParamCount-1 downto 0 do
            case i of
              0: EmitB($5F);
              1: EmitB($5E);
              2: EmitB($5A);
              3: EmitB($59);
              4: begin EmitB($41); EmitB($58); end;
              5: begin EmitB($41); EmitB($59); end;
            end;
            
          { Save Self on stack across the call }
          EmitB($57); { push rdi }
          
          EmitCallProc(pi);
          
          { Restore Self into rax as the result of the constructor call }
          EmitB($58); { pop rax }
        end
        else
        begin
          { No constructor defined, just return the instance pointer in rax }
          EmitB($48); EmitB($89); EmitB($F8); { mov rax, rdi }
        end;
      end
      else
      begin
        GenSpecialCall(-pi, ASTLeft[node]);
      end;
    end;
    AN_VIRTUAL_CALL:
    begin
      pi := ASTIVal[node];
      slot := ASTRight[node];
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
          if TypeIsFloat(Procs[pi].Params[pathIdx].TypeKind) then
            begin EmitB($66); EmitB($48); EmitB($0F); EmitB($7E); EmitB($C0); end; { movq rax, xmm0 }
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
      { Virtual Method Table Dispatch: }
      { mov rax, [rdi] }
      EmitB($48); EmitB($8B); EmitB($07);
      { call [rax + slot * 8] }
      EmitB($FF); EmitB($90); EmitI32(slot * 8);
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
          if (ASTKind[rhsNode] = AN_CALL) or (ASTTk[rhsNode] = Ord(tyString)) then
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
            if (ASTKind[rhsNode] = AN_CALL) or (ASTTk[rhsNode] = Ord(tyString)) then
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
          if TypeIsFloat(lhsTk) then
          begin
            if lhsTk = tySingle then
              begin EmitB($F3); EmitB($0F); EmitB($11); EmitB($01); end  { movss [rcx], xmm0 }
            else if lhsTk = tyExtended then
            begin
              EmitB($48); EmitB($83); EmitB($EC); EmitB($08);              { sub rsp, 8 }
              EmitB($F2); EmitB($0F); EmitB($11); EmitB($04); EmitB($24); { movsd [rsp], xmm0 }
              EmitB($DD); EmitB($04); EmitB($24);                          { fldl [rsp] }
              EmitB($48); EmitB($83); EmitB($C4); EmitB($08);              { add rsp, 8 }
              EmitB($DF); EmitB($39);                                       { fstpt [rcx] }
            end
            else
              begin EmitB($F2); EmitB($0F); EmitB($11); EmitB($01); end; { movsd [rcx], xmm0 }
          end
          else
          begin
            i := TypeSize(lhsTk);
            if i = 1 then
              begin EmitB($88); EmitB($01); end
            else if i = 2 then
              begin EmitB($66); EmitB($89); EmitB($01); end
            else if i = 4 then
              begin EmitB($89); EmitB($01); end
            else
              begin EmitB($48); EmitB($89); EmitB($01); end;
          end;
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
      breakBase := LoopBreakFixCount;
      continueBase := LoopContinueFixCount;
      if LoopNestDepth >= MAX_LOOP_FIXUPS then Error('loop nesting overflow');
      LoopExceptionDepth[LoopNestDepth] := ExceptionCodegenDepth;
      Inc(LoopNestDepth);
      loopTop := CodeLen;
      GenAST(ASTLeft[node]);
      EmitB($48); EmitB($85); EmitB($C0);
      EmitB($0F); EmitB($84); condJmp := CodeLen; EmitI32(0);
      
      GenAST(ASTRight[node]);
      Dec(LoopNestDepth);
      for i := continueBase to LoopContinueFixCount - 1 do
        Patch32(LoopContinueFixPos[i], loopTop - (LoopContinueFixPos[i] + 4));
      LoopContinueFixCount := continueBase;
      EmitB($E9); EmitI32(loopTop - (CodeLen + 4));
      Patch32(condJmp, CodeLen - (condJmp + 4));
      for i := breakBase to LoopBreakFixCount - 1 do
        Patch32(LoopBreakFixPos[i], CodeLen - (LoopBreakFixPos[i] + 4));
      LoopBreakFixCount := breakBase;
    end;
    AN_FOR:
    begin
      breakBase := LoopBreakFixCount;
      continueBase := LoopContinueFixCount;
      if LoopNestDepth >= MAX_LOOP_FIXUPS then Error('loop nesting overflow');
      LoopExceptionDepth[LoopNestDepth] := ExceptionCodegenDepth;
      Inc(LoopNestDepth);
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
      EmitLoadVar(limitIdx);
      EmitB($48); EmitB($89); EmitB($C1); { mov rcx, rax }
      EmitLoadVar(idx);
      EmitB($48); EmitB($39); EmitB($C8); { cmp rax, rcx }
      
      down := ASTIVal[isDownNode] = 1;
      EmitB($0F);
      if down then EmitB($8C) else EmitB($8F);
      exitJmp := CodeLen; EmitI32(0);
      
      GenAST(bodyNode);
      
      continueTarget := CodeLen;
      Dec(LoopNestDepth);
      for i := continueBase to LoopContinueFixCount - 1 do
        Patch32(LoopContinueFixPos[i], continueTarget - (LoopContinueFixPos[i] + 4));
      LoopContinueFixCount := continueBase;
      EmitLoadVar(idx);
      if down then
        begin EmitB($48); EmitB($FF); EmitB($C8); end
      else
        begin EmitB($48); EmitB($FF); EmitB($C0); end;
      EmitStoreVar(idx);
      
      EmitB($E9); EmitI32(loopTop - (CodeLen + 4));
      Patch32(exitJmp, CodeLen - (exitJmp + 4));
      for i := breakBase to LoopBreakFixCount - 1 do
        Patch32(LoopBreakFixPos[i], CodeLen - (LoopBreakFixPos[i] + 4));
      LoopBreakFixCount := breakBase;
    end;
    AN_REPEAT:
    begin
      breakBase := LoopBreakFixCount;
      continueBase := LoopContinueFixCount;
      if LoopNestDepth >= MAX_LOOP_FIXUPS then Error('loop nesting overflow');
      LoopExceptionDepth[LoopNestDepth] := ExceptionCodegenDepth;
      Inc(LoopNestDepth);
      loopTop := CodeLen;
      GenAST(ASTLeft[node]);
      continueTarget := CodeLen;
      Dec(LoopNestDepth);
      for i := continueBase to LoopContinueFixCount - 1 do
        Patch32(LoopContinueFixPos[i], continueTarget - (LoopContinueFixPos[i] + 4));
      LoopContinueFixCount := continueBase;
      GenAST(ASTRight[node]);
      EmitB($48); EmitB($85); EmitB($C0);
      EmitB($0F); EmitB($84); EmitI32(loopTop - (CodeLen + 4));
      for i := breakBase to LoopBreakFixCount - 1 do
        Patch32(LoopBreakFixPos[i], CodeLen - (LoopBreakFixPos[i] + 4));
      LoopBreakFixCount := breakBase;
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
        wid := ASTIVal[argNode];  { 0 = no width }
        if ASTKind[exprNode] = AN_STR_LIT then
        begin
          si := InternStr(GetASTStrVal(exprNode));
          if wid > 0 then
          begin
            { Pad string literal: compute padding = max(0, wid - len) }
            if wid > Strs[si].Len then
            begin
              EnsureSpaces;
              EmitB($48); EmitB($BE); EmitDataRef(SpacesOffset);
              MovRdxImm(wid - Strs[si].Len);
              MovRaxImm(SYS_WRITE); MovRdiImm(STDOUT); EmitSyscall;
            end;
          end;
          if Strs[si].Len > 0 then EmitwriteSyscall(Strs[si].Offset + 8, Strs[si].Len);
        end
        else if ASTKind[exprNode] = AN_IDENT then
        begin
          vidx := ASTIVal[exprNode];
          if (vidx >= 0) and (Syms[vidx].TypeKind = tyString) and not Syms[vidx].IsArray then
          begin
            if wid > 0 then
            begin
              { Runtime string width: load len, compute padding = max(0, wid - len) }
              EnsureSpaces;
              EmitLoadStrLen(vidx);        { rcx = len }
              MovRaxImm(wid);
              EmitB($48); EmitB($29); EmitB($C8);  { sub rax, rcx }
              EmitB($7E); EmitB(35);               { jle .skip_pad (35 bytes) }
              EmitB($48); EmitB($BE); EmitDataRef(SpacesOffset);
              EmitB($48); EmitB($89); EmitB($C2);  { mov rdx, rax }
              MovRaxImm(SYS_WRITE); MovRdiImm(STDOUT); EmitSyscall;
              { .skip_pad: }
            end;
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
            if TypeIsOrdinal(Syms[vidx].TypeKind) and
               (not TypeSigned(Syms[vidx].TypeKind)) and
               (TypeSize(Syms[vidx].TypeKind) = 8) then
            begin
              if wid > 0 then EmitwriteUIntW(wid) else EmitwriteUInt;
            end
            else
            begin
              if wid > 0 then EmitwriteIntW(wid) else EmitwriteInt;
            end;
          end;
        end
        else
        begin
          GenAST(exprNode);
          if ASTTk[exprNode] = Ord(tyChar) then
            EmitwriteChar
          else if ASTTk[exprNode] = Ord(tyString) then
          begin
            if wid > 0 then
            begin
              EnsureSpaces;
              EmitB($48); EmitB($89); EmitB($C1);  { mov rcx, rax }  { save ptr }
              EmitB($48); EmitB($8B); EmitB($00);  { mov rax, [rax] } { rax = len }
              EmitB($48); EmitB($87); EmitB($C8);  { xchg rax, rcx }  { rax=ptr, rcx=len }
              { compute padding }
              EmitB($50);                           { push rax (ptr) }
              EmitB($51);                           { push rcx (len) }
              MovRaxImm(wid);
              EmitB($48); EmitB($29); EmitB($C8);  { sub rax, rcx }
              EmitB($7E); EmitB(35);               { jle .skip_pad (35 bytes) }
              EmitB($48); EmitB($BE); EmitDataRef(SpacesOffset);
              EmitB($48); EmitB($89); EmitB($C2);  { mov rdx, rax }
              MovRaxImm(SYS_WRITE); MovRdiImm(STDOUT); EmitSyscall;
              { .skip_pad: }
              EmitB($59);                           { pop rcx → rdx via next }
              EmitB($58);                           { pop rax (ptr) }
              EmitB($48); EmitB($89); EmitB($C6);  { mov rsi, rax }
              EmitB($48); EmitB($89); EmitB($CA);  { mov rdx, rcx }
              EmitB($48); EmitB($83); EmitB($C6); EmitB($08); { add rsi, 8 }
              MovRaxImm(SYS_WRITE); MovRdiImm(STDOUT); EmitSyscall;
            end
            else
            begin
              EmitB($48); EmitB($89); EmitB($C6); { mov rsi, rax }
              EmitB($48); EmitB($8B); EmitB($10); { mov rdx, [rax] }
              EmitB($48); EmitB($83); EmitB($C6); EmitB($08); { add rsi, 8 }
              MovRaxImm(SYS_WRITE); MovRdiImm(STDOUT); EmitSyscall;
            end;
          end
          else if TypeIsOrdinal(IntToTypeKind(ASTTk[exprNode])) and
                  (not TypeSigned(IntToTypeKind(ASTTk[exprNode]))) and
                  (TypeSize(IntToTypeKind(ASTTk[exprNode])) = 8) then
          begin
            if wid > 0 then EmitwriteUIntW(wid) else EmitwriteUInt;
          end
          else
          begin
            if wid > 0 then EmitwriteIntW(wid) else EmitwriteInt;
          end;
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
        if (ASTKind[node] = AN_EXIT) and (CurProc >= 0) and
           (Procs[CurProc].RetSymIdx >= 0) then
          EmitStoreVar(Procs[CurProc].RetSymIdx);
        if ASTKind[node] = AN_EXIT then
          EmitCleanupToDepth(0);
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
            EmitProcEpilog(Procs[CurProc].RetSymIdx);
          end
          else EmitExit(0);
        end;
      end
      else
      begin
        if ASTKind[node] = AN_EXIT then
          EmitCleanupToDepth(0);
        if ASTKind[node] = AN_HALT then
          EmitExit(0)
        else
        begin
          if CurProc >= 0 then EmitProcEpilog(Procs[CurProc].RetSymIdx)
          else EmitExit(0);
        end;
      end;
    end;
    AN_BREAK:
    begin
      if LoopNestDepth = 0 then Error('break outside loop');
      if LoopBreakFixCount >= MAX_LOOP_FIXUPS then Error('too many break statements');
      EmitCleanupToDepth(LoopExceptionDepth[LoopNestDepth - 1]);
      EmitB($E9);
      LoopBreakFixPos[LoopBreakFixCount] := CodeLen;
      Inc(LoopBreakFixCount);
      EmitI32(0);
    end;
    AN_CONTINUE:
    begin
      if LoopNestDepth = 0 then Error('continue outside loop');
      if LoopContinueFixCount >= MAX_LOOP_FIXUPS then Error('too many continue statements');
      EmitCleanupToDepth(LoopExceptionDepth[LoopNestDepth - 1]);
      EmitB($E9);
      LoopContinueFixPos[LoopContinueFixCount] := CodeLen;
      Inc(LoopContinueFixCount);
      EmitI32(0);
    end;
    AN_RAISE:
    begin
      if ASTLeft[node] <> -1 then
      begin
        GenAST(ASTLeft[node]);
        EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_OBJ);
        dummyRec := ResolveNodeRec(ASTLeft[node]);
        if dummyRec < REC_UCLASS_BASE then dummyRec := REC_NONE;
        MovRaxImm(dummyRec);
        EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_CLS);
      end;
      EmitCodeCall(ExcRaiseAddr);
    end;
    AN_TRY_EXCEPT:
    begin
      EmitB($48); EmitB($83); EmitB($EC); EmitB(EXC_FRAME_SIZE); { sub rsp, frame }
      EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_TOP);
      EmitB($48); EmitB($89); EmitB($04); EmitB($24); { frame.prev := old top }
      EmitB($48); EmitB($89); EmitB($E0);             { mov rax, rsp }
      EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_TOP);
      EmitB($48); EmitB($8D); EmitB($7C); EmitB($24); EmitB(EXC_JMP_OFFSET);
      EmitCodeCall(ExcSetJmpAddr);
      EmitB($85); EmitB($C0);                         { test eax, eax }
      EmitB($0F); EmitB($85); thenJmp := CodeLen; EmitI32(0); { jne handler }

      ExceptionFinallyBody[ExceptionCodegenDepth] := -1;
      Inc(ExceptionCodegenDepth);
      GenAST(ASTLeft[node]);
      Dec(ExceptionCodegenDepth);
      EmitB($48); EmitB($8B); EmitB($04); EmitB($24);
      EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_TOP);
      EmitB($48); EmitB($83); EmitB($C4); EmitB(EXC_FRAME_SIZE);
      EmitB($E9); elseJmp := CodeLen; EmitI32(0);

      Patch32(thenJmp, CodeLen - (thenJmp + 4));
      EmitB($48); EmitB($8B); EmitB($04); EmitB($24);
      EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_TOP);
      EmitB($48); EmitB($83); EmitB($C4); EmitB(EXC_FRAME_SIZE);
      handlerNode := ASTRight[node];
      jmpCount := 0;
      while handlerNode <> -1 do
      begin
        handlerNextJmp := -1;
        if ASTIVal[handlerNode] >= 0 then
        begin
          EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_CLS);
          EmitB($48); EmitB($3D); EmitI32(ASTIVal[handlerNode]);
          EmitB($0F); EmitB($85); handlerNextJmp := CodeLen; EmitI32(0);
        end;
        if ASTSOffset[handlerNode] >= 0 then
        begin
          EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_OBJ);
          EmitStoreVar(ASTSOffset[handlerNode]);
        end;
        GenAST(ASTLeft[handlerNode]);
        MovRaxImm(0);
        EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_OBJ);
        EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_CLS);
        if jmpCount >= 256 then Error('too many exception handlers');
        EmitB($E9); jmpPositions[jmpCount] := CodeLen; Inc(jmpCount); EmitI32(0);
        if handlerNextJmp >= 0 then
          Patch32(handlerNextJmp, CodeLen - (handlerNextJmp + 4));
        handlerNode := ASTRight[handlerNode];
      end;
      EmitCodeCall(ExcRaiseAddr); { no typed handler matched }
      for i := 0 to jmpCount - 1 do
        Patch32(jmpPositions[i], CodeLen - (jmpPositions[i] + 4));
      Patch32(elseJmp, CodeLen - (elseJmp + 4));
    end;
    AN_TRY_FINALLY:
    begin
      EmitB($48); EmitB($83); EmitB($EC); EmitB(EXC_FRAME_SIZE);
      EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_TOP);
      EmitB($48); EmitB($89); EmitB($04); EmitB($24);
      EmitB($48); EmitB($89); EmitB($E0);
      EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_TOP);
      EmitB($48); EmitB($8D); EmitB($7C); EmitB($24); EmitB(EXC_JMP_OFFSET);
      EmitCodeCall(ExcSetJmpAddr);
      EmitB($85); EmitB($C0);
      EmitB($0F); EmitB($85); thenJmp := CodeLen; EmitI32(0);

      ExceptionFinallyBody[ExceptionCodegenDepth] := ASTRight[node];
      Inc(ExceptionCodegenDepth);
      GenAST(ASTLeft[node]);
      Dec(ExceptionCodegenDepth);
      EmitLeaveExceptionFrames(1);
      GenAST(ASTRight[node]);
      EmitB($E9); elseJmp := CodeLen; EmitI32(0);

      Patch32(thenJmp, CodeLen - (thenJmp + 4));
      EmitLeaveExceptionFrames(1);
      GenAST(ASTRight[node]);
      EmitCodeCall(ExcRaiseAddr);

      Patch32(elseJmp, CodeLen - (elseJmp + 4));
    end;
  end;
end;

procedure CompileAST(node: Integer);
begin
  GenAST(node);
end;
