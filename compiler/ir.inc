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
  CurLowerLine := 0;
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
  IRLine[IRCount] := CurLowerLine;
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
    IR_SETLEN_STR: Result := 'setlen_str';
    IR_DYNUNIQUE: Result := 'dynunique';
    IR_SLOTADDR: Result := 'slotaddr';
    IR_ZERO_SYM: Result := 'zero_sym';
    IR_DEFAULT_MEM: Result := 'default_mem';
    IR_READ_DISCARD: Result := 'read_discard';
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
    IR_STORE_DYN: Result := 'store_dyn';
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
    IR_SYSCALL: Result := 'syscall';
    IR_COSWITCH: Result := 'coswitch';
    IR_YIELD: Result := 'yield';
    IR_CALL_IND: Result := 'call_ind';
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
    if (IRTk[i] < 0) or (IRTk[i] > Ord(tyFixedString)) then
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
        if (op < 0) or ((op > Ord(tkShl)) and (op <> Ord(tkXor))) then
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

      IR_DEFAULT_MEM:
        IRRequireNode(IRA[i], 'default_mem dest');

      IR_ZERO_SYM:
        { IRA = symbol index of the slot to nil/zero (e.g. a managed lazy var
          before its initializer assign). Not a node reference. }
        if (IRA[i] < 0) or (IRA[i] >= SymCount) then
          Error('invalid symbol in zero_sym');

      IR_READ_DISCARD:
        begin end;

      IR_DYNDATA:
        if (IRA[i] < 0) or (IRA[i] >= SymCount) then
          Error('invalid symbol in dyndata');

      IR_SETLEN_DYN:
      begin
        IRRequireNode(IRA[i], 'setlen_dyn target');
        IRRequireNode(IRB[i], 'setlen_dyn count');
      end;

      IR_SETLEN_STR:
      begin
        IRRequireNode(IRA[i], 'setlen_str target');
        IRRequireNode(IRB[i], 'setlen_str count');
      end;

      IR_DYNUNIQUE:
        { IRA = slot-address node; IRB carries the depth integer, not a node. }
        IRRequireNode(IRA[i], 'dynunique slot');

      IR_SLOTADDR:
        if (IRA[i] < 0) or (IRA[i] >= SymCount) then
          Error('invalid symbol in slotaddr');

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

      IR_STORE_DYN:
      begin
        IRRequireNode(IRA[i], 'store_dyn slot address');
        IRRequireNode(IRB[i], 'store_dyn value');
      end;

      IR_ARG:
      begin
        IRRequireNode(IRA[i], 'arg value');
        IRRequireOptionalNode(IRB[i], 'next arg');
      end;

      IR_SYSCALL:
        IRRequireNode(IRA[i], 'syscall number arg');

      IR_COSWITCH:
        IRRequireNode(IRA[i], 'coswitch first arg');

      IR_YIELD:
        IRRequireNode(IRA[i], 'yield value');

      IR_CALL_IND:
      begin
        IRRequireNode(IRA[i], 'call_ind callee');
        IRRequireOptionalNode(IRB[i], 'call_ind first arg');
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

      IR_VMTADDR:
        if (IRA[i] < 0) or (IRA[i] >= UClsCount) then
          Error('invalid class index in vmtaddr');

      IR_IMTADDR:
        if (IRA[i] < 0) or (IRA[i] >= IMTCount) then
          Error('invalid IMT index in imtaddr');

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
function IRMaterializeIntfCast(node: Integer; doTrap: Boolean): Integer; forward;

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
    else if (IRKind[irNode] = IR_VIRTUAL_CALL) or (IRKind[irNode] = IR_CALL_IND) then
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
    AN_FIELD:
      Result := RecFieldDynDepth(ResolveNodeRec(ASTLeft[node]), GetASTIdentName(node));
    AN_INDEX:
      begin
        bd := NodeDynDepth(ASTLeft[node]);
        if bd > 0 then Result := bd - 1
        else if (ASTKind[ASTLeft[node]] = AN_IDENT) and
                (Syms[ASTIVal[ASTLeft[node]]].IsArray) and
                (Syms[ASTIVal[ASTLeft[node]]].ArrLen <> -1) and
                (SymElemDynDepth[ASTIVal[ASTLeft[node]]] > 0) then
          { Indexing a FIXED array whose element is a dynamic array
            (`array[..] of TA`): the element is a dyn array of this depth. }
          Result := SymElemDynDepth[ASTIVal[ASTLeft[node]]];
      end;
  end;
end;

function NodeDynBaseTk(node: Integer): TTypeKind;
{ Base element type of a (possibly nested) dynamic-array expression, walking to
  the root symbol or field. tyUnknown if not a dynamic array. }
begin
  Result := tyUnknown;
  if node < 0 then Exit;
  if ASTKind[node] = AN_IDENT then
  begin
    if Syms[ASTIVal[node]].IsArray and (Syms[ASTIVal[node]].ArrLen = -1) then
      Result := Syms[ASTIVal[node]].ElemType
    else if Syms[ASTIVal[node]].IsArray and (Syms[ASTIVal[node]].ArrLen <> -1) and
            (SymElemDynDepth[ASTIVal[node]] > 0) then
      { fixed array of a dyn-array element: element base type lives in ElemType }
      Result := Syms[ASTIVal[node]].ElemType;
  end
  else if ASTKind[node] = AN_FIELD then
    Result := RecFieldType(ResolveNodeRec(ASTLeft[node]), GetASTIdentName(node))
  else if ASTKind[node] = AN_INDEX then
    Result := NodeDynBaseTk(ASTLeft[node]);
end;

function NodeIsManagedString(node: Integer): Boolean;
{ True if the lvalue node denotes a managed AnsiString (a string symbol, record/
  class field, indexed element, or pointer deref of one). Drives the address-
  based SetLength path (IR_SETLEN_STR) so a field / var-param field needs no
  symbol reconstruction. Frozen inline strings (tyString) return False. }
var rec: Integer;
begin
  Result := False;
  if node < 0 then Exit;
  case ASTKind[node] of
    AN_IDENT:
      { A scalar managed-string variable — NOT a dynamic array of strings (whose
        symbol also carries tyAnsiString as its element type). }
      Result := (Syms[ASTIVal[node]].TypeKind = tyAnsiString) and
                not Syms[ASTIVal[node]].IsArray;
    AN_FIELD:
      { RecFieldType reports the ELEMENT type for an array field, so an
        `array of string` field also reads back tyAnsiString — exclude it via the
        field's dyn-array depth so only a scalar string field matches. }
      begin
        rec := ResolveNodeRec(ASTLeft[node]);
        if rec <> REC_NONE then
          Result := (RecFieldType(rec, GetASTIdentName(node)) = tyAnsiString) and
                    (RecFieldDynDepth(rec, GetASTIdentName(node)) = 0);
      end;
    AN_INDEX, AN_DEREF:
      { An indexed element / pointer deref of a managed string tags tyAnsiString,
        but indexing a multidimensional array (`s[i]` where s is `array of array
        of AnsiString`) yields a SUB-ARRAY that also tags tyAnsiString (its base
        element type). Require dyn depth 0 so only a true scalar string matches. }
      Result := (IntToTypeKind(ASTTk[node]) = tyAnsiString) and
                (NodeDynDepth(node) = 0);
  end;
end;

function NodeDynBaseRec(node: Integer): Integer;
{ Base element record id of a (possibly nested) dynamic-array expression. }
begin
  Result := REC_NONE;
  if node < 0 then Exit;
  if ASTKind[node] = AN_IDENT then
    Result := Syms[ASTIVal[node]].ElemRecName
  else if ASTKind[node] = AN_FIELD then
    Result := RecFieldRecId(ResolveNodeRec(ASTLeft[node]), GetASTIdentName(node))
  else if ASTKind[node] = AN_INDEX then
    Result := NodeDynBaseRec(ASTLeft[node]);
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

function IRBitMask(width: Integer): Int64;
var i: Integer; m: Int64;
begin
  m := 0;
  for i := 0 to width - 1 do
    m := (m shl 1) or 1;
  Result := m;
end;

function IRBitStorageTk(bytes: Integer): TTypeKind;
begin
  if bytes <= 1 then Result := tyUInt8
  else if bytes = 2 then Result := tyUInt16
  else Result := tyUInt32;
end;

function IRLowerBitFieldRead(fieldNode: Integer; storageAddr: Integer; storageTk: TTypeKind): Integer;
var recId, width, shift: Integer; fieldName: AnsiString; value, maskNode: Integer;
begin
  recId := ResolveNodeRec(ASTLeft[fieldNode]);
  fieldName := GetASTIdentName(fieldNode);
  width := RecFieldBitWidth(recId, fieldName);
  shift := RecFieldBitShift(recId, fieldName);
  storageTk := IRBitStorageTk(RecFieldBitBytes(recId, fieldName));
  value := IRAppend(IR_LOAD_MEM, storageAddr, -1, -1, 0, Ord(storageTk));
  if shift > 0 then
    value := IRAppend(IR_BINOP, value,
                      IRAppend(IR_CONST_INT, -1, -1, -1, shift, Ord(tyInteger)),
                      Ord(tkIdent), 0, Ord(storageTk));
  maskNode := IRAppend(IR_CONST_INT, -1, -1, -1, IRBitMask(width), Ord(storageTk));
  Result := IRAppend(IR_BINOP, value, maskNode, Ord(tkAnd), 0, Ord(storageTk));
end;

function IRLowerBitFieldStore(fieldNode, rhsValue: Integer; storageTk: TTypeKind): Integer;
var recId, width, shift, addr, oldVal, clearMask, newBits, maskedNew, maskNode: Integer;
    fieldName: AnsiString; mask, shiftedMask: Int64;
begin
  recId := ResolveNodeRec(ASTLeft[fieldNode]);
  fieldName := GetASTIdentName(fieldNode);
  width := RecFieldBitWidth(recId, fieldName);
  shift := RecFieldBitShift(recId, fieldName);
  storageTk := IRBitStorageTk(RecFieldBitBytes(recId, fieldName));
  addr := IRLowerAddress(fieldNode);
  mask := IRBitMask(width);
  shiftedMask := mask shl shift;
  oldVal := IRAppend(IR_LOAD_MEM, addr, -1, -1, 0, Ord(storageTk));
  clearMask := IRAppend(IR_BINOP, oldVal,
                        IRAppend(IR_CONST_INT, -1, -1, -1, not shiftedMask, Ord(storageTk)),
                        Ord(tkAnd), 0, Ord(storageTk));
  maskedNew := IRAppend(IR_BINOP, rhsValue,
                        IRAppend(IR_CONST_INT, -1, -1, -1, mask, Ord(storageTk)),
                        Ord(tkAnd), 0, Ord(storageTk));
  if shift > 0 then
    maskedNew := IRAppend(IR_BINOP, maskedNew,
                          IRAppend(IR_CONST_INT, -1, -1, -1, shift, Ord(tyInteger)),
                          Ord(tkShl), 0, Ord(storageTk));
  newBits := IRAppend(IR_BINOP, clearMask, maskedNew, Ord(tkOr), 0, Ord(storageTk));
  Result := IRAppend(IR_STORE_MEM, addr, newBits, -1, 0, Ord(storageTk));
end;

function IRLowerAddress(node: Integer): Integer;
var baseNode, baseAddr, indexNode, lo, elemSize: Integer;
    fieldName: AnsiString;
    isArr: Boolean;
    tk: TTypeKind;
    baseDynDepth, dynRootSym, dynBaseRec, slotAddrNode: Integer;
    dynBaseTk: TTypeKind;
    recName, aliasIdx: Integer;
begin
  { Address of an address-of: `&(&x)`. In valid C this only arises from array
    decay (`&arr` where arr is an array yields arr's address), so the address of
    that is the operand's own address. Collapse one level. }
  if ASTKind[node] = AN_ADDR then
  begin
    Result := IRLowerAddress(ASTLeft[node]);
    Exit;
  end;
  { `&function` — a function's address IS the function-pointer value (C `&f == f`).
    The AN_PROCADDR value node already yields the code address. }
  if ASTKind[node] = AN_PROCADDR then
  begin
    Result := IRLowerAST(node);
    Exit;
  end;
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
    { C array-of-pointer indexing followed by another subscript:
      `names[0][1]`. The base `names[0]` is a pointer VALUE stored inside an
      array slot; using IRLowerAddress(base) would index from the slot address
      itself. Load the pointer value, then index the pointed-to element type. }
    if CProgramMode and (ASTKind[baseNode] = AN_INDEX) and
       (IntToTypeKind(ASTTk[baseNode]) = tyPointer) then
    begin
      indexNode := IRLowerAST(ASTRight[node]);
      tk := IntToTypeKind(ASTTk[node]);
      if tk = tyRecord then
        elemSize := RecSize(ResolveNodeRec(node))
      else
        elemSize := TypeSize(tk);
      baseAddr := IRLowerAST(baseNode);
      Result := IRAppend(IR_INDEX, baseAddr, indexNode, 0, elemSize, ASTTk[node]);
      Exit;
    end;
    { Computed pointer-value indexing, e.g. C `(cond ? a : b)[i]`. The base
      expression yields the pointer value; taking IRLowerAddress(base) would ask
      for the address of a non-lvalue expression such as AN_TERNARY. }
    if CProgramMode and
       (ASTKind[baseNode] <> AN_IDENT) and
       (ASTKind[baseNode] <> AN_FIELD) and
       (ASTKind[baseNode] <> AN_PTR_CAST) and
       (ASTKind[baseNode] <> AN_INDEX) and
       IRNodePointerBase(baseNode) then
    begin
      indexNode := IRLowerAST(ASTRight[node]);
      elemSize := IRPointerStride(baseNode);
      baseAddr := IRLowerAST(baseNode);
      Result := IRAppend(IR_INDEX, baseAddr, indexNode, 0, elemSize, ASTTk[node]);
      Exit;
    end;
    { Nested dynamic-array indexing: base is a nested dyn array (depth>=2) or a
      sub-array element (an AN_INDEX whose value is still a dyn array). The base
      handle is wrapped in IR_DYNUNIQUE, which loads the data pointer on a read
      and clones-if-shared (copy-on-write) on a write, decided by InLValueWrite
      at codegen time — exactly as the depth-1 path does for the outer array, so
      writing through one alias never mutates another at any depth. Plain depth-1
      arrays keep the path below. }
    baseDynDepth := NodeDynDepth(baseNode);
    if (baseDynDepth >= 2) or
       ((baseDynDepth = 1) and ((ASTKind[baseNode] = AN_INDEX) or
                                (ASTKind[baseNode] = AN_FIELD))) then
    begin
      { Base element metadata, walking to the root symbol OR record/class field
        (a dynamic-array field is just another handle slot). }
      dynBaseTk := NodeDynBaseTk(baseNode);
      dynBaseRec := NodeDynBaseRec(baseNode);
      elemSize := DynElemSize(baseDynDepth, dynBaseTk, dynBaseRec);
      { Address of the slot holding this level's array handle. For a variable
        root the slot is the variable itself; for a field root it is the field
        slot in the object; for a sub-array it is the element address in the
        parent's data (its own IR_DYNUNIQUE chain, so COW recurses upward). }
      if ASTKind[baseNode] = AN_IDENT then
        slotAddrNode := IRAppend(IR_SLOTADDR, ASTIVal[baseNode], -1, -1, 0, Ord(tyPointer))
      else
        slotAddrNode := IRLowerAddress(baseNode);
      baseAddr := IRAppend(IR_DYNUNIQUE, slotAddrNode, baseDynDepth, dynBaseRec,
                           elemSize, Ord(dynBaseTk));
      indexNode := IRLowerAST(ASTRight[node]);
      if baseDynDepth >= 2 then
        Result := IRAppend(IR_INDEX, baseAddr, indexNode, 0, elemSize, Ord(tyPointer))
      else
        Result := IRAppend(IR_INDEX, baseAddr, indexNode, 0, elemSize, Ord(dynBaseTk));
      Exit;
    end;
    { Indexing a string LITERAL or untyped string const (AN_STR_LIT): its VALUE
      is a pointer to the frozen [len][data] blob (data at +8), and it has no
      addressable slot — so index it like a frozen string but with the literal's
      value as the base (lo=-7 puts index 1 at data[0]). Without this,
      IRLowerAddress(AN_STR_LIT) yields a wrong base and s[i] reads garbage / the
      whole string (bug-const-string-index-miscompiles). }
    if ASTKind[baseNode] = AN_STR_LIT then
    begin
      baseAddr := IRLowerAST(baseNode);
      indexNode := IRLowerAST(ASTRight[node]);
      Result := IRAppend(IR_INDEX, baseAddr, indexNode, -7, 1, Ord(tyChar));
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
      tk := IntToTypeKind(ASTTk[baseNode]);
      recName := ResolveNodeRec(baseNode);
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
    else if TypeIsFrozenString(tk) and not isArr then
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
      else if (tk = tyFixedString) or (tk = tyShortString) then
      begin
        { array-of-string[N] element stride: the per-element frozen slot size,
          from the array symbol's capacity (matches AllocArray's sizing). }
        if ASTKind[baseNode] = AN_IDENT then
          elemSize := FrozenStrSlotSize(tk, SymStrCap[ASTIVal[baseNode]])
        else
          elemSize := FrozenStrSlotSize(tk, 0);
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

    { A FIXED array whose element is a dynamic array (`array[..] of TA`) stores a
      pointer-sized handle per slot, regardless of the element base type's own
      size — override the stride so a[i] addresses the right slot, and tag the
      slot-address node tyPointer (like a nested dyn sub-array element) so Length
      / indexing treat a[i] as a dyn-array handle, not a base value. }
    if isArr and (ASTKind[baseNode] = AN_IDENT) and
       Syms[ASTIVal[baseNode]].IsArray and (Syms[ASTIVal[baseNode]].ArrLen <> -1) and
       (SymElemDynDepth[ASTIVal[baseNode]] > 0) then
    begin
      elemSize := TARGET_PTR_SIZE;
      Result := IRAppend(IR_INDEX, baseAddr, indexNode, lo, elemSize, Ord(tyPointer));
      Exit;
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
    else if ((ASTKind[baseNode] = AN_CALL) or (ASTKind[baseNode] = AN_VIRTUAL_CALL))
            and (ASTTk[baseNode] = Ord(tyRecord)) then
      { Record-returning call result used as a field base (f(args).field): the
        call's IR value is the address of its hidden aggregate-result temp
        (aggregates are returned by-reference), so use it directly rather than
        trying to take the address of a call node. }
      baseAddr := IRLowerAST(baseNode)
    else
      baseAddr := IRLowerAddress(baseNode);

    recName := ResolveNodeRec(baseNode);
    fieldName := GetASTIdentName(node);
    { A dynamic-array field slot holds a heap handle (pointer); tag the address
      node tyPointer so Length / indexing treat it as a handle slot, like a
      nested sub-array element. }
    if RecFieldDynDepth(recName, fieldName) > 0 then
      Result := IRAppend(IR_FIELD, baseAddr, -1, -1, RecFieldOffset(recName, fieldName), Ord(tyPointer))
    else
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
  else if (ASTKind[node] = AN_AS_CAST) and UClsIsInterface[Integer(ASTIVal[node])] then
  begin
    { `obj as IFoo` is an interface lvalue: the address of its fat-pointer temp. }
    Result := IRAppend(IR_LEA, IRMaterializeIntfCast(node, True), -1, -1, 0, Ord(tyPointer));
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
    { This hidden aggregate-result temp is allocated during IR lowering, after the
      parser's prologue zero-init pass. If the call sits on a branch that is not
      taken (e.g. `Result := F(0); Exit` in an untaken early-exit), the temp is
      never filled, yet the proc's scope-exit cleanup would release its managed
      fields and free stack garbage. Mark it so codegen nil-inits its full extent
      before the body. }
    if (Procs[procIdx].RetType = tyRecord) and
       RecordHasManagedFields(ProcRetRecId[procIdx]) then
      SymIsHiddenArgTemp[scratchSym] := True;
    scratchAddr := IRAppend(IR_LEA, scratchSym, -1, -1, 0, Ord(tyPointer));
    Result := IRAppend(IR_CALL, procIdx, firstArg, scratchAddr, 0, tk);
  end
  else
    Result := IRAppend(IR_CALL, procIdx, firstArg, classIdx, 0, tk);
end;

function IRNodePointerBase(node: Integer): Boolean;
begin
  Result := IntToTypeKind(ASTTk[node]) = tyPointer;
  if CProgramMode and not Result and
     (IntToTypeKind(ASTTk[node]) <> tyInt64) then
    Result := CNodeDecaysToPointer(node);
end;

function IRPointerStride(node: Integer): Integer;
var elemTk: TTypeKind; recId, aliasIdx: Integer; fieldName: AnsiString;
begin
  elemTk := tyUnknown;
  recId := REC_NONE;
  if ASTKind[node] = AN_IDENT then
  begin
    if Syms[ASTIVal[node]].IsArray and (Syms[ASTIVal[node]].ArrLen <> -1) then
    begin
      elemTk := Syms[ASTIVal[node]].ElemType;
      recId := Syms[ASTIVal[node]].ElemRecName;
    end
    else
    begin
      elemTk := Syms[ASTIVal[node]].PtrElemTk;
      recId := Syms[ASTIVal[node]].PtrElemRec;
    end;
  end
  else if ASTKind[node] = AN_FIELD then
  begin
    recId := ResolveNodeRec(ASTLeft[node]);
    fieldName := GetASTIdentName(node);
    if CProgramMode and RecFieldIsArray(recId, fieldName) and
       (RecFieldDynDepth(recId, fieldName) = 0) then
    begin
      elemTk := RecFieldType(recId, fieldName);
      recId := ResolveNodeRec(node);
    end
    else
    begin
      elemTk := RecFieldPtrElemTk(recId, fieldName);
      recId := RecFieldPtrElemRec(recId, fieldName);
    end;
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
    if IRNodePointerBase(ASTLeft[node]) then
      Result := IRPointerStride(ASTLeft[node])
    else
      Result := IRPointerStride(ASTRight[node]);
    Exit;
  end
  else if ASTKind[node] = AN_TERNARY then
  begin
    if (ASTRight[node] >= 0) and IRNodePointerBase(ASTLeft[ASTRight[node]]) then
      Result := IRPointerStride(ASTLeft[ASTRight[node]])
    else if (ASTRight[node] >= 0) and IRNodePointerBase(ASTRight[ASTRight[node]]) then
      Result := IRPointerStride(ASTRight[ASTRight[node]]);
    Exit;
  end
  else if ASTKind[node] = AN_CALL then
  begin
    if (ASTIVal[node] >= 0) and
       (Procs[ASTIVal[node]].RetType = tyPointer) then
      elemTk := IntToTypeKind(ProcRetPtrElemTk[ASTIVal[node]]);
  end
  else if ASTKind[node] = AN_INCDEC then
  begin
    Result := IRPointerStride(ASTLeft[node]);
    Exit;
  end
  else if ASTKind[node] = AN_ASSIGN then
  begin
    Result := IRPointerStride(ASTLeft[node]);
    Exit;
  end;
  if elemTk = tyRecord then
    Result := RecSize(recId)
  else if elemTk = tyUnknown then
    Result := 1
  else
    Result := TypeSize(elemTk);
end;

function IsNodePChar(node: Integer): Boolean;
var tk: TTypeKind; procIdx, recId, symId: Integer;
begin
  Result := False;
  if node < 0 then Exit;
  tk := IntToTypeKind(ASTTk[node]);
  if tk <> tyPointer then Exit;

  { 1. If it's a PChar cast node }
  if (ASTKind[node] = AN_PTR_CAST) and (ASTIVal[node] = -2) then
  begin
    Result := True;
    Exit;
  end;

  { 2. If it's an identifier }
  if ASTKind[node] = AN_IDENT then
  begin
    symId := ASTIVal[node];
    if (symId >= 0) and (symId < SymCount) then
    begin
      if (Syms[symId].TypeKind = tyPointer) and
         ((Syms[symId].PtrElemTk = tyChar) or
          (Syms[symId].PtrElemTk = tyUInt8) or
          (Syms[symId].PtrElemTk = tyInt8)) then
      begin
        Result := True;
        Exit;
      end;
    end;
  end;

  { 3. If it's a field access }
  if ASTKind[node] = AN_FIELD then
  begin
    recId := ResolveNodeRec(ASTLeft[node]);
    if recId <> REC_NONE then
    begin
      tk := RecFieldPtrElemTk(recId, GetASTIdentName(node));
      if (tk = tyChar) or (tk = tyUInt8) or (tk = tyInt8) then
      begin
        Result := True;
        Exit;
      end;
    end;
  end;

  { 4. If it's a function call }
  if ASTKind[node] = AN_CALL then
  begin
    procIdx := ASTIVal[node];
    if (procIdx >= 0) and (procIdx < ProcCount) then
    begin
      if (ProcRetPtrElemTk[procIdx] = Ord(tyChar)) or
         (ProcRetPtrElemTk[procIdx] = Ord(tyUInt8)) or
         (ProcRetPtrElemTk[procIdx] = Ord(tyInt8)) then
      begin
        Result := True;
        Exit;
      end;
    end;
  end;

  { 5. If it's a binop pointer expression }
  if ASTKind[node] = AN_BINOP then
  begin
    if IntToTypeKind(ASTTk[ASTLeft[node]]) = tyPointer then
      Result := IsNodePChar(ASTLeft[node])
    else
      Result := IsNodePChar(ASTRight[node]);
    Exit;
  end;
end;

function IsASTLValue(node: Integer): Boolean;
var symIdx: Integer;
begin
  Result := False;
  if node < 0 then Exit;
  if ASTKind[node] = AN_IDENT then
  begin
    symIdx := ASTIVal[node];
    Result := (Syms[symIdx].Kind = skLocal) or
              (Syms[symIdx].Kind = skParam) or
              (Syms[symIdx].Kind = skGlobal);
  end
  else
    Result := (ASTKind[node] = AN_FIELD) or
              (ASTKind[node] = AN_INDEX) or
              (ASTKind[node] = AN_DEREF);
end;

function IRLowerCallArg(cpi: Integer; pathIdx: Integer; argAST: Integer; isRefArg: Boolean): Integer;
var argTk: TTypeKind;
    needTemp: Boolean;
    argIsWholeArray: Boolean;
    argRecId: Integer;
    savedLastTypeRecId: Integer;
    tmpSym: Integer;
    tmpAddr: Integer;
    srcAddr: Integer;
    value: Integer;
    caCount, caElemRec, caElemSz, caSym, savedRec, caArgSym: Integer;
    caElemTk: TTypeKind;
    caIdent, caCountLit, caArg1, caArg2, caSlCall: Integer;
    caRecName: Integer; caField: AnsiString; oaEligible: Boolean;
  coerceParamSym, coerceIntfCi, coerceCast: Integer;
begin
  { A frozen-string concatenation used as a call argument builds its result in a
    272-byte buffer carved off the stack (`sub rsp, 272`, no restore), leaving the
    pointer at rsp. In a multi-argument call (a method's implicit Self plus the
    string is the common case) that punches a hole between the argument pushes, so
    the push/pop marshalling pops buffer bytes instead of the real arguments and
    corrupts the call. Spill it to a hidden local first — the automatic form of the
    `s := a + b; f(s)` workaround — and pass the local by ADDRESS: a frozen-string
    argument is the slot address (IR_LEA), not the loaded value, which for a local
    would be the inline length word. Managed AnsiString concat returns a heap
    handle (no stack temp), so this targets only frozen tyString. See
    bug-stack-corruption-inline-string-concat. }
  if (IntToTypeKind(ASTTk[argAST]) = tyString) and
     (ASTKind[argAST] = AN_BINOP) and (Integer(ASTIVal[argAST]) = Ord(tkPlus)) then
  begin
    tmpSym := AllocVar('', tyString);
    value := IRLowerAST(argAST);
    IRAppend(IR_STORE_SYM, tmpSym, value, -1, 0, Ord(tyString));
    Result := IRAppend(IR_LEA, tmpSym, -1, -1, 0, Ord(tyString));
    Exit;
  end;
  { Implicit class -> interface coercion: a class argument given to an interface
    parameter is wrapped in the same fat-pointer build as an explicit `obj as
    IFoo`, then marshalled by the ordinary record-param ABI (re-entry below). }
  if (cpi >= 0) and (pathIdx >= 0) and (pathIdx < Procs[cpi].ParamCount) and
     (Procs[cpi].Params[pathIdx].TypeKind = tyRecord) and
     (IntToTypeKind(ASTTk[argAST]) = tyClass) then
  begin
    coerceParamSym := ProcParamRecId[cpi * 16 + pathIdx];
    if (coerceParamSym >= REC_UCLASS_BASE) and
       UClsIsInterface[coerceParamSym - REC_UCLASS_BASE] then
    begin
      coerceIntfCi := coerceParamSym - REC_UCLASS_BASE;
      coerceCast := AllocNode(AN_AS_CAST);
      ASTLeft[coerceCast] := argAST;
      ASTIVal[coerceCast] := coerceIntfCi;
      ASTTk[coerceCast] := Ord(tyRecord);
      Result := IRLowerCallArg(cpi, pathIdx, coerceCast, isRefArg);
      Exit;
    end;
  end;
  { Static array -> `array of T` open param: copy the bounds-less static array into
    a fresh dyn array (with a length header) and pass that handle, so Length()/
    indexing over the param work. A `var` (by-ref) array param must alias the
    caller's array, not a copy. (Inlined here from the former TryStaticToOpenArray
    helper — kept in a helper historically to dodge a codegen landmine where the
    nested indexing expressions below lost sign-extension inside this large hot
    function; re-testing whether the sign-extension fixes this cycle cured it.) }
  if (cpi >= 0) and (pathIdx >= 0) and (pathIdx < Procs[cpi].ParamCount) and
     Procs[cpi].Params[pathIdx].IsArray and (not Procs[cpi].Params[pathIdx].IsRef) and
     (ASTKind[argAST] = AN_IDENT) then
  begin
    caArgSym := ASTIVal[argAST];
    if (caArgSym >= 0) and (caArgSym < SymCount) and Syms[caArgSym].IsArray and
       (Syms[caArgSym].ArrLen >= 0) and (Syms[caArgSym].Kind <> skParam) then
    begin
      caElemTk := Syms[caArgSym].ElemType;
      caElemRec := Syms[caArgSym].ElemRecName;
      if not ((caElemTk = tyRecord) and RecordHasManagedFields(caElemRec)) then
      begin
        caCount := Syms[caArgSym].ArrLen;
        if caElemTk = tyRecord then caElemSz := RecSize(caElemRec)
        else caElemSz := TypeSize(caElemTk);
        { Copy the fixed array into a frame/BSS-local `[len:8][data]` buffer and
          pass `&data` — the open-array param reads its length at [data-8] and
          indexes `data`. A plain byte buffer (not a heap dyn array) auto-frees
          (it is reused at the same site / private per frame), so there is no
          per-call leak and recursion is safe; managed element handles are simply
          borrowed bytes (no per-element ARC), correct for a const/value param
          whose callee only reads them. }
        caSym := AllocArray('', tyUInt8, 0, 8 + caCount * caElemSz - 1);
        SymIsHiddenArgTemp[caSym] := True;
        { length header at buf[0..7] }
        IRAppend(IR_STORE_MEM,
          IRAppend(IR_SLOTADDR, caSym, -1, -1, 0, Ord(tyPointer)),
          IRAppend(IR_CONST_INT, -1, -1, -1, caCount, Ord(tyInteger)),
          -1, 0, Ord(tyPointer));
        { data := &buf + 8; copy the fixed array's elements into it }
        value := IRAppend(IR_BINOP,
          IRAppend(IR_SLOTADDR, caSym, -1, -1, 0, Ord(tyPointer)),
          IRAppend(IR_CONST_INT, -1, -1, -1, 8, Ord(tyInteger)),
          Ord(tkPlus), 0, Ord(tyPointer));
        IRAppend(IR_COPY_REC, value,
          IRAppend(IR_LEA, caArgSym, -1, -1, 0, Ord(tyPointer)),
          -1, caCount * caElemSz, Ord(tyRecord));
        Result := IRAppend(IR_BINOP,
          IRAppend(IR_SLOTADDR, caSym, -1, -1, 0, Ord(tyPointer)),
          IRAppend(IR_CONST_INT, -1, -1, -1, 8, Ord(tyInteger)),
          Ord(tkPlus), 0, Ord(tyPointer));
        Exit;
      end;
    end;
  end;
  { Static array -> `var`/`out` open-array param: a `var` open array must let the
    callee read AND write the caller's elements, and Length/High over it must
    work. A bare static-array address has no length header at [data-8], so High
    returns garbage (bug-var-open-array-fixed-arg-length). Pass a header'd dyn
    temp instead (copy the static array in), and register a copy-OUT so the
    callee's writes propagate back after the call (copy-in / copy-out aliasing —
    observably equal to true aliasing unless the callee reaches the same array by
    another path during the call). A function result in rax/xmm0 is preserved
    across the post-call writeback (the AN_CALL flush spills it to a temp).
    Element types with managed payloads are excluded (the value path excludes
    them too). The compiler's own source never feeds a static array to a var
    open-array param, so self-host / cross-bootstrap stay byte-identical (this
    path is not exercised there). }
  if (cpi >= 0) and (pathIdx >= 0) and (pathIdx < Procs[cpi].ParamCount) and
     Procs[cpi].Params[pathIdx].IsArray and Procs[cpi].Params[pathIdx].IsRef and
     ((ASTKind[argAST] = AN_IDENT) or (ASTKind[argAST] = AN_FIELD)) and
     (PendOAWBCount <= 63) then
  begin
    { Determine the static-array source (a whole 1-D static array, either a
      simple var or a record/class field). Dynamic arrays and open-array params
      already carry a length header and are left alone. }
    oaEligible := False; caCount := 0; caElemTk := tyUnknown; caElemRec := REC_NONE;
    if ASTKind[argAST] = AN_IDENT then
    begin
      caArgSym := ASTIVal[argAST];
      if (caArgSym >= 0) and (caArgSym < SymCount) and Syms[caArgSym].IsArray and
         (Syms[caArgSym].ArrLen >= 0) and (Syms[caArgSym].Kind <> skParam) and
         (SymArrNDims[caArgSym] <= 1) then
      begin
        caElemTk := Syms[caArgSym].ElemType;
        caElemRec := Syms[caArgSym].ElemRecName;
        caCount := Syms[caArgSym].ArrLen;
        oaEligible := True;
      end;
    end
    else
    begin
      caRecName := ResolveNodeRec(ASTLeft[argAST]);
      caField := GetASTIdentName(argAST);
      if RecFieldIsArray(caRecName, caField) and
         (RecFieldArrLen(caRecName, caField) >= 0) and
         (RecFieldDynDepth(caRecName, caField) = 0) and
         (RecFieldArrNDims(caRecName, caField) <= 1) then
      begin
        caElemTk := RecFieldType(caRecName, caField);
        caElemRec := RecFieldRecId(caRecName, caField);
        caCount := RecFieldArrLen(caRecName, caField);
        oaEligible := True;
      end;
    end;
    if oaEligible and (caElemTk <> tyAnsiString) and
       not ((caElemTk = tyRecord) and RecordHasManagedFields(caElemRec)) then
    begin
      if caElemTk = tyRecord then caElemSz := RecSize(caElemRec)
      else caElemSz := TypeSize(caElemTk);
      { Frame/BSS-local `[len:8][data]` buffer (same no-leak, recursion-safe shape
        as the const/value path above), plus a registered copy-OUT so the callee's
        writes propagate back to the caller's array after the call. }
      caSym := AllocArray('', tyUInt8, 0, 8 + caCount * caElemSz - 1);
      SymIsHiddenArgTemp[caSym] := True;
      IRAppend(IR_STORE_MEM,
        IRAppend(IR_SLOTADDR, caSym, -1, -1, 0, Ord(tyPointer)),
        IRAppend(IR_CONST_INT, -1, -1, -1, caCount, Ord(tyInteger)),
        -1, 0, Ord(tyPointer));
      value := IRAppend(IR_BINOP,
        IRAppend(IR_SLOTADDR, caSym, -1, -1, 0, Ord(tyPointer)),
        IRAppend(IR_CONST_INT, -1, -1, -1, 8, Ord(tyInteger)),
        Ord(tkPlus), 0, Ord(tyPointer));
      { copy-IN: static array (var or field) -> buffer data }
      IRAppend(IR_COPY_REC, value, IRLowerAddress(argAST),
        -1, caCount * caElemSz, Ord(tyRecord));
      { register copy-OUT: buffer data -> the argument's address, after the call.
        The dest is the arg AST node, re-lowered (IRLowerAddress) at flush time. }
      PendOAWBTemp[PendOAWBCount] := caSym;
      PendOAWBDest[PendOAWBCount] := argAST;
      PendOAWBSize[PendOAWBCount] := caCount * caElemSz;
      Inc(PendOAWBCount);
      Result := IRAppend(IR_BINOP,
        IRAppend(IR_SLOTADDR, caSym, -1, -1, 0, Ord(tyPointer)),
        IRAppend(IR_CONST_INT, -1, -1, -1, 8, Ord(tyInteger)),
        Ord(tkPlus), 0, Ord(tyPointer));
      Exit;
    end;
  end;
  { An `array of const` literal lowers to a freshly built dyn-array of TVarRec;
    its value is the data-pointer handle, passed straight through (never the
    record-by-value copy path below). }
  if (ASTKind[argAST] = AN_VARREC_ARRAY) or (ASTKind[argAST] = AN_ARRAY_CTOR) then
  begin
    Result := IRLowerAST(argAST);
    Exit;
  end;
  argTk := IntToTypeKind(ASTTk[argAST]);
  needTemp := False;
  argRecId := REC_NONE;
  { A whole array variable is never a record-by-value argument: its node carries
    the element's tyRecord tag, but the value is the array, not one record.
    Routing it through the record temp-copy path below would substitute a
    throwaway record temp for the real array slot whenever the element record is
    >8 bytes — corrupting e.g. SetLength's target (the array was lost, the temp
    resized). Only fires when the element record is large, so it stayed latent
    until a >8-byte (e.g. managed-field) record element appeared. }
  argIsWholeArray := (ASTKind[argAST] = AN_IDENT) and
     (Integer(ASTIVal[argAST]) >= 0) and (Integer(ASTIVal[argAST]) < SymCount) and
     Syms[ASTIVal[argAST]].IsArray;
  if (argTk = tyRecord) and not argIsWholeArray then
  begin
    argRecId := ResolveNodeRec(argAST);
    if CProgramMode then
      { C struct-by-value: a record param is by-ref ABI (8-byte pointer slot),
        so ALWAYS copy the record to a temp and pass &temp — true by-value with
        correct field access for any size. C-mode-gated -> Pascal byte-identical. }
      needTemp := True
    else if isRefArg then
    begin
      if not IsASTLValue(argAST) then
        needTemp := True;
    end
    else
    begin
      if RecSize(argRecId) > 8 then
        needTemp := True;
    end;
  end;

  if needTemp then
  begin
    savedLastTypeRecId := LastTypeRecId;
    LastTypeRecId := argRecId;
    tmpSym := AllocVar('', tyRecord);
    LastTypeRecId := savedLastTypeRecId;
    { A managed-field record temp is filled by IR_COPY_REC_MANAGED below, which
      RELEASES the destination's old managed fields before copying. This temp is
      allocated during IR lowering, after the parser's prologue zero-init pass,
      so without a nil-init its fields hold stack garbage and the release frees a
      bogus handle (double-free / heap corruption — crashes when the arg is a
      managed-record value, e.g. `f(g(x), …)` with g returning a managed record).
      Mark it so codegen nil-inits its full extent before the body, exactly like
      the hidden aggregate-result temp in IRAppendCall. }
    if RecordHasManagedFields(argRecId) then
      SymIsHiddenArgTemp[tmpSym] := True;

    tmpAddr := IRAppend(IR_LEA, tmpSym, -1, -1, 0, Ord(tyPointer));

    if IsASTLValue(argAST) then
      srcAddr := IRLowerAddress(argAST)
    else
      srcAddr := IRLowerAST(argAST);

    if RecordHasManagedFields(argRecId) then
      IRAppend(IR_COPY_REC_MANAGED, tmpAddr, srcAddr, argRecId, RecSize(argRecId), Ord(tyRecord))
    else
      IRAppend(IR_COPY_REC, tmpAddr, srcAddr, -1, RecSize(argRecId), Ord(tyRecord));

    value := tmpAddr;
  end
  else
  begin
    if isRefArg then
    begin
      if (cpi >= 0) and (pathIdx >= 0) and (pathIdx < 16) and
         (ProcParamDynDepth[cpi * 16 + pathIdx] > 0) and
         (ASTKind[argAST] = AN_IDENT) and
         not ((Syms[ASTIVal[argAST]].Kind = skParam) and
              Syms[ASTIVal[argAST]].IsRef) then
        { var/out named-dynamic-array param: pass the ADDRESS of the caller's
          handle slot (&caller_slot) so SetLength can publish a resized handle
          back. IR_LEA over a dyn-array ident would instead yield the handle
          VALUE, so use IR_SLOTADDR explicitly (mirrors the by-ref AnsiString
          arg below). A forwarded by-ref param already holds &caller_slot in its
          slot, so it takes the IRLowerAddress path. }
        value := IRAppend(IR_SLOTADDR, ASTIVal[argAST], -1, -1, 0, Ord(tyPointer))
      else if (cpi >= 0) and
         (ASTKind[argAST] = AN_IDENT) and
         (Syms[ASTIVal[argAST]].TypeKind = tyAnsiString) and
         not ((Syms[ASTIVal[argAST]].Kind = skParam) and
              Syms[ASTIVal[argAST]].IsRef) then
        value := IRAppend(IR_SLOTADDR, ASTIVal[argAST], -1, -1, 0, Ord(tyPointer))
      else
        value := IRLowerAddress(argAST);
    end
    else
    begin
      value := IRLowerAST(argAST);
      if (argTk = tyRecord) and ((ASTKind[argAST] = AN_CALL) or (ASTKind[argAST] = AN_BINOP)) then
        value := IRAppend(IR_LOAD_MEM, value, -1, -1, 0, ASTTk[argAST]);
      { Integer argument to a float parameter: convert. The call ABI carries a
        float as its IEEE bits; an integer value (raw bits in a GPR) would be
        misread by the callee as a float (e.g. V(1,1,1) into Double params gives
        0.0). Round-trip through a hidden float temp, whose STORE already does the
        int->float (cvtsi2sd) conversion uniformly on every target
        (feature-int-to-float-assign). }
      if (cpi >= 0) and (pathIdx >= 0) and (pathIdx < Procs[cpi].ParamCount) and
         TypeIsFloat(Procs[cpi].Params[pathIdx].TypeKind) and
         (not TypeIsFloat(argTk)) and TypeIsOrdinal(argTk) then
      begin
        tmpSym := AllocVar('', Procs[cpi].Params[pathIdx].TypeKind);
        IRAppend(IR_STORE_SYM, tmpSym, value, -1, 0, Ord(Procs[cpi].Params[pathIdx].TypeKind));
        value := IRAppend(IR_LOAD_SYM, tmpSym, -1, -1, 0, Ord(Procs[cpi].Params[pathIdx].TypeKind));
      end;
    end;
  end;
  Result := value;
end;

function IsConstStrLitNode(n: Integer): Boolean;
{ A compile-time string-or-char literal (foldable in an ESP tyString concat). }
begin
  Result := (ASTKind[n] = AN_STR_LIT) or
            ((ASTKind[n] = AN_INT_LIT) and (IntToTypeKind(ASTTk[n]) = tyChar));
end;

function ConstStrLitValue(n: Integer): AnsiString;
{ The string value of a node accepted by IsConstStrLitNode. }
begin
  if ASTKind[n] = AN_STR_LIT then
    Result := GetTokenStrFromRaw(ASTSOffset[n], ASTSLen[n])
  else
  begin
    Result := '';
    AppendChar(Result, Chr(Integer(ASTIVal[n])));
  end;
end;

function IsClassDescOrSelf(c, target: Integer): Boolean;
{ True if class c is `target` or transitively descends it (closed-world walk of
  the compile-time parent chain). Drives the is/as VMT-set test. }
var cur: Integer;
begin
  Result := False;
  cur := c;
  while cur >= 0 do
  begin
    if cur = target then begin Result := True; Exit; end;
    cur := UClsParent[cur];
  end;
end;

{ Emit IR that evaluates `instExpr` once into a hidden pointer temp (returned in
  instSym) and computes a Boolean temp = (inst <> nil) and (VMT(inst) is the VMT
  of `targetCi` or any descendant). Returns the Boolean temp's sym index. The
  descendant set is enumerated here, at codegen, so classes declared after the
  is/as site are included (whole-program closed world). Shared by `is` and `as`. }
function IRLowerClassMatch(instExpr, targetCi: Integer; var instSym: Integer): Integer;
var rvar, instVal, endLbl, skipLbl, c, li, znode, notnil, vmtSym, lv, va, eq: Integer;
begin
  rvar := AllocVar('', tyBoolean);
  instSym := AllocVar('', tyPointer);
  vmtSym := AllocVar('', tyPointer);
  instVal := IRLowerAST(instExpr);
  IRAppend(IR_STORE_SYM, instSym, instVal, -1, 0, Ord(tyPointer));
  IRAppend(IR_STORE_SYM, rvar, IRAppend(IR_CONST_INT, -1, -1, -1, 0, Ord(tyBoolean)), -1, 0, Ord(tyBoolean));
  endLbl := IRNewLabel;
  { nil instance: leave rvar false }
  li := IRAppend(IR_LOAD_SYM, instSym, -1, -1, 0, Ord(tyPointer));
  znode := IRAppend(IR_CONST_INT, -1, -1, -1, 0, Ord(tyPointer));
  notnil := IRAppend(IR_BINOP, li, znode, Ord(tkNeq), 0, Ord(tyBoolean));
  IRAppend(IR_JUMP_IF_FALSE, endLbl, notnil, -1, 0, 0);
  { vmt := [inst+0] }
  IRAppend(IR_STORE_SYM, vmtSym,
           IRAppend(IR_LOAD_MEM, IRAppend(IR_LOAD_SYM, instSym, -1, -1, 0, Ord(tyPointer)),
                    -1, -1, 0, Ord(tyPointer)),
           -1, 0, Ord(tyPointer));
  { Match set: for a class target, c is the class or a descendant; for an
    interface target, c is any class that implements it (directly or inherited,
    via FindIMT). So `obj is IFoo` is true iff obj's class implements IFoo. }
  for c := 0 to UClsCount - 1 do
    if (UClsVMTOffset[c] >= 0) and
       ( (UClsIsInterface[targetCi] and (FindIMT(c, targetCi) >= 0)) or
         ((not UClsIsInterface[targetCi]) and IsClassDescOrSelf(c, targetCi)) ) then
    begin
      lv := IRAppend(IR_LOAD_SYM, vmtSym, -1, -1, 0, Ord(tyPointer));
      va := IRAppend(IR_VMTADDR, c, -1, -1, 0, Ord(tyPointer));
      eq := IRAppend(IR_BINOP, lv, va, Ord(tkEq), 0, Ord(tyBoolean));
      skipLbl := IRNewLabel;
      IRAppend(IR_JUMP_IF_FALSE, skipLbl, eq, -1, 0, 0);
      IRAppend(IR_STORE_SYM, rvar, IRAppend(IR_CONST_INT, -1, -1, -1, 1, Ord(tyBoolean)), -1, 0, Ord(tyBoolean));
      IRAppend(IR_LABEL, -1, -1, -1, skipLbl, 0);
    end;
  IRAppend(IR_LABEL, -1, -1, -1, endLbl, 0);
  Result := rvar;
end;

function IRMaterializeIntfCast(node: Integer; doTrap: Boolean): Integer;
{ Build the CORBA fat pointer {IMT@0, instance@PTR} for `obj as IFoo` (or an
  implicit class->interface coercion) into a hidden interface temp; return the
  temp's symbol. The IMT is chosen by a closed-world DYNAMIC lookup: match the
  instance's VMT against every class that implements the interface, so the cast
  is correct even when the source is typed as a base class. nil -> {nil,nil};
  a non-nil class that does not implement the interface traps (Halt 1) when
  doTrap. Memoised in ASTLiftedVar: the interface-call path takes the fat
  pointer's address twice, so this must build it once. }
var intfCi, tmpSym, instSym, instVal, endLbl, c, skipLbl, savedRec: Integer;
    li, vmtSym, lv, va, eq, imtPi, w1Addr: Integer;
begin
  if ASTLiftedVar[node] >= 0 then begin Result := ASTLiftedVar[node]; Exit; end;
  intfCi := Integer(ASTIVal[node]);
  savedRec := LastTypeRecId;
  LastTypeRecId := REC_UCLASS_BASE + intfCi;
  tmpSym := AllocVar('', tyRecord);          { size = 2*TARGET_PTR_SIZE }
  LastTypeRecId := savedRec;
  ASTLiftedVar[node] := tmpSym;

  instSym := AllocVar('', tyPointer);
  instVal := IRLowerAST(ASTLeft[node]);
  IRAppend(IR_STORE_SYM, instSym, instVal, -1, 0, Ord(tyPointer));

  { Zero both fat-pointer words: IMT@0 := nil, instance@PTR := instance. }
  IRAppend(IR_STORE_MEM, IRAppend(IR_LEA, tmpSym, -1, -1, 0, Ord(tyPointer)),
           IRAppend(IR_CONST_INT, -1, -1, -1, 0, Ord(tyPointer)), -1, 0, Ord(tyPointer));
  w1Addr := IRAppend(IR_BINOP, IRAppend(IR_LEA, tmpSym, -1, -1, 0, Ord(tyPointer)),
                     IRAppend(IR_CONST_INT, -1, -1, -1, TARGET_PTR_SIZE, Ord(tyInteger)),
                     Ord(tkPlus), 0, Ord(tyPointer));
  IRAppend(IR_STORE_MEM, w1Addr, IRAppend(IR_LOAD_SYM, instSym, -1, -1, 0, Ord(tyPointer)),
           -1, 0, Ord(tyPointer));

  endLbl := IRNewLabel;
  { nil instance: leave {nil,nil}, never trap. }
  li := IRAppend(IR_LOAD_SYM, instSym, -1, -1, 0, Ord(tyPointer));
  IRAppend(IR_JUMP_IF_FALSE, endLbl,
           IRAppend(IR_BINOP, li, IRAppend(IR_CONST_INT, -1, -1, -1, 0, Ord(tyPointer)),
                    Ord(tkNeq), 0, Ord(tyBoolean)), -1, 0, 0);
  { vmt := [inst]. }
  vmtSym := AllocVar('', tyPointer);
  IRAppend(IR_STORE_SYM, vmtSym,
           IRAppend(IR_LOAD_MEM, IRAppend(IR_LOAD_SYM, instSym, -1, -1, 0, Ord(tyPointer)),
                    -1, -1, 0, Ord(tyPointer)), -1, 0, Ord(tyPointer));
  for c := 0 to UClsCount - 1 do
    if (UClsVMTOffset[c] >= 0) and (FindIMT(c, intfCi) >= 0) then
    begin
      lv := IRAppend(IR_LOAD_SYM, vmtSym, -1, -1, 0, Ord(tyPointer));
      va := IRAppend(IR_VMTADDR, c, -1, -1, 0, Ord(tyPointer));
      eq := IRAppend(IR_BINOP, lv, va, Ord(tkEq), 0, Ord(tyBoolean));
      skipLbl := IRNewLabel;
      IRAppend(IR_JUMP_IF_FALSE, skipLbl, eq, -1, 0, 0);
      imtPi := FindIMT(c, intfCi);
      IRAppend(IR_STORE_MEM, IRAppend(IR_LEA, tmpSym, -1, -1, 0, Ord(tyPointer)),
               IRAppend(IR_IMTADDR, imtPi, -1, -1, 0, Ord(tyPointer)), -1, 0, Ord(tyPointer));
      IRAppend(IR_JUMP, endLbl, -1, -1, 0, 0);     { matched -> skip the trap }
      IRAppend(IR_LABEL, -1, -1, -1, skipLbl, 0);
    end;
  { Non-nil instance whose class implements no matching IMT: a bad cast. }
  if doTrap then
    IRAppend(IR_TERMINATE, IRAppend(IR_CONST_INT, -1, -1, -1, 1, Ord(tyInteger)), -1, -1, AN_HALT, 0);
  IRAppend(IR_LABEL, -1, -1, -1, endLbl, 0);
  Result := tmpSym;
end;

function NodeIsInterface(node: Integer): Boolean;
{ True iff the node is an interface-typed value (a CORBA fat pointer). }
var rec: Integer;
begin
  Result := False;
  if node < 0 then Exit;
  if IntToTypeKind(ASTTk[node]) <> tyRecord then Exit;
  rec := ResolveNodeRec(node);
  Result := (rec >= REC_UCLASS_BASE) and UClsIsInterface[rec - REC_UCLASS_BASE];
end;

function IRIntfInstanceWord(node: Integer): Integer;
{ The instance pointer of an interface value (fat pointer's word at offset
  TARGET_PTR_SIZE), used for identity comparison. A non-interface operand (a nil
  literal) lowers to its plain value, so `iface = nil` compares against 0. }
begin
  if NodeIsInterface(node) then
    Result := IRAppend(IR_LOAD_MEM,
                IRAppend(IR_BINOP, IRLowerAddress(node),
                  IRAppend(IR_CONST_INT, -1, -1, -1, TARGET_PTR_SIZE, Ord(tyInteger)),
                  Ord(tkPlus), 0, Ord(tyPointer)),
                -1, -1, 0, Ord(tyPointer))
  else
    Result := IRLowerAST(node);
end;

{ Runtime mutation of one bit of a 32-byte set: set (isIncl) or clear bit `val`
  in the set at `setAddrNode`. The value is masked to 0..255 so the byte index
  always lands inside the 32-byte set — out-of-range elements are ignored, like
  the constant set-literal bake path. setAddrNode is an already-lowered address
  node; valNode is an already-lowered integer value. Emits the load/modify/store
  as a statement. Target-independent: only IR_BINOP / IR_LOAD_MEM / IR_STORE_MEM
  primitives, which every backend already implements. (`shr` is IR_BINOP with op
  Ord(tkIdent), matching the term parser.) }
procedure IRLowerSetBitMutate(setAddrNode, valNode: Integer; isIncl: Boolean);
var vTmp, ptrTmp, mask, curByte, newByte: Integer;
begin
  { Evaluate the value once. }
  vTmp := AllocVar('', tyInteger);
  IRAppend(IR_STORE_SYM, vTmp, valNode, -1, 0, Ord(tyInteger));
  { byteAddr := setAddr + ((val and 255) shr 3); cache in a pointer temp so the
    address is computed once and reused by the load and the store. }
  ptrTmp := AllocVar('', tyPointer);
  IRAppend(IR_STORE_SYM, ptrTmp,
    IRAppend(IR_BINOP, setAddrNode,
      IRAppend(IR_BINOP,
        IRAppend(IR_BINOP, IRAppend(IR_LOAD_SYM, vTmp, -1, -1, 0, Ord(tyInteger)),
          IRAppend(IR_CONST_INT, -1, -1, -1, 255, Ord(tyInteger)), Ord(tkAnd), 0, Ord(tyInteger)),
        IRAppend(IR_CONST_INT, -1, -1, -1, 3, Ord(tyInteger)), Ord(tkIdent), 0, Ord(tyInteger)),
      Ord(tkPlus), 0, Ord(tyPointer)),
    -1, 0, Ord(tyPointer));
  { mask := 1 shl ((val and 255) and 7). }
  mask := IRAppend(IR_BINOP,
            IRAppend(IR_CONST_INT, -1, -1, -1, 1, Ord(tyInteger)),
            IRAppend(IR_BINOP,
              IRAppend(IR_BINOP, IRAppend(IR_LOAD_SYM, vTmp, -1, -1, 0, Ord(tyInteger)),
                IRAppend(IR_CONST_INT, -1, -1, -1, 255, Ord(tyInteger)), Ord(tkAnd), 0, Ord(tyInteger)),
              IRAppend(IR_CONST_INT, -1, -1, -1, 7, Ord(tyInteger)), Ord(tkAnd), 0, Ord(tyInteger)),
            Ord(tkShl), 0, Ord(tyInteger));
  curByte := IRAppend(IR_LOAD_MEM, IRAppend(IR_LOAD_SYM, ptrTmp, -1, -1, 0, Ord(tyPointer)),
               -1, -1, 0, Ord(tyUInt8));
  if isIncl then
    newByte := IRAppend(IR_BINOP, curByte, mask, Ord(tkOr), 0, Ord(tyInteger))
  else
    newByte := IRAppend(IR_BINOP, curByte,
                 IRAppend(IR_NOT, mask, -1, -1, 0, Ord(tyInteger)), Ord(tkAnd), 0, Ord(tyInteger));
  IRAppend(IR_STORE_MEM, IRAppend(IR_LOAD_SYM, ptrTmp, -1, -1, 0, Ord(tyPointer)),
    newByte, -1, 0, Ord(tyUInt8));
end;

{ Runtime `lo..hi` range into a set: a counter loop calling IRLowerSetBitMutate.
  lo/hi are already-lowered integer values. Always Include (set literals only
  add). }
procedure IRLowerSetRangeMutate(setSym, loNode, hiNode: Integer);
var iSym, hiSym, topLbl, endLbl: Integer;
begin
  iSym := AllocVar('', tyInteger);
  hiSym := AllocVar('', tyInteger);
  IRAppend(IR_STORE_SYM, iSym, loNode, -1, 0, Ord(tyInteger));
  IRAppend(IR_STORE_SYM, hiSym, hiNode, -1, 0, Ord(tyInteger));
  topLbl := IRNewLabel;
  endLbl := IRNewLabel;
  IRAppend(IR_LABEL, -1, -1, -1, topLbl, 0);
  { while i <= hi }
  IRAppend(IR_JUMP_IF_FALSE, endLbl,
    IRAppend(IR_BINOP, IRAppend(IR_LOAD_SYM, iSym, -1, -1, 0, Ord(tyInteger)),
      IRAppend(IR_LOAD_SYM, hiSym, -1, -1, 0, Ord(tyInteger)), Ord(tkLe), 0, Ord(tyBoolean)),
    -1, 0, 0);
  IRLowerSetBitMutate(IRAppend(IR_LEA, setSym, -1, -1, 0, Ord(tyPointer)),
    IRAppend(IR_LOAD_SYM, iSym, -1, -1, 0, Ord(tyInteger)), True);
  { i := i + 1 }
  IRAppend(IR_STORE_SYM, iSym,
    IRAppend(IR_BINOP, IRAppend(IR_LOAD_SYM, iSym, -1, -1, 0, Ord(tyInteger)),
      IRAppend(IR_CONST_INT, -1, -1, -1, 1, Ord(tyInteger)), Ord(tkPlus), 0, Ord(tyInteger)),
    -1, 0, Ord(tyInteger));
  IRAppend(IR_JUMP, topLbl, -1, -1, 0, 0);
  IRAppend(IR_LABEL, -1, -1, -1, endLbl, 0);
end;

{ Append a synthetic string literal to the raw TokChars pool and return an
  IR_CONST_STR node referencing it. Lets IR lowering emit string writes for
  text that is not in the user's source (e.g. Boolean TRUE/FALSE). }
function IRSyntheticConstStr(const s: AnsiString): Integer;
var k, off: Integer;
begin
  off := TokCharLen;
  for k := 1 to Length(s) do
  begin
    TokChars[TokCharLen] := s[k];
    Inc(TokCharLen);
  end;
  Result := IRAppend(IR_CONST_STR, off, Length(s), -1, 0, Ord(tyString));
end;

{ Lower a Boolean `write` argument to a TRUE/FALSE string write, branching at
  runtime. Target-independent: emits IR_JUMP_IF_FALSE / IR_WRITE(const_str) /
  IR_JUMP / IR_LABEL, all of which every backend already handles, so the boolean
  output is FPC-correct on all targets at once. Returns the first node; writes
  the final node (the end label) into lastNode. wid = field width (-1 = none). }
function IRLowerBoolWrite(value, wid: Integer; var lastNode: Integer; fd: Integer): Integer;
var bFalse, bEnd: Integer;
begin
  bFalse := IRNewLabel;
  bEnd := IRNewLabel;
  Result := IRAppend(IR_JUMP_IF_FALSE, bFalse, value, -1, 0, 0);
  { Pascal/FPC renders TRUE/FALSE; the Nil-Python frontend renders Python's
    True/False. (ival = target fd, threaded for writeln(StdErr,..).) }
  if isNilPy then
    IRAppend(IR_WRITE, IRSyntheticConstStr('True'), wid, -1, fd, Ord(tyString))
  else
    IRAppend(IR_WRITE, IRSyntheticConstStr('TRUE'), wid, -1, fd, Ord(tyString));
  IRAppend(IR_JUMP, bEnd, -1, -1, 0, 0);
  IRAppend(IR_LABEL, -1, -1, -1, bFalse, 0);
  if isNilPy then
    IRAppend(IR_WRITE, IRSyntheticConstStr('False'), wid, -1, fd, Ord(tyString))
  else
    IRAppend(IR_WRITE, IRSyntheticConstStr('FALSE'), wid, -1, fd, Ord(tyString));
  lastNode := IRAppend(IR_LABEL, -1, -1, -1, bEnd, 0);
end;

procedure IRLowerCSwitchDispatchSeq(seqNode, selTmp, selTk: Integer; var defaultLabel: Integer);
var seq, stmt, condNode: Integer;
begin
  seq := seqNode;
  while seq <> -1 do
  begin
    stmt := ASTLeft[seq];
    if stmt >= 0 then
    begin
      if ASTKind[stmt] = AN_CASE then
      begin
        ASTSOffset[stmt] := IRNewLabel;
        condNode := IRAppend(IR_BINOP,
          IRAppend(IR_LOAD_SYM, selTmp, -1, -1, 0, selTk),
          IRAppend(IR_CONST_INT, -1, -1, -1, ASTIVal[stmt], selTk),
          Ord(tkNeq), 0, Ord(tyBoolean));
        IRAppend(IR_JUMP_IF_FALSE, ASTSOffset[stmt], condNode, -1, 0, 0);
      end
      else if ASTKind[stmt] = AN_DEFAULT then
      begin
        ASTSOffset[stmt] := IRNewLabel;
        defaultLabel := ASTSOffset[stmt];
      end
      else if ASTKind[stmt] = AN_BLOCK then
        IRLowerCSwitchDispatchSeq(ASTLeft[stmt], selTmp, selTk, defaultLabel);
    end;
    seq := ASTRight[seq];
  end;
end;

procedure IRLowerCSwitchBodySeq(seqNode: Integer);
var seq, stmt, lowered: Integer;
begin
  seq := seqNode;
  while seq <> -1 do
  begin
    stmt := ASTLeft[seq];
    if stmt >= 0 then
    begin
      if (ASTKind[stmt] = AN_CASE) or (ASTKind[stmt] = AN_DEFAULT) then
        IRAppend(IR_LABEL, -1, -1, -1, ASTSOffset[stmt], 0)
      else if ASTKind[stmt] = AN_BLOCK then
        IRLowerCSwitchBodySeq(ASTLeft[stmt])
      else
      begin
        lowered := IRLowerAST(stmt);
        IRMarkStatementNode(lowered);
      end;
    end;
    seq := ASTRight[seq];
  end;
end;

function IRLowerAST(node: Integer): Integer;
var left, right, seq, item, value, outNode, first, last, leftAddr, argNode, argVal, intCallNode, intArgSeq, argNode2, zeroVal, procIdx, zeroBytes: Integer;
    pairNode, condNode, specialId, classIdx, slot, cpi, pathIdx: Integer;
    isRefArg: Boolean; argTk: TTypeKind; callRetType: TTypeKind; callVal: Integer;
    startLabel, elseLabel, endLabel, startLabelNode, endLabelNode: Integer;
    lhsNode, pair3, pair1, pair2, initNode, limitNode, isDownNode, bodyNode: Integer;
    foldOff, foldK: Integer;
    bLastNode: Integer;
    writeFd: Integer;
    foldStr: AnsiString;
    down: Boolean;
    varIdx: Integer;
    initValNode, storeNode, limitValNode, cmpNode, condJmpNode, bodyIRNode: Integer;
    loadVarNode2, constOneNode, stepNode, storeStepNode, jmpNode: Integer;
    hiddenArgSym: Integer; argIsManagedTemp: Boolean;
    continueLabel, continueLabelNode: Integer;
    branchSeq, branchPair, labelsHead, stmtNode, labelNode: Integer;
    clauseBodyLabel, nextClauseLabel, selectorValNode: Integer;
    ternTmp: Integer;
    swSelTmp, swDefault, swSeq, swMarker, swSelTk: Integer;
    rhsIsLValue: Boolean;
    isComIntf: Boolean;
    intfTmpImt, intfTmpInst: Integer;
    cv: Int64;
    constValNode, clauseBodyLabelNode, exitJmpNode, nextClauseLabelNode: Integer;
    beforeCount, handlerLabel, handlerNode, handlerNextLabel, savedDepth: Integer;
    raiseValueNode, raiseClass: Integer;
    i, lbId, off, len, idx, itemNode, lo, hi, val1, elemSize, savedProc: Integer;
    slTargetAST, slCountAST, slRootSym, slDepth, slTargetAddr, slCountNode: Integer;
    slFldRec, slFldDepth, slFldBaseRec: Integer; slFldName: AnsiString; slFldBaseTk: TTypeKind;
    helperPi, wrapperArg, wrapperCall: Integer;
    lhsTk, lhsStoreTk, castTk: TTypeKind;
    vrCount, vrTmp, vrIdent, vrCountLit, vrArg1, vrArg2, vrSlCall: Integer;
    vrIdxLit, vrIndex, vrTag, elemAddr, vrSavedRecId, vrBoxSym: Integer;
    vrElemTk: TTypeKind;
    setAllConst: Boolean; setSym: Integer;
    dcSrcSym, dcElemRec, dcElemSz, dcIdxAst, dcCntAst, dcSrcTmp, dcIdxTmp: Integer;
    dcCntTmp, dcTempSym, dcTempIdent, dcCountIdent, dcSlArg1, dcSlArg2: Integer;
    dcSlCall, dcSetlenVal, dcDestData, dcSrcStart, dcNbytes, dcSavedRec: Integer;
    dcElemTk: TTypeKind;
    pendBase: Integer;
    mcCrefSym, mcInstSym, mcSize, mcVmt, mcAddr, mcSelfArg: Integer;
    dynLenTmp, dynLenPi: Integer;
begin
  if node = -1 then
  begin
    Result := -1;
    Exit;
  end;

  if ASTLine[node] <> 0 then CurLowerLine := ASTLine[node];

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

    AN_DEFAULT:
      Error('default requires an assignment target');

    AN_ARRAY_CTOR:
    begin
      { `[e0, e1, ...]` for an `array of T` (scalar/string) parameter: build a heap
        dyn-array temp of T, SetLength(N), store each element through the normal
        element-assign path (type coercion + managed-string ARC), and yield the
        data-pointer handle as the open-array argument. Plain-element mirror of
        AN_VARREC_ARRAY. }
      vrElemTk := IntToTypeKind(ASTIVal[node]);
      vrCount := 0;
      item := ASTLeft[node];
      while item <> -1 do begin Inc(vrCount); item := ASTRight[item]; end;

      vrTmp := AllocDynArray('', vrElemTk, 1);
      { Managed local synthesised after the prologue zero-init pass — flag it for
        the codegen prologue nil-init and zero the handle slot here so SetLength
        sees nil (mirrors AN_VARREC_ARRAY). }
      SymIsHiddenArgTemp[vrTmp] := True;
      IRAppend(IR_DEFAULT_MEM,
        IRAppend(IR_SLOTADDR, vrTmp, -1, -1, 0, Ord(tyPointer)),
        -1, REC_NONE, TARGET_PTR_SIZE, Ord(tyPointer));

      { SetLength(tmp, vrCount) }
      vrIdent := AllocNode(AN_IDENT);
      ASTIVal[vrIdent] := vrTmp; ASTTk[vrIdent] := Ord(tyPointer);
      vrCountLit := AllocNode(AN_INT_LIT);
      ASTIVal[vrCountLit] := vrCount; ASTTk[vrCountLit] := Ord(tyInteger);
      vrArg1 := AllocNode(AN_ARG); ASTLeft[vrArg1] := vrIdent;
      vrArg2 := AllocNode(AN_ARG); ASTLeft[vrArg2] := vrCountLit;
      ASTRight[vrArg1] := vrArg2;
      vrSlCall := AllocNode(AN_CALL); ASTIVal[vrSlCall] := -102;
      ASTLeft[vrSlCall] := vrArg1;
      value := IRLowerAST(vrSlCall);
      IRIVal[value] := 1;   { mark the SetLength IR_CALL as a statement to emit }

      { tmp[i] := element, via the normal element-assign path. }
      i := 0;
      item := ASTLeft[node];
      while item <> -1 do
      begin
        vrIdent := AllocNode(AN_IDENT);
        ASTIVal[vrIdent] := vrTmp; ASTTk[vrIdent] := Ord(tyPointer);
        vrIdxLit := AllocNode(AN_INT_LIT);
        ASTIVal[vrIdxLit] := i; ASTTk[vrIdxLit] := Ord(tyInteger);
        vrIndex := AllocNode(AN_INDEX);
        ASTLeft[vrIndex] := vrIdent; ASTRight[vrIndex] := vrIdxLit;
        ASTTk[vrIndex] := Ord(vrElemTk);
        elemAddr := AllocNode(AN_ASSIGN);
        ASTLeft[elemAddr] := vrIndex;
        ASTRight[elemAddr] := ASTLeft[item];
        ASTTk[elemAddr] := Ord(vrElemTk);
        IRMarkStatementNode(IRLowerAST(elemAddr));
        Inc(i);
        item := ASTRight[item];
      end;

      Result := IRAppend(IR_LEA, vrTmp, -1, -1, 0, Ord(tyPointer));
    end;

    AN_VARREC_ARRAY:
    begin
      { Lower `[e0, e1, ...]` in an `array of const` position to a heap dyn-array
        of TVarRec and yield its data-pointer handle. Each element becomes one
        TVarRec: VType at offset 0, the value at the union offset
        (TARGET_PTR_SIZE). The callee walks it as an open array of records, with
        Length/High reading the dyn-array header word — no new codegen needed. }
      vrCount := 0;
      item := ASTLeft[node];
      while item <> -1 do begin Inc(vrCount); item := ASTRight[item]; end;

      vrSavedRecId := LastTypeRecId;
      LastTypeRecId := ASTIVal[node];        { TVarRecId }
      vrTmp := AllocDynArray('', tyRecord, 1);
      LastTypeRecId := vrSavedRecId;

      { This dyn-array temp is a managed local synthesised during lowering, after
        the parser's prologue zero-init pass, so flag it for the codegen prologue
        nil-init. The inline DEFAULT_MEM below only zeroes the slot when this
        literal is actually reached; if the `[...]` sits in a branch that is not
        taken, the slot would otherwise hold stale stack bytes and the function's
        managed-local cleanup would free a garbage handle. }
      SymIsHiddenArgTemp[vrTmp] := True;

      { Zero the handle slot (allocated after the prologue) so SetLength sees nil. }
      IRAppend(IR_DEFAULT_MEM,
        IRAppend(IR_SLOTADDR, vrTmp, -1, -1, 0, Ord(tyPointer)),
        -1, REC_NONE, TARGET_PTR_SIZE, Ord(tyPointer));

      { SetLength(tmp, vrCount): synthesise the dyn-array SetLength (-102) call. }
      vrIdent := AllocNode(AN_IDENT);
      ASTIVal[vrIdent] := vrTmp; ASTTk[vrIdent] := Ord(tyPointer);
      vrCountLit := AllocNode(AN_INT_LIT);
      ASTIVal[vrCountLit] := vrCount; ASTTk[vrCountLit] := Ord(tyInteger);
      vrArg1 := AllocNode(AN_ARG); ASTLeft[vrArg1] := vrIdent;
      vrArg2 := AllocNode(AN_ARG); ASTLeft[vrArg2] := vrCountLit;
      ASTRight[vrArg1] := vrArg2;
      vrSlCall := AllocNode(AN_CALL); ASTIVal[vrSlCall] := -102;
      ASTLeft[vrSlCall] := vrArg1;
      value := IRLowerAST(vrSlCall);
      IRIVal[value] := 1;   { mark the SetLength IR_CALL as a statement to emit }

      { Fill each element. }
      i := 0;
      item := ASTLeft[node];
      while item <> -1 do
      begin
        vrIdent := AllocNode(AN_IDENT);
        ASTIVal[vrIdent] := vrTmp; ASTTk[vrIdent] := Ord(tyPointer);
        vrIdxLit := AllocNode(AN_INT_LIT);
        ASTIVal[vrIdxLit] := i; ASTTk[vrIdxLit] := Ord(tyInteger);
        vrIndex := AllocNode(AN_INDEX);
        ASTLeft[vrIndex] := vrIdent; ASTRight[vrIndex] := vrIdxLit;
        ASTTk[vrIndex] := Ord(tyRecord);

        { Element tag from the element's static type. The value union is one
          pointer-sized slot, so types wider than a pointer (Int64 — also on
          64-bit where it fits, for uniformity — and floats) are boxed: stored in
          a hidden local and the slot holds a pointer to it (FPC's VInt64/
          VExtended convention). }
        vrElemTk := IntToTypeKind(ASTTk[ASTLeft[item]]);
        if (vrElemTk = tyString) or (vrElemTk = tyAnsiString) then
          vrTag := 11             { vtAnsiString }
        else if vrElemTk = tyBoolean then
          vrTag := 1              { vtBoolean }
        else if vrElemTk = tyChar then
          vrTag := 2              { vtChar }
        else if vrElemTk = tyPointer then
          vrTag := 5              { vtPointer }
        else if (vrElemTk = tyInt64) or (vrElemTk = tyUInt64) then
          vrTag := 16             { vtInt64 (boxed) }
        else if (vrElemTk = tySingle) or (vrElemTk = tyDouble) or (vrElemTk = tyExtended) then
          vrTag := 3             { vtExtended (boxed) }
        else
          vrTag := 0;            { vtInteger }

        { VType := tag  (element offset 0) }
        elemAddr := IRLowerAddress(vrIndex);
        IRAppend(IR_STORE_MEM, elemAddr,
          IRAppend(IR_CONST_INT, -1, -1, -1, vrTag, Ord(tyNativeInt)),
          -1, 0, Ord(tyNativeInt));

        { value := elem  (element offset TARGET_PTR_SIZE) }
        elemAddr := IRLowerAddress(vrIndex);
        elemAddr := IRAppend(IR_BINOP, elemAddr,
          IRAppend(IR_CONST_INT, -1, -1, -1, TARGET_PTR_SIZE, Ord(tyInteger)),
          Ord(tkPlus), 0, Ord(tyPointer));
        if (vrTag = 16) or (vrTag = 3) then
        begin
          { Boxed value (Int64/float): a pointer-sized union slot can't hold a
            64-bit value on 32-bit targets, so store the element in a hidden local
            and put its address in the slot — FPC's VInt64/VExtended convention.
            The asm-text emitters (which build tyInt64 `%`-hole vectors like
            `['b %', LabelPositions[i] - CodeLen]`) dereference boxed Int64 holes,
            so this stays correct for both user `array of const` and internal asm.
            The local is unmanaged and written before any read — no nil-init. }
          vrBoxSym := AllocVar('', vrElemTk);
          IRAppend(IR_STORE_MEM,
            IRAppend(IR_SLOTADDR, vrBoxSym, -1, -1, 0, Ord(tyPointer)),
            IRLowerAST(ASTLeft[item]), -1, 0, Ord(vrElemTk));
          value := IRAppend(IR_SLOTADDR, vrBoxSym, -1, -1, 0, Ord(tyPointer));
        end
        else
        begin
          value := IRLowerAST(ASTLeft[item]);
          if vrElemTk = tyString then
            { vtAnsiString from a frozen (inline) string literal: its value points
              at the 8-byte length prefix, so skip to the NUL-terminated char data
              (InternStr terminates it), like FPC's VAnsiString. A runtime
              tyAnsiString value is ALREADY a char pointer (matches PChar(s), which
              only adjusts tyString), so it is stored as-is. }
            value := IRAppend(IR_BINOP, value,
              IRAppend(IR_CONST_INT, -1, -1, -1, 8, Ord(tyInteger)),
              Ord(tkPlus), 0, Ord(tyPointer));
        end;
        IRAppend(IR_STORE_MEM, elemAddr, value, -1, 0, Ord(tyNativeInt));

        Inc(i);
        item := ASTRight[item];
      end;

      Result := IRAppend(IR_LEA, vrTmp, -1, -1, 0, Ord(tyPointer));
    end;

    AN_SET_CONST_REF:
      { Named set constant: the 32-byte mask was already baked into Data[] at
        declaration time; yield its address exactly like a baked set literal. }
      Result := IRAppend(IR_SET_LIT, -1, -1, -1, ASTIVal[node], Ord(tySet));

    AN_SET_LIT:
    begin
      { An all-constant set literal is baked into a 32-byte Data[] blob (the
        original fast path, kept byte-identical). The parser leaves a constant
        element as an AN_INT_LIT (a constant range as an AN_PAIR of two of them);
        any other element kind means a runtime value, so the whole literal is
        built at runtime into a zeroed set temp with Include/range loops. }
      setAllConst := True;
      argNode := ASTLeft[node];
      while argNode <> -1 do
      begin
        itemNode := ASTLeft[argNode];
        if ASTKind[itemNode] = AN_PAIR then
        begin
          if (ASTKind[ASTLeft[itemNode]] <> AN_INT_LIT) or
             (ASTKind[ASTRight[itemNode]] <> AN_INT_LIT) then setAllConst := False;
        end
        else if ASTKind[itemNode] <> AN_INT_LIT then
          setAllConst := False;
        argNode := ASTRight[argNode];
      end;

      if setAllConst then
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
      end
      else
      begin
        setSym := AllocVar('', tySet);
        IRAppend(IR_DEFAULT_MEM, IRAppend(IR_LEA, setSym, -1, -1, 0, Ord(tyPointer)),
          -1, REC_NONE, 32, Ord(tySet));
        argNode := ASTLeft[node];
        while argNode <> -1 do
        begin
          itemNode := ASTLeft[argNode];
          if ASTKind[itemNode] = AN_PAIR then
            IRLowerSetRangeMutate(setSym, IRLowerAST(ASTLeft[itemNode]),
              IRLowerAST(ASTRight[itemNode]))
          else
            IRLowerSetBitMutate(IRAppend(IR_LEA, setSym, -1, -1, 0, Ord(tyPointer)),
              IRLowerAST(itemNode), True);
          argNode := ASTRight[argNode];
        end;
        Result := IRAppend(IR_LEA, setSym, -1, -1, 0, Ord(tySet));
      end;
    end;

    AN_SET_INCL:
      IRLowerSetBitMutate(IRLowerAddress(ASTLeft[node]), IRLowerAST(ASTRight[node]), True);

    AN_SET_EXCL:
      IRLowerSetBitMutate(IRLowerAddress(ASTLeft[node]), IRLowerAST(ASTRight[node]), False);

    AN_DYN_COPY:
    begin
      { Copy(arr, index, count) over a dynamic array -> a fresh `array of T`.
        Element type/size come from the source symbol, so this is generic over T
        (what a non-generic RTL routine cannot express). Build: clamp the count
        to the source bounds (PXXClampLen), SetLength a fresh dyn-array local to
        that, then raw-copy count*elemSize bytes from source[index] (PXXMemCopy).
        Index is 0-based (FPC dynamic-array Copy semantics). The result behaves
        like a dyn-array variable read, so the caller's assignment retains it and
        the local's scope-exit release balances it. NOTE: a raw byte copy, so an
        array of a managed element type (AnsiString / managed record) is shallow
        — deep element copy is a later extension. }
      dcSrcSym := ASTIVal[ASTLeft[node]];
      dcElemTk := Syms[dcSrcSym].ElemType;
      dcElemRec := Syms[dcSrcSym].ElemRecName;
      if dcElemTk = tyRecord then dcElemSz := RecSize(dcElemRec)
      else dcElemSz := TypeSize(dcElemTk);
      dcIdxAst := ASTLeft[ASTRight[node]];
      dcCntAst := ASTLeft[ASTRight[ASTRight[node]]];

      { Materialize source data pointer and index once. (IR_LEA on a dyn-array
        symbol in read context loads the handle = data pointer, like indexing.) }
      dcSrcTmp := AllocVar('', tyPointer);
      IRAppend(IR_STORE_SYM, dcSrcTmp,
        IRAppend(IR_LEA, dcSrcSym, -1, -1, 0, Ord(tyPointer)), -1, 0, Ord(tyPointer));
      dcIdxTmp := AllocVar('', tyInteger);
      IRAppend(IR_STORE_SYM, dcIdxTmp, IRLowerAST(dcIdxAst), -1, 0, Ord(tyInteger));

      { clampedCount := PXXClampLen(srcData, index, count). }
      procIdx := FindProc('PXXClampLen');
      if procIdx < 0 then Error('compiler error: PXXClampLen not found');
      first := IRAppend(IR_ARG, IRAppend(IR_LOAD_SYM, dcSrcTmp, -1, -1, 0, Ord(tyPointer)),
                 -1, -1, 0, Ord(tyPointer));
      last := IRAppend(IR_ARG, IRAppend(IR_LOAD_SYM, dcIdxTmp, -1, -1, 0, Ord(tyInteger)),
                -1, -1, 0, Ord(tyInteger));
      IRB[first] := last;
      argNode := IRAppend(IR_ARG, IRLowerAST(dcCntAst), -1, -1, 0, Ord(tyInteger));
      IRB[last] := argNode;
      dcCntTmp := AllocVar('', tyInteger);
      IRAppend(IR_STORE_SYM, dcCntTmp, IRAppendCall(procIdx, first, -1, Ord(tyNativeInt)),
        -1, 0, Ord(tyInteger));

      { Fresh dyn-array local of the source element type; zero its handle slot. }
      dcSavedRec := LastTypeRecId;
      if dcElemTk = tyRecord then LastTypeRecId := dcElemRec;
      dcTempSym := AllocDynArray('', dcElemTk, 1);
      LastTypeRecId := dcSavedRec;
      IRAppend(IR_DEFAULT_MEM, IRAppend(IR_SLOTADDR, dcTempSym, -1, -1, 0, Ord(tyPointer)),
        -1, REC_NONE, TARGET_PTR_SIZE, Ord(tyPointer));

      { SetLength(temp, clampedCount) via the -102 dyn-array SetLength call. }
      dcTempIdent := AllocNode(AN_IDENT); ASTIVal[dcTempIdent] := dcTempSym;
      ASTTk[dcTempIdent] := Ord(tyPointer);
      dcCountIdent := AllocNode(AN_IDENT); ASTIVal[dcCountIdent] := dcCntTmp;
      ASTTk[dcCountIdent] := Ord(tyInteger);
      dcSlArg1 := AllocNode(AN_ARG); ASTLeft[dcSlArg1] := dcTempIdent;
      dcSlArg2 := AllocNode(AN_ARG); ASTLeft[dcSlArg2] := dcCountIdent;
      ASTRight[dcSlArg1] := dcSlArg2;
      dcSlCall := AllocNode(AN_CALL); ASTIVal[dcSlCall] := -102; ASTLeft[dcSlCall] := dcSlArg1;
      dcSetlenVal := IRLowerAST(dcSlCall);
      IRIVal[dcSetlenVal] := 1;

      { PXXMemCopy(destData, srcData + index*elemSize, clampedCount*elemSize).
        Materialize the dest data pointer into a temp first: lea on the dyn-array
        symbol must be evaluated here in read context (handle = data pointer);
        feeding it straight into the call-arg position lowered it as an lvalue
        (the slot address) instead, so the copy missed the data block. }
      procIdx := FindProc('PXXMemCopy');
      if procIdx < 0 then Error('compiler error: PXXMemCopy not found');
      dcDestData := AllocVar('', tyPointer);
      IRAppend(IR_STORE_SYM, dcDestData,
        IRAppend(IR_LEA, dcTempSym, -1, -1, 0, Ord(tyPointer)), -1, 0, Ord(tyPointer));
      dcSrcStart := IRAppend(IR_BINOP,
        IRAppend(IR_LOAD_SYM, dcSrcTmp, -1, -1, 0, Ord(tyPointer)),
        IRAppend(IR_BINOP, IRAppend(IR_LOAD_SYM, dcIdxTmp, -1, -1, 0, Ord(tyInteger)),
          IRAppend(IR_CONST_INT, -1, -1, -1, dcElemSz, Ord(tyInteger)), Ord(tkStar), 0, Ord(tyInteger)),
        Ord(tkPlus), 0, Ord(tyPointer));
      dcNbytes := IRAppend(IR_BINOP, IRAppend(IR_LOAD_SYM, dcCntTmp, -1, -1, 0, Ord(tyInteger)),
        IRAppend(IR_CONST_INT, -1, -1, -1, dcElemSz, Ord(tyInteger)), Ord(tkStar), 0, Ord(tyInteger));
      first := IRAppend(IR_ARG, IRAppend(IR_LOAD_SYM, dcDestData, -1, -1, 0, Ord(tyPointer)),
                 -1, -1, 0, Ord(tyPointer));
      last := IRAppend(IR_ARG, dcSrcStart, -1, -1, 0, Ord(tyPointer));
      IRB[first] := last;
      argNode := IRAppend(IR_ARG, dcNbytes, -1, -1, 0, Ord(tyInteger));
      IRB[last] := argNode;
      { Store the (ignored) result so the call is linked into the statement
        stream — a bare call whose result is unused is not emitted. }
      IRAppend(IR_STORE_SYM, dcDestData, IRAppendCall(procIdx, first, -1, Ord(tyPointer)),
        -1, 0, Ord(tyPointer));

      { Like a dyn-array variable read: lea on the dyn-array symbol loads the
        handle (pointer-sized), so tag it tyPointer (an element-typed tag would
        make the assignment store only the element's width and truncate the
        64-bit handle). }
      Result := IRAppend(IR_LEA, dcTempSym, -1, -1, 0, Ord(tyPointer));
    end;

    AN_ASM:
      Result := IRAppend(IR_ASM, ASTLeft[node], ASTRight[node], -1, 0, Ord(tyUnknown));

    AN_IDENT:
    begin
      varIdx := ASTIVal[node];
      if TypeIsFrozenString(Syms[varIdx].TypeKind) or (Syms[varIdx].TypeKind = tySet) or Syms[varIdx].IsArray then
        Result := IRAppend(IR_LEA, varIdx, -1, -1, 0, ASTTk[node])
      else
        Result := IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, ASTTk[node]);
    end;

    AN_INDEX, AN_FIELD, AN_DEREF:
    begin
      left := IRLowerAddress(node);
      if CProgramMode and (ASTKind[node] = AN_FIELD) and
         RecFieldIsArray(ResolveNodeRec(ASTLeft[node]), GetASTIdentName(node)) and
         (RecFieldDynDepth(ResolveNodeRec(ASTLeft[node]), GetASTIdentName(node)) = 0) then
      begin
        { C fixed-array struct field (e.g. `char contents[N]`) decays to a pointer
          = the field's ADDRESS, exactly like an array variable (AN_IDENT IsArray
          -> IR_LEA above). Without this it would load the array's first bytes as a
          scalar value. }
        Result := left;
        IRTk[Result] := Ord(tyPointer);
      end
      else if CProgramMode and (ASTKind[node] = AN_FIELD) and
              (RecFieldBitWidth(ResolveNodeRec(ASTLeft[node]), GetASTIdentName(node)) > 0) then
        Result := IRLowerBitFieldRead(node, left,
                                      RecFieldType(ResolveNodeRec(ASTLeft[node]),
                                                   GetASTIdentName(node)))
      else if (IntToTypeKind(ASTTk[node]) = tyString) or (IntToTypeKind(ASTTk[node]) = tySet) then
      begin
        { A frozen-string / set value IS its address (no load). Present the
          address node with the value's frozen-string tag, mirroring the AN_IDENT
          path above: otherwise it carries IRLowerAddress's tyPointer tag and a
          consumer (e.g. `m := p^` into a managed string) misreads the address as
          a raw pointer instead of a frozen inline string. }
        Result := left;
        if IntToTypeKind(ASTTk[node]) = tyString then
          IRTk[Result] := ASTTk[node];
      end
      else if NodeDynDepth(node) > 0 then
        { Dynamic-array handle read (e.g. `rec.arr`, a nested sub-array): the
          value is a pointer-sized heap handle. ASTTk tags it with the ELEMENT
          type (Integer etc.), so an element-typed load would emit a 4-byte
          movsxd and sign-extend-truncate the 64-bit handle — a corrupted pointer
          whose first refcount/deref segfaults. Force a full pointer-width load. }
        Result := IRAppend(IR_LOAD_MEM, left, -1, -1, 0, Ord(tyPointer))
      else
        Result := IRAppend(IR_LOAD_MEM, left, -1, -1, 0, ASTTk[node]);
    end;

    AN_PTR_CAST:
    begin
      castTk := IntToTypeKind(ASTTk[node]);
      if (castTk = tyString) or (castTk = tyAnsiString) then
      begin
        if IsNodePChar(ASTLeft[node]) and not CProgramMode then
        begin
          procIdx := FindProc('PCharToString');
          if procIdx < 0 then Error('compiler error: PCharToString helper not found');

          wrapperArg := AllocNode(AN_ARG);
          ASTLeft[wrapperArg] := ASTLeft[node];
          ASTRight[wrapperArg] := -1;
          ASTTk[wrapperArg] := Ord(tyPointer);

          wrapperCall := AllocNode(AN_CALL);
          ASTIVal[wrapperCall] := procIdx;
          { Tag with PCharToString's ACTUAL return kind (AnsiString in managed
            mode, frozen tyString under -uPXX_MANAGED_STRING). Hardcoding tyString
            mislabelled the managed handle as frozen and miscompiled the result. }
          ASTTk[wrapperCall] := Ord(Procs[procIdx].RetType);
          ASTLeft[wrapperCall] := wrapperArg;
          ASTRight[wrapperCall] := -1;

          Result := IRLowerAST(wrapperCall);
          Exit;
        end;
      end;

      { PChar(managedString): the managed handle is already the NUL-terminated
        char pointer when non-empty, but an empty managed string is a nil handle —
        FPC guarantees PChar('') is a valid pointer to a static #0 byte, never nil.
        Route through PXXPCharOf, which substitutes that shared #0 byte for a nil
        handle, so a C/PAL call f(PChar(s)) on an empty s does not deref nil. The
        helper is registered whenever managed strings are in use (needHeapUnit);
        if absent (degenerate build) fall through to the bare reinterpret. }
      if (ASTIVal[node] = -2) and (ASTTk[ASTLeft[node]] = Ord(tyAnsiString)) then
      begin
        procIdx := FindProc('PXXPCharOf');
        if procIdx >= 0 then
        begin
          wrapperArg := AllocNode(AN_ARG);
          ASTLeft[wrapperArg] := ASTLeft[node];
          ASTRight[wrapperArg] := -1;
          ASTTk[wrapperArg] := Ord(tyPointer);

          wrapperCall := AllocNode(AN_CALL);
          ASTIVal[wrapperCall] := procIdx;
          ASTTk[wrapperCall] := Ord(tyPointer);
          ASTLeft[wrapperCall] := wrapperArg;
          ASTRight[wrapperCall] := -1;

          Result := IRLowerAST(wrapperCall);
          Exit;
        end;
      end;

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
      end
      else if ASTIVal[node] = -1 then
      begin
        { Builtin numeric/ordinal reinterpret (Int64/UInt64/Integer/Cardinal/...):
          re-tag the result IR node with the cast's width so width-sensitive ops
          (e.g. tkShl's 32-bit wrap) read the operand's real width. Without this,
          UInt64(1) lowers to the inner const's 32-bit IRTk and a shl-into-bit-31
          truncation would wrongly fire. See bug-shl-signed-integer-width. }
        castTk := IntToTypeKind(ASTTk[node]);
        if ((castTk = tyInt64) or (castTk = tyUInt64))
           and not ((IntToTypeKind(IRTk[Result]) = tyInt64)
                    or (IntToTypeKind(IRTk[Result]) = tyUInt64)) then
        begin
          { Widening numeric reinterpret 32->64 (e.g. Int64(someInteger)): on a
            32-bit target the inner value occupies one register and its high word
            is undefined; a bare re-tag tells consumers "this is 64-bit" but no
            sign/zero-extend ever runs (EmitNode64 widens only when the SOURCE tag
            is narrow). Force a real widen by adding 0: the inner node keeps its
            own narrow tag so the extend direction follows its signedness, and the
            sum carries the cast's 64-bit tag. No-op on 64-bit targets where the
            load is already full-width. See bug-i386-arm32-int64-conformance. }
          right := IRAppend(IR_CONST_INT, -1, -1, -1, 0, ASTTk[node]);
          Result := IRAppend(IR_BINOP, Result, right, Ord(tkPlus), 0, ASTTk[node]);
        end
        else if CProgramMode and TypeIsOrdinal(castTk) and
                TypeIsOrdinal(IntToTypeKind(IRTk[Result])) and
                (IRTk[Result] <> ASTTk[node]) then
        begin
          { Do not retag a width-sensitive load in place. `(int)byte_field`
            must load one byte and then widen the value; changing the load node
            to Integer makes codegen read four bytes from the byte field. }
          right := IRAppend(IR_CONST_INT, -1, -1, -1, 0, ASTTk[node]);
          Result := IRAppend(IR_BINOP, Result, right, Ord(tkPlus), 0, ASTTk[node]);
        end
        else
          IRTk[Result] := ASTTk[node];
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

    AN_SYSCALL:
    begin
      { Args (nr, a0..a5) as an IR_ARG chain; backend moves them into the
        target's syscall registers and emits the native trap instruction. }
      first := -1;
      last := -1;
      item := ASTLeft[node];
      while item <> -1 do
      begin
        value := IRLowerAST(ASTLeft[item]);
        argNode := IRAppend(IR_ARG, value, -1, -1, 0, ASTTk[ASTLeft[item]]);
        if first < 0 then first := argNode
        else IRB[last] := argNode;
        last := argNode;
        item := ASTRight[item];
      end;
      Result := IRAppend(IR_SYSCALL, first, -1, -1, 0, ASTTk[node]);
    end;

    AN_COSWITCH:
    begin
      { Two pointer args (pfrom, pto) as an IR_ARG chain; backend moves them into
        rdi/rsi and calls the bare CoSwitch stub. }
      first := -1;
      last := -1;
      item := ASTLeft[node];
      while item <> -1 do
      begin
        value := IRLowerAST(ASTLeft[item]);
        argNode := IRAppend(IR_ARG, value, -1, -1, 0, ASTTk[ASTLeft[item]]);
        if first < 0 then first := argNode
        else IRB[last] := argNode;
        last := argNode;
        item := ASTRight[item];
      end;
      Result := IRAppend(IR_COSWITCH, first, -1, -1, 0, ASTTk[node]);
    end;

    AN_YIELD:
    begin
      { value -> [self+CO_OFF_CURRENT], then CoSwitch(self+GENCTX -> self+CALLERCTX).
        IRIVal carries the generator self-pointer local sym idx. A record element
        does not fit the one-word current slot, so yield its ADDRESS instead — the
        stackful generator's frame keeps the record alive until the next resume,
        and the for-in desugar derefs the address into the loop variable. }
      if IntToTypeKind(ASTTk[ASTLeft[node]]) = tyRecord then
        value := IRLowerAddress(ASTLeft[node])
      else
        value := IRLowerAST(ASTLeft[node]);
      Result := IRAppend(IR_YIELD, value, -1, -1, ASTIVal[node], ASTTk[ASTLeft[node]]);
    end;

    AN_AWAIT:
    begin
      { Stackful (v1): documentary — `await E` evaluates exactly as `E`. The
        awaited call suspends on its own (reactor/CoYield). The stackless backend
        will instead split the state machine here. }
      Result := IRLowerAST(ASTLeft[node]);
    end;

    AN_STR_FROM_CHAR:
    begin
      { String(c): Left is the `__t := c` store (a 1-char string materialised into
        a hidden temp via the ordinary assignment path, frozen or managed); Right
        is the read of __t that yields the string value. No backend code — both
        sub-nodes are ordinary IR built at parse time. }
      { Mark the side-effect as a statement so a call-shaped Left (e.g. the
        synthesized ArgStr that fills a temp for inline ParamStr) is actually
        emitted; a store-shaped Left (String(c)) emits unconditionally, so the
        mark is a harmless no-op there. }
      IRMarkStatementNode(IRLowerAST(ASTLeft[node]));   { side-effect into hidden temp }
      Result := IRLowerAST(ASTRight[node]);
    end;

    AN_IS_TEST:
    begin
      varIdx := IRLowerClassMatch(ASTLeft[node], Integer(ASTIVal[node]), classIdx);
      Result := IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, Ord(tyBoolean));
    end;

    AN_AS_CAST:
    begin
      if UClsIsInterface[Integer(ASTIVal[node])] then
      begin
        { `obj as IFoo`: yield the address of the materialised fat pointer (the
          aggregate-by-reference convention, like a record-returning call). }
        Result := IRAppend(IR_LEA, IRMaterializeIntfCast(node, True), -1, -1, 0, Ord(tyPointer));
        Exit;
      end;
      { Checked downcast: compute the match, then yield the instance typed as T.
        nil passes through (nil as T = nil); a non-nil mismatch traps (Halt). }
      varIdx := IRLowerClassMatch(ASTLeft[node], Integer(ASTIVal[node]), classIdx);
      endLabel := IRNewLabel;     { continue (yield instance) }
      elseLabel := IRNewLabel;    { trap }
      left := IRAppend(IR_LOAD_SYM, classIdx, -1, -1, 0, Ord(tyPointer));
      value := IRAppend(IR_BINOP, left, IRAppend(IR_CONST_INT, -1, -1, -1, 0, Ord(tyPointer)),
                        Ord(tkNeq), 0, Ord(tyBoolean));
      IRAppend(IR_JUMP_IF_FALSE, endLabel, value, -1, 0, 0);   { nil -> pass through }
      right := IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, Ord(tyBoolean));
      IRAppend(IR_JUMP_IF_FALSE, elseLabel, right, -1, 0, 0);  { non-nil mismatch -> trap }
      IRAppend(IR_JUMP, endLabel, -1, -1, 0, 0);
      IRAppend(IR_LABEL, -1, -1, -1, elseLabel, 0);
      IRAppend(IR_TERMINATE, IRAppend(IR_CONST_INT, -1, -1, -1, 1, Ord(tyInteger)), -1, -1, AN_HALT, 0);
      IRAppend(IR_LABEL, -1, -1, -1, endLabel, 0);
      Result := IRAppend(IR_LOAD_SYM, classIdx, -1, -1, 0, Ord(tyClass));
    end;

    AN_CLASS_CAST:
    begin
      { Hard class reinterpret: the instance pointer is unchanged, only the
        static type. Pass the value through; .field/[i] on it resolve their
        offsets against the cast's class via ResolveNodeRec(AN_CLASS_CAST). }
      Result := IRLowerAST(ASTLeft[node]);
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
      { Fold a compile-time concat of two string/char literals (`'a' + 'b'`) to a
        single interned literal — constant folding, target-independent. Besides
        avoiding a runtime concat, this is the correctness fix for
        bug-string-literal-concat-compare-segfault: a literal-concat appearing as
        a comparison operand (`x = 'a' + 'b'`) otherwise fed the runtime
        string-concat result into the hand-emitted string-compare path and
        crashed. A folded single literal behaves exactly like writing the literal
        on one line (the known-good form), so assignment and comparison agree.
        ESP needs it regardless (no frozen-string concat path). }
      if (Integer(ASTIVal[node]) = Ord(tkPlus)) and
         IsConstStrLitNode(ASTLeft[node]) and IsConstStrLitNode(ASTRight[node]) then
      begin
        foldStr := ConstStrLitValue(ASTLeft[node]) + ConstStrLitValue(ASTRight[node]);
        foldOff := TokCharLen;
        for foldK := 1 to Length(foldStr) do
        begin
          TokChars[TokCharLen] := foldStr[foldK];
          Inc(TokCharLen);
        end;
        { Tag the folded result tyString — a plain one-line literal's kind — not
          ASTTk[node]. The surrounding expression may be tyAnsiString (e.g. a
          Concat-synthesised `+` chain in managed mode); emitting the literal as
          tyAnsiString would make downstream managed paths treat this static
          literal pointer as a heap handle and release it -> crash at scope exit
          (regressed test_concat_intrinsic). As tyString it behaves exactly like
          any other string literal and is coerced to managed on use. }
        Result := IRAppend(IR_CONST_STR, foldOff, Length(foldStr), -1, 0, Ord(tyString));
        Exit;
      end;

      { Short-circuit boolean and/or (FPC default {$B-}): evaluate the right
        operand only when the left has not already decided the result. The parser
        tags a logical (both-operands-boolean) and/or with ASTTk = tyBoolean;
        bitwise integer and/or keep an ordinal type and fall through to the
        unconditional IR_BINOP below. The result is held in a temp (a local when
        inside a proc, so recursion stays reentrant); the right operand's IR is
        lowered AFTER the conditional jump, so it sits past the branch in the
        linear statement stream and is skipped at runtime. }
      if ((Integer(ASTIVal[node]) = Ord(tkAnd)) or (Integer(ASTIVal[node]) = Ord(tkOr))) and
         (IntToTypeKind(ASTTk[node]) = tyBoolean) then
      begin
        varIdx := AllocVar('', tyBoolean);
        endLabel := IRNewLabel;
        left := IRLowerAST(ASTLeft[node]);
        IRAppend(IR_STORE_SYM, varIdx, left, -1, 0, Ord(tyBoolean));
        value := IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, Ord(tyBoolean));
        if Integer(ASTIVal[node]) = Ord(tkAnd) then
        begin
          { left false -> skip right (result already false) }
          IRAppend(IR_JUMP_IF_FALSE, endLabel, value, -1, 0, 0);
          right := IRLowerAST(ASTRight[node]);
          IRAppend(IR_STORE_SYM, varIdx, right, -1, 0, Ord(tyBoolean));
          IRAppend(IR_LABEL, -1, -1, -1, endLabel, 0);
        end
        else
        begin
          { left true -> skip right (result already true). Only JUMP_IF_FALSE
            exists, so branch to an "evaluate right" label when left is false,
            else jump straight to the end. }
          elseLabel := IRNewLabel;
          IRAppend(IR_JUMP_IF_FALSE, elseLabel, value, -1, 0, 0);
          IRAppend(IR_JUMP, endLabel, -1, -1, 0, 0);
          IRAppend(IR_LABEL, -1, -1, -1, elseLabel, 0);
          right := IRLowerAST(ASTRight[node]);
          IRAppend(IR_STORE_SYM, varIdx, right, -1, 0, Ord(tyBoolean));
          IRAppend(IR_LABEL, -1, -1, -1, endLabel, 0);
        end;
        Result := IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, Ord(tyBoolean));
        Exit;
      end;
      { Operator overloading: a <op> b on a class/record operand resolves to a
        call to the registered operator proc (lhs, rhs), mirroring the direct
        backend. Args are passed by value (rdi=lhs, rsi=rhs). }
      cpi := FindOpOverload(Integer(ASTIVal[node]), ASTTk[ASTLeft[node]], ResolveNodeRec(ASTLeft[node]));
      if cpi >= 0 then
      begin
        left  := IRLowerCallArg(cpi, 0, ASTLeft[node], Procs[cpi].Params[0].IsRef);
        first := IRAppend(IR_ARG, left, -1, -1, 0, ASTTk[ASTLeft[node]]);
        right := IRLowerCallArg(cpi, 1, ASTRight[node], Procs[cpi].Params[1].IsRef);
        last  := IRAppend(IR_ARG, right, -1, -1, 0, ASTTk[ASTRight[node]]);
        IRB[first] := last;
        Result := IRAppendCall(cpi, first, -1, ASTTk[node]);
      end
      else if ((Integer(ASTIVal[node]) = Ord(tkEq)) or (Integer(ASTIVal[node]) = Ord(tkNeq))) and
              (NodeIsInterface(ASTLeft[node]) or NodeIsInterface(ASTRight[node])) then
      begin
        { Interface identity: two interface values are equal iff they reference
          the same instance, so compare the fat pointers' instance words (not the
          IMT word, which is shared by every instance of a class). `iface = nil`
          compares the instance word against 0. }
        left := IRIntfInstanceWord(ASTLeft[node]);
        right := IRIntfInstanceWord(ASTRight[node]);
        Result := IRAppend(IR_BINOP, left, right, Integer(ASTIVal[node]), 0, Ord(tyBoolean));
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
        if (ASTIVal[node] = Ord(tkMinus)) and
           IRNodePointerBase(ASTLeft[node]) and
           IRNodePointerBase(ASTRight[node]) then
        begin
          { Pointer difference `p - q` = (address_p - address_q) / sizeof(element)
            (C ptrdiff). Both operands are pointers; subtract addresses then divide
            by the element stride. }
          left := IRLowerAST(ASTLeft[node]);
          right := IRLowerAST(ASTRight[node]);
          Result := IRAppend(IR_BINOP, left, right, Ord(tkMinus), 0, Ord(tyInt64));
          elemSize := IRPointerStride(ASTLeft[node]);
          if elemSize > 1 then
          begin
            item := IRAppend(IR_CONST_INT, -1, -1, -1, elemSize, Ord(tyInt64));
            { tkDiv = integer division (tkSlash is the float `/` path) }
            Result := IRAppend(IR_BINOP, Result, item, Ord(tkDiv), 0, Ord(tyInt64));
          end;
        end
        else if ((ASTIVal[node] = Ord(tkPlus)) or (ASTIVal[node] = Ord(tkMinus))) and
           IRNodePointerBase(ASTLeft[node]) and
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
                IRNodePointerBase(ASTRight[node]) then
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

    AN_VAR_DECL:
    begin
      varIdx := ASTIVal[node];
      if SymNeedsZeroing(varIdx, zeroBytes) then
      begin
        IRAppend(IR_ZERO_SYM, varIdx, -1, -1, 0, Ord(Syms[varIdx].TypeKind));
      end;
      if ASTLeft[node] <> -1 then
        Result := IRLowerAST(ASTLeft[node])
      else
        Result := -1;
    end;

    AN_ASSIGN:
    begin
      lhsTk := IntToTypeKind(ASTTk[ASTLeft[node]]);
      if (lhsTk = tyUnknown) and (ASTKind[ASTLeft[node]] = AN_IDENT) then
      begin
        varIdx := ASTIVal[ASTLeft[node]];
        if (varIdx >= 0) and (varIdx < SymCount) then
          lhsTk := Syms[varIdx].TypeKind;
      end;
      lhsStoreTk := lhsTk;
      if ASTKind[ASTLeft[node]] = AN_FIELD then
      begin
        slFldRec := ResolveNodeRec(ASTLeft[ASTLeft[node]]);
        slFldName := GetASTIdentName(ASTLeft[node]);
        if slFldRec <> REC_NONE then
          lhsStoreTk := RecFieldType(slFldRec, slFldName);
        if (lhsTk = tyUnknown) or (lhsTk = tyAuto) then
          lhsTk := lhsStoreTk;
      end;
      if ASTKind[ASTRight[node]] = AN_DEFAULT then
      begin
        if (lhsTk = tyUnknown) or (lhsTk = tyAuto) then
          Error('default requires a known target type');
        ASTTk[ASTRight[node]] := Ord(lhsTk);
        if (lhsTk = tyRecord) or (lhsTk = tySet) or
           ((ASTKind[ASTLeft[node]] = AN_IDENT) and Syms[ASTIVal[ASTLeft[node]]].IsArray and
            not (Syms[ASTIVal[ASTLeft[node]]].ArrLen = -1)) then
        begin
          leftAddr := IRLowerAddress(ASTLeft[node]);
          if lhsTk = tyRecord then
          begin
            idx := ResolveNodeRec(ASTLeft[node]);
            elemSize := RecSize(idx);
            if RecordHasManagedFields(idx) then
              Result := IRAppend(IR_DEFAULT_MEM, leftAddr, -1, idx, elemSize, Ord(lhsTk))
            else
              Result := IRAppend(IR_DEFAULT_MEM, leftAddr, -1, REC_NONE, elemSize, Ord(lhsTk));
          end
          else if lhsTk = tySet then
            Result := IRAppend(IR_DEFAULT_MEM, leftAddr, -1, REC_NONE, TypeSize(tySet), Ord(lhsTk))
          else
          begin
            varIdx := ASTIVal[ASTLeft[node]];
            if Syms[varIdx].ElemType = tyRecord then
              elemSize := RecSize(Syms[varIdx].ElemRecName)
            else
              elemSize := TypeSize(Syms[varIdx].ElemType);
            Result := IRAppend(IR_DEFAULT_MEM, leftAddr, -1, REC_NONE,
                               Syms[varIdx].ArrLen * elemSize, ASTTk[ASTLeft[node]]);
          end;
        end
        else
        begin
          if lhsTk = tyString then
            value := IRAppend(IR_CONST_STR, 0, 0, -1, 0, Ord(tyString))
          else
            value := IRAppend(IR_CONST_INT, -1, -1, -1, 0, Ord(lhsTk));
          if ASTKind[ASTLeft[node]] = AN_IDENT then
            Result := IRAppend(IR_STORE_SYM, ASTIVal[ASTLeft[node]], value, -1, 0, ASTTk[ASTLeft[node]])
          else
          begin
            leftAddr := IRLowerAddress(ASTLeft[node]);
            Result := IRAppend(IR_STORE_MEM, leftAddr, value, -1, 0, Ord(lhsStoreTk));
          end;
        end;
      end
      else
      begin
      if (lhsTk = tyString) or (lhsTk = tyAnsiString) then
      begin
        if IsNodePChar(ASTRight[node]) and not CProgramMode then
        begin
          procIdx := FindProc('PCharToString');
          if procIdx < 0 then Error('compiler error: PCharToString helper not found');

          wrapperArg := AllocNode(AN_ARG);
          ASTLeft[wrapperArg] := ASTRight[node];
          ASTRight[wrapperArg] := -1;
          ASTTk[wrapperArg] := Ord(tyPointer);

          wrapperCall := AllocNode(AN_CALL);
          ASTIVal[wrapperCall] := procIdx;
          { Tag with PCharToString's ACTUAL return kind (AnsiString in managed
            mode, frozen tyString under -uPXX_MANAGED_STRING). Hardcoding tyString
            mislabelled the managed handle as frozen and miscompiled the result. }
          ASTTk[wrapperCall] := Ord(Procs[procIdx].RetType);
          ASTLeft[wrapperCall] := wrapperArg;
          ASTRight[wrapperCall] := -1;

          ASTRight[node] := wrapperCall;
        end;
      end;

      { Class -> interface: build the CORBA fat pointer {IMT, instance} into the
        LHS. The IMT for (RHS static class, interface) is captured here; the
        instance pointer is the RHS value. (interface := interface falls through
        to the 16-byte record copy below.) }
      if lhsTk = tyRecord then
      begin
        varIdx := ResolveNodeRec(ASTLeft[node]);
        isComIntf := (varIdx >= REC_UCLASS_BASE) and
                     UClsIsInterface[varIdx - REC_UCLASS_BASE] and
                     UClsIsComInterface[varIdx - REC_UCLASS_BASE];
        { interface := nil — zero the whole fat pointer {nil, nil}. The RHS is a
          pointer/ordinal nil, not a class or interface, so it never reaches the
          record-copy path (which would dereference a bogus source). }
        if (varIdx >= REC_UCLASS_BASE) and UClsIsInterface[varIdx - REC_UCLASS_BASE] and
           (IntToTypeKind(ASTTk[ASTRight[node]]) <> tyClass) and
           (IntToTypeKind(ASTTk[ASTRight[node]]) <> tyRecord) then
        begin
          { COM/ARC: release the old reference before discarding the slot. }
          if isComIntf then
          begin
            first := IRAppend(IR_ARG, IRLowerAddress(ASTLeft[node]), -1, -1, 0, Ord(tyPointer));
            seq := IRAppendCall(FindProc('PXXIntfRelease'), first, -1, Ord(tyNativeInt));
            IRIVal[seq] := 1;  { statement-level: side-effect call, result discarded }
          end;
          Result := IRAppend(IR_DEFAULT_MEM, IRLowerAddress(ASTLeft[node]),
                             -1, REC_NONE, RecSize(varIdx), Ord(tyRecord));
          Exit;
        end;
        if (varIdx >= REC_UCLASS_BASE) and UClsIsInterface[varIdx - REC_UCLASS_BASE] and
           (IntToTypeKind(ASTTk[ASTRight[node]]) = tyClass) then
        begin
          classIdx := ResolveNodeRec(ASTRight[node]);
          procIdx := FindIMT(classIdx - REC_UCLASS_BASE, varIdx - REC_UCLASS_BASE);
          if procIdx < 0 then Error('class does not implement the interface');
          if isComIntf then
          begin
            { COM/ARC class -> interface. Stash the new (IMT, instance) in scratch
              slots, retain the new reference, release the old slot, then publish.
              Retain-before-release keeps re-assigning the same object safe. }
            intfTmpImt := AllocVar('', tyPointer);
            IRAppend(IR_STORE_SYM, intfTmpImt,
                     IRAppend(IR_IMTADDR, procIdx, -1, -1, 0, Ord(tyPointer)), -1, 0, Ord(tyPointer));
            intfTmpInst := AllocVar('', tyPointer);
            IRAppend(IR_STORE_SYM, intfTmpInst, IRLowerAST(ASTRight[node]), -1, 0, Ord(tyPointer));
            first := IRAppend(IR_ARG, IRAppend(IR_LOAD_SYM, intfTmpImt, -1, -1, 0, Ord(tyPointer)), -1, -1, 0, Ord(tyPointer));
            argNode := IRAppend(IR_ARG, IRAppend(IR_LOAD_SYM, intfTmpInst, -1, -1, 0, Ord(tyPointer)), -1, -1, 0, Ord(tyPointer));
            IRB[first] := argNode;
            seq := IRAppendCall(FindProc('PXXIntfAddRefRaw'), first, -1, Ord(tyNativeInt));
            IRIVal[seq] := 1;
            first := IRAppend(IR_ARG, IRLowerAddress(ASTLeft[node]), -1, -1, 0, Ord(tyPointer));
            seq := IRAppendCall(FindProc('PXXIntfRelease'), first, -1, Ord(tyNativeInt));
            IRIVal[seq] := 1;
            leftAddr := IRLowerAddress(ASTLeft[node]);
            IRAppend(IR_STORE_MEM, leftAddr,
                     IRAppend(IR_LOAD_SYM, intfTmpImt, -1, -1, 0, Ord(tyPointer)), -1, 0, Ord(tyPointer));
            outNode := IRAppend(IR_BINOP, IRLowerAddress(ASTLeft[node]),
                                IRAppend(IR_CONST_INT, -1, -1, -1, TARGET_PTR_SIZE, Ord(tyInteger)),
                                Ord(tkPlus), 0, Ord(tyPointer));
            Result := IRAppend(IR_STORE_MEM, outNode,
                               IRAppend(IR_LOAD_SYM, intfTmpInst, -1, -1, 0, Ord(tyPointer)), -1, 0, Ord(tyPointer));
            Exit;
          end;
          leftAddr := IRLowerAddress(ASTLeft[node]);
          IRAppend(IR_STORE_MEM, leftAddr,
                   IRAppend(IR_IMTADDR, procIdx, -1, -1, 0, Ord(tyPointer)), -1, 0, Ord(tyPointer));
          value := IRLowerAST(ASTRight[node]);
          outNode := IRAppend(IR_BINOP, IRLowerAddress(ASTLeft[node]),
                              IRAppend(IR_CONST_INT, -1, -1, -1, TARGET_PTR_SIZE, Ord(tyInteger)),
                              Ord(tkPlus), 0, Ord(tyPointer));
          Result := IRAppend(IR_STORE_MEM, outNode, value, -1, 0, Ord(tyPointer));
          Exit;
        end;
        { COM/ARC interface -> interface (RHS is another interface lvalue):
          retain source, release old dest, copy the fat pointer — all in the
          ARC-correct order inside PXXIntfAssign. }
        if isComIntf and
           ((ASTKind[ASTRight[node]] = AN_IDENT) or (ASTKind[ASTRight[node]] = AN_FIELD) or
            (ASTKind[ASTRight[node]] = AN_INDEX) or (ASTKind[ASTRight[node]] = AN_DEREF)) and
           (ResolveNodeRec(ASTRight[node]) >= REC_UCLASS_BASE) and
           UClsIsInterface[ResolveNodeRec(ASTRight[node]) - REC_UCLASS_BASE] then
        begin
          first := IRAppend(IR_ARG, IRLowerAddress(ASTLeft[node]), -1, -1, 0, Ord(tyPointer));
          argNode := IRAppend(IR_ARG, IRLowerAddress(ASTRight[node]), -1, -1, 0, Ord(tyPointer));
          IRB[first] := argNode;
          Result := IRAppendCall(FindProc('PXXIntfAssign'), first, -1, Ord(tyPointer));
          IRIVal[Result] := 1;
          Exit;
        end;
      end;

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
          directly — Code at field+0, Data at field+TARGET_PTR_SIZE (8 on
          64-bit, 4 on i386/arm32, matching the user TMethod's Data offset). }
        left := ASTRight[node];
        leftAddr := IRLowerAddress(ASTLeft[node]);
        value := IRAppend(IR_PROCADDR, Integer(ASTIVal[left]), -1, -1, 0, Ord(tyPointer));
        IRAppend(IR_STORE_MEM, leftAddr, value, -1, 0, Ord(tyPointer));
        right := IRLowerAddress(ASTLeft[node]);
        item := IRAppend(IR_CONST_INT, -1, -1, -1, TARGET_PTR_SIZE, Ord(tyInteger));
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
      else if (ASTKind[ASTLeft[node]] = AN_IDENT) and
              (ASTIVal[ASTLeft[node]] >= 0) and
              Syms[ASTIVal[ASTLeft[node]]].IsArray and
              (Syms[ASTIVal[ASTLeft[node]]].ArrLen >= 0) and
              (SymArrNDims[ASTIVal[ASTLeft[node]]] <= 1) and
              (SymElemDynDepth[ASTIVal[ASTLeft[node]]] = 0) and
              (Syms[ASTIVal[ASTLeft[node]]].ElemType <> tyAnsiString) and
              (Syms[ASTIVal[ASTLeft[node]]].ElemType <> tyString) and
              not ((Syms[ASTIVal[ASTLeft[node]]].ElemType = tyRecord) and
                   RecordHasManagedFields(Syms[ASTIVal[ASTLeft[node]]].ElemRecName)) and
              rhsIsLValue then
      begin
        { Whole static-array assignment (`b := a`). The scalar store path below
          moves only one element's width, leaving the rest of `b` as garbage
          (bug-fixed-array-assignment-no-copy). Copy the full ArrLen*elemSize
          via IR_COPY_REC, mirroring the whole-record path and the static-array
          arg-copy idiom above. Managed-element arrays (string / managed-record
          elements) need per-element ARC and are left to the scalar path. }
        i := ASTIVal[ASTLeft[node]];
        if Syms[i].ElemType = tyRecord then elemSize := RecSize(Syms[i].ElemRecName)
        else elemSize := TypeSize(Syms[i].ElemType);
        leftAddr := IRLowerAddress(ASTLeft[node]);
        right := IRLowerAddress(ASTRight[node]);
        Result := IRAppend(IR_COPY_REC, leftAddr, right, -1,
                           Syms[i].ArrLen * elemSize, Ord(tyRecord));
      end
      else if CProgramMode and (ASTKind[ASTLeft[node]] = AN_FIELD) and
              (RecFieldBitWidth(ResolveNodeRec(ASTLeft[ASTLeft[node]]),
                                GetASTIdentName(ASTLeft[node])) > 0) then
      begin
        value := IRLowerAST(ASTRight[node]);
        lhsStoreTk := RecFieldType(ResolveNodeRec(ASTLeft[ASTLeft[node]]),
                                   GetASTIdentName(ASTLeft[node]));
        IRLowerBitFieldStore(ASTLeft[node], value, lhsStoreTk);
        Result := IRLowerBitFieldRead(ASTLeft[node], IRLowerAddress(ASTLeft[node]), lhsStoreTk);
      end
      else if (ASTKind[ASTLeft[node]] <> AN_IDENT) and
              (NodeDynDepth(ASTLeft[node]) > 0) then
      begin
        { Whole dynamic-array assignment into a non-IDENT lvalue (a record/object
          dyn-array field, or a nested sub-array slot). The source handle is
          pointer-sized; store all 8 bytes into the field address. Without this
          the generic scalar store below used the element width (truncating the
          8-byte handle to 4) and the field ended up holding the source's slot
          address rather than its handle -> segfault on the next index/Length.

          On x86-64 use the ARC-correct IR_STORE_DYN: retain the new handle and
          element-aware release the old one, matching the IR_STORE_SYM IDENT
          path. Without that retain, assigning a LOCAL dyn array to a field
          (`field := tmp`) shares the handle, and the local's scope-exit release
          frees the data the field still points at — managed-element strings come
          back empty, and a shrinking rebuild segfaults
          (bug-dynarray-managed-record-field-reassign). Other targets keep the
          bare handle store (share-semantics) for now; the new op is x86-64-only,
          so they never see it. }
        value := IRLowerAST(ASTRight[node]);
        leftAddr := IRLowerAddress(ASTLeft[node]);
        if TargetArch = TARGET_X86_64 then
        begin
          Result := IRAppend(IR_STORE_DYN, leftAddr, value,
                             NodeDynDepth(ASTLeft[node]), -1,
                             Ord(NodeDynBaseTk(ASTLeft[node])));
          IRSetLenBaseRec[Result] := NodeDynBaseRec(ASTLeft[node]);
        end
        else
          Result := IRAppend(IR_STORE_MEM, leftAddr, value, -1, 0, Ord(tyPointer));
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
        { A C string literal stored to a pointer must land on char 0, not the
          8-byte Pascal length prefix the literal's handle points at. Apply the
          same +8 skip the call-argument path uses (see the tyString->tyPointer
          marshalling in AN_CALL). C-mode only -> Pascal self-build unaffected. }
        if CProgramMode and (ASTKind[ASTRight[node]] = AN_STR_LIT) and
           (lhsTk = tyPointer) then
          value := IRAppend(IR_BINOP, value,
                            IRAppend(IR_CONST_INT, -1, -1, -1, 8, Ord(tyInteger)),
                            Ord(tkPlus), 0, Ord(tyPointer));
        if ASTKind[ASTLeft[node]] = AN_IDENT then
        begin
          Result := IRAppend(IR_STORE_SYM, ASTIVal[ASTLeft[node]], value, -1, 0, ASTTk[ASTLeft[node]]);
          { In C an assignment is an expression yielding the stored value, so load
            it back; this lets `g(p = x)` / `(p = x)->f` use the value. Pascal keeps
            the store node as the result -> self-build byte-identical. }
          if CProgramMode then
            Result := IRAppend(IR_LOAD_SYM, ASTIVal[ASTLeft[node]], -1, -1, 0, ASTTk[ASTLeft[node]]);
        end
        else
        begin
          leftAddr := IRLowerAddress(ASTLeft[node]);
          Result := IRAppend(IR_STORE_MEM, leftAddr, value, -1, 0, Ord(lhsStoreTk));
          if CProgramMode then
            Result := IRAppend(IR_LOAD_MEM, leftAddr, -1, -1, 0, Ord(lhsStoreTk));
        end;
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
      else if (CurProc < 0) and (ASTLeft[node] <> -1) then
      begin
        { `return <expr>` from a top-level C main (no enclosing proc): the value
          IS the process exit code, so terminate with it like Halt(expr). Pascal
          program-level Exit never carries a value, so this never fires in a
          self-build (byte-identical preserved). }
        value := IRLowerAST(ASTLeft[node]);
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
        { Managed AnsiString target reached through a non-symbol lvalue (record/
          class field, var-param field, index, deref): address the slot
          generically and resize via PXXStrSetLen. The address-based op needs no
          symbol reconstruction, so a field works like a plain variable
          (bug-setlength-record-field-via-var-param). A plain symbol target
          (AN_IDENT, incl a by-ref `var s: string` param) keeps the existing
          symbol path — on x86-64 that is the amortized in-place inline resize, so
          string-building stays O(n). Only tyAnsiString reaches here; frozen
          inline strings take the -101 store-length path. }
        if NodeIsManagedString(slTargetAST) and (ASTKind[slTargetAST] <> AN_IDENT) then
        begin
          slTargetAddr := IRLowerAddress(slTargetAST);
          slCountNode := IRLowerAST(slCountAST);
          Result := IRAppend(IR_SETLEN_STR, slTargetAddr, slCountNode, -1, -1, Ord(tyAnsiString));
          Exit;
        end;
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
        { Dynamic-array FIELD target (obj.field): no root symbol, so address the
          slot via the field and carry element metadata on the node. Covers any
          depth, including managed-string/record element leaves. }
        if ASTKind[slTargetAST] = AN_FIELD then
        begin
          slFldRec := ResolveNodeRec(ASTLeft[slTargetAST]);
          slFldName := GetASTIdentName(slTargetAST);
          slFldDepth := RecFieldDynDepth(slFldRec, slFldName);
          if slFldDepth > 0 then
          begin
            slFldBaseTk := RecFieldType(slFldRec, slFldName);
            slFldBaseRec := RecFieldRecId(slFldRec, slFldName);
            slTargetAddr := IRLowerAddress(slTargetAST);
            slCountNode := IRLowerAST(slCountAST);
            Result := IRAppend(IR_SETLEN_DYN, slTargetAddr, slCountNode,
                               slFldDepth, -1, Ord(slFldBaseTk));
            IRSetLenBaseRec[Result] := slFldBaseRec;
            Exit;
          end;
        end;
        { Nested sub-array SLOT reached through a non-array-symbol root — e.g.
          `SetLength(rec.matrix[i], n)`, where `matrix` is an `array of array of
          T` FIELD. The base symbol is the record (dyn depth 0) so the depth>=2
          symbol path above does not fire, and the target is an AN_INDEX (not a
          bare field) so the field path does not either. Use the slot-address
          path with leaf element metadata walked from the dyn-array base
          (NodeDynBaseTk/Rec handle the field+index chain). The array-symbol
          rooted nested case (`m[i]`) is already taken by the depth>=2 branch. }
        if (ASTKind[slTargetAST] = AN_INDEX) and (NodeDynDepth(slTargetAST) >= 1) then
        begin
          slDepth := NodeDynDepth(slTargetAST);
          slTargetAddr := IRLowerAddress(slTargetAST);
          slCountNode := IRLowerAST(slCountAST);
          Result := IRAppend(IR_SETLEN_DYN, slTargetAddr, slCountNode, slDepth,
                             -1, Ord(NodeDynBaseTk(slTargetAST)));
          IRSetLenBaseRec[Result] := NodeDynBaseRec(slTargetAST);
          Exit;
        end;
      end;
      if cpi = -201 then
      begin
        argVal := ASTLeft[item];
        argTk := IntToTypeKind(ASTTk[argVal]);
        if argTk = tyVariant then
        begin
          procIdx := FindProc('VariantToStr');
          if procIdx < 0 then Error('str: VariantToStr builtin not loaded');
          value := IRLowerAddress(argVal);
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyVariant));
          Result := IRAppendCall(procIdx, argNode, -1, Ord(tyAnsiString));
          Exit;
        end;
        if TypeIsFloat(argTk) then
        begin
          { str(float): format via the RTL FloatToStr (natural decimal). }
          procIdx := FindProc('FloatToStr');
          if procIdx < 0 then Error('str: builtin unit not loaded');
          value := IRLowerAST(argVal);                       { double bits in rax }
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyDouble));
          Result := IRAppendCall(procIdx, argNode, -1, Ord(Procs[procIdx].RetType));
          Exit;
        end;
        value := IRLowerAST(argVal);

        procIdx := FindProc('StrInt');
        if procIdx < 0 then Error('str: builtin unit not loaded');

        argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(argTk));
        first := argNode;

        zeroVal := IRAppend(IR_CONST_INT, 0, -1, -1, 0, Ord(tyInteger));
        argNode2 := IRAppend(IR_ARG, zeroVal, -1, -1, 0, Ord(tyInteger));
        IRB[argNode] := argNode2;

        Result := IRAppendCall(procIdx, first, -1, Ord(Procs[procIdx].RetType));
        Exit;
      end;
      pathIdx := 0;
      classIdx := -1;
      pendBase := PendOAWBCount;   { open-array copy-out writebacks added by this call's args }
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
            { Force-address the Length arg only when it is an lvalue (string/array
              variable, field, element): the codegen reads its [-8] header from the
              slot. A non-lvalue string VALUE (a concat / function result) is
              lowered as a value instead — the codegen's tyAnsiString-value path
              reads the length from the handle directly. }
            if pathIdx = 0 then isRefArg := IsASTLValue(ASTLeft[item]);
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

        { Length(F()) where F returns a dynamic array: the call result is a heap
          handle (data ptr), not an lvalue, so the force-address path can't fire
          and the value path would deref it as an address ([rax]) and read the
          first element instead of the [-8] count. Bind the handle to a hidden
          dynamic-array local and hand its IR_LEA to the Length codegen — the same
          shape a dyn-array variable produces, so every backend's existing
          dyn-array Length path serves it. See bug-length-of-dynarray-call-result. }
        { Length(ps^) / Length(rec.pf^) over a managed string (ps: ^string): `@s`
          of a managed string yields the HANDLE (the heap data pointer) itself,
          so `ps` holds the handle and `ps^` IS that handle. Its address-lowering
          (IRLowerAddress AN_DEREF) collapses to a bare load of ps tagged
          tyPointer, which the Length codegen's catch-all then derefs once more
          ([handle]) and returns the first data word instead of the [handle-8]
          length (garbage). Lower it instead as the plain handle load retagged
          tyAnsiString: that is the same shape a managed-string VALUE produces, so
          every backend's tyAnsiString Length path (no extra deref -> test ->
          [-8]) serves it with no codegen change. Frozen `ps^` keeps tyString and
          is untouched; managed strings don't exist on ESP so riscv32/xtensa never
          see this. The deref is borrowed (ASTKind AN_DEREF is already excluded
          from the managed-temp owning path above), so no double-free. See
          bug-managed-length-via-pointer-deref. }
        if (cpi < 0) and (-cpi = Ord(tkLength)) and (pathIdx = 0) and
           (ASTKind[ASTLeft[item]] = AN_DEREF) and
           (IntToTypeKind(ASTTk[ASTLeft[item]]) = tyAnsiString) then
        begin
          value := IRLowerAST(ASTLeft[ASTLeft[item]]);
          IRTk[value] := Ord(tyAnsiString);
        end
        else if (cpi < 0) and (-cpi = Ord(tkLength)) and (pathIdx = 0) and
           (ASTKind[ASTLeft[item]] = AN_CALL) and (ASTIVal[ASTLeft[item]] >= 0) and
           ProcRetIsDynArray[ASTIVal[ASTLeft[item]]] then
        begin
          dynLenPi := ASTIVal[ASTLeft[item]];
          dynLenTmp := AllocVar('', tyPointer);
          Syms[dynLenTmp].IsArray := True;
          Syms[dynLenTmp].ArrLen := -1;
          SymDynDepth[dynLenTmp] := 1;
          Syms[dynLenTmp].ElemType := ProcRetElemTk[dynLenPi];
          Syms[dynLenTmp].ElemRecName := ProcRetElemRec[dynLenPi];
          callVal := IRLowerAST(ASTLeft[item]);
          IRAppend(IR_STORE_SYM, dynLenTmp, callVal, -1, 0, Ord(tyPointer));
          value := IRAppend(IR_LEA, dynLenTmp, -1, -1, 0, Ord(tyPointer));
        end
        else
          value := IRLowerCallArg(cpi, pathIdx, ASTLeft[item], isRefArg);

        { A materialised managed-string argument (a literal, concat, char/string
          coercion, or function result — anything that is not an existing lvalue)
          is refcount 1 with no owner, so passing it directly leaks one reference
          per call. Bind it to a hidden owning local and pass that by borrow: the
          local's store releases the previous value (loop reuse) and the epilog's
          managed-local release frees it at scope exit. Only fires under managed
          strings (tyAnsiString exists only with PXX_MANAGED_STRING), so the
          self-hosted compiler build is unaffected. }
        argIsManagedTemp :=
          (not isRefArg) and (cpi >= 0) and (pathIdx < Procs[cpi].ParamCount) and
          (Procs[cpi].Params[pathIdx].TypeKind = tyAnsiString) and
          (ASTKind[ASTLeft[item]] <> AN_IDENT) and
          (ASTKind[ASTLeft[item]] <> AN_FIELD) and
          (ASTKind[ASTLeft[item]] <> AN_INDEX) and
          (ASTKind[ASTLeft[item]] <> AN_DEREF);

        { Auto const char* marshalling: a string argument passed to a Pointer
          parameter gets the same +8 length-prefix skip as an explicit PChar()
          cast, so C bindings pass a Pascal string without PChar() boilerplate.
          The string data at Offset+8 is NUL-terminated by InternStr. }
        if (not isRefArg) and (cpi >= 0) and
           (IntToTypeKind(IRTk[value]) = tyString) and
           (((pathIdx < Procs[cpi].ParamCount) and
             (Procs[cpi].Params[pathIdx].TypeKind = tyPointer)) or
            (ProcVariadic[cpi] and (pathIdx >= Procs[cpi].ParamCount))) then
        begin
          { A string passed to a Pointer param OR as a variadic arg (the callee's
            va_arg(char*) wants C char data, not the Pascal length prefix) gets the
            +8 length-prefix skip. }
          right := IRAppend(IR_CONST_INT, -1, -1, -1, 8, Ord(tyInteger));
          value := IRAppend(IR_BINOP, value, right, Ord(tkPlus), 0, Ord(tyPointer));
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyPointer));
        end
        else if (not isRefArg) and (cpi >= 0) and (pathIdx < Procs[cpi].ParamCount) and
           (Procs[cpi].Params[pathIdx].TypeKind = tyPointer) and
           (IntToTypeKind(ASTTk[ASTLeft[item]]) = tyAnsiString) then
          { A managed string arg to a Pointer (const char*) param: the tyAnsiString
            value is ALREADY a char pointer (no inline length prefix), so pass it
            as-is — the dual of the frozen tyString +8 skip above. Scalar `string`
            resolves to tyAnsiString in managed mode, so this is the common path. }
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyPointer))
        else if argIsManagedTemp then
        begin
          hiddenArgSym := AllocVar('', tyAnsiString);
          SymIsHiddenArgTemp[hiddenArgSym] := True;
          IRAppend(IR_DEFAULT_MEM,
            IRAppend(IR_SLOTADDR, hiddenArgSym, -1, -1, 0, Ord(tyPointer)),
            -1, REC_NONE, TARGET_PTR_SIZE, Ord(tyAnsiString));
          IRAppend(IR_STORE_SYM, hiddenArgSym, value, -1, 0, Ord(tyAnsiString));
          value := IRAppend(IR_LOAD_SYM, hiddenArgSym, -1, -1, 0, Ord(tyAnsiString));
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyAnsiString));
        end
        else
          argNode := IRAppend(IR_ARG, value, -1, -1, 0, ASTTk[ASTLeft[item]]);
        if first < 0 then first := argNode
        else IRB[last] := argNode;
        last := argNode;
        item := ASTRight[item];
        Inc(pathIdx);
      end;
      { Default parameters: a call that omitted trailing args supplies each
        remaining param's constant default (ordinal/char/bool/enum). MatchProcCall
        already accepted the shorter arity (ProcArityMatches). }
      cpi := ASTIVal[node];
      if cpi >= 0 then
        while (pathIdx < Procs[cpi].ParamCount) and (pathIdx < 16) and
              ProcParamHasDefault[cpi * 16 + pathIdx] do
        begin
          argNode := IRAppend(IR_ARG,
            IRAppend(IR_CONST_INT, -1, -1, -1, ProcParamDefaultVal[cpi * 16 + pathIdx],
                     Ord(Procs[cpi].Params[pathIdx].TypeKind)),
            -1, -1, 0, Ord(Procs[cpi].Params[pathIdx].TypeKind));
          if first < 0 then first := argNode else IRB[last] := argNode;
          last := argNode;
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
      { copy-OUT the open-array writebacks this call's args registered (a static
        array passed to a `var`/`out` open-array param): temp data -> static
        array, after the call. Emitted by the linear IR_COPY_REC driver in append
        order, so it runs after the call. A function result lives in rax/xmm0 at
        this point and the COPY_REC would clobber it, so spill it to a temp before
        the writeback and reload it afterwards (the reload node has a higher index
        and therefore emits after the COPY_REC). }
      if PendOAWBCount > pendBase then
      begin
        if Procs[ASTIVal[node]].IsFunc then
        begin
          value := AllocVar('', IntToTypeKind(ASTTk[node]));
          IRAppend(IR_STORE_SYM, value, Result, -1, 0, ASTTk[node]);
          while PendOAWBCount > pendBase do
          begin
            Dec(PendOAWBCount);
            IRAppend(IR_COPY_REC,
              IRLowerAddress(PendOAWBDest[PendOAWBCount]),
              IRAppend(IR_BINOP,
                IRAppend(IR_SLOTADDR, PendOAWBTemp[PendOAWBCount], -1, -1, 0, Ord(tyPointer)),
                IRAppend(IR_CONST_INT, -1, -1, -1, 8, Ord(tyInteger)),
                Ord(tkPlus), 0, Ord(tyPointer)),
              -1, PendOAWBSize[PendOAWBCount], Ord(tyRecord));
          end;
          Result := IRAppend(IR_LOAD_SYM, value, -1, -1, 0, ASTTk[node]);
        end
        else
          while PendOAWBCount > pendBase do
          begin
            Dec(PendOAWBCount);
            IRAppend(IR_COPY_REC,
              IRLowerAddress(PendOAWBDest[PendOAWBCount]),
              IRAppend(IR_BINOP,
                IRAppend(IR_SLOTADDR, PendOAWBTemp[PendOAWBCount], -1, -1, 0, Ord(tyPointer)),
                IRAppend(IR_CONST_INT, -1, -1, -1, 8, Ord(tyInteger)),
                Ord(tkPlus), 0, Ord(tyPointer)),
              -1, PendOAWBSize[PendOAWBCount], Ord(tyRecord));
          end;
      end;
    end;

    AN_CALL_IND:
    begin
      { Indirect call through a proc-typed value. Marshal args by the signature
        (ASTIVal = signature Procs[] index) and emit IR_CALL_IND (IRA = callee
        code address, IRB = args, IRIVal = sig, IRC = extra leading Self args:
        0 for a plain proc pointer, 1 for a method pointer). A method pointer is
        a 16-byte {Code@0, Data@8} record: load Self (Data) as arg0, call Code. }
      cpi := ASTIVal[node];
      first := -1; last := -1;
      if ASTSLen[node] = 1 then
      begin
        { Method pointer: prepend Self loaded from the record's Data field. }
        leftAddr := IRLowerAddress(ASTRight[node]);          { addr of {Code,Data} }
        right := IRAppend(IR_CONST_INT, -1, -1, -1, TARGET_PTR_SIZE, Ord(tyInteger));
        outNode := IRAppend(IR_BINOP, leftAddr, right, Ord(tkPlus), 0, Ord(tyPointer));
        value := IRAppend(IR_LOAD_MEM, outNode, -1, -1, 0, Ord(tyPointer)); { Self = [addr+ptrsize] }
        first := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyPointer));
        last := first;
      end;
      item := ASTLeft[node];
      pathIdx := 0;
      while item <> -1 do
      begin
        isRefArg := (pathIdx < Procs[cpi].ParamCount) and Procs[cpi].Params[pathIdx].IsRef;
        value := IRLowerCallArg(cpi, pathIdx, ASTLeft[item], isRefArg);
        argNode := IRAppend(IR_ARG, value, -1, -1, 0, ASTTk[ASTLeft[item]]);
        if first < 0 then first := argNode
        else IRB[last] := argNode;
        last := argNode;
        item := ASTRight[item];
        Inc(pathIdx);
      end;
      if ASTSLen[node] = 1 then
        { callee = Code field (record base address, offset 0). }
        callVal := IRAppend(IR_LOAD_MEM, IRLowerAddress(ASTRight[node]), -1, -1, 0, Ord(tyPointer))
      else
        callVal := IRLowerAST(ASTRight[node]);   { plain: load the code-address value }
      Result := IRAppend(IR_CALL_IND, callVal, first, ASTSLen[node], cpi, ASTTk[node]);
    end;

    AN_INTF_CALL:
    begin
      { CORBA interface call. The interface value is a fat pointer {IMT@0,
        instance@8}. Self = [iface+8] (prepended like a method-pointer call);
        code = [[iface+0] + slot*8]. Marshal explicit args by the signature. }
      cpi := ASTIVal[node];
      { self = [iface+8] }
      leftAddr := IRLowerAddress(ASTRight[node]);
      right := IRAppend(IR_CONST_INT, -1, -1, -1, TARGET_PTR_SIZE, Ord(tyInteger));
      outNode := IRAppend(IR_BINOP, leftAddr, right, Ord(tkPlus), 0, Ord(tyPointer));
      value := IRAppend(IR_LOAD_MEM, outNode, -1, -1, 0, Ord(tyPointer));
      first := IRAppend(IR_ARG, value, -1, -1, 0, Ord(tyPointer));
      last := first;
      { explicit args: signature params 1.. (param 0 is Self) }
      item := ASTLeft[node];
      pathIdx := 1;
      while item <> -1 do
      begin
        isRefArg := (pathIdx < Procs[cpi].ParamCount) and Procs[cpi].Params[pathIdx].IsRef;
        value := IRLowerCallArg(cpi, pathIdx, ASTLeft[item], isRefArg);
        argNode := IRAppend(IR_ARG, value, -1, -1, 0, ASTTk[ASTLeft[item]]);
        IRB[last] := argNode; last := argNode;
        item := ASTRight[item];
        Inc(pathIdx);
      end;
      { code = [[iface+0] + slot*8] }
      value := IRAppend(IR_LOAD_MEM, IRLowerAddress(ASTRight[node]), -1, -1, 0, Ord(tyPointer)); { IMT ptr }
      right := IRAppend(IR_CONST_INT, -1, -1, -1, ASTSOffset[node] * 8, Ord(tyInteger));
      outNode := IRAppend(IR_BINOP, value, right, Ord(tkPlus), 0, Ord(tyPointer));
      callVal := IRAppend(IR_LOAD_MEM, outNode, -1, -1, 0, Ord(tyPointer));
      { IRC=0: the interface signature's ParamCount already counts Self (param 0),
        and Self is the first node in the arg chain, so no extra injected-Self. }
      Result := IRAppend(IR_CALL_IND, callVal, first, 0, cpi, ASTTk[node]);
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

    AN_INCDEC:
    begin
      { Pre/post ++/--. Evaluate the lvalue ADDRESS exactly once into a hidden
        pointer temp (so `a[i++]++` bumps i once), load the current value, stash
        the OLD value, store old±delta, and yield old (postfix) or the new stored
        value (prefix). Pointer operands step by element size. }
      left := ASTLeft[node];
      if not IsASTLValue(left) then Error('++/-- operand is not an lvalue');
      argTk := IntToTypeKind(ASTTk[left]);
      if argTk = tyUnknown then argTk := tyInteger;
      if argTk = tyPointer then foldK := ASTIVal[node] * IRPointerStride(left)
      else foldK := ASTIVal[node];
      varIdx := AllocVar('', tyPointer);                 { paddr = &lvalue, once }
      IRAppend(IR_STORE_SYM, varIdx, IRLowerAddress(left), -1, 0, Ord(tyPointer));
      slot := AllocVar('', argTk);                       { old value }
      IRAppend(IR_STORE_SYM, slot,
        IRAppend(IR_LOAD_MEM, IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, Ord(tyPointer)),
                 -1, -1, 0, Ord(argTk)), -1, 0, Ord(argTk));
      IRAppend(IR_STORE_MEM, IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, Ord(tyPointer)),
        IRAppend(IR_BINOP, IRAppend(IR_LOAD_SYM, slot, -1, -1, 0, Ord(argTk)),
                 IRAppend(IR_CONST_INT, -1, -1, -1, foldK, Ord(argTk)),
                 Ord(tkPlus), 0, Ord(argTk)), -1, 0, Ord(argTk));
      if ASTSOffset[node] = 1 then
        Result := IRAppend(IR_LOAD_SYM, slot, -1, -1, 0, Ord(argTk))   { postfix: old }
      else
        Result := IRAppend(IR_LOAD_MEM, IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, Ord(tyPointer)),
                           -1, -1, 0, Ord(argTk));                     { prefix: new }
    end;

    AN_COMPOUND_ASSIGN:
    begin
      { Value-bearing assignment `lv = rhs` and compound `lv OP= rhs`. Lvalue
        address computed ONCE; for compound, current = *paddr, new = current OP
        rhs; store and yield the stored value (so `a = b = c` chains via the
        Right being another AN_COMPOUND_ASSIGN). }
      left := ASTLeft[node];
      if not IsASTLValue(left) then Error('assignment target is not an lvalue');
      argTk := IntToTypeKind(ASTTk[left]);
      if argTk = tyUnknown then argTk := tyInteger;
      varIdx := AllocVar('', tyPointer);
      IRAppend(IR_STORE_SYM, varIdx, IRLowerAddress(left), -1, 0, Ord(tyPointer));
      right := IRLowerAST(ASTRight[node]);
      if ASTIVal[node] = Ord(tkAssign) then
        value := right
      else
        value := IRAppend(IR_BINOP,
          IRAppend(IR_LOAD_MEM, IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, Ord(tyPointer)),
                   -1, -1, 0, Ord(argTk)),
          right, ASTIVal[node], 0, Ord(argTk));
      slot := AllocVar('', argTk);                       { stored value, yielded }
      IRAppend(IR_STORE_SYM, slot, value, -1, 0, Ord(argTk));
      IRAppend(IR_STORE_MEM, IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, Ord(tyPointer)),
               IRAppend(IR_LOAD_SYM, slot, -1, -1, 0, Ord(argTk)), -1, 0, Ord(argTk));
      Result := IRAppend(IR_LOAD_SYM, slot, -1, -1, 0, Ord(argTk));
    end;

    AN_COMMA:
    begin
      { C comma operator: evaluate Left for its side effects (discard the value),
        yield Right. Right-nested, so each Left peels one operand off the front. }
      IRMarkStatementNode(IRLowerAST(ASTLeft[node]));
      Result := IRLowerAST(ASTRight[node]);
    end;

    AN_TERNARY:
    begin
      { Value-bearing conditional `c ? a : b` / `if c then a else b`. Mirror the
        AN_IF control flow but store each arm into one hidden temp and yield a
        load of it — so the selected arm's side effects run (short-circuit) and
        the expression has a value. Scalar/ordinal/pointer/float result types
        (what C ternary and the if-expression yield); a managed-arm form would
        need the retain/release assign path and is deferred (slice 2). }
      pairNode := ASTRight[node];
      argTk := IntToTypeKind(ASTTk[node]);
      if argTk = tyUnknown then argTk := tyInteger;
      { A string-literal arm types as frozen tyString, which has inline [N]
        storage and no usable handle slot for a temp. In Pascal (managed-default)
        carry the result as a managed AnsiString — the per-arm assignment coerces
        the frozen literal into the managed temp and the load yields a real
        handle. In C a string literal is a frozen `char*` address, NOT a managed
        AnsiString; routing it through the ARC assign path builds a garbage
        handle the consumer derefs -> crash (the printf `(k=='X')?"0X":"0x"`
        segfault). So in C mode carry the arm as a plain pointer: the per-arm
        assignment stores the literal's address and the load yields the char*. }
      if argTk = tyString then
      begin
        if CProgramMode then argTk := tyPointer
        else argTk := tyAnsiString;
      end;
      if argTk = tyRecord then LastTypeRecId := ResolveNodeRec(ASTLeft[pairNode]);
      varIdx := AllocVar('', argTk);
      if argTk = tyRecord then Syms[varIdx].RecName := LastTypeRecId;
      { Managed/aggregate result temp: the per-arm AN_ASSIGN delegation below
        releases the dest's old managed fields before copy, so the temp must be
        nil-inited (allocated post-prologue) — same rule as other hidden temps. }
      if (argTk = tyAnsiString) or (argTk = tyString) or TypeIsAggregate(argTk) then
        SymIsHiddenArgTemp[varIdx] := True;
      elseLabel := IRNewLabel;
      endLabel := IRNewLabel;
      condNode := IRLowerAST(ASTLeft[node]);
      first := IRAppend(IR_JUMP_IF_FALSE, elseLabel, condNode, -1, 0, 0);
      { Each arm: lower `temp := arm` through the ordinary assignment path so
        scalar, string (ARC), and record (managed copy) results all work and the
        selected arm's side effects run (short-circuit). }
      lhsNode := AllocNode(AN_IDENT); ASTIVal[lhsNode] := varIdx; ASTTk[lhsNode] := Ord(argTk);
      argNode := AllocNode(AN_ASSIGN); ASTLeft[argNode] := lhsNode; ASTRight[argNode] := ASTLeft[pairNode];
      IRMarkStatementNode(IRLowerAST(argNode));
      IRAppend(IR_JUMP, endLabel, -1, -1, 0, 0);
      IRAppend(IR_LABEL, -1, -1, -1, elseLabel, 0);
      lhsNode := AllocNode(AN_IDENT); ASTIVal[lhsNode] := varIdx; ASTTk[lhsNode] := Ord(argTk);
      argNode := AllocNode(AN_ASSIGN); ASTLeft[argNode] := lhsNode; ASTRight[argNode] := ASTRight[pairNode];
      IRMarkStatementNode(IRLowerAST(argNode));
      IRAppend(IR_LABEL, -1, -1, -1, endLabel, 0);
      Result := IRAppend(IR_LOAD_SYM, varIdx, -1, -1, 0, Ord(argTk));
    end;

    AN_SWITCH:
    begin
      endLabel := IRNewLabel;
      { selector evaluated once into a temp }
      value := IRLowerAST(ASTLeft[node]);
      first := value;
      if ASTTk[ASTLeft[node]] = 0 then swSelTk := Ord(tyInteger)
      else swSelTk := ASTTk[ASTLeft[node]];
      swSelTmp := AllocVar('', IntToTypeKind(swSelTk));
      IRAppend(IR_STORE_SYM, swSelTmp, value, -1, 0, swSelTk);
      { pass 1 — dispatch: give each case/default marker a label and, for a case,
        emit `if (sel == caseval) goto label` (via JUMP_IF_FALSE of `sel != val`). }
      swDefault := -1;
      IRLowerCSwitchDispatchSeq(ASTLeft[ASTRight[node]], swSelTmp, swSelTk, swDefault);
      if swDefault >= 0 then IRAppend(IR_JUMP, swDefault, -1, -1, 0, 0)
      else IRAppend(IR_JUMP, endLabel, -1, -1, 0, 0);
      { pass 2 — bodies in source order (fallthrough). break -> end; continue is
        inherited so it targets the enclosing loop, giving a break-only scope. }
      if IRLoopStackDepth >= 64 then Error('IR loop stack overflow');
      IRLoopStackBreak[IRLoopStackDepth] := endLabel;
      if IRLoopStackDepth > 0 then
        IRLoopStackContinue[IRLoopStackDepth] := IRLoopStackContinue[IRLoopStackDepth - 1]
      else
        IRLoopStackContinue[IRLoopStackDepth] := endLabel;
      IRLoopStackExceptionDepth[IRLoopStackDepth] := ExceptionCodegenDepth;
      Inc(IRLoopStackDepth);
      IRLowerCSwitchBodySeq(ASTLeft[ASTRight[node]]);
      Dec(IRLoopStackDepth);
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
            if ASTRight[ASTLeft[labelNode]] <> -1 then
            begin
              { Range label lo..hi: enter the body when lo <= selector <= hi.
                Skip to elseLabel (this label-test's exit) when either bound
                fails; reaching the unconditional jump means in-range. }
              hi := ASTIVal[ASTRight[ASTLeft[labelNode]]];
              elseLabel := IRNewLabel;
              constValNode := IRAppend(IR_CONST_INT, -1, -1, -1, cv, Ord(tyInteger));
              cmpNode := IRAppend(IR_BINOP, selectorValNode, constValNode, Ord(tkGe), 0, Ord(tyBoolean));
              condJmpNode := IRAppend(IR_JUMP_IF_FALSE, elseLabel, cmpNode, -1, 0, 0);
              if first < 0 then first := condJmpNode;
              constValNode := IRAppend(IR_CONST_INT, -1, -1, -1, hi, Ord(tyInteger));
              cmpNode := IRAppend(IR_BINOP, selectorValNode, constValNode, Ord(tkLe), 0, Ord(tyBoolean));
              IRAppend(IR_JUMP_IF_FALSE, elseLabel, cmpNode, -1, 0, 0);
              IRAppend(IR_JUMP, clauseBodyLabel, -1, -1, 0, 0);
              last := IRAppend(IR_LABEL, -1, -1, -1, elseLabel, 0);
            end
            else
            begin
              constValNode := IRAppend(IR_CONST_INT, -1, -1, -1, cv, Ord(tyInteger));
              cmpNode := IRAppend(IR_BINOP, selectorValNode, constValNode, Ord(tkNeq), 0, Ord(tyBoolean));
              condJmpNode := IRAppend(IR_JUMP_IF_FALSE, clauseBodyLabel, cmpNode, -1, 0, 0);
              if first < 0 then first := condJmpNode;
              last := condJmpNode;
            end;

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
      { Target fd, threaded into each IR_WRITE/IR_WRITELN's ival slot so codegen
        emits the write syscalls against it. ASTIVal[node] = 0 means the default
        (stdout); writeln(StdErr,..) set it to 2 in the parser. }
      writeFd := ASTIVal[node];
      if writeFd = 0 then writeFd := STDOUT;
      item := ASTLeft[node];
      while item <> -1 do
      begin
        { IR_WRITE: IRB = field width (0 = none), IRC = decimals (-1 = none),
          IRIVal = target fd, IRTk = the source expression type (write dispatch). }
        bLastNode := -1;
        if (ASTKind[item] = AN_ARG) and (IntToTypeKind(ASTTk[ASTLeft[item]]) = tyBoolean) then
        begin
          { write(Boolean[:w]) -> FPC-style TRUE/FALSE text, branched at runtime. }
          value := IRLowerAST(ASTLeft[item]);
          outNode := IRLowerBoolWrite(value, ASTIVal[item], bLastNode, writeFd);
        end
        else if (ASTKind[item] = AN_PAIR) and (IntToTypeKind(ASTTk[ASTLeft[item]]) = tyBoolean) then
        begin
          value := IRLowerAST(ASTLeft[item]);
          outNode := IRLowerBoolWrite(value, -1, bLastNode, writeFd);
        end
        else if (ASTKind[item] <> AN_ARG) and (ASTKind[item] <> AN_PAIR) and
                (IntToTypeKind(ASTTk[item]) = tyBoolean) then
        begin
          value := IRLowerAST(item);
          outNode := IRLowerBoolWrite(value, -1, bLastNode, writeFd);
        end
        else if ASTKind[item] = AN_ARG then
        begin
          { A Variant arg writes its slot address; codegen reads tag+payload and
            dispatches at runtime (IRTk stays tyVariant). }
          if IntToTypeKind(ASTTk[ASTLeft[item]]) = tyVariant then
            value := IRLowerAddress(ASTLeft[item])
          else
            value := IRLowerAST(ASTLeft[item]);
          if IsNodePChar(ASTLeft[item]) then
            { write(PChar): tag the IR_WRITE with the -3 decimals sentinel so
              codegen emits a runtime C-string (strlen + write) instead of
              printing the pointer value. }
            outNode := IRAppend(IR_WRITE, value, ASTIVal[item], -3, writeFd, Ord(tyPointer))
          else
            outNode := IRAppend(IR_WRITE, value, ASTIVal[item], ASTSOffset[item], writeFd, Ord(IntToTypeKind(ASTTk[ASTLeft[item]])));
        end
        else if ASTKind[item] = AN_PAIR then
        begin
          value := IRLowerAST(ASTLeft[item]);
          outNode := IRAppend(IR_WRITE, value, -1, -1, writeFd, IRTk[value]);
        end
        else if IntToTypeKind(ASTTk[item]) = tyVariant then
        begin
          value := IRLowerAddress(item);
          outNode := IRAppend(IR_WRITE, value, -1, -1, writeFd, Ord(tyVariant));
        end
        else
        begin
          value := IRLowerAST(item);
          outNode := IRAppend(IR_WRITE, value, -1, -1, writeFd, IRTk[value]);
        end;
        if first < 0 then first := outNode;
        if bLastNode >= 0 then last := bLastNode else last := outNode;
        item := ASTRight[item];
      end;
      if ASTKind[node] = AN_WRITELN then
        Result := IRAppend(IR_WRITELN, first, last, -1, writeFd, 0)
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
      if ASTKind[node] = AN_READLN then
      begin
        outNode := IRAppend(IR_READ_DISCARD, -1, -1, -1, 0, 0);
        last := outNode;
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
        { Self (pathIdx=0) is always passed by value (pointer). Real args go
          through the same IRLowerCallArg as a direct call so by-ref literals,
          static->open-array, class->interface coercion, and frozen-string concat
          marshal identically — a raw IRLowerAddress(literal) here produced a bad
          pointer (corrupt string length). See bug-mixed-signature-vmt-misdispatch. }
        if pathIdx = 0 then
          value := IRLowerAST(ASTLeft[item])
        else
          value := IRLowerCallArg(cpi, pathIdx, ASTLeft[item], isRefArg);
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

    AN_METACLASS_NEW:
    begin
      { Metaclass-dispatched construction `classRefVar.Create(args)`.
          ASTRight   = classref value node (yields the dynamic class's RTTI blob)
          ASTIVal    = ctor proc idx (param signature)
          ASTSOffset = ctor VMT slot (-1 if the ctor is not virtual)
          ASTLeft    = AN_ARG chain of explicit ctor args (Self excluded)
        Allocate the DYNAMIC class read from the RTTI blob (size@16, vmt@24),
        stamp its VMT, then run the constructor through the stamped VMT — an
        ordinary virtual call once [inst+0] holds the right VMT. Built as
        target-independent IR (same idiom as is/as), so all backends share it. }
      cpi := ASTIVal[node];
      slot := ASTSOffset[node];

      { cref := <classref value> (the RTTI blob pointer). }
      mcCrefSym := AllocVar('', tyPointer);
      IRAppend(IR_STORE_SYM, mcCrefSym, IRLowerAST(ASTRight[node]), -1, 0, Ord(tyPointer));

      { size := [cref+16] (RTTI instance size). }
      mcAddr := IRAppend(IR_BINOP,
                  IRAppend(IR_LOAD_SYM, mcCrefSym, -1, -1, 0, Ord(tyPointer)),
                  IRAppend(IR_CONST_INT, -1, -1, -1, 16, Ord(tyInteger)),
                  Ord(tkPlus), 0, Ord(tyPointer));
      mcSize := IRAppend(IR_LOAD_MEM, mcAddr, -1, -1, 0, Ord(tyInt64));

      { inst := GetMem(size) — plain alloc (classIdx = -1: no VMT stamp here). }
      mcInstSym := AllocVar('', tyPointer);
      IRAppend(IR_STORE_SYM, mcInstSym,
               IRAppend(IR_CALL, -Ord(tkGetMem),
                        IRAppend(IR_ARG, mcSize, -1, -1, 0, Ord(tyInteger)),
                        -1, 0, Ord(tyPointer)),
               -1, 0, Ord(tyPointer));

      { [inst+0] := [cref+24] (stamp the dynamic class's VMT). }
      mcAddr := IRAppend(IR_BINOP,
                  IRAppend(IR_LOAD_SYM, mcCrefSym, -1, -1, 0, Ord(tyPointer)),
                  IRAppend(IR_CONST_INT, -1, -1, -1, 24, Ord(tyInteger)),
                  Ord(tkPlus), 0, Ord(tyPointer));
      mcVmt := IRAppend(IR_LOAD_MEM, mcAddr, -1, -1, 0, Ord(tyInt64));
      IRAppend(IR_STORE_MEM,
               IRAppend(IR_LOAD_SYM, mcInstSym, -1, -1, 0, Ord(tyPointer)),
               mcVmt, -1, 0, Ord(tyPointer));

      { Constructor call: Self (param 0) = inst, then the explicit args. }
      mcSelfArg := IRAppend(IR_ARG,
                     IRAppend(IR_LOAD_SYM, mcInstSym, -1, -1, 0, Ord(tyPointer)),
                     -1, -1, 0, Ord(tyClass));
      first := mcSelfArg; last := mcSelfArg;
      item := ASTLeft[node];
      pathIdx := 1;
      while item <> -1 do
      begin
        isRefArg := (pathIdx < Procs[cpi].ParamCount) and Procs[cpi].Params[pathIdx].IsRef;
        if isRefArg then
          value := IRLowerAddress(ASTLeft[item])
        else
          value := IRLowerAST(ASTLeft[item]);
        argNode := IRAppend(IR_ARG, value, -1, -1, 0, ASTTk[ASTLeft[item]]);
        IRB[last] := argNode;
        last := argNode;
        item := ASTRight[item];
        Inc(pathIdx);
      end;

      if slot >= 0 then
        { The call runs for its side effect (it fills the instance); its result
          is discarded, so flag it a statement root or it would be pruned. }
        IRMarkStatementNode(IRAppend(IR_VIRTUAL_CALL, first, last, cpi, slot, Ord(tyClass)))
      else
        IRMarkStatementNode(IRAppendCall(cpi, first, -1, Ord(tyClass)));

      { The construction value is the instance, not the ctor body's return. }
      Result := IRAppend(IR_LOAD_SYM, mcInstSym, -1, -1, 0, ASTTk[node]);
    end;

    AN_LABEL:
    begin
      { Synthetic label (stackless generator transform): ASTSOffset = -1 sentinel,
        ASTIVal carries the GotoLabel slot index directly (no name match). }
      if ASTSOffset[node] = -1 then
      begin
        i := ASTIVal[node];
        if GotoLabelIRId[i] = -1 then GotoLabelIRId[i] := IRNewLabel;
        Result := IRAppend(IR_LABEL, -1, -1, -1, GotoLabelIRId[i], 0);
      end
      else
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
    end;
    AN_GOTO:
    begin
      if ASTSOffset[node] = -1 then
      begin
        i := ASTIVal[node];
        if GotoLabelIRId[i] = -1 then GotoLabelIRId[i] := IRNewLabel;
        Result := IRAppend(IR_JUMP, GotoLabelIRId[i], -1, -1, 0, 0);
      end
      else
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

{ DWARF -g: record a line-table row at the start address of IR instruction i when
  its source line changes. Called at the top of every backend's statement emit
  loop (defined here, before the per-arch ir_codegen_* files), so CodeLen is the
  address where this instruction's machine code begins. The first row of a proc
  body also drops an entry row at the proc's low_pc and marks the body row
  prologue_end, so `break <func>` skips the prologue cleanly. }
procedure DbgRecordRow(i: Integer);
begin
  if not DebugInfo then Exit;
  if (IRLine[i] = 0) or (IRLine[i] = DwarfLastLine) then Exit;
  if DwarfProcFirstRow and (CurProc >= 0) and (DwarfRowCount < MAX_DWARF_ROWS) then
  begin
    DwarfRowAddr[DwarfRowCount] := Procs[CurProc].BodyAddr;
    DwarfRowLine[DwarfRowCount] := IRLine[i];
    DwarfRowPrologueEnd[DwarfRowCount] := False;
    Inc(DwarfRowCount);
  end;
  if DwarfRowCount < MAX_DWARF_ROWS then
  begin
    DwarfRowAddr[DwarfRowCount] := CodeLen;
    DwarfRowLine[DwarfRowCount] := IRLine[i];
    DwarfRowPrologueEnd[DwarfRowCount] := DwarfProcFirstRow;
    Inc(DwarfRowCount);
    DwarfProcFirstRow := False;
  end;
  DwarfLastLine := IRLine[i];
end;
