{ ===== IR -> AArch64 machine code (cross target, minimal and growing) =====

  AArch64 (ARM64) target backend. Operates on fixed-width 32-bit instructions.
  Registers used: x0 for expression results, x1..x7 for arguments/temporaries. }

procedure IREmitNodeAarch64(node: Integer); forward;

procedure EmitLoadDataRefA64(rd, dataOff: Integer);
{ Load a data address (or descriptor sentinel) into x[rd]. EmitDataRef emits an
  8-byte slot on this 64-bit target, so use the 64-bit literal load and branch
  past the full 8 bytes (mirrors EmitwriteSyscallA64). }
begin
  EmitI32($58000040 or rd);  { ldr x[rd], [pc+8] }
  EmitI32($14000003);        { b [pc+12] (skip 8-byte literal) }
  EmitDataRef(dataOff);
end;

procedure EmitHeapAllocLockedA64;
{ x0 = requested payload bytes. Returns payload pointer in x0. Delegates to the
  Pascal PXXAlloc(size, align=8). Threadsafe locking is x86-64-only. }
var pi: Integer;
begin
  EmitLoadImmA64(1, 8);              { mov x1, #8 (align) }
  pi := FindProc('PXXAlloc');
  if pi < 0 then Error('compiler error: Alloc helper not found in builtin unit');
  EmitCallProc(pi);                 { x0 = pointer }
end;

procedure EmitHeapFreeLockedA64;
{ x0 = payload pointer. Delegates to PXXFree(p). nil ignored inside. }
var pi: Integer;
begin
  pi := FindProc('PXXFree');
  if pi < 0 then Error('compiler error: Free helper not found in builtin unit');
  EmitCallProc(pi);
end;

procedure EmitStrIncRefA64;
{ x0 = managed-string handle. Retain; x0 preserved. }
var pi: Integer;
begin
  EmitI32($F81F0FE0);             { str x0, [sp, #-16]! (save handle; x0 still arg) }
  pi := FindProc('PXXStrIncRef');
  if pi < 0 then Error('compiler error: PXXStrIncRef not found');
  EmitCallProc(pi);
  EmitI32($F84107E0);             { ldr x0, [sp], #16 (restore handle) }
end;

procedure EmitStrDecRefA64;
{ x0 = managed-string handle. x0 clobbered. }
var pi: Integer;
begin
  pi := FindProc('PXXStrDecRef');
  if pi < 0 then Error('compiler error: PXXStrDecRef not found');
  EmitCallProc(pi);
end;

procedure EmitAnsiStringFromNodeA64(valNode: Integer);
{ Build a managed AnsiString handle in x0 from a literal, char, inline string,
  or existing handle (retained unless a fresh concat/function result). }
var sVal: AnsiString; si, pi: Integer; tk: TTypeKind;
begin
  if IRKind[valNode] = IR_CONST_STR then
  begin
    sVal := GetTokenStrFromRaw(IRA[valNode], IRB[valNode]);
    si := InternStr(sVal);
    EmitLoadImmA64(0, Strs[si].Len);
    EmitLoadDataRefA64(1, Strs[si].Offset + 8);
    pi := FindProc('PXXStrFromLit');
    if pi < 0 then Error('compiler error: PXXStrFromLit not found');
    EmitCallProc(pi);
    Exit;
  end;
  tk := IntToTypeKind(IRTk[valNode]);
  if tk = tyChar then
  begin
    IREmitNodeAarch64(valNode);   { x0 = char code }
    EmitI32($F81F0FE0);           { str x0, [sp, #-16]! (byte at [sp]) }
    EmitLoadImmA64(0, 1);         { x0 = 1 }
    EmitI32($910003E1);           { add x1, sp, #0 }
    pi := FindProc('PXXStrFromLit');
    if pi < 0 then Error('compiler error: PXXStrFromLit not found');
    EmitCallProc(pi);
    EmitI32($910043FF);           { add sp, sp, #16 }
  end
  else if tk = tyString then
  begin
    IREmitNodeAarch64(valNode);   { x0 = inline string buffer }
    EmitI32($AA0003E2);           { mov x2, x0 }
    EmitI32($F9400040);           { ldr x0, [x2] (len) }
    EmitI32($91002041);           { add x1, x2, #8 (src) }
    pi := FindProc('PXXStrFromLit');
    if pi < 0 then Error('compiler error: PXXStrFromLit not found');
    EmitCallProc(pi);
  end
  else
  begin
    IREmitNodeAarch64(valNode);   { x0 = handle }
    if not (((IRKind[valNode] = IR_BINOP) and
             (IntToTypeKind(IRTk[valNode]) = tyAnsiString)) or
            ((IRKind[valNode] = IR_CALL) and (IRA[valNode] >= 0))) then
      EmitStrIncRefA64;
  end;
end;

{ Decompose an evaluated string operand value (in x[valueReg]) into
  (src in x[srcReg], len in x[lenReg]). tk selects managed-handle / inline /
  char. For char, charStackOff is the byte offset from sp. }
procedure EmitA64StringParts(valueReg, srcReg, lenReg: Integer; tk: TTypeKind;
                             charStackOff: Integer);
begin
  if tk = tyAnsiString then
  begin
    EmitI32($AA0003E0 or (valueReg shl 16) or srcReg); { mov src, value }
    EmitLoadImmA64(lenReg, 0);
    EmitI32($B4000040 or (valueReg) or (2 shl 5));     { cbz value, +8 }
    { ldur len, [value, #-8] }
    EmitI32($F85F8000 or (valueReg shl 5) or lenReg);
  end
  else if tk = tyString then
  begin
    EmitI32($F9400000 or (valueReg shl 5) or lenReg);  { ldr len, [value] }
    EmitI32($91002000 or (valueReg shl 5) or srcReg);  { add src, value, #8 }
  end
  else
  begin
    EmitLoadImmA64(lenReg, 1);
    EmitI32($910003E0 or (charStackOff shl 10) or srcReg); { add src, sp, #off }
  end;
end;

procedure EmitA64CopyBytes(countReg, srcReg, dstReg: Integer);
{ Copy x[countReg] bytes from x[srcReg] to x[dstReg]. Uses w8 as scratch. }
var donePos, loopStart: Integer;
begin
  donePos := CodeLen;
  EmitI32($B4000000 or countReg);                 { cbz count, done (patched) }
  loopStart := CodeLen;
  EmitI32($39400008 or (srcReg shl 5));            { ldrb w8, [src] }
  EmitI32($39000008 or (dstReg shl 5));            { strb w8, [dst] }
  EmitI32($91000400 or (srcReg shl 5) or srcReg);  { add src, src, #1 }
  EmitI32($91000400 or (dstReg shl 5) or dstReg);  { add dst, dst, #1 }
  EmitI32($F1000400 or (countReg shl 5) or countReg); { subs count, count, #1 }
  EmitI32($54000001 or ((((loopStart - CodeLen) div 4) and $7FFFF) shl 5)); { b.ne loop }
  Patch32(donePos, $B4000000 or countReg or ((((CodeLen - donePos) div 4) and $7FFFF) shl 5));
end;

procedure EmitLoadVarA64(idx: Integer);
var tk: TTypeKind; sz: Integer; sgn: Boolean;
begin
  tk := Syms[idx].TypeKind;
  sz := TypeSize(tk);
  sgn := TypeSigned(tk);

  if Syms[idx].Kind = skGlobal then
  begin
    EmitI32($18000041);  { ldr w1, [pc+8] }
    EmitI32($14000002);  { b [pc+8] }
    EmitGlobRef(Syms[idx].Offset);
    if sz = 1 then
    begin
      if sgn then EmitI32($39C00020) else EmitI32($39400020);
    end
    else if sz = 2 then
    begin
      if sgn then EmitI32($79C00020) else EmitI32($79400020);
    end
    else if sz = 4 then
      EmitI32($B9400020)
    else
      EmitI32($F9400020);
  end
  else
  begin
    EmitLoadImmA64(9, Syms[idx].Offset);
    EmitI32($8B0903A9);  { add x9, x29, x9 }
    if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then
    begin
      EmitI32($F9400121);  { ldr x1, [x9] }
      if sz = 1 then
      begin
        if sgn then EmitI32($39C00020) else EmitI32($39400020);
      end
      else if sz = 2 then
      begin
        if sgn then EmitI32($79C00020) else EmitI32($79400020);
      end
      else if sz = 4 then
        EmitI32($B9400020)
      else
        EmitI32($F9400020);
    end
    else
    begin
      if sz = 1 then
      begin
        if sgn then EmitI32($39C00120) else EmitI32($39400120);
      end
      else if sz = 2 then
      begin
        if sgn then EmitI32($79C00120) else EmitI32($79400120);
      end
      else if sz = 4 then
        EmitI32($B9400120)
      else
        EmitI32($F9400120);
    end;
  end;
end;

procedure EmitStoreVarA64(idx: Integer);
var tk: TTypeKind; sz: Integer;
begin
  tk := Syms[idx].TypeKind;
  sz := TypeSize(tk);

  if Syms[idx].Kind = skGlobal then
  begin
    EmitI32($18000041);  { ldr w1, [pc+8] }
    EmitI32($14000002);  { b [pc+8] }
    EmitGlobRef(Syms[idx].Offset);
    if sz = 1 then
      EmitI32($39000020)  { strb w0, [x1] }
    else if sz = 2 then
      EmitI32($79000020)  { strh w0, [x1] }
    else if sz = 4 then
      EmitI32($B9000020)  { str w0, [x1] }
    else
      EmitI32($F9000020); { str x0, [x1] }
  end
  else
  begin
    EmitLoadImmA64(9, Syms[idx].Offset);
    EmitI32($8B0903A9);  { add x9, x29, x9 }
    if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then
    begin
      EmitI32($F9400121);  { ldr x1, [x9] }
      if sz = 1 then
        EmitI32($39000020)  { strb w0, [x1] }
      else if sz = 2 then
        EmitI32($79000020)  { strh w0, [x1] }
      else if sz = 4 then
        EmitI32($B9000020)  { str w0, [x1] }
      else
        EmitI32($F9000020); { str x0, [x1] }
    end
    else
    begin
      if sz = 1 then
        EmitI32($39000120)  { strb w0, [x9] }
      else if sz = 2 then
        EmitI32($79000120)  { strh w0, [x9] }
      else if sz = 4 then
        EmitI32($B9000120)  { str w0, [x9] }
      else
        EmitI32($F9000120); { str x0, [x9] }
    end;
  end;
end;

procedure EmitLoadVarAddrA64(idx: Integer);
begin
  if Syms[idx].Kind = skGlobal then
  begin
    EmitI32($18000040);  { ldr w0, [pc+8] }
    EmitI32($14000002);  { b [pc+8] }
    EmitGlobRef(Syms[idx].Offset);
  end
  else if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then
  begin
    EmitLoadImmA64(9, Syms[idx].Offset);
    EmitI32($8B0903A9);  { add x9, x29, x9 }
    EmitI32($F9400120);  { ldr x0, [x9] }
  end
  else
  begin
    EmitLoadImmA64(0, Syms[idx].Offset);
    EmitI32($8B0003A0);  { add x0, x29, x0 }
  end;
end;

procedure EmitSetccA64(opTk: Integer);
begin
  if opTk = Ord(tkEq) then EmitI32($9A9F17E0)
  else if opTk = Ord(tkNeq) then EmitI32($9A9F07E0)
  else if opTk = Ord(tkLt) then EmitI32($9A9FA7E0)
  else if opTk = Ord(tkLe) then EmitI32($9A9FC7E0)
  else if opTk = Ord(tkGt) then EmitI32($9A9FD7E0)
  else if opTk = Ord(tkGe) then EmitI32($9A9FB7E0)
  else Error('target aarch64: unsupported compare operator');
end;

procedure IREmitNodeAarch64(node: Integer);
var
  valNode, si, left, right, op, pi, argNode, nArgs, i, sz, wid: Integer;
  classIdx, elemSize, lo: Integer;
  sVal: AnsiString;
  tk, lhsTk, rhsTk: TTypeKind;
  sgn: Boolean;
begin
  if node = -1 then Exit;
  case IRKind[node] of
    IR_NOP, IR_BLOCK: ;

    IR_CONST_INT:
      EmitLoadImmA64(0, IRIVal[node]);

    IR_LOAD_SYM:
      EmitLoadVarA64(IRA[node]);

    IR_STORE_SYM:
      begin
        si := IRA[node];
        if Syms[si].TypeKind = tyAnsiString then
        begin
          valNode := IRB[node];
          EmitAnsiStringFromNodeA64(valNode);   { x0 = new handle (retained) }
          if (Syms[si].Kind = skParam) and Syms[si].IsRef then
          begin
            EmitI32($F81F0FE0);                 { str x0, [sp, #-16]! (new) }
            EmitLoadImmA64(9, Syms[si].Offset);
            EmitI32($8B0903A9);                 { add x9, x29, x9 }
            EmitI32($F9400121);                 { ldr x1, [x9] caller slot addr }
            EmitI32($F9400020);                 { ldr x0, [x1] old }
            EmitI32($F94003E2);                 { ldr x2, [sp] new }
            EmitI32($F9000022);                 { str x2, [x1] }
            EmitStrDecRefA64;                   { release old (x0) }
            EmitI32($910043FF);                 { add sp, sp, #16 }
          end
          else
          begin
            EmitI32($F81F0FE0);                 { str x0, [sp, #-16]! (new) }
            EmitLoadVarA64(si);                 { x0 = old }
            EmitStrDecRefA64;                   { release old }
            EmitI32($F84107E0);                 { ldr x0, [sp], #16 (new) }
            EmitStoreVarA64(si);                { store new }
          end;
          Exit;
        end;
        IREmitNodeAarch64(IRB[node]);
        EmitStoreVarA64(IRA[node]);
      end;

    IR_LEA:
      begin
        si := IRA[node];
        if Syms[si].IsArray and (Syms[si].ArrLen = -1) then
        begin
          { Dynamic array: slot holds the heap data pointer; load it (v1: no COW). }
          EmitLoadVarAddrA64(si);               { x0 = slot address }
          EmitI32($F9400000);                   { ldr x0, [x0] = handle }
        end
        else
          EmitLoadVarAddrA64(si);
      end;

    IR_SLOTADDR:
      EmitLoadVarAddrA64(IRA[node]);            { always the slot address }

    IR_BINOP:
      begin
        left := IRA[node];
        right := IRB[node];
        op := IRC[node];
        tk := IntToTypeKind(IRTk[node]);

        if (tk = tyAnsiString) and (op = Ord(tkPlus)) then
        begin
          { a + b -> PXXStrConcat(lenA, srcA, srcB, lenB). Operands pushed as
            16-byte slots. }
          lhsTk := IntToTypeKind(IRTk[left]);
          rhsTk := IntToTypeKind(IRTk[right]);
          IREmitNodeAarch64(left);  EmitI32($F81F0FE0); { push lhs }
          IREmitNodeAarch64(right); EmitI32($F81F0FE0); { push rhs; [sp]=rhs,[sp+16]=lhs }
          EmitI32($F94003E0);                           { ldr x0, [sp] (rhs) }
          EmitA64StringParts(0, 1, 2, rhsTk, 0);        { x1=srcB, x2=lenB }
          EmitI32($F81F0FE1);                           { str x1, [sp,#-16]! (srcB) }
          EmitI32($F81F0FE2);                           { str x2, [sp,#-16]! (lenB) }
          { [sp]=lenB,[sp+16]=srcB,[sp+32]=rhs,[sp+48]=lhs }
          EmitI32($F9401BE0);                           { ldr x0, [sp,#48] (lhs) }
          EmitA64StringParts(0, 1, 2, lhsTk, 48);       { x1=srcA, x2=lenA }
          EmitI32($AA0203E0);                           { mov x0, x2 (lenA) }
          EmitI32($F9400BE2);                           { ldr x2, [sp,#16] (srcB) }
          EmitI32($F94003E3);                           { ldr x3, [sp] (lenB) }
          EmitI32($910083FF);                           { add sp, sp, #32 (drop temps) }
          pi := FindProc('PXXStrConcat');
          if pi < 0 then Error('compiler error: PXXStrConcat not found');
          EmitCallProc(pi);                             { x0 = result }
          EmitI32($F81F0FE0);                           { push result; [sp]=res,[sp+16]=rhs,[sp+32]=lhs }
          if (IRKind[left] = IR_BINOP) and (IntToTypeKind(IRTk[left]) = tyAnsiString) then
          begin
            EmitI32($F94013E0);                         { ldr x0, [sp,#32] (lhs) }
            EmitStrDecRefA64;
          end;
          if (IRKind[right] = IR_BINOP) and (IntToTypeKind(IRTk[right]) = tyAnsiString) then
          begin
            EmitI32($F9400BE0);                         { ldr x0, [sp,#16] (rhs) }
            EmitStrDecRefA64;
          end;
          EmitI32($F84107E0);                           { ldr x0, [sp], #16 (result) }
          EmitI32($910083FF);                           { add sp, sp, #32 (drop rhs,lhs) }
          Exit;
        end;

        if ((op = Ord(tkEq)) or (op = Ord(tkNeq))) and
           ((IntToTypeKind(IRTk[left]) in [tyAnsiString, tyString, tyChar]) and
            (IntToTypeKind(IRTk[right]) in [tyAnsiString, tyString, tyChar])) and
           ((IntToTypeKind(IRTk[left]) = tyAnsiString) or
            (IntToTypeKind(IRTk[right]) = tyAnsiString)) then
        begin
          { String/char equality via PXXStrEq(lenA, srcA, lenB, srcB). At least
            one operand is a managed handle. }
          lhsTk := IntToTypeKind(IRTk[left]);
          rhsTk := IntToTypeKind(IRTk[right]);
          IREmitNodeAarch64(left);  EmitI32($F81F0FE0); { push lhs }
          IREmitNodeAarch64(right); EmitI32($F81F0FE0); { push rhs }
          EmitI32($F94003E0);                           { ldr x0, [sp] (rhs) }
          EmitA64StringParts(0, 1, 2, rhsTk, 0);        { x1=srcB, x2=lenB }
          EmitI32($F81F0FE1);                           { str x1, [sp,#-16]! (srcB) }
          EmitI32($F81F0FE2);                           { str x2, [sp,#-16]! (lenB) }
          EmitI32($F9401BE0);                           { ldr x0, [sp,#48] (lhs) }
          EmitA64StringParts(0, 1, 2, lhsTk, 48);       { x1=srcA, x2=lenA }
          EmitI32($AA0203E0);                           { mov x0, x2 (lenA) }
          EmitI32($F9400BE3);                           { ldr x3, [sp,#16] (srcB) }
          EmitI32($F94003E2);                           { ldr x2, [sp] (lenB) }
          EmitI32($910083FF);                           { add sp, sp, #32 }
          pi := FindProc('PXXStrEq');
          if pi < 0 then Error('compiler error: PXXStrEq not found');
          EmitCallProc(pi);                             { x0 = 1/0 }
          if op = Ord(tkNeq) then
            EmitI32($D2400000);                         { eor x0, x0, #1 }
          EmitI32($F81F0FE0);                           { push result }
          if (IRKind[left] = IR_BINOP) and (IntToTypeKind(IRTk[left]) = tyAnsiString) then
          begin
            EmitI32($F94013E0);                         { ldr x0, [sp,#32] (lhs) }
            EmitStrDecRefA64;
          end;
          if (IRKind[right] = IR_BINOP) and (IntToTypeKind(IRTk[right]) = tyAnsiString) then
          begin
            EmitI32($F9400BE0);                         { ldr x0, [sp,#16] (rhs) }
            EmitStrDecRefA64;
          end;
          EmitI32($F84107E0);                           { ldr x0, [sp], #16 (result) }
          EmitI32($910083FF);                           { add sp, sp, #32 }
          Exit;
        end;

        if not (TypeIsOrdinal(tk) or (tk = tyBoolean) or (tk = tyUnknown)) then
          Error('target aarch64: non-integer binop not yet supported');
        IREmitNodeAarch64(left);
        EmitI32($F81F0FE0); { str x0, [sp, #-16]! }
        IREmitNodeAarch64(right);
        EmitI32($AA0003E1); { mov x1, x0 }
        EmitI32($F84107E0); { ldr x0, [sp], #16 }

        if op = Ord(tkPlus) then EmitI32($8B010000)        { add x0, x0, x1 }
        else if op = Ord(tkMinus) then EmitI32($CB010000)  { sub x0, x0, x1 }
        else if op = Ord(tkStar) then EmitI32($9B017C00)   { mul x0, x0, x1 }
        else if op = Ord(tkDiv) then EmitI32($9AC10C00)    { sdiv x0, x0, x1 }
        else if op = Ord(tkMod) then
        begin
          EmitI32($9AC10C02);  { sdiv x2, x0, x1 }
          EmitI32($9B018040);  { msub x0, x2, x1, x0 }
        end
        else if op = Ord(tkAnd) then EmitI32($8A010000)    { and x0, x0, x1 }
        else if op = Ord(tkOr) then EmitI32($AA010000)     { orr x0, x0, x1 }
        else if op = Ord(tkShl) then EmitI32($9AC12000)    { lsl x0, x0, x1 }
        else if op = Ord(tkIdent) then EmitI32($9AC12400)  { lsr x0, x0, x1 }
        else if (op = Ord(tkEq)) or (op = Ord(tkNeq)) or (op = Ord(tkLt)) or
                (op = Ord(tkLe)) or (op = Ord(tkGt)) or (op = Ord(tkGe)) then
        begin
          EmitI32($EB01001F); { cmp x0, x1 }
          EmitSetccA64(op);
        end
        else
          Error('target aarch64: binop operator not yet supported');
      end;

    IR_CALL:
      begin
        pi := IRA[node];
        if pi = -Ord(tkGetMem) then
        begin
          si := IRC[node];
          if si >= REC_UCLASS_BASE then
            Error('target aarch64: class instantiation not yet supported');
          argNode := IRB[node];               { size arg }
          IREmitNodeAarch64(IRA[argNode]);    { size -> x0 }
          EmitHeapAllocLockedA64;             { x0 = payload pointer }
          Exit;
        end;
        if pi = -Ord(tkFreeMem) then
        begin
          argNode := IRB[node];               { pointer arg }
          IREmitNodeAarch64(IRA[argNode]);    { p -> x0 }
          EmitHeapFreeLockedA64;
          Exit;
        end;
        if pi = -102 then
        begin
          { SetLength(arr, n) -> PXXDynSetLen(slotAddr, n, desc). }
          argNode := IRB[node];               { arg1 = array lvalue (IR_LEA) }
          valNode := IRB[argNode];            { arg2 = new length }
          left := IRA[argNode];               { IR_LEA node }
          if IRKind[left] <> IR_LEA then
            Error('target aarch64: SetLength expects an array variable');
          si := IRA[left];
          if not (Syms[si].IsArray and (Syms[si].ArrLen = -1)) then
            Error('target aarch64: SetLength only supports dynamic arrays yet');
          if (Syms[si].Kind = skParam) and Syms[si].IsRef then
            Error('target aarch64: SetLength on a var-array parameter not yet supported');
          EmitLoadVarAddrA64(si);             { x0 = slot address }
          EmitI32($F81F0FE0);                 { str x0, [sp, #-16]! }
          IREmitNodeAarch64(IRA[valNode]);    { x0 = n }
          EmitI32($AA0003E1);                 { mov x1, x0 (n) }
          EmitI32($F84107E0);                 { ldr x0, [sp], #16 (slotAddr) }
          EmitLoadDataRefA64(2, GetOrAllocSymRTTI(si)); { x2 = desc }
          pi := FindProc('PXXDynSetLen');
          if pi < 0 then Error('compiler error: PXXDynSetLen not found');
          EmitCallProc(pi);
          Exit;
        end;
        if pi = -Ord(tkLength) then
        begin
          { Length(arr): IR_LEA auto-loaded the data pointer; count at [handle-8]. }
          argNode := IRB[node];
          valNode := IRA[argNode];
          IREmitNodeAarch64(valNode);         { x0 = handle (or 0) }
          if (IRKind[valNode] = IR_INDEX) or (IRKind[valNode] = IR_FIELD) then
            EmitI32($F9400000);               { ldr x0, [x0] (deref slot to handle) }
          EmitI32($B4000040);                 { cbz x0, +8 (skip ldur) }
          EmitI32($F85F8000);                 { ldur x0, [x0, #-8] }
          Exit;
        end;
        if pi < 0 then
          Error('target aarch64: builtin/special call not yet supported');
        if ProcExternal[pi] then
          Error('target aarch64: external calls not yet supported');
        if TypeIsAggregate(Procs[pi].RetType) then
          Error('target aarch64: aggregate-valued results not yet supported');

        argNode := IRB[node];
        nArgs := 0;
        while argNode <> -1 do
        begin
          IREmitNodeAarch64(IRA[argNode]);
          EmitI32($F81F0FE0); { str x0, [sp, #-16]! }
          Inc(nArgs);
          argNode := IRB[argNode];
        end;
        if nArgs <> Procs[pi].ParamCount then
          Error('target aarch64: call argument count mismatch');
        if nArgs > 8 then
          Error('target aarch64: procedures with more than 8 arguments not yet supported');

        for i := nArgs - 1 downto 0 do
          EmitI32($F84107E0 + i); { ldr x[i], [sp], #16 }

        EmitCallProc(pi);
      end;

    IR_CONST_STR:
      begin
        sVal := GetTokenStrFromRaw(IRA[node], IRB[node]);
        si := InternStr(sVal);
        EmitLoadDataRefA64(0, Strs[si].Offset);  { x0 = [len][data] struct addr }
      end;

    IR_FIELD:
      begin
        IREmitNodeAarch64(IRA[node]);            { base address -> x0 }
        if Integer(IRIVal[node]) <> 0 then
        begin
          EmitLoadImmA64(9, IRIVal[node]);       { x9 = offset }
          EmitI32($8B090000);                    { add x0, x0, x9 }
        end;
      end;

    IR_INDEX:
      begin
        { base[index]: addr = base + (index - lo) * elemSize. No COW (managed
          dynamic arrays use the handle loaded by IR_LEA). }
        IREmitNodeAarch64(IRA[node]);            { base -> x0 }
        EmitI32($F81F0FE0);                      { str x0, [sp, #-16]! }
        IREmitNodeAarch64(IRB[node]);            { index -> x0 }
        if IRC[node] <> 0 then
        begin
          EmitLoadImmA64(9, IRC[node]);          { x9 = lo }
          EmitI32($CB090000);                    { sub x0, x0, x9 }
        end;
        if Integer(IRIVal[node]) <> 1 then
        begin
          EmitLoadImmA64(9, IRIVal[node]);       { x9 = elemSize }
          EmitI32($9B097C00);                    { mul x0, x0, x9 }
        end;
        EmitI32($F84107E1);                      { ldr x1, [sp], #16 (base) }
        EmitI32($8B010000);                      { add x0, x0, x1 }
      end;

    IR_LOAD_MEM:
      begin
        IREmitNodeAarch64(IRA[node]); { address -> x0 }
        tk := IntToTypeKind(IRTk[node]);
        if not (TypeIsOrdinal(tk) or (tk = tyBoolean) or (tk = tyPointer) or
                (tk = tyChar) or (tk = tyUnknown) or
                (tk = tyAnsiString) or (tk = tyClass)) then
          Error('target aarch64: load through pointer of this type not yet supported');
        sz := TypeSize(tk);
        sgn := TypeSigned(tk);
        if sz = 1 then
        begin
          if sgn then EmitI32($39C00000) else EmitI32($39400000); { ldrsb/ldrb x0/w0, [x0] }
        end
        else if sz = 2 then
        begin
          if sgn then EmitI32($79C00000) else EmitI32($79400000); { ldrsh/ldrh }
        end
        else if sz = 4 then
        begin
          if sgn then EmitI32($B9800000) else EmitI32($B9400000); { ldrsw/ldr w0 }
        end
        else
          EmitI32($F9400000); { ldr x0, [x0] }
      end;

    IR_STORE_MEM:
      begin
        tk := IntToTypeKind(IRTk[node]);
        if tk = tyAnsiString then
        begin
          { Managed-string store through an address (field/slot): publish new,
            release old. }
          valNode := IRB[node];
          EmitAnsiStringFromNodeA64(valNode);   { x0 = new (retained) }
          EmitI32($F81F0FE0);                   { str x0, [sp, #-16]! (new) }
          IREmitNodeAarch64(IRA[node]);         { x0 = slot address }
          EmitI32($AA0003E1);                   { mov x1, x0 }
          EmitI32($F9400020);                   { ldr x0, [x1] old }
          EmitI32($F94003E2);                   { ldr x2, [sp] new }
          EmitI32($F9000022);                   { str x2, [x1] }
          EmitStrDecRefA64;                     { release old }
          EmitI32($910043FF);                   { add sp, sp, #16 }
          Exit;
        end;
        if not (TypeIsOrdinal(tk) or (tk = tyBoolean) or (tk = tyPointer) or
                (tk = tyChar) or (tk = tyUnknown)) then
          Error('target aarch64: store through pointer of this type not yet supported');
        IREmitNodeAarch64(IRB[node]); { value -> x0 }
        EmitI32($F81F0FE0);           { str x0, [sp, #-16]! }
        IREmitNodeAarch64(IRA[node]); { address -> x0 }
        EmitI32($F84107E1);           { ldr x1, [sp], #16 (value) }
        sz := TypeSize(tk);
        if sz = 1 then EmitI32($39000001)      { strb w1, [x0] }
        else if sz = 2 then EmitI32($79000001) { strh w1, [x0] }
        else if sz = 4 then EmitI32($B9000001) { str w1, [x0] }
        else EmitI32($F9000001);               { str x1, [x0] }
      end;

    IR_COPY_REC:
      begin
        { PXXMemMove(dest, src, count). }
        IREmitNodeAarch64(IRB[node]);          { x0 = src }
        EmitI32($F81F0FE0);                    { str x0, [sp, #-16]! }
        IREmitNodeAarch64(IRA[node]);          { x0 = dest }
        EmitI32($F84107E1);                    { ldr x1, [sp], #16 (src) }
        EmitLoadImmA64(2, IRIVal[node]);       { x2 = count }
        pi := FindProc('PXXMemMove');
        if pi < 0 then Error('compiler error: PXXMemMove not found');
        EmitCallProc(pi);
      end;

    IR_COPY_REC_MANAGED:
      begin
        { ARC record copy: retain src, release dest, then move. }
        IREmitNodeAarch64(IRB[node]);          { x0 = src }
        EmitI32($F81F0FE0);                    { str x0, [sp,#-16]! (src @ [sp+16]) }
        IREmitNodeAarch64(IRA[node]);          { x0 = dest }
        EmitI32($F81F0FE0);                    { str x0, [sp,#-16]! (dest @ [sp]) }
        pi := FindProc('PXXRecordRetain');
        if pi < 0 then Error('compiler error: PXXRecordRetain not found');
        EmitI32($F9400BE0);                    { ldr x0, [sp,#16] (src) }
        EmitLoadDataRefA64(1, -(RECORD_RTTI_DATAREF_BASE + (IRC[node] - REC_UCLASS_BASE)));
        EmitCallProc(pi);
        pi := FindProc('PXXRecordRelease');
        if pi < 0 then Error('compiler error: PXXRecordRelease not found');
        EmitI32($F94003E0);                    { ldr x0, [sp] (dest) }
        EmitLoadDataRefA64(1, -(RECORD_RTTI_DATAREF_BASE + (IRC[node] - REC_UCLASS_BASE)));
        EmitCallProc(pi);
        pi := FindProc('PXXMemMove');
        if pi < 0 then Error('compiler error: PXXMemMove not found');
        EmitI32($F94003E0);                    { ldr x0, [sp] (dest) }
        EmitI32($F9400BE1);                    { ldr x1, [sp,#16] (src) }
        EmitLoadImmA64(2, IRIVal[node]);       { x2 = count }
        EmitCallProc(pi);
        EmitI32($910083FF);                    { add sp, sp, #32 }
      end;

    IR_DEFAULT_MEM:
      begin
        IREmitNodeAarch64(IRA[node]);          { x0 = dest }
        if (IRC[node] >= 0) and RecordHasManagedFields(IRC[node]) then
        begin
          EmitI32($F81F0FE0);                  { str x0, [sp,#-16]! (dest) }
          pi := FindProc('PXXRecordRelease');
          if pi < 0 then Error('compiler error: PXXRecordRelease not found');
          EmitI32($F94003E0);                  { ldr x0, [sp] (dest) }
          EmitLoadDataRefA64(1, -(RECORD_RTTI_DATAREF_BASE + (IRC[node] - REC_UCLASS_BASE)));
          EmitCallProc(pi);
          pi := FindProc('PXXMemZero');
          if pi < 0 then Error('compiler error: PXXMemZero not found');
          EmitI32($F94003E0);                  { ldr x0, [sp] (dest) }
          EmitLoadImmA64(1, IRIVal[node]);     { x1 = count }
          EmitCallProc(pi);
          EmitI32($910043FF);                  { add sp, sp, #16 }
        end
        else
        begin
          pi := FindProc('PXXMemZero');
          if pi < 0 then Error('compiler error: PXXMemZero not found');
          EmitLoadImmA64(1, IRIVal[node]);     { x1 = count }
          EmitCallProc(pi);
        end;
      end;

    IR_SYSCALL:
      begin
        { Raw syscall: args (nr, a0..a5) pushed left-to-right, then popped
          into x8 (number) and x0..x5. Result stays in x0. }
        argNode := IRA[node]; nArgs := 0;
        while argNode <> -1 do
        begin
          IREmitNodeAarch64(IRA[argNode]);
          EmitI32($F81F0FE0); { str x0, [sp, #-16]! }
          Inc(nArgs);
          argNode := IRB[argNode];
        end;
        for i := nArgs - 1 downto 0 do
          if i = 0 then
            EmitI32($F84107E8)          { ldr x8, [sp], #16 }
          else
            EmitI32($F84107E0 + i - 1); { ldr x[i-1], [sp], #16 }
        EmitI32($D4000001); { svc #0 }
      end;

    IR_NEG:
      begin
        IREmitNodeAarch64(IRA[node]);
        EmitI32($CB0003E0); { neg x0, x0 }
      end;

    IR_NOT:
      begin
        IREmitNodeAarch64(IRA[node]);
        if TypeIsOrdinal(IntToTypeKind(IRTk[node])) and
           (IntToTypeKind(IRTk[node]) <> tyBoolean) then
        begin
          EmitI32($AA2003E0); { mvn x0, x0 }
        end
        else
        begin
          EmitI32($D2400000); { eor x0, x0, #1 }
        end;
      end;

    IR_WRITE:
      begin
        valNode := IRA[node];
        wid  := IRB[node];   { field width, 0 = none }
        if IRKind[valNode] = IR_CONST_STR then
        begin
          sVal := GetTokenStrFromRaw(IRA[valNode], IRB[valNode]);
          si := InternStr(sVal);
          if (wid > 0) and (wid > Strs[si].Len) then
          begin
            EnsureSpaces;
            EmitwriteSyscall(SpacesOffset, wid - Strs[si].Len);
          end;
          if Strs[si].Len > 0 then
            EmitwriteSyscall(Strs[si].Offset + 8, Strs[si].Len);
        end
        else
        begin
          tk := IntToTypeKind(IRTk[node]);
          if tk = tyChar then
          begin
            IREmitNodeAarch64(valNode);
            if wid > 1 then
            begin
              { Save x0 on stack to preserve character value }
              EmitI32($F81F0FE0); { str x0, [sp, #-16]! }
              EnsureSpaces;
              EmitwriteSyscall(SpacesOffset, wid - 1);
              EmitI32($F84107E0); { ldr x0, [sp], #16 }
            end;
            EmitwriteCharA64;
          end
          else if TypeIsOrdinal(tk) then
          begin
            IREmitNodeAarch64(valNode);
            if not TypeSigned(tk) then
            begin
              if wid > 0 then
                EmitwriteUIntWA64(wid)
              else
                EmitwriteUIntA64;
            end
            else
            begin
              if wid > 0 then
                EmitwriteIntWA64(wid)
              else
                EmitwriteIntA64;
            end;
          end
          else if tk = tyString then
          begin
            { write(1, buf+8, [buf]) for an inline [len:8][data] value. }
            IREmitNodeAarch64(valNode);            { x0 = struct addr }
            EmitI32($F9400002);                    { ldr x2, [x0] (len) }
            EmitI32($91002001);                    { add x1, x0, #8 (buf) }
            EmitI32($D2800020);                    { movz x0, #1 (fd) }
            EmitI32($D2800808);                    { movz x8, #64 (write) }
            EmitI32($D4000001);                    { svc #0 }
          end
          else if tk = tyAnsiString then
          begin
            { write(1, data, [data-8]); nil handle -> skip. }
            IREmitNodeAarch64(valNode);            { x0 = handle }
            wid := CodeLen;
            EmitI32($B4000000);                    { cbz x0, done (patched) }
            EmitI32($F81F0FE0);                    { str x0, [sp, #-16]! (preserve) }
            EmitI32($F85F8002);                    { ldur x2, [x0, #-8] (len) }
            EmitI32($AA0003E1);                    { mov x1, x0 (buf) }
            EmitI32($D2800020);                    { movz x0, #1 (fd) }
            EmitI32($D2800808);                    { movz x8, #64 (write) }
            EmitI32($D4000001);                    { svc #0 }
            EmitI32($F84107E0);                    { ldr x0, [sp], #16 (handle) }
            if (IRKind[valNode] = IR_BINOP) and
               (IntToTypeKind(IRTk[valNode]) = tyAnsiString) then
              EmitStrDecRefA64;
            Patch32(wid, $B4000000 or ((((CodeLen - wid) div 4) and $7FFFF) shl 5));
          end
          else
            Error('target aarch64: write of this operand not yet supported');
        end;
      end;

    IR_WRITELN:
      EmitwriteSyscall(NEWLINE_OFFSET, 1);

    IR_TERMINATE:
      begin
        if IRIVal[node] = AN_HALT then
        begin
          if IRA[node] <> -1 then
          begin
            IREmitNodeAarch64(IRA[node]);
            EmitI32($D2800BC8); { movz x8, #94 }
            EmitI32($D4000001); { svc #0 }
          end
          else
            EmitExit(0);
        end
        else
        begin
          if CurProc >= 0 then
            EmitProcEpilog(Procs[CurProc].RetSymIdx)
          else
            EmitExit(0);
        end;
      end;

    else
      Error('target aarch64: IR op not yet supported: ' + IROpName(IRKind[node]));
  end;
end;

procedure IREmitMachineCodeAarch64;
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
            EmitI32($14000000 or (((LabelPositions[lblId] - CodeLen) div 4) and $03ffffff))
          else
          begin
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitI32($14000000);
          end;
        end;

      IR_JUMP_IF_FALSE:
        begin
          lblId := IRA[i];
          IREmitNodeAarch64(IRB[i]); { condition -> x0 }
          if LabelPositions[lblId] <> -1 then
            EmitI32($B4000000 or (((LabelPositions[lblId] - CodeLen) div 4) and $7ffff) shl 5)
          else
          begin
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitI32($B4000000);
          end;
        end;

      IR_CALL:
        begin
          if IRIVal[i] = 1 then
            IREmitNodeAarch64(i);
        end;

      IR_STORE_SYM, IR_WRITE, IR_WRITELN:
        IREmitNodeAarch64(i);

      IR_NOP, IR_CONST_STR, IR_CONST_INT, IR_BLOCK,
      IR_LOAD_SYM, IR_BINOP, IR_NEG, IR_NOT, IR_ARG, IR_LEA, IR_SYSCALL,
      IR_FIELD, IR_INDEX, IR_CONST_STR: ;

      else
        IREmitNodeAarch64(i);
    end;
  end;

  for f := 0 to LabelFixupCount - 1 do
  begin
    lblId := LabelFixupTarget[f];
    pos := LabelFixupPos[f];
    targetOffset := LabelPositions[lblId];
    if targetOffset = -1 then Error('Unresolved forward jump in AArch64 IR codegen');
    if Code[pos+3] = $14 then
      Patch32(pos, $14000000 or (((targetOffset - pos) div 4) and $03ffffff))
    else if Code[pos+3] = $B4 then
      Patch32(pos, $B4000000 or (((targetOffset - pos) div 4) and $7ffff) shl 5)
    else
      Error('target aarch64: invalid instruction at label fixup');
  end;
end;
