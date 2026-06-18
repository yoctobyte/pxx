{ ===== IR -> Xtensa LX6/LX7 (Call0 ABI) machine code (cross target) ===== }
{ Register use: a2 = primary value, a3 = secondary, a4 = branch helper,
  a8/a9 = address/scratch temps, a15 = frame pointer, a1 = sp, a0 = ra. }

procedure XtensaAlignCode4;
{ Pad with 3-byte NOPs until CodeLen is 4-aligned (terminates in <= 3 steps). }
begin
  while (CodeLen mod 4) <> 0 do
    xtensa_nop;
end;

procedure XtensaEmitLitHeader;
{ Emit a jump over a 4-aligned 32-bit literal slot. The caller must emit
  exactly 4 literal bytes next, then `xtensa_l32r(rd, $FFFF)`: L32R offsets
  are one-extended (always negative), so the literal sits right before the
  4-aligned L32R and imm16 = -1 word. }
var jPos, litPos: Integer;
begin
  jPos := CodeLen;
  litPos := ((jPos + 3 + 3) div 4) * 4;
  xtensa_j((litPos + 4) - jPos);
  while CodeLen < litPos do
    EmitB(0);
end;

procedure EmitLoadConstXtensa(rd: Integer; v: Int32);
begin
  if (v >= -2048) and (v <= 2047) then
    xtensa_movi(rd, v)
  else
  begin
    XtensaEmitLitHeader;
    EmitI32(v);
    xtensa_l32r(rd, $FFFF);
  end;
end;

procedure EmitLoadDataRefXtensa(rd: Integer; dataOff: Integer);
begin
  XtensaEmitLitHeader;
  EmitDataRef(dataOff);
  xtensa_l32r(rd, $FFFF);
end;

procedure EmitLoadGlobAddrXtensa(rd: Integer; bssOff: Integer);
begin
  XtensaEmitLitHeader;
  EmitGlobRef(bssOff);
  xtensa_l32r(rd, $FFFF);
end;

procedure EmitFrameAddrXtensa(rd: Integer; off: Integer);
var fp: Integer;
begin
  if XtensaABI = XTENSA_ABI_WINDOWED then
    fp := reg_xtensa_a7
  else
    fp := reg_xtensa_a15;
  if (off >= -128) and (off <= 127) then
    xtensa_addi(rd, fp, off)
  else
  begin
    EmitLoadConstXtensa(rd, off);
    xtensa_add(rd, fp, rd);
  end;
end;

procedure EmitSizedLoadXtensa(rd, rs: Integer; sz: Integer; sgn: Boolean);
{ rd must not be a9 (used as sign-extension scratch). }
begin
  if sz = 1 then
  begin
    xtensa_l8ui(rd, rs, 0);
    if sgn then
    begin
      { No signed 8-bit load: rd := (rd xor 128) - 128. }
      xtensa_movi(reg_xtensa_a9, 128);
      xtensa_xor(rd, rd, reg_xtensa_a9);
      xtensa_sub(rd, rd, reg_xtensa_a9);
    end;
  end
  else if sz = 2 then
  begin
    if sgn then xtensa_l16si(rd, rs, 0) else xtensa_l16ui(rd, rs, 0);
  end
  else
    xtensa_l32i(rd, rs, 0);
end;

procedure EmitSizedStoreXtensa(rt, rs: Integer; sz: Integer);
begin
  if sz = 1 then
    xtensa_s8i(rt, rs, 0)
  else if sz = 2 then
    xtensa_s16i(rt, rs, 0)
  else
    xtensa_s32i(rt, rs, 0);
end;

procedure EmitLoadVarXtensa(idx: Integer);
var tk: TTypeKind; sz: Integer; sgn: Boolean;
begin
  tk := Syms[idx].TypeKind;
  sz := TypeSize(tk);
  sgn := TypeSigned(tk);

  if Syms[idx].Kind = skGlobal then
  begin
    EmitLoadGlobAddrXtensa(reg_xtensa_a8, Syms[idx].Offset);
    EmitSizedLoadXtensa(reg_xtensa_a2, reg_xtensa_a8, sz, sgn);
  end
  else
  begin
    EmitFrameAddrXtensa(reg_xtensa_a8, Syms[idx].Offset);
    if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then
      xtensa_l32i(reg_xtensa_a8, reg_xtensa_a8, 0);
    EmitSizedLoadXtensa(reg_xtensa_a2, reg_xtensa_a8, sz, sgn);
  end;
end;

procedure EmitStoreVarXtensa(idx: Integer);
var tk: TTypeKind; sz: Integer;
begin
  tk := Syms[idx].TypeKind;
  sz := TypeSize(tk);

  if Syms[idx].Kind = skGlobal then
  begin
    EmitLoadGlobAddrXtensa(reg_xtensa_a8, Syms[idx].Offset);
    EmitSizedStoreXtensa(reg_xtensa_a2, reg_xtensa_a8, sz);
  end
  else
  begin
    EmitFrameAddrXtensa(reg_xtensa_a8, Syms[idx].Offset);
    if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then
      xtensa_l32i(reg_xtensa_a8, reg_xtensa_a8, 0);
    EmitSizedStoreXtensa(reg_xtensa_a2, reg_xtensa_a8, sz);
  end;
end;

procedure XtensaPushA2;
{ Spill a2 to the next expression-stack slot. Windowed: sp is constant, so the
  slot is sp-relative at the running XtSpillDepth offset (never move sp, or the
  window spill area at [sp-16] desyncs). Call0: classic moving-sp push. }
begin
  if XtensaABI = XTENSA_ABI_WINDOWED then
  begin
    if XtSpillDepth + 4 > XT_EXPR_REGION then
      Error('target xtensa: expression/argument stack exceeds reserved frame');
    xtensa_s32i(reg_xtensa_a2, reg_xtensa_sp, XtSpillDepth);
    Inc(XtSpillDepth, 4);
  end
  else
  begin
    xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, -4);
    xtensa_s32i(reg_xtensa_a2, reg_xtensa_sp, 0);
  end;
end;

procedure XtensaPopA3;
{ Pop the top expression-stack slot into a3 (windowed: sp constant). }
begin
  if XtensaABI = XTENSA_ABI_WINDOWED then
  begin
    Dec(XtSpillDepth, 4);
    xtensa_l32i(reg_xtensa_a3, reg_xtensa_sp, XtSpillDepth);
  end
  else
  begin
    xtensa_l32i(reg_xtensa_a3, reg_xtensa_sp, 0);
    xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, 4);
  end;
end;

procedure XtensaPopA2;
{ Pop the top expression-stack slot into a2 (windowed: sp constant). }
begin
  if XtensaABI = XTENSA_ABI_WINDOWED then
  begin
    Dec(XtSpillDepth, 4);
    xtensa_l32i(reg_xtensa_a2, reg_xtensa_sp, XtSpillDepth);
  end
  else
  begin
    xtensa_l32i(reg_xtensa_a2, reg_xtensa_sp, 0);
    xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, 4);
  end;
end;

procedure EmitSlotAddrXtensa(rd, si: Integer);
{ rd = address of the variable's storage slot (global abs / frame-relative). }
begin
  if Syms[si].Kind = skGlobal then
    EmitLoadGlobAddrXtensa(rd, Syms[si].Offset)
  else
    EmitFrameAddrXtensa(rd, Syms[si].Offset);
end;

procedure EmitHeapAllocLockedXtensa;
{ a2 = requested payload bytes -> a2 = payload pointer. Delegates to the Pascal
  PXXAlloc(size, align=8). No threadsafe lock (x86-64-only). }
var pi: Integer;
begin
  pi := FindProc('PXXAlloc');
  if pi < 0 then Error('compiler error: Alloc helper not found in builtin unit');
  if XtensaABI = XTENSA_ABI_WINDOWED then
  begin
    xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);   { arg0 = size }
    xtensa_movi(reg_xtensa_a11, 8);              { arg1 = align }
    EmitCallProc(pi);
    xtensa_mov(reg_xtensa_a2, reg_xtensa_a10);   { result }
  end
  else
  begin
    xtensa_movi(reg_xtensa_a3, 8);               { a2 = size already; arg1 = align }
    EmitCallProc(pi);                            { result in a2 }
  end;
end;

procedure EmitHeapFreeLockedXtensa;
{ a2 = payload pointer -> PXXFree(p). nil ignored inside. }
var pi: Integer;
begin
  pi := FindProc('PXXFree');
  if pi < 0 then Error('compiler error: Free helper not found in builtin unit');
  if XtensaABI = XTENSA_ABI_WINDOWED then
    xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);
  EmitCallProc(pi);
end;

procedure EmitStrFromLitXtensa;
{ a2 = len, a3 = src -> a2 = new managed-string handle (PXXStrFromLit). }
var pi: Integer;
begin
  pi := FindProc('PXXStrFromLit');
  if pi < 0 then Error('compiler error: PXXStrFromLit not found');
  if XtensaABI = XTENSA_ABI_WINDOWED then
  begin
    xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);   { arg0 = len }
    xtensa_mov(reg_xtensa_a11, reg_xtensa_a3);   { arg1 = src }
    EmitCallProc(pi);
    xtensa_mov(reg_xtensa_a2, reg_xtensa_a10);   { handle }
  end
  else
    EmitCallProc(pi);                            { a2=len, a3=src; result a2 }
end;

procedure EmitStrRefCallXtensa(const name: AnsiString);
{ a2 = handle -> call proc(handle). a2 is NOT preserved (DecRef path). }
var pi: Integer;
begin
  pi := FindProc(name);
  if pi < 0 then Error('compiler error: string refcount helper not found');
  if XtensaABI = XTENSA_ABI_WINDOWED then
    xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);
  EmitCallProc(pi);
end;

procedure EmitXtensaSoftDivCall(const name: AnsiString);
{ a2 = dividend (arg0), a3 = divisor (arg1) -> call helper -> result in a2.
  LX6 software div/mod path (--xtensa-cpu=lx6). }
var pi: Integer;
begin
  pi := FindProc(name);
  if pi < 0 then Error('compiler error: xtensa soft-divide helper not found');
  if XtensaABI = XTENSA_ABI_WINDOWED then
  begin
    xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);
    xtensa_mov(reg_xtensa_a11, reg_xtensa_a3);
    EmitCallProc(pi);
    xtensa_mov(reg_xtensa_a2, reg_xtensa_a10);
  end
  else
    EmitCallProc(pi);   { a2, a3 already hold arg0, arg1; result in a2 }
end;

procedure IREmitNodeXtensa(node: Integer);
var
  left, right, op, si, pi, nArgs, i, lo, elemSize, sz, argNode, argBase, valNode, j: Integer;
  tk: TTypeKind;
  sgn, savedLVW: Boolean;
  sVal: AnsiString;
begin
  case IRKind[node] of
    IR_CONST_INT:
      EmitLoadConstXtensa(reg_xtensa_a2, IRIVal[node]);

    IR_CONST_STR:
      begin
        sVal := GetTokenStrFromRaw(IRA[node], IRB[node]);
        si := InternStr(sVal);
        EmitLoadDataRefXtensa(reg_xtensa_a2, Strs[si].Offset);
      end;

    IR_LOAD_SYM:
      EmitLoadVarXtensa(IRA[node]);

    IR_STORE_SYM:
      begin
        si := IRA[node];
        if Syms[si].TypeKind = tyAnsiString then
        begin
          { Managed-string assignment: build the new handle in a2, then publish
            into the slot (DecRef old). Mirrors i386/riscv32. }
          valNode := IRB[node];
          if IRKind[valNode] = IR_CONST_STR then
          begin
            sVal := GetTokenStrFromRaw(IRA[valNode], IRB[valNode]);
            j := InternStr(sVal);
            EmitLoadConstXtensa(reg_xtensa_a2, Strs[j].Len);          { len }
            EmitLoadDataRefXtensa(reg_xtensa_a3, Strs[j].Offset + 8); { src }
            EmitStrFromLitXtensa;                                     { a2 = handle }
          end
          else if IntToTypeKind(IRTk[valNode]) = tyChar then
          begin
            IREmitNodeXtensa(valNode);                  { a2 = char code }
            XtensaPushA2;                               { spill char to the frame }
            { a3 = address of the spilled char slot. }
            if XtensaABI = XTENSA_ABI_WINDOWED then
              xtensa_addi(reg_xtensa_a3, reg_xtensa_sp, XtSpillDepth - 4)
            else
              xtensa_addi(reg_xtensa_a3, reg_xtensa_sp, 0);
            EmitLoadConstXtensa(reg_xtensa_a2, 1);      { len 1 }
            EmitStrFromLitXtensa;                       { a2 = handle }
            { drop the char slot }
            if XtensaABI = XTENSA_ABI_WINDOWED then Dec(XtSpillDepth, 4)
            else xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, 4);
          end
          else if IntToTypeKind(IRTk[valNode]) = tyString then
          begin
            IREmitNodeXtensa(valNode);                  { a2 = inline buffer addr }
            xtensa_l32i(reg_xtensa_a4, reg_xtensa_a2, 0); { len = [buf] }
            xtensa_addi(reg_xtensa_a3, reg_xtensa_a2, 8); { src = buf+8 }
            xtensa_mov(reg_xtensa_a2, reg_xtensa_a4);     { len }
            EmitStrFromLitXtensa;
          end
          else
          begin
            IREmitNodeXtensa(valNode);                  { a2 = source handle }
            if not (((IRKind[valNode] = IR_BINOP) and (IntToTypeKind(IRTk[valNode]) = tyAnsiString)) or
                    ((IRKind[valNode] = IR_CALL) and (IRA[valNode] >= 0))) then
            begin
              XtensaPushA2;                             { save handle }
              EmitStrRefCallXtensa('PXXStrIncRef');
              XtensaPopA2;                              { restore handle }
            end;
          end;
          { Publish: save new, DecRef the old handle in the slot, then store new.
            The slot address can't be held in a8 across the windowed DecRef call
            (call8 rotates a8-a15 out), so recompute it before the store. }
          XtensaPushA2;                                 { save new handle }
          { a2 = old handle from the slot }
          if (Syms[si].Kind = skParam) and Syms[si].IsRef then
          begin
            EmitFrameAddrXtensa(reg_xtensa_a2, Syms[si].Offset);
            xtensa_l32i(reg_xtensa_a2, reg_xtensa_a2, 0);  { caller slot addr }
            xtensa_l32i(reg_xtensa_a2, reg_xtensa_a2, 0);  { old handle }
          end
          else
          begin
            EmitSlotAddrXtensa(reg_xtensa_a2, si);
            xtensa_l32i(reg_xtensa_a2, reg_xtensa_a2, 0);  { old handle }
          end;
          EmitStrRefCallXtensa('PXXStrDecRef');            { DecRef(old) }
          XtensaPopA2;                                     { a2 = new handle }
          { recompute slot addr into a8 (no calls follow) and store }
          if (Syms[si].Kind = skParam) and Syms[si].IsRef then
          begin
            EmitFrameAddrXtensa(reg_xtensa_a8, Syms[si].Offset);
            xtensa_l32i(reg_xtensa_a8, reg_xtensa_a8, 0);  { caller slot addr }
          end
          else
            EmitSlotAddrXtensa(reg_xtensa_a8, si);          { slot addr }
          xtensa_s32i(reg_xtensa_a2, reg_xtensa_a8, 0);     { slot := new }
          Exit;
        end;
        IREmitNodeXtensa(IRB[node]);
        EmitStoreVarXtensa(IRA[node]);
      end;

    IR_LEA:
      begin
        si := IRA[node];
        if Syms[si].Kind = skGlobal then
          EmitLoadGlobAddrXtensa(reg_xtensa_a2, Syms[si].Offset)
        else
          EmitFrameAddrXtensa(reg_xtensa_a2, Syms[si].Offset);
        { Slot holds a heap data pointer (handle) that must be loaded in a
          read/index position: a local dynamic array, or an open-array value
          param (the caller passed the handle). SetLength keeps the slot address.
          (No COW / by-ref open arrays yet.) }
        if (Syms[si].IsArray and (Syms[si].ArrLen = -1)) or
           ((Syms[si].Kind = skParam) and Syms[si].IsArray and not Syms[si].IsRef) then
          xtensa_l32i(reg_xtensa_a2, reg_xtensa_a2, 0)
        { Scalar managed string: read position loads the handle; write position
          keeps the slot address for the store to publish a new handle. }
        else if (Syms[si].TypeKind = tyAnsiString) and not Syms[si].IsArray and
                not InLValueWrite and
                not ((Syms[si].Kind = skParam) and Syms[si].IsRef) then
          xtensa_l32i(reg_xtensa_a2, reg_xtensa_a2, 0);
      end;

    IR_SLOTADDR:
      EmitSlotAddrXtensa(reg_xtensa_a2, IRA[node]);   { always the slot address }

    IR_FIELD:
      begin
        IREmitNodeXtensa(IRA[node]);
        if Integer(IRIVal[node]) <> 0 then
        begin
          EmitLoadConstXtensa(reg_xtensa_a3, Integer(IRIVal[node]));
          xtensa_add(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a3);
        end;
      end;

    IR_INDEX:
      begin
        left := IRA[node];
        right := IRB[node];
        lo := IRC[node];
        elemSize := Integer(IRIVal[node]);

        IREmitNodeXtensa(left);               { base: handle (read) / slot addr (write) }
        { Managed-string index: read position already has the handle (IR_LEA
          loaded it); write position holds the slot address -> clone-if-shared
          via PXXStrUnique to get a writable handle (COW). }
        if (IRKind[left] = IR_LEA) and (Syms[IRA[left]].TypeKind = tyAnsiString) and
           not Syms[IRA[left]].IsArray and InLValueWrite then
        begin
          pi := FindProc('PXXStrUnique');
          if pi < 0 then Error('compiler error: PXXStrUnique not found');
          if XtensaABI = XTENSA_ABI_WINDOWED then
          begin
            xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);
            EmitCallProc(pi);
            xtensa_mov(reg_xtensa_a2, reg_xtensa_a10);   { a2 = unique handle }
          end
          else
            EmitCallProc(pi);                            { a2 = unique handle }
        end;
        XtensaPushA2;

        IREmitNodeXtensa(right);
        if lo <> 0 then
        begin
          EmitLoadConstXtensa(reg_xtensa_a3, lo);
          xtensa_sub(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a3);
        end;

        if (elemSize = 2) or (elemSize = 4) or (elemSize = 8) then
        begin
          xtensa_add(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a2);
          if elemSize >= 4 then
            xtensa_add(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a2);
          if elemSize = 8 then
            xtensa_add(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a2);
        end
        else if elemSize <> 1 then
        begin
          EmitLoadConstXtensa(reg_xtensa_a3, elemSize);
          xtensa_mull(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a3);
        end;

        XtensaPopA3;
        xtensa_add(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a3);
      end;

    IR_LOAD_MEM:
      begin
        IREmitNodeXtensa(IRA[node]);
        tk := IntToTypeKind(IRTk[node]);
        sz := TypeSize(tk);
        sgn := TypeSigned(tk);
        EmitSizedLoadXtensa(reg_xtensa_a2, reg_xtensa_a2, sz, sgn);
      end;

    IR_STORE_MEM:
      begin
        IREmitNodeXtensa(IRB[node]);
        XtensaPushA2;
        savedLVW := InLValueWrite;
        InLValueWrite := True;
        IREmitNodeXtensa(IRA[node]);
        InLValueWrite := savedLVW;
        XtensaPopA3;
        tk := IntToTypeKind(IRTk[node]);
        sz := TypeSize(tk);
        EmitSizedStoreXtensa(reg_xtensa_a3, reg_xtensa_a2, sz);
      end;

    IR_BINOP:
      begin
        left := IRA[node];
        right := IRB[node];
        op := IRC[node];

        if (IntToTypeKind(IRTk[node]) = tyAnsiString) and (op = Ord(tkPlus)) then
        begin
          { Managed-string concat -> PXXStrConcat(lenA, srcA, srcB, lenB). Operand
            len/src into a4=lenA,a5=srcA,a6=srcB,a7=lenB (a2-a7 survive call8). }
          argBase := XtSpillDepth;
          IREmitNodeXtensa(left);  XtensaPushA2;       { lhs @ argBase }
          IREmitNodeXtensa(right); XtensaPushA2;       { rhs @ argBase+4 }
          { rhs -> srcB(a6)/lenB(a7) }
          xtensa_l32i(reg_xtensa_a8, reg_xtensa_sp, argBase + 4);
          if IntToTypeKind(IRTk[right]) = tyAnsiString then
          begin
            xtensa_mov(reg_xtensa_a6, reg_xtensa_a8);
            EmitAsmXtensa(['movi a7, 0', 'movi a9, 0', 'beq a8, a9, .cb',
                           'addi a9, a8, -8', 'l32i a7, a9, 0', '.cb:']);
          end
          else if IntToTypeKind(IRTk[right]) = tyString then
          begin
            xtensa_l32i(reg_xtensa_a7, reg_xtensa_a8, 0);
            xtensa_addi(reg_xtensa_a6, reg_xtensa_a8, 8);
          end
          else
          begin
            xtensa_addi(reg_xtensa_a6, reg_xtensa_sp, argBase + 4);
            EmitLoadConstXtensa(reg_xtensa_a7, 1);
          end;
          { lhs -> srcA(a5)/lenA(a4) }
          xtensa_l32i(reg_xtensa_a8, reg_xtensa_sp, argBase + 0);
          if IntToTypeKind(IRTk[left]) = tyAnsiString then
          begin
            xtensa_mov(reg_xtensa_a5, reg_xtensa_a8);
            EmitAsmXtensa(['movi a4, 0', 'movi a9, 0', 'beq a8, a9, .ca',
                           'addi a9, a8, -8', 'l32i a4, a9, 0', '.ca:']);
          end
          else if IntToTypeKind(IRTk[left]) = tyString then
          begin
            xtensa_l32i(reg_xtensa_a4, reg_xtensa_a8, 0);
            xtensa_addi(reg_xtensa_a5, reg_xtensa_a8, 8);
          end
          else
          begin
            xtensa_addi(reg_xtensa_a5, reg_xtensa_sp, argBase + 0);
            EmitLoadConstXtensa(reg_xtensa_a4, 1);
          end;
          pi := FindProc('PXXStrConcat');
          if pi < 0 then Error('compiler error: PXXStrConcat not found');
          if XtensaABI = XTENSA_ABI_WINDOWED then
          begin
            xtensa_mov(reg_xtensa_a10, reg_xtensa_a4);
            xtensa_mov(reg_xtensa_a11, reg_xtensa_a5);
            xtensa_mov(reg_xtensa_a12, reg_xtensa_a6);
            xtensa_mov(reg_xtensa_a13, reg_xtensa_a7);
            EmitCallProc(pi);
            xtensa_mov(reg_xtensa_a2, reg_xtensa_a10);
          end
          else
          begin
            xtensa_mov(reg_xtensa_a2, reg_xtensa_a4);   { a2=lenA }
            xtensa_mov(reg_xtensa_a3, reg_xtensa_a5);   { a3=srcA }
            xtensa_mov(reg_xtensa_a4, reg_xtensa_a6);   { a4=srcB }
            xtensa_mov(reg_xtensa_a5, reg_xtensa_a7);   { a5=lenB }
            EmitCallProc(pi);                           { result a2 }
          end;
          { release fresh tyAnsiString BINOP operand temporaries }
          XtensaPushA2;                                 { result @ argBase+8 }
          if (IRKind[left] = IR_BINOP) and (IntToTypeKind(IRTk[left]) = tyAnsiString) then
          begin
            xtensa_l32i(reg_xtensa_a2, reg_xtensa_sp, argBase + 0);
            EmitStrRefCallXtensa('PXXStrDecRef');
          end;
          if (IRKind[right] = IR_BINOP) and (IntToTypeKind(IRTk[right]) = tyAnsiString) then
          begin
            xtensa_l32i(reg_xtensa_a2, reg_xtensa_sp, argBase + 4);
            EmitStrRefCallXtensa('PXXStrDecRef');
          end;
          xtensa_l32i(reg_xtensa_a2, reg_xtensa_sp, argBase + 8);   { result }
          XtSpillDepth := argBase;                                  { drop result, rhs, lhs }
          Exit;
        end;

        if ((op = Ord(tkEq)) or (op = Ord(tkNeq))) and
           ((IntToTypeKind(IRTk[left]) = tyAnsiString) or (IntToTypeKind(IRTk[right]) = tyAnsiString)) then
        begin
          { Managed-string equality -> PXXStrEq(lenA, srcA, lenB, srcB) -> 1/0.
            Each operand decomposed (mirrors concat): handle -> len [h-8] (0 if
            nil) + src h; frozen tyString -> len [buf] + src buf+8; char -> len 1
            + src &slot. Build a4=lenA,a5=srcA,a6=lenB,a7=srcB (a2-a7 survive
            call8). }
          argBase := XtSpillDepth;
          IREmitNodeXtensa(left);  XtensaPushA2;       { lhs @ argBase }
          IREmitNodeXtensa(right); XtensaPushA2;       { rhs @ argBase+4 }
          { rhs -> lenB(a6)/srcB(a7) }
          xtensa_l32i(reg_xtensa_a8, reg_xtensa_sp, argBase + 4);
          if IntToTypeKind(IRTk[right]) = tyAnsiString then
          begin
            xtensa_mov(reg_xtensa_a7, reg_xtensa_a8);
            EmitAsmXtensa(['movi a6, 0', 'movi a9, 0', 'beq a8, a9, .cb',
                           'addi a9, a8, -8', 'l32i a6, a9, 0', '.cb:']);
          end
          else if IntToTypeKind(IRTk[right]) = tyString then
          begin
            xtensa_l32i(reg_xtensa_a6, reg_xtensa_a8, 0);
            xtensa_addi(reg_xtensa_a7, reg_xtensa_a8, 8);
          end
          else
          begin
            xtensa_addi(reg_xtensa_a7, reg_xtensa_sp, argBase + 4);
            EmitLoadConstXtensa(reg_xtensa_a6, 1);
          end;
          { lhs -> lenA(a4)/srcA(a5) }
          xtensa_l32i(reg_xtensa_a8, reg_xtensa_sp, argBase + 0);
          if IntToTypeKind(IRTk[left]) = tyAnsiString then
          begin
            xtensa_mov(reg_xtensa_a5, reg_xtensa_a8);
            EmitAsmXtensa(['movi a4, 0', 'movi a9, 0', 'beq a8, a9, .ca',
                           'addi a9, a8, -8', 'l32i a4, a9, 0', '.ca:']);
          end
          else if IntToTypeKind(IRTk[left]) = tyString then
          begin
            xtensa_l32i(reg_xtensa_a4, reg_xtensa_a8, 0);
            xtensa_addi(reg_xtensa_a5, reg_xtensa_a8, 8);
          end
          else
          begin
            xtensa_addi(reg_xtensa_a5, reg_xtensa_sp, argBase + 0);
            EmitLoadConstXtensa(reg_xtensa_a4, 1);
          end;
          pi := FindProc('PXXStrEq');
          if pi < 0 then Error('compiler error: PXXStrEq not found');
          if XtensaABI = XTENSA_ABI_WINDOWED then
          begin
            xtensa_mov(reg_xtensa_a10, reg_xtensa_a4);
            xtensa_mov(reg_xtensa_a11, reg_xtensa_a5);
            xtensa_mov(reg_xtensa_a12, reg_xtensa_a6);
            xtensa_mov(reg_xtensa_a13, reg_xtensa_a7);
            EmitCallProc(pi);
            xtensa_mov(reg_xtensa_a2, reg_xtensa_a10);
          end
          else
          begin
            xtensa_mov(reg_xtensa_a2, reg_xtensa_a4);   { a2=lenA }
            xtensa_mov(reg_xtensa_a3, reg_xtensa_a5);   { a3=srcA }
            xtensa_mov(reg_xtensa_a4, reg_xtensa_a6);   { a4=lenB }
            xtensa_mov(reg_xtensa_a5, reg_xtensa_a7);   { a5=srcB }
            EmitCallProc(pi);                           { result a2 }
          end;
          { release fresh tyAnsiString BINOP operand temporaries }
          XtensaPushA2;                                 { result @ argBase+8 }
          if (IRKind[left] = IR_BINOP) and (IntToTypeKind(IRTk[left]) = tyAnsiString) then
          begin
            xtensa_l32i(reg_xtensa_a2, reg_xtensa_sp, argBase + 0);
            EmitStrRefCallXtensa('PXXStrDecRef');
          end;
          if (IRKind[right] = IR_BINOP) and (IntToTypeKind(IRTk[right]) = tyAnsiString) then
          begin
            xtensa_l32i(reg_xtensa_a2, reg_xtensa_sp, argBase + 4);
            EmitStrRefCallXtensa('PXXStrDecRef');
          end;
          xtensa_l32i(reg_xtensa_a2, reg_xtensa_sp, argBase + 8);   { result }
          XtSpillDepth := argBase;                                  { drop result, rhs, lhs }
          if op = Ord(tkNeq) then
          begin
            xtensa_movi(reg_xtensa_a8, 1);
            xtensa_xor(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a8);
          end;
          Exit;
        end;

        if (op = Ord(tkPlus)) and (IntToTypeKind(IRTk[node]) = tyString) then
          Error('target xtensa: frozen tyString concat unsupported; only literal+literal folds (combine nested string literals)');

        IREmitNodeXtensa(left);
        XtensaPushA2;
        IREmitNodeXtensa(right);
        xtensa_mov(reg_xtensa_a3, reg_xtensa_a2);
        { pop the saved left operand into a2 }
        if XtensaABI = XTENSA_ABI_WINDOWED then
        begin
          Dec(XtSpillDepth, 4);
          xtensa_l32i(reg_xtensa_a2, reg_xtensa_sp, XtSpillDepth);
        end
        else
        begin
          xtensa_l32i(reg_xtensa_a2, reg_xtensa_sp, 0);
          xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, 4);
        end;
        { a2 = left, a3 = right }

        if op = Ord(tkPlus) then xtensa_add(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a3)
        else if op = Ord(tkMinus) then xtensa_sub(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a3)
        else if op = Ord(tkStar) then xtensa_mull(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a3)
        else if op = Ord(tkDiv) then
        begin
          if XtensaSoftDivide then EmitXtensaSoftDivCall('__pxx_divsi3')
          else xtensa_quos(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a3);
        end
        else if op = Ord(tkMod) then
        begin
          if XtensaSoftDivide then EmitXtensaSoftDivCall('__pxx_modsi3')
          else xtensa_rems(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a3);
        end
        else if op = Ord(tkShl) then
        begin
          { a2 := a2 << a3 : SAR from a3, then SLL takes the value in s=a2. }
          xtensa_ssl(reg_xtensa_a3);
          xtensa_sll(reg_xtensa_a2, reg_xtensa_a2);
        end
        else if op = Ord(tkIdent) then
        begin
          { 'shr' parses as an identifier operator (logical right shift, like the
            riscv path): SAR from a3, then SRL takes the value in t=a2. }
          xtensa_ssr(reg_xtensa_a3);
          xtensa_srl(reg_xtensa_a2, reg_xtensa_a2);
        end
        else if op = Ord(tkAnd) then xtensa_and(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a3)
        else if op = Ord(tkOr) then xtensa_or(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a3)
        { Comparison: a2 := (a2 rel a3) ? 1 : 0. = and <> subtract then branch on
          zero; the ordered forms branch on the operands. The conditional branch
          skips the `movi a4, 0` to the `.done` label. }
        else if op = Ord(tkEq) then
          EmitAsmXtensa(['sub a2, a2, a3','movi a3, 0','movi a4, 1','beq a2, a3, .done','movi a4, 0','.done:','mov a2, a4'])
        else if op = Ord(tkNeq) then
          EmitAsmXtensa(['sub a2, a2, a3','movi a3, 0','movi a4, 1','bne a2, a3, .done','movi a4, 0','.done:','mov a2, a4'])
        else if op = Ord(tkLt) then
          EmitAsmXtensa(['movi a4, 1','blt a2, a3, .done','movi a4, 0','.done:','mov a2, a4'])
        else if op = Ord(tkGt) then
          EmitAsmXtensa(['movi a4, 1','blt a3, a2, .done','movi a4, 0','.done:','mov a2, a4'])
        else if op = Ord(tkLe) then
          EmitAsmXtensa(['movi a4, 1','bge a3, a2, .done','movi a4, 0','.done:','mov a2, a4'])
        else if op = Ord(tkGe) then
          EmitAsmXtensa(['movi a4, 1','bge a2, a3, .done','movi a4, 0','.done:','mov a2, a4'])
        else
          Error('target xtensa: unsupported binary operator (div/mod/shifts pending)');
      end;

    IR_CALL:
      begin
        pi := IRA[node];
        if pi = -Ord(tkGetMem) then
        begin
          { GetMem / New. Class instantiation (VMT + ctor) is a later step. }
          if IRC[node] >= REC_UCLASS_BASE then
            Error('target xtensa: class instantiation not yet supported');
          argNode := IRB[node];                 { size arg }
          IREmitNodeXtensa(IRA[argNode]);       { size -> a2 }
          EmitHeapAllocLockedXtensa;            { a2 = payload pointer }
          Exit;
        end;
        if pi = -Ord(tkFreeMem) then
        begin
          argNode := IRB[node];                 { pointer arg }
          IREmitNodeXtensa(IRA[argNode]);       { p -> a2 }
          EmitHeapFreeLockedXtensa;
          Exit;
        end;
        if pi = -102 then
        begin
          { SetLength(arr, n) -> PXXDynSetLen(slotAddr, n, desc). SetLength on a
            managed AnsiString -> PXXStrSetLen(slotAddr, n). }
          argNode := IRB[node];                 { arg1 = array/string lvalue }
          valNode := IRB[argNode];              { arg2 = new length }
          left := IRA[argNode];
          if (IRKind[left] = IR_LOAD_SYM) and
             (Syms[IRA[left]].TypeKind = tyAnsiString) then
          begin
            si := IRA[left];
            argBase := XtSpillDepth;
            if (Syms[si].Kind = skParam) and Syms[si].IsRef then
            begin
              EmitFrameAddrXtensa(reg_xtensa_a2, Syms[si].Offset);
              xtensa_l32i(reg_xtensa_a2, reg_xtensa_a2, 0); { caller slot addr }
            end
            else
              EmitSlotAddrXtensa(reg_xtensa_a2, si);        { slot address }
            XtensaPushA2;                                    { slot @ argBase }
            IREmitNodeXtensa(IRA[valNode]);                  { a2 = n }
            XtensaPushA2;                                    { n @ argBase+4 }
            pi := FindProc('PXXStrSetLen');
            if pi < 0 then Error('compiler error: PXXStrSetLen not found');
            if XtensaABI = XTENSA_ABI_WINDOWED then
            begin
              xtensa_l32i(reg_xtensa_a10, reg_xtensa_sp, argBase + 0);
              xtensa_l32i(reg_xtensa_a11, reg_xtensa_sp, argBase + 4);
              XtSpillDepth := argBase;
            end
            else
            begin
              xtensa_l32i(reg_xtensa_a2, reg_xtensa_sp, argBase + 0);
              xtensa_l32i(reg_xtensa_a3, reg_xtensa_sp, argBase + 4);
              XtSpillDepth := argBase;
            end;
            EmitCallProc(pi);
            Exit;
          end;
          if IRKind[left] <> IR_LEA then
            Error('target xtensa: SetLength expects an array variable');
          si := IRA[left];
          if not (Syms[si].IsArray and (Syms[si].ArrLen = -1)) then
            Error('target xtensa: SetLength only supports dynamic arrays yet');
          if (Syms[si].Kind = skParam) and Syms[si].IsRef then
            Error('target xtensa: SetLength on a var-array parameter not yet supported');
          argBase := XtSpillDepth;
          EmitSlotAddrXtensa(reg_xtensa_a2, si); { a2 = slot address (not the handle) }
          XtensaPushA2;
          IREmitNodeXtensa(IRA[valNode]);       { a2 = n }
          XtensaPushA2;
          EmitLoadDataRefXtensa(reg_xtensa_a2, GetOrAllocSymRTTI(si)); { a2 = desc }
          XtensaPushA2;
          pi := FindProc('PXXDynSetLen');
          if pi < 0 then Error('compiler error: PXXDynSetLen not found');
          if XtensaABI = XTENSA_ABI_WINDOWED then
          begin
            xtensa_l32i(reg_xtensa_a10, reg_xtensa_sp, argBase + 0);
            xtensa_l32i(reg_xtensa_a11, reg_xtensa_sp, argBase + 4);
            xtensa_l32i(reg_xtensa_a12, reg_xtensa_sp, argBase + 8);
            XtSpillDepth := argBase;
          end
          else
          begin
            xtensa_l32i(reg_xtensa_a2, reg_xtensa_sp, 8);
            xtensa_l32i(reg_xtensa_a3, reg_xtensa_sp, 4);
            xtensa_l32i(reg_xtensa_a4, reg_xtensa_sp, 0);
            xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, 12);
          end;
          EmitCallProc(pi);
          Exit;
        end;
        if pi = -Ord(tkLength) then
        begin
          { Length(arr): a2 = handle; count at [handle-8], nil handle -> 0.
            (l32i has no negative offset, so address via addi first.) }
          argNode := IRB[node];
          IREmitNodeXtensa(IRA[argNode]);       { a2 = handle (or 0) }
          EmitAsmXtensa(['movi a4, 0', 'beq a2, a4, .lzero',
                         'addi a2, a2, -8', 'l32i a2, a2, 0', '.lzero:']);
          Exit;
        end;
        if pi < 0 then
        begin
          { Type-pun passthroughs: Ord/Chr/Integer()/LongWord() are identity on
            the value already in a2 (char/int share the register model). }
          if (pi = -Ord(tkOrd)) or (pi = -Ord(tkChr)) or
             (pi = -Ord(tkInteger_T)) or (pi = -Ord(tkLongWord_T)) or
             (pi = -Ord(tkChar_T)) or (pi = -Ord(tkBoolean_T)) or
             (pi = -Ord(tkString_T)) then
          begin
            argNode := IRB[node];
            IREmitNodeXtensa(IRA[argNode]);
            Exit;
          end;
          Error('target xtensa: builtin calls not supported in bare-metal stage 1');
        end;

        argNode := IRB[node];
        nArgs := 0;
        argBase := XtSpillDepth;   { windowed: base offset of this call's arg block }
        while argNode <> -1 do
        begin
          IREmitNodeXtensa(IRA[argNode]);
          { External C call: skip the 8-byte length prefix of a Pascal string
            literal so the callee sees a const char* (as on x86-64/riscv32). }
          if ProcExternal[pi] and (IntToTypeKind(IRTk[argNode]) = tyString) then
            xtensa_addi(reg_xtensa_a2, reg_xtensa_a2, 8);
          XtensaPushA2;
          Inc(nArgs);
          argNode := IRB[argNode];
        end;

        if nArgs > 6 then
          Error('target xtensa: more than 6 call arguments not supported yet');

        { Load the outgoing argument registers. Windowed keeps sp constant, so
          the args sit at sp-relative offsets wid..wid+(n-1)*4 (arg0 lowest);
          pop them off the expression stack by resetting XtSpillDepth. Call0
          uses the moving-sp slots (arg0 deepest) and frees them with addi. }
        if XtensaABI = XTENSA_ABI_WINDOWED then
        begin
          for i := 0 to nArgs - 1 do
            xtensa_l32i(reg_xtensa_a10 + i, reg_xtensa_sp, argBase + i * 4);
          XtSpillDepth := argBase;
        end
        else
        begin
          for i := 0 to nArgs - 1 do
            xtensa_l32i(reg_xtensa_a2 + i, reg_xtensa_sp, (nArgs - 1 - i) * 4);
          if nArgs > 0 then
            xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, nArgs * 4);
        end;

        EmitCallProc(pi);
        if XtensaABI = XTENSA_ABI_WINDOWED then
          xtensa_mov(reg_xtensa_a2, reg_xtensa_a10);
      end;

    IR_WRITE, IR_WRITELN:
      begin
        { Bare-metal: write/writeln does nothing. }
      end;

    IR_TERMINATE:
      begin
        if IRIVal[node] = AN_HALT then
          EmitExit(0)                            { bare-metal: park in a self-loop }
        else if CurProc >= 0 then
          EmitProcEpilog(Procs[CurProc].RetSymIdx) { early Exit: jump out via epilogue }
        else
          EmitExit(0);
      end;

    IR_DEFAULT_MEM:
      begin
        { Zero IRIVal bytes at dest. ESP has no managed records yet, so skip the
          PXXRecordRelease path the hosted targets take for managed fields. }
        IREmitNodeXtensa(IRA[node]);             { a2 = dest }
        pi := FindProc('PXXMemZero');
        if pi < 0 then Error('compiler error: PXXMemZero not found');
        if XtensaABI = XTENSA_ABI_WINDOWED then
        begin
          xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);        { arg0 = dest }
          EmitLoadConstXtensa(reg_xtensa_a11, Integer(IRIVal[node])); { arg1 = count }
        end
        else
          EmitLoadConstXtensa(reg_xtensa_a3, Integer(IRIVal[node])); { a2=dest; arg1=count }
        EmitCallProc(pi);
      end;

    IR_NEG:
      begin
        IREmitNodeXtensa(IRA[node]);
        xtensa_movi(reg_xtensa_a8, 0);
        xtensa_sub(reg_xtensa_a2, reg_xtensa_a8, reg_xtensa_a2);
      end;

    IR_NOT:
      begin
        IREmitNodeXtensa(IRA[node]);
        xtensa_movi(reg_xtensa_a8, 1);
        xtensa_xor(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a8);
      end;

    else
      Error('target xtensa: unsupported node in IR codegen: ' + IROpName(IRKind[node]));
  end;
end;

procedure IREmitMachineCodeXtensa;
var i, lblId, pos, f: Integer;
    LabelPositions: array[0..MAX_IR-1] of Integer;
    LabelFixupPos: array[0..2047] of Integer;
    LabelFixupTarget: array[0..2047] of Integer;
    LabelFixupCount: Integer;
begin
  for i := 0 to MAX_IR - 1 do
    LabelPositions[i] := -1;
  LabelFixupCount := 0;

  for i := 0 to IRCount - 1 do
  begin
    case IRKind[i] of
      IR_LABEL:
        begin
          lblId := Integer(IRIVal[i]);
          if (lblId >= 0) and (lblId < MAX_IR) then
            LabelPositions[lblId] := CodeLen;
        end;

      IR_JUMP:
        begin
          lblId := IRA[i];
          if LabelPositions[lblId] <> -1 then
            xtensa_j(LabelPositions[lblId] - CodeLen)
          else
          begin
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            xtensa_j(4);
          end;
        end;

      IR_JUMP_IF_FALSE:
        begin
          lblId := IRA[i];
          IREmitNodeXtensa(IRB[i]);
          { Conditional branch range is only +-127 bytes, so branch over an
            18-bit J: if cond <> 0 skip the J, else J label. }
          xtensa_movi(reg_xtensa_a4, 0);
          xtensa_bne(reg_xtensa_a2, reg_xtensa_a4, 6);
          if LabelPositions[lblId] <> -1 then
            xtensa_j(LabelPositions[lblId] - CodeLen)
          else
          begin
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            xtensa_j(4);
          end;
        end;

      IR_CALL:
        begin
          if IRIVal[i] = 1 then
            IREmitNodeXtensa(i);
        end;

      IR_STORE_SYM, IR_WRITE, IR_WRITELN:
        IREmitNodeXtensa(i);

      IR_NOP, IR_CONST_STR, IR_CONST_INT, IR_BLOCK,
      IR_LOAD_SYM, IR_BINOP, IR_NEG, IR_NOT, IR_ARG, IR_LEA, IR_SYSCALL,
      IR_SLOTADDR, IR_FIELD, IR_INDEX: ;

      else
        IREmitNodeXtensa(i);
    end;
  end;

  for f := 0 to LabelFixupCount - 1 do
  begin
    lblId := LabelFixupTarget[f];
    pos := LabelFixupPos[f];
    if LabelPositions[lblId] = -1 then
      Error('Unresolved forward jump in Xtensa IR codegen');
    Patch24(pos, EncodeXtensaJ(LabelPositions[lblId] - pos));
  end;
end;
