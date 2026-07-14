{ SPDX-License-Identifier: MPL-2.0 }
{ ===== IR -> ARM32 machine code (cross target, minimal and growing) =====

  ARM32 (ARMv7-A) target backend. Operates on fixed-width 32-bit instructions.
  Registers used: r0 for expression results, r1..r3 for arguments/temporaries. }

procedure IREmitLeaveExceptionFramesArm32(count: Integer);
var i: Integer;
begin
  for i := 1 to count do
  begin
    EmitI32($E59D2000);                                         { ldr r2, [sp] }
    EmitI32($E59F1000);                                         { ldr r1, [pc] }
    EmitI32($EA000000);                                         { b .+8 }
    EmitGlobRef(BSS_EXC_TOP);
    EmitI32($E5812000);                                         { str r2, [r1] }
    EmitI32($E28DD030);                                         { add sp, sp, #48 }
  end;
end;

procedure EmitLoadVarArm32(idx: Integer);
var tk: TTypeKind; sz: Integer; sgn: Boolean;
begin
  tk := Syms[idx].TypeKind;
  sz := TypeSize(tk);
  sgn := TypeSigned(tk);

  if Syms[idx].Kind = skGlobal then
  begin
    EmitI32($E59F1000);  { ldr r1, [pc] }
    EmitI32($EA000000);  { b .+8 }
    EmitGlobRef(Syms[idx].Offset);
    if sz = 1 then
    begin
      if sgn then EmitI32($E1D100D0) else EmitI32($E5D10000);
    end
    else if sz = 2 then
    begin
      if sgn then EmitI32($E1D100F0) else EmitI32($E1D100B0);
    end
    else
      EmitI32($E5910000);
  end
  else
  begin
    EmitLoadImmArm32(9, Syms[idx].Offset);
    EmitI32($E08B9009);  { add r9, fp, r9 }
    if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then
    begin
      EmitI32($E5991000);  { ldr r1, [r9] }
      if sz = 1 then
      begin
        if sgn then EmitI32($E1D100D0) else EmitI32($E5D10000);
      end
      else if sz = 2 then
      begin
        if sgn then EmitI32($E1D100F0) else EmitI32($E1D100B0);
      end
      else
        EmitI32($E5910000);
    end
    else
    begin
      if sz = 1 then
      begin
        if sgn then EmitI32($E1D900D0) else EmitI32($E5D90000);
      end
      else if sz = 2 then
      begin
        if sgn then EmitI32($E1D900F0) else EmitI32($E1D900B0);
      end
      else
        EmitI32($E5990000);
    end;
  end;
end;

procedure EmitStoreVarArm32(idx: Integer);
var tk: TTypeKind; sz: Integer;
begin
  tk := Syms[idx].TypeKind;
  sz := TypeSize(tk);

  if Syms[idx].Kind = skGlobal then
  begin
    EmitI32($E59F1000);  { ldr r1, [pc] }
    EmitI32($EA000000);  { b .+8 }
    EmitGlobRef(Syms[idx].Offset);
    if sz = 1 then
      EmitI32($E5C10000)  { strb r0, [r1] }
    else if sz = 2 then
      EmitI32($E1C100B0)  { strh r0, [r1] }
    else
      EmitI32($E5810000); { str r0, [r1] }
  end
  else
  begin
    EmitLoadImmArm32(9, Syms[idx].Offset);
    EmitI32($E08B9009);  { add r9, fp, r9 }
    if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then
    begin
      EmitI32($E5991000);  { ldr r1, [r9] }
      if sz = 1 then
        EmitI32($E5C10000)  { strb r0, [r1] }
      else if sz = 2 then
        EmitI32($E1C100B0)  { strh r0, [r1] }
      else
        EmitI32($E5810000); { str r0, [r1] }
    end
    else
    begin
      if sz = 1 then
        EmitI32($E5C90000)  { strb r0, [r9] }
      else if sz = 2 then
        EmitI32($E1C900B0)  { strh r0, [r9] }
      else
        EmitI32($E5890000); { str r0, [r9] }
    end;
  end;
end;

procedure EmitLoadVarAddrArm32(idx: Integer);
begin
  if Syms[idx].Kind = skGlobal then
  begin
    EmitI32($E59F0000);  { ldr r0, [pc] }
    EmitI32($EA000000);  { b .+8 }
    EmitGlobRef(Syms[idx].Offset);
  end
  else if (Syms[idx].Kind = skParam) and
          (Syms[idx].IsRef or Syms[idx].IsArray or
           TypeIsFrozenString(Syms[idx].TypeKind) or (Syms[idx].TypeKind = tySet)) then
  begin
    { By-ref, open-array, fixed-string, or set param: the slot holds a pointer
      the caller passed (the array data / buffer / forwarded slot), so load the
      pointer itself, not the slot address. Mirrors i386 EmitLoadVarAddr386. }
    EmitLoadImmArm32(9, Syms[idx].Offset);
    EmitI32($E08B9009);  { add r9, fp, r9 }
    EmitI32($E5990000);  { ldr r0, [r9] }
  end
  else
  begin
    EmitLoadImmArm32(0, Syms[idx].Offset);
    EmitI32($E08B0000);  { add r0, fp, r0 }
  end;
end;

procedure EmitSetccArm32(opTk: Integer; signed: Boolean);
begin
  EmitAsmArm32('mov r0, #0');
  if opTk = Ord(tkEq) then EmitAsmArm32('moveq r0, #1')
  else if opTk = Ord(tkNeq) then EmitAsmArm32('movne r0, #1')
  else if signed then
  begin
    if opTk = Ord(tkLt) then EmitAsmArm32('movlt r0, #1')
    else if opTk = Ord(tkLe) then EmitAsmArm32('movle r0, #1')
    else if opTk = Ord(tkGt) then EmitAsmArm32('movgt r0, #1')
    else if opTk = Ord(tkGe) then EmitAsmArm32('movge r0, #1')
    else Error('target arm32: unsupported compare operator');
  end
  else
  begin
    { unsigned ordered compares: lo/ls/hi/hs (Cardinal/LongWord, C unsigned int) }
    if opTk = Ord(tkLt) then EmitAsmArm32('movlo r0, #1')
    else if opTk = Ord(tkLe) then EmitAsmArm32('movls r0, #1')
    else if opTk = Ord(tkGt) then EmitAsmArm32('movhi r0, #1')
    else if opTk = Ord(tkGe) then EmitAsmArm32('movhs r0, #1')
    else Error('target arm32: unsupported compare operator');
  end;
end;

procedure EmitSetccArm32Float(opTk: Integer);
{ VFP compare after `vcmp.f64` + `vmrs APSR_nzcv`: unordered (NaN operand) sets
  N=0 Z=0 C=1 V=1. IEEE wants every ordered relation FALSE for NaN and <> TRUE.
  Signed `lt` (N<>V) and `le` (Z or N<>V) both fire on unordered, so use the
  FP-safe `mi` (N==1) for < and `ls` (C==0 or Z==1) for <=. eq/ne (Z-based) and
  gt/ge (N==V, 0 on unordered) are already correct. }
begin
  EmitAsmArm32('mov r0, #0');
  if opTk = Ord(tkEq) then EmitAsmArm32('moveq r0, #1')
  else if opTk = Ord(tkNeq) then EmitAsmArm32('movne r0, #1')
  else if opTk = Ord(tkLt) then EmitAsmArm32('movmi r0, #1')
  else if opTk = Ord(tkLe) then EmitAsmArm32('movls r0, #1')
  else if opTk = Ord(tkGt) then EmitAsmArm32('movgt r0, #1')
  else if opTk = Ord(tkGe) then EmitAsmArm32('movge r0, #1')
  else Error('target arm32: unsupported float compare operator');
end;

procedure EmitHeapAllocLockedArm32;
{ r0 = requested payload bytes. Returns payload pointer in r0. }
var procIdx: Integer;
begin
  EmitI32($E92D000E);             { push {r1,r2,r3} }
  EmitI32($E3A01008);             { mov r1, #8 (alignment) }
  procIdx := FindProc('PXXAlloc');
  if procIdx < 0 then Error('compiler error: Alloc helper not found in builtin unit');
  EmitCallProc(procIdx);
  EmitI32($E8BD000E);             { pop {r1,r2,r3} }
end;

procedure EmitHeapFreeLockedArm32;
{ r0 = payload pointer. nil is ignored inside PXXFree. }
var procIdx: Integer;
begin
  EmitI32($E92D000E);             { push {r1,r2,r3} }
  procIdx := FindProc('PXXFree');
  if procIdx < 0 then Error('compiler error: Free helper not found in builtin unit');
  EmitCallProc(procIdx);
  EmitI32($E8BD000E);             { pop {r1,r2,r3} }
end;

procedure IREmitNodeArm32(node: Integer); forward;

procedure EmitStrIncRefArm32;
{ r0 = managed-string handle. Preserve r0-r3 for expression callers. }
var procIdx: Integer;
begin
  EmitI32($E92D000F);             { push {r0,r1,r2,r3} }
  procIdx := FindProc('PXXStrIncRef');
  if procIdx < 0 then Error('compiler error: PXXStrIncRef not found');
  EmitCallProc(procIdx);
  EmitI32($E8BD000F);             { pop {r0,r1,r2,r3} }
end;

procedure EmitStrDecRefArm32;
{ r0 = managed-string handle. r0 is clobbered. }
var procIdx: Integer;
begin
  EmitI32($E92D000E);             { push {r1,r2,r3} }
  procIdx := FindProc('PXXStrDecRef');
  if procIdx < 0 then Error('compiler error: PXXStrDecRef not found');
  EmitCallProc(procIdx);
  EmitI32($E8BD000E);             { pop {r1,r2,r3} }
end;

procedure EmitLoadDataRefArm32(rd, dataOff: Integer);
begin
  EmitI32($E59F0000 or (rd shl 12));  { ldr rd, [pc] }
  EmitI32($EA000000);                 { b .+8 }
  EmitDataRef(dataOff);
end;

procedure EmitIoLockStubsArm32;
{ --threadsafe statement-atomic console I/O, the arm32 port of EmitIoLockStubs.
  Reentrant owner-tid spinlock: BSS_IO_OWNER = owning tid (0 = free), BSS_IO_DEPTH
  = nesting depth (so a write-arg that itself writes cannot self-deadlock). gettid
  (svc 224) per I/O statement; LL/SC (ldrex/strex) spinlock with an explicit dmb
  ish barrier (ARM has no implicit acquire/release on ldrex/strex). Fronted by a
  branch so it is reached only via bl. r9=&owner, r10=&depth held across the
  gettid syscall (the EABI syscall preserves r4-r12). Hex verified vs clang. }
var jmpOver: Integer;
begin
  EmitI32($EA000000); jmpOver := CodeLen - 4;   { b .end (patched below) }
  IOLockAddr := CodeLen;
  EmitI32($E59F9000); EmitI32($EA000000); EmitGlobRef(BSS_IO_OWNER);   { ldr r9,[pc]; b; &owner }
  EmitI32($E59FA000); EmitI32($EA000000); EmitGlobRef(BSS_IO_DEPTH);   { ldr r10,[pc]; b; &depth }
  EmitI32($E3A070E0);   { mov r7, #224        gettid }
  EmitI32($EF000000);   { svc 0               r0 = tid }
  EmitI32($E5991000);   { ldr r1, [r9]        owner }
  EmitI32($E1510000);   { cmp r1, r0 }
  EmitI32($0A000006);   { beq bump  (+6, already ours) }
  EmitI32($E1991F9F);   { ldrex r1, [r9]      (spin) }
  EmitI32($E3510000);   { cmp r1, #0 }
  EmitI32($1AFFFFFC);   { bne spin  (-3, owned by other) }
  EmitI32($E1892F90);   { strex r2, r0, [r9]  take with our tid }
  EmitI32($E3520000);   { cmp r2, #0 }
  EmitI32($1AFFFFF9);   { bne spin  (-6, sc failed) }
  EmitI32($F57FF05B);   { dmb ish }
  EmitI32($E59A1000);   { ldr r1, [r10]       (bump) }
  EmitI32($E2811001);   { add r1, r1, #1 }
  EmitI32($E58A1000);   { str r1, [r10] }
  EmitI32($E12FFF1E);   { bx lr }

  IOUnlockAddr := CodeLen;
  EmitI32($E59F9000); EmitI32($EA000000); EmitGlobRef(BSS_IO_OWNER);   { ldr r9,[pc]; b; &owner }
  EmitI32($E59FA000); EmitI32($EA000000); EmitGlobRef(BSS_IO_DEPTH);   { ldr r10,[pc]; b; &depth }
  EmitI32($F57FF05B);   { dmb ish }
  EmitI32($E59A1000);   { ldr r1, [r10] }
  EmitI32($E2411001);   { sub r1, r1, #1 }
  EmitI32($E58A1000);   { str r1, [r10] }
  EmitI32($E3510000);   { cmp r1, #0 }
  EmitI32($1A000001);   { bne keep  (+1, still nested) }
  EmitI32($E3A02000);   { mov r2, #0 }
  EmitI32($E5892000);   { str r2, [r9]        release: owner := 0 }
  EmitI32($E12FFF1E);   { bx lr  (keep) }

  Patch32(jmpOver, $EA000000 or ((((CodeLen - jmpOver) div 4) - 2) and $00FFFFFF));
end;

{ ===== 64-bit (Int64/UInt64) value model: r0:r1 = lo:hi register pair =====
  Unlike the low-word fat-slot model for ordinary ordinals, true 8-byte values
  live in r0(low):r1(high) while in flight, are loaded/stored as two words, and
  have their own arithmetic/shift/compare sequences below. Mirrors the i386
  edx:eax model (ir_codegen386.inc). Producers of a 64-bit-typed node leave
  r0:r1; consumers needing only 32 bits keep r0 (correct truncation). }

function Is64BitArm32(tk: TTypeKind): Boolean;
begin
  Result := (tk = tyInt64) or (tk = tyUInt64);
end;

procedure EmitLoadVar64Arm32(idx: Integer);
{ Load an 8-byte slot into r0:r1 (lo:hi). r9 is the address scratch. }
begin
  if Syms[idx].Kind = skGlobal then
  begin
    EmitI32($E59F9000);  { ldr r9, [pc] }
    EmitI32($EA000000);  { b .+8 }
    EmitGlobRef(Syms[idx].Offset);
  end
  else
  begin
    EmitLoadImmArm32(9, Syms[idx].Offset);
    EmitI32($E08B9009);  { add r9, fp, r9 }
    if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then
      EmitI32($E5999000);  { ldr r9, [r9] (forwarded slot addr) }
  end;
  EmitI32($E5990000);  { ldr r0, [r9] (lo) }
  EmitI32($E5991004);  { ldr r1, [r9, #4] (hi) }
end;

procedure EmitStoreVar64Arm32(idx: Integer);
{ Store r0:r1 (lo:hi) into an 8-byte slot. r9 is the address scratch. }
begin
  if Syms[idx].Kind = skGlobal then
  begin
    EmitI32($E59F9000);  { ldr r9, [pc] }
    EmitI32($EA000000);  { b .+8 }
    EmitGlobRef(Syms[idx].Offset);
  end
  else
  begin
    EmitLoadImmArm32(9, Syms[idx].Offset);
    EmitI32($E08B9009);  { add r9, fp, r9 }
    if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then
      EmitI32($E5999000);  { ldr r9, [r9] }
  end;
  EmitI32($E5890000);  { str r0, [r9] (lo) }
  EmitI32($E5891004);  { str r1, [r9, #4] (hi) }
end;

procedure EmitNode64Arm32(node: Integer);
{ Emit node; guarantee its full 64-bit value sits in r0:r1. A 32-bit source is
  widened: sign-extend (signed) or zero-extend (unsigned) into r1. }
var ntk: TTypeKind;
begin
  IREmitNodeArm32(node);
  ntk := IntToTypeKind(IRTk[node]);
  if not Is64BitArm32(ntk) then
  begin
    if TypeSigned(ntk) then
      EmitI32($E1A01FC0)   { mov r1, r0, asr #31 }
    else
      EmitI32($E3A01000);  { mov r1, #0 }
  end;
end;

procedure EmitUDivMod64Arm32(wantMod: Boolean);
{ Unsigned 64-bit divide. Pre: [sp]=N.lo, [sp+4]=N.hi (dividend); divisor in
  r0:r1. Restoring binary long division, 64 iterations MSB-first. Post: the
  8-byte dividend is popped; quotient (or remainder when wantMod) in r0:r1.
  Clobbers r2..r6, r9. }
var loopOff, skip1, jaOff, skip2: Integer;
begin
  EmitI32($E59D2000);  { ldr r2, [sp]    (NQ.lo) }
  EmitI32($E59D3004);  { ldr r3, [sp, #4] (NQ.hi) }
  EmitI32($E3A04000);  { mov r4, #0  (R.lo) }
  EmitI32($E3A05000);  { mov r5, #0  (R.hi) }
  EmitI32($E3A06040);  { mov r6, #64 (count) }
  loopOff := CodeLen;
  EmitI32($E1B02082);  { lsls r2, r2, #1 }
  EmitI32($E0B33003);  { adcs r3, r3, r3 }
  EmitI32($E0B44004);  { adcs r4, r4, r4 }
  EmitI32($E0A55005);  { adc  r5, r5, r5 }
  EmitI32($E1550001);  { cmp r5, r1  (R.hi vs D.hi) }
  skip1 := CodeLen; EmitI32($3A000000);  { bcc .skip (R.hi < D.hi) }
  jaOff := CodeLen;  EmitI32($8A000000);  { bhi .sub (R.hi > D.hi) }
  EmitI32($E1540000);  { cmp r4, r0  (R.lo vs D.lo) }
  skip2 := CodeLen; EmitI32($3A000000);  { bcc .skip }
  Patch32(jaOff, $8A000000 or ((((CodeLen - jaOff) div 4) - 2) and $00ffffff));  { .sub: }
  EmitI32($E0544000);  { subs r4, r4, r0 }
  EmitI32($E0C55001);  { sbc  r5, r5, r1 }
  EmitI32($E3822001);  { orr  r2, r2, #1 (quotient bit) }
  Patch32(skip1, $3A000000 or ((((CodeLen - skip1) div 4) - 2) and $00ffffff));  { .skip: }
  Patch32(skip2, $3A000000 or ((((CodeLen - skip2) div 4) - 2) and $00ffffff));
  EmitI32($E2566001);  { subs r6, r6, #1 }
  EmitI32($1A000000 or ((((loopOff - CodeLen) div 4) - 2) and $00ffffff));  { bne .loop }
  EmitI32($E28DD008);  { add sp, sp, #8 (pop dividend) }
  if wantMod then
  begin
    EmitI32($E1A00004);  { mov r0, r4 }
    EmitI32($E1A01005);  { mov r1, r5 }
  end
  else
  begin
    EmitI32($E1A00002);  { mov r0, r2 }
    EmitI32($E1A01003);  { mov r1, r3 }
  end;
end;

procedure EmitIDivMod64Arm32(wantMod: Boolean);
{ Signed 64-bit divide/mod, same calling convention as the unsigned core.
  Truncated division: quotient sign = dividend xor divisor, remainder takes the
  dividend's sign. Operands are made non-negative in place, the unsigned core
  runs, then the result sign is applied. Sign flags live in r7 across the core
  (the core does not touch r7). }
var dpos, npos, doneOff: Integer;
begin
  EmitI32($E3A07000);  { mov r7, #0 (flags) }
  EmitI32($E3510000);  { cmp r1, #0 (divisor sign) }
  dpos := CodeLen; EmitI32($5A000000);  { bpl .dpos }
  EmitI32($E2700000);  { rsbs r0, r0, #0 }
  EmitI32($E2E11000);  { rsc  r1, r1, #0 (abs divisor) }
  EmitI32($E2277001);  { eor  r7, r7, #1 (negate quotient) }
  Patch32(dpos, $5A000000 or ((((CodeLen - dpos) div 4) - 2) and $00ffffff));  { .dpos: }
  EmitI32($E59D2000);  { ldr r2, [sp]    (N.lo) }
  EmitI32($E59D3004);  { ldr r3, [sp, #4] (N.hi) }
  EmitI32($E3530000);  { cmp r3, #0 (dividend sign) }
  npos := CodeLen; EmitI32($5A000000);  { bpl .npos }
  EmitI32($E2722000);  { rsbs r2, r2, #0 }
  EmitI32($E2E33000);  { rsc  r3, r3, #0 (abs dividend) }
  EmitI32($E58D2000);  { str r2, [sp] }
  EmitI32($E58D3004);  { str r3, [sp, #4] }
  EmitI32($E2277001);  { eor r7, r7, #1 (flip quotient negate) }
  EmitI32($E3877002);  { orr r7, r7, #2 (negate remainder) }
  Patch32(npos, $5A000000 or ((((CodeLen - npos) div 4) - 2) and $00ffffff));  { .npos: }
  EmitUDivMod64Arm32(wantMod);  { result in r0:r1 }
  if wantMod then
    EmitI32($E3170002)   { tst r7, #2 }
  else
    EmitI32($E3170001);  { tst r7, #1 }
  doneOff := CodeLen; EmitI32($0A000000);  { beq .done }
  EmitI32($E2700000);  { rsbs r0, r0, #0 }
  EmitI32($E2E11000);  { rsc  r1, r1, #0 (apply sign) }
  Patch32(doneOff, $0A000000 or ((((CodeLen - doneOff) div 4) - 2) and $00ffffff));  { .done: }
end;

procedure EmitBinop64Arm32(left, right, op: Integer; signedOp: Boolean);
{ Evaluate (left OP right) as a 64-bit operation. left is spilled to the stack
  ([sp]=lo, [sp+4]=hi); right is materialised into r0:r1. Arithmetic/bit ops
  leave the 64-bit result in r0:r1; comparisons leave 0/1 in r0. }
begin
  EmitNode64Arm32(left);
  EmitI32($E92D0003);   { push {r0, r1} (left lo, hi) }
  EmitNode64Arm32(right);  { right -> r0:r1 }

  if (op = Ord(tkDiv)) or (op = Ord(tkMod)) then
  begin
    if signedOp then EmitIDivMod64Arm32(op = Ord(tkMod))
    else EmitUDivMod64Arm32(op = Ord(tkMod));
    Exit;
  end;

  if (op = Ord(tkShl)) or (op = Ord(tkIdent)) or (op = Ord(tkShr)) then
  begin
    { shift count in r0 (right.lo); value = left popped into r2:r3. }
    EmitI32($E8BD000C);  { pop {r2, r3} (value lo, hi) }
    EmitI32($E250C020);  { subs r12, r0, #32 (n-32) }
    if op = Ord(tkShl) then
    begin
      { n>=32: hi = lo << (n-32); lo = 0 }
      EmitI32($51A01C12);  { lslpl r1, r2, r12 }
      EmitI32($53A00000);  { movpl r0, #0 }
      { n<32: hi = (hi<<n)|(lo>>(32-n)); lo = lo<<n }
      EmitI32($4260C020);  { rsbmi r12, r0, #32 }
      EmitI32($41A01013);  { lslmi r1, r3, r0 }
      EmitI32($41811C32);  { orrmi r1, r1, r2, lsr r12 }
      EmitI32($41A00012);  { lslmi r0, r2, r0 }
    end
    else if (op = Ord(tkShr)) and signedOp then
    begin
      { C signed '>>' — arithmetic. n>=32: lo = hi>>a(n-32); hi = sign(hi) }
      EmitI32($51A00C53);  { asrpl r0, r3, r12 }
      EmitI32($51A01FC3);  { asrpl r1, r3, #31 (sign-fill hi) }
      { n<32: lo = (lo>>n)|(hi<<(32-n)); hi = hi>>a n }
      EmitI32($4260C020);  { rsbmi r12, r0, #32 }
      EmitI32($41A04C13);  { lslmi r4, r3, r12 (hi<<(32-n)) }
      EmitI32($41A01053);  { asrmi r1, r3, r0  (hi>>a n) }
      EmitI32($41A00032);  { lsrmi r0, r2, r0  (lo>>n, logical for lo bits) }
      EmitI32($41800004);  { orrmi r0, r0, r4 }
    end
    else
    begin
      { Pascal 'shr' (tkIdent) or C unsigned '>>' — logical.
        n>=32: lo = hi>>(n-32); hi = 0 }
      EmitI32($51A00C33);  { lsrpl r0, r3, r12 }
      EmitI32($53A01000);  { movpl r1, #0 }
      { n<32: lo = (lo>>n)|(hi<<(32-n)); hi = hi>>n }
      EmitI32($4260C020);  { rsbmi r12, r0, #32 }
      EmitI32($41A04C13);  { lslmi r4, r3, r12 (hi<<(32-n)) }
      EmitI32($41A01033);  { lsrmi r1, r3, r0  (hi>>n) }
      EmitI32($41A00032);  { lsrmi r0, r2, r0  (lo>>n) }
      EmitI32($41800004);  { orrmi r0, r0, r4 }
    end;
    Exit;
  end;

  EmitI32($E8BD000C);  { pop {r2, r3} (left lo, hi) }

  if op = Ord(tkPlus) then
  begin
    EmitI32($E0920000);  { adds r0, r2, r0 }
    EmitI32($E0A31001);  { adc  r1, r3, r1 }
  end
  else if op = Ord(tkMinus) then
  begin
    EmitI32($E0520000);  { subs r0, r2, r0 }
    EmitI32($E0C31001);  { sbc  r1, r3, r1 }
  end
  else if op = Ord(tkStar) then
  begin
    { A=left(r2:r3), B=right(r0:r1). low 64 of A*B. }
    EmitI32($E0010192);  { mul r1, r2, r1  (Alo*Bhi) }
    EmitI32($E0030093);  { mul r3, r3, r0  (Ahi*Blo) }
    EmitI32($E0811003);  { add r1, r1, r3  (cross) }
    EmitI32($E08C3092);  { umull r3, r12, r2, r0 (Alo*Blo) }
    EmitI32($E08C1001);  { add r1, r12, r1 (hi += high(Alo*Blo)) }
    EmitI32($E1A00003);  { mov r0, r3 (lo) }
  end
  else if op = Ord(tkAnd) then
  begin
    EmitI32($E0020000);  { and r0, r2, r0 }
    EmitI32($E0031001);  { and r1, r3, r1 }
  end
  else if op = Ord(tkOr) then
  begin
    EmitI32($E1820000);  { orr r0, r2, r0 }
    EmitI32($E1831001);  { orr r1, r3, r1 }
  end
  else if op = Ord(tkXor) then
  begin
    EmitI32($E0220000);  { eor r0, r2, r0 }
    EmitI32($E0231001);  { eor r1, r3, r1 }
  end
  else if (op = Ord(tkEq)) or (op = Ord(tkNeq)) then
  begin
    EmitI32($E0222000);  { eor r2, r2, r0 (lo diff) }
    EmitI32($E0233001);  { eor r3, r3, r1 (hi diff) }
    EmitI32($E1822003);  { orr r2, r2, r3 (0 iff equal) }
    EmitI32($E3520000);  { cmp r2, #0 }
    EmitI32($E3A00000);  { mov r0, #0 }
    if op = Ord(tkEq) then EmitI32($03A00001)   { moveq r0, #1 }
    else EmitI32($13A00001);                     { movne r0, #1 }
  end
  else if (op = Ord(tkLt)) or (op = Ord(tkLe)) or
          (op = Ord(tkGt)) or (op = Ord(tkGe)) then
  begin
    { Avoid relying on Z (sbcs sets Z from the high word only). lt/ge subtract
      left-right; gt/le subtract right-left, so the result uses only the
      Z-free conditions lt/lo (for lt,gt) or ge/hs (for le,ge). }
    if (op = Ord(tkLt)) or (op = Ord(tkGe)) then
    begin
      EmitI32($E0522000);  { subs r2, r2, r0 (left.lo-right.lo) }
      EmitI32($E0D33001);  { sbcs r3, r3, r1 (left.hi-right.hi) }
    end
    else
    begin
      EmitI32($E0500002);  { subs r0, r0, r2 (right.lo-left.lo) }
      EmitI32($E0D11003);  { sbcs r1, r1, r3 (right.hi-left.hi) }
    end;
    EmitI32($E3A00000);  { mov r0, #0 }
    if (op = Ord(tkLt)) or (op = Ord(tkGt)) then
    begin
      if signedOp then EmitI32($B3A00001)   { movlt r0, #1 }
      else EmitI32($33A00001);               { movlo r0, #1 }
    end
    else
    begin
      if signedOp then EmitI32($A3A00001)   { movge r0, #1 }
      else EmitI32($23A00001);               { movhs r0, #1 }
    end;
  end
  else
    Error('target arm32: 64-bit binop operator not yet supported');
end;

procedure EmitwriteUInt64Arm32;
{ r0:r1 = unsigned 64-bit value -> decimal on stdout. Repeated divide-by-10 via
  a 64-iteration bit loop; digits grow downward from the INTBUF tail. }
var digitLoop, bitLoop, noSub: Integer;
begin
  EmitI32($E3A08000);  { mov r8, #0 (digit count) }
  EmitI32($E59F5000);  { ldr r5, [pc] }
  EmitI32($EA000000);  { b .+8 }
  EmitGlobRef(BSS_INTBUF + INTBUF_SIZE);
  digitLoop := CodeLen;
  EmitI32($E3A02000);  { mov r2, #0 (remainder) }
  EmitI32($E3A03040);  { mov r3, #64 (bit count) }
  bitLoop := CodeLen;
  EmitI32($E1B00080);  { lsls r0, r0, #1 }
  EmitI32($E0B11001);  { adcs r1, r1, r1 }
  EmitI32($E0A22002);  { adc  r2, r2, r2 }
  EmitI32($E352000A);  { cmp r2, #10 }
  noSub := CodeLen; EmitI32($3A000000);  { blo .nosub }
  EmitI32($E242200A);  { sub r2, r2, #10 }
  EmitI32($E3800001);  { orr r0, r0, #1 }
  Patch32(noSub, $3A000000 or ((((CodeLen - noSub) div 4) - 2) and $00ffffff));  { .nosub: }
  EmitI32($E2533001);  { subs r3, r3, #1 }
  EmitI32($1A000000 or ((((bitLoop - CodeLen) div 4) - 2) and $00ffffff));  { bne .bitLoop }
  EmitI32($E2822030);  { add r2, r2, #48 (ascii) }
  EmitI32($E2455001);  { sub r5, r5, #1 }
  EmitI32($E5C52000);  { strb r2, [r5] }
  EmitI32($E2888001);  { add r8, r8, #1 }
  EmitI32($E1903001);  { orrs r3, r0, r1 (quotient == 0 ?) }
  EmitI32($1A000000 or ((((digitLoop - CodeLen) div 4) - 2) and $00ffffff));  { bne .digitLoop }
  EmitI32($E1A02008);  { mov r2, r8 (len) }
  EmitI32($E1A01005);  { mov r1, r5 (buf) }
  EmitI32($E3A00001);  { mov r0, #1 (stdout) }
  EmitI32($E3A07004);  { mov r7, #4 (write) }
  EmitI32($EF000000);  { svc #0 }
end;

procedure EmitwriteInt64Arm32;
{ r0:r1 = signed 64-bit value -> decimal on stdout. }
var posOff: Integer;
begin
  EmitI32($E3510000);  { cmp r1, #0 }
  posOff := CodeLen; EmitI32($5A000000);  { bpl .positive }
  EmitI32($E2700000);  { rsbs r0, r0, #0 }
  EmitI32($E2E11000);  { rsc  r1, r1, #0 (negate) }
  EmitI32($E92D0003);  { push {r0, r1} }
  EmitwriteSyscallArm32(MINUS_OFFSET, 1);
  EmitI32($E8BD0003);  { pop {r0, r1} }
  Patch32(posOff, $5A000000 or ((((CodeLen - posOff) div 4) - 2) and $00ffffff));  { .positive: }
  EmitwriteUInt64Arm32;
end;


procedure EmitLoadArgvPtrArm32;
{ On entry r0 = argv index. Returns r0 = argv[index] C-string pointer. }
begin
  EmitI32($E1A00100);                 { lsl r0, r0, #2 }
  EmitI32($E59F1000);                 { ldr r1, [pc] }
  EmitI32($EA000000);                 { b .+8 }
  EmitGlobRef(BSS_INITIAL_RSP);
  EmitI32($E5911000);                 { ldr r1, [r1] = initial sp }
  EmitI32($E2811004);                 { add r1, r1, #4 (argv base) }
  EmitI32($E0810000);                 { add r0, r1, r0 }
  EmitI32($E5900000);                 { ldr r0, [r0] = argv[index] }
end;

procedure EmitArgvToAnsiStringArm32;
{ On entry r0 = argv index. Returns r0 = managed string handle. }
var procIdx, loopStart, donePos: Integer;
begin
  EmitLoadArgvPtrArm32;               { r0 = src }
  EmitI32($E1A01000);                 { mov r1, r0 (src) }
  EmitI32($E3A02000);                 { mov r2, #0 (len) }
  loopStart := CodeLen;
  EmitI32($E7D13002);                 { ldrb r3, [r1, r2] }
  EmitI32($E3530000);                 { cmp r3, #0 }
  donePos := CodeLen;
  EmitI32($0A000000);                 { beq done }
  EmitI32($E2822001);                 { add r2, r2, #1 }
  EmitI32($EA000000 or ((((loopStart - CodeLen) div 4) - 2) and $00ffffff));
  Patch32(donePos, $0A000000 or ((((CodeLen - donePos) div 4) - 2) and $00ffffff));
  EmitI32($E1A00002);                 { mov r0, r2 (len) }
  procIdx := FindProc('PXXStrFromLit');
  if procIdx < 0 then Error('compiler error: PXXStrFromLit not found');
  EmitCallProc(procIdx);                   { r0 = managed handle }
end;

procedure EmitArgvToFixedStringArm32(dstIdx: Integer);
{ On entry r0 = argv index. Copy argv[index] into fixed string dstIdx. }
var loopStart, donePos, capDone: Integer;
begin
  EmitLoadArgvPtrArm32;               { r0 = src }
  EmitI32($E1A05000);                 { mov r5, r0 (src) }
  EmitI32($E3A04000);                 { mov r4, #0 (len) }
  loopStart := CodeLen;
  EmitI32($E7D58004);                 { ldrb r8, [r5, r4] }
  EmitI32($E3580000);                 { cmp r8, #0 }
  donePos := CodeLen;
  EmitI32($0A000000);                 { beq done }
  EmitI32($E2844001);                 { add r4, r4, #1 }
  EmitI32($EA000000 or ((((loopStart - CodeLen) div 4) - 2) and $00ffffff));
  Patch32(donePos, $0A000000 or ((((CodeLen - donePos) div 4) - 2) and $00ffffff));
  EmitI32($E3540C01);                 { cmp r4, #256 }
  capDone := CodeLen;
  EmitI32($DA000000);                 { ble cap_done }
  EmitLoadImmArm32(4, 256);
  Patch32(capDone, $DA000000 or ((((CodeLen - capDone) div 4) - 2) and $00ffffff));
  EmitLoadVarAddrArm32(dstIdx);       { r0 = dst }
  EmitI32($E5804000);                 { str r4, [r0] }
  EmitI32($E3A01000);                 { mov r1, #0 }
  EmitI32($E5801004);                 { str r1, [r0, #4] }
  EmitI32($E2806008);                 { add r6, r0, #8 }
  EmitArm32CopyBytes(4, 5, 6);
end;

{ ---- Float support (VFP). Value model: float-typed IR nodes leave their
  value in d0 (a second channel besides r0); spills use vpush/vpop. Float ->
  text goes through the portable builtinheap helpers (PXXWriteFloat*). ---- }

procedure EmitIntToD0Arm32;
{ signed r0 -> d0 }
begin
  EmitI32($EE000A10);  { vmov s0, r0 }
  EmitI32($EEB80BC0);  { vcvt.f64.s32 d0, s0 }
end;

procedure EmitWriteCStrArm32;
{ r0 = PChar (NUL-terminated) -> strlen + write to stdout. Mirrors x86-64
  EmitWriteCStr so write(PChar) prints the string, not the pointer value. }
begin
  EmitI32($E1A01000);   { mov r1, r0 (buf) }
  EmitI32($E3A02000);   { mov r2, #0 (len) }
  { scan: }
  EmitI32($E5D03000);   { ldrb r3, [r0] }
  EmitI32($E3530000);   { cmp r3, #0 }
  EmitI32($0A000002);   { beq done }
  EmitI32($E2800001);   { add r0, r0, #1 }
  EmitI32($E2822001);   { add r2, r2, #1 }
  EmitI32($EAFFFFF9);   { b scan }
  { done: }
  EmitI32($E3A00001);   { mov r0, #1 (stdout) }
  EmitI32($E3A07004);   { mov r7, #4 (sys_write) }
  EmitI32($EF000000);   { svc #0 }
end;

procedure EmitFloatCallWriterArm32(const name: AnsiString; decs: Integer);
{ d0 = value. Spill to a stack slot, pass its address (plus decimals for the
  fixed writer) to the builtinheap float writer. }
var procIdx: Integer;
begin
  EmitI32($ED2D0B02);            { vpush {d0} }
  EmitI32($E1A0000D);            { mov r0, sp (slot addr) }
  if decs >= 0 then
    EmitLoadImmArm32(1, decs);   { r1 = decimals }
  procIdx := FindProc(name);
  if procIdx < 0 then Error('compiler error: float writer helper not found');
  EmitCallProc(procIdx);
  EmitI32($E28DD008);            { add sp, sp, #8 (drop slot) }
end;

procedure EmitVarHelperCallArm32(const name: AnsiString);
{ r0 = variant slot address; r0-r3 preserved. }
var procIdx: Integer;
begin
  EmitI32($E92D000F);            { push {r0-r3} }
  procIdx := FindProc(name);
  if procIdx < 0 then Error('compiler error: variant helper not found');
  EmitCallProc(procIdx);
  EmitI32($E8BD000F);            { pop {r0-r3} }
end;

procedure EmitVariantFillArm32(tag: Integer; payloadTk: TTypeKind);
{ r0 = variant slot address; payload on the stack: vpush'd d0 for a double,
  else a pushed 4-byte word. Clears the old value, stores tag + payload,
  leaves the slot address in r0. }
begin
  EmitVarHelperCallArm32('PXXVarClear');
  EmitLoadImmArm32(1, tag);
  EmitI32($E5801000);                  { str r1, [r0] }
  EmitI32($E3A01000);                  { mov r1, #0 }
  EmitI32($E5801004);                  { str r1, [r0, #4] }
  if TypeIsFloat(payloadTk) then
  begin
    EmitI32($ECBD0B02);                { vpop {d0} }
    EmitI32($ED800B02);                { vstr d0, [r0, #8] }
  end
  else
  begin
    EmitI32($E8BD0002);                { pop {r1} (payload) }
    EmitI32($E5801008);                { str r1, [r0, #8] }
    if tag = VT_INT then
    begin
      EmitI32($E1A02FC1);              { asr r2, r1, #31 (sign) }
      EmitI32($E580200C);              { str r2, [r0, #12] }
    end
    else
    begin
      EmitI32($E3A02000);              { mov r2, #0 }
      EmitI32($E580200C);              { str r2, [r0, #12] }
    end;
  end;
end;

procedure EmitLoadVariantAddrArm32(node: Integer);
{ Address of a variant slot for value-position variant nodes. }
begin
  if IRKind[node] = IR_LOAD_SYM then
    EmitLoadVarAddrArm32(IRA[node])
  else if IRKind[node] = IR_LOAD_MEM then
    IREmitNodeArm32(IRA[node])
  else
    IREmitNodeArm32(node);
end;

procedure EmitAnsiStringFromNodeArm32(valNode: Integer);
{ Build a managed AnsiString handle in r0 from a char, inline string, literal,
  or existing AnsiString-like expression. Existing handles are retained unless
  they are fresh owners produced by concat/user function results. }
var sVal: AnsiString; si, procIdx: Integer; tk: TTypeKind;
begin
  if IRKind[valNode] = IR_CONST_STR then
  begin
    sVal := GetTokenStrFromRaw(IRA[valNode], IRB[valNode]);
    si := InternStr(sVal);
    EmitLoadImmArm32(0, Strs[si].Len);
    EmitLoadDataRefArm32(1, Strs[si].Offset + 8);
    procIdx := FindProc('PXXStrFromLit');
    if procIdx < 0 then Error('compiler error: PXXStrFromLit not found');
    EmitCallProc(procIdx);
    Exit;
  end;

  tk := IntToTypeKind(IRTk[valNode]);
  if tk = tyChar then
  begin
    IREmitNodeArm32(valNode);       { r0 = char code }
    EmitI32($E92D0001);             { push {r0}; byte lives at [sp] }
    EmitI32($E3A00001);             { mov r0, #1 }
    EmitI32($E28D1000);             { add r1, sp, #0 }
    procIdx := FindProc('PXXStrFromLit');
    if procIdx < 0 then Error('compiler error: PXXStrFromLit not found');
    EmitCallProc(procIdx);
    EmitI32($E28DD004);             { add sp, sp, #4 }
  end
  else if TypeIsFrozenString(tk) then
  begin
    IREmitNodeArm32(valNode);       { r0 = inline string buffer }
    EmitI32($E1A02000);             { mov r2, r0 }
    EmitI32($E5920000);             { ldr r0, [r2] (len) }
    EmitI32($E2821008);             { add r1, r2, #8 (src) }
    procIdx := FindProc('PXXStrFromLit');
    if procIdx < 0 then Error('compiler error: PXXStrFromLit not found');
    EmitCallProc(procIdx);
  end
  else
  begin
    IREmitNodeArm32(valNode);       { r0 = handle }
    if not (((IRKind[valNode] = IR_BINOP) and
             (IntToTypeKind(IRTk[valNode]) = tyAnsiString)) or
            ((IRKind[valNode] = IR_CALL) and (IRA[valNode] >= 0))) then
      EmitStrIncRefArm32;
  end;
end;

procedure EmitArm32StringParts(valueReg, srcReg, lenReg: Integer; tk: TTypeKind;
                               charStackOff: Integer);
{ Convert an evaluated string operand into (src,len). For tyChar, valueReg is
  the pushed word value and charStackOff points to that byte on the stack. }
var jmpPos: Integer;
begin
  if tk = tyAnsiString then
  begin
    EmitI32($E1A00000 or (srcReg shl 12) or valueReg); { mov src, value }
    EmitLoadImmArm32(lenReg, 0);
    EmitI32($E3500000 or (valueReg shl 16));           { cmp value, #0 }
    jmpPos := CodeLen;
    EmitI32($0A000000);                                { beq done }
    EmitI32($E5100008 or (valueReg shl 16) or (lenReg shl 12)); { ldr len, [value,#-8] }
    Patch32(jmpPos, $0A000000 or ((((CodeLen - jmpPos) div 4) - 2) and $00ffffff));
  end
  else if TypeIsFrozenString(tk) then
  begin
    EmitI32($E5900000 or (valueReg shl 16) or (lenReg shl 12)); { ldr len, [value] }
    EmitI32($E2800008 or (valueReg shl 16) or (srcReg shl 12)); { add src, value, #8 }
  end
  else
  begin
    EmitLoadImmArm32(lenReg, 1);
    if (charStackOff >= 0) and (charStackOff <= 255) then
      EmitI32($E28D0000 or (srcReg shl 12) or charStackOff)     { add src, sp, #off }
    else
    begin
      EmitLoadImmArm32(srcReg, charStackOff);
      EmitI32($E08D0000 or (srcReg shl 12) or srcReg);          { add src, sp, src }
    end;
  end;
end;

procedure EmitArm32CopyBytes(countReg, srcReg, dstReg: Integer);
var donePos, loopStart: Integer;
begin
  EmitI32($E3500000 or (countReg shl 16)); { cmp count, #0 }
  donePos := CodeLen;
  EmitI32($0A000000);                      { beq done }
  loopStart := CodeLen;
  EmitI32($E5D08000 or (srcReg shl 16));   { ldrb r8, [src] }
  EmitI32($E5C08000 or (dstReg shl 16));   { strb r8, [dst] }
  EmitI32($E2800001 or (srcReg shl 16) or (srcReg shl 12)); { add src, src, #1 }
  EmitI32($E2800001 or (dstReg shl 16) or (dstReg shl 12)); { add dst, dst, #1 }
  EmitI32($E2500001 or (countReg shl 16) or (countReg shl 12)); { subs count, count, #1 }
  EmitI32($1A000000 or ((((loopStart - CodeLen) div 4) - 2) and $00ffffff));
  Patch32(donePos, $0A000000 or ((((CodeLen - donePos) div 4) - 2) and $00ffffff));
end;

procedure IREmitNodeArm32(node: Integer);
var
  valNode, si, left, right, op, procIdx, argNode, nArgs, i, j, wid, sz: Integer;
  classIdx, elemSize, lo, nBlock: Integer;
  vaRevM, vaRevP, vaRevO1, vaRevO2: Integer;
  itemNode, hi, p1, p2: Integer;
  lhsTk, rhsTk: TTypeKind;
  sVal: AnsiString;
  tk: TTypeKind;
  sgn, savedLValueWrite: Boolean;
begin
  if node = -1 then Exit;
  case IRKind[node] of
    IR_NOP, IR_BLOCK: ;

    IR_ASM:
      begin
        { Inline asm block: replay the parse-time-captured text lines
          (AsmParseBodyTextArm32, asmenc.inc) through the arm32 text engine.
          Emitting here, at final code positions, makes label fixups and
          @glob relocations natively correct. Labels are block-scoped. }
        AsmArm32BlockBegin;
        for i := IRA[node] to IRA[node] + IRB[node] - 1 do
          AsmArm32ProcessInlineLine(i);
        AsmArm32BlockResolve;
      end;

    IR_CONST_INT:
      begin
        if TypeIsFloat(IntToTypeKind(IRTk[node])) then
        begin
          { Float literal: raw double bits -> d0 via r0:r1. }
          EmitI32($E59F0004);                                  { ldr r0, [pc, #4] (lo) }
          EmitI32($E59F1004);                                  { ldr r1, [pc, #4] (hi) }
          EmitI32($EA000001);                                  { b past the data }
          EmitI32(Integer(IRIVal[node] and $FFFFFFFF));
          EmitI32(Integer(IRIVal[node] shr 32));
          EmitI32($EC410B10);                                  { vmov d0, r0, r1 }
          Exit;
        end;
        if Is64BitArm32(IntToTypeKind(IRTk[node])) then
        begin
          { Full 64-bit literal -> r0:r1 (lo:hi). }
          EmitLoadImmArm32(0, Integer(IRIVal[node] and $FFFFFFFF));
          EmitLoadImmArm32(1, Integer(IRIVal[node] shr 32));
          Exit;
        end;
        EmitLoadImmArm32(0, IRIVal[node]);
      end;

    IR_CONST_STR:
      begin
        sVal := GetTokenStrFromRaw(IRA[node], IRB[node]);
        si := InternStr(sVal);
        EmitLoadDataRefArm32(0, Strs[si].Offset);
      end;

    IR_CONST_DATA:
      { Absolute data address (sentinel-resolvable), see the x86-64 case. }
      EmitLoadDataRefArm32(0, Integer(IRIVal[node]));

    IR_FRAME:
      { get_frame: fp (r11) is the frame pointer (push {fp,lr}; mov fp, sp). }
      EmitI32($E1A0000B); { mov r0, fp }

    IR_LOAD_SYM:
      begin
        si := IRA[node];
        tk := Syms[si].TypeKind;
        if TypeIsFloat(tk) then
        begin
          { Float load -> d0 (Single widened to double). Address -> r1. }
          if Syms[si].Kind = skGlobal then
          begin
            EmitI32($E59F1000);  { ldr r1, [pc] }
            EmitI32($EA000000);  { b .+8 }
            EmitGlobRef(Syms[si].Offset);
          end
          else
          begin
            EmitLoadImmArm32(9, Syms[si].Offset);
            EmitI32($E08B1009);  { add r1, fp, r9 }
            if (Syms[si].Kind = skParam) and Syms[si].IsRef then
              EmitI32($E5911000); { ldr r1, [r1] }
          end;
          if tk = tySingle then
          begin
            EmitI32($ED910A00);  { vldr s0, [r1] }
            EmitI32($EEB70AC0);  { vcvt.f64.f32 d0, s0 }
          end
          else
            EmitI32($ED910B00);  { vldr d0, [r1] }
          Exit;
        end;
        if tk = tyVariant then
        begin
          EmitLoadVariantAddrArm32(node);
          Exit;
        end;
        if Is64BitArm32(tk) or
           ((tk = tyRecord) and not Syms[si].IsArray and
            (RecSize(Syms[si].RecName) > 4) and (RecSize(Syms[si].RecName) <= 8)) then
        begin
          { A 5-8 byte record VALUE (e.g. a by-value call argument load, or a
            whole-record read) needs both words -- EmitLoadVar64Arm32 is type-
            agnostic (raw 8-byte load, already by-ref-aware), so it works
            unchanged for a record the same way it does for Int64/UInt64.
            Without this, `tk = tyRecord` fell through to the 1-word
            EmitLoadVarArm32 below, silently dropping the record's high 4
            bytes for any record over 4 bytes
            (bug-arm32-record-byvalue-over-4-bytes-abi-gap). }
          EmitLoadVar64Arm32(si);
          Exit;
        end;
        EmitLoadVarArm32(si);
      end;

    IR_STORE_SYM:
      begin
        si := IRA[node];
        if Syms[si].TypeKind = tyAnsiString then
        begin
          valNode := IRB[node];
          if (IRKind[valNode] = IR_CALL) and (IRA[valNode] = -Ord(tkArgStr)) then
          begin
            argNode := IRB[valNode];
            IREmitNodeArm32(IRA[argNode]);            { r0 = argv index }
            EmitArgvToAnsiStringArm32;                { r0 = new handle }
          end
          else
            EmitAnsiStringFromNodeArm32(valNode);     { r0 = new handle }
          if (Syms[si].Kind = skParam) and Syms[si].IsRef then
          begin
            EmitI32($E92D0001);                       { push {r0} new }
            EmitLoadImmArm32(9, Syms[si].Offset);
            EmitI32($E08B9009);                       { add r9, fp, r9 }
            EmitI32($E5991000);                       { ldr r1, [r9] slot addr }
            EmitI32($E5910000);                       { ldr r0, [r1] old }
            EmitI32($E59D2000);                       { ldr r2, [sp] new }
            EmitI32($E5812000);                       { str r2, [r1] }
            EmitStrDecRefArm32;
            EmitI32($E28DD004);                       { add sp, sp, #4 }
          end
          else
          begin
            EmitI32($E92D0001);                       { push {r0} new }
            EmitLoadVarArm32(si);                     { r0 = old }
            EmitStrDecRefArm32;
            EmitI32($E8BD0001);                       { pop {r0} new }
            EmitStoreVarArm32(si);
          end;
          Exit;
        end;
        if TypeIsFrozenString(Syms[si].TypeKind) and not Syms[si].IsArray then
        begin
          { Frozen inline-string assignment (s := <string>): copy [len:8][chars]
            from the source into s's buffer (r6=dst, r5=src, r4=count). Without
            this the scalar store below dropped the source address into s. }
          valNode := IRB[node];
          IREmitNodeArm32(valNode);                   { r0 = source addr (or char) }
          EmitI32($E92D0001);                         { push {r0} }
          if Syms[si].Kind = skGlobal then
          begin
            EmitI32($E59F6000);                       { ldr r6, [pc] }
            EmitI32($EA000000);                       { b .+8 }
            EmitGlobRef(Syms[si].Offset);
          end
          else if Syms[si].Kind = skParam then
          begin
            EmitLoadImmArm32(9, Syms[si].Offset);
            EmitI32($E08B9009);                       { add r9, fp, r9 }
            EmitI32($E5996000);                       { ldr r6, [r9] (forwarded ptr) }
          end
          else
          begin
            EmitLoadImmArm32(9, Syms[si].Offset);
            EmitI32($E08B6009);                       { add r6, fp, r9 (local buffer) }
          end;
          EmitI32($E8BD0020);                         { pop {r5} (src/char) }
          if IntToTypeKind(IRTk[valNode]) = tyChar then
          begin
            { r5 = char ordinal -> [len=1][char] }
            EmitLoadImmArm32(9, 1);
            EmitI32($E5869000);                       { str r9, [r6] (len=1) }
            EmitLoadImmArm32(9, 0);
            EmitI32($E5869004);                       { str r9, [r6,#4] }
            EmitI32($E5C65008);                       { strb r5, [r6,#8] }
            Exit;
          end;
          EmitI32($E5959000);                         { ldr r9, [r5] (len lo) }
          EmitI32($E5869000);                         { str r9, [r6] }
          EmitI32($E5959004);                         { ldr r9, [r5,#4] (len hi) }
          EmitI32($E5869004);                         { str r9, [r6,#4] }
          EmitI32($E5954000);                         { ldr r4, [r5] (count) }
          EmitI32($E2855008);                         { add r5, r5, #8 }
          EmitI32($E2866008);                         { add r6, r6, #8 }
          EmitArm32CopyBytes(4, 5, 6);
          Exit;
        end;
        tk := Syms[si].TypeKind;
        if TypeIsFloat(tk) then
        begin
          IREmitNodeArm32(IRB[node]);                 { value -> d0 (or r0) }
          if not TypeIsFloat(IntToTypeKind(IRTk[IRB[node]])) then
            EmitIntToD0Arm32;
          if tk = tySingle then
            EmitI32($EEB70BC0);                       { vcvt.f32.f64 s0, d0 }
          if Syms[si].Kind = skGlobal then
          begin
            EmitI32($E59F1000);  { ldr r1, [pc] }
            EmitI32($EA000000);  { b .+8 }
            EmitGlobRef(Syms[si].Offset);
          end
          else
          begin
            EmitLoadImmArm32(9, Syms[si].Offset);
            EmitI32($E08B1009);  { add r1, fp, r9 }
            if (Syms[si].Kind = skParam) and Syms[si].IsRef then
              EmitI32($E5911000); { ldr r1, [r1] }
          end;
          if tk = tySingle then
            EmitI32($ED810A00)   { vstr s0, [r1] }
          else
            EmitI32($ED810B00);  { vstr d0, [r1] }
          Exit;
        end;
        if TypeIsFrozenString(tk) and not Syms[si].IsArray and
           (IRKind[IRB[node]] = IR_CALL) and (IRA[IRB[node]] = -Ord(tkArgStr)) then
        begin
          argNode := IRB[IRB[node]];
          IREmitNodeArm32(IRA[argNode]);              { r0 = argv index }
          EmitArgvToFixedStringArm32(si);
          Exit;
        end;
        if TypeIsFrozenString(tk) and not Syms[si].IsArray and
           (IntToTypeKind(IRTk[IRB[node]]) in [tyString, tyAnsiString]) then
        begin
          { Legacy inline string struct ([len:8][data]) assignment: copy the
            whole struct into the slot, not just a pointer (mirrors the x86-64
            len-field + rep-movsb store). The source — a string literal or a
            tyString-returning call result — leaves the struct's address in r0. }
          IREmitNodeArm32(IRB[node]);                  { r0 = source struct addr }
          EmitI32($E1A05000);                          { mov r5, r0 (src) }
          EmitLoadVarAddrArm32(si);                    { r0 = dest slot address }
          EmitI32($E1A06000);                          { mov r6, r0 (dst) }
          EmitI32($E5954000);                          { ldr r4, [r5] (len low word) }
          EmitI32($E2844008);                          { add r4, r4, #8 (len field + data) }
          EmitArm32CopyBytes(4, 5, 6);
          Exit;
        end;
        if Is64BitArm32(tk) then
        begin
          EmitNode64Arm32(IRB[node]);
          EmitStoreVar64Arm32(IRA[node]);
          Exit;
        end;
        IREmitNodeArm32(IRB[node]);
        { C double->int: a float RHS (in d0) stored to an integer slot truncates
          via VFP vcvt.s32.f64 (arm32 `long` is 32-bit, so 32-bit convert suffices)
          instead of storing raw bits from r0. Mirrors x86-64/i386/aarch64. }
        if CProgramMode and (not TypeIsFloat(tk)) and
           TypeIsFloat(IntToTypeKind(IRTk[IRB[node]])) then
        begin
          EmitI32($EEBD0BC0);                       { vcvt.s32.f64 s0, d0 (trunc) }
          EmitI32($EE100A10);                       { vmov r0, s0 }
        end;
        EmitStoreVarArm32(IRA[node]);
      end;

    IR_LEA:
      begin
        si := IRA[node];
        if Syms[si].IsArray and (Syms[si].ArrLen = -1) then
        begin
          { Dynamic array: slot holds the heap data pointer. Read position loads
            it (Length/indexing want the data ptr); WRITE position wants the
            SLOT's own address instead, so a SetLength target (or the outer
            level of a nested SetLength(a[i], n), which addresses the root
            symbol's own slot via a plain IR_LEA) can publish a new handle into
            it -- mirrors the x86-64 IR_LEA read/write gate immediately below
            for scalar AnsiString. Previously this always loaded the handle
            regardless of InLValueWrite, so SetLength on the array itself wrote
            through the CURRENT (often nil) handle value instead of the slot,
            silently no-opping (or, one level down inside a nested array,
            computing a bogus small-integer "address" from a nil base plus an
            index stride and segfaulting on any index > 0) --
            bug-nested-dynarray-cross-segfault. v1: no COW either way. }
          if Syms[si].Kind = skGlobal then
          begin
            EmitI32($E59F0000); EmitI32($EA000000); EmitGlobRef(Syms[si].Offset); { r0 = slot addr }
            if not InLValueWrite then
              EmitI32($E5900000);  { ldr r0, [r0] = handle }
          end
          else
          begin
            EmitLoadImmArm32(0, Syms[si].Offset);
            EmitI32($E08B0000);  { add r0, fp, r0 = local slot addr }
            if (Syms[si].Kind = skParam) and Syms[si].IsRef then
            begin
              { by-ref (var/out) named-dynarray param: the local slot holds
                &caller_slot; load it (needed either way -- SetLength wants to
                publish through it, Length/indexing want to deref it once
                more). }
              EmitI32($E5900000);  { ldr r0, [r0] = &caller_slot }
              if not InLValueWrite then
                EmitI32($E5900000);  { ldr r0, [r0] = data ptr }
            end
            else if not InLValueWrite then
              EmitI32($E5900000);  { ldr r0, [r0] = handle }
            { else: r0 already holds &local_slot -- exactly what a write wants. }
          end;
        end
        else if (Syms[si].TypeKind = tyAnsiString) and not Syms[si].IsArray and
                not InLValueWrite then
        begin
          { Scalar managed string in read position: the slot holds the heap data
            pointer (handle); load it so Length / index / concat operate on the
            data, not the slot. Write position keeps the slot address (else
            branch) so a store can publish a new handle. Mirrors the x86-64
            IR_LEA read/write gate. }
          if Syms[si].Kind = skGlobal then
          begin
            EmitI32($E59F0000); EmitI32($EA000000); EmitGlobRef(Syms[si].Offset);
            EmitI32($E5900000);  { ldr r0, [r0] = handle }
          end
          else
          begin
            EmitLoadImmArm32(0, Syms[si].Offset);
            EmitI32($E08B0000);  { add r0, fp, r0 = slot addr }
            EmitI32($E5900000);  { ldr r0, [r0] = handle }
          end;
        end
        else
          EmitLoadVarAddrArm32(si);
      end;

    IR_SLOTADDR:
      begin
        si := IRA[node];
        if Syms[si].Kind = skGlobal then
        begin
          EmitI32($E59F0000);  { ldr r0, [pc] }
          EmitI32($EA000000);  { b .+8 }
          EmitGlobRef(Syms[si].Offset);
        end
        else
        begin
          EmitLoadImmArm32(0, Syms[si].Offset);
          EmitI32($E08B0000);  { add r0, fp, r0 }
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
          portable builtin helpers (x86-64 keeps its asm path). A managed
          string wants its SLOT address — force lvalue-write mode. }
        tk := IntToTypeKind(IRTk[node]);
        if tk = tyAnsiString then
        begin
          savedLValueWrite := InLValueWrite;
          InLValueWrite := True;
          IREmitNodeArm32(IRA[node]);  { r0 = slot address }
          InLValueWrite := savedLValueWrite;
          procIdx := FindProc('PXXReadVarStrM');
          if procIdx < 0 then Error('compiler error: PXXReadVarStrM not found');
          EmitCallProc(procIdx);
        end
        else if tk = tyChar then
        begin
          IREmitNodeArm32(IRA[node]);  { r0 = target address }
          procIdx := FindProc('PXXReadVarChar');
          if procIdx < 0 then Error('compiler error: PXXReadVarChar not found');
          EmitCallProc(procIdx);
        end
        else if TypeIsOrdinal(tk) then
        begin
          IREmitNodeArm32(IRA[node]);  { r0 = target address }
          EmitLoadImmArm32(1, TypeSize(tk));   { r1 = size }
          procIdx := FindProc('PXXReadVarInt');
          if procIdx < 0 then Error('compiler error: PXXReadVarInt not found');
          EmitCallProc(procIdx);
        end
        else
          Error('target arm32: read/readln target type not supported');
      end;

    IR_SETLEN_STR:
      begin
        { SetLength(ansistring-lvalue, n) -> PXXStrSetLen(slotAddr, n). IRA =
          slot-address node, IRB = new length. Address-based, so a record/var-
          param field needs no symbol reconstruction. }
        IREmitNodeArm32(IRA[node]);    { r0 = slot address }
        EmitI32($E92D0001);            { push {r0} slotAddr }
        IREmitNodeArm32(IRB[node]);    { r0 = n }
        EmitI32($E92D0001);            { push {r0} n }
        EmitI32($E8BD0002);            { pop {r1} (n) }
        EmitI32($E8BD0001);            { pop {r0} (slotAddr) }
        procIdx := FindProc('PXXStrSetLen');
        if procIdx < 0 then Error('compiler error: PXXStrSetLen not found');
        EmitCallProc(procIdx);
      end;

    IR_SETLEN_DYN:
      begin
        { Nested / record-or-class-field SetLength via the portable
          PXXDynSetLen(slotAddr, n, desc). IRA = slot-address node, IRB = length;
          descriptor allocated from the node metadata. }
        savedLValueWrite := InLValueWrite;
        InLValueWrite := True;
        IREmitNodeArm32(IRA[node]);    { r0 = slot addr }
        InLValueWrite := savedLValueWrite;
        EmitI32($E92D0001);            { push {r0} slotAddr }
        IREmitNodeArm32(IRB[node]);    { r0 = n }
        EmitI32($E92D0001);            { push {r0} n }
        EmitI32($E8BD0002);            { pop {r1} (n) }
        EmitI32($E8BD0001);            { pop {r0} (slotAddr) }
        EmitLoadDataRefArm32(2, GetOrAllocNodeDynDesc(node)); { r2 = desc }
        procIdx := FindProc('PXXDynSetLen');
        if procIdx < 0 then Error('compiler error: PXXDynSetLen not found');
        EmitCallProc(procIdx);
      end;

    IR_DYNUNIQUE:
      begin
        { Nested dyn-array copy-on-write. IRA = slot-address node. Read: load the
          level's data pointer; write: clone-if-shared via
          PXXDynArrayUnique(slotAddr, desc), returning the data pointer in r0. }
        IREmitNodeArm32(IRA[node]);    { r0 = slot addr }
        if InLValueWrite then
        begin
          EmitLoadDataRefArm32(1, GetOrAllocDynUniqueDesc(node)); { r1 = desc }
          procIdx := FindProc('PXXDynArrayUnique');
          if procIdx < 0 then Error('compiler error: PXXDynArrayUnique not found');
          EmitCallProc(procIdx);            { r0 = unique data ptr }
        end
        else
          EmitI32($E5900000);          { ldr r0, [r0] }
      end;

    IR_BINOP:
      begin
        left := IRA[node];
        right := IRB[node];
        op := IRC[node];
        tk := IntToTypeKind(IRTk[node]);

        if (tk = tyAnsiString) and (op = Ord(tkPlus)) then
        begin
          lhsTk := IntToTypeKind(IRTk[left]);
          rhsTk := IntToTypeKind(IRTk[right]);
          IREmitNodeArm32(left);  EmitI32($E92D0001); { push lhs }
          IREmitNodeArm32(right); EmitI32($E92D0001); { push rhs }

          EmitI32($E59D0000);                         { r0 = rhs value }
          EmitArm32StringParts(0, 1, 2, rhsTk, 0);    { r1=srcB, r2=lenB }
          EmitI32($E92D0006);                         { push {r1,r2} }
          EmitI32($E59D000C);                         { r0 = lhs value }
          EmitArm32StringParts(0, 1, 2, lhsTk, 12);   { r1=srcA, r2=lenA }
          EmitI32($E1A00002);                         { mov r0, r2 (lenA) }
          EmitI32($E59D2000);                         { r2 = srcB }
          EmitI32($E59D3004);                         { r3 = lenB }
          EmitI32($E28DD008);                         { add sp, sp, #8 }
          procIdx := FindProc('PXXStrConcat');
          if procIdx < 0 then Error('compiler error: PXXStrConcat not found');
          EmitCallProc(procIdx);                           { r0 = result }

          EmitI32($E92D0001);                         { push result }
          if (IRKind[left] = IR_BINOP) and (IntToTypeKind(IRTk[left]) = tyAnsiString) then
          begin
            EmitI32($E59D0008);                       { lhs }
            EmitStrDecRefArm32;
          end;
          if (IRKind[right] = IR_BINOP) and (IntToTypeKind(IRTk[right]) = tyAnsiString) then
          begin
            EmitI32($E59D0004);                       { rhs }
            EmitStrDecRefArm32;
          end;
          EmitI32($E8BD0001);                         { pop result }
          EmitI32($E28DD008);                         { drop rhs,lhs }
          Exit;
        end;

        if (tk = tyString) and (op = Ord(tkPlus)) then
        begin
          lhsTk := IntToTypeKind(IRTk[left]);
          rhsTk := IntToTypeKind(IRTk[right]);
          IREmitNodeArm32(left);  EmitI32($E92D0001); { push lhs }
          IREmitNodeArm32(right); EmitI32($E92D0001); { push rhs }

          EmitLoadImmArm32(9, 272);
          EmitI32($E04DD009);                         { sub sp, sp, r9 }
          EmitI32($E1A0300D);                         { mov r3, sp (buffer) }

          EmitI32($E59D0114);                         { r0 = lhs value [sp+276] }
          EmitArm32StringParts(0, 5, 4, lhsTk, 276);  { r5=src, r4=len }
          EmitI32($E1A07004);                         { mov r7, r4 (left len) }
          EmitI32($E2836008);                         { add r6, r3, #8 (dst) }
          EmitArm32CopyBytes(4, 5, 6);

          EmitI32($E59D0110);                         { r0 = rhs value [sp+272] }
          EmitArm32StringParts(0, 5, 4, rhsTk, 272);  { r5=src, r4=len }
          EmitI32($E1A09004);                         { mov r9, r4 (right len) }
          EmitI32($E2836008);                         { add r6, r3, #8 }
          EmitI32($E0866007);                         { add r6, r6, r7 }
          EmitArm32CopyBytes(4, 5, 6);

          EmitI32($E0877009);                         { add r7, r7, r9 (total len) }
          EmitI32($E3570C01);                         { cmp r7, #256 }
          j := CodeLen;
          EmitI32($DA000000);                         { ble cap_done }
          EmitLoadImmArm32(7, 256);
          Patch32(j, $DA000000 or ((((CodeLen - j) div 4) - 2) and $00ffffff));
          EmitI32($E5837000);                         { str r7, [r3] }
          EmitI32($E3A00000);                         { mov r0, #0 }
          EmitI32($E5830004);                         { str r0, [r3,#4] }
          EmitI32($E1A00003);                         { mov r0, r3 }
          Exit;
        end;

        if ((op = Ord(tkEq)) or (op = Ord(tkNeq))) and
           ((IntToTypeKind(IRTk[left]) in [tyAnsiString, tyString]) or
            (IntToTypeKind(IRTk[right]) in [tyAnsiString, tyString])) and
           ((IntToTypeKind(IRTk[left]) in [tyAnsiString, tyString, tyChar, tyPointer]) and
            (IntToTypeKind(IRTk[right]) in [tyAnsiString, tyString, tyChar, tyPointer])) then
        begin
          lhsTk := IntToTypeKind(IRTk[left]);
          rhsTk := IntToTypeKind(IRTk[right]);
          { A frozen-string operand reached through a pointer deref or a pointer
            field (`pstr^`, `rec.pstrField^`) is tagged tyPointer, but its value is
            the buffer address — decode it as a frozen string. The condition above
            still requires the other side to be a genuine string, so a real
            pointer/integer compare never lands here. Mirrors i386/x86-64, which
            tolerate the tyPointer tag in their string-equality path. }
          if lhsTk = tyPointer then lhsTk := tyString;
          if rhsTk = tyPointer then rhsTk := tyString;
          IREmitNodeArm32(left);  EmitI32($E92D0001); { push lhs }
          IREmitNodeArm32(right); EmitI32($E92D0001); { push rhs }

          EmitI32($E59D0000);                         { r0 = rhs value }
          EmitArm32StringParts(0, 1, 2, rhsTk, 0);    { r1=srcB, r2=lenB }
          EmitI32($E92D0006);                         { push {r1,r2} }
          EmitI32($E59D000C);                         { r0 = lhs value }
          EmitArm32StringParts(0, 1, 2, lhsTk, 12);   { r1=srcA, r2=lenA }
          EmitI32($E1A00002);                         { mov r0, r2 (lenA) }
          EmitI32($E59D3000);                         { r3 = srcB }
          EmitI32($E59D2004);                         { r2 = lenB }
          EmitI32($E28DD008);                         { add sp, sp, #8 }
          procIdx := FindProc('PXXStrEq');
          if procIdx < 0 then Error('compiler error: PXXStrEq not found');
          EmitCallProc(procIdx);
          if op = Ord(tkNeq) then
            EmitI32($E2200001);                       { eor r0, r0, #1 }

          EmitI32($E92D0001);                         { push result }
          if (IRKind[left] = IR_BINOP) and (IntToTypeKind(IRTk[left]) = tyAnsiString) then
          begin
            EmitI32($E59D0008);                       { lhs }
            EmitStrDecRefArm32;
          end;
          if (IRKind[right] = IR_BINOP) and (IntToTypeKind(IRTk[right]) = tyAnsiString) then
          begin
            EmitI32($E59D0004);                       { rhs }
            EmitStrDecRefArm32;
          end;
          EmitI32($E8BD0001);                         { pop result }
          EmitI32($E28DD008);                         { drop rhs,lhs }
          Exit;
        end;

        lhsTk := IntToTypeKind(IRTk[left]);
        rhsTk := IntToTypeKind(IRTk[right]);
        if TypeIsFloat(lhsTk) or TypeIsFloat(rhsTk) or (op = Ord(tkSlash)) then
        begin
          IREmitNodeArm32(left);
          if not TypeIsFloat(lhsTk) then EmitIntToD0Arm32;
          EmitI32($ED2D0B02);                    { vpush {d0} }
          IREmitNodeArm32(right);
          if not TypeIsFloat(rhsTk) then EmitIntToD0Arm32;
          EmitI32($EEB01B40);                    { vmov.f64 d1, d0 }
          EmitI32($ECBD0B02);                    { vpop {d0} (left) }

          if op = Ord(tkPlus) then EmitI32($EE300B01)        { vadd.f64 d0, d0, d1 }
          else if op = Ord(tkMinus) then EmitI32($EE300B41)  { vsub.f64 d0, d0, d1 }
          else if op = Ord(tkStar) then EmitI32($EE200B01)   { vmul.f64 d0, d0, d1 }
          else if op = Ord(tkSlash) then EmitI32($EE800B01)  { vdiv.f64 d0, d0, d1 }
          else if (op = Ord(tkEq)) or (op = Ord(tkNeq)) or (op = Ord(tkLt)) or
                  (op = Ord(tkLe)) or (op = Ord(tkGt)) or (op = Ord(tkGe)) then
          begin
            EmitI32($EEB40B41);                  { vcmp.f64 d0, d1 }
            EmitI32($EEF1FA10);                  { vmrs APSR_nzcv, fpscr }
            EmitSetccArm32Float(op);             { NaN-correct: mi/ls for </<= }
          end
          else
            Error('target arm32: unsupported float binop');
          Exit;
        end;

        { 64-bit (Int64/UInt64) ops use the dedicated r0:r1 path. A comparison
          carries a Boolean result tk, so key off the operands too. }
        if Is64BitArm32(tk) or Is64BitArm32(lhsTk) or Is64BitArm32(rhsTk) then
        begin
          EmitBinop64Arm32(left, right, op,
            not ((lhsTk = tyUInt64) or (rhsTk = tyUInt64)));
          Exit;
        end;

        if not (TypeIsOrdinal(tk) or (tk = tyBoolean) or (tk = tyUnknown)) then
          Error('target arm32: non-integer binop not yet supported');
        IREmitNodeArm32(left);
        EmitI32($E92D0001); { push {r0} }
        IREmitNodeArm32(right);
        EmitI32($E1A01000); { mov r1, r0 }
        EmitI32($E8BD0001); { pop {r0} }

        if op = Ord(tkPlus) then EmitI32($E0800001)        { add r0, r0, r1 }
        else if op = Ord(tkMinus) then EmitI32($E0400001)  { sub r0, r0, r1 }
        else if op = Ord(tkStar) then EmitI32($E0000091)   { mul r0, r1, r0 }
        else if op = Ord(tkDiv) then
        begin
          { unsigned dividend (Cardinal/LongWord, C unsigned int) -> udiv (bit21) }
          if TypeDivideUnsigned(lhsTk) then EmitI32($E730F110)   { udiv r0, r0, r1 }
          else EmitI32($E710F110);                               { sdiv r0, r0, r1 }
        end
        else if op = Ord(tkMod) then
        begin
          if TypeDivideUnsigned(lhsTk) then EmitI32($E732F110)   { udiv r2, r0, r1 }
          else EmitI32($E712F110);                               { sdiv r2, r0, r1 }
          EmitI32($E0020192);  { mul r2, r2, r1 }
          EmitI32($E0400002);  { sub r0, r0, r2 }
        end
        else if op = Ord(tkAnd) then EmitI32($E0000001)    { and r0, r0, r1 }
        else if op = Ord(tkOr) then EmitI32($E1800001)     { orr r0, r0, r1 }
        else if op = Ord(tkXor) then EmitI32($E0200001)    { eor r0, r0, r1 }
        else if op = Ord(tkShl) then EmitI32($E1A00110)    { lsl r0, r0, r1 }
        else if op = Ord(tkIdent) then EmitI32($E1A00130)  { lsr r0, r0, r1 }
        else if op = Ord(tkShr) then EmitI32($E1A00150)    { C signed >> (bug-c-signed-arith-shift-right); asr r0, r0, r1 }
        else if (op = Ord(tkEq)) or (op = Ord(tkNeq)) or (op = Ord(tkLt)) or
                (op = Ord(tkLe)) or (op = Ord(tkGt)) or (op = Ord(tkGe)) then
        begin
          EmitI32($E1500001); { cmp r0, r1 }
          EmitSetccArm32(op, not TypeCompareUnsigned(lhsTk, rhsTk));
        end
        else if op = Ord(tkIn) then
        begin
          { Set membership: r0 = element, r1 = set address. Result (0/1) -> r0. }
          EmitI32($E35000FF);                   { cmp r0, #255 }
          p1 := CodeLen; EmitI32($8A000000);    { bhi out-of-range (patched) }
          EmitI32($E1A021A0);                   { lsr r2, r0, #3 (byte index) }
          EmitI32($E7D12002);                   { ldrb r2, [r1, r2] (set byte) }
          EmitI32($E2003007);                   { and r3, r0, #7 (bit index) }
          EmitI32($E3A00001);                   { mov r0, #1 }
          EmitI32($E1A00310);                   { lsl r0, r0, r3 }
          EmitI32($E1120000);                   { tst r2, r0 }
          EmitI32($13A00001);                   { movne r0, #1 }
          EmitI32($03A00000);                   { moveq r0, #0 }
          p2 := CodeLen; EmitI32($EA000000);    { b done (patched) }
          Patch32(p1, $8A000000 or (((CodeLen - p1 - 8) div 4) and $00FFFFFF));
          EmitI32($E3A00000);                   { mov r0, #0 }
          Patch32(p2, $EA000000 or (((CodeLen - p2 - 8) div 4) and $00FFFFFF));
        end
        else
          Error('target arm32: binop operator not yet supported');
      end;

    IR_CALL:
      begin
        procIdx := IRA[node];
        if procIdx = -Ord(tkGetMem) then
        begin
          { GetMem / New / class instantiation. For a class: alloc, store the
            VMT pointer at offset 0, run the ctor, return Self in r0. AAPCS:
            word-push each arg (Self deepest), load r0..r3, drop the block. }
          classIdx := IRC[node];
          argNode := IRB[node];          { size arg }
          IREmitNodeArm32(IRA[argNode]); { size -> r0 }
          EmitHeapAllocLockedArm32;      { r0 = payload pointer }
          if classIdx < REC_UCLASS_BASE then
            Exit;                        { plain GetMem: pointer in r0 }
          EmitLoadDataRefArm32(9, UClsVMTOffset[classIdx - REC_UCLASS_BASE]); { r9 = VMT addr }
          EmitI32($E5809000);            { str r9, [r0] (VMT pointer) }
          p1 := IRResolveCtorProc(node, classIdx);   { overload-resolved ctor }
          if p1 < 0 then
            Exit;                        { no ctor: instance pointer in r0 }
          EmitI32($E92D0001);            { push {r0} (Self = word 0, deepest) }
          nArgs := 1;                    { total arg words }
          argNode := IRB[node];          { size arg }
          argNode := IRB[argNode];       { first explicit ctor arg }
          while argNode <> -1 do
          begin
            IREmitNodeArm32(IRA[argNode]);
            EmitI32($E92D0001);          { push {r0} }
            Inc(nArgs);
            argNode := IRB[argNode];
          end;
          if nArgs > 4 then
            Error('target arm32: constructor with more than 4 parameter words not supported');
          for i := 0 to nArgs - 1 do
            EmitI32($E59D0000 or (i shl 12) or ((nArgs - 1 - i) * 4)); { ldr r[i], [sp, #off] }
          EmitLoadImmArm32(9, nArgs * 4);
          EmitI32($E08DD009);            { add sp, sp, r9 (drop pushed words) }
          EmitI32($E92D0001);            { push {r0} (save Self) }
          EmitCallProc(p1);
          EmitI32($E8BD0001);            { pop {r0} (Self = constructor result) }
          Exit;
        end;
        if procIdx = -Ord(tkFreeMem) then
        begin
          argNode := IRB[node];          { pointer arg }
          IREmitNodeArm32(IRA[argNode]); { p -> r0 }
          EmitHeapFreeLockedArm32;
          Exit;
        end;
        if procIdx = -102 then
        begin
          { SetLength(arr, n) -> PXXDynSetLen(slotAddr, n, desc); SetLength on a
            managed AnsiString -> PXXStrSetLen(slotAddr, n). }
          argNode := IRB[node];          { arg1 = array/string lvalue }
          valNode := IRB[argNode];       { arg2 = new length }
          left := IRA[argNode];          { IR_LEA or IR_LOAD_SYM node }
          if (IRKind[left] = IR_LOAD_SYM) and
             (Syms[IRA[left]].TypeKind = tyAnsiString) then
          begin
            { Managed-string SetLength via the portable runtime helper. Load the
              handle slot's address into r0 (a by-ref param slot holds the
              caller's slot address — deref once). }
            si := IRA[left];
            if (Syms[si].Kind = skParam) and Syms[si].IsRef then
            begin
              EmitLoadImmArm32(0, Syms[si].Offset);
              EmitI32($E08B0000);        { add r0, fp, r0 (param slot addr) }
              EmitI32($E5900000);        { ldr r0, [r0] (caller slot addr) }
            end
            else if Syms[si].Kind = skGlobal then
            begin
              EmitI32($E59F0000); EmitI32($EA000000); EmitGlobRef(Syms[si].Offset);
            end
            else
            begin
              EmitLoadImmArm32(0, Syms[si].Offset);
              EmitI32($E08B0000);        { add r0, fp, r0 }
            end;
            EmitI32($E92D0001);          { push {r0} slotAddr }
            IREmitNodeArm32(IRA[valNode]); { r0 = n }
            EmitI32($E92D0001);          { push {r0} n }
            EmitI32($E8BD0002);          { pop {r1} (n) }
            EmitI32($E8BD0001);          { pop {r0} (slotAddr) }
            procIdx := FindProc('PXXStrSetLen');
            if procIdx < 0 then Error('compiler error: PXXStrSetLen not found');
            EmitCallProc(procIdx);
            Exit;
          end;
          if IRKind[left] <> IR_LEA then
            Error('target arm32: SetLength expects an array variable');
          si := IRA[left];
          if not (Syms[si].IsArray and (Syms[si].ArrLen = -1)) then
            Error('target arm32: SetLength only supports dynamic arrays yet');
          { slot address -> r0, push. For a by-ref (var/out) param the slot holds
            &caller_slot, so deref to it; PXXDynSetLen resizes and publishes the
            new handle into caller_slot. }
          if Syms[si].Kind = skGlobal then
          begin
            EmitI32($E59F0000); EmitI32($EA000000); EmitGlobRef(Syms[si].Offset);
          end
          else
          begin
            EmitLoadImmArm32(0, Syms[si].Offset);
            EmitI32($E08B0000);          { add r0, fp, r0 }
          end;
          if (Syms[si].Kind = skParam) and Syms[si].IsRef then
            EmitI32($E5900000);          { ldr r0, [r0] = &caller_slot }
          EmitI32($E92D0001);            { push {r0} slotAddr }
          IREmitNodeArm32(IRA[valNode]); { r0 = n }
          EmitI32($E92D0001);            { push {r0} n }
          EmitI32($E8BD0002);            { pop {r1} (n) }
          EmitI32($E8BD0001);            { pop {r0} (slotAddr) }
          EmitLoadDataRefArm32(2, GetOrAllocSymRTTI(si)); { r2 = desc }
          procIdx := FindProc('PXXDynSetLen');
          if procIdx < 0 then Error('compiler error: PXXDynSetLen not found');
          EmitCallProc(procIdx);
          Exit;
        end;
        if procIdx = -101 then
        begin
          { SetLength(s, n) on a frozen inline string: store n into the 8-byte
            length prefix at [buffer+0] (hi dword = 0, length < 4GB). The buffer
            address comes straight from EmitLoadVarAddrArm32 (which already loads
            the pointer P for a string param). Mirrors x86-64 EmitStoreStrLen. }
          argNode := IRB[node];
          valNode := IRB[argNode];
          left := IRA[argNode];
          if IRKind[left] <> IR_LEA then
            Error('target arm32: SetLength expects a string variable');
          si := IRA[left];
          EmitLoadVarAddrArm32(si);    { r0 = buffer addr }
          EmitI32($E92D0001);          { push {r0} buffer addr }
          IREmitNodeArm32(IRA[valNode]); { r0 = new length }
          EmitI32($E8BD0002);          { pop {r1} buffer addr }
          EmitI32($E5810000);          { str r0, [r1] (len lo) }
          EmitI32($E3A02000);          { mov r2, #0 }
          EmitI32($E5812004);          { str r2, [r1, #4] (len hi) }
          Exit;
        end;
        if procIdx = -Ord(tkLength) then
        begin
          { Length(arr): IR_LEA auto-loaded the data pointer; count at [handle-8]. }
          argNode := IRB[node];
          valNode := IRA[argNode];
          if (IntToTypeKind(IRTk[valNode]) = tyString) or
             ((IRKind[valNode] = IR_LEA) and
              TypeIsFrozenString(Syms[IRA[valNode]].TypeKind) and
              not Syms[IRA[valNode]].IsArray) or
             (((IRKind[valNode] = IR_LOAD_SYM) or (IRKind[valNode] = IR_LOAD_MEM)) and
              (IntToTypeKind(IRTk[valNode]) = tyPointer)) then
          begin
            { Frozen inline string: length is the 8-byte prefix at [buffer+0]. A
              frozen string reached through a pointer deref (`ps^`, `rec.pf^`)
              lowers to a bare pointer load whose value IS the buffer address;
              read the prefix there, mirroring x86-64's else catch-all. }
            IREmitNodeArm32(valNode);    { r0 = frozen buffer addr }
            EmitI32($E5900000);          { ldr r0, [r0] }
            Exit;
          end;
          IREmitNodeArm32(valNode);      { r0 = handle (or 0) }
          if (IRKind[valNode] = IR_INDEX) or (IRKind[valNode] = IR_FIELD) or
             ((IRKind[valNode] = IR_LEA) and (Syms[IRA[valNode]].Kind = skParam) and
              Syms[IRA[valNode]].IsRef and (Syms[IRA[valNode]].TypeKind = tyAnsiString) and
              not Syms[IRA[valNode]].IsArray) then
            EmitI32($E5900000);          { ldr r0, [r0] (deref slot/&handle to handle) }
          EmitI32($E3500000);            { cmp r0, #0 }
          EmitI32($0A000000);            { beq +1 (skip ldr) }
          EmitI32($E5100008);            { ldr r0, [r0, #-8] }
          Exit;
        end;
        if procIdx = -100 then
        begin
          { LoadFile(path, dst): read the whole file named by `path` into the
            managed-string `dst` via the portable PXXStrLoadFile helper, then
            publish the new handle (releasing dst's old one). Managed dst only —
            compiler.pas reads into AnsiString. }
          argNode := IRB[node];
          left := IRA[argNode];          { val1 = path node }
          valNode := IRB[argNode];       { arg2 }
          right := IRA[valNode];         { val2 = dst node }
          if not ((IRKind[right] = IR_LOAD_SYM) and
                  (Syms[IRA[right]].TypeKind = tyAnsiString)) then
            Error('target arm32: LoadFile expects a managed-string destination');
          si := IRA[right];              { dst sym }
          IREmitNodeArm32(left);         { r0 = path handle = nul-terminated C string }
          procIdx := FindProc('PXXStrLoadFile');
          if procIdx < 0 then Error('compiler error: PXXStrLoadFile not found');
          EmitCallProc(procIdx);              { r0 = new managed handle (refcount 1) }
          EmitI32($E92D0001);            { push {r0} new }
          EmitLoadVarArm32(si);          { r0 = dst old handle }
          EmitStrDecRefArm32;
          EmitI32($E8BD0001);            { pop {r0} new }
          EmitStoreVarArm32(si);
          Exit;
        end;
        if procIdx < 0 then
        begin
          j := -procIdx;
          if (j = Ord(tkOrd)) or (j = Ord(tkChr)) or
             (j = Ord(tkInteger_T)) or (j = Ord(tkLongWord_T)) or
             (j = Ord(tkChar_T)) or (j = Ord(tkBoolean_T)) or
             (j = Ord(tkString_T)) then
          begin
            { type-pun passthrough: evaluate the argument in place }
            argNode := IRB[node];
            IREmitNodeArm32(IRA[argNode]);
            Exit;
          end;
          if j = 200 then
          begin
            { int(x): float/Variant -> integer }
            argNode := IRB[node];
            valNode := IRA[argNode];
            if IntToTypeKind(IRTk[valNode]) = tyVariant then
            begin
              EmitLoadVariantAddrArm32(valNode);    { r0 = slot addr }
              EmitI32($E5901000);                   { ldr r1, [r0] (tag low) }
              EmitI32($E3510003);                   { cmp r1, #3 (VT_DOUBLE) }
              i := CodeLen;
              EmitI32($1A000000);                   { bne .not_double }
              EmitI32($ED900B02);                   { vldr d0, [r0, #8] }
              EmitI32($EEBD0BC0);                   { vcvt.s32.f64 s0, d0 }
              EmitI32($EE100A10);                   { vmov r0, s0 }
              lo := CodeLen;
              EmitI32($EA000000);                   { b .done }
              Patch32(i, $1A000000 or ((((CodeLen - i) div 4) - 2) and $00ffffff));
              EmitI32($E5900008);                   { ldr r0, [r0, #8] (payload low) }
              Patch32(lo, $EA000000 or ((((CodeLen - lo) div 4) - 2) and $00ffffff));
              Exit;
            end;
            IREmitNodeArm32(valNode);
            if TypeIsFloat(IntToTypeKind(IRTk[valNode])) then
            begin
              EmitI32($EEBD0BC0);                   { vcvt.s32.f64 s0, d0 (trunc) }
              EmitI32($EE100A10);                   { vmov r0, s0 }
            end;
            Exit;
          end
          else if (j = 203) or (j = 204) or (j = 205) or (j = 206) then
          begin
            { Float intrinsics: 203 Trunc, 204 Round, 205 Frac, 206 Int }
            argNode := IRB[node];
            valNode := IRA[argNode];
            IREmitNodeArm32(valNode);
            if TypeIsFloat(IntToTypeKind(IRTk[valNode])) then
            begin
              if j = 204 then procIdx := FindProc('__pxx_d2i64_rne')
              else procIdx := FindProc('__pxx_d2i64');
              if ((j = 203) or (j = 204)) and Is64BitArm32(IntToTypeKind(IRTk[node])) and
                 (procIdx >= 0) then
              begin
                { 64-bit result: VFP vcvt.s32.f64 is 32-bit only and saturates at
                  2^31, so an Int64 cast of a large double (e.g. sqlite's %f
                  double->u64) came out wrong. Route through the soft-float 64-bit
                  kernel. arm32 carries the value as double in d0. (Falls back to
                  the 32-bit VFP path below when softfloat is absent — e.g. a
                  minimal program with no builtin/heap that never pulled it.) }
                EmitI32($EC510B10);                 { vmov r0, r1, d0 (double bits -> Int64 arg) }
                EmitCallProc(procIdx);              { r0:r1 = Int64 result }
                Exit;
              end;
              if j = 203 then
              begin
                EmitI32($EEBD0BC0);                 { vcvt.s32.f64 s0, d0 (round-zero) }
                EmitI32($EE100A10);                 { vmov r0, s0 }
                if Is64BitArm32(IntToTypeKind(IRTk[node])) then
                  EmitI32($E1A01FC0);               { mov r1, r0, asr #31 (widen to Int64) }
              end
              else if j = 204 then
              begin
                EmitI32($EEBD0B40);                 { vcvtr.s32.f64 s0, d0 (FPSCR RN = half-even) }
                EmitI32($EE100A10);                 { vmov r0, s0 }
                if Is64BitArm32(IntToTypeKind(IRTk[node])) then
                  EmitI32($E1A01FC0);               { mov r1, r0, asr #31 (widen to Int64) }
              end
              else if j = 205 then
              begin
                { Frac = x - trunc(x). Scratch s8 (in d4): s0 aliases the
                  low half of d0, converting into it would corrupt x. }
                EmitI32($EEBD4BC0);                 { vcvt.s32.f64 s8, d0 }
                EmitI32($EEB81BC4);                 { vcvt.f64.s32 d1, s8 }
                EmitI32($EE300B41);                 { vsub.f64 d0, d0, d1 }
              end
              else
              begin
                { Int = trunc as float }
                EmitI32($EEBD0BC0);                 { vcvt.s32.f64 s0, d0 }
                EmitI32($EEB80BC0);                 { vcvt.f64.s32 d0, s0 }
              end;
            end
            else
            begin
              { integer argument }
              if j = 205 then
              begin
                EmitLoadImmArm32(0, 0);
                EmitLoadImmArm32(1, 0);
                EmitI32($EC410B10);                 { vmov d0, r0, r1 = 0.0 }
              end
              else if j = 206 then
                EmitIntToD0Arm32;
              { 203/204: r0 already holds the value }
            end;
            Exit;
          end
          else if j = Ord(tkArgCount) then
          begin
            { ArgCount/ParamCount = argc - 1. Initial sp points at argc. }
            EmitI32($E59F0000);             { ldr r0, [pc] }
            EmitI32($EA000000);             { b .+8 }
            EmitGlobRef(BSS_INITIAL_RSP);
            EmitI32($E5900000);             { ldr r0, [r0] = initial sp }
            EmitI32($E5900000);             { ldr r0, [r0] = argc }
            EmitI32($E2400001);             { sub r0, r0, #1 }
            Exit;
          end
          else if j = Ord(tkArgStr) then
          begin
            { ArgStr(index, strVar): fixed-string statement form. ParamStr
              expression assignments are handled by IR_STORE_SYM. }
            argNode := IRB[node];
            if argNode = -1 then
              Error('target arm32: ArgStr expects an index');
            IREmitNodeArm32(IRA[argNode]);  { r0 = argv index }
            argNode := IRB[argNode];
            if argNode = -1 then
              Error('target arm32: ParamStr expression must be assigned directly');
            valNode := IRA[argNode];
            { Managed-string dest (scalar `string` is tyAnsiString by default):
              build a heap AnsiString from argv[index] and publish it (release
              dst's old handle), mirroring LoadFile. The fixed-buffer emitter
              below is for a frozen string dest only. }
            if (IRKind[valNode] = IR_LOAD_SYM) and
               (Syms[IRA[valNode]].TypeKind = tyAnsiString) then
            begin
              si := IRA[valNode];
              EmitArgvToAnsiStringArm32;     { r0 (index) -> r0 = new handle }
              EmitI32($E92D0001);            { push {r0} new }
              EmitLoadVarArm32(si);          { r0 = old handle }
              EmitStrDecRefArm32;
              EmitI32($E8BD0001);            { pop {r0} new }
              EmitStoreVarArm32(si);
              Exit;
            end;
            if IRKind[valNode] <> IR_LEA then
              Error('target arm32: ArgStr expects a string variable');
            EmitArgvToFixedStringArm32(IRA[valNode]);
            Exit;
          end
          else if j = SPECIAL_IN then
          begin
            { x in [items]: items are constant single values or [lo..hi] ranges
              (IR_BLOCK, lo in IRA, hi in IRB). Accumulate membership in r4 using
              conditional execution — no shared true-label jump table needed. }
            argNode := IRB[node];          { arg1 = the test value (IR_ARG) }
            IREmitNodeArm32(IRA[argNode]);  { r0 = test value }
            EmitI32($E1A01000);            { mov r1, r0 (test value) }
            EmitI32($E3A04000);            { mov r4, #0 (result accumulator) }
            argNode := IRB[argNode];       { first set item }
            while argNode <> -1 do
            begin
              itemNode := IRA[argNode];
              if IRKind[itemNode] = IR_BLOCK then
              begin
                lo := Integer(IRIVal[IRA[itemNode]]);
                hi := Integer(IRIVal[IRB[itemNode]]);
                EmitLoadImmArm32(2, lo);
                EmitI32($E1510002);        { cmp r1, r2 }
                p1 := CodeLen; EmitI32($BA000000);   { blt skip (below lo) }
                EmitLoadImmArm32(2, hi);
                EmitI32($E1510002);        { cmp r1, r2 }
                p2 := CodeLen; EmitI32($CA000000);   { bgt skip (above hi) }
                EmitI32($E3A04001);        { mov r4, #1 (in range) }
                Patch32(p1, $BA000000 or ((((CodeLen - p1) div 4) - 2) and $00ffffff));
                Patch32(p2, $CA000000 or ((((CodeLen - p2) div 4) - 2) and $00ffffff));
              end
              else
              begin
                lo := Integer(IRIVal[itemNode]);
                EmitLoadImmArm32(2, lo);
                EmitI32($E1510002);        { cmp r1, r2 }
                EmitI32($03A04001);        { moveq r4, #1 }
              end;
              argNode := IRB[argNode];
            end;
            EmitI32($E1A00004);            { mov r0, r4 (result) }
            Exit;
          end
          else if j = Ord(tkSysOpen) then
          begin
            { ARM EABI open(path, flags, mode): r7=5, r0=path, r1=flags,
              r2=mode. Managed AnsiString handles are nul-terminated paths. }
            argNode := IRB[node];
            valNode := IRA[argNode];
            if IntToTypeKind(IRTk[valNode]) <> tyAnsiString then
              Error('target arm32: SysOpen expects a managed AnsiString path');
            IREmitNodeArm32(valNode);       { r0 = path handle }
            EmitI32($E92D0001);             { push {r0} path }
            argNode := IRB[argNode];
            IREmitNodeArm32(IRA[argNode]);  { r0 = flags }
            EmitI32($E1A01000);             { mov r1, r0 }
            EmitI32($E8BD0001);             { pop {r0} path }
            EmitI32($E3A02000);             { mov r2, #0 }
            EmitI32($E3A07005);             { mov r7, #5 (__NR_open) }
            EmitI32($EF000000);             { svc #0 }
            Exit;
          end
          else if j = Ord(tkSysRead) then
          begin
            { read(fd, buf, count): r7=3, r0=fd, r1=buf, r2=count. }
            argNode := IRB[node];
            IREmitNodeArm32(IRA[argNode]);  { r0 = fd }
            EmitI32($E92D0001);             { push {r0} fd }
            argNode := IRB[argNode];
            IREmitNodeArm32(IRA[argNode]);  { r0 = buf address }
            EmitI32($E92D0001);             { push {r0} buf }
            argNode := IRB[argNode];
            IREmitNodeArm32(IRA[argNode]);  { r0 = count }
            EmitI32($E1A02000);             { mov r2, r0 }
            EmitI32($E8BD0002);             { pop {r1} buf }
            EmitI32($E8BD0001);             { pop {r0} fd }
            EmitI32($E3A07003);             { mov r7, #3 (__NR_read) }
            EmitI32($EF000000);             { svc #0 }
            Exit;
          end
          else if j = Ord(tkSyswrite) then
          begin
            { write(fd, buf, count): r7=4, r0=fd, r1=buf, r2=count. }
            argNode := IRB[node];
            IREmitNodeArm32(IRA[argNode]);  { r0 = fd }
            EmitI32($E92D0001);             { push {r0} fd }
            argNode := IRB[argNode];
            IREmitNodeArm32(IRA[argNode]);  { r0 = buf address }
            EmitI32($E92D0001);             { push {r0} buf }
            argNode := IRB[argNode];
            IREmitNodeArm32(IRA[argNode]);  { r0 = count }
            EmitI32($E1A02000);             { mov r2, r0 }
            EmitI32($E8BD0002);             { pop {r1} buf }
            EmitI32($E8BD0001);             { pop {r0} fd }
            EmitI32($E3A07004);             { mov r7, #4 (__NR_write) }
            EmitI32($EF000000);             { svc #0 }
            Exit;
          end
          else if j = Ord(tkSysClose) then
          begin
            { close(fd): r7=6, r0=fd. }
            argNode := IRB[node];
            IREmitNodeArm32(IRA[argNode]);  { r0 = fd }
            EmitI32($E3A07006);             { mov r7, #6 (__NR_close) }
            EmitI32($EF000000);             { svc #0 }
            Exit;
          end
          else if j = Ord(tkSysFchmod) then
          begin
            { fchmod(fd, mode): r7=94, r0=fd, r1=mode. }
            argNode := IRB[node];
            IREmitNodeArm32(IRA[argNode]);  { r0 = fd }
            EmitI32($E92D0001);             { push {r0} fd }
            argNode := IRB[argNode];
            IREmitNodeArm32(IRA[argNode]);  { r0 = mode }
            EmitI32($E1A01000);             { mov r1, r0 }
            EmitI32($E8BD0001);             { pop {r0} fd }
            EmitI32($E3A0705E);             { mov r7, #94 (__NR_fchmod) }
            EmitI32($EF000000);             { svc #0 }
            Exit;
          end
          else if j = 210 then
          begin
            { bare `Eof` (stdin) -> PXXStdinEof: Boolean (portable builtin,
              shares the peek byte with PXXReadLine). }
            procIdx := FindProc('PXXStdinEof');
            if procIdx < 0 then Error('compiler error: PXXStdinEof not found');
            EmitCallProc(procIdx);
            Exit;
          end
          else
            Error('target arm32: builtin/special call not yet supported');
        end;
        if ProcExternal[procIdx] then
        begin
          { External C call (armel / base AAPCS soft-float): the cross sysroot is
            armel (gnueabi, ld-linux.so.3), so FP and 64-bit values pass in the
            CORE registers r0..r3, not VFP. Build a contiguous argument block in a
            16-byte stack temp using AAPCS placement rules — 4 bytes for
            int/single/pointer, 8 bytes (8-byte aligned) for double/extended and
            Int64/UInt64 — then load words 0..3 into r0..r3. The value model keeps
            floats as doubles in d0, so a single arg is fcvt'd to s0 and a double
            stored from d0; results come back in r0 (int/single) or r0:r1
            (double/Int64) and are bridged back to the value model. Stack
            arguments (block > 16 bytes) are not supported yet — the validated
            C-import / libm surface fits in the four core registers. The call goes
            through the external's GOT slot via EmitExternalCallArm32. }
          { Pass 1: compute the AAPCS block size. }
          sz := 0;   { running block offset }
          for i := 0 to Procs[procIdx].ParamCount - 1 do
          begin
            tk := Procs[procIdx].Params[i].TypeKind;
            if (tk = tyDouble) or (tk = tyExtended) or (tk = tyInt64) or (tk = tyUInt64) then
            begin
              if (sz and 4) <> 0 then Inc(sz, 4);   { 8-byte align }
              Inc(sz, 8);
            end
            else
              Inc(sz, 4);
          end;
          if sz > 16 then
            Error('target arm32: external call argument block exceeds 4 core registers (stack args not supported yet)');
          EmitI32($E24DD010);                       { sub sp, sp, #16 }
          { Pass 2: evaluate each arg and store its word(s) at the block offset. }
          argNode := IRB[node];
          nArgs := 0;
          j := 0;   { running block offset }
          while argNode <> -1 do
          begin
            tk := Procs[procIdx].Params[nArgs].TypeKind;
            if (tk = tyDouble) or (tk = tyExtended) then
            begin
              if (j and 4) <> 0 then Inc(j, 4);
              IREmitNodeArm32(IRA[argNode]);        { d0 = double }
              EmitI32($ED8D0B00 or (j shr 2));      { vstr d0, [sp, #j] }
              Inc(j, 8);
            end
            else if (tk = tyInt64) or (tk = tyUInt64) then
            begin
              if (j and 4) <> 0 then Inc(j, 4);
              EmitNode64Arm32(IRA[argNode]);        { r0=lo, r1=hi }
              EmitI32($E58D0000 or j);              { str r0, [sp, #j] }
              EmitI32($E58D1000 or (j + 4));        { str r1, [sp, #j+4] }
              Inc(j, 8);
            end
            else if tk = tySingle then
            begin
              IREmitNodeArm32(IRA[argNode]);        { d0 = double }
              EmitI32($EEB70BC0);                   { vcvt.f32.f64 s0, d0 }
              EmitI32($ED8D0A00 or (j shr 2));      { vstr s0, [sp, #j] }
              Inc(j, 4);
            end
            else
            begin
              IREmitNodeArm32(IRA[argNode]);        { r0 = arg }
              EmitI32($E58D0000 or j);              { str r0, [sp, #j] }
              Inc(j, 4);
            end;
            Inc(nArgs);
            argNode := IRB[argNode];
          end;
          if nArgs <> Procs[procIdx].ParamCount then
            Error('target arm32: external call argument count mismatch');
          { Load r0..r3 from the block (one word each; padding words are harmless). }
          i := 0;
          while (i * 4) < sz do
          begin
            EmitI32($E59D0000 or (i shl 12) or (i * 4)); { ldr r[i], [sp, #i*4] }
            Inc(i);
          end;
          EmitI32($E28DD010);                       { add sp, sp, #16 }
          EmitExternalCallArm32(RegisterExternal(procIdx));
          if Procs[procIdx].RetType = tySingle then
          begin
            EmitI32($EE000A10);                     { vmov s0, r0 }
            EmitI32($EEB70AC0);                     { vcvt.f64.f32 d0, s0 }
          end
          else if TypeIsFloat(Procs[procIdx].RetType) then
            EmitI32($EC410B10);                     { vmov d0, r0, r1 (double result) }
          Exit;
        end;

        { Aggregate result: push the caller's hidden destination first (deepest
          word) so arg evaluation can't disturb it; it is loaded into r12 (ip,
          a scratch reg) just before the call. }
        if RetViaHiddenDest(Procs[procIdx].RetType) then
        begin
          IREmitNodeArm32(IRC[node]);   { r0 = hidden destination }
          EmitI32($E92D0001);           { push {r0} }
        end;

        { Word-based argument passing: each scalar arg is one machine word, an
          Int64/UInt64 by-value arg is two (lo then hi, lo at the lower word
          index). j counts total words. Words are pushed in index order so word
          k sits at [sp + (j-1-k)*4]; words 0..3 load into r0..r3, the rest stay
          on the stack for the callee. Mirrors the parser.inc spill loop. }
        argNode := IRB[node];
        nArgs := 0;
        j := 0;
        while argNode <> -1 do
        begin
          if (procIdx >= 0) and (nArgs < Procs[procIdx].ParamCount) and
             (Procs[procIdx].Params[nArgs].TypeKind = tyAnsiString) and
             ((IntToTypeKind(IRTk[argNode]) = tyChar) or
              TypeIsFrozenString(IntToTypeKind(IRTk[argNode]))) then
          begin
            EmitAnsiStringFromNodeArm32(IRA[argNode]);
            EmitI32($E92D0001); { push {r0} }
            Inc(j, 1);
          end
          else if (procIdx >= 0) and (nArgs < Procs[procIdx].ParamCount) and
                  ((Procs[procIdx].Params[nArgs].TypeKind = tyInt64) or
                   (Procs[procIdx].Params[nArgs].TypeKind = tyUInt64)) and
                  (not Procs[procIdx].Params[nArgs].IsRef) and
                  (not Procs[procIdx].Params[nArgs].IsArray) then
          begin
            { By-value Int64: pass the full 64 bits as two words (lo then hi).
              A by-ref/open-array Int64 param is just a pointer (falls through). }
            EmitNode64Arm32(IRA[argNode]);  { r0=lo, r1=hi }
            EmitI32($E92D0001); { push {r0} (lo = word j) }
            EmitI32($E92D0002); { push {r1} (hi = word j+1) }
            Inc(j, 2);
          end
          else if (procIdx >= 0) and (nArgs >= Procs[procIdx].ParamCount) and
                  (IntToTypeKind(IRTk[IRA[argNode]]) in [tyInt64, tyUInt64]) then
          begin
            { Variadic tail int64/uint64: two words lo:hi, matching the callee
              reg-save + __pxx_va_arg_cross32's 8-byte step (else the high word
              was dropped, shifting every later variadic arg). }
            EmitNode64Arm32(IRA[argNode]);  { r0=lo, r1=hi }
            EmitI32($E92D0001); EmitI32($E92D0002);
            Inc(j, 2);
          end
          else if (procIdx >= 0) and (nArgs >= Procs[procIdx].ParamCount) and
                  (IntToTypeKind(IRTk[IRA[argNode]]) = tyDouble) then
          begin
            { Variadic tail double: two words from d0. }
            IREmitNodeArm32(IRA[argNode]);  { d0 }
            EmitI32($EC510B10);             { vmov r0, r1, d0 }
            EmitI32($E92D0001); EmitI32($E92D0002);
            Inc(j, 2);
          end
          else if (procIdx >= 0) and (nArgs < Procs[procIdx].ParamCount) and
                  (nArgs < MAX_PROC_PARAMS) and
                  (Procs[procIdx].Params[nArgs].TypeKind = tyRecord) and
                  (not Procs[procIdx].Params[nArgs].IsRef) and
                  (not Procs[procIdx].Params[nArgs].IsArray) and
                  (RecSize(ProcParamRecId[procIdx * MAX_PROC_PARAMS + nArgs]) > 4) and
                  (RecSize(ProcParamRecId[procIdx * MAX_PROC_PARAMS + nArgs]) <= 8) then
          begin
            { By-value record over 4 bytes (up to 8): pass both words, mirroring
              Int64 above. IREmitNodeArm32 already yields r0:r1 for a 5-8 byte
              record value (IR_LOAD_SYM was widened to match); without this
              branch the record fell to the generic 1-word case below and
              silently dropped its high word for every plain-value record over
              4 bytes (bug-arm32-record-byvalue-over-4-bytes-abi-gap). }
            IREmitNodeArm32(IRA[argNode]);  { r0=lo, r1=hi }
            EmitI32($E92D0001); { push {r0} (lo = word j) }
            EmitI32($E92D0002); { push {r1} (hi = word j+1) }
            Inc(j, 2);
          end
          else if (procIdx >= 0) and (nArgs < Procs[procIdx].ParamCount) and
                  TypeIsFloat(Procs[procIdx].Params[nArgs].TypeKind) and
                  (not Procs[procIdx].Params[nArgs].IsRef) and
                  (not Procs[procIdx].Params[nArgs].IsArray) then
          begin
            { By-value float param: evaluate the arg into d0 (widen an int arg),
              then move d0 -> r0:r1 and push as words. A Double is two words; a
              Single narrows to s0 -> r0, one word. See feature-cross-float-returns. }
            IREmitNodeArm32(IRA[argNode]);
            if not TypeIsFloat(IntToTypeKind(IRTk[IRA[argNode]])) then
              EmitIntToD0Arm32;
            if Procs[procIdx].Params[nArgs].TypeKind = tySingle then
            begin
              EmitI32($EEB70BC0);  { vcvt.f32.f64 s0, d0 }
              EmitI32($EE100A10);  { vmov r0, s0 }
              EmitI32($E92D0001);  { push {r0} (word j) }
              Inc(j, 1);
            end
            else
            begin
              EmitI32($EC510B10);  { vmov r0, r1, d0 (r0=lo, r1=hi) }
              EmitI32($E92D0001);  { push {r0} (lo = word j) }
              EmitI32($E92D0002);  { push {r1} (hi = word j+1) }
              Inc(j, 2);
            end;
          end
          else
          begin
            IREmitNodeArm32(IRA[argNode]);
            EmitI32($E92D0001); { push {r0} }
            Inc(j, 1);
          end;
          Inc(nArgs);
          argNode := IRB[argNode];
        end;
        { Variadic callee: more args than declared params is legitimate (AAPCS
          passes them like named args; the arg-word count `j` already reflects
          the actual args pushed, so the register/stack marshalling below is
          correct). Only strict equality blocked it. }
        if (nArgs <> Procs[procIdx].ParamCount) and not ProcVariadic[procIdx] then
          Error('target arm32: call argument count mismatch');

        { Variadic stack tail (words 4..j-1) was pushed in index order, so it lands
          REVERSED in memory (word j-1 lowest = [fp+8], word 4 highest). The callee
          reads variadic args with a FORWARD va_arg walk from [fp+8], so reverse the
          (j-4) low words in place. The four register words (high offsets) and any
          hidden-dest word (at [sp+j*4]) are untouched. A variadic fn's named params
          are the register words, so only the variadic tail is reordered. }
        if ProcVariadic[procIdx] and (j > 5) then
        begin
          vaRevM := j - 4;
          for vaRevP := 0 to (vaRevM div 2) - 1 do
          begin
            vaRevO1 := vaRevP * 4;
            vaRevO2 := (vaRevM - 1 - vaRevP) * 4;
            EmitI32($E59D9000 or vaRevO1);   { ldr r9,  [sp, #o1] }
            EmitI32($E59DC000 or vaRevO2);   { ldr r12, [sp, #o2] }
            EmitI32($E58DC000 or vaRevO1);   { str r12, [sp, #o1] }
            EmitI32($E58D9000 or vaRevO2);   { str r9,  [sp, #o2] }
          end;
        end;

        for i := 0 to j - 1 do
          if i < 4 then
            EmitI32($E59D0000 or (i shl 12) or ((j - 1 - i) * 4)); { ldr r[i], [sp, #off] }

        if RetViaHiddenDest(Procs[procIdx].RetType) then
        begin
          { Hidden dest is the deepest word, at [sp + j*4]; load it into r12.
            The callee prologue stashes r12 (EmitAggregateDestStash) and returns
            the dest pointer in r0. The ldr immediate offset is 12-bit. }
          if j * 4 >= 4096 then
            Error('target arm32: too many aggregate-call argument words');
          EmitI32($E59DC000 or (j * 4));  { ldr r12, [sp, #j*4] (hidden dest) }
          if j <= 4 then
          begin
            { All args fit in r0-r3: drop the arg words + dest before the call. }
            EmitLoadImmArm32(9, (j + 1) * 4);
            EmitI32($E08DD009);           { add sp, sp, r9 (drop args + dest) }
            EmitCallProc(procIdx);
          end
          else
          begin
            { j>4: words 0-3 are in r0-r3, words 4..j-1 are stack arguments the
              callee reads at [fp + 8 + (pnWords-1-k)*4]. Keep them on the stack
              across the call (sp still points at word j-1), then drop args+dest.
              The hidden dest sits at [sp + j*4], above word 0, so the callee's
              stack-param reads never touch it. Mirrors the non-aggregate j>4
              path below. }
            EmitCallProc(procIdx);
            EmitLoadImmArm32(9, (j + 1) * 4);
            EmitI32($E08DD009);           { add sp, sp, r9 (drop args + dest) }
          end;
        end
        else
        begin
          if (j > 0) and (j <= 4) then
          begin
            EmitLoadImmArm32(9, j * 4);
            EmitI32($E08DD009); { add sp, sp, r9 (no stack words; drop all) }
          end;

          EmitCallProc(procIdx);
          if j > 4 then
          begin
            EmitLoadImmArm32(9, j * 4);
            EmitI32($E08DD009); { add sp, sp, r9 (drop all pushed words) }
          end;
          { Float result: callee returned the bits in r0(:r1); move into d0 for
            the value model (mirrors the external-call path). }
          if Procs[procIdx].RetType = tySingle then
          begin
            EmitI32($EE000A10);                     { vmov s0, r0 }
            EmitI32($EEB70AC0);                     { vcvt.f64.f32 d0, s0 }
          end
          else if TypeIsFloat(Procs[procIdx].RetType) then
            EmitI32($EC410B10);                     { vmov d0, r0, r1 (double result) }
        end;
      end;

    IR_CALL_IND:
      begin
        procIdx := Integer(IRIVal[node]);                 { signature proc index }
        if (procIdx >= 0) and ProcCdecl[procIdx] and (not CProgramMode) then
        begin
          { armel (cdecl) indirect call through a `cdecl` proc-type value — a
            dlsym'd C function. PASCAL-mode only: the C frontend marks every C
            fnptr signature ProcCdecl, but a pxx-COMPILED callee reached through
            one uses pxx's internal convention — C-mode indirect calls keep the
            internal path, or lua's dispatch and sqlite's VFS miscompile
            (tstate caught exactly that at b362). Mirrors the external-direct marshalling: build a
            contiguous AAPCS argument block in a 16-byte stack temp (4 bytes for
            int/single/pointer, 8-byte-aligned 8 bytes for double/Int64), load
            words 0..3 into r0..r3. The callee is a runtime value: pushed below
            the block, popped into r12, blx r12. A variadic tail is classified
            by the arg's own IR type (floats promoted to double). Injected
            method-pointer Self is not supported here (C fnptrs have none).
            (feature-cdecl-indirect-cross-targets; x86-64 shape c461fce.) }
          if Integer(IRC[node]) > 0 then
            Error('target arm32: cdecl method pointer not supported');
          IREmitNodeArm32(IRA[node]);               { r0 = callee address }
          EmitI32($E92D0001);                       { push {r0} (callee) }
          EmitI32($E24DD010);                       { sub sp, sp, #16 }
          argNode := IRB[node];
          nArgs := 0;
          j := 0;   { running block offset }
          while argNode <> -1 do
          begin
            if nArgs < Procs[procIdx].ParamCount then
              tk := Procs[procIdx].Params[nArgs].TypeKind
            else if TypeIsFloat(IntToTypeKind(IRTk[IRA[argNode]])) then
              tk := tyDouble                        { variadic float -> double }
            else
              tk := tyInteger;
            if (tk = tyDouble) or (tk = tyExtended) then
            begin
              if (j and 4) <> 0 then Inc(j, 4);
              IREmitNodeArm32(IRA[argNode]);        { d0 = double }
              EmitI32($ED8D0B00 or (j shr 2));      { vstr d0, [sp, #j] }
              Inc(j, 8);
            end
            else if (tk = tyInt64) or (tk = tyUInt64) then
            begin
              if (j and 4) <> 0 then Inc(j, 4);
              EmitNode64Arm32(IRA[argNode]);        { r0=lo, r1=hi }
              EmitI32($E58D0000 or j);              { str r0, [sp, #j] }
              EmitI32($E58D1000 or (j + 4));        { str r1, [sp, #j+4] }
              Inc(j, 8);
            end
            else if tk = tySingle then
            begin
              IREmitNodeArm32(IRA[argNode]);        { d0 = double }
              EmitI32($EEB70BC0);                   { vcvt.f32.f64 s0, d0 }
              EmitI32($ED8D0A00 or (j shr 2));      { vstr s0, [sp, #j] }
              Inc(j, 4);
            end
            else
            begin
              IREmitNodeArm32(IRA[argNode]);        { r0 = arg }
              EmitI32($E58D0000 or j);              { str r0, [sp, #j] }
              Inc(j, 4);
            end;
            Inc(nArgs);
            argNode := IRB[argNode];
          end;
          if j > 16 then
            Error('target arm32: cdecl indirect call argument block exceeds 4 core registers (stack args not supported yet)');
          i := 0;
          while (i * 4) < j do
          begin
            EmitI32($E59D0000 or (i shl 12) or (i * 4)); { ldr r[i], [sp, #i*4] }
            Inc(i);
          end;
          EmitI32($E28DD010);                       { add sp, sp, #16 }
          EmitI32($E8BD1000);                       { pop {r12} (callee) }
          EmitI32($E12FFF3C);                       { blx r12 }
          if Procs[procIdx].RetType = tySingle then
          begin
            EmitI32($EE000A10);                     { vmov s0, r0 }
            EmitI32($EEB70AC0);                     { vcvt.f64.f32 d0, s0 }
          end
          else if TypeIsFloat(Procs[procIdx].RetType) then
            EmitI32($EC410B10);                     { vmov d0, r0, r1 (double result) }
          Exit;
        end;
        { Indirect call through a proc-typed value. Word-based args (<=4 words,
          one per scalar/pointer arg). Push the callee first (deepest), push args,
          load r0..r3 from the arg slots, load the callee into r9, drop the whole
          block, then `blx r9`. (Int64-by-value / managed args via a proc pointer
          are not handled in v1.) An aggregate / frozen-string result pushes its
          hidden caller-destination deeper still (below the callee) and loads it
          into r12 just before the call, like the direct-call path. }
        if IRCallDest[node] >= 0 then
        begin
          IREmitNodeArm32(IRCallDest[node]);         { r0 = hidden destination }
          EmitI32($E92D0001);                        { push {r0} (dest, deepest) }
        end;
        IREmitNodeArm32(IRA[node]);                  { r0 = callee address }
        EmitI32($E92D0001);                          { push {r0} (callee) }
        argNode := IRB[node];
        j := 0;
        nArgs := 0;
        while argNode <> -1 do
        begin
          if (procIdx >= 0) and (nArgs < Procs[procIdx].ParamCount) and
             ((Procs[procIdx].Params[nArgs].TypeKind = tyInt64) or
              (Procs[procIdx].Params[nArgs].TypeKind = tyUInt64)) and
             (not Procs[procIdx].Params[nArgs].IsRef) and
             (not Procs[procIdx].Params[nArgs].IsArray) then
          begin
            { 64-bit by-value param = two words (lo then hi), as the direct call
              does — sqlite's VFS xRead/xWrite take an sqlite_int64 offset; pushing
              it as one word shifts every following arg word in the callee. }
            EmitNode64Arm32(IRA[argNode]);             { r0=lo, r1=hi }
            EmitI32($E92D0001);                        { push {r0} (lo) }
            EmitI32($E92D0002);                        { push {r1} (hi) }
            Inc(j, 2);
          end
          else if (procIdx >= 0) and (nArgs < Procs[procIdx].ParamCount) and
                  (Procs[procIdx].Params[nArgs].TypeKind = tyDouble) and
                  (not Procs[procIdx].Params[nArgs].IsRef) then
          begin
            IREmitNodeArm32(IRA[argNode]);             { d0 }
            if not TypeIsFloat(IntToTypeKind(IRTk[IRA[argNode]])) then EmitIntToD0Arm32;
            EmitI32($EC510B10);                        { vmov r0, r1, d0 }
            EmitI32($E92D0001); EmitI32($E92D0002);    { push lo, hi }
            Inc(j, 2);
          end
          else
          begin
            IREmitNodeArm32(IRA[argNode]);
            EmitI32($E92D0001);                        { push {r0} }
            Inc(j, 1);
          end;
          Inc(nArgs);
          argNode := IRB[argNode];
        end;
        { Block words above the args: callee at [sp+j*4], hidden dest (when
          present) one word deeper at [sp+(j+1)*4]. }
        if IRCallDest[node] >= 0 then nBlock := j + 2 else nBlock := j + 1;
        if (j + 1) * 4 >= 4096 then
          Error('target arm32: too many indirect-call argument words');
        if j <= 4 then
        begin
          for i := 0 to j - 1 do
            EmitI32($E59D0000 or (i shl 12) or ((j - 1 - i) * 4)); { ldr r[i], [sp, #off] }
          EmitI32($E59D9000 or (j * 4));             { ldr r9, [sp, #j*4] (callee) }
          if IRCallDest[node] >= 0 then
            EmitI32($E59DC000 or ((j + 1) * 4));     { ldr r12, [sp, #(j+1)*4] (hidden dest) }
          EmitLoadImmArm32(8, nBlock * 4);
          EmitI32($E08DD008);                        { add sp, sp, r8 (drop args + callee [+ dest]) }
          EmitI32($E12FFF39);                        { blx r9 }
        end
        else
        begin
          { j>4: words 0-3 -> r0-r3, words 4..j-1 stay on the stack across the
            call (the callee reads them at [fp+8+(pnWords-1-k)*4], same reversed
            layout as the direct/virtual j>4 paths). Callee pointer sits above the
            arg block at [sp+j*4]; drop args+callee after the call returns. }
          for i := 0 to 3 do
            EmitI32($E59D0000 or (i shl 12) or ((j - 1 - i) * 4)); { ldr r[i], [sp, #off] }
          EmitI32($E59D9000 or (j * 4));             { ldr r9, [sp, #j*4] (callee) }
          if IRCallDest[node] >= 0 then
            EmitI32($E59DC000 or ((j + 1) * 4));     { ldr r12, [sp, #(j+1)*4] (hidden dest) }
          EmitI32($E12FFF39);                        { blx r9 }
          EmitLoadImmArm32(8, nBlock * 4);
          EmitI32($E08DD008);                        { add sp, sp, r8 (drop args + callee [+ dest]) }
        end;
      end;

    IR_VIRTUAL_CALL:
      begin
        { VMT dispatch. IRA=first arg, IRB=last arg, IRC=proc idx, IRIVal=slot.
          Word-push args (Self = param 0, deepest), load r0..r3, drop the block,
          load the VMT pointer from [Self], call through [VMT + slot*8]. The data
          blob keeps 8-byte slots; the 32-bit address is in the low word. An
          aggregate / frozen-string result pushes its hidden caller-destination
          below the args and loads it into r12 just before the dispatch. }
        procIdx := IRC[node];
        j := Integer(IRIVal[node]);                  { VMT slot }
        if IRCallDest[node] >= 0 then
        begin
          IREmitNodeArm32(IRCallDest[node]);         { r0 = hidden destination }
          EmitI32($E92D0001);                        { push {r0} (dest, deepest) }
        end;
        argNode := IRA[node];
        nArgs := 0;                                  { total arg words }
        while argNode <> -1 do
        begin
          IREmitNodeArm32(IRA[argNode]);
          EmitI32($E92D0001);                        { push {r0} }
          Inc(nArgs);
          argNode := IRB[argNode];
        end;
        if IRCallDest[node] >= 0 then nBlock := nArgs + 1 else nBlock := nArgs;
        if nArgs * 4 >= 4096 then
          Error('target arm32: too many virtual-call argument words');
        if nArgs <= 4 then
        begin
          for i := 0 to nArgs - 1 do
            EmitI32($E59D0000 or (i shl 12) or ((nArgs - 1 - i) * 4)); { ldr r[i], [sp, #off] }
          if IRCallDest[node] >= 0 then
            EmitI32($E59DC000 or (nArgs * 4));       { ldr r12, [sp, #nArgs*4] (hidden dest) }
          EmitLoadImmArm32(8, nBlock * 4);
          EmitI32($E08DD008);                        { add sp, sp, r8 (drop pushed words) }
          EmitI32($E5909000);                        { ldr r9, [r0] (VMT ptr) }
          EmitI32($E5999000 or (j * 8));             { ldr r9, [r9, #slot*8] }
          EmitI32($E12FFF39);                        { blx r9 }
        end
        else
        begin
          { nArgs > 4: words 0-3 go to r0-r3, words 4..nArgs-1 stay on the
            stack across the call — the callee reads them at
            [fp + 8 + (pnWords-1-k)*4], exactly like the direct-call j>4 path
            above. Drop the whole block after the call returns. }
          for i := 0 to 3 do
            EmitI32($E59D0000 or (i shl 12) or ((nArgs - 1 - i) * 4)); { ldr r[i], [sp, #off] }
          if IRCallDest[node] >= 0 then
            EmitI32($E59DC000 or (nArgs * 4));       { ldr r12, [sp, #nArgs*4] (hidden dest) }
          EmitI32($E5909000);                        { ldr r9, [r0] (VMT ptr) }
          EmitI32($E5999000 or (j * 8));             { ldr r9, [r9, #slot*8] }
          EmitI32($E12FFF39);                        { blx r9 }
          EmitLoadImmArm32(8, nBlock * 4);
          EmitI32($E08DD008);                        { add sp, sp, r8 (drop args [+ dest]) }
        end;
      end;

    IR_COSWITCH:
      begin
        { __pxxcoswitch(pfrom, pto): pfrom -> r0, pto -> r1, bl CoSwitch. }
        argNode := IRA[node];                        { IR_ARG pfrom }
        IREmitNodeArm32(IRA[argNode]);               { r0 = pfrom }
        EmitI32($E52D0004);                          { push {r0} (str r0,[sp,#-4]!) }
        argNode := IRB[argNode];                     { IR_ARG pto }
        IREmitNodeArm32(IRA[argNode]);               { r0 = pto }
        EmitI32($E1A01000);                          { mov r1, r0 (pto) }
        EmitI32($E49D0004);                          { pop {r0} (ldr r0,[sp],#4) }
        EmitI32($EB000000 or ((((CoSwitchAddr - CodeLen) div 4) - 2) and $00ffffff)); { bl CoSwitch }
      end;

    IR_PROCADDR:
      begin
        { @proc -> r0 = absolute code address, via a PC-relative load of a 4-byte
          literal patched at finalize. }
        if ProcExternal[IRA[node]] then
        begin
          EmitExternalProcAddr(IRA[node]);           { r0 = resolved external fn ptr (GOT) }
          Exit;
        end;
        EmitI32($E59F0000);                          { ldr r0, [pc] (literal below) }
        EmitI32($EA000000);                          { b .+8 (skip the 4-byte literal) }
        if ProcAddrFixCount >= MAX_CALLFIX then Error('proc addr fixup overflow');
        ProcAddrFix[ProcAddrFixCount].CodePos := CodeLen;
        ProcAddrFix[ProcAddrFixCount].ProcIdx := IRA[node];
        Inc(ProcAddrFixCount);
        EmitI32(0);                                  { 4-byte literal (patched) }
      end;

    IR_FIELD:
      begin
        IREmitNodeArm32(IRA[node]); { base address -> r0 }
        if Integer(IRIVal[node]) <> 0 then
        begin
          EmitLoadImmArm32(1, Integer(IRIVal[node]));
          EmitI32($E0800001);       { add r0, r0, r1 }
        end;
      end;

    IR_INDEX:
      begin
        left := IRA[node];
        right := IRB[node];
        lo := IRC[node];
        elemSize := Integer(IRIVal[node]);
        IREmitNodeArm32(left);      { base address -> r0 }
        if (InLValueWrite and (IRKind[left] = IR_LEA) and
            Syms[IRA[left]].IsArray and (Syms[IRA[left]].ArrLen = -1)) then
        begin
          { Indexing INTO a dynamic-array symbol during a write (`g[i] := x`,
            or the base level of a nested SetLength(a[i], n)): the write-mode
            IR_LEA branch above (added for a SetLength target that IS the
            array symbol itself) leaves r0 one deref short of the data
            pointer -- correct for THAT caller, but indexing always needs to
            read the array's own handle to use as a base; the real write
            happens at the computed element address further down, not to the
            array's handle slot. Deref once more to reach it (v1: no COW here
            either, matching the rest of this backend -- x86-64 reaches the
            same data pointer via a full COW-aware PXXDynArrayUnique call
            instead of a bare deref, but nothing on this backend tracks array
            aliasing to make that distinction matter yet). }
          EmitI32($E5900000);  { ldr r0, [r0] = data ptr }
        end
        else if ((IRKind[left] = IR_LEA) and (Syms[IRA[left]].TypeKind = tyAnsiString) and
            not Syms[IRA[left]].IsArray) or
           (((IRKind[left] = IR_FIELD) or (IRKind[left] = IR_INDEX)) and
            (IRTk[left] = Ord(tyAnsiString)) and (elemSize = 1)) then
        begin
          { Managed string in write position: clone-if-shared so the index write
            does not mutate a buffer still aliased by another handle. r0 holds the
            slot address (write-mode IR_LEA); PXXStrUnique publishes a unique
            handle into the slot and returns it. Read position just loads the
            handle. Mirrors i386 IR_INDEX. }
          if InLValueWrite then
          begin
            procIdx := FindProc('PXXStrUnique');
            if procIdx < 0 then Error('compiler error: PXXStrUnique not found');
            EmitCallProc(procIdx);       { r0 (slot addr) -> r0 unique handle }
          end
          else if (IRKind[left] = IR_LEA) and (Syms[IRA[left]].Kind = skParam) and
                  Syms[IRA[left]].IsRef then
            EmitI32($E5900000)      { ldr r0, [r0] (&handle -> handle) }
          else if (IRKind[left] = IR_FIELD) or (IRKind[left] = IR_INDEX) then
            EmitI32($E5900000);     { ldr r0, [r0] = handle }
        end;
        EmitI32($E92D0001);         { push {r0} }
        { The INDEX expression is a READ even when the whole IR_INDEX is a
          write target: `b[Length(b)] := c` must read b's handle inside
          Length, not its slot address. Left set, IR_LEA(b) kept the slot
          addr, Length read [slot-8] garbage, and the store landed wild —
          silently lost on small offsets, SIGSEGV on big ones
          (bug-arm32-chacha20poly1305-segfault). x86-64 has had this reset
          from the start; the other backends never got it. }
        savedLValueWrite := InLValueWrite;
        InLValueWrite := False;
        IREmitNodeArm32(right);     { index -> r0 }
        InLValueWrite := savedLValueWrite;
        if lo <> 0 then
        begin
          EmitLoadImmArm32(1, lo);
          EmitI32($E0400001);       { sub r0, r0, r1 }
        end;
        if elemSize = 8 then
          EmitI32($E1A00180)        { lsl r0, r0, #3 }
        else if elemSize = 4 then
          EmitI32($E1A00100)        { lsl r0, r0, #2 }
        else if elemSize = 2 then
          EmitI32($E1A00080)        { lsl r0, r0, #1 }
        else if elemSize <> 1 then
        begin
          EmitLoadImmArm32(1, elemSize);
          EmitI32($E0000091);       { mul r0, r1, r0 }
        end;
        EmitI32($E8BD0002);         { pop {r1} = base }
        EmitI32($E0800001);         { add r0, r0, r1 }
      end;

    IR_LOAD_MEM:
      begin
        IREmitNodeArm32(IRA[node]); { address -> r0 }
        tk := IntToTypeKind(IRTk[node]);
        if TypeIsFloat(tk) then
        begin
          if tk = tySingle then
          begin
            EmitI32($ED900A00);  { vldr s0, [r0] }
            EmitI32($EEB70AC0);  { vcvt.f64.f32 d0, s0 }
          end
          else
            EmitI32($ED900B00);  { vldr d0, [r0] }
          Exit;
        end;
        if (tk = tyString) or (tk = tyFixedString) or (tk = tyShortString) then
        begin
          { A frozen/inline-string value IS its buffer address. Deref'ing a
            pointer-to-frozen-string (typinfo NamePtr^) yields that address — a
            pointer-width (4-byte) load, not the TypeSize(tyString)=8 path.
            bug-cross-gate-masked-failures. }
          EmitI32($E5900000);          { ldr r0, [r0] (pointer width) }
          Exit;
        end;
        if not (TypeIsOrdinal(tk) or (tk = tyBoolean) or (tk = tyPointer) or
                (tk = tyChar) or (tk = tyUnknown) or
                (tk = tyAnsiString) or (tk = tyClass) or (tk = tyRecord)) then
          Error('target arm32: load through pointer of this type not yet supported');
        sz := TypeSize(tk);
        sgn := TypeSigned(tk);
        if sz = 1 then
        begin
          if sgn then EmitI32($E1D000D0) else EmitI32($E5D00000); { ldrsb/ldrb r0, [r0] }
        end
        else if sz = 2 then
        begin
          if sgn then EmitI32($E1D000F0) else EmitI32($E1D000B0); { ldrsh/ldrh r0, [r0] }
        end
        else if Is64BitArm32(tk) or (tk = tyRecord) then
        begin
          { A record VALUE loaded through memory only ever means a <=8-byte
            by-value record (IRLowerCallArg wraps a record-returning call /
            operator result in IR_LOAD_MEM; >8-byte records go by pointer).
            Load both words like Int64 — the old 1-word record load handed a
            bignum operator chain (`a * b + a`) a TBigInt whose dynarray handle
            word was stale garbage and lib_bignum_ops crashed on arm32 too
            (bug-riscv32-byval-record-param-one-word; completes the v137
            record-param widening). Harmless for a <=4-byte record: r1 is
            scratch. }
          EmitI32($E5901004);  { ldr r1, [r0, #4] (hi first, r0 is the addr) }
          EmitI32($E5900000);  { ldr r0, [r0]     (lo) }
        end
        else
          EmitI32($E5900000); { ldr r0, [r0] (4-byte) }
      end;

    IR_STORE_MEM:
      begin
        tk := IntToTypeKind(IRTk[node]);
        if tk = tyString then
        begin
          { Frozen inline-string store through a pointer (PString(p)^ := s): copy
            the 8-byte length prefix, then the `length` chars. Mirrors i386. }
          valNode := IRB[node];
          IREmitNodeArm32(valNode);                { r0 = source string addr }
          EmitI32($E92D0001);                      { push {r0} (src) }
          savedLValueWrite := InLValueWrite;
          InLValueWrite := True;
          IREmitNodeArm32(IRA[node]);              { r0 = dest addr }
          InLValueWrite := savedLValueWrite;
          EmitI32($E1A06000);                      { mov r6, r0 (dst) }
          EmitI32($E8BD0020);                      { pop {r5} (src) }
          if IntToTypeKind(IRTk[valNode]) = tyChar then
            Error('target arm32: char-to-inline-string store through pointer not yet supported');
          EmitI32($E5959000);                      { ldr r9, [r5] (len lo) }
          EmitI32($E5869000);                      { str r9, [r6] }
          EmitI32($E5959004);                      { ldr r9, [r5,#4] (len hi) }
          EmitI32($E5869004);                      { str r9, [r6,#4] }
          EmitI32($E5954000);                      { ldr r4, [r5] (count) }
          EmitI32($E2855008);                      { add r5, r5, #8 }
          EmitI32($E2866008);                      { add r6, r6, #8 }
          EmitArm32CopyBytes(4, 5, 6);
          Exit;
        end;
        if tk = tyAnsiString then
        begin
          valNode := IRB[node];
          EmitAnsiStringFromNodeArm32(valNode); { r0 = new }
          EmitI32($E92D0001);                   { push {r0} new }
          savedLValueWrite := InLValueWrite;
          InLValueWrite := True;
          IREmitNodeArm32(IRA[node]);           { r0 = slot address }
          InLValueWrite := savedLValueWrite;
          EmitI32($E1A01000);                   { mov r1, r0 }
          EmitI32($E5910000);                   { ldr r0, [r1] old }
          EmitI32($E59D2000);                   { ldr r2, [sp] new }
          EmitI32($E5812000);                   { str r2, [r1] }
          EmitStrDecRefArm32;
          EmitI32($E28DD004);                   { add sp, sp, #4 }
          Exit;
        end;
        if TypeIsFloat(tk) then
        begin
          IREmitNodeArm32(IRB[node]);               { value -> d0 (or r0) }
          if not TypeIsFloat(IntToTypeKind(IRTk[IRB[node]])) then
            EmitIntToD0Arm32;
          EmitI32($ED2D0B02);                       { vpush {d0} }
          savedLValueWrite := InLValueWrite;
          InLValueWrite := True;
          IREmitNodeArm32(IRA[node]);               { address -> r0 }
          InLValueWrite := savedLValueWrite;
          EmitI32($ECBD0B02);                       { vpop {d0} }
          if tk = tySingle then
          begin
            EmitI32($EEB70BC0);                     { vcvt.f32.f64 s0, d0 }
            EmitI32($ED800A00);                     { vstr s0, [r0] }
          end
          else
            EmitI32($ED800B00);                     { vstr d0, [r0] }
          Exit;
        end;
        if not (TypeIsOrdinal(tk) or (tk = tyBoolean) or (tk = tyPointer) or
                (tk = tyChar) or (tk = tyClass) or (tk = tyUnknown)) then
          Error('target arm32: store through pointer of this type not yet supported');
        if Is64BitArm32(tk) then
        begin
          EmitNode64Arm32(IRB[node]);  { value -> r0:r1 }
          EmitI32($E92D0003);          { push {r0, r1} }
          savedLValueWrite := InLValueWrite;
          InLValueWrite := True;
          IREmitNodeArm32(IRA[node]);  { address -> r0 }
          InLValueWrite := savedLValueWrite;
          EmitI32($E8BD0006);          { pop {r1, r2} (value lo, hi) }
          EmitI32($E5801000);          { str r1, [r0] }
          EmitI32($E5802004);          { str r2, [r0, #4] }
          Exit;
        end;
        IREmitNodeArm32(IRB[node]); { value -> r0 (or d0 if float) }
        { C double->int: a float RHS (in d0) into an integer field/element
          truncates (VFP vcvt.s32.f64) before the store. Mirrors IR_STORE_SYM. }
        if CProgramMode and (not TypeIsFloat(tk)) and
           TypeIsFloat(IntToTypeKind(IRTk[IRB[node]])) then
        begin
          EmitI32($EEBD0BC0);       { vcvt.s32.f64 s0, d0 (trunc) }
          EmitI32($EE100A10);       { vmov r0, s0 }
        end;
        EmitI32($E92D0001);         { push {r0} }
        savedLValueWrite := InLValueWrite;
        InLValueWrite := True;
        IREmitNodeArm32(IRA[node]); { address -> r0 }
        InLValueWrite := savedLValueWrite;
        EmitI32($E8BD0002);         { pop {r1} (value) }
        sz := TypeSize(tk);
        if sz = 1 then EmitI32($E5C01000)      { strb r1, [r0] }
        else if sz = 2 then EmitI32($E1C010B0) { strh r1, [r0] }
        else EmitI32($E5801000);               { str r1, [r0] }
      end;

    IR_COPY_REC:
      begin
        { PXXMemMove(dest, src, count). }
        IREmitNodeArm32(IRB[node]);          { r0 = src }
        EmitI32($E92D0001);                  { push {r0} }
        IREmitNodeArm32(IRA[node]);          { r0 = dest }
        EmitI32($E8BD0002);                  { pop {r1} (src) }
        EmitLoadImmArm32(2, IRIVal[node]);   { r2 = count }
        procIdx := FindProc('PXXMemMove');
        if procIdx < 0 then Error('compiler error: PXXMemMove not found');
        EmitCallProc(procIdx);
      end;

    IR_COPY_REC_MANAGED:
      begin
        { ARC record copy: retain src, release dest, then move. }
        IREmitNodeArm32(IRB[node]);          { r0 = src }
        EmitI32($E92D0001);                  { push {r0} src at [sp+4] later }
        IREmitNodeArm32(IRA[node]);          { r0 = dest }
        EmitI32($E92D0001);                  { push {r0} dest at [sp] }
        procIdx := FindProc('PXXRecordRetain');
        if procIdx < 0 then Error('compiler error: PXXRecordRetain not found');
        EmitI32($E59D0004);                  { ldr r0, [sp, #4] (src) }
        EmitLoadDataRefArm32(1, -(RECORD_RTTI_DATAREF_BASE + (IRC[node] - REC_UCLASS_BASE)));
        EmitCallProc(procIdx);
        procIdx := FindProc('PXXRecordRelease');
        if procIdx < 0 then Error('compiler error: PXXRecordRelease not found');
        EmitI32($E59D0000);                  { ldr r0, [sp] (dest) }
        EmitLoadDataRefArm32(1, -(RECORD_RTTI_DATAREF_BASE + (IRC[node] - REC_UCLASS_BASE)));
        EmitCallProc(procIdx);
        procIdx := FindProc('PXXMemMove');
        if procIdx < 0 then Error('compiler error: PXXMemMove not found');
        EmitI32($E59D0000);                  { ldr r0, [sp] (dest) }
        EmitI32($E59D1004);                  { ldr r1, [sp, #4] (src) }
        EmitLoadImmArm32(2, IRIVal[node]);   { r2 = count }
        EmitCallProc(procIdx);
        EmitI32($E28DD008);                  { add sp, sp, #8 }
      end;

    IR_DEFAULT_MEM:
      begin
        IREmitNodeArm32(IRA[node]);          { r0 = dest }
        if (IRC[node] >= 0) and RecordHasManagedFields(IRC[node]) then
        begin
          EmitI32($E92D0001);                { push {r0} dest }
          procIdx := FindProc('PXXRecordRelease');
          if procIdx < 0 then Error('compiler error: PXXRecordRelease not found');
          EmitI32($E59D0000);                { ldr r0, [sp] (dest) }
          EmitLoadDataRefArm32(1, -(RECORD_RTTI_DATAREF_BASE + (IRC[node] - REC_UCLASS_BASE)));
          EmitCallProc(procIdx);
          procIdx := FindProc('PXXMemZero');
          if procIdx < 0 then Error('compiler error: PXXMemZero not found');
          EmitI32($E59D0000);                { ldr r0, [sp] (dest) }
          EmitLoadImmArm32(1, IRIVal[node]); { r1 = count }
          EmitCallProc(procIdx);
          EmitI32($E28DD004);                { add sp, sp, #4 }
        end
        else
        begin
          procIdx := FindProc('PXXMemZero');
          if procIdx < 0 then Error('compiler error: PXXMemZero not found');
          EmitLoadImmArm32(1, IRIVal[node]); { r1 = count }
          EmitCallProc(procIdx);
        end;
      end;

    IR_CLASSREF:
      EmitLoadDataRefArm32(0, -(CLASSREF_DATAREF_BASE + IRA[node])); { r0 = class RTTI blob addr }

    IR_VMTADDR:
      EmitLoadDataRefArm32(0, UClsVMTOffset[IRA[node]]); { r0 = class VMT addr (is/as identity) }

    IR_IMTADDR:
      EmitLoadDataRefArm32(0, IMTOff[IRA[node]]); { r0 = interface method table addr }

    IR_SET_LIT:
      EmitLoadDataRefArm32(0, IRIVal[node]);   { r0 = set-literal blob addr }

    IR_SET_COPY:
      begin
        { Copy 32-byte set from src (IRB) to dest (IRA). }
        IREmitNodeArm32(IRB[node]);              { r0 = source addr }
        EmitI32($E92D0001);                      { push {r0} }
        IREmitNodeArm32(IRA[node]);              { r0 = dest addr }
        EmitI32($E1A06000);                      { mov r6, r0 (dst) }
        EmitI32($E8BD0020);                      { pop {r5} (src) }
        EmitLoadImmArm32(4, 32);                 { r4 = 32 }
        EmitArm32CopyBytes(4, 5, 6);
      end;

    IR_SET_BINOP:
      begin
        { Set +/-/* over 8 dwords into the BSS scratch (IRIVal). }
        IREmitNodeArm32(IRA[node]);              { r0 = lhs addr }
        EmitI32($E92D0001);                      { push {r0} }
        IREmitNodeArm32(IRB[node]);              { r0 = rhs addr }
        EmitI32($E1A02000);                      { mov r2, r0 (rhs) }
        EmitI32($E8BD0002);                      { pop {r1} (lhs) }
        EmitI32($E59F3000);                      { ldr r3, [pc] (scratch addr) }
        EmitI32($EA000000);                      { b .+8 }
        EmitGlobRef(IRIVal[node]);
        for i := 0 to 7 do
        begin
          EmitI32($E5914000 or (i * 4));         { ldr r4, [r1, #i*4] }
          EmitI32($E5925000 or (i * 4));         { ldr r5, [r2, #i*4] }
          if IntToTokenKind(IRC[node]) = tkPlus then EmitI32($E1844005)   { orr r4,r4,r5 }
          else if IntToTokenKind(IRC[node]) = tkStar then EmitI32($E0044005) { and r4,r4,r5 }
          else if IntToTokenKind(IRC[node]) = tkMinus then EmitI32($E1C44005); { bic r4,r4,r5 }
          EmitI32($E5834000 or (i * 4));         { str r4, [r3, #i*4] }
        end;
        EmitI32($E1A00003);                      { mov r0, r3 (result addr) }
      end;

    IR_SET_CMP:
      begin
        { Compare two 32-byte sets (8 dwords). r6 = differences, r7 = subset
          violations. }
        IREmitNodeArm32(IRA[node]);              { r0 = lhs addr }
        EmitI32($E92D0001);                      { push {r0} }
        IREmitNodeArm32(IRB[node]);              { r0 = rhs addr }
        EmitI32($E1A02000);                      { mov r2, r0 (rhs) }
        EmitI32($E8BD0002);                      { pop {r1} (lhs) }
        EmitI32($E3A06000);                      { mov r6, #0 (differences) }
        EmitI32($E3A07000);                      { mov r7, #0 (violations) }
        for i := 0 to 7 do
        begin
          EmitI32($E5914000 or (i * 4));         { ldr r4, [r1, #i*4] (lhs) }
          EmitI32($E5925000 or (i * 4));         { ldr r5, [r2, #i*4] (rhs) }
          EmitI32($E0248005);                    { eor r8, r4, r5 }
          EmitI32($E1866008);                    { orr r6, r6, r8 }
          if (IRC[node] = Ord(tkLe)) or (IRC[node] = Ord(tkLt)) then
          begin
            EmitI32($E1C48005);                  { bic r8, r4, r5 (lhs and not rhs) }
            EmitI32($E1877008);                  { orr r7, r7, r8 }
          end
          else if (IRC[node] = Ord(tkGe)) or (IRC[node] = Ord(tkGt)) then
          begin
            EmitI32($E1C58004);                  { bic r8, r5, r4 (rhs and not lhs) }
            EmitI32($E1877008);                  { orr r7, r7, r8 }
          end;
        end;
        if IRC[node] = Ord(tkEq) then
        begin
          EmitI32($E3560000);                    { cmp r6, #0 }
          EmitI32($03A00001);                    { moveq r0, #1 }
          EmitI32($13A00000);                    { movne r0, #0 }
        end
        else if IRC[node] = Ord(tkNeq) then
        begin
          EmitI32($E3560000);                    { cmp r6, #0 }
          EmitI32($13A00001);                    { movne r0, #1 }
          EmitI32($03A00000);                    { moveq r0, #0 }
        end
        else if (IRC[node] = Ord(tkLe)) or (IRC[node] = Ord(tkGe)) then
        begin
          EmitI32($E3570000);                    { cmp r7, #0 }
          EmitI32($03A00001);                    { moveq r0, #1 }
          EmitI32($13A00000);                    { movne r0, #0 }
        end
        else { tkLt / tkGt: proper = subset AND unequal }
        begin
          EmitI32($E3570000);                    { cmp r7, #0 }
          EmitI32($03A00001);                    { moveq r0, #1 }
          EmitI32($13A00000);                    { movne r0, #0 }
          EmitI32($E3560000);                    { cmp r6, #0 }
          EmitI32($13A03001);                    { movne r3, #1 }
          EmitI32($03A03000);                    { moveq r3, #0 }
          EmitI32($E0000003);                    { and r0, r0, r3 }
        end;
      end;

    IR_RTTI_REG:
      EmitLoadDataRefArm32(0, -100);   { r0 = RTTI-registry addr (sentinel) }

    IR_RESOURCES:
      EmitLoadDataRefArm32(0, -101);   { r0 = resource-table addr (sentinel) }

    IR_SYSCALL:
      begin
        { Raw syscall (EABI): args (nr, a0..a5) pushed left-to-right, then
          popped into r7 (number) and r0..r5. Result stays in r0. }
        argNode := IRA[node]; nArgs := 0;
        while argNode <> -1 do
        begin
          IREmitNodeArm32(IRA[argNode]);
          EmitI32($E92D0001); { push {r0} }
          Inc(nArgs);
          argNode := IRB[argNode];
        end;
        for i := nArgs - 1 downto 0 do
          if i = 0 then
            EmitI32($E8BD0080)                  { pop {r7} }
          else
            EmitI32($E8BD0000 or (1 shl (i - 1))); { pop {r[i-1]} }
        EmitI32($EF000000); { svc 0 }
        { The kernel returns a 32-bit value in r0, but the node is typed Int64
          (results are signed: a negative is -errno). Sign-extend into the high
          word so `result < 0` and other full-64-bit uses are correct — without
          this, a -errno return reads as a large positive Int64. }
        EmitI32($E1A01FC0); { mov r1, r0, asr #31 }
      end;

    IR_CLONE:
      begin
        { __pxxclone(flags, childStack, entry, arg, ctidptr): evaluate the five
          args left-to-right, pop into r0..r4 (the clone stub's input contract:
          r0=flags r1=childStack r2=entry r3=arg r4=ctidptr), then bl the bare
          clone+trampoline stub. Child tid stays in r0. }
        EnsureCloneStub;
        argNode := IRA[node]; nArgs := 0;
        while argNode <> -1 do
        begin
          IREmitNodeArm32(IRA[argNode]);
          EmitI32($E92D0001);           { push {r0} }
          Inc(nArgs);
          argNode := IRB[argNode];
        end;
        for i := nArgs - 1 downto 0 do
          EmitI32($E8BD0000 or (1 shl i));   { pop {r[i]}  (i=4..0) }
        EmitI32($EB000000 or ((((CloneStubAddr - CodeLen) div 4) - 2) and $00FFFFFF)); { bl stub }
      end;

    IR_ATOMIC:
      begin
        { Atomic read-modify-write on addr^, returning the OLD value, via an
          LL/SC (ldrex/strex) retry loop + a trailing dmb ish (ARM has no
          implicit barrier on ldrex/strex, unlike aarch64's ldaxr/stlxr or x86
          TSO). Args popped into r1=addr (+ r2=val/expected, r3=newval). Result
          (old) in r0. The 64-bit variants need ldrexd/strexd register pairs —
          rejected, exactly like i386. Hex verified against clang -march=armv7-a. }
        if (IRIVal[node] = ATOMIC_XCHG64) or (IRIVal[node] = ATOMIC_CAS64) or
           (IRIVal[node] = ATOMIC_ADD64) then
          Error('target arm32: __pxxatomic_*64 not supported (32-bit target)');
        argNode := IRA[node]; nArgs := 0;
        while argNode <> -1 do
        begin
          IREmitNodeArm32(IRA[argNode]);
          EmitI32($E92D0001);           { push {r0} }
          Inc(nArgs);
          argNode := IRB[argNode];
        end;
        case IRIVal[node] of
          ATOMIC_CAS:
            begin
              EmitI32($E8BD0008);       { pop {r3}  newval }
              EmitI32($E8BD0004);       { pop {r2}  expected }
              EmitI32($E8BD0002);       { pop {r1}  addr }
              EmitI32($E1910F9F);       { ldrex r0, [r1]   old }
              EmitI32($E1500002);       { cmp r0, r2 }
              EmitI32($1A000002);       { bne done (+2) }
              EmitI32($E1814F93);       { strex r4, r3, [r1] }
              EmitI32($E3540000);       { cmp r4, #0 }
              EmitI32($1AFFFFF9);       { bne loop (-7) }
              EmitI32($F57FF05B);       { dmb ish  (done) }
            end;
          ATOMIC_ADD:
            begin
              EmitI32($E8BD0004);       { pop {r2}  delta }
              EmitI32($E8BD0002);       { pop {r1}  addr }
              EmitI32($E1910F9F);       { ldrex r0, [r1]   old }
              EmitI32($E0804002);       { add r4, r0, r2 }
              EmitI32($E1813F94);       { strex r3, r4, [r1] }
              EmitI32($E3530000);       { cmp r3, #0 }
              EmitI32($1AFFFFFA);       { bne loop (-6) }
              EmitI32($F57FF05B);       { dmb ish }
            end;
          else { ATOMIC_XCHG }
            begin
              EmitI32($E8BD0004);       { pop {r2}  val }
              EmitI32($E8BD0002);       { pop {r1}  addr }
              EmitI32($E1910F9F);       { ldrex r0, [r1] }
              EmitI32($E1813F92);       { strex r3, r2, [r1] }
              EmitI32($E3530000);       { cmp r3, #0 }
              EmitI32($1AFFFFFB);       { bne loop (-5) }
              EmitI32($F57FF05B);       { dmb ish }
            end;
        end;
        { The old value is a 32-bit word in r0, but the intrinsic is typed Int64
          (r0:r1). Sign-extend into the high word so the full-64-bit result is
          correct — mirrors IR_SYSCALL's `mov r1, r0, asr #31`. }
        EmitI32($E1A01FC0);             { mov r1, r0, asr #31 }
      end;

    IR_NEG:
      begin
        tk := IntToTypeKind(IRTk[node]);
        if TypeIsFloat(tk) then
        begin
          IREmitNodeArm32(IRA[node]);
          EmitI32($EEB10B40);  { vneg.f64 d0, d0 }
        end
        else if Is64BitArm32(tk) then
        begin
          EmitNode64Arm32(IRA[node]);  { value -> r0:r1 }
          EmitI32($E2700000);  { rsbs r0, r0, #0 }
          EmitI32($E2E11000);  { rsc  r1, r1, #0 (negate 64-bit) }
        end
        else
        begin
          IREmitNodeArm32(IRA[node]);
          EmitI32($E2600000); { rsb r0, r0, #0 }
        end;
      end;

    IR_NOT:
      begin
        IREmitNodeArm32(IRA[node]);
        if Is64BitArm32(IntToTypeKind(IRTk[node])) then
        begin
          { 64-bit value in the r0:r1 pair: complement BOTH words. `mvn r0,r0`
            alone left the high word (r1) intact, so `not x` for an Int64 read as
            a 32-bit-wide complement (e.g. -6 printed as 4294967290). Mirrors the
            i386 eax:edx pair. }
          EmitI32($E1E00000); { mvn r0, r0 }
          EmitI32($E1E01001); { mvn r1, r1 }
        end
        else if TypeIsOrdinal(IntToTypeKind(IRTk[node])) and
           (IntToTypeKind(IRTk[node]) <> tyBoolean) then
        begin
          EmitI32($E1E00000); { mvn r0, r0 }
        end
        else
        begin
          EmitI32($E2200001); { eor r0, r0, #1 }
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
          if IRC[node] = -3 then
          begin
            { write(PChar): runtime NUL-terminated C string (strlen + write). }
            IREmitNodeArm32(valNode);
            EmitWriteCStrArm32;
          end
          else if tk = tyVariant then
          begin
            EmitLoadVariantAddrArm32(valNode);    { r0 = slot addr }
            procIdx := FindProc('PXXWriteVariant');
            if procIdx < 0 then Error('compiler error: PXXWriteVariant not found');
            EmitCallProc(procIdx);
          end
          else if TypeIsFloat(tk) then
          begin
            IREmitNodeArm32(valNode);             { value -> d0 }
            j := IRC[node];                       { decimals }
            if j = -2 then EmitFloatCallWriterArm32('PXXWriteFloatNat', -1)
            else if j >= 0 then EmitFloatCallWriterArm32('PXXWriteFloatFixed', j)
            else EmitFloatCallWriterArm32('PXXWriteFloatSci', -1);
          end
          else if tk = tyChar then
          begin
            IREmitNodeArm32(valNode);
            if wid > 1 then
            begin
              { Save r0 on stack to preserve character value }
              EmitI32($E92D0001); { push {r0} }
              EnsureSpaces;
              EmitwriteSyscall(SpacesOffset, wid - 1);
              EmitI32($E8BD0001); { pop {r0} }
            end;
            EmitwriteCharArm32;
          end
          else if Is64BitArm32(tk) then
          begin
            EmitNode64Arm32(valNode);   { r0:r1 = value }
            if tk = tyUInt64 then EmitwriteUInt64Arm32
            else EmitwriteInt64Arm32;
          end
          else if TypeIsOrdinal(tk) or (tk = tyUnknown) then
          begin
            IREmitNodeArm32(valNode);
            if (tk <> tyUnknown) and not TypeSigned(tk) then
            begin
              if wid > 0 then
                EmitwriteUIntWArm32(wid)
              else
                EmitwriteUIntArm32;
            end
            else
            begin
              if wid > 0 then
                EmitwriteIntWArm32(wid)
              else
                EmitwriteIntArm32;
            end;
          end
          else if tk = tyAnsiString then
          begin
            IREmitNodeArm32(valNode);            { r0 = handle }
            EmitI32($E3500000);                  { cmp r0, #0 }
            j := CodeLen;
            EmitI32($0A000000);                  { beq done }
            EmitI32($E92D0001);                  { push {r0} }
            EmitI32($E5102008);                  { ldr r2, [r0, #-8] }
            EmitI32($E1A01000);                  { mov r1, r0 }
            EmitI32($E3A00001);                  { mov r0, #1 }
            EmitI32($E3A07004);                  { mov r7, #4 }
            EmitI32($EF000000);                  { svc #0 }
            EmitI32($E8BD0001);                  { pop {r0} handle }
            if (IRKind[valNode] = IR_BINOP) and
               (IntToTypeKind(IRTk[valNode]) = tyAnsiString) then
              EmitStrDecRefArm32;
            Patch32(j, $0A000000 or ((((CodeLen - j) div 4) - 2) and $00ffffff));
          end
          else if tk = tyString then
          begin
            IREmitNodeArm32(valNode);            { r0 = [len:8][data] }
            EmitI32($E5902000);                  { ldr r2, [r0] }
            EmitI32($E2801008);                  { add r1, r0, #8 }
            EmitI32($E3A00001);                  { mov r0, #1 }
            EmitI32($E3A07004);                  { mov r7, #4 }
            EmitI32($EF000000);                  { svc #0 }
          end
          else
            Error('target arm32: write of this operand not yet supported');
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
            IREmitNodeArm32(IRA[node]);
            EmitI32($E3A07001); { mov r7, #1 }
            EmitI32($EF000000); { svc #0 }
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

    IR_VAR_STORE:
      begin
        { IRA = dest addr, IRB = value/src addr, IRC = source TTypeKind ord. }
        tk := IntToTypeKind(IRC[node]);
        if tk = tyVariant then
        begin
          { ARC-correct 16-byte variant-to-variant copy. }
          EmitLoadVariantAddrArm32(IRB[node]);   { r0 = src addr }
          EmitVarHelperCallArm32('PXXVarRetain');
          EmitI32($E92D0001);                    { push {r0} (src) }
          IREmitNodeArm32(IRA[node]);            { r0 = dest addr }
          EmitVarHelperCallArm32('PXXVarClear');
          EmitI32($E8BD0002);                    { pop {r1} (src) }
          EmitI32($E5912000);                    { ldr r2, [r1] }
          EmitI32($E5802000);                    { str r2, [r0] }
          EmitI32($E5912004);                    { ldr r2, [r1, #4] }
          EmitI32($E5802004);                    { str r2, [r0, #4] }
          EmitI32($E5912008);                    { ldr r2, [r1, #8] }
          EmitI32($E5802008);                    { str r2, [r0, #8] }
          EmitI32($E591200C);                    { ldr r2, [r1, #12] }
          EmitI32($E580200C);                    { str r2, [r0, #12] }
        end
        else
        begin
          j := VariantTagForTk386(tk, 'Variant :=');
          if (tk = tyString) or (tk = tyAnsiString) then
          begin
            if tk = tyString then
              EmitAnsiStringFromNodeArm32(IRB[node])  { r0 = new handle (owned) }
            else
            begin
              IREmitNodeArm32(IRB[node]);             { r0 = handle }
              EmitStrIncRefArm32;
            end;
            EmitI32($E92D0001);                       { push {r0} (payload) }
          end
          else
          begin
            IREmitNodeArm32(IRB[node]);               { scalar -> r0 / double -> d0 }
            if TypeIsFloat(tk) then
              EmitI32($ED2D0B02)                      { vpush {d0} }
            else
              EmitI32($E92D0001);                     { push {r0} }
          end;
          IREmitNodeArm32(IRA[node]);                 { r0 = dest addr }
          EmitVariantFillArm32(j, tk);
        end;
      end;

    IR_VAR_BOX:
      begin
        { Box a scalar into a temp variant (IRA = temp addr); addr -> r0. }
        tk := IntToTypeKind(IRC[node]);
        j := VariantTagForTk386(tk, 'Variant operand');
        if (tk = tyString) or (tk = tyAnsiString) then
        begin
          if tk = tyString then
            EmitAnsiStringFromNodeArm32(IRB[node])
          else
          begin
            IREmitNodeArm32(IRB[node]);
            EmitStrIncRefArm32;
          end;
          EmitI32($E92D0001);                         { push {r0} (payload) }
        end
        else
        begin
          IREmitNodeArm32(IRB[node]);
          if TypeIsFloat(tk) then
            EmitI32($ED2D0B02)                        { vpush {d0} }
          else
            EmitI32($E92D0001);                       { push {r0} }
        end;
        IREmitNodeArm32(IRA[node]);                   { r0 = temp addr }
        EmitVariantFillArm32(j, tk);                  { leaves addr in r0 }
      end;

    IR_VAR_BINOP:
      begin
        { PXXVarBinOp(dest, left, right, opTk, isCompare): args r0-r3 plus
          the 5th argument on the stack at [sp]. }
        sgn := IntToTypeKind(IRTk[node]) = tyBoolean;
        IREmitNodeArm32(IRA[node]);                   { r0 = left addr }
        EmitI32($E92D0001);                           { push {r0} }
        IREmitNodeArm32(IRB[node]);                   { r0 = right addr }
        EmitI32($E1A02000);                           { mov r2, r0 (right) }
        EmitI32($E8BD0002);                           { pop {r1} (left) }
        if sgn then
          EmitI32($E3A00000)                          { mov r0, #0 (dest unused) }
        else
        begin
          EmitI32($E59F0000);                         { ldr r0, [pc] }
          EmitI32($EA000000);                         { b .+8 }
          EmitGlobRef(Integer(IRIVal[node]));         { dest temp }
        end;
        EmitLoadImmArm32(3, IRC[node]);               { r3 = opTk }
        if sgn then
          EmitLoadImmArm32(9, 1)
        else
          EmitLoadImmArm32(9, 0);
        EmitI32($E92D0200);                           { push {r9} (isCompare, 5th arg) }
        procIdx := FindProc('PXXVarBinOp');
        if procIdx < 0 then Error('compiler error: PXXVarBinOp not found');
        EmitCallProc(procIdx);
        EmitI32($E28DD004);                           { add sp, sp, #4 }
      end;

    else
      Error('target arm32: IR op not yet supported: ' + IROpName(IRKind[node]));
  end;
end;

procedure IREmitMachineCodeArm32;
var i, lblId, pos, targetOffset, f, si, classIdx, sz, procIdx: Integer;
    tk: TTypeKind;
    LabelFixupCount: Integer;
begin
  { Clear only this body's labels ([0, IRLabelCount) — see IREmitMachineCode). }
  for i := 0 to IRLabelCount - 1 do
    LabelPositions[i] := -1;
  LabelFixupCount := 0;

  { Nil-init hidden owning locals synthesised for materialised managed-string
    arguments. They are created during this body's IR lowering, after the
    parser's prologue zero-init pass, so they would otherwise hold stale stack
    bytes; an early-exit / epilogue cleanup would then DecRef garbage and
    segfault. Main-program temps are skGlobal (BSS, already zeroed); only
    skLocal needs it. Mirrors the x86-64 path in IREmitMachineCode. }
  if CurProc >= 0 then
    for i := Procs[CurProc].ScopeBase to SymCount - 1 do
      if SymIsHiddenArgTemp[i] and (Syms[i].Kind = skLocal) then
      begin
        if (Syms[i].TypeKind = tyRecord) and not Syms[i].IsArray and
           (RecSize(Syms[i].RecName) > TARGET_PTR_SIZE) then
        begin
          { Managed-record temp: zero the full record (PXXMemZero) so every
            managed field starts nil, not just the first pointer-sized slot. }
          EmitLoadImmArm32(0, Syms[i].Offset);
          EmitI32($E08B0000);    { add r0, fp, r0 (dest) }
          EmitLoadImmArm32(1, RecSize(Syms[i].RecName));   { r1 = count }
          procIdx := FindProc('PXXMemZero');
          if procIdx < 0 then Error('compiler error: PXXMemZero not found');
          EmitCallProc(procIdx);
        end
        else
        begin
          EmitI32($E3A00000);    { mov r0, #0 }
          EmitStoreVarArm32(i);  { str r0, [fp+off] }
        end;
      end;

  for i := 0 to IRCount - 1 do
  begin
    DbgRecordRow(i);   { DWARF -g line table }
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
            EmitAsmArm32(['b %', LabelPositions[lblId] - CodeLen])
          else
          begin
            if LabelFixupCount >= MAX_IR then Error('label fixup overflow');
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitAsmArm32('b 8');
          end;
        end;

      IR_JUMP_IF_FALSE:
        begin
          lblId := IRA[i];
          IREmitNodeArm32(IRB[i]); { condition -> r0 (r1:r0 if 64-bit) }
          { A 64-bit condition is r1:r0, so `cmp r0, #0` ignores the HIGH half and a
            nonzero value whose low word is zero tested as FALSE
            (bug-32bit-truthiness-high-half). `orrs` ORs both halves and sets the
            flags, so Z is set iff the whole 64-bit value is zero. }
          if Is64BitArm32(IntToTypeKind(IRTk[IRB[i]])) then
            EmitI32($E1900001)   { orrs r0, r0, r1 — raw: the text emitter has no `orrs` }
          else
            EmitAsmArm32('cmp r0, #0');
          if LabelPositions[lblId] <> -1 then
            EmitAsmArm32(['beq %', LabelPositions[lblId] - CodeLen])
          else
          begin
            if LabelFixupCount >= MAX_IR then Error('label fixup overflow');
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitAsmArm32('beq 8');
          end;
        end;

      IR_CALL:
        begin
          if IRIVal[i] = 1 then
            IREmitNodeArm32(i);
        end;

      IR_CALL_IND:
        begin
          if IRStmtRoot[i] then
            IREmitNodeArm32(i);
        end;

      IR_VIRTUAL_CALL:
        begin
          if IRStmtRoot[i] then
            IREmitNodeArm32(i);
        end;

      IR_EXC_ENTER:
        begin
          lblId := IRA[i];
          EmitI32($E24DD030);                                         { sub sp, sp, #48 }
          EmitI32($E59F1000);                                         { ldr r1, [pc] }
          EmitI32($EA000000);                                         { b .+8 }
          EmitGlobRef(BSS_EXC_TOP);
          EmitI32($E5912000);                                         { ldr r2, [r1] }
          EmitI32($E58D2000);                                         { str r2, [sp] }
          EmitI32($E1A0200D);                                         { mov r2, sp }
          EmitI32($E5812000);                                         { str r2, [r1] }
          EmitI32($E28D0008);                                         { add r0, sp, #8 }
          EmitI32($EB000000 or ((((ExcSetJmpAddr - CodeLen) div 4) - 2) and $00ffffff)); { bl ExcSetJmpAddr }
          EmitI32($E3500000);                                         { cmp r0, #0 }
          if LabelPositions[lblId] <> -1 then
            EmitI32($1A000000 or ((((LabelPositions[lblId] - CodeLen) div 4) - 2) and $00ffffff)) { bne label }
          else
          begin
            if LabelFixupCount >= MAX_IR then Error('label fixup overflow');
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitI32($1A000000);
          end;
        end;

      IR_EXC_LEAVE:
        begin
          IREmitLeaveExceptionFramesArm32(IRA[i]);
        end;

      IR_RAISE:
        begin
          if IRA[i] <> -1 then
          begin
            IREmitNodeArm32(IRA[i]);                                  { result in r0 }
            EmitI32($E59F1000);                                       { ldr r1, [pc] }
            EmitI32($EA000000);                                       { b .+8 }
            EmitGlobRef(BSS_EXC_OBJ);
            EmitI32($E5810000);                                       { str r0, [r1] }
            classIdx := Integer(IRIVal[i]);
            EmitLoadImmArm32(0, classIdx);                            { r0 = classIdx }
            EmitI32($E59F1000);                                       { ldr r1, [pc] }
            EmitI32($EA000000);                                       { b .+8 }
            EmitGlobRef(BSS_EXC_CLS);
            EmitI32($E5810000);                                       { str r0, [r1] }
          end;
          EmitI32($EB000000 or ((((ExcRaiseAddr - CodeLen) div 4) - 2) and $00ffffff)); { bl ExcRaiseAddr }
        end;

      IR_EXC_STORE:
        begin
          si := IRA[i];
          tk := Syms[si].TypeKind;
          sz := TypeSize(tk);
          EmitI32($E59F1000);                                         { ldr r1, [pc] }
          EmitI32($EA000000);                                         { b .+8 }
          EmitGlobRef(IRExcStoreSlot(i));
          EmitI32($E5910000);                                         { ldr r0, [r1] }
          EmitStoreVarArm32(si);
        end;

      IR_EXC_MATCH:
        begin
          lblId := IRA[i];
          EmitI32($E59F1000);                                         { ldr r1, [pc] }
          EmitI32($EA000000);                                         { b .+8 }
          EmitGlobRef(BSS_EXC_CLS);
          EmitI32($E5910000);                                         { ldr r0, [r1] }
          EmitLoadImmArm32(1, Integer(IRIVal[i]));                    { r1 = expected }
          EmitI32($E1500001);                                         { cmp r0, r1 }
          if LabelPositions[lblId] <> -1 then
            EmitI32($1A000000 or ((((LabelPositions[lblId] - CodeLen) div 4) - 2) and $00ffffff)) { bne label }
          else
          begin
            if LabelFixupCount >= MAX_IR then Error('label fixup overflow');
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitI32($1A000000);
          end;
        end;

      IR_EXC_MATCH_HIT:
        begin
          lblId := IRA[i];
          EmitI32($E59F1000);                                         { ldr r1, [pc] }
          EmitI32($EA000000);                                         { b .+8 }
          EmitGlobRef(BSS_EXC_CLS);
          EmitI32($E5910000);                                         { ldr r0, [r1] }
          EmitLoadImmArm32(1, Integer(IRIVal[i]));                    { r1 = expected }
          EmitI32($E1500001);                                         { cmp r0, r1 }
          if LabelPositions[lblId] <> -1 then
            EmitI32($0A000000 or ((((LabelPositions[lblId] - CodeLen) div 4) - 2) and $00ffffff)) { beq label }
          else
          begin
            if LabelFixupCount >= MAX_IR then Error('label fixup overflow');
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitI32($0A000000);
          end;
        end;

      IR_EXC_CLEAR:
        begin
          EmitI32($E3A00000);                                         { mov r0, #0 }
          EmitI32($E59F1000);                                         { ldr r1, [pc] }
          EmitI32($EA000000);                                         { b .+8 }
          EmitGlobRef(BSS_EXC_OBJ);
          EmitI32($E5810000);                                         { str r0, [r1] }
          EmitI32($E59F1000);                                         { ldr r1, [pc] }
          EmitI32($EA000000);                                         { b .+8 }
          EmitGlobRef(BSS_EXC_CLS);
          EmitI32($E5810000);                                         { str r0, [r1] }
          EmitI32($E59F1000);                                         { ldr r1, [pc] }
          EmitI32($EA000000);                                         { b .+8 }
          EmitGlobRef(BSS_EXC_ADDR);
          EmitI32($E5810000);                                         { str r0, [r1] }
        end;

      IR_STORE_SYM, IR_WRITE, IR_WRITELN:
        IREmitNodeArm32(i);

      IR_IO_LOCK:
        EmitI32($EB000000 or ((((IOLockAddr - CodeLen) div 4) - 2) and $00FFFFFF));   { bl io-lock }

      IR_IO_UNLOCK:
        EmitI32($EB000000 or ((((IOUnlockAddr - CodeLen) div 4) - 2) and $00FFFFFF)); { bl io-unlock }

      IR_NOP, IR_CONST_STR, IR_CONST_INT, IR_BLOCK,
      IR_LOAD_SYM, IR_LOAD_MEM, IR_BINOP, IR_NEG, IR_NOT, IR_ARG, IR_LEA, IR_SYSCALL,
      IR_SET_LIT, IR_SET_BINOP, IR_SET_CMP, IR_CONST_DATA,
      IR_SLOTADDR, IR_DYNUNIQUE, IR_FIELD, IR_INDEX,
      IR_ATOMIC, IR_CLONE: ;
      { IR_ATOMIC / IR_CLONE are value nodes consumed by their parent store, like
        IR_SYSCALL — emitting them at statement level too ran the rmw/spawn twice. }
      { IR_LOAD_MEM: pure value node — must not emit at statement level, else its
        address operand re-evaluates (`*f()` calls f twice). See aarch64 note. }

      else
        IREmitNodeArm32(i);
    end;
  end;

  for f := 0 to LabelFixupCount - 1 do
  begin
    lblId := LabelFixupTarget[f];
    pos := LabelFixupPos[f];
    targetOffset := LabelPositions[lblId];
    if targetOffset = -1 then Error('Unresolved forward jump in ARM32 IR codegen');
    if Code[pos+3] = $EA then
      Patch32(pos, $EA000000 or ((((targetOffset - pos) div 4) - 2) and $00ffffff))
    else if Code[pos+3] = $0A then
      Patch32(pos, $0A000000 or ((((targetOffset - pos) div 4) - 2) and $00ffffff))
    else if Code[pos+3] = $1A then
      Patch32(pos, $1A000000 or ((((targetOffset - pos) div 4) - 2) and $00ffffff))
    else
      Error('target arm32: invalid instruction at label fixup');
  end;
end;
