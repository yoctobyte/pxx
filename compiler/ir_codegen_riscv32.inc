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
  else if op = Ord(tkIdent) then   { 'shr' parses as ident; logical on Int64/UInt64 }
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
      Error('target riscv32: Int64-to-float conversion not yet supported');
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
           ((IntToTypeKind(IRTk[left]) = tyAnsiString) or (IntToTypeKind(IRTk[right]) = tyAnsiString)) then
        begin
          { Managed-string equality -> PXXStrEq(lenA, srcA, lenB, srcB) -> 1/0. }
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
        else if op = Ord(tkDiv) then rv32_div(reg_a0, reg_a0, reg_a1)
        else if op = Ord(tkMod) then rv32_rem(reg_a0, reg_a0, reg_a1)
        else if op = Ord(tkAnd) then rv32_and(reg_a0, reg_a0, reg_a1)
        else if op = Ord(tkOr) then rv32_or(reg_a0, reg_a0, reg_a1)
        else if op = Ord(tkXor) then rv32_xor(reg_a0, reg_a0, reg_a1)
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
        procIdx := IRA[node];
        if procIdx = -Ord(tkGetMem) then
        begin
          { GetMem / New. Class instantiation (VMT + ctor) is a later step. }
          if IRC[node] >= REC_UCLASS_BASE then
            Error('target riscv32: class instantiation not yet supported');
          argNode := IRB[node];               { size arg }
          IREmitNodeRISCV32(IRA[argNode]);    { size -> a0 }
          EmitHeapAllocLockedRISCV32;         { a0 = payload pointer }
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
            Error('target riscv32: SetLength on a var-array parameter not yet supported');
          EmitSlotAddrRISCV32(reg_a0, si);    { a0 = slot address (not the handle) }
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
          Error('target riscv32: standard builtin calls not supported in bare-metal stage 1');
        end;

        { Word-based argument passing (matches the callee spill in parser.inc):
          each scalar arg is one word, a by-value Int64/UInt64 is two (lo then
          hi). nArgs counts WORDS here; word k is pushed in index order so it
          lands at [sp + (nWords-1-k)*4], then loads into a[k] (<=8 words). }
        argNode := IRB[node];
        nArgs := 0;     { word count }
        i := 0;         { argument index }
        while argNode <> -1 do
        begin
          if (procIdx >= 0) and (not ProcExternal[procIdx]) and
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

        if nArgs > 8 then
          Error('target riscv32: more than 8 call argument words not supported yet');

        for i := 0 to nArgs - 1 do
          rv32_lw(reg_a0 + i, reg_sp, (nArgs - 1 - i) * 4);

        if nArgs > 0 then
          rv32_addi(reg_sp, reg_sp, nArgs * 4);

        EmitCallProc(procIdx);
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
        procIdx := FindProc('PXXMemZero');
        if procIdx < 0 then Error('compiler error: PXXMemZero not found');
        EmitCallProc(procIdx);
      end;

    IR_NEG:
      begin
        { LANDMINE: low-word-only — negates a0, ignores a1, so unary minus on a
          runtime Int64/UInt64 is WRONG (high word stale). Harmless for softfloat
          (never negates an Int64), so left as-is. The xtensa twin handles 64-bit
          (EmitNode64Xtensa + borrow); mirror that here when esp-float needs it. }
        IREmitNodeRISCV32(IRA[node]);
        rv32_sub(reg_a0, reg_zero, reg_a0);
      end;

    IR_NOT:
      begin
        { Same low-word-only caveat as IR_NEG for 64-bit bitwise not. }
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
