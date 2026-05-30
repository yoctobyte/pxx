function Shl8_(shift: Integer): Integer;
begin
  Shl8_ := 0;
  if shift = 0 then Shl8_ := 1
  else if shift = 1 then Shl8_ := 2
  else if shift = 2 then Shl8_ := 4
  else if shift = 3 then Shl8_ := 8
  else if shift = 4 then Shl8_ := 16
  else if shift = 5 then Shl8_ := 32
  else if shift = 6 then Shl8_ := 64
  else if shift = 7 then Shl8_ := 128;
end;

procedure IRReset;
begin
  IRCount := 0;
  IRLabelCount := 0;
  IRLoopStackDepth := 0;
end;

function IRAppend(kind, a, b, c: Integer; ival: Int64; tk: Integer): Integer;
begin
  if IRCount >= MAX_IR then Error('IR overflow');
  IRKind[IRCount] := kind;
  IRA[IRCount] := a;
  IRB[IRCount] := b;
  IRC[IRCount] := c;
  IRIVal[IRCount] := ival;
  IRTk[IRCount] := tk;
  Result := IRCount;
  Inc(IRCount);
end;

function IROpName(kind: Integer): AnsiString;
begin
  case kind of
    IR_NOP: Result := 'nop';
    IR_CONST_INT: Result := 'const_int';
    IR_CONST_STR: Result := 'const_str';
    IR_LOAD_SYM: Result := 'load_sym';
    IR_STORE_SYM: Result := 'store_sym';
    IR_BINOP: Result := 'binop';
    IR_CALL: Result := 'call';
    IR_WRITE: Result := 'write';
    IR_WRITELN: Result := 'writeln';
    IR_READLINE: Result := 'readline';
    IR_READ_VAR: Result := 'read_var';
    IR_COPY_REC: Result := 'copy_rec';
    IR_BLOCK: Result := 'block';
    IR_UNSUPPORTED: Result := 'unsupported';
    IR_IF: Result := 'if';
    IR_LABEL: Result := 'label';
    IR_JUMP: Result := 'jump';
    IR_JUMP_IF_FALSE: Result := 'jump_if_false';
    IR_NEG: Result := 'neg';
    IR_NOT: Result := 'not';
    IR_LEA: Result := 'lea';
    IR_INDEX: Result := 'index';
    IR_FIELD: Result := 'field';
    IR_LOAD_MEM: Result := 'load_mem';
    IR_STORE_MEM: Result := 'store_mem';
    IR_ARG: Result := 'arg';
    IR_EXC_ENTER: Result := 'exc_enter';
    IR_EXC_LEAVE: Result := 'exc_leave';
    IR_RAISE: Result := 'raise';
    IR_EXC_MATCH: Result := 'exc_match';
    IR_EXC_STORE: Result := 'exc_store';
    IR_EXC_CLEAR: Result := 'exc_clear';
    IR_TERMINATE: Result := 'terminate';
    IR_VIRTUAL_CALL: Result := 'virtual_call';
    IR_ASM: Result := 'asm';
    IR_RTTI_REG: Result := 'rtti_reg';
    IR_RESOURCES: Result := 'resources';
    IR_SET_LIT: Result := 'set_lit';
  else
    Result := 'unknown';
  end;
end;

function IRNodeOK(idx: Integer): Boolean;
begin
  Result := (idx >= 0) and (idx < IRCount);
end;

function IRNewLabel: Integer;
begin
  Result := IRLabelCount;
  Inc(IRLabelCount);
end;

function IRLabelExists(labelId: Integer): Boolean;
var i: Integer;
begin
  Result := False;
  for i := 0 to IRCount - 1 do
    if (IRKind[i] = IR_LABEL) and (IRIVal[i] = labelId) then
      Result := True;
end;

procedure IRRequireNode(idx: Integer; const context: AnsiString);
begin
  if not IRNodeOK(idx) then
    Error('invalid IR node reference in ' + context);
end;

procedure IRRequireOptionalNode(idx: Integer; const context: AnsiString);
begin
  if (idx <> -1) and not IRNodeOK(idx) then
    Error('invalid optional IR node reference in ' + context);
end;

procedure IRVerify;
var i, lblId, op: Integer;
    seenLabel: array[0..MAX_IR-1] of Boolean;
begin
  for i := 0 to MAX_IR - 1 do
    seenLabel[i] := False;

  { Pass 1: populate seen labels and verify uniqueness }
  for i := 0 to IRCount - 1 do
  begin
    if (IRTk[i] < 0) or (IRTk[i] > Ord(tySet)) then
      Error('invalid type kind in IR node');

    if IRKind[i] = IR_LABEL then
    begin
      lblId := Integer(IRIVal[i]);
      if (lblId < 0) or (lblId >= MAX_IR) then
        Error('IR label ID out of bounds');
      if seenLabel[lblId] then
        Error('duplicate IR label definition');
      seenLabel[lblId] := True;
    end;
  end;

  { Pass 2: check all instructions and operand invariants }
  for i := 0 to IRCount - 1 do
  begin
    case IRKind[i] of
      IR_CONST_INT, IR_CONST_STR, IR_NOP, IR_LABEL, IR_ASM, IR_RTTI_REG, IR_SET_LIT, IR_RESOURCES:
        begin end;

      IR_LOAD_SYM:
        if (IRA[i] < 0) or (IRA[i] >= SymCount) then
          Error('invalid IR symbol reference in load_sym');

      IR_STORE_SYM:
      begin
        if (IRA[i] < 0) or (IRA[i] >= SymCount) then
          Error('invalid IR symbol reference in store_sym');
        IRRequireNode(IRB[i], 'store_sym');
      end;

      IR_BINOP:
      begin
        IRRequireNode(IRA[i], 'binop left');
        IRRequireNode(IRB[i], 'binop right');
        op := IRC[i];
        if (op < 0) or (op > Ord(tkIn)) then
          Error('invalid operator token kind in binop');
      end;

      IR_CALL:
      begin
        if (IRA[i] >= ProcCount) then
          Error('invalid IR proc reference in call');
        IRRequireOptionalNode(IRB[i], 'call first arg');
        { IRC = classIdx (record id for constructor/method dispatch), NOT a
          node — do not validate it as one. Args chain via IRB[argNode]. }
      end;

      IR_WRITE:
        IRRequireNode(IRA[i], 'write');

      IR_READLINE:
        begin end;

      IR_READ_VAR:
        IRRequireNode(IRA[i], 'read_var');

      IR_COPY_REC:
      begin
        IRRequireNode(IRA[i], 'copy_rec dest');
        IRRequireNode(IRB[i], 'copy_rec src');
      end;

      IR_WRITELN, IR_BLOCK:
      begin
        IRRequireOptionalNode(IRA[i], 'block first');
        IRRequireOptionalNode(IRB[i], 'block last');
      end;

      IR_IF:
      begin
        IRRequireNode(IRA[i], 'if condition');
        IRRequireNode(IRB[i], 'if then');
        IRRequireOptionalNode(IRC[i], 'if else');
      end;

      IR_JUMP:
      begin
        lblId := IRA[i];
        if (lblId < 0) or (lblId >= MAX_IR) then
          Error('invalid IR jump target out of bounds');
        if not seenLabel[lblId] then
          Error('invalid IR jump target (label not defined)');
      end;

      IR_JUMP_IF_FALSE:
      begin
        lblId := IRA[i];
        if (lblId < 0) or (lblId >= MAX_IR) then
          Error('invalid IR conditional jump target out of bounds');
        if not seenLabel[lblId] then
          Error('invalid IR conditional jump target (label not defined)');
        IRRequireNode(IRB[i], 'jump condition');
      end;

      IR_NEG, IR_NOT:
        IRRequireNode(IRA[i], 'unary operand');

      IR_LEA:
        if (IRA[i] < 0) or (IRA[i] >= SymCount) then
          Error('invalid symbol in lea');

      IR_INDEX:
      begin
        IRRequireNode(IRA[i], 'index base');
        IRRequireNode(IRB[i], 'index offset');
      end;

      IR_FIELD:
        IRRequireNode(IRA[i], 'field base');

      IR_LOAD_MEM:
        IRRequireNode(IRA[i], 'load_mem address');

      IR_STORE_MEM:
      begin
        IRRequireNode(IRA[i], 'store_mem address');
        IRRequireNode(IRB[i], 'store_mem value');
      end;

      IR_ARG:
      begin
        IRRequireNode(IRA[i], 'arg value');
        IRRequireOptionalNode(IRB[i], 'next arg');
      end;

      IR_EXC_ENTER, IR_EXC_MATCH:
      begin
        lblId := IRA[i];
        if (lblId < 0) or (lblId >= MAX_IR) then
          Error('invalid IR exception jump target out of bounds');
        if not seenLabel[lblId] then
          Error('invalid IR exception jump target (label not defined)');
      end;

      IR_EXC_LEAVE, IR_EXC_CLEAR:
        begin end;

      IR_RAISE:
        IRRequireOptionalNode(IRA[i], 'raise value');

      IR_EXC_STORE:
        if (IRA[i] < 0) or (IRA[i] >= SymCount) then
          Error('invalid symbol in exception store');

      IR_TERMINATE:
        IRRequireOptionalNode(IRA[i], 'terminate value');

      IR_VIRTUAL_CALL:
      begin
        IRRequireOptionalNode(IRA[i], 'virtual_call first arg');
        IRRequireOptionalNode(IRB[i], 'virtual_call last arg');
        if (IRC[i] < 0) or (IRC[i] >= ProcCount) then
          Error('invalid proc index in virtual_call');
      end;

      IR_PROCADDR:
        if (IRA[i] < 0) or (IRA[i] >= ProcCount) then
          Error('invalid proc index in procaddr');

      IR_UNSUPPORTED:
        begin end;

    else
      Error('unknown IR opcode');
    end;
  end;
end;

function IRLowerAST(node: Integer): Integer; forward;

procedure IRLowerCleanupToDepth(targetDepth: Integer);
var current, bodyNode, savedDepth: Integer;
begin
  current := ExceptionCodegenDepth;
  while current > targetDepth do
  begin
    IRAppend(IR_EXC_LEAVE, 1, -1, -1, 0, 0);
    bodyNode := ExceptionFinallyBody[current - 1];
    if bodyNode <> -1 then
    begin
      savedDepth := ExceptionCodegenDepth;
      ExceptionCodegenDepth := current - 1;
      IRLowerAST(bodyNode);
      ExceptionCodegenDepth := savedDepth;
    end;
    Dec(current);
  end;
end;

procedure IRMarkStatementNode(irNode: Integer);
begin
  if (irNode >= 0) and (irNode < IRCount) and (IRKind[irNode] = IR_CALL) then
    IRIVal[irNode] := 1;
end;

function IRLowerAddress(node: Integer): Integer;
var baseNode, baseAddr, indexNode, lo, elemSize: Integer;
    fieldName: AnsiString;
    isArr: Boolean;
    tk: TTypeKind;
    recName, aliasIdx: Integer;
begin
  if ASTKind[node] = AN_IDENT then
  begin
    Result := IRAppend(IR_LEA, ASTIVal[node], -1, -1, 0, Ord(tyPointer));
  end
  else if ASTKind[node] = AN_INDEX then
  begin
    baseNode := ASTLeft[node];
    { Pointer indexing p[i]: base address is the pointer's VALUE (not &p), and
      the stride is the pointed-at element size. Arrays fall through below. }
    if (ASTKind[baseNode] = AN_IDENT) and
       (Syms[ASTIVal[baseNode]].TypeKind = tyPointer) and
       (not Syms[ASTIVal[baseNode]].IsArray) then
    begin
      indexNode := IRLowerAST(ASTRight[node]);
      tk := Syms[ASTIVal[baseNode]].PtrElemTk;
      if tk = tyRecord then
        elemSize := RecSize(Syms[ASTIVal[baseNode]].PtrElemRec)
      else
        elemSize := TypeSize(tk);
      baseAddr := IRLowerAST(baseNode);
      Result := IRAppend(IR_INDEX, baseAddr, indexNode, 0, elemSize, Ord(tk));
      Exit;
    end;
    { Pointer-typed class field indexing FField[i]: base is the field's VALUE
      (the pointer), stride is the pointed-at element size. Mirrors the AN_IDENT
      pointer path above for an AN_FIELD base. }
    if ASTKind[baseNode] = AN_FIELD then
    begin
      recName := ResolveNodeRec(ASTLeft[baseNode]);
      fieldName := GetASTIdentName(baseNode);
      if (RecFieldType(recName, fieldName) = tyPointer) and
         (not RecFieldIsArray(recName, fieldName)) then
      begin
        indexNode := IRLowerAST(ASTRight[node]);
        tk := RecFieldPtrElemTk(recName, fieldName);
        if tk = tyRecord then
          elemSize := RecSize(RecFieldPtrElemRec(recName, fieldName))
        else
          elemSize := TypeSize(tk);
        baseAddr := IRLowerAST(baseNode);   { field value = the pointer }
        Result := IRAppend(IR_INDEX, baseAddr, indexNode, 0, elemSize, Ord(tk));
        Exit;
      end;
    end;
    { Typed-pointer-cast indexing PType(expr)[i]: base is the cast's pointer
      VALUE, stride is the cast's pointed-at element size (from the alias). }
    if ASTKind[baseNode] = AN_PTR_CAST then
    begin
      indexNode := IRLowerAST(ASTRight[node]);
      aliasIdx := ASTIVal[baseNode];
      tk := IntToTypeKind(AliasElemTk[aliasIdx]);
      if tk = tyRecord then
        elemSize := RecSize(AliasElemRec[aliasIdx])
      else
        elemSize := TypeSize(tk);
      baseAddr := IRLowerAST(baseNode);
      Result := IRAppend(IR_INDEX, baseAddr, indexNode, 0, elemSize, Ord(tk));
      Exit;
    end;
    baseAddr := IRLowerAddress(baseNode);
    indexNode := IRLowerAST(ASTRight[node]);

    isArr := IsNodeArray(baseNode);
    if ASTKind[baseNode] = AN_IDENT then
    begin
      tk := Syms[ASTIVal[baseNode]].TypeKind;
      recName := Syms[ASTIVal[baseNode]].RecName;
    end
    else if ASTKind[baseNode] = AN_FIELD then
    begin
      recName := ResolveNodeRec(baseNode);
      tk := RecFieldType(ResolveNodeRec(ASTLeft[baseNode]), GetASTIdentName(baseNode));
    end
    else
    begin
      tk := tyInteger;
      recName := REC_NONE;
    end;

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
    
    lo := 0;
    if (tk = tyString) and not isArr then
    begin
      lo := -7;
      elemSize := 1;
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
        elemSize := RecSize(recName)
      else
        elemSize := TypeSize(tk);

      if ASTKind[baseNode] = AN_IDENT then
      begin
        if Syms[ASTIVal[baseNode]].RecName <> REC_TPARAM then
          lo := Syms[ASTIVal[baseNode]].ConstVal;
      end;
    end;
    
    Result := IRAppend(IR_INDEX, baseAddr, indexNode, lo, elemSize, ASTTk[node]);
  end
  else if ASTKind[node] = AN_FIELD then
  begin
    baseNode := ASTLeft[node];
    if (ASTKind[baseNode] = AN_IDENT) and
       (Syms[ASTIVal[baseNode]].TypeKind = tyClass) then
      baseAddr := IRAppend(IR_LOAD_SYM, ASTIVal[baseNode], -1, -1, 0, Ord(tyPointer))
    else
      baseAddr := IRLowerAddress(baseNode);
    
    recName := ResolveNodeRec(baseNode);
    fieldName := GetASTIdentName(node);
    Result := IRAppend(IR_FIELD, baseAddr, -1, -1, RecFieldOffset(recName, fieldName), ASTTk[node]);
  end
  else if ASTKind[node] = AN_DEREF then
  begin
    Result := IRLowerAST(ASTLeft[node]);
  end
  else if ASTKind[node] = AN_PTR_CAST then
  begin
    { The cast result is the pointer value itself; use it as the address.
      IRLowerAST(inner) evaluates the integer/pointer expression -> rax = address. }
    Result := IRLowerAST(ASTLeft[node]);
  end
  else
    Result := IRAppend(IR_UNSUPPORTED, ASTKind[node], ASTLeft[node], ASTRight[node], ASTIVal[node], ASTTk[node]);
end;

function IRLowerAST(node: Integer): Integer;
var left, right, seq, item, value, outNode, first, last, leftAddr, argNode: Integer;
    pairNode, condNode, specialId, classIdx, slot, cpi, pathIdx: Integer;
    isRefArg: Boolean;
    startLabel, elseLabel, endLabel, startLabelNode, endLabelNode: Integer;
    lhsNode, pair3, pair1, pair2, initNode, limitNode, isDownNode, bodyNode: Integer;
    down: Boolean;
    varIdx: Integer;
    initValNode, storeNode, limitValNode, cmpNode, condJmpNode, bodyIRNode: Integer;
    loadVarNode2, constOneNode, stepNode, storeStepNode, jmpNode: Integer;
    continueLabel, continueLabelNode: Integer;
    branchSeq, branchPair, labelsHead, stmtNode, labelNode: Integer;
    clauseBodyLabel, nextClauseLabel, selectorValNode: Integer;
    rhsIsLValue: Boolean;
    cv: Int64;
    constValNode, clauseBodyLabelNode, exitJmpNode, nextClauseLabelNode: Integer;
    beforeCount, handlerLabel, handlerNode, handlerNextLabel, savedDepth: Integer;
    raiseValueNode, raiseClass: Integer;
    i, lbId, off, len, idx, itemNode, lo, hi, val1: Integer;
begin
  if node = -1 then
  begin
    Result := -1;
    Exit;
  end;

  case ASTKind[node] of
    AN_INT_LIT, AN_BOOL_LIT:
      Result := IRAppend(IR_CONST_INT, -1, -1, -1, ASTIVal[node], ASTTk[node]);

    AN_FLOAT_LIT:
      { IVal holds the IEEE 754 double bit pattern. The IR value model carries
        floats as bits in rax (binop/store move them to xmm via movq), so a float
        literal is just mov rax, imm64 — identical to IR_CONST_INT. ASTTk (tyDouble)
        is preserved so downstream nodes select the float path. }
      Result := IRAppend(IR_CONST_INT, -1, -1, -1, ASTIVal[node], ASTTk[node]);

    AN_STR_LIT:
      Result := IRAppend(IR_CONST_STR, ASTSOffset[node], ASTSLen[node], -1, 0, ASTTk[node]);

    AN_SET_LIT:
    begin
      { Align DataLen to 8 bytes }
      while (DataLen mod 8) <> 0 do
      begin
        if DataLen >= MAX_DATA then Error('data overflow');
        Data[DataLen] := 0;
        Inc(DataLen);
      end;
      idx := DataLen;
      for i := 0 to 31 do
      begin
        if DataLen >= MAX_DATA then Error('data overflow');
        Data[DataLen] := 0;
        Inc(DataLen);
      end;
      argNode := ASTLeft[node];
      while argNode <> -1 do
      begin
        itemNode := ASTLeft[argNode];
        if ASTKind[itemNode] = AN_PAIR then
        begin
          lo := ASTIVal[ASTLeft[itemNode]];
          hi := ASTIVal[ASTRight[itemNode]];
          if lo < 0 then lo := 0;
          if hi > 255 then hi := 255;
          for val1 := lo to hi do
          begin
            Data[idx + (val1 div 8)] := Data[idx + (val1 div 8)] or Shl8_(val1 mod 8);
          end;
        end
        else
        begin
          val1 := ASTIVal[itemNode];
          if (val1 >= 0) and (val1 <= 255) then
          begin
            Data[idx + (val1 div 8)] := Data[idx + (val1 div 8)] or Shl8_(val1 mod 8);
          end;
        end;
        argNode := ASTRight[argNode];
      end;
      Result := IRAppend(IR_SET_LIT, -1, -1, -1, idx, ASTTk[node]);
    end;

    AN_ASM:
      Result := IRAppend(IR_ASM, ASTLeft[node], ASTRight[node], -1, 0, Ord(tyUnknown));

    AN_IDENT:
    begin
      varIdx := ASTIVal[node];
      if (Syms[varIdx].TypeKind = tyString) or Syms[varIdx].IsArray then
        Result := IRAppend(IR_LEA, varIdx, -1, -1, 0, ASTTk[node])
      else
        Result := IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, ASTTk[node]);
    end;

    AN_INDEX, AN_FIELD, AN_DEREF:
    begin
      left := IRLowerAddress(node);
      if IntToTypeKind(ASTTk[node]) = tyString then
        Result := left
      else
        Result := IRAppend(IR_LOAD_MEM, left, -1, -1, 0, ASTTk[node]);
    end;

    AN_PTR_CAST:
    begin
      { A cast PType(expr) is purely a type-tag change — the value in rax is
        already the pointer. No load-through-memory here. }
      Result := IRLowerAST(ASTLeft[node]);
    end;

    AN_RTTI_REG:
    begin
      Result := IRAppend(IR_RTTI_REG, -1, -1, -1, 0, ASTTk[node]);
    end;

    AN_RESOURCES:
    begin
      Result := IRAppend(IR_RESOURCES, -1, -1, -1, 0, ASTTk[node]);
    end;

    AN_ADDR:
    begin
      Result := IRLowerAddress(ASTLeft[node]);
    end;

    AN_PROCADDR:
    begin
      Result := IRAppend(IR_PROCADDR, Integer(ASTIVal[node]), -1, -1, 0, ASTTk[node]);
    end;

    AN_NEG:
    begin
      left := IRLowerAST(ASTLeft[node]);
      Result := IRAppend(IR_NEG, left, -1, -1, 0, ASTTk[node]);
    end;

    AN_NOT:
    begin
      left := IRLowerAST(ASTLeft[node]);
      Result := IRAppend(IR_NOT, left, -1, -1, 0, ASTTk[node]);
    end;

    AN_BINOP:
    begin
      { Operator overloading: a <op> b on a class/record operand resolves to a
        call to the registered operator proc (lhs, rhs), mirroring the direct
        backend. Args are passed by value (rdi=lhs, rsi=rhs). }
      cpi := FindOpOverload(Integer(ASTIVal[node]), ASTTk[ASTLeft[node]], ResolveNodeRec(ASTLeft[node]));
      if cpi >= 0 then
      begin
        left  := IRLowerAST(ASTLeft[node]);
        first := IRAppend(IR_ARG, left, -1, -1, 0, ASTTk[ASTLeft[node]]);
        right := IRLowerAST(ASTRight[node]);
        last  := IRAppend(IR_ARG, right, -1, -1, 0, ASTTk[ASTRight[node]]);
        IRB[first] := last;
        Result := IRAppend(IR_CALL, cpi, first, -1, 0, ASTTk[node]);
      end
      else
      begin
        left := IRLowerAST(ASTLeft[node]);
        right := IRLowerAST(ASTRight[node]);
        Result := IRAppend(IR_BINOP, left, right, Integer(ASTIVal[node]), 0, ASTTk[node]);
      end;
    end;

    AN_ASSIGN:
    begin
      { Whole-record copy: the scalar store paths move only a qword (8 bytes),
        which truncates records larger than 8 bytes. When the RHS is an lvalue,
        copy the full RecSize via IR_COPY_REC (rep movsb). }
      rhsIsLValue := (ASTKind[ASTRight[node]] = AN_IDENT) or
                     (ASTKind[ASTRight[node]] = AN_FIELD) or
                     (ASTKind[ASTRight[node]] = AN_INDEX) or
                     (ASTKind[ASTRight[node]] = AN_DEREF);
      if (IntToTypeKind(ASTTk[ASTLeft[node]]) = tyRecord) and rhsIsLValue then
      begin
        leftAddr := IRLowerAddress(ASTLeft[node]);
        right := IRLowerAddress(ASTRight[node]);
        Result := IRAppend(IR_COPY_REC, leftAddr, right, -1,
                           RecSize(ResolveNodeRec(ASTLeft[node])), Ord(tyRecord));
      end
      else
      begin
        value := IRLowerAST(ASTRight[node]);
        if ASTKind[ASTLeft[node]] = AN_IDENT then
          Result := IRAppend(IR_STORE_SYM, ASTIVal[ASTLeft[node]], value, -1, 0, ASTTk[ASTLeft[node]])
        else
        begin
          leftAddr := IRLowerAddress(ASTLeft[node]);
          Result := IRAppend(IR_STORE_MEM, leftAddr, value, -1, 0, ASTTk[ASTLeft[node]]);
        end;
      end;
    end;

    AN_HALT, AN_EXIT:
    begin
      beforeCount := IRCount;
      if ASTKind[node] = AN_HALT then
      begin
        if ASTLeft[node] <> -1 then
          value := IRLowerAST(ASTLeft[node])
        else
          value := -1;
        last := IRAppend(IR_TERMINATE, value, -1, -1, AN_HALT, 0);
      end
      else
      begin
        if ASTLeft[node] <> -1 then
        begin
          value := IRLowerAST(ASTLeft[node]);
          if (CurProc >= 0) and (Procs[CurProc].RetSymIdx >= 0) then
            last := IRAppend(IR_STORE_SYM, Procs[CurProc].RetSymIdx, value, -1, 0, ASTTk[ASTLeft[node]]);
        end;
        IRLowerCleanupToDepth(0);
        last := IRAppend(IR_TERMINATE, -1, -1, -1, AN_EXIT, 0);
      end;
      if beforeCount < last then
        Result := IRAppend(IR_BLOCK, beforeCount, last, -1, 0, 0)
      else
        Result := last;
    end;

    AN_CALL:
    begin
      first := -1;
      last := -1;
      cpi := ASTIVal[node];
      item := ASTLeft[node];
      pathIdx := 0;
      classIdx := -1;
      if cpi = -Ord(tkGetMem) then
        classIdx := ASTRight[node];
      while item <> -1 do
      begin
        isRefArg := False;
        if cpi >= 0 then
        begin
          if (pathIdx < Procs[cpi].ParamCount) and Procs[cpi].Params[pathIdx].IsRef then
            isRefArg := True;
        end
        else
        begin
          specialId := -cpi;
          if specialId = Ord(tkLength) then
          begin
            if pathIdx = 0 then isRefArg := True;
          end
          else if (specialId = Ord(tkSysRead)) or (specialId = Ord(tkSyswrite)) then
          begin
            if pathIdx = 1 then isRefArg := True;
          end
          else if (specialId = Ord(tkGetMem)) and (pathIdx > 0) then
          begin
            classIdx := ASTRight[node];
            slot := FindUMeth(classIdx - REC_UCLASS_BASE, 'create');
            if slot >= 0 then
            begin
              slot := UMthProc_[slot];
              if (pathIdx < Procs[slot].ParamCount) and Procs[slot].Params[pathIdx].IsRef then
                isRefArg := True;
            end;
          end;
        end;

        if isRefArg then
          value := IRLowerAddress(ASTLeft[item])
        else
          value := IRLowerAST(ASTLeft[item]);

        argNode := IRAppend(IR_ARG, value, -1, -1, 0, ASTTk[item]);
        if first < 0 then first := argNode
        else IRB[last] := argNode;
        last := argNode;
        item := ASTRight[item];
        Inc(pathIdx);
      end;
      Result := IRAppend(IR_CALL, ASTIVal[node], first, classIdx, 0, ASTTk[node]);
    end;

    AN_IF:
    begin
      pairNode := ASTRight[node];
      elseLabel := IRNewLabel;
      endLabel := IRNewLabel;
      condNode := IRLowerAST(ASTLeft[node]);
      first := condNode;
      last := IRAppend(IR_JUMP_IF_FALSE, elseLabel, condNode, -1, 0, 0);
      last := IRLowerAST(ASTLeft[pairNode]);
      IRMarkStatementNode(last);
      last := IRAppend(IR_JUMP, endLabel, -1, -1, 0, 0);
      last := IRAppend(IR_LABEL, -1, -1, -1, elseLabel, 0);
      if ASTRight[pairNode] <> -1 then
      begin
        last := IRLowerAST(ASTRight[pairNode]);
        IRMarkStatementNode(last);
      end;
      endLabelNode := IRAppend(IR_LABEL, -1, -1, -1, endLabel, 0);
      Result := IRAppend(IR_BLOCK, first, endLabelNode, -1, 0, 0);
    end;

    AN_WHILE:
    begin
      startLabel := IRNewLabel;
      endLabel := IRNewLabel;
      startLabelNode := IRAppend(IR_LABEL, -1, -1, -1, startLabel, 0);
      condNode := IRLowerAST(ASTLeft[node]);
      last := IRAppend(IR_JUMP_IF_FALSE, endLabel, condNode, -1, 0, 0);
      
      if IRLoopStackDepth >= 64 then Error('IR loop stack overflow');
      IRLoopStackBreak[IRLoopStackDepth] := endLabel;
      IRLoopStackContinue[IRLoopStackDepth] := startLabel;
      IRLoopStackExceptionDepth[IRLoopStackDepth] := ExceptionCodegenDepth;
      Inc(IRLoopStackDepth);
      
      last := IRLowerAST(ASTRight[node]);
      IRMarkStatementNode(last);
      
      Dec(IRLoopStackDepth);
      
      last := IRAppend(IR_JUMP, startLabel, -1, -1, 0, 0);
      endLabelNode := IRAppend(IR_LABEL, -1, -1, -1, endLabel, 0);
      Result := IRAppend(IR_BLOCK, startLabelNode, endLabelNode, -1, 0, 0);
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
      
      down := ASTIVal[isDownNode] = 1;
      varIdx := ASTIVal[lhsNode];
      
      initValNode := IRLowerAST(initNode);
      storeNode := IRAppend(IR_STORE_SYM, varIdx, initValNode, -1, 0, ASTTk[lhsNode]);
      
      limitValNode := IRLowerAST(limitNode);
      
      startLabel := IRNewLabel;
      endLabel := IRNewLabel;
      continueLabel := IRNewLabel;
      
      startLabelNode := IRAppend(IR_LABEL, -1, -1, -1, startLabel, 0);
      
      condNode := IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, ASTTk[lhsNode]);
      
      if down then
        cmpNode := IRAppend(IR_BINOP, condNode, limitValNode, Ord(tkGe), 0, Ord(tyBoolean))
      else
        cmpNode := IRAppend(IR_BINOP, condNode, limitValNode, Ord(tkLe), 0, Ord(tyBoolean));
        
      condJmpNode := IRAppend(IR_JUMP_IF_FALSE, endLabel, cmpNode, -1, 0, 0);
      
      if IRLoopStackDepth >= 64 then Error('IR loop stack overflow');
      IRLoopStackBreak[IRLoopStackDepth] := endLabel;
      IRLoopStackContinue[IRLoopStackDepth] := continueLabel;
      IRLoopStackExceptionDepth[IRLoopStackDepth] := ExceptionCodegenDepth;
      Inc(IRLoopStackDepth);
      
      bodyIRNode := IRLowerAST(bodyNode);
      IRMarkStatementNode(bodyIRNode);
      
      Dec(IRLoopStackDepth);
      
      continueLabelNode := IRAppend(IR_LABEL, -1, -1, -1, continueLabel, 0);
      
      loadVarNode2 := IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, ASTTk[lhsNode]);
      constOneNode := IRAppend(IR_CONST_INT, -1, -1, -1, 1, Ord(tyInteger));
      
      if down then
        stepNode := IRAppend(IR_BINOP, loadVarNode2, constOneNode, Ord(tkMinus), 0, ASTTk[lhsNode])
      else
        stepNode := IRAppend(IR_BINOP, loadVarNode2, constOneNode, Ord(tkPlus), 0, ASTTk[lhsNode]);
        
      storeStepNode := IRAppend(IR_STORE_SYM, varIdx, stepNode, -1, 0, ASTTk[lhsNode]);
      
      jmpNode := IRAppend(IR_JUMP, startLabel, -1, -1, 0, 0);
      
      endLabelNode := IRAppend(IR_LABEL, -1, -1, -1, endLabel, 0);
      
      Result := IRAppend(IR_BLOCK, storeNode, endLabelNode, -1, 0, 0);
    end;

    AN_REPEAT:
    begin
      startLabel := IRNewLabel;
      continueLabel := IRNewLabel;
      endLabel := IRNewLabel;
      
      startLabelNode := IRAppend(IR_LABEL, -1, -1, -1, startLabel, 0);
      
      if IRLoopStackDepth >= 64 then Error('IR loop stack overflow');
      IRLoopStackBreak[IRLoopStackDepth] := endLabel;
      IRLoopStackContinue[IRLoopStackDepth] := continueLabel;
      IRLoopStackExceptionDepth[IRLoopStackDepth] := ExceptionCodegenDepth;
      Inc(IRLoopStackDepth);
      
      bodyIRNode := IRLowerAST(ASTLeft[node]);
      IRMarkStatementNode(bodyIRNode);
      
      Dec(IRLoopStackDepth);
      
      continueLabelNode := IRAppend(IR_LABEL, -1, -1, -1, continueLabel, 0);
      
      condNode := IRLowerAST(ASTRight[node]);
      
      last := IRAppend(IR_JUMP_IF_FALSE, startLabel, condNode, -1, 0, 0);
      
      endLabelNode := IRAppend(IR_LABEL, -1, -1, -1, endLabel, 0);
      
      Result := IRAppend(IR_BLOCK, startLabelNode, endLabelNode, -1, 0, 0);
    end;

    AN_CASE:
    begin
      selectorValNode := IRLowerAST(ASTLeft[node]);
      endLabel := IRNewLabel;
      
      first := -1;
      last := -1;
      
      branchSeq := ASTRight[node];
      while branchSeq <> -1 do
      begin
        branchPair := ASTLeft[branchSeq];
        labelsHead := ASTLeft[branchPair];
        stmtNode   := ASTRight[branchPair];
        
        if labelsHead = -1 then
        begin
          { Else Clause }
          bodyIRNode := IRLowerAST(stmtNode);
          IRMarkStatementNode(bodyIRNode);
          if first < 0 then first := bodyIRNode;
          last := bodyIRNode;
        end
        else
        begin
          { Normal Clause }
          clauseBodyLabel := IRNewLabel;
          nextClauseLabel := IRNewLabel;
          
          labelNode := labelsHead;
          while labelNode <> -1 do
          begin
            cv := ASTIVal[ASTLeft[labelNode]];
            constValNode := IRAppend(IR_CONST_INT, -1, -1, -1, cv, Ord(tyInteger));
            cmpNode := IRAppend(IR_BINOP, selectorValNode, constValNode, Ord(tkNeq), 0, Ord(tyBoolean));
            condJmpNode := IRAppend(IR_JUMP_IF_FALSE, clauseBodyLabel, cmpNode, -1, 0, 0);
            if first < 0 then first := condJmpNode;
            last := condJmpNode;
            
            labelNode := ASTRight[labelNode];
          end;
          
          exitJmpNode := IRAppend(IR_JUMP, nextClauseLabel, -1, -1, 0, 0);
          last := exitJmpNode;
          
          clauseBodyLabelNode := IRAppend(IR_LABEL, -1, -1, -1, clauseBodyLabel, 0);
          last := clauseBodyLabelNode;
          
          bodyIRNode := IRLowerAST(stmtNode);
          IRMarkStatementNode(bodyIRNode);
          last := bodyIRNode;
          
          exitJmpNode := IRAppend(IR_JUMP, endLabel, -1, -1, 0, 0);
          last := exitJmpNode;
          
          nextClauseLabelNode := IRAppend(IR_LABEL, -1, -1, -1, nextClauseLabel, 0);
          last := nextClauseLabelNode;
        end;
        
        branchSeq := ASTRight[branchSeq];
      end;
      
      endLabelNode := IRAppend(IR_LABEL, -1, -1, -1, endLabel, 0);
      last := endLabelNode;
      
      Result := IRAppend(IR_BLOCK, first, last, -1, 0, 0);
    end;

    AN_BREAK:
    begin
      if IRLoopStackDepth = 0 then Error('break outside loop');
      beforeCount := IRCount;
      IRLowerCleanupToDepth(IRLoopStackExceptionDepth[IRLoopStackDepth - 1]);
      jmpNode := IRAppend(IR_JUMP, IRLoopStackBreak[IRLoopStackDepth - 1], -1, -1, 0, 0);
      if beforeCount < jmpNode then
        Result := IRAppend(IR_BLOCK, beforeCount, jmpNode, -1, 0, 0)
      else
        Result := jmpNode;
    end;

    AN_CONTINUE:
    begin
      if IRLoopStackDepth = 0 then Error('continue outside loop');
      beforeCount := IRCount;
      IRLowerCleanupToDepth(IRLoopStackExceptionDepth[IRLoopStackDepth - 1]);
      jmpNode := IRAppend(IR_JUMP, IRLoopStackContinue[IRLoopStackDepth - 1], -1, -1, 0, 0);
      if beforeCount < jmpNode then
        Result := IRAppend(IR_BLOCK, beforeCount, jmpNode, -1, 0, 0)
      else
        Result := jmpNode;
    end;

    AN_RAISE:
    begin
      if ASTLeft[node] <> -1 then
      begin
        raiseValueNode := IRLowerAST(ASTLeft[node]);
        raiseClass := ResolveNodeRec(ASTLeft[node]);
        if raiseClass < REC_UCLASS_BASE then raiseClass := REC_NONE;
      end
      else
      begin
        raiseValueNode := -1;
        raiseClass := REC_NONE;
      end;
      Result := IRAppend(IR_RAISE, raiseValueNode, -1, -1, raiseClass, 0);
    end;

    AN_TRY_EXCEPT:
    begin
      handlerLabel := IRNewLabel;
      endLabel := IRNewLabel;
      first := IRAppend(IR_EXC_ENTER, handlerLabel, -1, -1, 0, 0);

      ExceptionFinallyBody[ExceptionCodegenDepth] := -1;
      Inc(ExceptionCodegenDepth);
      last := IRLowerAST(ASTLeft[node]);
      Dec(ExceptionCodegenDepth);

      last := IRAppend(IR_EXC_LEAVE, 1, -1, -1, 0, 0);
      last := IRAppend(IR_JUMP, endLabel, -1, -1, 0, 0);
      last := IRAppend(IR_LABEL, -1, -1, -1, handlerLabel, 0);
      last := IRAppend(IR_EXC_LEAVE, 1, -1, -1, 0, 0);

      handlerNode := ASTRight[node];
      while handlerNode <> -1 do
      begin
        handlerNextLabel := -1;
        if ASTIVal[handlerNode] >= 0 then
        begin
          handlerNextLabel := IRNewLabel;
          last := IRAppend(IR_EXC_MATCH, handlerNextLabel, -1, -1, ASTIVal[handlerNode], 0);
        end;
        if ASTSOffset[handlerNode] >= 0 then
          last := IRAppend(IR_EXC_STORE, ASTSOffset[handlerNode], -1, -1, 0, 0);
        last := IRLowerAST(ASTLeft[handlerNode]);
        IRMarkStatementNode(last);
        last := IRAppend(IR_EXC_CLEAR, -1, -1, -1, 0, 0);
        last := IRAppend(IR_JUMP, endLabel, -1, -1, 0, 0);
        if handlerNextLabel >= 0 then
          last := IRAppend(IR_LABEL, -1, -1, -1, handlerNextLabel, 0);
        handlerNode := ASTRight[handlerNode];
      end;
      last := IRAppend(IR_RAISE, -1, -1, -1, REC_NONE, 0);
      endLabelNode := IRAppend(IR_LABEL, -1, -1, -1, endLabel, 0);
      Result := IRAppend(IR_BLOCK, first, endLabelNode, -1, 0, 0);
    end;

    AN_TRY_FINALLY:
    begin
      handlerLabel := IRNewLabel;
      endLabel := IRNewLabel;
      first := IRAppend(IR_EXC_ENTER, handlerLabel, -1, -1, 0, 0);

      ExceptionFinallyBody[ExceptionCodegenDepth] := ASTRight[node];
      Inc(ExceptionCodegenDepth);
      last := IRLowerAST(ASTLeft[node]);
      IRMarkStatementNode(last);
      Dec(ExceptionCodegenDepth);

      last := IRAppend(IR_EXC_LEAVE, 1, -1, -1, 0, 0);
      last := IRLowerAST(ASTRight[node]);
      IRMarkStatementNode(last);
      last := IRAppend(IR_JUMP, endLabel, -1, -1, 0, 0);

      last := IRAppend(IR_LABEL, -1, -1, -1, handlerLabel, 0);
      last := IRAppend(IR_EXC_LEAVE, 1, -1, -1, 0, 0);
      savedDepth := ExceptionCodegenDepth;
      ExceptionCodegenDepth := savedDepth;
      last := IRLowerAST(ASTRight[node]);
      IRMarkStatementNode(last);
      ExceptionCodegenDepth := savedDepth;
      last := IRAppend(IR_RAISE, -1, -1, -1, REC_NONE, 0);

      endLabelNode := IRAppend(IR_LABEL, -1, -1, -1, endLabel, 0);
      Result := IRAppend(IR_BLOCK, first, endLabelNode, -1, 0, 0);
    end;

    AN_WRITE, AN_WRITELN:
    begin
      first := -1;
      last := -1;
      item := ASTLeft[node];
      while item <> -1 do
      begin
        { IR_WRITE: IRB = field width (0 = none), IRC = decimals (-1 = none),
          IRTk = the source expression type (for write dispatch). }
        if ASTKind[item] = AN_ARG then
        begin
          value := IRLowerAST(ASTLeft[item]);
          outNode := IRAppend(IR_WRITE, value, ASTIVal[item], ASTSOffset[item], 0, Ord(IntToTypeKind(ASTTk[ASTLeft[item]])));
        end
        else if ASTKind[item] = AN_PAIR then
        begin
          value := IRLowerAST(ASTLeft[item]);
          outNode := IRAppend(IR_WRITE, value, -1, -1, 0, IRTk[value]);
        end
        else
        begin
          value := IRLowerAST(item);
          outNode := IRAppend(IR_WRITE, value, -1, -1, 0, IRTk[value]);
        end;
        if first < 0 then first := outNode;
        last := outNode;
        item := ASTRight[item];
      end;
      if ASTKind[node] = AN_WRITELN then
        Result := IRAppend(IR_WRITELN, first, last, -1, 0, 0)
      else
        Result := IRAppend(IR_BLOCK, first, last, -1, 0, 0);
    end;

    AN_READLN, AN_READ:
    begin
      { Read one line from stdin, then parse each lvalue target from it by type. }
      first := IRAppend(IR_READLINE, -1, -1, -1, 0, 0);
      last := first;
      item := ASTLeft[node];
      while item <> -1 do
      begin
        value := IRLowerAddress(ASTLeft[item]);   { target address }
        outNode := IRAppend(IR_READ_VAR, value, -1, -1, 0,
                            Ord(IntToTypeKind(ASTTk[ASTLeft[item]])));
        last := outNode;
        item := ASTRight[item];
      end;
      Result := IRAppend(IR_BLOCK, first, last, -1, 0, 0);
    end;

    AN_BLOCK:
    begin
      first := -1;
      last := -1;
      seq := ASTLeft[node];
      while seq <> -1 do
      begin
        if ASTKind[seq] = AN_SEQ then
        begin
          item := IRLowerAST(ASTLeft[seq]);
          IRMarkStatementNode(item);
          seq := ASTRight[seq];
        end
        else
        begin
          item := IRLowerAST(seq);
          IRMarkStatementNode(item);
          seq := -1;
        end;
        if first < 0 then first := item;
        last := item;
      end;
      Result := IRAppend(IR_BLOCK, first, last, -1, 0, 0);
    end;

    AN_VIRTUAL_CALL:
    begin
      { AN_VIRTUAL_CALL layout:
          ASTIVal[node] = proc index   (for param signature)
          ASTRight[node] = VMT slot index
          ASTLeft[node]  = first AN_ARG (Self is arg 0, injected by parser) }
      first := -1;
      last := -1;
      cpi := ASTIVal[node];
      slot := ASTRight[node];
      item := ASTLeft[node];
      pathIdx := 0;
      while item <> -1 do
      begin
        isRefArg := False;
        if (pathIdx > 0) and (pathIdx < Procs[cpi].ParamCount) and
           Procs[cpi].Params[pathIdx].IsRef then
          isRefArg := True;
        { Self (pathIdx=0) is always passed by value (pointer) }
        if isRefArg then
          value := IRLowerAddress(ASTLeft[item])
        else
          value := IRLowerAST(ASTLeft[item]);
        argNode := IRAppend(IR_ARG, value, -1, -1, 0, ASTTk[item]);
        if first < 0 then first := argNode
        else IRB[last] := argNode;
        last := argNode;
        item := ASTRight[item];
        Inc(pathIdx);
      end;
      { IRA=first arg, IRB=last arg, IRC=proc idx, IRIVal=VMT slot }
      Result := IRAppend(IR_VIRTUAL_CALL, first, last, cpi, slot, ASTTk[node]);
    end;

    AN_LABEL:
    begin
      off := ASTSOffset[node];
      len := ASTSLen[node];
      lbId := -1;
      for i := 0 to GotoLabelCount - 1 do
        if TokSlicesMatch(GotoLabelNOff[i], GotoLabelNLen[i], off, len) then
        begin
          if GotoLabelIRId[i] = -1 then
            GotoLabelIRId[i] := IRNewLabel;
          lbId := GotoLabelIRId[i];
          Break;
        end;
      if lbId = -1 then Error('AN_LABEL: undeclared label');
      Result := IRAppend(IR_LABEL, -1, -1, -1, lbId, 0);
    end;
    AN_GOTO:
    begin
      off := ASTSOffset[node];
      len := ASTSLen[node];
      lbId := -1;
      for i := 0 to GotoLabelCount - 1 do
        if TokSlicesMatch(GotoLabelNOff[i], GotoLabelNLen[i], off, len) then
        begin
          if GotoLabelIRId[i] = -1 then
            GotoLabelIRId[i] := IRNewLabel;
          lbId := GotoLabelIRId[i];
          Break;
        end;
      if lbId = -1 then Error('AN_GOTO: undefined label');
      Result := IRAppend(IR_JUMP, lbId, -1, -1, 0, 0);
    end;
    AN_PAIR, AN_SEQ:
    begin
      left := IRLowerAST(ASTLeft[node]);
      IRMarkStatementNode(left);
      right := IRLowerAST(ASTRight[node]);
      IRMarkStatementNode(right);
      Result := IRAppend(IR_BLOCK, left, right, -1, 0, 0);
    end;

  else
    Result := IRAppend(IR_UNSUPPORTED, ASTKind[node], ASTLeft[node], ASTRight[node], ASTIVal[node], ASTTk[node]);
  end;
end;

procedure IRDump;
var i, blockNum: Integer;
    isLeader: array[0..MAX_IR-1] of Boolean;
    symIdx: Integer;
begin
  for i := 0 to MAX_IR - 1 do
    isLeader[i] := False;

  if IRCount > 0 then
    isLeader[0] := True;

  for i := 0 to IRCount - 1 do
  begin
    if IRKind[i] = IR_LABEL then
      isLeader[i] := True;
    if (IRKind[i] = IR_JUMP) or (IRKind[i] = IR_JUMP_IF_FALSE) then
    begin
      if i + 1 < IRCount then
        isLeader[i + 1] := True;
    end;
  end;

  writeln('IR count=', IRCount);
  blockNum := 0;
  for i := 0 to IRCount - 1 do
  begin
    if isLeader[i] then
    begin
      Inc(blockNum);
      writeln('--- BASIC BLOCK BB', blockNum, ' ---');
    end;
    write(i, ': ', IROpName(IRKind[i]),
          ' a=', IRA[i],
          ' b=', IRB[i],
          ' c=', IRC[i],
          ' ival=', IRIVal[i],
          ' tk=', IRTk[i]);
          
    if (IRKind[i] = IR_LOAD_SYM) or (IRKind[i] = IR_STORE_SYM) or (IRKind[i] = IR_LEA) then
    begin
      symIdx := IRA[i];
      if (symIdx >= 0) and (symIdx < SymCount) then
        write(' [sym=', Syms[symIdx].Name, ']');
    end;
    if IRKind[i] = IR_FIELD then
      write(' [offset=', IRIVal[i], ']');
    if IRKind[i] = IR_INDEX then
      write(' [lo=', IRC[i], ' size=', IRIVal[i], ']');
    writeln;
  end;
end;

procedure IRBuildAndMaybeDump(node: Integer);
begin
  if not DumpIR then Exit;
  IRReset;
  IRLowerAST(node);
  IRVerify;
  IRDump;
end;
