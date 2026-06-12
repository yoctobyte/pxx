{ ===== IR -> RISC-V 32-bit machine code (cross target) ===== }

procedure EmitLoadImmRISCV32(rd: Integer; v: Int32);
var
  lo, hi: Integer;
begin
  if (v >= -2048) and (v <= 2047) then
  begin
    rv32_addi(rd, reg_zero, v);
  end
  else
  begin
    lo := v and $FFF;
    hi := v - lo;
    if (v and $800) <> 0 then
      hi := hi + $1000;
    rv32_lui(rd, hi);
    if lo <> 0 then
      rv32_addi(rd, rd, lo);
  end;
end;

procedure EmitLoadDataRefRISCV32(rd: Integer; dataOff: Integer);
begin
  { Load 32-bit literal at PC-relative offset }
  rv32_auipc(rd, 0);
  rv32_jal(reg_zero, 8);
  EmitDataRef(dataOff);
  rv32_lw(rd, rd, 8);
end;

procedure EmitLoadGlobAddrRISCV32(rd: Integer; bssOff: Integer);
{ Same inline-literal trick, but the 32-bit slot is a BSS absolute address
  patched by the ELF writer. }
begin
  rv32_auipc(rd, 0);
  rv32_jal(reg_zero, 8);
  EmitGlobRef(bssOff);
  rv32_lw(rd, rd, 8);
end;

procedure EmitSizedLoadRISCV32(rd, rs: Integer; sz: Integer; sgn: Boolean);
begin
  if sz = 1 then
  begin
    if sgn then rv32_lb(rd, rs, 0) else rv32_lbu(rd, rs, 0);
  end
  else if sz = 2 then
  begin
    if sgn then rv32_lh(rd, rs, 0) else rv32_lhu(rd, rs, 0);
  end
  else
    rv32_lw(rd, rs, 0);
end;

procedure EmitSizedStoreRISCV32(rs2, rs1: Integer; sz: Integer);
begin
  if sz = 1 then
    rv32_sb(rs2, rs1, 0)
  else if sz = 2 then
    rv32_sh(rs2, rs1, 0)
  else
    rv32_sw(rs2, rs1, 0);
end;

procedure EmitLoadVarRISCV32(idx: Integer);
var tk: TTypeKind; sz: Integer; sgn: Boolean;
begin
  tk := Syms[idx].TypeKind;
  sz := TypeSize(tk);
  sgn := TypeSigned(tk);

  if Syms[idx].Kind = skGlobal then
  begin
    EmitLoadGlobAddrRISCV32(reg_t0, Syms[idx].Offset);
    EmitSizedLoadRISCV32(reg_a0, reg_t0, sz, sgn);
  end
  else
  begin
    { Local variable offset relative to frame pointer s0 }
    EmitLoadImmRISCV32(reg_t0, Syms[idx].Offset);
    rv32_add(reg_t0, reg_s0, reg_t0);
    if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then
      rv32_lw(reg_t0, reg_t0, 0);
    EmitSizedLoadRISCV32(reg_a0, reg_t0, sz, sgn);
  end;
end;

procedure EmitStoreVarRISCV32(idx: Integer);
var tk: TTypeKind; sz: Integer;
begin
  tk := Syms[idx].TypeKind;
  sz := TypeSize(tk);

  if Syms[idx].Kind = skGlobal then
  begin
    EmitLoadGlobAddrRISCV32(reg_t0, Syms[idx].Offset);
    EmitSizedStoreRISCV32(reg_a0, reg_t0, sz);
  end
  else
  begin
    EmitLoadImmRISCV32(reg_t0, Syms[idx].Offset);
    rv32_add(reg_t0, reg_s0, reg_t0);
    if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then
      rv32_lw(reg_t0, reg_t0, 0);
    EmitSizedStoreRISCV32(reg_a0, reg_t0, sz);
  end;
end;

procedure IREmitNodeRISCV32(node: Integer);
var
  left, right, op, si, pi, nArgs, i, lo, elemSize, sz, argNode: Integer;
  tk: TTypeKind;
  sgn: Boolean;
  sVal: AnsiString;
begin
  case IRKind[node] of
    IR_CONST_INT:
      EmitLoadImmRISCV32(reg_a0, IRIVal[node]);

    IR_CONST_STR:
      begin
        sVal := GetTokenStrFromRaw(IRA[node], IRB[node]);
        si := InternStr(sVal);
        EmitLoadDataRefRISCV32(reg_a0, Strs[si].Offset);
      end;

    IR_LOAD_SYM:
      EmitLoadVarRISCV32(IRA[node]);

    IR_STORE_SYM:
      begin
        IREmitNodeRISCV32(IRB[node]);
        EmitStoreVarRISCV32(IRA[node]);
      end;

    IR_LEA:
      begin
        si := IRA[node];
        if Syms[si].Kind = skGlobal then
          EmitLoadGlobAddrRISCV32(reg_a0, Syms[si].Offset)
        else
        begin
          EmitLoadImmRISCV32(reg_a0, Syms[si].Offset);
          rv32_add(reg_a0, reg_s0, reg_a0);
        end;
      end;

    IR_FIELD:
      begin
        IREmitNodeRISCV32(IRA[node]);
        if Integer(IRIVal[node]) <> 0 then
        begin
          EmitLoadImmRISCV32(reg_a1, Integer(IRIVal[node]));
          rv32_add(reg_a0, reg_a0, reg_a1);
        end;
      end;

    IR_INDEX:
      begin
        left := IRA[node];
        right := IRB[node];
        lo := IRC[node];
        elemSize := Integer(IRIVal[node]);

        IREmitNodeRISCV32(left);
        rv32_addi(reg_sp, reg_sp, -4);
        rv32_sw(reg_a0, reg_sp, 0);

        IREmitNodeRISCV32(right);
        if lo <> 0 then
          rv32_addi(reg_a0, reg_a0, -lo);

        if elemSize = 8 then
        begin
          rv32_addi(reg_a1, reg_zero, 3);
          rv32_sll(reg_a0, reg_a0, reg_a1);
        end
        else if elemSize = 4 then
        begin
          rv32_addi(reg_a1, reg_zero, 2);
          rv32_sll(reg_a0, reg_a0, reg_a1);
        end
        else if elemSize = 2 then
        begin
          rv32_addi(reg_a1, reg_zero, 1);
          rv32_sll(reg_a0, reg_a0, reg_a1);
        end
        else if elemSize <> 1 then
        begin
          EmitLoadImmRISCV32(reg_a1, elemSize);
          rv32_mul(reg_a0, reg_a0, reg_a1);
        end;

        rv32_lw(reg_a1, reg_sp, 0);
        rv32_addi(reg_sp, reg_sp, 4);
        rv32_add(reg_a0, reg_a0, reg_a1);
      end;

    IR_LOAD_MEM:
      begin
        IREmitNodeRISCV32(IRA[node]);
        tk := IntToTypeKind(IRTk[node]);
        sz := TypeSize(tk);
        sgn := TypeSigned(tk);
        if sz = 1 then
        begin
          if sgn then rv32_lb(reg_a0, reg_a0, 0) else rv32_lbu(reg_a0, reg_a0, 0);
        end
        else if sz = 2 then
        begin
          if sgn then rv32_lh(reg_a0, reg_a0, 0) else rv32_lhu(reg_a0, reg_a0, 0);
        end
        else
          rv32_lw(reg_a0, reg_a0, 0);
      end;

    IR_STORE_MEM:
      begin
        IREmitNodeRISCV32(IRB[node]);
        rv32_addi(reg_sp, reg_sp, -4);
        rv32_sw(reg_a0, reg_sp, 0);

        IREmitNodeRISCV32(IRA[node]);
        rv32_lw(reg_a1, reg_sp, 0);
        rv32_addi(reg_sp, reg_sp, 4);

        tk := IntToTypeKind(IRTk[node]);
        sz := TypeSize(tk);
        if sz = 1 then
          rv32_sb(reg_a1, reg_a0, 0)
        else if sz = 2 then
          rv32_sh(reg_a1, reg_a0, 0)
        else
          rv32_sw(reg_a1, reg_a0, 0);
      end;

    IR_BINOP:
      begin
        left := IRA[node];
        right := IRB[node];
        op := IRC[node];

        IREmitNodeRISCV32(left);
        rv32_addi(reg_sp, reg_sp, -4);
        rv32_sw(reg_a0, reg_sp, 0);

        IREmitNodeRISCV32(right);
        rv32_addi(reg_a1, reg_a0, 0);

        rv32_lw(reg_a0, reg_sp, 0);
        rv32_addi(reg_sp, reg_sp, 4);

        if op = Ord(tkPlus) then rv32_add(reg_a0, reg_a0, reg_a1)
        else if op = Ord(tkMinus) then rv32_sub(reg_a0, reg_a0, reg_a1)
        else if op = Ord(tkStar) then rv32_mul(reg_a0, reg_a0, reg_a1)
        else if op = Ord(tkDiv) then rv32_div(reg_a0, reg_a0, reg_a1)
        else if op = Ord(tkMod) then rv32_rem(reg_a0, reg_a0, reg_a1)
        else if op = Ord(tkAnd) then rv32_and(reg_a0, reg_a0, reg_a1)
        else if op = Ord(tkOr) then rv32_or(reg_a0, reg_a0, reg_a1)
        else if op = Ord(tkShl) then rv32_sll(reg_a0, reg_a0, reg_a1)
        else if op = Ord(tkIdent) then rv32_srl(reg_a0, reg_a0, reg_a1) { 'shr' parses as ident }
        else if op = Ord(tkEq) then
        begin
          rv32_sub(reg_a0, reg_a0, reg_a1);
          rv32_sltu(reg_a0, reg_zero, reg_a0);
          rv32_xori(reg_a0, reg_a0, 1);
        end
        else if op = Ord(tkNeq) then
        begin
          rv32_sub(reg_a0, reg_a0, reg_a1);
          rv32_sltu(reg_a0, reg_zero, reg_a0);
        end
        else if op = Ord(tkLt) then
          rv32_slt(reg_a0, reg_a0, reg_a1)
        else if op = Ord(tkGt) then
          rv32_slt(reg_a0, reg_a1, reg_a0)
        else if op = Ord(tkLe) then
        begin
          rv32_slt(reg_a0, reg_a1, reg_a0);
          rv32_xori(reg_a0, reg_a0, 1);
        end
        else if op = Ord(tkGe) then
        begin
          rv32_slt(reg_a0, reg_a0, reg_a1);
          rv32_xori(reg_a0, reg_a0, 1);
        end
        else
          Error('target riscv32: unsupported binary operator');
      end;

    IR_CALL:
      begin
        pi := IRA[node];
        if pi < 0 then
          Error('target riscv32: standard builtin calls not supported in bare-metal stage 1');

        argNode := IRB[node];
        nArgs := 0;
        while argNode <> -1 do
        begin
          IREmitNodeRISCV32(IRA[argNode]);
          rv32_addi(reg_sp, reg_sp, -4);
          rv32_sw(reg_a0, reg_sp, 0);
          Inc(nArgs);
          argNode := IRB[argNode];
        end;

        if nArgs > 8 then
          Error('target riscv32: more than 8 call arguments not supported yet');

        for i := 0 to nArgs - 1 do
          rv32_lw(reg_a0 + i, reg_sp, (nArgs - 1 - i) * 4);

        if nArgs > 0 then
          rv32_addi(reg_sp, reg_sp, nArgs * 4);

        EmitCallProc(pi);
      end;

    IR_WRITE, IR_WRITELN:
      begin
        { Bare-metal: write/writeln does nothing. }
      end;

    IR_NEG:
      begin
        IREmitNodeRISCV32(IRA[node]);
        rv32_sub(reg_a0, reg_zero, reg_a0);
      end;

    IR_NOT:
      begin
        IREmitNodeRISCV32(IRA[node]);
        rv32_xori(reg_a0, reg_a0, 1);
      end;

    else
      Error('target riscv32: unsupported node in IR codegen');
  end;
end;

procedure IREmitMachineCodeRISCV32;
var i, lblId, pos, targetOffset, f: Integer;
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
            rv32_jal(reg_zero, LabelPositions[lblId] - CodeLen)
          else
          begin
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            rv32_jal(reg_zero, 0);
          end;
        end;

      IR_JUMP_IF_FALSE:
        begin
          lblId := IRA[i];
          IREmitNodeRISCV32(IRB[i]);
          if LabelPositions[lblId] <> -1 then
            rv32_beq(reg_a0, reg_zero, LabelPositions[lblId] - CodeLen)
          else
          begin
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            rv32_beq(reg_a0, reg_zero, 0);
          end;
        end;

      IR_CALL:
        begin
          if IRIVal[i] = 1 then
            IREmitNodeRISCV32(i);
        end;

      IR_STORE_SYM, IR_WRITE, IR_WRITELN:
        IREmitNodeRISCV32(i);

      IR_NOP, IR_CONST_STR, IR_CONST_INT, IR_BLOCK,
      IR_LOAD_SYM, IR_BINOP, IR_NEG, IR_NOT, IR_ARG, IR_LEA, IR_SYSCALL,
      IR_SLOTADDR, IR_FIELD, IR_INDEX: ;

      else
        IREmitNodeRISCV32(i);
    end;
  end;

  for f := 0 to LabelFixupCount - 1 do
  begin
    lblId := LabelFixupTarget[f];
    pos := LabelFixupPos[f];
    targetOffset := LabelPositions[lblId];
    if targetOffset = -1 then Error('Unresolved forward jump in RISC-V IR codegen');

    { Read the instruction word to check opcode }
    { RISC-V jal has opcode 0x6F, beq has opcode 0x63 }
    if (Code[pos] = $6F) then
      Patch32(pos, EncodeRISCVJAL(reg_zero, targetOffset - pos))
    else if (Code[pos] = $63) then
      Patch32(pos, EncodeRISCVBEQ(reg_a0, reg_zero, targetOffset - pos))
    else
      Error('target riscv32: invalid instruction at label fixup');
  end;
end;
