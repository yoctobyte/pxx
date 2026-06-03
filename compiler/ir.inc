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
  IRStmtRoot[IRCount] := False;
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
    IR_COPY_REC_MANAGED: Result := 'copy_rec_managed';
    IR_DYNDATA: Result := 'dyndata';
    IR_SETLEN_DYN: Result := 'setlen_dyn';
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
    IR_SET_COPY: Result := 'set_copy';
    IR_SET_BINOP: Result := 'set_binop';
    IR_SET_CMP: Result := 'set_cmp';
    IR_VAR_STORE: Result := 'var_store';
    IR_VAR_BINOP: Result := 'var_binop';
    IR_VAR_BOX: Result := 'var_box';
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
    if (IRTk[i] < 0) or (IRTk[i] > Ord(tyAnsiString)) then
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
        if (op < 0) or (op > Ord(tkShl)) then
          Error('invalid operator token kind in binop');
      end;

      IR_CALL:
      begin
        if (IRA[i] >= ProcCount) then
          Error('invalid IR proc reference in call');
        IRRequireOptionalNode(IRB[i], 'call first arg');
        if (IRA[i] >= 0) and TypeIsAggregate(Procs[IRA[i]].RetType) then
          IRRequireNode(IRC[i], 'call aggregate destination');
        { Otherwise IRC = classIdx (record id for constructor/method dispatch),
          NOT a node. Args chain via IRB[argNode]. }
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

      IR_COPY_REC_MANAGED:
      begin
        IRRequireNode(IRA[i], 'copy_rec_managed dest');
        IRRequireNode(IRB[i], 'copy_rec_managed src');
      end;

      IR_DYNDATA:
        if (IRA[i] < 0) or (IRA[i] >= SymCount) then
          Error('invalid symbol in dyndata');

      IR_SETLEN_DYN:
      begin
        IRRequireNode(IRA[i], 'setlen_dyn target');
        IRRequireNode(IRB[i], 'setlen_dyn count');
      end;

      IR_SET_COPY, IR_SET_BINOP, IR_SET_CMP:
      begin
        IRRequireNode(IRA[i], 'set op left');
        IRRequireNode(IRB[i], 'set op right');
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

      IR_CLASSREF:
        if (IRA[i] < 0) or (IRA[i] >= UClsCount) then
          Error('invalid class index in classref');

      IR_UNSUPPORTED:
        begin end;

      IR_VAR_STORE:
      begin
        IRRequireNode(IRA[i], 'var_store dest');
        IRRequireNode(IRB[i], 'var_store value');
      end;

      IR_VAR_BINOP:
      begin
        IRRequireNode(IRA[i], 'var_binop left');
        IRRequireNode(IRB[i], 'var_binop right');
      end;

      IR_VAR_BOX:
      begin
        IRRequireNode(IRA[i], 'var_box dest');
        IRRequireNode(IRB[i], 'var_box value');
      end;

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
  if (irNode >= 0) and (irNode < IRCount) then
  begin
    if IRKind[irNode] = IR_CALL then
      IRIVal[irNode] := 1
    else if IRKind[irNode] = IR_VIRTUAL_CALL then
      IRStmtRoot[irNode] := True;
  end;
end;

function NodeDynDepth(node: Integer): Integer;
{ Dynamic-array nesting of an expression's value: 0 if not a dyn array, else the
  remaining `array of` levels. m (array of array of T) is 2; m[i] is 1; m[i][j]
  is 0 (a base value). }
var bd: Integer;
begin
  Result := 0;
  if node < 0 then Exit;
  case ASTKind[node] of
    AN_IDENT:
      if Syms[ASTIVal[node]].IsArray and (Syms[ASTIVal[node]].ArrLen = -1) then
        Result := SymDynDepth[ASTIVal[node]];
    AN_INDEX:
      begin
        bd := NodeDynDepth(ASTLeft[node]);
        if bd > 0 then Result := bd - 1;
      end;
  end;
end;

function NodeDynBaseSym(node: Integer): Integer;
{ Root dynamic-array symbol of a (possibly nested) index expression, or -1. }
begin
  Result := -1;
  if node < 0 then Exit;
  if ASTKind[node] = AN_IDENT then
  begin
    if Syms[ASTIVal[node]].IsArray and (Syms[ASTIVal[node]].ArrLen = -1) then
      Result := ASTIVal[node];
  end
  else if ASTKind[node] = AN_INDEX then
    Result := NodeDynBaseSym(ASTLeft[node]);
end;

function DynElemSize(depth: Integer; baseTk: TTypeKind; baseRec: Integer): Integer;
{ Stride of one element of a dynamic array at the given depth. depth>1 holds
  pointer-sized sub-array handles; depth=1 holds base elements. }
begin
  if depth > 1 then
    Result := TARGET_PTR_SIZE
  else if baseTk = tyRecord then
    Result := RecSize(baseRec)
  else
    Result := TypeSize(baseTk);
end;

function IRLowerAddress(node: Integer): Integer;
var baseNode, baseAddr, indexNode, lo, elemSize: Integer;
    fieldName: AnsiString;
    isArr: Boolean;
    tk: TTypeKind;
    baseDynDepth, dynRootSym, dynBaseRec: Integer;
    dynBaseTk: TTypeKind;
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
    { Nested dynamic-array indexing: base is a nested dyn array (depth>=2) or a
      sub-array element (an AN_INDEX whose value is still a dyn array). The base
      data pointer is evaluated independently of InLValueWrite; no copy-on-write
      at nested levels. Plain depth-1 arrays keep the path below. }
    baseDynDepth := NodeDynDepth(baseNode);
    if (baseDynDepth >= 2) or
       ((baseDynDepth = 1) and (ASTKind[baseNode] = AN_INDEX)) then
    begin
      dynRootSym := NodeDynBaseSym(baseNode);
      dynBaseTk := Syms[dynRootSym].ElemType;
      dynBaseRec := Syms[dynRootSym].ElemRecName;
      if ASTKind[baseNode] = AN_IDENT then
        baseAddr := IRAppend(IR_DYNDATA, ASTIVal[baseNode], -1, -1, 0, Ord(tyPointer))
      else
        baseAddr := IRAppend(IR_LOAD_MEM, IRLowerAddress(baseNode), -1, -1, 0, Ord(tyPointer));
      indexNode := IRLowerAST(ASTRight[node]);
      elemSize := DynElemSize(baseDynDepth, dynBaseTk, dynBaseRec);
      if baseDynDepth >= 2 then
        Result := IRAppend(IR_INDEX, baseAddr, indexNode, 0, elemSize, Ord(tyPointer))
      else
        Result := IRAppend(IR_INDEX, baseAddr, indexNode, 0, elemSize, Ord(dynBaseTk));
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
    if (tk = tyAnsiString) and not isArr then
    begin
      lo := 1;
      elemSize := 1;
      tk := tyChar;
      recName := REC_NONE;
    end
    else if (tk = tyString) and not isArr then
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
    { A class-typed base holds a POINTER to the object, so the field offset must
      be applied to that pointer's VALUE, not to the address of the slot holding
      it. This is true for any class-typed base — a variable (a.b), a class-typed
      field (a.b.c), an index, etc. — so evaluate the base as a value when it is
      class-typed, and take its address only for embedded (record) bases. }
    if ASTTk[baseNode] = Ord(tyClass) then
      baseAddr := IRLowerAST(baseNode)
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

function IRAppendCall(procIdx, firstArg, classIdx, tk: Integer): Integer;
var scratchSym, scratchAddr, savedRecId: Integer;
begin
  if (procIdx >= 0) and TypeIsAggregate(Procs[procIdx].RetType) then
  begin
    { Aggregate calls return into caller-owned storage. IRC carries an IR_LEA
      node for that hidden destination; ordinary calls keep the class index. }
    savedRecId := LastTypeRecId;
    if Procs[procIdx].RetType = tyRecord then
      LastTypeRecId := ProcRetRecId[procIdx];
    scratchSym := AllocVar('', Procs[procIdx].RetType);
    LastTypeRecId := savedRecId;
    scratchAddr := IRAppend(IR_LEA, scratchSym, -1, -1, 0, Ord(tyPointer));
    Result := IRAppend(IR_CALL, procIdx, firstArg, scratchAddr, 0, tk);
  end
  else
    Result := IRAppend(IR_CALL, procIdx, firstArg, classIdx, 0, tk);
end;

function IRPointerStride(node: Integer): Integer;
var elemTk: TTypeKind; recId, aliasIdx: Integer;
begin
  elemTk := tyUnknown;
  recId := REC_NONE;
  if ASTKind[node] = AN_IDENT then
  begin
    elemTk := Syms[ASTIVal[node]].PtrElemTk;
    recId := Syms[ASTIVal[node]].PtrElemRec;
  end
  else if ASTKind[node] = AN_FIELD then
  begin
    recId := ResolveNodeRec(ASTLeft[node]);
    elemTk := RecFieldPtrElemTk(recId, GetASTIdentName(node));
    recId := RecFieldPtrElemRec(recId, GetASTIdentName(node));
  end
  else if ASTKind[node] = AN_PTR_CAST then
  begin
    aliasIdx := ASTIVal[node];
    if aliasIdx >= 0 then
    begin
      elemTk := IntToTypeKind(AliasElemTk[aliasIdx]);
      recId := AliasElemRec[aliasIdx];
    end;
  end
  else if ASTKind[node] = AN_BINOP then
  begin
    if IntToTypeKind(ASTTk[ASTLeft[node]]) = tyPointer then
      Result := IRPointerStride(ASTLeft[node])
    else
      Result := IRPointerStride(ASTRight[node]);
    Exit;
  end;
  if elemTk = tyRecord then
    Result := RecSize(recId)
  else if elemTk = tyUnknown then
    Result := 1
  else
    Result := TypeSize(elemTk);
end;

function IRLowerAST(node: Integer): Integer;
var left, right, seq, item, value, outNode, first, last, leftAddr, argNode, argVal, intCallNode, intArgSeq, argNode2, zeroVal, pi: Integer;
    pairNode, condNode, specialId, classIdx, slot, cpi, pathIdx: Integer;
    isRefArg: Boolean; argTk: TTypeKind; callRetType: TTypeKind; callVal: Integer;
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
    i, lbId, off, len, idx, itemNode, lo, hi, val1, elemSize, savedProc: Integer;
    slTargetAST, slCountAST, slRootSym, slDepth, slTargetAddr, slCountNode: Integer;
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
      if (Syms[varIdx].TypeKind = tyString) or (Syms[varIdx].TypeKind = tySet) or Syms[varIdx].IsArray then
        Result := IRAppend(IR_LEA, varIdx, -1, -1, 0, ASTTk[node])
      else
        Result := IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, ASTTk[node]);
    end;

    AN_INDEX, AN_FIELD, AN_DEREF:
    begin
      left := IRLowerAddress(node);
      if (IntToTypeKind(ASTTk[node]) = tyString) or (IntToTypeKind(ASTTk[node]) = tySet) then
        Result := left
      else
        Result := IRAppend(IR_LOAD_MEM, left, -1, -1, 0, ASTTk[node]);
    end;

    AN_PTR_CAST:
    begin
      { A cast PType(expr) is purely a type-tag change — the value in rax is
        already the pointer. No load-through-memory here. }
      Result := IRLowerAST(ASTLeft[node]);
      { PChar(stringExpr): an inline-length string value points at its 8-byte
        length prefix; a C `const char*` needs the char data, which sits at +8
        (now guaranteed NUL-terminated by InternStr). Sentinel -2 in ASTIVal
        marks the PChar/PAnsiChar adapter; only adjust for inline-string
        operands so PChar(somePointer) stays a pure reinterpret. }
      if (ASTIVal[node] = -2) and (ASTTk[ASTLeft[node]] = Ord(tyString)) then
      begin
        right := IRAppend(IR_CONST_INT, -1, -1, -1, 8, Ord(tyInteger));
        Result := IRAppend(IR_BINOP, Result, right, Ord(tkPlus), 0, Ord(tyPointer));
      end;
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

    AN_CLASSREF:
    begin
      { class index in IRA; codegen emits the RTTI-blob address (PClassRTTI). }
      Result := IRAppend(IR_CLASSREF, Integer(ASTIVal[node]), -1, -1, 0, Ord(tyPointer));
    end;

    AN_METHODREF:
    begin
      { Outside an assignment to a TMethod target we can only surface the code
        half; the proper 16-byte store lives in AN_ASSIGN. }
      Result := IRAppend(IR_PROCADDR, Integer(ASTIVal[node]), -1, -1, 0, Ord(tyPointer));
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
        Result := IRAppendCall(cpi, first, -1, ASTTk[node]);
      end
      else if (ASTIVal[node] <> Ord(tkIn)) and
              ((IntToTypeKind(ASTTk[ASTLeft[node]]) = tySet) or
               (IntToTypeKind(ASTTk[ASTRight[node]]) = tySet)) then
      begin
        left := IRLowerAST(ASTLeft[node]);
        right := IRLowerAST(ASTRight[node]);
        if (ASTIVal[node] = Ord(tkEq)) or (ASTIVal[node] = Ord(tkNeq)) or
           (ASTIVal[node] = Ord(tkLt)) or (ASTIVal[node] = Ord(tkLe)) or
           (ASTIVal[node] = Ord(tkGt)) or (ASTIVal[node] = Ord(tkGe)) then
          Result := IRAppend(IR_SET_CMP, left, right, Integer(ASTIVal[node]), 0, Ord(tyBoolean))
        else
        begin
          BSSSize := AlignTo(BSSSize, 8);
          idx := BSSSize;
          Inc(BSSSize, 32);
          Result := IRAppend(IR_SET_BINOP, left, right, Integer(ASTIVal[node]), idx, Ord(tySet));
        end;
      end
      else if (IntToTypeKind(ASTTk[ASTLeft[node]]) = tyVariant) or
              (IntToTypeKind(ASTTk[ASTRight[node]]) = tyVariant) then
      begin
        { Variant operand: make both sides variant addresses (box a scalar side
          into a temp), then IR_VAR_BINOP. Comparison -> Boolean in rax;
          arithmetic -> a Variant result in a fresh BSS temp (addr in rax). }
        if IntToTypeKind(ASTTk[ASTLeft[node]]) = tyVariant then
          left := IRLowerAddress(ASTLeft[node])
        else
        begin
          savedProc := CurProc;
          CurProc := -1;
          value := AllocVar('', tyVariant);
          CurProc := savedProc;
          left := IRAppend(IR_VAR_BOX, IRAppend(IR_LEA, value, -1, -1, 0, Ord(tyPointer)),
                           IRLowerAST(ASTLeft[node]), Ord(IntToTypeKind(ASTTk[ASTLeft[node]])), 0, Ord(tyVariant));
        end;
        if IntToTypeKind(ASTTk[ASTRight[node]]) = tyVariant then
          right := IRLowerAddress(ASTRight[node])
        else
        begin
          savedProc := CurProc;
          CurProc := -1;
          value := AllocVar('', tyVariant);
          CurProc := savedProc;
          right := IRAppend(IR_VAR_BOX, IRAppend(IR_LEA, value, -1, -1, 0, Ord(tyPointer)),
                            IRLowerAST(ASTRight[node]), Ord(IntToTypeKind(ASTTk[ASTRight[node]])), 0, Ord(tyVariant));
        end;
        item := Integer(ASTIVal[node]);
        if (item = Ord(tkEq)) or (item = Ord(tkNeq)) or (item = Ord(tkLt)) or
           (item = Ord(tkLe)) or (item = Ord(tkGt)) or (item = Ord(tkGe)) then
          Result := IRAppend(IR_VAR_BINOP, left, right, item, 0, Ord(tyBoolean))
        else
        begin
          BSSSize := AlignTo(BSSSize, 8);
          idx := BSSSize;
          Inc(BSSSize, 16);
          Result := IRAppend(IR_VAR_BINOP, left, right, item, idx, Ord(tyVariant));
        end;
      end
      else
      begin
        if ((ASTIVal[node] = Ord(tkPlus)) or (ASTIVal[node] = Ord(tkMinus))) and
           (IntToTypeKind(ASTTk[ASTLeft[node]]) = tyPointer) and
           TypeIsOrdinal(IntToTypeKind(ASTTk[ASTRight[node]])) then
        begin
          left := IRLowerAST(ASTLeft[node]);
          right := IRLowerAST(ASTRight[node]);
          elemSize := IRPointerStride(ASTLeft[node]);
          if elemSize > 1 then
          begin
            item := IRAppend(IR_CONST_INT, -1, -1, -1, elemSize, Ord(tyInteger));
            right := IRAppend(IR_BINOP, right, item, Ord(tkStar), 0, Ord(tyInteger));
          end;
          Result := IRAppend(IR_BINOP, left, right, Integer(ASTIVal[node]), 0, Ord(tyPointer));
        end
        else if (ASTIVal[node] = Ord(tkPlus)) and
                TypeIsOrdinal(IntToTypeKind(ASTTk[ASTLeft[node]])) and
                (IntToTypeKind(ASTTk[ASTRight[node]]) = tyPointer) then
        begin
          left := IRLowerAST(ASTRight[node]);
          right := IRLowerAST(ASTLeft[node]);
          elemSize := IRPointerStride(ASTRight[node]);
          if elemSize > 1 then
          begin
            item := IRAppend(IR_CONST_INT, -1, -1, -1, elemSize, Ord(tyInteger));
            right := IRAppend(IR_BINOP, right, item, Ord(tkStar), 0, Ord(tyInteger));
          end;
          Result := IRAppend(IR_BINOP, left, right, Ord(tkPlus), 0, Ord(tyPointer));
        end
        else
        begin
          left := IRLowerAST(ASTLeft[node]);
          right := IRLowerAST(ASTRight[node]);
          Result := IRAppend(IR_BINOP, left, right, Integer(ASTIVal[node]), 0, ASTTk[node]);
        end;
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
      if ASTKind[ASTRight[node]] = AN_METHODREF then
      begin
        { @obj.method assigned to a TMethod target: write the two pointers
          directly — Code at field+0, Data at field+8. }
        left := ASTRight[node];
        leftAddr := IRLowerAddress(ASTLeft[node]);
        value := IRAppend(IR_PROCADDR, Integer(ASTIVal[left]), -1, -1, 0, Ord(tyPointer));
        IRAppend(IR_STORE_MEM, leftAddr, value, -1, 0, Ord(tyPointer));
        right := IRLowerAddress(ASTLeft[node]);
        item := IRAppend(IR_CONST_INT, -1, -1, -1, 8, Ord(tyInteger));
        outNode := IRAppend(IR_BINOP, right, item, Ord(tkPlus), 0, Ord(tyPointer));
        seq := IRLowerAST(ASTLeft[left]);
        Result := IRAppend(IR_STORE_MEM, outNode, seq, -1, 0, Ord(tyPointer));
      end
      else if IntToTypeKind(ASTTk[ASTLeft[node]]) = tySet then
      begin
        leftAddr := IRLowerAddress(ASTLeft[node]);
        right := IRLowerAST(ASTRight[node]);
        Result := IRAppend(IR_SET_COPY, leftAddr, right, -1, 0, Ord(tySet));
      end
      else if (ASTKind[ASTLeft[node]] = AN_IDENT) and
              Syms[ASTIVal[ASTLeft[node]]].IsArray and
              (Syms[ASTIVal[ASTLeft[node]]].ArrLen = -1) then
      begin
        value := IRLowerAST(ASTRight[node]);
        Result := IRAppend(IR_STORE_SYM, ASTIVal[ASTLeft[node]], value, -1, 0,
                           ASTTk[ASTLeft[node]]);
      end
      else if (IntToTypeKind(ASTTk[ASTLeft[node]]) = tyRecord) or
              ((ASTKind[ASTLeft[node]] = AN_IDENT) and
               (Syms[ASTIVal[ASTLeft[node]]].TypeKind = tyRecord)) then
      begin
        { A record-typed destination. The function-name result form
          (`FuncName := rec`) leaves the LHS ASTTk unset (0), so fall back to
          the symbol's TypeKind; without this the scalar store path below
          copies only the first qword and truncates the record. }
        leftAddr := IRLowerAddress(ASTLeft[node]);
        if rhsIsLValue then
          right := IRLowerAddress(ASTRight[node])
        else
          right := IRLowerAST(ASTRight[node]);
        if RecordHasManagedFields(ResolveNodeRec(ASTLeft[node])) then
          { ARC-correct copy: retain source managed fields, release the old
            destination ones, then bulk-copy. }
          Result := IRAppend(IR_COPY_REC_MANAGED, leftAddr, right,
                             ResolveNodeRec(ASTLeft[node]),
                             RecSize(ResolveNodeRec(ASTLeft[node])), Ord(tyRecord))
        else
          Result := IRAppend(IR_COPY_REC, leftAddr, right, -1,
                             RecSize(ResolveNodeRec(ASTLeft[node])), Ord(tyRecord));
      end
      else if IntToTypeKind(ASTTk[ASTLeft[node]]) = tyVariant then
      begin
        { Variant target. IRC carries the source kind: tyVariant => full 16-byte
          copy; any scalar kind => box it (tag + payload) via IR_VAR_STORE. }
        leftAddr := IRLowerAddress(ASTLeft[node]);
        if IntToTypeKind(ASTTk[ASTRight[node]]) = tyVariant then
        begin
          if rhsIsLValue then
            right := IRLowerAddress(ASTRight[node])
          else
            right := IRLowerAST(ASTRight[node]);
          Result := IRAppend(IR_VAR_STORE, leftAddr, right, Ord(tyVariant), 0, Ord(tyVariant));
        end
        else
        begin
          value := IRLowerAST(ASTRight[node]);
          Result := IRAppend(IR_VAR_STORE, leftAddr, value,
                             Ord(IntToTypeKind(ASTTk[ASTRight[node]])), 0, Ord(tyVariant));
        end;
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
          begin
            varIdx := Procs[CurProc].RetSymIdx;
            if Syms[varIdx].TypeKind = tySet then
            begin
              leftAddr := IRAppend(IR_LEA, varIdx, -1, -1, 0, Ord(tyPointer));
              last := IRAppend(IR_SET_COPY, leftAddr, value, -1, 0, Ord(tySet));
            end
            else if Syms[varIdx].TypeKind = tyRecord then
            begin
              leftAddr := IRAppend(IR_LEA, varIdx, -1, -1, 0, Ord(tyPointer));
              { COPY_REC needs the SOURCE ADDRESS. For an lvalue record source
                IRLowerAST would emit IR_LOAD_SYM (first 8 bytes loaded as a
                value), which COPY_REC would then misread as a pointer and
                segfault. Take its address instead, mirroring assignment. }
              rhsIsLValue := (ASTKind[ASTLeft[node]] = AN_IDENT) or
                             (ASTKind[ASTLeft[node]] = AN_FIELD) or
                             (ASTKind[ASTLeft[node]] = AN_INDEX) or
                             (ASTKind[ASTLeft[node]] = AN_DEREF);
              if rhsIsLValue then
                right := IRLowerAddress(ASTLeft[node])
              else
                right := value;
              if RecordHasManagedFields(Syms[varIdx].RecName) then
                last := IRAppend(IR_COPY_REC_MANAGED, leftAddr, right,
                                 Syms[varIdx].RecName,
                                 RecSize(Syms[varIdx].RecName), Ord(tyRecord))
              else
                last := IRAppend(IR_COPY_REC, leftAddr, right, -1,
                                 RecSize(Syms[varIdx].RecName), Ord(tyRecord));
            end
            else if Syms[varIdx].TypeKind = tyVariant then
            begin
              leftAddr := IRAppend(IR_LEA, varIdx, -1, -1, 0, Ord(tyPointer));
              if IntToTypeKind(ASTTk[ASTLeft[node]]) = tyVariant then
              begin
                rhsIsLValue := (ASTKind[ASTLeft[node]] = AN_IDENT) or
                               (ASTKind[ASTLeft[node]] = AN_FIELD) or
                               (ASTKind[ASTLeft[node]] = AN_INDEX) or
                               (ASTKind[ASTLeft[node]] = AN_DEREF);
                if rhsIsLValue then
                  right := IRLowerAddress(ASTLeft[node])
                else
                  right := value;
                last := IRAppend(IR_VAR_STORE, leftAddr, right, Ord(tyVariant), 0, Ord(tyVariant));
              end
              else
              begin
                last := IRAppend(IR_VAR_STORE, leftAddr, value,
                                 Ord(IntToTypeKind(ASTTk[ASTLeft[node]])), 0, Ord(tyVariant));
              end;
            end
            else
              last := IRAppend(IR_STORE_SYM, varIdx, value, -1, 0, ASTTk[ASTLeft[node]]);
          end;
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
      if cpi = -102 then
      begin
        { SetLength. Nested dynamic arrays (root depth >= 2) take a
          dedicated path operating on the target slot ADDRESS with a depth-aware
          element stride. Plain depth-1 arrays fall through to the generic
          special-call lowering (managed strings/records + COW). }
        slTargetAST := ASTLeft[ASTLeft[node]];
        slCountAST  := ASTLeft[ASTRight[ASTLeft[node]]];
        slRootSym := NodeDynBaseSym(slTargetAST);
        if (slRootSym >= 0) and (SymDynDepth[slRootSym] >= 2) then
        begin
          slDepth := NodeDynDepth(slTargetAST);
          slTargetAddr := IRLowerAddress(slTargetAST);
          slCountNode := IRLowerAST(slCountAST);
          Result := IRAppend(IR_SETLEN_DYN, slTargetAddr, slCountNode, slDepth,
                             slRootSym, Ord(tyPointer));
          Exit;
        end;
      end;
      if cpi = -201 then
      begin
        argVal := ASTLeft[item];
        argTk := IntToTypeKind(ASTTk[argVal]);
        if argTk = tyVariant then
        begin
          pi := FindProc('VariantToStr');
          if pi < 0 then Error('str: VariantToStr builtin not loaded');
          value := IRLowerAddress(argVal);
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyVariant));
          Result := IRAppendCall(pi, argNode, -1, Ord(tyAnsiString));
          Exit;
        end;
        if TypeIsFloat(argTk) then
        begin
          { str(float): format via the RTL FloatToStr (natural decimal). }
          pi := FindProc('FloatToStr');
          if pi < 0 then Error('str: builtin unit not loaded');
          value := IRLowerAST(argVal);                       { double bits in rax }
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyDouble));
          Result := IRAppendCall(pi, argNode, -1, Ord(tyString));
          Exit;
        end;
        value := IRLowerAST(argVal);

        pi := FindProc('StrInt');
        if pi < 0 then Error('str: builtin unit not loaded');

        argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(argTk));
        first := argNode;

        zeroVal := IRAppend(IR_CONST_INT, 0, -1, -1, 0, Ord(tyInteger));
        argNode2 := IRAppend(IR_ARG, zeroVal, -1, -1, 0, Ord(tyInteger));
        IRB[argNode] := argNode2;

        Result := IRAppendCall(pi, first, -1, Ord(tyString));
        Exit;
      end;
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

        { Auto const char* marshalling: a string argument passed to a Pointer
          parameter gets the same +8 length-prefix skip as an explicit PChar()
          cast, so C bindings pass a Pascal string without PChar() boilerplate.
          The string data at Offset+8 is NUL-terminated by InternStr. }
        if (not isRefArg) and (cpi >= 0) and (pathIdx < Procs[cpi].ParamCount) and
           (Procs[cpi].Params[pathIdx].TypeKind = tyPointer) and
           (IntToTypeKind(ASTTk[ASTLeft[item]]) = tyString) then
        begin
          right := IRAppend(IR_CONST_INT, -1, -1, -1, 8, Ord(tyInteger));
          value := IRAppend(IR_BINOP, value, right, Ord(tkPlus), 0, Ord(tyPointer));
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyPointer));
        end
        else
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, ASTTk[ASTLeft[item]]);
        if first < 0 then first := argNode
        else IRB[last] := argNode;
        last := argNode;
        item := ASTRight[item];
        Inc(pathIdx);
      end;
      if ASTLiftedVar[node] >= 0 then
      begin
        callRetType := Procs[ASTIVal[node]].RetType;
        callVal := IRAppendCall(ASTIVal[node], first, classIdx, Ord(callRetType));
        IRIVal[callVal] := 1;
        Result := IRAppend(IR_LOAD_SYM, ASTLiftedVar[node], -1, -1, 0, ASTTk[node]);
      end
      else
        Result := IRAppendCall(ASTIVal[node], first, classIdx, ASTTk[node]);
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
          { A Variant arg writes its slot address; codegen reads tag+payload and
            dispatches at runtime (IRTk stays tyVariant). }
          if IntToTypeKind(ASTTk[ASTLeft[item]]) = tyVariant then
            value := IRLowerAddress(ASTLeft[item])
          else
            value := IRLowerAST(ASTLeft[item]);
          outNode := IRAppend(IR_WRITE, value, ASTIVal[item], ASTSOffset[item], 0, Ord(IntToTypeKind(ASTTk[ASTLeft[item]])));
        end
        else if ASTKind[item] = AN_PAIR then
        begin
          value := IRLowerAST(ASTLeft[item]);
          outNode := IRAppend(IR_WRITE, value, -1, -1, 0, IRTk[value]);
        end
        else if IntToTypeKind(ASTTk[item]) = tyVariant then
        begin
          value := IRLowerAddress(item);
          outNode := IRAppend(IR_WRITE, value, -1, -1, 0, Ord(tyVariant));
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
        argNode := IRAppend(IR_ARG, value, -1, -1, 0, ASTTk[ASTLeft[item]]);
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
