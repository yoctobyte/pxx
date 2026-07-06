{ SPDX-License-Identifier: MPL-2.0 }
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

procedure IREmitLeaveExceptionFramesRISCV32(count: Integer);
var i: Integer;
begin
  for i := 1 to count do
  begin
    rv32_lw(reg_t2, reg_sp, 0);                   { prev EXC_TOP }
    EmitLoadGlobAddrRISCV32(reg_t1, BSS_EXC_TOP);
    rv32_sw(reg_t2, reg_t1, 0);
    rv32_addi(reg_sp, reg_sp, EXC_FRAME_SIZE_RV32);
  end;
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
var procIdx: Integer;
begin
  procIdx := FindProc('PXXAlloc');
  if procIdx < 0 then Error('compiler error: Alloc helper not found in builtin unit');
  rv32_addi(reg_a1, reg_zero, 8);   { a1 = align (a0 = size already) }
  EmitCallProc(procIdx);                 { result in a0 }
end;

procedure EmitHeapFreeLockedRISCV32;
{ a0 = payload pointer -> PXXFree(p). nil ignored inside. }
var procIdx: Integer;
begin
  procIdx := FindProc('PXXFree');
  if procIdx < 0 then Error('compiler error: Free helper not found in builtin unit');
  EmitCallProc(procIdx);
end;

procedure IREmitNodeRISCV32(node: Integer); forward;

{ ===== 64-bit (Int64/UInt64) value model: a0:a1 = lo:hi register pair =====
  True 8-byte values live in a0(low):a1(high) in flight, are loaded/stored as two
  words, and have their own arithmetic/shift/compare sequences (RISC-V has no
  condition flags, so carry/borrow are synthesised with sltu). Mirrors the arm32
  r0:r1 / i386 edx:eax models. A 32-bit source widens into a1 (sign/zero-ext);
  consumers needing only 32 bits keep a0. Scratch: t0:t1 = popped left operand,
  t2..t6 = temporaries. 64-bit div/mod is intentionally not provided yet (the
  soft-float kernels avoid the div operator); it errors until added. }

function Is64BitRISCV32(tk: TTypeKind): Boolean;
begin
  { Double occupies an a0:a1 register pair / 8-byte slot, same storage shape as
    Int64 — so the value-model paths (const/load/store) treat it as 64-bit.
    Arithmetic is dispatched separately (IsFloatRISCV32, checked first). }
  Result := (tk = tyInt64) or (tk = tyUInt64) or (tk = tyDouble);
end;

function IsFloatRISCV32(tk: TTypeKind): Boolean;
begin
  Result := (tk = tySingle) or (tk = tyDouble);
end;

procedure EmitLoadConst64RISCV32(v: Int64);
begin
  EmitLoadImmRISCV32(reg_a0, Integer(v and $FFFFFFFF));
  EmitLoadImmRISCV32(reg_a1, Integer((v shr 32) and $FFFFFFFF));
end;

procedure EmitSlotAddr64RISCV32(rd, idx: Integer);
{ rd = address of an 8-byte slot (global abs / frame-relative; ref forwarded). }
begin
  if Syms[idx].Kind = skGlobal then
    EmitLoadGlobAddrRISCV32(rd, Syms[idx].Offset)
  else
  begin
    EmitLoadImmRISCV32(rd, Syms[idx].Offset);
    rv32_add(rd, reg_s0, rd);
    if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then
      rv32_lw(rd, rd, 0);
  end;
end;

procedure EmitLoadVar64RISCV32(idx: Integer);
begin
  EmitSlotAddr64RISCV32(reg_t0, idx);
  rv32_lw(reg_a0, reg_t0, 0);   { lo }
  rv32_lw(reg_a1, reg_t0, 4);   { hi }
end;

procedure EmitStoreVar64RISCV32(idx: Integer);
begin
  EmitSlotAddr64RISCV32(reg_t0, idx);  { value in a0:a1; addr in t0 }
  rv32_sw(reg_a0, reg_t0, 0);   { lo }
  rv32_sw(reg_a1, reg_t0, 4);   { hi }
end;

procedure EmitNode64RISCV32(node: Integer);
{ Emit node; guarantee its full 64-bit value sits in a0:a1, widening a 32-bit
  source (sign-extend signed, zero-extend unsigned) into a1. }
var ntk: TTypeKind;
begin
  IREmitNodeRISCV32(node);
  ntk := IntToTypeKind(IRTk[node]);
  if not Is64BitRISCV32(ntk) then
  begin
    if TypeSigned(ntk) then
      rv32_srai(reg_a1, reg_a0, 31)
    else
      rv32_addi(reg_a1, reg_zero, 0);
  end;
end;

procedure EmitUDivMod64RISCV32(wantMod: Boolean);
{ Unsigned 64-bit divide. Pre: dividend in t0:t1 (lo:hi), divisor in a0:a1.
  Restoring binary long division, 64 iterations MSB-first: the dividend doubles
  as the quotient register (t0:t1), the remainder builds in t2:t3. Post: result
  (quotient, or remainder when wantMod) in a0:a1. Clobbers t0..t6. }
begin
  EmitAsmRv32([
    'addi t2, zero, 0',     { R.lo = 0 }
    'addi t3, zero, 0',     { R.hi = 0 }
    'addi t4, zero, 64',    { count }
    '.loop:',
    { shift {R.hi:R.lo:NQ.hi:NQ.lo} left by 1, MSB first }
    'srli t5, t0, 31',      { NQ.lo top bit }
    'add t0, t0, t0',       { NQ.lo <<= 1 }
    'srli t6, t1, 31',      { NQ.hi top bit }
    'add t1, t1, t1',       { NQ.hi <<= 1 }
    'or t1, t1, t5',        { NQ.hi |= old NQ.lo top }
    'srli t5, t2, 31',      { R.lo top bit }
    'add t2, t2, t2',       { R.lo <<= 1 }
    'or t2, t2, t6',        { R.lo |= old NQ.hi top }
    'add t3, t3, t3',       { R.hi <<= 1 }
    'or t3, t3, t5',        { R.hi |= old R.lo top }
    { if R (t3:t2) >= divisor (a1:a0) unsigned: subtract, set quotient bit }
    'bltu t3, a1, .nosub',  { R.hi < D.hi }
    'bne t3, a1, .sub',     { R.hi > D.hi }
    'bltu t2, a0, .nosub',  { R.hi == D.hi and R.lo < D.lo }
    '.sub:',
    'sltu t5, t2, a0',      { borrow }
    'sub t2, t2, a0',       { R.lo -= D.lo }
    'sub t3, t3, a1',       { R.hi -= D.hi }
    'sub t3, t3, t5',       { R.hi -= borrow }
    'ori t0, t0, 1',        { quotient bit }
    '.nosub:',
    'addi t4, t4, -1',
    'bne t4, zero, .loop'
  ]);
  if wantMod then
  begin
    rv32_addi(reg_a0, reg_t2, 0);
    rv32_addi(reg_a1, reg_t3, 0);
  end
  else
  begin
    rv32_addi(reg_a0, reg_t0, 0);
    rv32_addi(reg_a1, reg_t1, 0);
  end;
end;

procedure EmitIDivMod64RISCV32(wantMod: Boolean);
{ Signed 64-bit divide/mod. Truncated: quotient sign = dividend xor divisor,
  remainder takes the dividend's sign. Operands made non-negative in place, the
  unsigned core runs, then the sign is applied. Flags live in a3 (the core does
  not touch a3). Pre/post same regs as the unsigned core. }
begin
  EmitAsmRv32([
    'addi a3, zero, 0',     { flags: bit0 negate-quotient, bit1 negate-remainder }
    { divisor sign }
    'bge a1, zero, .dpos',
    'sltu t6, zero, a0',    { borrow for negate }
    'sub a0, zero, a0',
    'sub a1, zero, a1',
    'sub a1, a1, t6',       { a0:a1 = -divisor }
    'xori a3, a3, 1',
    '.dpos:',
    { dividend sign }
    'bge t1, zero, .npos',
    'sltu t6, zero, t0',
    'sub t0, zero, t0',
    'sub t1, zero, t1',
    'sub t1, t1, t6',       { t0:t1 = -dividend }
    'xori a3, a3, 1',
    'ori a3, a3, 2',
    '.npos:'
  ]);
  EmitUDivMod64RISCV32(wantMod);   { result in a0:a1; a3 preserved }
  if wantMod then
    EmitAsmRv32(['andi t5, a3, 2'])
  else
    EmitAsmRv32(['andi t5, a3, 1']);
  EmitAsmRv32([
    'beq t5, zero, .done',
    'sltu t6, zero, a0',
    'sub a0, zero, a0',
    'sub a1, zero, a1',
    'sub a1, a1, t6',       { apply sign }
    '.done:'
  ]);
end;

procedure EmitBinop64RISCV32(left, right, op: Integer; signedOp: Boolean);
{ (left OP right) as a 64-bit op. left spilled to the stack, right -> a0:a1, left
  popped into t0:t1. Arithmetic/bit ops leave a0:a1; comparisons leave 0/1 in a0. }
begin
  EmitNode64RISCV32(left);
  rv32_addi(reg_sp, reg_sp, -8);
  rv32_sw(reg_a0, reg_sp, 0);
  rv32_sw(reg_a1, reg_sp, 4);
  EmitNode64RISCV32(right);             { right -> a0:a1 }
  rv32_lw(reg_t0, reg_sp, 0);           { left.lo (dividend.lo) }
  rv32_lw(reg_t1, reg_sp, 4);           { left.hi }
  rv32_addi(reg_sp, reg_sp, 8);

  if (op = Ord(tkDiv)) or (op = Ord(tkMod)) then
  begin
    { dividend in t0:t1, divisor in a0:a1 }
    if signedOp then EmitIDivMod64RISCV32(op = Ord(tkMod))
    else EmitUDivMod64RISCV32(op = Ord(tkMod));
  end
  else if op = Ord(tkPlus) then
  begin
    rv32_add(reg_t2, reg_t0, reg_a0);   { lo = t0 + a0 }
    rv32_sltu(reg_t3, reg_t2, reg_t0);  { carry }
    rv32_add(reg_a1, reg_t1, reg_a1);   { hi = t1 + a1 }
    rv32_add(reg_a1, reg_a1, reg_t3);   { hi += carry }
    rv32_addi(reg_a0, reg_t2, 0);
  end
  else if op = Ord(tkMinus) then
  begin
    rv32_sltu(reg_t3, reg_t0, reg_a0);  { borrow }
    rv32_sub(reg_t2, reg_t0, reg_a0);   { lo }
    rv32_sub(reg_a1, reg_t1, reg_a1);   { hi }
    rv32_sub(reg_a1, reg_a1, reg_t3);   { hi -= borrow }
    rv32_addi(reg_a0, reg_t2, 0);
  end
  else if op = Ord(tkStar) then
  begin
    { low 64 of (t1:t0) * (a1:a0) }
    rv32_mul(reg_t2, reg_t0, reg_a0);    { lo = low(Alo*Blo) }
    rv32_mulhu(reg_t3, reg_t0, reg_a0);  { high(Alo*Blo) }
    rv32_mul(reg_t4, reg_t0, reg_a1);    { low(Alo*Bhi) }
    rv32_mul(reg_t5, reg_t1, reg_a0);    { low(Ahi*Blo) }
    rv32_add(reg_a1, reg_t3, reg_t4);
    rv32_add(reg_a1, reg_a1, reg_t5);
    rv32_addi(reg_a0, reg_t2, 0);
  end
  else if op = Ord(tkAnd) then
  begin
    rv32_and(reg_a0, reg_t0, reg_a0);
    rv32_and(reg_a1, reg_t1, reg_a1);
  end
  else if op = Ord(tkOr) then
  begin
    rv32_or(reg_a0, reg_t0, reg_a0);
    rv32_or(reg_a1, reg_t1, reg_a1);
  end
  else if op = Ord(tkXor) then
  begin
    rv32_xor(reg_a0, reg_t0, reg_a0);
    rv32_xor(reg_a1, reg_t1, reg_a1);
  end
  else if op = Ord(tkShl) then
  begin
    { count = a0 (& 63); value = t0:t1 -> a0:a1 }
    EmitAsmRv32([
      'andi t5, a0, 63',
      'addi t2, zero, 32',
      'bgeu t5, t2, .big',
      'beq t5, zero, .zero',
      'sub t3, t2, t5',      { 32 - n }
      'srl t4, t0, t3',      { lo >> (32-n) }
      'sll a1, t1, t5',      { hi << n }
      'or a1, a1, t4',
      'sll a0, t0, t5',      { lo << n }
      'j .end',
      '.big:',
      'sub t3, t5, t2',      { n - 32 }
      'sll a1, t0, t3',      { lo << (n-32) }
      'addi a0, zero, 0',
      'j .end',
      '.zero:',
      'addi a0, t0, 0',
      'addi a1, t1, 0',
      '.end:'
    ]);
  end
  else if (op = Ord(tkIdent)) or ((op = Ord(tkShr)) and not signedOp) then
  { Pascal 'shr' (tkIdent) or C unsigned '>>' (tkShr): logical on Int64/UInt64 }
  begin
    EmitAsmRv32([
      'andi t5, a0, 63',
      'addi t2, zero, 32',
      'bgeu t5, t2, .big',
      'beq t5, zero, .zero',
      'sub t3, t2, t5',      { 32 - n }
      'sll t4, t1, t3',      { hi << (32-n) }
      'srl a0, t0, t5',      { lo >> n }
      'or a0, a0, t4',
      'srl a1, t1, t5',      { hi >> n }
      'j .end',
      '.big:',
      'sub t3, t5, t2',      { n - 32 }
      'srl a0, t1, t3',      { hi >> (n-32) }
      'addi a1, zero, 0',
      'j .end',
      '.zero:',
      'addi a0, t0, 0',
      'addi a1, t1, 0',
      '.end:'
    ]);
  end
  else if op = Ord(tkShr) then   { C signed '>>': arithmetic (sign-propagating) }
  begin
    EmitAsmRv32([
      'andi t5, a0, 63',
      'addi t2, zero, 32',
      'bgeu t5, t2, .big',
      'beq t5, zero, .zero',
      'sub t3, t2, t5',      { 32 - n }
      'sll t4, t1, t3',      { hi << (32-n) }
      'srl a0, t0, t5',      { lo >> n (logical for lo) }
      'or a0, a0, t4',
      'sra a1, t1, t5',      { hi >>a n (arithmetic) }
      'j .end',
      '.big:',
      'sub t3, t5, t2',      { n - 32 }
      'sra a0, t1, t3',      { hi >>a (n-32) }
      'srai a1, t1, 31',     { sign-fill high word }
      'j .end',
      '.zero:',
      'addi a0, t0, 0',
      'addi a1, t1, 0',
      '.end:'
    ]);
  end
  else if (op = Ord(tkEq)) or (op = Ord(tkNeq)) then
  begin
    rv32_xor(reg_t3, reg_t0, reg_a0);
    rv32_xor(reg_t4, reg_t1, reg_a1);
    rv32_or(reg_t3, reg_t3, reg_t4);
    rv32_sltu(reg_t3, reg_zero, reg_t3);   { t3 = (a <> b) }
    if op = Ord(tkEq) then rv32_xori(reg_a0, reg_t3, 1)
    else rv32_addi(reg_a0, reg_t3, 0);
  end
  else if (op = Ord(tkLt)) or (op = Ord(tkGe)) then
  begin
    { a0 = (left < right): hi compare (signed/unsigned) then unsigned lo tiebreak }
    if signedOp then rv32_slt(reg_t3, reg_t1, reg_a1)
    else rv32_sltu(reg_t3, reg_t1, reg_a1);
    rv32_sltu(reg_t4, reg_t0, reg_a0);
    rv32_xor(reg_t5, reg_t1, reg_a1);
    rv32_sltu(reg_t5, reg_zero, reg_t5);
    rv32_xori(reg_t5, reg_t5, 1);          { hi equal }
    rv32_and(reg_t4, reg_t5, reg_t4);
    rv32_or(reg_a0, reg_t3, reg_t4);
    if op = Ord(tkGe) then rv32_xori(reg_a0, reg_a0, 1);   { ge = not lt }
  end
  else if (op = Ord(tkGt)) or (op = Ord(tkLe)) then
  begin
    { a0 = (left > right) = (right < left) }
    if signedOp then rv32_slt(reg_t3, reg_a1, reg_t1)
    else rv32_sltu(reg_t3, reg_a1, reg_t1);
    rv32_sltu(reg_t4, reg_a0, reg_t0);
    rv32_xor(reg_t5, reg_t1, reg_a1);
    rv32_sltu(reg_t5, reg_zero, reg_t5);
    rv32_xori(reg_t5, reg_t5, 1);
    rv32_and(reg_t4, reg_t5, reg_t4);
    rv32_or(reg_a0, reg_t3, reg_t4);
    if op = Ord(tkLe) then rv32_xori(reg_a0, reg_a0, 1);   { le = not gt }
  end
  else
    Error('target riscv32: 64-bit binop operator not yet supported');
end;

procedure EmitFloatConvRISCV32(srcTk, dstTk: TTypeKind);
{ Value already in a0 (single) or a0:a1 (double). Repack in place to dstTk.
  Both kinds are float here. }
var procIdx: Integer;
begin
  if srcTk = dstTk then Exit;
  if (srcTk = tySingle) and (dstTk = tyDouble) then
    procIdx := FindProc('__pxx_s2d')          { a0 -> a0:a1 }
  else if (srcTk = tyDouble) and (dstTk = tySingle) then
    procIdx := FindProc('__pxx_d2s')          { a0:a1 -> a0 }
  else
  begin
    Error('target riscv32: unsupported float-to-float conversion');
    Exit;
  end;
  if procIdx < 0 then Error('compiler error: softfloat repack helper not found (uses softfloat?)');
  EmitCallProc(procIdx);
end;

procedure EmitFloatOperandRISCV32(node: Integer; wantTk: TTypeKind);
{ Emit node and leave its value coerced to wantTk (a float kind) in a0 / a0:a1.
  Source may be a float (repacked) or a 32-bit integer (i2s/i2d). }
var ntk: TTypeKind; procIdx: Integer;
begin
  ntk := IntToTypeKind(IRTk[node]);
  if IsFloatRISCV32(ntk) then
  begin
    if ntk = tyDouble then EmitNode64RISCV32(node) else IREmitNodeRISCV32(node);
    EmitFloatConvRISCV32(ntk, wantTk);
  end
  else
  begin
    if (ntk = tyInt64) or (ntk = tyUInt64) then
    begin
      EmitNode64RISCV32(node);                 { a0:a1 = 64-bit int }
      if ntk = tyUInt64 then procIdx := FindProc('__pxx_ul2d')
      else procIdx := FindProc('__pxx_l2d');
      if procIdx < 0 then Error('compiler error: __pxx_l2d not found (uses softfloat?)');
      EmitCallProc(procIdx);                   { a0:a1 = double bits }
      EmitFloatConvRISCV32(tyDouble, wantTk);
      Exit;
    end;
    IREmitNodeRISCV32(node);                   { a0 = 32-bit int }
    if wantTk = tySingle then procIdx := FindProc('__pxx_i2s')
    else procIdx := FindProc('__pxx_i2d');
    if procIdx < 0 then Error('compiler error: softfloat i2s/i2d not found (uses softfloat?)');
    EmitCallProc(procIdx);
  end;
end;

procedure EmitFloatBinopRISCV32(node: Integer);
{ Float arithmetic + comparison via the soft-float kernels. Result of an
  arithmetic op lands in a0 (single) / a0:a1 (double); a comparison lands as a
  Boolean 0/1 in a0 (NaN-correct mapping of the kernel's -1/0/1/2 code). }
var left, right, op, procIdx: Integer; ltk, rtk: TTypeKind; isDouble: Boolean; nm: AnsiString;
begin
  left := IRA[node]; right := IRB[node]; op := IRC[node];
  ltk := IntToTypeKind(IRTk[left]); rtk := IntToTypeKind(IRTk[right]);
  isDouble := (ltk = tyDouble) or (rtk = tyDouble);

  if isDouble then
  begin
    EmitFloatOperandRISCV32(left, tyDouble);
    rv32_addi(reg_sp, reg_sp, -8); rv32_sw(reg_a0, reg_sp, 0); rv32_sw(reg_a1, reg_sp, 4);
    EmitFloatOperandRISCV32(right, tyDouble);
    rv32_addi(reg_a2, reg_a0, 0); rv32_addi(reg_a3, reg_a1, 0);          { a2:a3 = right }
    rv32_lw(reg_a0, reg_sp, 0); rv32_lw(reg_a1, reg_sp, 4); rv32_addi(reg_sp, reg_sp, 8); { a0:a1 = left }
    nm := '__pxx_d';
  end
  else
  begin
    EmitFloatOperandRISCV32(left, tySingle);
    rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);
    EmitFloatOperandRISCV32(right, tySingle);
    rv32_addi(reg_a1, reg_a0, 0);                                        { a1 = right }
    rv32_lw(reg_a0, reg_sp, 0); rv32_addi(reg_sp, reg_sp, 4);            { a0 = left }
    nm := '__pxx_s';
  end;

  if op = Ord(tkPlus) then nm := nm + 'add'
  else if op = Ord(tkMinus) then nm := nm + 'sub'
  else if op = Ord(tkStar) then nm := nm + 'mul'
  else if op = Ord(tkSlash) then nm := nm + 'div'
  else if (op = Ord(tkEq)) or (op = Ord(tkNeq)) or (op = Ord(tkLt)) or
          (op = Ord(tkGt)) or (op = Ord(tkLe)) or (op = Ord(tkGe)) then nm := nm + 'cmp'
  else begin Error('target riscv32: unsupported float operator'); Exit; end;

  procIdx := FindProc(nm);
  if procIdx < 0 then Error('compiler error: ' + nm + ' not found (uses softfloat?)');
  EmitCallProc(procIdx);

  { comparison kernels return -1/0/1, or 2 for NaN (unordered). }
  if op = Ord(tkEq) then rv32_sltiu(reg_a0, reg_a0, 1)             { ==0 }
  else if op = Ord(tkNeq) then rv32_sltu(reg_a0, reg_zero, reg_a0) { <>0 }
  else if op = Ord(tkLt) then rv32_slti(reg_a0, reg_a0, 0)         { ==-1 }
  else if op = Ord(tkLe) then rv32_slti(reg_a0, reg_a0, 1)         { in {-1,0} }
  else if op = Ord(tkGt) then begin rv32_xori(reg_a0, reg_a0, 1); rv32_sltiu(reg_a0, reg_a0, 1); end { ==1 }
  else if op = Ord(tkGe) then rv32_sltiu(reg_a0, reg_a0, 2);       { in {0,1} }
end;

procedure IREmitNodeRISCV32(node: Integer);
var
  left, right, op, si, procIdx, nArgs, i, lo, elemSize, sz, argNode, valNode, j: Integer;
  tk: TTypeKind;
  sgn, savedLVW: Boolean;
  sVal: AnsiString;
begin
  case IRKind[node] of
    IR_CONST_INT:
      if Is64BitRISCV32(IntToTypeKind(IRTk[node])) then
        EmitLoadConst64RISCV32(IRIVal[node])
      else
        EmitLoadImmRISCV32(reg_a0, IRIVal[node]);

    IR_CONST_STR:
      begin
        sVal := GetTokenStrFromRaw(IRA[node], IRB[node]);
        si := InternStr(sVal);
        EmitLoadDataRefRISCV32(reg_a0, Strs[si].Offset);
      end;

    IR_CONST_DATA:
      { Absolute data address (sentinel-resolvable), see the x86-64 case. }
      EmitLoadDataRefRISCV32(reg_a0, Integer(IRIVal[node]));

    IR_ASM:
      begin
        { Inline asm block: replay the parse-time-captured text lines
          (AsmParseBodyTextRv32, asmenc.inc) through the rv32 text engine.
          Emitting here, at final code positions, makes label fixups and
          @glob relocations natively correct — no AsmBytes-offset rebase
          like the x86-64 path needs. Labels are scoped to the block. }
        AsmRv32BlockBegin;
        for i := IRA[node] to IRA[node] + IRB[node] - 1 do
          AsmRv32ProcessInlineLine(i);
        AsmRv32BlockResolve;
      end;

    IR_PROCADDR:
      begin
        { @proc -> a0 = the routine's absolute code address. Load a PC-relative
          inline literal word that the ELF writer patches to entry+BodyAddr
          (same shape as the iram cross-section call literal). Needed for raw ISR
          install (mtvec) and @isr -> esp_intr_alloc. }
        if ProcExternal[IRA[node]] then
        begin
          EmitExternalProcAddr(IRA[node]);   { a0 = resolved external fn addr }
          Exit;
        end;
        rv32_auipc(reg_a0, 0);            { a0 = PC of this auipc }
        rv32_jal(reg_zero, 8);            { skip the 4-byte literal }
        if ProcAddrFixCount >= MAX_CALLFIX then Error('proc addr fixup overflow');
        ProcAddrFix[ProcAddrFixCount].CodePos := CodeLen;
        ProcAddrFix[ProcAddrFixCount].ProcIdx := IRA[node];
        Inc(ProcAddrFixCount);
        EmitI32(0);                       { literal: absolute proc addr (patched) }
        rv32_lw(reg_a0, reg_a0, 8);       { a0 = [auipc_pc + 8] = literal }
      end;

    IR_LOAD_SYM:
      if Is64BitRISCV32(Syms[IRA[node]].TypeKind) then
        EmitLoadVar64RISCV32(IRA[node])
      else
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
            procIdx := FindProc('PXXStrFromLit'); if procIdx < 0 then Error('compiler error: PXXStrFromLit not found');
            EmitCallProc(procIdx);                                 { a0 = handle }
          end
          else if IntToTypeKind(IRTk[valNode]) = tyChar then
          begin
            IREmitNodeRISCV32(valNode);                       { a0 = char code }
            rv32_addi(reg_sp, reg_sp, -8); rv32_sw(reg_a0, reg_sp, 0); { [sp] = char }
            rv32_addi(reg_a1, reg_sp, 0);                     { arg1 = &char }
            rv32_addi(reg_a0, reg_zero, 1);                   { arg0 = len 1 }
            procIdx := FindProc('PXXStrFromLit'); EmitCallProc(procIdx);
            rv32_addi(reg_sp, reg_sp, 8);
          end
          else if IntToTypeKind(IRTk[valNode]) = tyString then
          begin
            IREmitNodeRISCV32(valNode);                       { a0 = inline buffer addr }
            rv32_lw(reg_a2, reg_a0, 0);                       { len = [buf] }
            rv32_addi(reg_a1, reg_a0, 8);                     { arg1 = buf+8 }
            rv32_addi(reg_a0, reg_a2, 0);                     { arg0 = len }
            procIdx := FindProc('PXXStrFromLit'); EmitCallProc(procIdx);
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
              procIdx := FindProc('PXXStrIncRef'); EmitCallProc(procIdx);          { a0 = p }
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
            procIdx := FindProc('PXXStrDecRef'); EmitCallProc(procIdx);
            rv32_addi(reg_sp, reg_sp, 4);
          end
          else
          begin
            rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);   { push new }
            EmitLoadVarRISCV32(si);                                      { a0 = old handle }
            procIdx := FindProc('PXXStrDecRef'); EmitCallProc(procIdx);
            rv32_lw(reg_a0, reg_sp, 0); rv32_addi(reg_sp, reg_sp, 4);    { pop new }
            EmitStoreVarRISCV32(si);                                     { slot := new }
          end;
          Exit;
        end;
        { Float destination: coerce the RHS to the slot's float width (i2s/i2d/
          s2d/d2s as needed) before storing. Must precede the Is64Bit branch —
          a Double slot is Is64Bit but a non-double RHS needs conversion, not a
          raw 64-bit move. }
        if IsFloatRISCV32(Syms[IRA[node]].TypeKind) then
        begin
          EmitFloatOperandRISCV32(IRB[node], Syms[IRA[node]].TypeKind);
          if Syms[IRA[node]].TypeKind = tyDouble then
            EmitStoreVar64RISCV32(IRA[node])
          else
            EmitStoreVarRISCV32(IRA[node]);
          Exit;
        end;
        if Is64BitRISCV32(Syms[IRA[node]].TypeKind) then
        begin
          EmitNode64RISCV32(IRB[node]);
          EmitStoreVar64RISCV32(IRA[node]);
        end
        else
        begin
          IREmitNodeRISCV32(IRB[node]);
          EmitStoreVarRISCV32(IRA[node]);
        end;
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
          rv32_lw(reg_a0, reg_a0, 0)
        { Scalar var/out param: the slot holds the forwarded caller address, so
          its lvalue address is [slot], not &slot. Without this deref, taking the
          address of a var param (e.g. forwarding `var op` into another routine's
          `var p`, or `@op`) yields the local slot — the inner write never reaches
          the caller (feature-riscv32-var-param-forwarding). The load/store paths
          and the 64-bit slot-addr emitter already deref; this brings IR_LEA's
          32-bit scalar path in line. Arrays/strings keep their handling above. }
        else if (Syms[si].Kind = skParam) and Syms[si].IsRef and
                not Syms[si].IsArray and (Syms[si].TypeKind <> tyAnsiString) then
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
          procIdx := FindProc('PXXStrUnique');
          if procIdx < 0 then Error('compiler error: PXXStrUnique not found');
          EmitCallProc(procIdx);                   { a0 = unique handle }
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
        else if (sz = 8) and Is64BitRISCV32(tk) then
        begin
          { 64-bit load through memory (Int64/Double array element / field):
            two words into a0:a1. Was a single lw — the high word was stale. }
          rv32_lw(reg_a1, reg_a0, 4);
          rv32_lw(reg_a0, reg_a0, 0);
        end
        else
          rv32_lw(reg_a0, reg_a0, 0);
      end;

    IR_STORE_MEM:
      begin
        tk := IntToTypeKind(IRTk[node]);
        sz := TypeSize(tk);
        { Float destination: coerce the RHS to the target float width (i2d/l2d/
          i2s/s2d/d2s) before storing. Must precede the Is64Bit branch — a Double
          target is Is64Bit but an integer RHS needs int->double conversion, not a
          raw 64-bit bit-copy. Mirrors the IR_STORE_SYM float path. Without this,
          `*(double*)p = intval` stored the raw integer bits as a denormal (e.g.
          sqlite3AtoF's `*pResult = s` for an integer-valued real hung FpDecode). }
        if IsFloatRISCV32(tk) then
        begin
          EmitFloatOperandRISCV32(IRB[node], tk);   { a0(single) / a0:a1(double) }
          if tk = tyDouble then
          begin
            rv32_addi(reg_sp, reg_sp, -8);
            rv32_sw(reg_a0, reg_sp, 0);
            rv32_sw(reg_a1, reg_sp, 4);
            savedLVW := InLValueWrite;
            InLValueWrite := True;
            IREmitNodeRISCV32(IRA[node]);
            InLValueWrite := savedLVW;
            rv32_lw(reg_a1, reg_sp, 0);
            rv32_lw(reg_t1, reg_sp, 4);
            rv32_addi(reg_sp, reg_sp, 8);
            rv32_sw(reg_a1, reg_a0, 0);
            rv32_sw(reg_t1, reg_a0, 4);
          end
          else
          begin
            rv32_addi(reg_sp, reg_sp, -4);
            rv32_sw(reg_a0, reg_sp, 0);
            savedLVW := InLValueWrite;
            InLValueWrite := True;
            IREmitNodeRISCV32(IRA[node]);
            InLValueWrite := savedLVW;
            rv32_lw(reg_a1, reg_sp, 0);
            rv32_addi(reg_sp, reg_sp, 4);
            rv32_sw(reg_a1, reg_a0, 0);
          end;
          Exit;
        end;
        if (sz = 8) and Is64BitRISCV32(tk) then
        begin
          { 64-bit store through memory: spill both value words across the
            address evaluation, then store the pair. Was single-word (the
            high word of an Int64/Double field/element store was dropped). }
          EmitNode64RISCV32(IRB[node]);              { a0:a1 = value }
          rv32_addi(reg_sp, reg_sp, -8);
          rv32_sw(reg_a0, reg_sp, 0);
          rv32_sw(reg_a1, reg_sp, 4);
          savedLVW := InLValueWrite;
          InLValueWrite := True;
          IREmitNodeRISCV32(IRA[node]);              { a0 = dest addr }
          InLValueWrite := savedLVW;
          rv32_lw(reg_a1, reg_sp, 0);
          rv32_lw(reg_t1, reg_sp, 4);
          rv32_addi(reg_sp, reg_sp, 8);
          rv32_sw(reg_a1, reg_a0, 0);
          rv32_sw(reg_t1, reg_a0, 4);
          Exit;
        end;
        IREmitNodeRISCV32(IRB[node]);
        rv32_addi(reg_sp, reg_sp, -4);
        rv32_sw(reg_a0, reg_sp, 0);

        savedLVW := InLValueWrite;
        InLValueWrite := True;
        IREmitNodeRISCV32(IRA[node]);
        InLValueWrite := savedLVW;
        rv32_lw(reg_a1, reg_sp, 0);
        rv32_addi(reg_sp, reg_sp, 4);

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
          procIdx := FindProc('PXXStrConcat');
          if procIdx < 0 then Error('compiler error: PXXStrConcat not found');
          EmitCallProc(procIdx);                { a0 = result handle }
          { release fresh tyAnsiString BINOP operands (nested concat temporaries) }
          rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);  { push result; [sp+4]=rhs,[sp+8]=lhs }
          if (IRKind[left] = IR_BINOP) and (IntToTypeKind(IRTk[left]) = tyAnsiString) then
          begin
            rv32_lw(reg_a0, reg_sp, 8);
            procIdx := FindProc('PXXStrDecRef'); EmitCallProc(procIdx);
          end;
          if (IRKind[right] = IR_BINOP) and (IntToTypeKind(IRTk[right]) = tyAnsiString) then
          begin
            rv32_lw(reg_a0, reg_sp, 4);
            procIdx := FindProc('PXXStrDecRef'); EmitCallProc(procIdx);
          end;
          rv32_lw(reg_a0, reg_sp, 0); rv32_addi(reg_sp, reg_sp, 4);   { pop result }
          rv32_addi(reg_sp, reg_sp, 8);                               { drop rhs, lhs }
          Exit;
        end;

        if ((op = Ord(tkEq)) or (op = Ord(tkNeq))) and
           ((IntToTypeKind(IRTk[left]) = tyAnsiString) or (IntToTypeKind(IRTk[right]) = tyAnsiString) or
            TypeIsFrozenString(IntToTypeKind(IRTk[left])) or TypeIsFrozenString(IntToTypeKind(IRTk[right]))) then
        begin
          { String equality (managed handle, frozen buffer, or char operands —
            EmitStrOperandRISCV32 normalizes each) -> PXXStrEq -> 1/0.
            Was gated on tyAnsiString only, so frozen = frozen (e.g.
            ParamStr(1) = '--selftest') compared ADDRESSES. }
          IREmitNodeRISCV32(left);  rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);
          IREmitNodeRISCV32(right); rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);
          EmitStrOperandRISCV32(IntToTypeKind(IRTk[right]), 0, reg_t1, reg_t2);  { lenB, srcB }
          EmitStrOperandRISCV32(IntToTypeKind(IRTk[left]),  4, reg_a0, reg_a1);  { lenA, srcA }
          rv32_addi(reg_a2, reg_t1, 0);    { a2 = lenB }
          rv32_addi(reg_a3, reg_t2, 0);    { a3 = srcB }
          procIdx := FindProc('PXXStrEq');
          if procIdx < 0 then Error('compiler error: PXXStrEq not found');
          EmitCallProc(procIdx);                { a0 = 1/0 }
          { release fresh operand temporaries }
          rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);  { push result }
          if (IRKind[left] = IR_BINOP) and (IntToTypeKind(IRTk[left]) = tyAnsiString) then
          begin
            rv32_lw(reg_a0, reg_sp, 8);
            procIdx := FindProc('PXXStrDecRef'); EmitCallProc(procIdx);
          end;
          if (IRKind[right] = IR_BINOP) and (IntToTypeKind(IRTk[right]) = tyAnsiString) then
          begin
            rv32_lw(reg_a0, reg_sp, 4);
            procIdx := FindProc('PXXStrDecRef'); EmitCallProc(procIdx);
          end;
          rv32_lw(reg_a0, reg_sp, 0); rv32_addi(reg_sp, reg_sp, 4);   { pop result }
          rv32_addi(reg_sp, reg_sp, 8);                               { drop rhs, lhs }
          if op = Ord(tkNeq) then rv32_xori(reg_a0, reg_a0, 1);
          Exit;
        end;

        { Float arithmetic/compare via the soft-float kernels. MUST precede the
          64-bit check below — Double is now Is64Bit (a0:a1 storage shape) but its
          arithmetic is soft-float, not integer. Key off the operands: a compare
          carries a Boolean result tk. }
        if IsFloatRISCV32(IntToTypeKind(IRTk[node])) or
           IsFloatRISCV32(IntToTypeKind(IRTk[left])) or
           IsFloatRISCV32(IntToTypeKind(IRTk[right])) then
        begin
          EmitFloatBinopRISCV32(node);
          Exit;
        end;

        { 64-bit (Int64/UInt64) ops use the dedicated a0:a1 path. A comparison
          carries a Boolean result tk, so key off the operands too. }
        if Is64BitRISCV32(IntToTypeKind(IRTk[node])) or
           Is64BitRISCV32(IntToTypeKind(IRTk[left])) or
           Is64BitRISCV32(IntToTypeKind(IRTk[right])) then
        begin
          EmitBinop64RISCV32(left, right, op,
            not ((IntToTypeKind(IRTk[left]) = tyUInt64) or (IntToTypeKind(IRTk[right]) = tyUInt64)));
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
        else if op = Ord(tkDiv) then
        begin
          { unsigned dividend (Cardinal/LongWord, C unsigned int) -> divu }
          if TypeDivideUnsigned(IntToTypeKind(IRTk[left])) then rv32_divu(reg_a0, reg_a0, reg_a1)
          else rv32_div(reg_a0, reg_a0, reg_a1);
        end
        else if op = Ord(tkMod) then
        begin
          if TypeDivideUnsigned(IntToTypeKind(IRTk[left])) then rv32_remu(reg_a0, reg_a0, reg_a1)
          else rv32_rem(reg_a0, reg_a0, reg_a1);
        end
        else if op = Ord(tkAnd) then rv32_and(reg_a0, reg_a0, reg_a1)
        else if op = Ord(tkOr) then rv32_or(reg_a0, reg_a0, reg_a1)
        else if op = Ord(tkXor) then rv32_xor(reg_a0, reg_a0, reg_a1)
        else if op = Ord(tkShl) then rv32_sll(reg_a0, reg_a0, reg_a1)
        else if op = Ord(tkIdent) then rv32_srl(reg_a0, reg_a0, reg_a1) { 'shr' parses as ident }
        else if op = Ord(tkShr) then rv32_sra(reg_a0, reg_a0, reg_a1)  { C signed >> (bug-c-signed-arith-shift-right) }
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
        else if (op = Ord(tkLt)) or (op = Ord(tkGt)) or
                (op = Ord(tkLe)) or (op = Ord(tkGe)) then
        begin
          { Unsigned operands (Cardinal/LongWord, C unsigned int) use sltu, not
            slt — was hardcoded signed, so an inline `LongWord > 0` / C
            `(a-10u) > 0` compared signed. }
          sgn := not TypeCompareUnsigned(IntToTypeKind(IRTk[left]), IntToTypeKind(IRTk[right]));
          if op = Ord(tkLt) then
          begin
            if sgn then rv32_slt(reg_a0, reg_a0, reg_a1)
            else rv32_sltu(reg_a0, reg_a0, reg_a1);
          end
          else if op = Ord(tkGt) then
          begin
            if sgn then rv32_slt(reg_a0, reg_a1, reg_a0)
            else rv32_sltu(reg_a0, reg_a1, reg_a0);
          end
          else if op = Ord(tkLe) then
          begin
            if sgn then rv32_slt(reg_a0, reg_a1, reg_a0)
            else rv32_sltu(reg_a0, reg_a1, reg_a0);
            rv32_xori(reg_a0, reg_a0, 1);
          end
          else { tkGe }
          begin
            if sgn then rv32_slt(reg_a0, reg_a0, reg_a1)
            else rv32_sltu(reg_a0, reg_a0, reg_a1);
            rv32_xori(reg_a0, reg_a0, 1);
          end;
        end
        else if op = Ord(tkIn) then
        begin
          { Set membership: a0 = element, a1 = set address. Branch-free:
            in-range flag (elem < 256) gates both the byte offset (so an
            out-of-range element never derefs past the 32-byte set) and the
            result bit. Result 0/1 -> a0. }
          rv32_sltiu(reg_t2, reg_a0, 256);        { t2 = in-range (0/1) }
          rv32_sub(reg_t0, reg_zero, reg_t2);     { t0 = 0 or 0xFFFFFFFF mask }
          rv32_srli(reg_t1, reg_a0, 3);           { byte index }
          rv32_and(reg_t1, reg_t1, reg_t0);       { clamp to 0 when out of range }
          rv32_add(reg_t1, reg_a1, reg_t1);
          rv32_lbu(reg_t1, reg_t1, 0);            { set byte }
          rv32_andi(reg_t0, reg_a0, 7);           { bit index }
          rv32_srl(reg_t1, reg_t1, reg_t0);
          rv32_andi(reg_t1, reg_t1, 1);
          rv32_and(reg_a0, reg_t1, reg_t2);
        end
        else
        begin
          ErrorIdent := 'op ' + MangleSuffix(op);
          Error('target riscv32: unsupported binary operator');
        end;
      end;

    IR_CALL:
      begin
        procIdx := IRA[node];
        if procIdx = -Ord(tkGetMem) then
        begin
          { GetMem / New / class instantiation. For a class: alloc, store the
            VMT pointer at offset 0, run the ctor, return Self in a0 (mirrors
            the arm32 shape at rv32 word width). }
          j := IRC[node];                     { class idx (or < base) }
          argNode := IRB[node];               { size arg }
          IREmitNodeRISCV32(IRA[argNode]);    { size -> a0 }
          EmitHeapAllocLockedRISCV32;         { a0 = payload pointer }
          if j < REC_UCLASS_BASE then
            Exit;                             { plain GetMem }
          EmitLoadDataRefRISCV32(reg_t1, UClsVMTOffset[j - REC_UCLASS_BASE]);
          rv32_sw(reg_t1, reg_a0, 0);         { [Self] = VMT }
          j := FindUMeth(j - REC_UCLASS_BASE, 'create');
          if j < 0 then
            Exit;                             { no ctor: instance in a0 }
          rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);  { Self, deepest }
          nArgs := 1;
          argNode := IRB[node];               { size arg }
          argNode := IRB[argNode];            { first explicit ctor arg }
          while argNode <> -1 do
          begin
            IREmitNodeRISCV32(IRA[argNode]);
            rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);
            Inc(nArgs);
            argNode := IRB[argNode];
          end;
          if nArgs > 8 then
            Error('target riscv32: constructor with more than 8 parameter words not supported');
          for i := 0 to nArgs - 1 do
            rv32_lw(reg_a0 + i, reg_sp, (nArgs - 1 - i) * 4);
          rv32_lw(reg_t1, reg_sp, (nArgs - 1) * 4);            { Self again }
          rv32_addi(reg_sp, reg_sp, nArgs * 4);
          rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_t1, reg_sp, 0);  { save Self }
          EmitCallProc(UMthProc_[j]);
          rv32_lw(reg_a0, reg_sp, 0); rv32_addi(reg_sp, reg_sp, 4);   { Self }
          Exit;
        end;
        if procIdx = -Ord(tkFreeMem) then
        begin
          argNode := IRB[node];               { pointer arg }
          IREmitNodeRISCV32(IRA[argNode]);    { p -> a0 }
          EmitHeapFreeLockedRISCV32;
          Exit;
        end;
        if procIdx = -102 then
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
            procIdx := FindProc('PXXStrSetLen');
            if procIdx < 0 then Error('compiler error: PXXStrSetLen not found');
            EmitCallProc(procIdx);
            Exit;
          end;
          if IRKind[left] <> IR_LEA then
            Error('target riscv32: SetLength expects an array variable');
          si := IRA[left];
          if not (Syms[si].IsArray and (Syms[si].ArrLen = -1)) then
            Error('target riscv32: SetLength only supports dynamic arrays yet');
          if (Syms[si].Kind = skParam) and Syms[si].IsRef then
          begin
            { var-array param: the frame slot holds the CALLER's slot address }
            EmitSlotAddrRISCV32(reg_a0, si);
            rv32_lw(reg_a0, reg_a0, 0);
          end
          else
            EmitSlotAddrRISCV32(reg_a0, si);  { a0 = slot address (not the handle) }
          rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);  { push slot }
          IREmitNodeRISCV32(IRA[valNode]);    { a0 = n }
          rv32_addi(reg_a1, reg_a0, 0);       { a1 = n }
          rv32_lw(reg_a0, reg_sp, 0); rv32_addi(reg_sp, reg_sp, 4);   { pop slot -> a0 }
          EmitLoadDataRefRISCV32(reg_a2, GetOrAllocSymRTTI(si));      { a2 = desc }
          procIdx := FindProc('PXXDynSetLen');
          if procIdx < 0 then Error('compiler error: PXXDynSetLen not found');
          EmitCallProc(procIdx);
          Exit;
        end;
        if procIdx = -Ord(tkLength) then
        begin
          { Length(arr): a0 = handle; count at [handle-8], nil handle -> 0. }
          argNode := IRB[node];
          IREmitNodeRISCV32(IRA[argNode]);    { a0 = handle (or 0) }
          rv32_beq(reg_a0, reg_zero, 8);      { if nil, skip the load (result 0) }
          rv32_lw(reg_a0, reg_a0, -8);
          Exit;
        end;
        if procIdx < 0 then
        begin
          { Type-pun passthroughs: Ord/Chr/Integer()/LongWord() are identity on
            the value already in a0 (char/int share the register model). }
          if (procIdx = -Ord(tkOrd)) or (procIdx = -Ord(tkChr)) or
             (procIdx = -Ord(tkInteger_T)) or (procIdx = -Ord(tkLongWord_T)) or
             (procIdx = -Ord(tkChar_T)) or (procIdx = -Ord(tkBoolean_T)) or
             (procIdx = -Ord(tkString_T)) then
          begin
            argNode := IRB[node];
            IREmitNodeRISCV32(IRA[argNode]);
            Exit;
          end;
          if (procIdx = -203) or (procIdx = -204) then
          begin
            { Trunc (-203, toward zero) / Round (-204, nearest-even) -> Int64, via
              the soft-float d2i[_rne]/s2i[_rne] kernels (32-bit result, sign-
              extended to the a0:a1 pair). }
            argNode := IRB[node];
            tk := IntToTypeKind(IRTk[IRA[argNode]]);
            if tk = tyDouble then
            begin
              { full 64-bit convert: the 32-bit d2i saturates at 2^31 (breaks a
                double->u64 cast, e.g. sqlite %f). d2i64 returns the Int64 in
                a0:a1 directly, so no sign-extend follows. }
              EmitNode64RISCV32(IRA[argNode]);    { a0:a1 = double bits }
              if procIdx = -204 then sVal := '__pxx_d2i64_rne' else sVal := '__pxx_d2i64';
              procIdx := FindProc(sVal);
              if procIdx < 0 then Error('compiler error: ' + sVal + ' not found (uses softfloat?)');
              EmitCallProc(procIdx);              { a0:a1 = full Int64 result }
              Exit;
            end
            else if tk = tySingle then
            begin
              IREmitNodeRISCV32(IRA[argNode]);    { a0 = single bits }
              if procIdx = -204 then sVal := '__pxx_s2i_rne' else sVal := '__pxx_s2i';
            end
            else
            begin
              IREmitNodeRISCV32(IRA[argNode]);     { Trunc/Round of an integer is identity }
              rv32_srai(reg_a1, reg_a0, 31);
              Exit;
            end;
            procIdx := FindProc(sVal);
            if procIdx < 0 then Error('compiler error: ' + sVal + ' not found (uses softfloat?)');
            EmitCallProc(procIdx);
            rv32_srai(reg_a1, reg_a0, 31);         { sign-extend to Int64 a0:a1 }
            Exit;
          end;
          if (procIdx = -205) or (procIdx = -206) then
          begin
            { Frac (-205) / Int (-206) -> float (node tk is tyDouble). Promote the
              arg to double, then call the fractional / integer-part kernel. }
            argNode := IRB[node];
            EmitFloatOperandRISCV32(IRA[argNode], tyDouble);   { a0:a1 = double }
            if procIdx = -205 then sVal := '__pxx_dfrac' else sVal := '__pxx_dint';
            procIdx := FindProc(sVal);
            if procIdx < 0 then Error('compiler error: ' + sVal + ' not found (uses softfloat?)');
            EmitCallProc(procIdx);                  { a0:a1 = double result }
            Exit;
          end;
          if procIdx = -Ord(tkArgCount) then
          begin
            { ParamCount = argc - 1; initial sp (saved by the entry stub)
              points at argc. }
            EmitLoadGlobAddrRISCV32(reg_t1, BSS_INITIAL_RSP);
            rv32_lw(reg_t1, reg_t1, 0);
            rv32_lw(reg_a0, reg_t1, 0);
            rv32_addi(reg_a0, reg_a0, -1);
            Exit;
          end;
          if procIdx = -Ord(tkArgStr) then
          begin
            { ArgStr(index, strVar) — the 2-arg statement form (ParamStr(i)
              expressions desugar to this with a hidden frozen temp). Fetch
              argv[index], then fill the dest: frozen -> PXXCStrToFrozen;
              managed -> PXXStrFromLit + PXXStrPublish. }
            argNode := IRB[node];
            if argNode = -1 then
              Error('target riscv32: ArgStr expects an index');
            IREmitNodeRISCV32(IRA[argNode]);          { a0 = index }
            argNode := IRB[argNode];
            if argNode = -1 then
              Error('target riscv32: ArgStr expects a destination string');
            valNode := IRA[argNode];
            rv32_slli(reg_a0, reg_a0, 2);
            EmitLoadGlobAddrRISCV32(reg_t1, BSS_INITIAL_RSP);
            rv32_lw(reg_t1, reg_t1, 0);               { initial sp }
            rv32_addi(reg_t1, reg_t1, 4);             { argv base }
            rv32_add(reg_a0, reg_t1, reg_a0);
            rv32_lw(reg_a0, reg_a0, 0);               { argv[index] (or junk past envp for a huge index — Pascal callers pass 0..ParamCount) }
            if (IRKind[valNode] = IR_LOAD_SYM) and
               (Syms[IRA[valNode]].TypeKind = tyAnsiString) then
            begin
              { managed dest: handle = FromLit(strlen(src), src); publish }
              rv32_addi(reg_a1, reg_a0, 0);           { a1 = src }
              rv32_addi(reg_a2, reg_zero, 0);         { len }
              i := CodeLen;                           { strlen loop }
              rv32_add(reg_t0, reg_a1, reg_a2);
              rv32_lbu(reg_t0, reg_t0, 0);
              rv32_beq(reg_t0, reg_zero, 12);
              rv32_addi(reg_a2, reg_a2, 1);
              EmitI32(EncodeRISCVJAL(reg_zero, i - CodeLen));
              rv32_addi(reg_a0, reg_a2, 0);           { a0 = len (a1 = src) }
              i := FindProc('PXXStrFromLit');
              if i < 0 then Error('compiler error: PXXStrFromLit not found');
              EmitCallProc(i);                        { a0 = handle }
              rv32_addi(reg_a1, reg_a0, 0);           { a1 = handle }
              EmitSlotAddrRISCV32(reg_a0, IRA[valNode]);
              i := FindProc('PXXStrPublish');
              if i < 0 then Error('compiler error: PXXStrPublish not found');
              EmitCallProc(i);
            end
            else
            begin
              { frozen dest: buffer address then byte copy. Emitting the dest
                lvalue may clobber a-regs, so park src on the stack. }
              rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);
              IREmitNodeRISCV32(valNode);             { a0 = dest buffer addr }
              rv32_lw(reg_a1, reg_sp, 0); rv32_addi(reg_sp, reg_sp, 4);  { a1 = src }
              i := FindProc('PXXCStrToFrozen');
              if i < 0 then Error('compiler error: PXXCStrToFrozen not found');
              EmitCallProc(i);
            end;
            Exit;
          end;
          if procIdx = -210 then
          begin
            { bare `Eof` (stdin) -> PXXStdinEof: Boolean (portable builtin,
              shares the peek byte with PXXReadLine). Hosted only. }
            procIdx := FindProc('PXXStdinEof');
            if procIdx < 0 then Error('compiler error: PXXStdinEof not found');
            EmitCallProc(procIdx);
            Exit;
          end;
          begin
            ErrorIdent := 'builtin id ' + MangleSuffix(-procIdx);
            Error('target riscv32: standard builtin calls not supported in bare-metal stage 1');
          end;
        end;

        { Word-based argument passing (matches the callee spill in parser.inc):
          each scalar arg is one word, a by-value Int64/UInt64 is two (lo then
          hi). nArgs counts WORDS here; word k is pushed in index order so it
          lands at [sp + (nWords-1-k)*4], then loads into a[k] (<=8 words). }
        { Aggregate (record) result: push the caller's hidden destination first
          (deepest), so it survives arg evaluation; loaded into t1 just before the
          call. riscv has no dedicated indirect-result register, so t1 (a
          caller-saved temp) carries it; the callee prologue reads t1 first. }
        if (procIdx >= 0) and (not ProcExternal[procIdx]) and
           RetViaHiddenDest(Procs[procIdx].RetType) then
        begin
          IREmitNodeRISCV32(IRC[node]);                  { a0 = hidden dest addr }
          rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);
        end;
        argNode := IRB[node];
        nArgs := 0;     { word count }
        i := 0;         { argument index }
        while argNode <> -1 do
        begin
          if (procIdx >= 0) and (not ProcExternal[procIdx]) and
             (i < Procs[procIdx].ParamCount) and
             IsFloatRISCV32(Procs[procIdx].Params[i].TypeKind) and
             (not Procs[procIdx].Params[i].IsRef) and
             (not Procs[procIdx].Params[i].IsArray) then
          begin
            { Float param: coerce the arg to the param's float width, then push
              one word (single) or two words lo:hi (double). }
            EmitFloatOperandRISCV32(IRA[argNode], Procs[procIdx].Params[i].TypeKind);
            if Procs[procIdx].Params[i].TypeKind = tyDouble then
            begin
              rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);  { lo }
              rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a1, reg_sp, 0);  { hi }
              Inc(nArgs, 2);
            end
            else
            begin
              rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);
              Inc(nArgs, 1);
            end;
          end
          else if (procIdx >= 0) and (not ProcExternal[procIdx]) and
             (i < Procs[procIdx].ParamCount) and
             (Procs[procIdx].Params[i].TypeKind = tySet) and
             (not Procs[procIdx].Params[i].IsRef) and
             (not Procs[procIdx].Params[i].IsArray) then
          begin
            { Set by-value param: the arg value is the 32-byte set's ADDRESS —
              push all 8 words inline (mirrors i386) so the callee spill can
              rebuild the full set in its 32-byte param slot. One address word
              would leave the callee reading its own slot as set bytes. }
            IREmitNodeRISCV32(IRA[argNode]);        { a0 = set address }
            for j := 0 to 7 do
            begin
              rv32_lw(reg_t1, reg_a0, j * 4);
              rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_t1, reg_sp, 0);
            end;
            Inc(nArgs, 8);
          end
          else if (procIdx >= 0) and (not ProcExternal[procIdx]) and
             (i < Procs[procIdx].ParamCount) and
             ((Procs[procIdx].Params[i].TypeKind = tyInt64) or
              (Procs[procIdx].Params[i].TypeKind = tyUInt64)) and
             (not Procs[procIdx].Params[i].IsRef) and
             (not Procs[procIdx].Params[i].IsArray) then
          begin
            EmitNode64RISCV32(IRA[argNode]);        { a0=lo, a1=hi }
            rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);  { lo, word nArgs }
            rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a1, reg_sp, 0);  { hi, word nArgs+1 }
            Inc(nArgs, 2);
          end
          else if (procIdx >= 0) and (not ProcExternal[procIdx]) and
             (i >= Procs[procIdx].ParamCount) and
             Is64BitRISCV32(IntToTypeKind(IRTk[IRA[argNode]])) then
          begin
            { Variadic tail arg (past the named params) that is 64-bit (int64/
              uint64/double): push two words lo:hi, matching the callee reg-save +
              __pxx_va_arg_cross32's 8-byte step. Without this the high word was
              dropped and every later variadic arg shifted by one word. }
            EmitNode64RISCV32(IRA[argNode]);        { a0=lo, a1=hi }
            rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);
            rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a1, reg_sp, 0);
            Inc(nArgs, 2);
          end
          else
          begin
            IREmitNodeRISCV32(IRA[argNode]);
            { External C call: a Pascal string literal is stored as an 8-byte
              length prefix + NUL-terminated chars; pass the char data so the
              callee sees a const char*. }
            if ProcExternal[procIdx] and (IntToTypeKind(IRTk[argNode]) = tyString) then
              rv32_addi(reg_a0, reg_a0, 8);
            rv32_addi(reg_sp, reg_sp, -4);
            rv32_sw(reg_a0, reg_sp, 0);
            Inc(nArgs, 1);
          end;
          Inc(i);
          argNode := IRB[argNode];
        end;

        { Variadic stack tail (words 8..nArgs-1) was pushed in index order, so it
          lands REVERSED in memory (word nArgs-1 at [sp+0], word 8 highest). The
          callee reads variadic args with a FORWARD va_arg walk from overflow =
          s0+16, so reverse the (nArgs-8) low words in place. The eight register
          words (high offsets) and any hidden-dest word (deepest) are untouched.
          Mirrors the arm32 variadic-tail reversal (ir_codegen_arm32.inc). }
        if (procIdx >= 0) and ProcVariadic[procIdx] and (nArgs > 9) then
        begin
          elemSize := nArgs - 8;
          for i := 0 to (elemSize div 2) - 1 do
          begin
            j := i * 4;
            sz := (elemSize - 1 - i) * 4;
            rv32_lw(reg_t1, reg_sp, j);
            rv32_lw(reg_t2, reg_sp, sz);
            rv32_sw(reg_t2, reg_sp, j);
            rv32_sw(reg_t1, reg_sp, sz);
          end;
        end;

        if nArgs > 8 then
        begin
          { Words 8+ pass on the stack: keep the WHOLE pushed word block live
            across the call (the callee reads word k >= 8 at
            [entry_sp + (nArgs-1-k)*4], see the parser.inc rv32 param spill),
            load a0..a7 from their slots, and free everything after return. }
          for i := 0 to 7 do
            rv32_lw(reg_a0 + i, reg_sp, (nArgs - 1 - i) * 4);
          if (procIdx >= 0) and (not ProcExternal[procIdx]) and
             RetViaHiddenDest(Procs[procIdx].RetType) then
          begin
            rv32_lw(reg_t1, reg_sp, nArgs * 4);        { hidden dest (deepest) }
            EmitCallProc(procIdx);
            rv32_addi(reg_sp, reg_sp, (nArgs + 1) * 4);
          end
          else
          begin
            EmitCallProc(procIdx);
            rv32_addi(reg_sp, reg_sp, nArgs * 4);
          end;
          Exit;
        end;

        for i := 0 to nArgs - 1 do
          rv32_lw(reg_a0 + i, reg_sp, (nArgs - 1 - i) * 4);

        if (procIdx >= 0) and (not ProcExternal[procIdx]) and
           RetViaHiddenDest(Procs[procIdx].RetType) then
        begin
          rv32_lw(reg_t1, reg_sp, nArgs * 4);          { hidden dest (pushed deepest) }
          rv32_addi(reg_sp, reg_sp, (nArgs + 1) * 4);  { free args + hidden dest }
        end
        else if nArgs > 0 then
          rv32_addi(reg_sp, reg_sp, nArgs * 4);

        EmitCallProc(procIdx);
      end;

    IR_SYSCALL:
      begin
        { Raw linux syscall (hosted qemu-user): args (nr, a0..a5) pushed, then
          popped into a7 (number) and a0..a5. 32-bit result in a0,
          sign-extended into a0:a1 (Int64 result; negative = -errno). }
        argNode := IRA[node]; nArgs := 0;
        while argNode <> -1 do
        begin
          IREmitNodeRISCV32(IRA[argNode]);
          rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);
          Inc(nArgs);
          argNode := IRB[argNode];
        end;
        rv32_lw(reg_a7, reg_sp, (nArgs - 1) * 4);          { syscall number }
        for i := 1 to nArgs - 1 do
          rv32_lw(reg_a0 + i - 1, reg_sp, (nArgs - 1 - i) * 4);
        rv32_addi(reg_sp, reg_sp, nArgs * 4);
        EmitI32($00000073);                                { ecall }
        rv32_srai(reg_a1, reg_a0, 31);
      end;

    IR_WRITE, IR_WRITELN:
      begin
        if EspBareBoot then
        begin
          { Bare-metal: write/writeln does nothing (UART output is explicit
            MMIO in user code, see test_esp_bare.pas). }
        end
        else if IRKind[node] = IR_WRITELN then
        begin
          procIdx := FindProc('PXXWriteNL');
          if procIdx < 0 then Error('compiler error: PXXWriteNL not found');
          EmitCallProc(procIdx);
        end
        else
        begin
          { Hosted: route every write argument through the portable
            buffer-based builtin helpers (PXXWrite*W in builtinheap.pas) —
            no inline write codegen on this backend.
            See bug-riscv32-hosted-writeln-hello-hangs. }
          valNode := IRA[node];
          j := IRB[node];                    { field width, 0 = none }
          if IRKind[valNode] = IR_CONST_STR then
          begin
            sVal := GetTokenStrFromRaw(IRA[valNode], IRB[valNode]);
            si := InternStr(sVal);
            if (j > 0) and (j > Strs[si].Len) then
            begin
              EmitLoadImmRISCV32(reg_a0, j - Strs[si].Len);
              procIdx := FindProc('PXXWritePad');
              if procIdx < 0 then Error('compiler error: PXXWritePad not found');
              EmitCallProc(procIdx);
            end;
            if Strs[si].Len > 0 then
            begin
              { write(1, data+8, len) — inline syscall, no helper needed }
              EmitLoadImmRISCV32(reg_a0, 1);
              EmitLoadDataRefRISCV32(reg_a1, Strs[si].Offset + 8);
              EmitLoadImmRISCV32(reg_a2, Strs[si].Len);
              EmitLoadImmRISCV32(reg_a7, 64);          { __NR_write }
              EmitI32($00000073);                      { ecall }
            end;
          end
          else
          begin
            tk := IntToTypeKind(IRTk[node]);
            if IRC[node] = -3 then
            begin
              { write(PChar): NUL-terminated C string }
              IREmitNodeRISCV32(valNode);
              procIdx := FindProc('PXXWriteCStr');
              if procIdx < 0 then Error('compiler error: PXXWriteCStr not found');
              EmitCallProc(procIdx);
            end
            else if TypeIsFloat(tk) then
            begin
              { a0:a1 = double bits; pass their stack address to the portable
                float writers (which format via write()-free helpers here). }
              EmitFloatOperandRISCV32(valNode, tyDouble);
              rv32_addi(reg_sp, reg_sp, -8);
              rv32_sw(reg_a0, reg_sp, 0);
              rv32_sw(reg_a1, reg_sp, 4);
              rv32_addi(reg_a0, reg_sp, 0);            { a0 = &double }
              i := IRC[node];                          { decimals }
              if i >= 0 then
              begin
                EmitLoadImmRISCV32(reg_a1, i);
                procIdx := FindProc('PXXWriteFloatFixed');
              end
              else if i = -2 then
                procIdx := FindProc('PXXWriteFloatNat')
              else
                procIdx := FindProc('PXXWriteFloatSci');
              if procIdx < 0 then Error('compiler error: float writer not found');
              EmitCallProc(procIdx);
              rv32_addi(reg_sp, reg_sp, 8);
            end
            else if tk = tyChar then
            begin
              IREmitNodeRISCV32(valNode);
              EmitLoadImmRISCV32(reg_a1, j);
              procIdx := FindProc('PXXWriteCharW');
              if procIdx < 0 then Error('compiler error: PXXWriteCharW not found');
              EmitCallProc(procIdx);
            end
            else if tk = tyBoolean then
            begin
              IREmitNodeRISCV32(valNode);
              EmitLoadImmRISCV32(reg_a1, j);
              procIdx := FindProc('PXXWriteBoolW');
              if procIdx < 0 then Error('compiler error: PXXWriteBoolW not found');
              EmitCallProc(procIdx);
            end
            else if tk = tyAnsiString then
            begin
              IREmitNodeRISCV32(valNode);              { a0 = handle }
              EmitLoadImmRISCV32(reg_a1, j);
              procIdx := FindProc('PXXWriteStrMW');
              if procIdx < 0 then Error('compiler error: PXXWriteStrMW not found');
              EmitCallProc(procIdx);
            end
            else if TypeIsFrozenString(tk) then
            begin
              IREmitNodeRISCV32(valNode);              { a0 = buffer addr }
              EmitLoadImmRISCV32(reg_a1, j);
              procIdx := FindProc('PXXWriteFrozenW');
              if procIdx < 0 then Error('compiler error: PXXWriteFrozenW not found');
              EmitCallProc(procIdx);
            end
            else if Is64BitRISCV32(tk) or TypeIsOrdinal(tk) or (tk = tyUnknown) then
            begin
              { PXXWriteDecW(v: Int64; uns, wid) — v = a0:a1 (2 words) }
              if Is64BitRISCV32(tk) then
                EmitNode64RISCV32(valNode)             { a0:a1 = value }
              else
              begin
                IREmitNodeRISCV32(valNode);
                if (tk <> tyUnknown) and not TypeSigned(tk) then
                  EmitLoadImmRISCV32(reg_a1, 0)        { zero-extend }
                else
                  rv32_srai(reg_a1, reg_a0, 31);       { sign-extend }
              end;
              if (tk <> tyUnknown) and not TypeSigned(tk) then
                EmitLoadImmRISCV32(reg_a2, 1)
              else
                EmitLoadImmRISCV32(reg_a2, 0);
              EmitLoadImmRISCV32(reg_a3, j);
              procIdx := FindProc('PXXWriteDecW');
              if procIdx < 0 then Error('compiler error: PXXWriteDecW not found');
              EmitCallProc(procIdx);
            end
            else
              Error('target riscv32: write of this type not supported (hosted)');
          end;
        end;
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
        procIdx := FindProc('PXXMemZero');
        if procIdx < 0 then Error('compiler error: PXXMemZero not found');
        EmitCallProc(procIdx);
      end;

    IR_COPY_REC:
      begin
        { Whole-record copy: PXXMemMove(dest, src, count). ESP has no managed
          record fields yet, so the plain byte move is correct (no per-field ARC). }
        IREmitNodeRISCV32(IRB[node]);            { a0 = src }
        rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);
        IREmitNodeRISCV32(IRA[node]);            { a0 = dest }
        rv32_lw(reg_a1, reg_sp, 0); rv32_addi(reg_sp, reg_sp, 4);   { a1 = src }
        EmitLoadImmRISCV32(reg_a2, Integer(IRIVal[node]));          { a2 = count }
        procIdx := FindProc('PXXMemMove');
        if procIdx < 0 then Error('compiler error: PXXMemMove not found');
        EmitCallProc(procIdx);
      end;

    IR_NEG:
      begin
        tk := IntToTypeKind(IRTk[node]);
        if tk = tyDouble then
        begin
          { Float negate = flip the IEEE sign bit (bit 63 = bit 31 of the hi
            word), NOT an integer negate. }
          EmitNode64RISCV32(IRA[node]);          { a0:a1 = double bits }
          EmitLoadImmRISCV32(reg_t0, Integer($80000000));
          rv32_xor(reg_a1, reg_a1, reg_t0);
        end
        else if tk = tySingle then
        begin
          IREmitNodeRISCV32(IRA[node]);          { a0 = single bits }
          EmitLoadImmRISCV32(reg_t0, Integer($80000000));
          rv32_xor(reg_a0, reg_a0, reg_t0);
        end
        else if Is64BitRISCV32(tk) then
        begin
          { Full 64-bit two's-complement negate: lo' = 0-lo, hi' = 0-hi-borrow
            (borrow = lo <> 0). Was low-word-only — unary minus on a runtime
            Int64 left the high word stale (surfaced as garbage decimals from
            PXXWriteDecW's u := -v). }
          EmitNode64RISCV32(IRA[node]);          { a0:a1 = value }
          rv32_sltu(reg_t1, reg_zero, reg_a0);   { borrow = lo <> 0 }
          rv32_sub(reg_a0, reg_zero, reg_a0);
          rv32_sub(reg_a1, reg_zero, reg_a1);
          rv32_sub(reg_a1, reg_a1, reg_t1);
        end
        else
        begin
          IREmitNodeRISCV32(IRA[node]);
          rv32_sub(reg_a0, reg_zero, reg_a0);
        end;
      end;

    IR_NOT:
      begin
        { Type-directed, mirroring i386/aarch64: bitwise complement for an
          integer/ordinal operand, boolean (low-bit) flip only for a Boolean.
          RISC-V has no `not`; `xori reg, -1` is the full-width complement (the
          12-bit immediate -1 sign-extends to all ones). }
        if Is64BitRISCV32(IntToTypeKind(IRTk[node])) then
        begin
          EmitNode64RISCV32(IRA[node]);              { a0:a1 = value }
          rv32_xori(reg_a0, reg_a0, -1);
          rv32_xori(reg_a1, reg_a1, -1);
        end
        else if TypeIsOrdinal(IntToTypeKind(IRTk[node])) and
                (IntToTypeKind(IRTk[node]) <> tyBoolean) then
        begin
          IREmitNodeRISCV32(IRA[node]);
          rv32_xori(reg_a0, reg_a0, -1);
        end
        else
        begin
          IREmitNodeRISCV32(IRA[node]);
          rv32_xori(reg_a0, reg_a0, 1);
        end;
      end;

    IR_CALL_IND:
      begin
        if IRCallDest[node] >= 0 then
          Error('target riscv32: aggregate/frozen-string result via an indirect call is not yet supported (feature-cross-virtual-indirect-hidden-dest)');
        { Indirect call through a proc-typed value (e.g. the PXXDivZeroHook
          runtime hook). v1 mirrors arm32: scalar word args only (no by-value
          Int64/float marshalling through a proc pointer yet). Push the callee
          first (deepest), push arg words, load a0.. from the slots, load the
          callee into t0, drop the block, jalr through t0. }
        IREmitNodeRISCV32(IRA[node]);      { a0 = callee address }
        rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);
        argNode := IRB[node];
        nArgs := 0;
        while argNode <> -1 do
        begin
          IREmitNodeRISCV32(IRA[argNode]);
          rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);
          Inc(nArgs);
          argNode := IRB[argNode];
        end;
        if nArgs > 8 then
          Error('target riscv32: indirect call with more than 8 argument words not supported');
        for i := 0 to nArgs - 1 do
          rv32_lw(reg_a0 + i, reg_sp, (nArgs - 1 - i) * 4);
        rv32_lw(reg_t0, reg_sp, nArgs * 4);              { callee (deepest) }
        rv32_addi(reg_sp, reg_sp, (nArgs + 1) * 4);      { drop args + callee }
        rv32_jalr(reg_ra, reg_t0, 0);
      end;

    IR_SET_LIT:
      EmitLoadDataRefRISCV32(reg_a0, Integer(IRIVal[node]));  { a0 = set blob addr }

    IR_SET_COPY:
      begin
        { Copy the 32-byte set from src (IRB) to dest (IRA), 8 words. }
        IREmitNodeRISCV32(IRB[node]);            { a0 = source addr }
        rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);
        IREmitNodeRISCV32(IRA[node]);            { a0 = dest addr }
        rv32_lw(reg_a1, reg_sp, 0); rv32_addi(reg_sp, reg_sp, 4);   { a1 = src }
        for i := 0 to 7 do
        begin
          rv32_lw(reg_t0, reg_a1, i * 4);
          rv32_sw(reg_t0, reg_a0, i * 4);
        end;
      end;

    IR_SET_BINOP:
      begin
        { Set +/-/* over 8 words into the BSS scratch (IRIVal). }
        IREmitNodeRISCV32(IRA[node]);            { a0 = lhs addr }
        rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);
        IREmitNodeRISCV32(IRB[node]);            { a0 = rhs addr }
        rv32_addi(reg_a1, reg_a0, 0);            { a1 = rhs }
        rv32_lw(reg_a0, reg_sp, 0); rv32_addi(reg_sp, reg_sp, 4);   { a0 = lhs }
        EmitLoadGlobAddrRISCV32(reg_a2, Integer(IRIVal[node]));     { a2 = scratch }
        for i := 0 to 7 do
        begin
          rv32_lw(reg_t0, reg_a0, i * 4);
          rv32_lw(reg_t1, reg_a1, i * 4);
          if IntToTokenKind(IRC[node]) = tkPlus then
            rv32_or(reg_t0, reg_t0, reg_t1)
          else if IntToTokenKind(IRC[node]) = tkStar then
            rv32_and(reg_t0, reg_t0, reg_t1)
          else if IntToTokenKind(IRC[node]) = tkMinus then
          begin
            rv32_xori(reg_t1, reg_t1, -1);       { not rhs }
            rv32_and(reg_t0, reg_t0, reg_t1);
          end;
          rv32_sw(reg_t0, reg_a2, i * 4);
        end;
        rv32_addi(reg_a0, reg_a2, 0);            { result addr }
      end;

    IR_SET_CMP:
      begin
        { Compare two 32-byte sets. t3 = accumulated differences, t4 =
          subset-direction violations (mirrors the aarch64 shape, 8 words). }
        IREmitNodeRISCV32(IRA[node]);            { a0 = lhs addr }
        rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);
        IREmitNodeRISCV32(IRB[node]);            { a0 = rhs addr }
        rv32_addi(reg_a1, reg_a0, 0);            { a1 = rhs }
        rv32_lw(reg_a0, reg_sp, 0); rv32_addi(reg_sp, reg_sp, 4);   { a0 = lhs }
        rv32_addi(reg_t3, reg_zero, 0);          { differences }
        rv32_addi(reg_t4, reg_zero, 0);          { violations }
        for i := 0 to 7 do
        begin
          rv32_lw(reg_t0, reg_a0, i * 4);        { lhs word }
          rv32_lw(reg_t1, reg_a1, i * 4);        { rhs word }
          rv32_xor(reg_t2, reg_t0, reg_t1);
          rv32_or(reg_t3, reg_t3, reg_t2);
          if (IRC[node] = Ord(tkLe)) or (IRC[node] = Ord(tkLt)) then
          begin
            rv32_xori(reg_t2, reg_t1, -1);       { not rhs }
            rv32_and(reg_t2, reg_t0, reg_t2);    { lhs and not rhs }
            rv32_or(reg_t4, reg_t4, reg_t2);
          end
          else if (IRC[node] = Ord(tkGe)) or (IRC[node] = Ord(tkGt)) then
          begin
            rv32_xori(reg_t2, reg_t0, -1);       { not lhs }
            rv32_and(reg_t2, reg_t1, reg_t2);    { rhs and not lhs }
            rv32_or(reg_t4, reg_t4, reg_t2);
          end;
        end;
        if IRC[node] = Ord(tkEq) then
          rv32_sltiu(reg_a0, reg_t3, 1)          { diffs = 0 }
        else if IRC[node] = Ord(tkNeq) then
        begin
          rv32_sltu(reg_a0, reg_zero, reg_t3);   { diffs <> 0 }
        end
        else if (IRC[node] = Ord(tkLe)) or (IRC[node] = Ord(tkGe)) then
          rv32_sltiu(reg_a0, reg_t4, 1)          { no violations }
        else
        begin
          { tkLt / tkGt: proper = subset AND unequal }
          rv32_sltiu(reg_t0, reg_t4, 1);
          rv32_sltu(reg_t1, reg_zero, reg_t3);
          rv32_and(reg_a0, reg_t0, reg_t1);
        end;
      end;

    IR_READLINE:
      begin
        procIdx := FindProc('PXXReadLine');
        if procIdx < 0 then Error('compiler error: PXXReadLine not found');
        EmitCallProc(procIdx);
      end;

    IR_READ_DISCARD:
      begin
        procIdx := FindProc('PXXReadDiscard');
        if procIdx < 0 then Error('compiler error: PXXReadDiscard not found');
        EmitCallProc(procIdx);
      end;

    IR_READ_VAR:
      begin
        { Parse one read/readln target from the shared line buffer via the
          portable builtin helpers. A managed string wants its SLOT address —
          force lvalue-write mode (mirrors the other backends). }
        tk := IntToTypeKind(IRTk[node]);
        if tk = tyAnsiString then
        begin
          savedLVW := InLValueWrite;
          InLValueWrite := True;
          IREmitNodeRISCV32(IRA[node]);    { a0 = slot address }
          InLValueWrite := savedLVW;
          procIdx := FindProc('PXXReadVarStrM');
          if procIdx < 0 then Error('compiler error: PXXReadVarStrM not found');
          EmitCallProc(procIdx);
        end
        else if tk = tyChar then
        begin
          IREmitNodeRISCV32(IRA[node]);    { a0 = target address }
          procIdx := FindProc('PXXReadVarChar');
          if procIdx < 0 then Error('compiler error: PXXReadVarChar not found');
          EmitCallProc(procIdx);
        end
        else if TypeIsOrdinal(tk) then
        begin
          IREmitNodeRISCV32(IRA[node]);    { a0 = target address }
          EmitLoadImmRISCV32(reg_a1, TypeSize(tk));
          procIdx := FindProc('PXXReadVarInt');
          if procIdx < 0 then Error('compiler error: PXXReadVarInt not found');
          EmitCallProc(procIdx);
        end
        else
          Error('target riscv32: read/readln target type not supported');
      end;

    IR_VIRTUAL_CALL:
      begin
        if IRCallDest[node] >= 0 then
          Error('target riscv32: aggregate/frozen-string result via a virtual call is not yet supported (feature-cross-virtual-indirect-hidden-dest)');
        { VMT dispatch. IRA=first arg, IRB=last arg, IRC=proc idx, IRIVal=slot.
          Word-push args (Self = word 0, deepest), load a0.., load the VMT
          pointer from [Self], call through [VMT + slot*8] (8-byte data slots,
          address in the low word — mirrors arm32). }
        argNode := IRA[node];
        nArgs := 0;
        while argNode <> -1 do
        begin
          IREmitNodeRISCV32(IRA[argNode]);
          rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);
          Inc(nArgs);
          argNode := IRB[argNode];
        end;
        if nArgs > 8 then
          Error('target riscv32: virtual call with more than 8 parameter words not supported');
        for i := 0 to nArgs - 1 do
          rv32_lw(reg_a0 + i, reg_sp, (nArgs - 1 - i) * 4);
        rv32_addi(reg_sp, reg_sp, nArgs * 4);
        rv32_lw(reg_t1, reg_a0, 0);                     { VMT pointer }
        rv32_lw(reg_t1, reg_t1, Integer(IRIVal[node]) * 8);
        rv32_jalr(reg_ra, reg_t1, 0);
      end;

    IR_SETLEN_STR:
      begin
        { SetLength(ansistring-lvalue, n) -> PXXStrSetLen(slotAddr, n). IRA =
          slot-address node, IRB = new length. Address-based, so a record/var-
          param field needs no symbol reconstruction. }
        IREmitNodeRISCV32(IRA[node]);      { a0 = slot address }
        rv32_addi(reg_sp, reg_sp, -4); rv32_sw(reg_a0, reg_sp, 0);  { push slot }
        IREmitNodeRISCV32(IRB[node]);      { a0 = n }
        rv32_addi(reg_a1, reg_a0, 0);      { a1 = n }
        rv32_lw(reg_a0, reg_sp, 0); rv32_addi(reg_sp, reg_sp, 4);   { pop slot -> a0 }
        procIdx := FindProc('PXXStrSetLen');
        if procIdx < 0 then Error('compiler error: PXXStrSetLen not found');
        EmitCallProc(procIdx);
      end;

    else
      Error('target riscv32: unsupported node in IR codegen: ' + IROpName(IRKind[node]));
  end;
end;

procedure IREmitMachineCodeRISCV32;
var i, lblId, pos, targetOffset, f, si, procIdx: Integer;
    LabelFixupCount: Integer;
begin
  { Nil-init hidden owning locals synthesised for materialised managed-string
    arguments (e.g. the concat temp in `raise E.Create('x: ' + c)`). They are
    created during this body's IR lowering, AFTER the parser's prologue
    zero-init pass, so they would otherwise hold stale stack bytes; the
    epilogue's scope-exit DecRef would then release garbage and segfault
    whenever the temp's own path never ran (the chess SetFEN crash). Mirrors
    the x86-64/i386/arm32/aarch64 walkers. }
  if CurProc >= 0 then
    for i := Procs[CurProc].ScopeBase to SymCount - 1 do
      if SymIsHiddenArgTemp[i] and (Syms[i].Kind = skLocal) then
      begin
        if (Syms[i].TypeKind = tyRecord) and not Syms[i].IsArray and
           (RecSize(Syms[i].RecName) > TARGET_PTR_SIZE) then
        begin
          EmitSlotAddrRISCV32(reg_a0, i);
          EmitLoadImmRISCV32(reg_a1, RecSize(Syms[i].RecName));
          procIdx := FindProc('PXXMemZero');
          if procIdx < 0 then Error('compiler error: PXXMemZero not found');
          EmitCallProc(procIdx);
        end
        else
        begin
          EmitSlotAddrRISCV32(reg_t0, i);
          rv32_sw(reg_zero, reg_t0, 0);
        end;
      end;
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
            if LabelFixupCount >= MAX_IR then Error('label fixup overflow');
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitAsmRv32('jal zero, 0');
          end;
        end;

      IR_JUMP_IF_FALSE:
        begin
          { bne-skip + jal, NOT a lone beq: B-type immediates reach only
            +-4KB, and a large routine (a flattened stackless generator, a big
            MakeMove) silently TRUNCATED the offset — branches landed inside
            unrelated code (chess perft counted 164). jal reaches +-1MB. }
          lblId := IRA[i];
          IREmitNodeRISCV32(IRB[i]);
          EmitI32($00051463);                       { bne a0, zero, +8 }
          if LabelPositions[lblId] <> -1 then
            EmitI32(EncodeRISCVJAL(reg_zero, LabelPositions[lblId] - CodeLen))
          else
          begin
            if LabelFixupCount >= MAX_IR then Error('label fixup overflow');
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitI32(EncodeRISCVJAL(reg_zero, 0));
          end;
        end;

      IR_EXC_ENTER:
        begin
          { try: push a 32-byte frame ([0]=prev EXC_TOP, jmpbuf at +8), chain
            it, setjmp; a raise longjmps back here with a0=1 -> jump to the
            handler label (beq-skip + jal, so the handler can be far). }
          lblId := IRA[i];
          rv32_addi(reg_sp, reg_sp, -EXC_FRAME_SIZE_RV32);
          EmitLoadGlobAddrRISCV32(reg_t1, BSS_EXC_TOP);
          rv32_lw(reg_t2, reg_t1, 0);
          rv32_sw(reg_t2, reg_sp, 0);
          rv32_sw(reg_sp, reg_t1, 0);
          rv32_addi(reg_a0, reg_sp, EXC_JMP_OFFSET_RV32);
          EmitI32(EncodeRISCVJAL(reg_ra, ExcSetJmpAddr - CodeLen));
          rv32_beq(reg_a0, reg_zero, 8);            { 0 = normal path: skip }
          if LabelPositions[lblId] <> -1 then
            EmitI32(EncodeRISCVJAL(reg_zero, LabelPositions[lblId] - CodeLen))
          else
          begin
            if LabelFixupCount >= MAX_IR then Error('label fixup overflow');
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitI32(EncodeRISCVJAL(reg_zero, 0));
          end;
        end;

      IR_EXC_LEAVE:
        IREmitLeaveExceptionFramesRISCV32(IRA[i]);

      IR_RAISE:
        begin
          if IRA[i] <> -1 then
          begin
            IREmitNodeRISCV32(IRA[i]);              { a0 = exception object }
            EmitLoadGlobAddrRISCV32(reg_t1, BSS_EXC_OBJ);
            rv32_sw(reg_a0, reg_t1, 0);
            EmitLoadImmRISCV32(reg_a0, Integer(IRIVal[i]));   { class idx }
            EmitLoadGlobAddrRISCV32(reg_t1, BSS_EXC_CLS);
            rv32_sw(reg_a0, reg_t1, 0);
          end;
          EmitI32(EncodeRISCVJAL(reg_ra, ExcRaiseAddr - CodeLen));
        end;

      IR_EXC_STORE:
        begin
          { `on E: EFoo do`: store the raised object into E's slot. }
          si := IRA[i];
          EmitLoadGlobAddrRISCV32(reg_t1, BSS_EXC_OBJ);
          rv32_lw(reg_t2, reg_t1, 0);
          EmitSlotAddrRISCV32(reg_t0, si);
          rv32_sw(reg_t2, reg_t0, 0);
        end;

      IR_EXC_MATCH:
        begin
          { jump to the label when the raised class <> this clause's class }
          lblId := IRA[i];
          EmitLoadGlobAddrRISCV32(reg_t1, BSS_EXC_CLS);
          rv32_lw(reg_t2, reg_t1, 0);
          EmitLoadImmRISCV32(reg_t0, Integer(IRIVal[i]));
          rv32_xor(reg_t2, reg_t2, reg_t0);
          rv32_sltiu(reg_a0, reg_t2, 1);            { a0 = equal }
          rv32_beq(reg_a0, reg_zero, 8);            { equal=0 -> take the jal }
          rv32_jal(reg_zero, 8);                    { equal: skip the jal }
          if LabelPositions[lblId] <> -1 then
            EmitI32(EncodeRISCVJAL(reg_zero, LabelPositions[lblId] - CodeLen))
          else
          begin
            if LabelFixupCount >= MAX_IR then Error('label fixup overflow');
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitI32(EncodeRISCVJAL(reg_zero, 0));
          end;
        end;

      IR_EXC_MATCH_HIT:
        begin
          { jump to the label when the raised class = this clause's class }
          lblId := IRA[i];
          EmitLoadGlobAddrRISCV32(reg_t1, BSS_EXC_CLS);
          rv32_lw(reg_t2, reg_t1, 0);
          EmitLoadImmRISCV32(reg_t0, Integer(IRIVal[i]));
          rv32_xor(reg_t2, reg_t2, reg_t0);
          rv32_sltiu(reg_a0, reg_t2, 1);            { a0 = equal }
          rv32_beq(reg_a0, reg_zero, 8);            { not equal: skip the jal }
          if LabelPositions[lblId] <> -1 then
            EmitI32(EncodeRISCVJAL(reg_zero, LabelPositions[lblId] - CodeLen))
          else
          begin
            if LabelFixupCount >= MAX_IR then Error('label fixup overflow');
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitI32(EncodeRISCVJAL(reg_zero, 0));
          end;
        end;

      IR_EXC_CLEAR:
        begin
          EmitLoadGlobAddrRISCV32(reg_t1, BSS_EXC_OBJ);
          rv32_sw(reg_zero, reg_t1, 0);
          EmitLoadGlobAddrRISCV32(reg_t1, BSS_EXC_CLS);
          rv32_sw(reg_zero, reg_t1, 0);
        end;

      IR_CALL:
        begin
          if IRIVal[i] = 1 then
            IREmitNodeRISCV32(i);
        end;

      IR_CALL_IND:
        begin
          if IRStmtRoot[i] then
            IREmitNodeRISCV32(i);
        end;

      IR_VIRTUAL_CALL:
        begin
          if IRStmtRoot[i] then
            IREmitNodeRISCV32(i);
        end;

      IR_STORE_SYM, IR_WRITE, IR_WRITELN:
        IREmitNodeRISCV32(i);

      IR_NOP, IR_CONST_STR, IR_CONST_INT, IR_BLOCK,
      IR_LOAD_SYM, IR_LOAD_MEM, IR_BINOP, IR_NEG, IR_NOT, IR_ARG, IR_LEA, IR_SYSCALL,
      IR_SET_LIT, IR_SET_BINOP, IR_SET_CMP, IR_CONST_DATA,
      IR_SLOTADDR, IR_FIELD, IR_INDEX: ;
      { IR_LOAD_MEM: pure value node — statement-level emit re-runs its address
        operand (`*f()` calls f twice). See aarch64 note. }

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
