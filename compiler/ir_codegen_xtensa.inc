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
begin
  xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, -4);
  xtensa_s32i(reg_xtensa_a2, reg_xtensa_sp, 0);
end;

procedure XtensaPopA3;
begin
  xtensa_l32i(reg_xtensa_a3, reg_xtensa_sp, 0);
  xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, 4);
end;

procedure IREmitNodeXtensa(node: Integer);
var
  left, right, op, si, pi, nArgs, i, lo, elemSize, sz, argNode: Integer;
  tk: TTypeKind;
  sgn: Boolean;
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
      end;

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

        IREmitNodeXtensa(left);
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
        IREmitNodeXtensa(IRA[node]);
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

        IREmitNodeXtensa(left);
        XtensaPushA2;
        IREmitNodeXtensa(right);
        xtensa_mov(reg_xtensa_a3, reg_xtensa_a2);
        xtensa_l32i(reg_xtensa_a2, reg_xtensa_sp, 0);
        xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, 4);
        { a2 = left, a3 = right }

        if op = Ord(tkPlus) then xtensa_add(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a3)
        else if op = Ord(tkMinus) then xtensa_sub(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a3)
        else if op = Ord(tkStar) then xtensa_mull(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a3)
        else if op = Ord(tkDiv) then xtensa_quos(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a3)
        else if op = Ord(tkMod) then xtensa_rems(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a3)
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
        if pi < 0 then
          Error('target xtensa: builtin calls not supported in bare-metal stage 1');

        argNode := IRB[node];
        nArgs := 0;
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

        for i := 0 to nArgs - 1 do
        begin
          if XtensaABI = XTENSA_ABI_WINDOWED then
            xtensa_l32i(reg_xtensa_a10 + i, reg_xtensa_sp, (nArgs - 1 - i) * 4)
          else
            xtensa_l32i(reg_xtensa_a2 + i, reg_xtensa_sp, (nArgs - 1 - i) * 4);
        end;

        if nArgs > 0 then
          xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, nArgs * 4);

        EmitCallProc(pi);
        if XtensaABI = XTENSA_ABI_WINDOWED then
          xtensa_mov(reg_xtensa_a2, reg_xtensa_a10);
      end;

    IR_WRITE, IR_WRITELN:
      begin
        { Bare-metal: write/writeln does nothing. }
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
      Error('target xtensa: unsupported node in IR codegen');
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
