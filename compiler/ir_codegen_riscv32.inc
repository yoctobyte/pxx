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

procedure EmitStrOperandRISCV32(operandTk: TTypeKind; slotOff, lenReg, srcReg: Integer);
{ Decompose a string-valued operand sitting at [sp+slotOff] into (len -> lenReg,
  src -> srcReg) for PXXStrConcat / PXXStrEq. A handle gives len [h-8] (nil->0)
  + src h; a frozen tyString gives len [buf] + src buf+8; a char gives len 1 +
  src &slot. lenReg/srcReg must differ from each other and from sp. }
begin
  rv32_lw(srcReg, reg_sp, slotOff);          { operand value }
  if operandTk = tyAnsiString then
  begin
    rv32_addi(lenReg, reg_zero, 0);
    rv32_beq(srcReg, reg_zero, 8);           { nil -> len 0 }
    rv32_lw(lenReg, srcReg, -8);
  end
  else if operandTk = tyString then
  begin
    rv32_lw(lenReg, srcReg, 0);              { len = [buf] }
    rv32_addi(srcReg, srcReg, 8);            { src = buf+8 }
  end
  else
  begin
    rv32_addi(srcReg, reg_sp, slotOff);      { src = &slot (char) }
    rv32_addi(lenReg, reg_zero, 1);
  end;
end;

procedure EmitSlotAddrRISCV32(rd, si: Integer);
{ rd = address of the variable's storage slot (global abs / frame-relative). }
begin
  if Syms[si].Kind = skGlobal then
    EmitLoadGlobAddrRISCV32(rd, Syms[si].Offset)
  else
  begin
    EmitLoadImmRISCV32(rd, Syms[si].Offset);
    rv32_add(rd, reg_s0, rd);
  end;
end;

procedure EmitHeapAllocLockedRISCV32;
{ a0 = requested payload bytes -> a0 = payload pointer. PXXAlloc(size, align=8). }
var pi: Integer;
begin
  pi := FindProc('PXXAlloc');
  if pi < 0 then Error('compiler error: Alloc helper not found in builtin unit');
  rv32_addi(reg_a1, reg_zero, 8);   { a1 = align (a0 = size already) }
  EmitCallProc(pi);                 { result in a0 }
end;

procedure EmitHeapFreeLockedRISCV32;
{ a0 = payload pointer -> PXXFree(p). nil ignored inside. }
var pi: Integer;
begin
  pi := FindProc('PXXFree');
  if pi < 0 then Error('compiler error: Free helper not found in builtin unit');
  EmitCallProc(pi);
end;

procedure IREmitNodeRISCV32(node: Integer);
var
  left, right, op, si, pi, nArgs, i, lo, elemSize, sz, argNode, valNode, j: Integer;
  tk: TTypeKind;
  sgn, savedLVW: Boolean;
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
        si := IRA[node];
        if Syms[si].TypeKind = tyAnsiString then
        begin
          { Managed-string assignment: build the new handle in a0, then publish
            into the slot (DecRef old). Mirrors i386. }
          valNode := IRB[node];
          if IRKind[valNode] = IR_CONST_STR then
          begin
            sVal := GetTokenStrFromRaw(IRA[valNode], IRB[valNode]);
            j := InternStr(sVal);
            EmitLoadImmRISCV32(reg_a0, Strs[j].Len);          { arg0 = len }
            EmitLoadDataRefRISCV32(reg_a1, Strs[j].Offset + 8); { arg1 = chars }
            pi := FindProc('PXXStrFromLit'); if pi < 0 then Error('compiler error: PXXStrFromLit not found');
            EmitCallProc(pi);                                 { a0 = handle }
          end
          else if IntToTypeKind(IRTk[valNode]) = tyChar then
          begin
            IREmitNodeRISCV32(valNode);                       { a0 = char code }
            rv32_addi(reg_sp, reg_sp, -8); rv32_sw(reg_a0, reg_sp, 0); { [sp] = char }
            rv32_addi(reg_a1, reg_sp, 0);                     { arg1 = &char }
            rv32_addi(reg_a0, reg_zero, 1);                   { arg0 = len 1 }
            pi := FindProc('PXXStrFromLit'); EmitCallProc(pi);
            rv32_addi(reg_sp, reg_sp, 8);
          end
          else if IntToTypeKind(IRTk[valNode]) = tyString then
          begin
            IREmitNodeRISCV32(valNode);                       { a0 = inline buffer addr }
            rv32_lw(reg_a2, reg_a0, 0);                       { len = [buf] }
            rv32_addi(reg_a1, reg_a0, 8);                     { arg1 = buf+8 }
            rv32_addi(reg_a0, reg_a2, 0);                     { arg0 = len }
            pi := FindProc('PXXStrFromLit'); EmitCallProc(pi);
          end
          else
          begin
            IREmitNodeRISCV32(valNode);                       { a0 = source handle }
            { A fresh result (concat / user-call) already carries its +1; a plain
              copy of another handle must IncRef. }
            if not (((IRKind[valNode] = IR_BINOP) and (IntToTypeKind(IRTk[valNode]) = tyAnsiString)) or
                    ((IRKind[valNode] = IR_CALL) and (IRA[valNode] >= 0))) then
            begin
              rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0); { save handle }
              pi := FindProc('PXXStrIncRef'); EmitCallProc(pi);          { a0 = p }
              rv32_lw(reg_a0, reg_sp, 0); rv32_addi(reg_sp, reg_sp, 4);  { restore handle }
            end;
          end;
          { Publish: store new, DecRef old. }
          if (Syms[si].Kind = skParam) and Syms[si].IsRef then
          begin
            rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);   { push new }
            rv32_lw(reg_t0, reg_s0, Syms[si].Offset);                    { t0 = caller slot addr }
            rv32_lw(reg_a1, reg_t0, 0);                                  { a1 = old }
            rv32_lw(reg_a0, reg_sp, 0);                                  { a0 = new }
            rv32_sw(reg_a0, reg_t0, 0);                                  { [slot] := new }
            rv32_addi(reg_a0, reg_a1, 0);                                { a0 = old }
            pi := FindProc('PXXStrDecRef'); EmitCallProc(pi);
            rv32_addi(reg_sp, reg_sp, 4);
          end
          else
          begin
            rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);   { push new }
            EmitLoadVarRISCV32(si);                                      { a0 = old handle }
            pi := FindProc('PXXStrDecRef'); EmitCallProc(pi);
            rv32_lw(reg_a0, reg_sp, 0); rv32_addi(reg_sp, reg_sp, 4);    { pop new }
            EmitStoreVarRISCV32(si);                                     { slot := new }
          end;
          Exit;
        end;
        IREmitNodeRISCV32(IRB[node]);
        EmitStoreVarRISCV32(IRA[node]);
      end;

    IR_LEA:
      begin
        si := IRA[node];
        EmitSlotAddrRISCV32(reg_a0, si);
        { Slot holds a heap data pointer (handle) loaded in read/index position:
          a local dynamic array, or an open-array value param (caller passed the
          handle). SetLength keeps the slot address by computing it directly.
          (No COW / by-ref open arrays yet.) }
        if (Syms[si].IsArray and (Syms[si].ArrLen = -1)) or
           ((Syms[si].Kind = skParam) and Syms[si].IsArray and not Syms[si].IsRef) then
          rv32_lw(reg_a0, reg_a0, 0)
        { Scalar managed string: read position needs the heap handle; write
          position keeps the slot address so the store can publish a new handle.
          A by-ref param's slot already holds the forwarded caller slot addr. }
        else if (Syms[si].TypeKind = tyAnsiString) and not Syms[si].IsArray and
                not InLValueWrite and
                not ((Syms[si].Kind = skParam) and Syms[si].IsRef) then
          rv32_lw(reg_a0, reg_a0, 0);
      end;

    IR_SLOTADDR:
      EmitSlotAddrRISCV32(reg_a0, IRA[node]);   { always the slot address }

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

        IREmitNodeRISCV32(left);              { base: handle (read) / slot addr (write) }
        { Managed-string index: read position already has the handle (IR_LEA
          loaded it); write position holds the slot address -> clone-if-shared
          via PXXStrUnique to get a writable handle (COW). }
        if (IRKind[left] = IR_LEA) and (Syms[IRA[left]].TypeKind = tyAnsiString) and
           not Syms[IRA[left]].IsArray and InLValueWrite then
        begin
          pi := FindProc('PXXStrUnique');
          if pi < 0 then Error('compiler error: PXXStrUnique not found');
          EmitCallProc(pi);                   { a0 = unique handle }
        end;
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

        savedLVW := InLValueWrite;
        InLValueWrite := True;
        IREmitNodeRISCV32(IRA[node]);
        InLValueWrite := savedLVW;
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

        if (IntToTypeKind(IRTk[node]) = tyAnsiString) and (op = Ord(tkPlus)) then
        begin
          { Managed-string concat -> PXXStrConcat(lenA, srcA, srcB, lenB). Each
            operand is a handle (len [h-8], 0 if nil), a frozen tyString (len
            [buf], src buf+8), or a char (len 1, src &slot). Operands pushed:
            [sp]=rhs, [sp+4]=lhs. }
          IREmitNodeRISCV32(left);  rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);
          IREmitNodeRISCV32(right); rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);
          EmitStrOperandRISCV32(IntToTypeKind(IRTk[right]), 0, reg_t1, reg_t2);  { lenB, srcB }
          EmitStrOperandRISCV32(IntToTypeKind(IRTk[left]),  4, reg_a0, reg_a1);  { lenA, srcA }
          rv32_addi(reg_a2, reg_t2, 0);    { a2 = srcB }
          rv32_addi(reg_a3, reg_t1, 0);    { a3 = lenB }
          pi := FindProc('PXXStrConcat');
          if pi < 0 then Error('compiler error: PXXStrConcat not found');
          EmitCallProc(pi);                { a0 = result handle }
          { release fresh tyAnsiString BINOP operands (nested concat temporaries) }
          rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);  { push result; [sp+4]=rhs,[sp+8]=lhs }
          if (IRKind[left] = IR_BINOP) and (IntToTypeKind(IRTk[left]) = tyAnsiString) then
          begin
            rv32_lw(reg_a0, reg_sp, 8);
            pi := FindProc('PXXStrDecRef'); EmitCallProc(pi);
          end;
          if (IRKind[right] = IR_BINOP) and (IntToTypeKind(IRTk[right]) = tyAnsiString) then
          begin
            rv32_lw(reg_a0, reg_sp, 4);
            pi := FindProc('PXXStrDecRef'); EmitCallProc(pi);
          end;
          rv32_lw(reg_a0, reg_sp, 0); rv32_addi(reg_sp, reg_sp, 4);   { pop result }
          rv32_addi(reg_sp, reg_sp, 8);                               { drop rhs, lhs }
          Exit;
        end;

        if ((op = Ord(tkEq)) or (op = Ord(tkNeq))) and
           ((IntToTypeKind(IRTk[left]) = tyAnsiString) or (IntToTypeKind(IRTk[right]) = tyAnsiString)) then
        begin
          { Managed-string equality -> PXXStrEq(lenA, srcA, lenB, srcB) -> 1/0. }
          IREmitNodeRISCV32(left);  rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);
          IREmitNodeRISCV32(right); rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);
          EmitStrOperandRISCV32(IntToTypeKind(IRTk[right]), 0, reg_t1, reg_t2);  { lenB, srcB }
          EmitStrOperandRISCV32(IntToTypeKind(IRTk[left]),  4, reg_a0, reg_a1);  { lenA, srcA }
          rv32_addi(reg_a2, reg_t1, 0);    { a2 = lenB }
          rv32_addi(reg_a3, reg_t2, 0);    { a3 = srcB }
          pi := FindProc('PXXStrEq');
          if pi < 0 then Error('compiler error: PXXStrEq not found');
          EmitCallProc(pi);                { a0 = 1/0 }
          { release fresh operand temporaries }
          rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);  { push result }
          if (IRKind[left] = IR_BINOP) and (IntToTypeKind(IRTk[left]) = tyAnsiString) then
          begin
            rv32_lw(reg_a0, reg_sp, 8);
            pi := FindProc('PXXStrDecRef'); EmitCallProc(pi);
          end;
          if (IRKind[right] = IR_BINOP) and (IntToTypeKind(IRTk[right]) = tyAnsiString) then
          begin
            rv32_lw(reg_a0, reg_sp, 4);
            pi := FindProc('PXXStrDecRef'); EmitCallProc(pi);
          end;
          rv32_lw(reg_a0, reg_sp, 0); rv32_addi(reg_sp, reg_sp, 4);   { pop result }
          rv32_addi(reg_sp, reg_sp, 8);                               { drop rhs, lhs }
          if op = Ord(tkNeq) then rv32_xori(reg_a0, reg_a0, 1);
          Exit;
        end;

        if (op = Ord(tkPlus)) and (IntToTypeKind(IRTk[node]) = tyString) then
          Error('target riscv32: frozen tyString concat unsupported; only literal+literal folds (combine nested string literals)');

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
        if pi = -Ord(tkGetMem) then
        begin
          { GetMem / New. Class instantiation (VMT + ctor) is a later step. }
          if IRC[node] >= REC_UCLASS_BASE then
            Error('target riscv32: class instantiation not yet supported');
          argNode := IRB[node];               { size arg }
          IREmitNodeRISCV32(IRA[argNode]);    { size -> a0 }
          EmitHeapAllocLockedRISCV32;         { a0 = payload pointer }
          Exit;
        end;
        if pi = -Ord(tkFreeMem) then
        begin
          argNode := IRB[node];               { pointer arg }
          IREmitNodeRISCV32(IRA[argNode]);    { p -> a0 }
          EmitHeapFreeLockedRISCV32;
          Exit;
        end;
        if pi = -102 then
        begin
          { SetLength(arr, n) -> PXXDynSetLen(slotAddr, n, desc). SetLength on a
            managed AnsiString -> PXXStrSetLen(slotAddr, n). }
          argNode := IRB[node];               { arg1 = array/string lvalue }
          valNode := IRB[argNode];            { arg2 = new length }
          left := IRA[argNode];
          if (IRKind[left] = IR_LOAD_SYM) and
             (Syms[IRA[left]].TypeKind = tyAnsiString) then
          begin
            si := IRA[left];
            if (Syms[si].Kind = skParam) and Syms[si].IsRef then
            begin
              EmitLoadImmRISCV32(reg_a0, Syms[si].Offset);
              rv32_add(reg_a0, reg_s0, reg_a0);
              rv32_lw(reg_a0, reg_a0, 0);      { a0 = caller slot addr }
            end
            else
              EmitSlotAddrRISCV32(reg_a0, si); { a0 = slot address }
            rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);  { push slot }
            IREmitNodeRISCV32(IRA[valNode]);   { a0 = n }
            rv32_addi(reg_a1, reg_a0, 0);      { a1 = n }
            rv32_lw(reg_a0, reg_sp, 0); rv32_addi(reg_sp, reg_sp, 4);   { pop slot -> a0 }
            pi := FindProc('PXXStrSetLen');
            if pi < 0 then Error('compiler error: PXXStrSetLen not found');
            EmitCallProc(pi);
            Exit;
          end;
          if IRKind[left] <> IR_LEA then
            Error('target riscv32: SetLength expects an array variable');
          si := IRA[left];
          if not (Syms[si].IsArray and (Syms[si].ArrLen = -1)) then
            Error('target riscv32: SetLength only supports dynamic arrays yet');
          if (Syms[si].Kind = skParam) and Syms[si].IsRef then
            Error('target riscv32: SetLength on a var-array parameter not yet supported');
          EmitSlotAddrRISCV32(reg_a0, si);    { a0 = slot address (not the handle) }
          rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);  { push slot }
          IREmitNodeRISCV32(IRA[valNode]);    { a0 = n }
          rv32_addi(reg_a1, reg_a0, 0);       { a1 = n }
          rv32_lw(reg_a0, reg_sp, 0); rv32_addi(reg_sp, reg_sp, 4);   { pop slot -> a0 }
          EmitLoadDataRefRISCV32(reg_a2, GetOrAllocSymRTTI(si));      { a2 = desc }
          pi := FindProc('PXXDynSetLen');
          if pi < 0 then Error('compiler error: PXXDynSetLen not found');
          EmitCallProc(pi);
          Exit;
        end;
        if pi = -Ord(tkLength) then
        begin
          { Length(arr): a0 = handle; count at [handle-8], nil handle -> 0. }
          argNode := IRB[node];
          IREmitNodeRISCV32(IRA[argNode]);    { a0 = handle (or 0) }
          rv32_beq(reg_a0, reg_zero, 8);      { if nil, skip the load (result 0) }
          rv32_lw(reg_a0, reg_a0, -8);
          Exit;
        end;
        if pi < 0 then
        begin
          { Type-pun passthroughs: Ord/Chr/Integer()/LongWord() are identity on
            the value already in a0 (char/int share the register model). }
          if (pi = -Ord(tkOrd)) or (pi = -Ord(tkChr)) or
             (pi = -Ord(tkInteger_T)) or (pi = -Ord(tkLongWord_T)) or
             (pi = -Ord(tkChar_T)) or (pi = -Ord(tkBoolean_T)) then
          begin
            argNode := IRB[node];
            IREmitNodeRISCV32(IRA[argNode]);
            Exit;
          end;
          Error('target riscv32: standard builtin calls not supported in bare-metal stage 1');
        end;

        argNode := IRB[node];
        nArgs := 0;
        while argNode <> -1 do
        begin
          IREmitNodeRISCV32(IRA[argNode]);
          { External C call: a Pascal string literal is stored as an 8-byte
            length prefix + NUL-terminated chars; pass the char data so the
            callee sees a const char* (same auto-marshal as x86-64). }
          if ProcExternal[pi] and (IntToTypeKind(IRTk[argNode]) = tyString) then
            rv32_addi(reg_a0, reg_a0, 8);
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

    IR_TERMINATE:
      begin
        if IRIVal[node] = AN_HALT then
          EmitExit(0)                            { bare-metal: park in a self-loop }
        else if CurProc >= 0 then
          EmitProcEpilog(Procs[CurProc].RetSymIdx) { early Exit via epilogue }
        else
          EmitExit(0);
      end;

    IR_DEFAULT_MEM:
      begin
        { Zero IRIVal bytes at dest. ESP has no managed records yet, so skip the
          PXXRecordRelease path the hosted targets take for managed fields. }
        IREmitNodeRISCV32(IRA[node]);            { a0 = dest }
        EmitLoadImmRISCV32(reg_a1, Integer(IRIVal[node]));  { a1 = byte count }
        pi := FindProc('PXXMemZero');
        if pi < 0 then Error('compiler error: PXXMemZero not found');
        EmitCallProc(pi);
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
            EmitAsmRv32(['jal zero, %', LabelPositions[lblId] - CodeLen])
          else
          begin
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitAsmRv32('jal zero, 0');
          end;
        end;

      IR_JUMP_IF_FALSE:
        begin
          lblId := IRA[i];
          IREmitNodeRISCV32(IRB[i]);
          if LabelPositions[lblId] <> -1 then
            EmitAsmRv32(['beq a0, zero, %', LabelPositions[lblId] - CodeLen])
          else
          begin
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitAsmRv32('beq a0, zero, 0');
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
