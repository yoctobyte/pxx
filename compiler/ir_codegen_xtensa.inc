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

procedure XtensaPush64;
{ Spill the 64-bit value in a2:a3 (lo at the lower address) to two expr-stack
  slots, same discipline as XtensaPushA2 (windowed: constant sp + XtSpillDepth;
  Call0: moving sp). }
begin
  if XtensaABI = XTENSA_ABI_WINDOWED then
  begin
    if XtSpillDepth + 8 > XT_EXPR_REGION then
      Error('target xtensa: expression/argument stack exceeds reserved frame');
    xtensa_s32i(reg_xtensa_a2, reg_xtensa_sp, XtSpillDepth);
    xtensa_s32i(reg_xtensa_a3, reg_xtensa_sp, XtSpillDepth + 4);
    Inc(XtSpillDepth, 8);
  end
  else
  begin
    xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, -8);
    xtensa_s32i(reg_xtensa_a2, reg_xtensa_sp, 0);
    xtensa_s32i(reg_xtensa_a3, reg_xtensa_sp, 4);
  end;
end;

procedure XtensaPop64ToA4A5;
{ Pop the top 64-bit expr-stack slot into a4:a5 (lo:hi). }
begin
  if XtensaABI = XTENSA_ABI_WINDOWED then
  begin
    Dec(XtSpillDepth, 8);
    xtensa_l32i(reg_xtensa_a4, reg_xtensa_sp, XtSpillDepth);
    xtensa_l32i(reg_xtensa_a5, reg_xtensa_sp, XtSpillDepth + 4);
  end
  else
  begin
    xtensa_l32i(reg_xtensa_a4, reg_xtensa_sp, 0);
    xtensa_l32i(reg_xtensa_a5, reg_xtensa_sp, 4);
    xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, 8);
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
var procIdx: Integer;
begin
  procIdx := FindProc('PXXAlloc');
  if procIdx < 0 then Error('compiler error: Alloc helper not found in builtin unit');
  if XtensaABI = XTENSA_ABI_WINDOWED then
  begin
    xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);   { arg0 = size }
    xtensa_movi(reg_xtensa_a11, 8);              { arg1 = align }
    EmitCallProc(procIdx);
    xtensa_mov(reg_xtensa_a2, reg_xtensa_a10);   { result }
  end
  else
  begin
    xtensa_movi(reg_xtensa_a3, 8);               { a2 = size already; arg1 = align }
    EmitCallProc(procIdx);                            { result in a2 }
  end;
end;

procedure EmitHeapFreeLockedXtensa;
{ a2 = payload pointer -> PXXFree(p). nil ignored inside. }
var procIdx: Integer;
begin
  procIdx := FindProc('PXXFree');
  if procIdx < 0 then Error('compiler error: Free helper not found in builtin unit');
  if XtensaABI = XTENSA_ABI_WINDOWED then
    xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);
  EmitCallProc(procIdx);
end;

procedure EmitStrFromLitXtensa;
{ a2 = len, a3 = src -> a2 = new managed-string handle (PXXStrFromLit). }
var procIdx: Integer;
begin
  procIdx := FindProc('PXXStrFromLit');
  if procIdx < 0 then Error('compiler error: PXXStrFromLit not found');
  if XtensaABI = XTENSA_ABI_WINDOWED then
  begin
    xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);   { arg0 = len }
    xtensa_mov(reg_xtensa_a11, reg_xtensa_a3);   { arg1 = src }
    EmitCallProc(procIdx);
    xtensa_mov(reg_xtensa_a2, reg_xtensa_a10);   { handle }
  end
  else
    EmitCallProc(procIdx);                            { a2=len, a3=src; result a2 }
end;

procedure EmitStrRefCallXtensa(const name: AnsiString);
{ a2 = handle -> call proc(handle). a2 is NOT preserved (DecRef path). }
var procIdx: Integer;
begin
  procIdx := FindProc(name);
  if procIdx < 0 then Error('compiler error: string refcount helper not found');
  if XtensaABI = XTENSA_ABI_WINDOWED then
    xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);
  EmitCallProc(procIdx);
end;

procedure EmitXtensaSoftDivCall(const name: AnsiString);
{ a2 = dividend (arg0), a3 = divisor (arg1) -> call helper -> result in a2.
  LX6 software div/mod path (--xtensa-cpu=lx6). }
var procIdx: Integer;
begin
  procIdx := FindProc(name);
  if procIdx < 0 then Error('compiler error: xtensa soft-divide helper not found');
  if XtensaABI = XTENSA_ABI_WINDOWED then
  begin
    xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);
    xtensa_mov(reg_xtensa_a11, reg_xtensa_a3);
    EmitCallProc(procIdx);
    xtensa_mov(reg_xtensa_a2, reg_xtensa_a10);
  end
  else
    EmitCallProc(procIdx);   { a2, a3 already hold arg0, arg1; result in a2 }
end;

procedure IREmitNodeXtensa(node: Integer); forward;

{ ===== 64-bit (Int64/UInt64) value model: a2:a3 = lo:hi register pair =====
  True 8-byte values live in a2(low):a3(high) in flight, are loaded/stored as two
  words, and have their own arithmetic/shift/compare sequences. Xtensa has no
  condition flags (like riscv/arm), so carries/borrows are computed via the
  unsigned branches bgeu/bltu. Mirrors the riscv32 a0:a1 / arm32 r0:r1 models. A
  32-bit source widens into a3 (sign/zero-ext). Scratch: a4:a5 = popped left
  operand, a6/a8..a14 = temporaries (a7 is the windowed frame pointer, a15 the
  Call0 frame pointer — both avoided). The MSB of a word is extracted with `srl`
  after presetting SAR=31 (no EXTUI needed). }

function Is64BitXtensa(tk: TTypeKind): Boolean;
begin
  { Double occupies an a2:a3 pair / 8-byte slot, same shape as Int64 — the
    value-model paths (const/load/store) treat it as 64-bit. Float arithmetic is
    dispatched separately (IsFloatXtensa, checked first). }
  Result := (tk = tyInt64) or (tk = tyUInt64) or (tk = tyDouble);
end;

function IsFloatXtensa(tk: TTypeKind): Boolean;
begin
  Result := (tk = tySingle) or (tk = tyDouble);
end;

procedure EmitLoadConst64Xtensa(v: Int64);
begin
  EmitLoadConstXtensa(reg_xtensa_a2, Integer(v and $FFFFFFFF));
  EmitLoadConstXtensa(reg_xtensa_a3, Integer((v shr 32) and $FFFFFFFF));
end;

procedure EmitSlotAddr64Xtensa(rd, idx: Integer);
{ rd = address of an 8-byte slot (global abs / frame-relative; ref forwarded). }
begin
  if Syms[idx].Kind = skGlobal then
    EmitLoadGlobAddrXtensa(rd, Syms[idx].Offset)
  else
  begin
    EmitFrameAddrXtensa(rd, Syms[idx].Offset);
    if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then
      xtensa_l32i(rd, rd, 0);
  end;
end;

procedure EmitLoadVar64Xtensa(idx: Integer);
begin
  EmitSlotAddr64Xtensa(reg_xtensa_a8, idx);
  xtensa_l32i(reg_xtensa_a2, reg_xtensa_a8, 0);   { lo }
  xtensa_l32i(reg_xtensa_a3, reg_xtensa_a8, 4);   { hi }
end;

procedure EmitStoreVar64Xtensa(idx: Integer);
begin
  EmitSlotAddr64Xtensa(reg_xtensa_a8, idx);       { value in a2:a3; addr in a8 }
  xtensa_s32i(reg_xtensa_a2, reg_xtensa_a8, 0);   { lo }
  xtensa_s32i(reg_xtensa_a3, reg_xtensa_a8, 4);   { hi }
end;

procedure EmitNode64Xtensa(node: Integer);
{ Emit node; guarantee its full 64-bit value sits in a2:a3, widening a 32-bit
  source (sign-extend signed, zero-extend unsigned) into a3. }
var ntk: TTypeKind;
begin
  IREmitNodeXtensa(node);
  ntk := IntToTypeKind(IRTk[node]);
  if not Is64BitXtensa(ntk) then
  begin
    if TypeSigned(ntk) then
      { a3 := (a2 < 0) ? -1 : 0 }
      EmitAsmXtensa(['movi a3, 0', 'bge a2, a3, .pos', 'movi a3, -1', '.pos:'])
    else
      xtensa_movi(reg_xtensa_a3, 0);
  end;
end;

procedure EmitUDivMod64Xtensa(wantMod: Boolean);
{ Unsigned 64-bit divide. Pre: dividend in a4:a5 (lo:hi), divisor in a2:a3.
  Restoring binary long division, 64 iterations MSB-first: the dividend (a4:a5)
  doubles as the quotient register, the remainder builds in a6:a8. SAR is preset
  to 31 so `srl` extracts a word's MSB. Post: result (quotient, or remainder when
  wantMod) in a2:a3. Clobbers a4,a5,a6,a8,a9,a10,a11,a12. }
begin
  EmitAsmXtensa([
    'movi a10, 31',
    'ssr a10',              { SAR = 31, so `srl x, y` = y >> 31 = MSB(y) }
    'movi a6, 0',           { R.lo }
    'movi a8, 0',           { R.hi }
    'movi a9, 64',          { count }
    'movi a11, 0',          { zero (loop test) }
    '.loop:',
    { shift {R.hi:R.lo:NQ.hi:NQ.lo} left by 1, MSB first }
    'srl a10, a4',          { NQ.lo top bit }
    'add a4, a4, a4',       { NQ.lo <<= 1 }
    'srl a12, a5',          { NQ.hi top bit }
    'add a5, a5, a5',       { NQ.hi <<= 1 }
    'or a5, a5, a10',       { NQ.hi |= old NQ.lo top }
    'srl a10, a6',          { R.lo top bit }
    'add a6, a6, a6',       { R.lo <<= 1 }
    'or a6, a6, a12',       { R.lo |= old NQ.hi top }
    'add a8, a8, a8',       { R.hi <<= 1 }
    'or a8, a8, a10',       { R.hi |= old R.lo top }
    { if R (a8:a6) >= divisor (a3:a2) unsigned: subtract, set quotient bit }
    'bltu a8, a3, .nosub',  { R.hi < D.hi }
    'bne a8, a3, .sub',     { R.hi > D.hi }
    'bltu a6, a2, .nosub',  { R.hi == D.hi and R.lo < D.lo }
    '.sub:',
    'movi a12, 0',
    'bgeu a6, a2, .nb',     { borrow }
    'movi a12, 1',
    '.nb:',
    'sub a6, a6, a2',       { R.lo -= D.lo }
    'sub a8, a8, a3',       { R.hi -= D.hi }
    'sub a8, a8, a12',      { R.hi -= borrow }
    'movi a12, 1',
    'or a4, a4, a12',       { quotient bit }
    '.nosub:',
    'addi a9, a9, -1',
    'bne a9, a11, .loop'
  ]);
  if wantMod then
  begin
    xtensa_mov(reg_xtensa_a2, reg_xtensa_a6);
    xtensa_mov(reg_xtensa_a3, reg_xtensa_a8);
  end
  else
  begin
    xtensa_mov(reg_xtensa_a2, reg_xtensa_a4);
    xtensa_mov(reg_xtensa_a3, reg_xtensa_a5);
  end;
end;

procedure EmitIDivMod64Xtensa(wantMod: Boolean);
{ Signed 64-bit divide/mod. Truncated: quotient sign = dividend xor divisor,
  remainder takes the dividend's sign. Operands (divisor a2:a3, dividend a4:a5)
  are made non-negative in place, the unsigned core runs, then the sign is
  applied. Flags live in a14 (the unsigned core does not touch a14). }
begin
  EmitAsmXtensa([
    'movi a14, 0',          { flags: bit0 negate-quotient, bit1 negate-remainder }
    { divisor sign (a3 = D.hi) }
    'movi a13, 0',
    'bge a3, a13, .dpos',
    'movi a12, 0',          { negate divisor a2:a3 }
    'beq a2, a13, .db0',
    'movi a12, 1',          { borrow if lo <> 0 }
    '.db0:',
    'sub a2, a13, a2',
    'sub a3, a13, a3',
    'sub a3, a3, a12',
    'movi a12, 1',
    'xor a14, a14, a12',
    '.dpos:',
    { dividend sign (a5 = N.hi) }
    'movi a13, 0',
    'bge a5, a13, .npos',
    'movi a12, 0',          { negate dividend a4:a5 }
    'beq a4, a13, .nb0',
    'movi a12, 1',
    '.nb0:',
    'sub a4, a13, a4',
    'sub a5, a13, a5',
    'sub a5, a5, a12',
    'movi a12, 1',
    'xor a14, a14, a12',
    'movi a12, 2',
    'or a14, a14, a12',
    '.npos:'
  ]);
  EmitUDivMod64Xtensa(wantMod);   { result in a2:a3; a14 preserved }
  if wantMod then
    EmitAsmXtensa(['movi a12, 2', 'and a12, a14, a12'])
  else
    EmitAsmXtensa(['movi a12, 1', 'and a12, a14, a12']);
  EmitAsmXtensa([
    'movi a13, 0',
    'beq a12, a13, .done',
    'movi a12, 0',          { negate result a2:a3 (a13 = 0) }
    'beq a2, a13, .rb0',
    'movi a12, 1',
    '.rb0:',
    'sub a2, a13, a2',
    'sub a3, a13, a3',
    'sub a3, a3, a12',
    '.done:'
  ]);
end;

procedure EmitBinop64Xtensa(left, right, op: Integer; signedOp: Boolean);
{ (left OP right) as a 64-bit op. left spilled to the expr stack, right -> a2:a3,
  left popped into a4:a5. Arithmetic/bit ops leave a2:a3; comparisons leave 0/1
  in a2. }
var hbr: AnsiString;
begin
  EmitNode64Xtensa(left);
  XtensaPush64;
  EmitNode64Xtensa(right);             { right -> a2:a3 }
  XtensaPop64ToA4A5;                    { a4:a5 = left.lo:hi }
  { now a4:a5 = left, a2:a3 = right }

  if (op = Ord(tkDiv)) or (op = Ord(tkMod)) then
  begin
    { dividend in a4:a5, divisor in a2:a3 }
    if signedOp then EmitIDivMod64Xtensa(op = Ord(tkMod))
    else EmitUDivMod64Xtensa(op = Ord(tkMod));
  end
  else if op = Ord(tkPlus) then
    EmitAsmXtensa([
      'add a8, a4, a2',     { lo = left.lo + right.lo }
      'movi a9, 0',
      'bgeu a8, a4, .nc',   { carry if lo <u left.lo }
      'movi a9, 1',
      '.nc:',
      'add a3, a5, a3',     { hi = left.hi + right.hi }
      'add a3, a3, a9',     { hi += carry }
      'mov a2, a8' ])
  else if op = Ord(tkMinus) then
    EmitAsmXtensa([
      'movi a9, 0',
      'bgeu a4, a2, .nb',   { borrow if left.lo <u right.lo }
      'movi a9, 1',
      '.nb:',
      'sub a8, a4, a2',     { lo }
      'sub a3, a5, a3',     { hi = left.hi - right.hi }
      'sub a3, a3, a9',     { hi -= borrow }
      'mov a2, a8' ])
  else if op = Ord(tkStar) then
    { low 64 of (a5:a4) * (a3:a2) }
    EmitAsmXtensa([
      'mull a8, a4, a2',    { lo = low(Llo*Rlo) }
      'muluh a9, a4, a2',   { high(Llo*Rlo) }
      'mull a10, a4, a3',   { low(Llo*Rhi) }
      'mull a11, a5, a2',   { low(Lhi*Rlo) }
      'add a9, a9, a10',
      'add a3, a9, a11',
      'mov a2, a8' ])
  else if op = Ord(tkAnd) then
    EmitAsmXtensa(['and a2, a4, a2', 'and a3, a5, a3'])
  else if op = Ord(tkOr) then
    EmitAsmXtensa(['or a2, a4, a2', 'or a3, a5, a3'])
  else if op = Ord(tkXor) then
    EmitAsmXtensa(['xor a2, a4, a2', 'xor a3, a5, a3'])
  else if op = Ord(tkShl) then
    { count = a2 (& 63); value = a4:a5 -> a2:a3 }
    EmitAsmXtensa([
      'movi a8, 63',
      'and a8, a2, a8',     { n }
      'movi a9, 32',
      'bgeu a8, a9, .big',
      'movi a10, 0',
      'beq a8, a10, .zero',
      'movi a12, 32',
      'sub a12, a12, a8',   { 32 - n }
      'ssl a8',             { SAR for << n }
      'sll a10, a4',        { lo << n  (final lo) }
      'sll a11, a5',        { hi << n }
      'ssr a12',            { SAR = 32-n }
      'srl a4, a4',         { lo >> (32-n) }
      'or a3, a11, a4',     { final hi }
      'mov a2, a10',        { final lo }
      'j .end',
      '.big:',
      'sub a8, a8, a9',     { n - 32 }
      'ssl a8',
      'sll a3, a4',         { hi = lo << (n-32) }
      'movi a2, 0',
      'j .end',
      '.zero:',
      'mov a2, a4',
      'mov a3, a5',
      '.end:' ])
  else if op = Ord(tkIdent) then   { 'shr' parses as ident; logical on Int64/UInt64 }
    EmitAsmXtensa([
      'movi a8, 63',
      'and a8, a2, a8',     { n }
      'movi a9, 32',
      'bgeu a8, a9, .big',
      'movi a10, 0',
      'beq a8, a10, .zero',
      'movi a12, 32',
      'sub a12, a12, a8',   { 32 - n }
      'ssr a8',             { SAR = n }
      'srl a10, a4',        { lo >> n }
      'srl a3, a5',         { hi >> n  (final hi) }
      'ssl a12',            { SAR for << (32-n) }
      'sll a11, a5',        { hi << (32-n) }
      'or a2, a10, a11',    { final lo }
      'j .end',
      '.big:',
      'sub a8, a8, a9',     { n - 32 }
      'ssr a8',
      'srl a2, a5',         { lo = hi >> (n-32) }
      'movi a3, 0',
      'j .end',
      '.zero:',
      'mov a2, a4',
      'mov a3, a5',
      '.end:' ])
  else if (op = Ord(tkEq)) or (op = Ord(tkNeq)) then
  begin
    EmitAsmXtensa([
      'movi a8, 0',
      'bne a4, a2, .ne',    { lo differ -> not equal }
      'bne a5, a3, .ne',    { hi differ -> not equal }
      'movi a8, 1',
      '.ne:',
      'mov a2, a8' ]);
    if op = Ord(tkNeq) then
      EmitAsmXtensa(['movi a8, 1', 'xor a2, a2, a8']);
  end
  else if (op = Ord(tkLt)) or (op = Ord(tkGe)) then
  begin
    { a2 = (left < right): hi compare (signed/unsigned) then unsigned lo tiebreak }
    if signedOp then hbr := 'blt' else hbr := 'bltu';
    EmitAsmXtensa([
      'movi a8, 1',
      hbr + ' a5, a3, .lt',  { left.hi < right.hi }
      'bne a5, a3, .lz',     { hi differ but not < -> 0 }
      'bltu a4, a2, .lt',    { hi equal, lo unsigned < }
      '.lz:',
      'movi a8, 0',
      '.lt:',
      'mov a2, a8' ]);
    if op = Ord(tkGe) then
      EmitAsmXtensa(['movi a8, 1', 'xor a2, a2, a8']);   { ge = not lt }
  end
  else if (op = Ord(tkGt)) or (op = Ord(tkLe)) then
  begin
    { a2 = (left > right) = (right < left) }
    if signedOp then hbr := 'blt' else hbr := 'bltu';
    EmitAsmXtensa([
      'movi a8, 1',
      hbr + ' a3, a5, .gt',  { right.hi < left.hi }
      'bne a3, a5, .gz',
      'bltu a2, a4, .gt',    { hi equal, right.lo unsigned < left.lo }
      '.gz:',
      'movi a8, 0',
      '.gt:',
      'mov a2, a8' ]);
    if op = Ord(tkLe) then
      EmitAsmXtensa(['movi a8, 1', 'xor a2, a2, a8']);   { le = not gt }
  end
  else
    Error('target xtensa: 64-bit binop operator not yet supported');
end;

procedure EmitFloatUnaryCallXtensa(const nm: AnsiString; srcDouble, dstDouble: Boolean);
{ Argument already in a2 (single/int) or a2:a3 (double). Call the kernel and
  leave its result in a2 (single/int) or a2:a3 (double). ABI-aware. }
var procIdx: Integer;
begin
  procIdx := FindProc(nm);
  if procIdx < 0 then Error('compiler error: ' + nm + ' not found (uses softfloat?)');
  if XtensaABI = XTENSA_ABI_WINDOWED then
  begin
    xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);
    if srcDouble then xtensa_mov(reg_xtensa_a11, reg_xtensa_a3);
    EmitCallProc(procIdx);
    xtensa_mov(reg_xtensa_a2, reg_xtensa_a10);
    if dstDouble then xtensa_mov(reg_xtensa_a3, reg_xtensa_a11);
  end
  else
    EmitCallProc(procIdx);   { Call0: args already a2(:a3); result a2(:a3) }
end;

procedure EmitFloatConvXtensa(srcTk, dstTk: TTypeKind);
{ Repack value (a2 / a2:a3) from one float width to the other, in place. }
begin
  if srcTk = dstTk then Exit;
  if (srcTk = tySingle) and (dstTk = tyDouble) then
    EmitFloatUnaryCallXtensa('__pxx_s2d', False, True)
  else if (srcTk = tyDouble) and (dstTk = tySingle) then
    EmitFloatUnaryCallXtensa('__pxx_d2s', True, False)
  else
    Error('target xtensa: unsupported float-to-float conversion');
end;

procedure EmitFloatOperandXtensa(node: Integer; wantTk: TTypeKind);
{ Emit node and coerce its value to wantTk (a float kind) in a2 / a2:a3. }
var ntk: TTypeKind;
begin
  ntk := IntToTypeKind(IRTk[node]);
  if IsFloatXtensa(ntk) then
  begin
    if ntk = tyDouble then EmitNode64Xtensa(node) else IREmitNodeXtensa(node);
    EmitFloatConvXtensa(ntk, wantTk);
  end
  else
  begin
    if (ntk = tyInt64) or (ntk = tyUInt64) then
    begin
      Error('target xtensa: Int64-to-float conversion not yet supported');
      Exit;
    end;
    IREmitNodeXtensa(node);            { a2 = 32-bit int }
    if wantTk = tySingle then EmitFloatUnaryCallXtensa('__pxx_i2s', False, False)
    else EmitFloatUnaryCallXtensa('__pxx_i2d', False, True);
  end;
end;

procedure EmitFloatCmpMapXtensa(op: Integer);
{ Map a soft-float compare code in a2 (-1/0/1, or 2 for NaN/unordered) to a
  Boolean 0/1 in a2. NaN-correct: only Eq/Neq/Lt/Le/Gt/Ge as defined for IEEE
  (unordered makes every relation false except <>). Uses a8/a9/a10 scratch. }
begin
  if op = Ord(tkEq) then
    EmitAsmXtensa(['movi a9, 0', 'movi a8, 0', 'bne a2, a9, .e', 'movi a8, 1', '.e:', 'mov a2, a8'])
  else if op = Ord(tkNeq) then
    EmitAsmXtensa(['movi a9, 0', 'movi a8, 1', 'bne a2, a9, .e', 'movi a8, 0', '.e:', 'mov a2, a8'])
  else if op = Ord(tkLt) then
    EmitAsmXtensa(['movi a9, 0', 'movi a8, 1', 'blt a2, a9, .e', 'movi a8, 0', '.e:', 'mov a2, a8'])
  else if op = Ord(tkLe) then
    EmitAsmXtensa(['movi a10, 1', 'movi a8, 1', 'blt a2, a10, .e', 'movi a8, 0', '.e:', 'mov a2, a8'])
  else if op = Ord(tkGt) then
    EmitAsmXtensa(['movi a10, 1', 'movi a8, 0', 'bne a2, a10, .e', 'movi a8, 1', '.e:', 'mov a2, a8'])
  else if op = Ord(tkGe) then
    EmitAsmXtensa(['movi a9, 0', 'movi a10, 2', 'movi a8, 0', 'blt a2, a9, .e', 'bge a2, a10, .e', 'movi a8, 1', '.e:', 'mov a2, a8'])
  else
    Error('target xtensa: unsupported float comparison');
end;

procedure EmitFloatBinopXtensa(node: Integer);
{ Float arithmetic + comparison via the soft-float kernels (both widths soft;
  HW single FPU is a follow-up). Arithmetic result lands in a2 / a2:a3; a
  comparison lands as a Boolean 0/1 in a2. }
var left, right, op, procIdx, argBase, nArgs, i: Integer; ltk, rtk, opTk: TTypeKind;
    isDouble, isCmp: Boolean; nm: AnsiString;
begin
  left := IRA[node]; right := IRB[node]; op := IRC[node];
  ltk := IntToTypeKind(IRTk[left]); rtk := IntToTypeKind(IRTk[right]);
  isDouble := (ltk = tyDouble) or (rtk = tyDouble);
  if isDouble then opTk := tyDouble else opTk := tySingle;
  isCmp := (op = Ord(tkEq)) or (op = Ord(tkNeq)) or (op = Ord(tkLt)) or
           (op = Ord(tkGt)) or (op = Ord(tkLe)) or (op = Ord(tkGe));

  { Hardware single FPU path (--xtensa-fpu, ESP32/-S3): single +,-,* via
    add.s/sub.s/mul.s. Single / and comparisons stay soft (no HW single divide /
    no FP-compare-to-AR path wired). Double normally stays soft, BUT under
    {$FASTDOUBLES ON} Double +,-,* also takes this path (operands coerced to
    single via d2s, the result repacked to double via s2d) — lossy single
    precision, traded for speed. }
  if XtensaHasFpu and ((op = Ord(tkPlus)) or (op = Ord(tkMinus)) or (op = Ord(tkStar))) and
     ((not isDouble) or XtensaFastDoubles) then
  begin
    EmitFloatOperandXtensa(left, tySingle);      { double operand -> single (d2s) }
    XtensaPushA2;
    EmitFloatOperandXtensa(right, tySingle);      { a2 = right bits }
    XtensaPopA3;                                   { a3 = left bits }
    xtensa_wfr(0, reg_xtensa_a3);                  { f0 = left }
    xtensa_wfr(1, reg_xtensa_a2);                  { f1 = right }
    if op = Ord(tkPlus) then xtensa_add_s(0, 0, 1)
    else if op = Ord(tkMinus) then xtensa_sub_s(0, 0, 1)
    else xtensa_mul_s(0, 0, 1);
    xtensa_rfr(reg_xtensa_a2, 0);                  { a2 = single result }
    if isDouble then EmitFloatConvXtensa(tySingle, tyDouble);  { s2d -> a2:a3 }
    Exit;
  end;

  argBase := XtSpillDepth;
  EmitFloatOperandXtensa(left, opTk);
  XtensaPushA2;
  if isDouble then begin xtensa_mov(reg_xtensa_a2, reg_xtensa_a3); XtensaPushA2; end;
  EmitFloatOperandXtensa(right, opTk);
  XtensaPushA2;
  if isDouble then begin xtensa_mov(reg_xtensa_a2, reg_xtensa_a3); XtensaPushA2; end;
  if isDouble then nArgs := 4 else nArgs := 2;

  { Load outgoing argument registers (mirrors the generic IR_CALL marshalling). }
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
    xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, nArgs * 4);
  end;

  if isDouble then nm := '__pxx_d' else nm := '__pxx_s';
  if op = Ord(tkPlus) then nm := nm + 'add'
  else if op = Ord(tkMinus) then nm := nm + 'sub'
  else if op = Ord(tkStar) then nm := nm + 'mul'
  else if op = Ord(tkSlash) then nm := nm + 'div'
  else if isCmp then nm := nm + 'cmp'
  else begin Error('target xtensa: unsupported float operator'); Exit; end;

  procIdx := FindProc(nm);
  if procIdx < 0 then Error('compiler error: ' + nm + ' not found (uses softfloat?)');
  EmitCallProc(procIdx);
  if XtensaABI = XTENSA_ABI_WINDOWED then
  begin
    xtensa_mov(reg_xtensa_a2, reg_xtensa_a10);
    if isDouble and not isCmp then xtensa_mov(reg_xtensa_a3, reg_xtensa_a11);
  end;

  if isCmp then EmitFloatCmpMapXtensa(op);
end;

procedure IREmitNodeXtensa(node: Integer);
var
  left, right, op, si, procIdx, nArgs, i, lo, elemSize, sz, argNode, argBase, valNode, j: Integer;
  tk: TTypeKind;
  sgn, savedLVW: Boolean;
  sVal: AnsiString;
begin
  case IRKind[node] of
    IR_CONST_INT:
      if Is64BitXtensa(IntToTypeKind(IRTk[node])) then
        EmitLoadConst64Xtensa(IRIVal[node])
      else
        EmitLoadConstXtensa(reg_xtensa_a2, IRIVal[node]);

    IR_CONST_STR:
      begin
        sVal := GetTokenStrFromRaw(IRA[node], IRB[node]);
        si := InternStr(sVal);
        EmitLoadDataRefXtensa(reg_xtensa_a2, Strs[si].Offset);
      end;

    IR_LOAD_SYM:
      if Is64BitXtensa(Syms[IRA[node]].TypeKind) then
        EmitLoadVar64Xtensa(IRA[node])
      else
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
        { Float destination: coerce the RHS to the slot's float width before the
          store. Must precede the Is64Bit branch (a Double slot is Is64Bit but a
          non-double RHS needs conversion, not a raw 64-bit move). }
        if IsFloatXtensa(Syms[IRA[node]].TypeKind) then
        begin
          EmitFloatOperandXtensa(IRB[node], Syms[IRA[node]].TypeKind);
          if Syms[IRA[node]].TypeKind = tyDouble then
            EmitStoreVar64Xtensa(IRA[node])
          else
            EmitStoreVarXtensa(IRA[node]);
          Exit;
        end;
        if Is64BitXtensa(Syms[IRA[node]].TypeKind) then
        begin
          EmitNode64Xtensa(IRB[node]);
          EmitStoreVar64Xtensa(IRA[node]);
        end
        else
        begin
          IREmitNodeXtensa(IRB[node]);
          EmitStoreVarXtensa(IRA[node]);
        end;
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
          xtensa_l32i(reg_xtensa_a2, reg_xtensa_a2, 0)
        { Scalar var/out param: the slot holds the forwarded caller address, so its
          lvalue address is [slot], not &slot. Without this deref, forwarding a
          `var` param into another routine's `var` param (or `@op`) yields the
          local slot and the inner write never reaches the caller
          (feature-riscv32-var-param-forwarding, same defect on xtensa). The 64-bit
          slot-addr emitter + load/store paths already deref; this aligns IR_LEA's
          scalar path. Arrays/strings keep their handling above. }
        else if (Syms[si].Kind = skParam) and Syms[si].IsRef and
                not Syms[si].IsArray and (Syms[si].TypeKind <> tyAnsiString) then
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
          procIdx := FindProc('PXXStrUnique');
          if procIdx < 0 then Error('compiler error: PXXStrUnique not found');
          if XtensaABI = XTENSA_ABI_WINDOWED then
          begin
            xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);
            EmitCallProc(procIdx);
            xtensa_mov(reg_xtensa_a2, reg_xtensa_a10);   { a2 = unique handle }
          end
          else
            EmitCallProc(procIdx);                            { a2 = unique handle }
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
          procIdx := FindProc('PXXStrConcat');
          if procIdx < 0 then Error('compiler error: PXXStrConcat not found');
          if XtensaABI = XTENSA_ABI_WINDOWED then
          begin
            xtensa_mov(reg_xtensa_a10, reg_xtensa_a4);
            xtensa_mov(reg_xtensa_a11, reg_xtensa_a5);
            xtensa_mov(reg_xtensa_a12, reg_xtensa_a6);
            xtensa_mov(reg_xtensa_a13, reg_xtensa_a7);
            EmitCallProc(procIdx);
            xtensa_mov(reg_xtensa_a2, reg_xtensa_a10);
          end
          else
          begin
            xtensa_mov(reg_xtensa_a2, reg_xtensa_a4);   { a2=lenA }
            xtensa_mov(reg_xtensa_a3, reg_xtensa_a5);   { a3=srcA }
            xtensa_mov(reg_xtensa_a4, reg_xtensa_a6);   { a4=srcB }
            xtensa_mov(reg_xtensa_a5, reg_xtensa_a7);   { a5=lenB }
            EmitCallProc(procIdx);                           { result a2 }
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
          procIdx := FindProc('PXXStrEq');
          if procIdx < 0 then Error('compiler error: PXXStrEq not found');
          if XtensaABI = XTENSA_ABI_WINDOWED then
          begin
            xtensa_mov(reg_xtensa_a10, reg_xtensa_a4);
            xtensa_mov(reg_xtensa_a11, reg_xtensa_a5);
            xtensa_mov(reg_xtensa_a12, reg_xtensa_a6);
            xtensa_mov(reg_xtensa_a13, reg_xtensa_a7);
            EmitCallProc(procIdx);
            xtensa_mov(reg_xtensa_a2, reg_xtensa_a10);
          end
          else
          begin
            xtensa_mov(reg_xtensa_a2, reg_xtensa_a4);   { a2=lenA }
            xtensa_mov(reg_xtensa_a3, reg_xtensa_a5);   { a3=srcA }
            xtensa_mov(reg_xtensa_a4, reg_xtensa_a6);   { a4=lenB }
            xtensa_mov(reg_xtensa_a5, reg_xtensa_a7);   { a5=srcB }
            EmitCallProc(procIdx);                           { result a2 }
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

        { Float arithmetic/compare via the soft-float kernels. MUST precede the
          64-bit check — Double is Is64Bit (a2:a3 storage shape) but its
          arithmetic is soft-float, not integer. Key off the operands. }
        if IsFloatXtensa(IntToTypeKind(IRTk[node])) or
           IsFloatXtensa(IntToTypeKind(IRTk[left])) or
           IsFloatXtensa(IntToTypeKind(IRTk[right])) then
        begin
          EmitFloatBinopXtensa(node);
          Exit;
        end;

        { 64-bit (Int64/UInt64) ops use the dedicated a2:a3 path. A comparison
          carries a Boolean result tk, so key off the operands too. }
        if Is64BitXtensa(IntToTypeKind(IRTk[node])) or
           Is64BitXtensa(IntToTypeKind(IRTk[left])) or
           Is64BitXtensa(IntToTypeKind(IRTk[right])) then
        begin
          EmitBinop64Xtensa(left, right, op,
            not ((IntToTypeKind(IRTk[left]) = tyUInt64) or (IntToTypeKind(IRTk[right]) = tyUInt64)));
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
        else if op = Ord(tkXor) then xtensa_xor(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a3)
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
        procIdx := IRA[node];
        if procIdx = -Ord(tkGetMem) then
        begin
          { GetMem / New. Class instantiation (VMT + ctor) is a later step. }
          if IRC[node] >= REC_UCLASS_BASE then
            Error('target xtensa: class instantiation not yet supported');
          argNode := IRB[node];                 { size arg }
          IREmitNodeXtensa(IRA[argNode]);       { size -> a2 }
          EmitHeapAllocLockedXtensa;            { a2 = payload pointer }
          Exit;
        end;
        if procIdx = -Ord(tkFreeMem) then
        begin
          argNode := IRB[node];                 { pointer arg }
          IREmitNodeXtensa(IRA[argNode]);       { p -> a2 }
          EmitHeapFreeLockedXtensa;
          Exit;
        end;
        if procIdx = -102 then
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
            procIdx := FindProc('PXXStrSetLen');
            if procIdx < 0 then Error('compiler error: PXXStrSetLen not found');
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
            EmitCallProc(procIdx);
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
          procIdx := FindProc('PXXDynSetLen');
          if procIdx < 0 then Error('compiler error: PXXDynSetLen not found');
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
          EmitCallProc(procIdx);
          Exit;
        end;
        if procIdx = -Ord(tkLength) then
        begin
          { Length(arr): a2 = handle; count at [handle-8], nil handle -> 0.
            (l32i has no negative offset, so address via addi first.) }
          argNode := IRB[node];
          IREmitNodeXtensa(IRA[argNode]);       { a2 = handle (or 0) }
          EmitAsmXtensa(['movi a4, 0', 'beq a2, a4, .lzero',
                         'addi a2, a2, -8', 'l32i a2, a2, 0', '.lzero:']);
          Exit;
        end;
        if procIdx < 0 then
        begin
          { Type-pun passthroughs: Ord/Chr/Integer()/LongWord() are identity on
            the value already in a2 (char/int share the register model). }
          if (procIdx = -Ord(tkOrd)) or (procIdx = -Ord(tkChr)) or
             (procIdx = -Ord(tkInteger_T)) or (procIdx = -Ord(tkLongWord_T)) or
             (procIdx = -Ord(tkChar_T)) or (procIdx = -Ord(tkBoolean_T)) or
             (procIdx = -Ord(tkString_T)) then
          begin
            argNode := IRB[node];
            IREmitNodeXtensa(IRA[argNode]);
            Exit;
          end;
          if (procIdx = -203) or (procIdx = -204) then
          begin
            { Trunc (-203, toward zero) / Round (-204, nearest-even) -> Int64, via
              the soft-float d2i[_rne]/s2i[_rne] kernels (32-bit result, sign-
              extended to the a2:a3 pair). }
            argNode := IRB[node];
            tk := IntToTypeKind(IRTk[IRA[argNode]]);
            if tk = tyDouble then
            begin
              EmitNode64Xtensa(IRA[argNode]);     { a2:a3 = double bits }
              if procIdx = -204 then EmitFloatUnaryCallXtensa('__pxx_d2i_rne', True, False)
              else EmitFloatUnaryCallXtensa('__pxx_d2i', True, False);
            end
            else if tk = tySingle then
            begin
              IREmitNodeXtensa(IRA[argNode]);     { a2 = single bits }
              if procIdx = -204 then EmitFloatUnaryCallXtensa('__pxx_s2i_rne', False, False)
              else EmitFloatUnaryCallXtensa('__pxx_s2i', False, False);
            end
            else
              IREmitNodeXtensa(IRA[argNode]);      { Trunc/Round of an integer is identity }
            { sign-extend a2 -> a3 for the Int64 result pair }
            EmitAsmXtensa(['movi a3, 0', 'bge a2, a3, .p', 'movi a3, -1', '.p:']);
            Exit;
          end;
          if (procIdx = -205) or (procIdx = -206) then
          begin
            { Frac (-205) / Int (-206) -> float (node tk tyDouble). Promote the
              arg to double, then call the fractional / integer-part kernel. }
            argNode := IRB[node];
            EmitFloatOperandXtensa(IRA[argNode], tyDouble);    { a2:a3 = double }
            if procIdx = -205 then EmitFloatUnaryCallXtensa('__pxx_dfrac', True, True)
            else EmitFloatUnaryCallXtensa('__pxx_dint', True, True);
            Exit;
          end;
          Error('target xtensa: builtin calls not supported in bare-metal stage 1');
        end;

        { Word-based argument passing (matches the callee spill in parser.inc):
          each scalar arg is one word, a by-value Int64/UInt64 is two (lo then
          hi). nArgs counts WORDS; word k loads into the k-th arg register
          (Call0 a2+k / windowed a10+k). Up to 6 words total. }
        { Aggregate (record) result, Call0 only: push the caller's hidden
          destination first (deepest), load into a8 just before the call. Windowed
          record results are unsupported (the call-window rotation has no clean
          caller->callee hidden-dest register) and are rejected at the callee
          epilogue, so no windowed call reaches here with an aggregate result. }
        if (procIdx >= 0) and (not ProcExternal[procIdx]) and
           TypeIsAggregate(Procs[procIdx].RetType) and (XtensaABI = XTENSA_ABI_CALL0) then
        begin
          IREmitNodeXtensa(IRC[node]);     { a2 = hidden dest addr }
          XtensaPushA2;
        end;
        argNode := IRB[node];
        nArgs := 0;     { word count }
        i := 0;         { argument index }
        argBase := XtSpillDepth;   { windowed: base offset of this call's arg block }
        while argNode <> -1 do
        begin
          if (procIdx >= 0) and (not ProcExternal[procIdx]) and
             (i < Procs[procIdx].ParamCount) and
             IsFloatXtensa(Procs[procIdx].Params[i].TypeKind) and
             (not Procs[procIdx].Params[i].IsRef) and
             (not Procs[procIdx].Params[i].IsArray) then
          begin
            { Float param: coerce to the param's float width, push one word
              (single) or two words lo:hi (double). }
            EmitFloatOperandXtensa(IRA[argNode], Procs[procIdx].Params[i].TypeKind);
            XtensaPushA2;                           { lo / single }
            if Procs[procIdx].Params[i].TypeKind = tyDouble then
            begin
              xtensa_mov(reg_xtensa_a2, reg_xtensa_a3);
              XtensaPushA2;                          { hi }
              Inc(nArgs, 2);
            end
            else
              Inc(nArgs, 1);
          end
          else if (procIdx >= 0) and (not ProcExternal[procIdx]) and
             (i < Procs[procIdx].ParamCount) and
             ((Procs[procIdx].Params[i].TypeKind = tyInt64) or
              (Procs[procIdx].Params[i].TypeKind = tyUInt64)) and
             (not Procs[procIdx].Params[i].IsRef) and
             (not Procs[procIdx].Params[i].IsArray) then
          begin
            EmitNode64Xtensa(IRA[argNode]);        { a2=lo, a3=hi }
            XtensaPushA2;                           { lo, word nArgs }
            xtensa_mov(reg_xtensa_a2, reg_xtensa_a3);
            XtensaPushA2;                           { hi, word nArgs+1 }
            Inc(nArgs, 2);
          end
          else
          begin
            IREmitNodeXtensa(IRA[argNode]);
            { External C call: skip the 8-byte length prefix of a Pascal string
              literal so the callee sees a const char* (as on x86-64/riscv32). }
            if ProcExternal[procIdx] and (IntToTypeKind(IRTk[argNode]) = tyString) then
              xtensa_addi(reg_xtensa_a2, reg_xtensa_a2, 8);
            XtensaPushA2;
            Inc(nArgs, 1);
          end;
          Inc(i);
          argNode := IRB[argNode];
        end;

        if nArgs > 6 then
          Error('target xtensa: more than 6 call argument words not supported yet');

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
          if (procIdx >= 0) and (not ProcExternal[procIdx]) and
             TypeIsAggregate(Procs[procIdx].RetType) then
          begin
            xtensa_l32i(reg_xtensa_a8, reg_xtensa_sp, nArgs * 4);   { hidden dest (deepest) }
            xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, (nArgs + 1) * 4);
          end
          else if nArgs > 0 then
            xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, nArgs * 4);
        end;

        EmitCallProc(procIdx);
        if XtensaABI = XTENSA_ABI_WINDOWED then
        begin
          xtensa_mov(reg_xtensa_a2, reg_xtensa_a10);
          { 64-bit result returns in the callee's a2:a3, the caller's a10:a11. }
          if Is64BitXtensa(IntToTypeKind(IRTk[node])) then
            xtensa_mov(reg_xtensa_a3, reg_xtensa_a11);
        end;
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
        procIdx := FindProc('PXXMemZero');
        if procIdx < 0 then Error('compiler error: PXXMemZero not found');
        if XtensaABI = XTENSA_ABI_WINDOWED then
        begin
          xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);        { arg0 = dest }
          EmitLoadConstXtensa(reg_xtensa_a11, Integer(IRIVal[node])); { arg1 = count }
        end
        else
          EmitLoadConstXtensa(reg_xtensa_a3, Integer(IRIVal[node])); { a2=dest; arg1=count }
        EmitCallProc(procIdx);
      end;

    IR_COPY_REC:
      begin
        { Whole-record copy: PXXMemMove(dest, src, count). ESP has no managed
          record fields yet, so the plain byte move is correct (no per-field ARC). }
        IREmitNodeXtensa(IRB[node]);             { a2 = src }
        XtensaPushA2;
        IREmitNodeXtensa(IRA[node]);             { a2 = dest }
        XtensaPopA3;                              { a3 = src }
        procIdx := FindProc('PXXMemMove');
        if procIdx < 0 then Error('compiler error: PXXMemMove not found');
        if XtensaABI = XTENSA_ABI_WINDOWED then
        begin
          xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);                   { arg0 = dest }
          xtensa_mov(reg_xtensa_a11, reg_xtensa_a3);                   { arg1 = src }
          EmitLoadConstXtensa(reg_xtensa_a12, Integer(IRIVal[node]));  { arg2 = count }
        end
        else
          EmitLoadConstXtensa(reg_xtensa_a4, Integer(IRIVal[node]));   { a2=dest, a3=src, a4=count }
        EmitCallProc(procIdx);
      end;

    IR_NEG:
      if IsFloatXtensa(IntToTypeKind(IRTk[node])) then
      begin
        { Float negate = flip the IEEE sign bit (bit 63 of a Double = bit 31 of
          the hi word a3; bit 31 of a Single in a2), NOT an integer negate. Must
          precede the Is64Bit branch (Double is Is64Bit). }
        if IntToTypeKind(IRTk[node]) = tyDouble then
        begin
          EmitNode64Xtensa(IRA[node]);           { a2:a3 = double bits }
          EmitLoadConstXtensa(reg_xtensa_a8, Integer($80000000));
          xtensa_xor(reg_xtensa_a3, reg_xtensa_a3, reg_xtensa_a8);
        end
        else
        begin
          IREmitNodeXtensa(IRA[node]);           { a2 = single bits }
          EmitLoadConstXtensa(reg_xtensa_a8, Integer($80000000));
          xtensa_xor(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a8);
        end;
      end
      else if Is64BitXtensa(IntToTypeKind(IRTk[node])) then
      begin
        EmitNode64Xtensa(IRA[node]);             { value -> a2:a3 }
        { negate: lo = 0-lo (borrow if lo<>0), hi = 0-hi-borrow }
        EmitAsmXtensa([
          'movi a8, 0',
          'movi a9, 0',
          'beq a2, a8, .nb',
          'movi a9, 1',
          '.nb:',
          'sub a2, a8, a2',
          'sub a3, a8, a3',
          'sub a3, a3, a9' ]);
      end
      else
      begin
        IREmitNodeXtensa(IRA[node]);
        xtensa_movi(reg_xtensa_a8, 0);
        xtensa_sub(reg_xtensa_a2, reg_xtensa_a8, reg_xtensa_a2);
      end;

    IR_NOT:
      if Is64BitXtensa(IntToTypeKind(IRTk[node])) then
      begin
        EmitNode64Xtensa(IRA[node]);             { value -> a2:a3 }
        EmitAsmXtensa(['movi a8, -1', 'xor a2, a2, a8', 'xor a3, a3, a8']);
      end
      else if TypeIsOrdinal(IntToTypeKind(IRTk[node])) and
              (IntToTypeKind(IRTk[node]) <> tyBoolean) then
      begin
        { 32-bit integer/ordinal: bitwise complement (mirror i386/aarch64), not a
          boolean flip. }
        IREmitNodeXtensa(IRA[node]);
        xtensa_movi(reg_xtensa_a8, -1);
        xtensa_xor(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a8);
      end
      else
      begin
        IREmitNodeXtensa(IRA[node]);
        xtensa_movi(reg_xtensa_a8, 1);
        xtensa_xor(reg_xtensa_a2, reg_xtensa_a2, reg_xtensa_a8);
      end;

    IR_SETLEN_STR:
      begin
        { SetLength(ansistring-lvalue, n) -> PXXStrSetLen(slotAddr, n). IRA =
          slot-address node, IRB = new length. Address-based, so a record/var-
          param field needs no symbol reconstruction. Spill both args, then load
          into the ABI arg registers. }
        argBase := XtSpillDepth;
        IREmitNodeXtensa(IRA[node]);          { a2 = slot address }
        XtensaPushA2;                         { slot @ argBase }
        IREmitNodeXtensa(IRB[node]);          { a2 = n }
        XtensaPushA2;                         { n @ argBase+4 }
        procIdx := FindProc('PXXStrSetLen');
        if procIdx < 0 then Error('compiler error: PXXStrSetLen not found');
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
        EmitCallProc(procIdx);
      end;

    else
      Error('target xtensa: unsupported node in IR codegen: ' + IROpName(IRKind[node]));
  end;
end;

procedure IREmitMachineCodeXtensa;
var i, lblId, pos, f: Integer;
    LabelPositions: array[0..MAX_IR-1] of Integer;
    LabelFixupPos: array[0..MAX_IR-1] of Integer;
    LabelFixupTarget: array[0..MAX_IR-1] of Integer;
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
            if LabelFixupCount >= MAX_IR then Error('label fixup overflow');
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
            if LabelFixupCount >= MAX_IR then Error('label fixup overflow');
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
