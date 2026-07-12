{ SPDX-License-Identifier: MPL-2.0 }
{ ===== IR -> AArch64 machine code (cross target, minimal and growing) =====

  AArch64 (ARM64) target backend. Operates on fixed-width 32-bit instructions.
  Registers used: x0 for expression results, x1..x7 for arguments/temporaries. }

procedure IREmitNodeAarch64(node: Integer); forward;

procedure EmitLoadArgvPtrA64;
{ On entry x0 = argv index. Returns x0 = argv[index] C-string pointer. }
begin
  EmitI32($D37DF000);                         { lsl x0, x0, #3 }
  EmitI32($18000041);                         { ldr w1, [pc+8] }
  EmitI32($14000002);                         { b [pc+8] }
  EmitGlobRef(BSS_INITIAL_RSP);
  EmitI32($F9400021);                         { ldr x1, [x1] = initial sp }
  EmitI32($91002021);                         { add x1, x1, #8 (argv base) }
  EmitI32($8B000020);                         { add x0, x1, x0 }
  EmitI32($F9400000);                         { ldr x0, [x0] }
end;

procedure EmitArgvToAnsiStringA64;
{ On entry x0 = argv index. Returns x0 = managed string handle. }
var loopStart, donePos, jmpPos, procIdx: Integer;
begin
  EmitLoadArgvPtrA64;                         { x0 = src }
  EmitI32($AA0003E1);                         { mov x1, x0 (src) }
  EmitI32($AA0003E3);                         { mov x3, x0 (scan) }
  EmitLoadImmA64(2, 0);                       { x2 = len }
  loopStart := CodeLen;
  EmitI32($39400064);                         { ldrb w4, [x3] }
  donePos := CodeLen; EmitI32($34000004);     { cbz w4, done }
  EmitI32($91000442);                         { add x2, x2, #1 }
  EmitI32($91000463);                         { add x3, x3, #1 }
  jmpPos := CodeLen; EmitI32($14000000);      { b loop }
  Patch32(donePos, $34000004 or (((CodeLen - donePos) div 4) and $7FFFF) shl 5);
  Patch32(jmpPos, $14000000 or (((loopStart - jmpPos) div 4) and $03FFFFFF));
  EmitI32($AA0203E0);                         { mov x0, x2 (len) }
  procIdx := FindProc('PXXStrFromLit');
  if procIdx < 0 then Error('compiler error: PXXStrFromLit not found');
  EmitCallProc(procIdx);                           { x0 = managed handle }
end;

procedure EmitLoadDataRefA64(rd, dataOff: Integer);
{ Load a data address (or descriptor sentinel) into x[rd]. EmitDataRef emits an
  8-byte slot on this 64-bit target, so use the 64-bit literal load and branch
  past the full 8 bytes (mirrors EmitwriteSyscallA64). }
begin
  EmitI32($58000040 or rd);  { ldr x[rd], [pc+8] }
  EmitI32($14000003);        { b [pc+12] (skip 8-byte literal) }
  EmitDataRef(dataOff);
end;

procedure EmitLoadGlobAddrA64(rd: Integer; offset: Integer);
begin
  EmitI32($18000040 or rd);  { ldr w[rd], [pc+8] }
  EmitI32($14000002);        { b [pc+8] }
  EmitGlobRef(offset);
end;

procedure IREmitLeaveExceptionFramesAarch64(count: Integer);
var i: Integer;
begin
  for i := 1 to count do
  begin
    EmitI32($18000041);                                         { ldr w1, [pc+8] }
    EmitI32($14000002);                                         { b [pc+8] }
    EmitGlobRef(BSS_EXC_TOP);
    EmitI32($F94003E2);                                         { ldr x2, [sp] }
    EmitI32($F9000022);                                         { str x2, [x1] }
    EmitI32($910203FF);                                         { add sp, sp, #128 }
  end;
end;

procedure EmitHeapAllocLockedA64;
{ x0 = requested payload bytes. Returns payload pointer in x0. Delegates to the
  Pascal PXXAlloc(size, align=8). Threadsafe locking is x86-64-only. }
var procIdx: Integer;
begin
  EmitLoadImmA64(1, 8);              { mov x1, #8 (align) }
  procIdx := FindProc('PXXAlloc');
  if procIdx < 0 then Error('compiler error: Alloc helper not found in builtin unit');
  EmitCallProc(procIdx);                 { x0 = pointer }
end;

procedure EmitHeapFreeLockedA64;
{ x0 = payload pointer. Delegates to PXXFree(p). nil ignored inside. }
var procIdx: Integer;
begin
  procIdx := FindProc('PXXFree');
  if procIdx < 0 then Error('compiler error: Free helper not found in builtin unit');
  EmitCallProc(procIdx);
end;

procedure EmitStrIncRefA64;
{ x0 = managed-string handle. Retain; x0 preserved. }
var procIdx: Integer;
begin
  EmitI32($F81F0FE0);             { str x0, [sp, #-16]! (save handle; x0 still arg) }
  procIdx := FindProc('PXXStrIncRef');
  if procIdx < 0 then Error('compiler error: PXXStrIncRef not found');
  EmitCallProc(procIdx);
  EmitI32($F84107E0);             { ldr x0, [sp], #16 (restore handle) }
end;

procedure EmitStrDecRefA64;
{ x0 = managed-string handle. x0 clobbered. }
var procIdx: Integer;
begin
  procIdx := FindProc('PXXStrDecRef');
  if procIdx < 0 then Error('compiler error: PXXStrDecRef not found');
  EmitCallProc(procIdx);
end;

procedure EmitIoLockStubsA64;
{ --threadsafe statement-atomic console I/O, the aarch64 port of EmitIoLockStubs.
  Reentrant owner-tid spinlock: BSS_IO_OWNER = owning tid (0 = free), BSS_IO_DEPTH
  = the owner's nesting depth, so a write argument that itself writes cannot
  self-deadlock. gettid (svc 178) per I/O statement; the futex-free spinlock uses
  LL/SC (ldaxr/stlxr) for acquire/release ordering. Fronted by a branch so it is
  reached only via bl. x9=&owner, x13=&depth held across the gettid syscall (the
  aarch64 syscall ABI preserves x1-x30). Hex verified against aarch64-linux-gnu-as. }
var jmpOver: Integer;
begin
  EmitI32($14000000); jmpOver := CodeLen - 4;   { b .end (patched below) }
  IOLockAddr := CodeLen;
  EmitLoadGlobAddrA64(9, BSS_IO_OWNER);
  EmitLoadGlobAddrA64(13, BSS_IO_DEPTH);
  EmitI32($D2801648);   { mov  x8, #178          gettid }
  EmitI32($D4000001);   { svc  #0                x0 = tid }
  EmitI32($F940012A);   { ldr  x10, [x9]         current owner }
  EmitI32($EB00015F);   { cmp  x10, x0 }
  EmitI32($540000A0);   { b.eq bump  (+5, already ours) }
  EmitI32($C85FFD2B);   { ldaxr x11, [x9]        (spin) }
  EmitI32($B5FFFFEB);   { cbnz x11, spin  (-1, owned by other) }
  EmitI32($C80CFD20);   { stlxr w12, x0, [x9]    take with our tid }
  EmitI32($35FFFFAC);   { cbnz w12, spin  (-3, sc failed) }
  EmitI32($F94001AA);   { ldr  x10, [x13]        (bump) }
  EmitI32($9100054A);   { add  x10, x10, #1 }
  EmitI32($F90001AA);   { str  x10, [x13] }
  EmitI32($D65F03C0);   { ret }

  IOUnlockAddr := CodeLen;
  EmitLoadGlobAddrA64(9, BSS_IO_OWNER);
  EmitLoadGlobAddrA64(13, BSS_IO_DEPTH);
  EmitI32($F94001AA);   { ldr  x10, [x13] }
  EmitI32($D100054A);   { sub  x10, x10, #1 }
  EmitI32($F90001AA);   { str  x10, [x13] }
  EmitI32($B500004A);   { cbnz x10, keep  (+2, still nested) }
  EmitI32($F900013F);   { str  xzr, [x9]         release: owner := 0 }
  EmitI32($D65F03C0);   { ret  (keep) }

  Patch32(jmpOver, $14000000 or (((CodeLen - jmpOver) div 4) and $03FFFFFF));
end;

procedure EmitAnsiStringFromNodeA64(valNode: Integer);
{ Build a managed AnsiString handle in x0 from a literal, char, inline string,
  or existing handle (retained unless a fresh concat/function result). }
var sVal: AnsiString; si, procIdx: Integer; tk: TTypeKind;
begin
  if IRKind[valNode] = IR_CONST_STR then
  begin
    sVal := GetTokenStrFromRaw(IRA[valNode], IRB[valNode]);
    si := InternStr(sVal);
    EmitLoadImmA64(0, Strs[si].Len);
    EmitLoadDataRefA64(1, Strs[si].Offset + 8);
    procIdx := FindProc('PXXStrFromLit');
    if procIdx < 0 then Error('compiler error: PXXStrFromLit not found');
    EmitCallProc(procIdx);
    Exit;
  end;
  tk := IntToTypeKind(IRTk[valNode]);
  if tk = tyChar then
  begin
    IREmitNodeAarch64(valNode);   { x0 = char code }
    EmitI32($F81F0FE0);           { str x0, [sp, #-16]! (byte at [sp]) }
    EmitLoadImmA64(0, 1);         { x0 = 1 }
    EmitI32($910003E1);           { add x1, sp, #0 }
    procIdx := FindProc('PXXStrFromLit');
    if procIdx < 0 then Error('compiler error: PXXStrFromLit not found');
    EmitCallProc(procIdx);
    EmitI32($910043FF);           { add sp, sp, #16 }
  end
  else if tk = tyString then
  begin
    IREmitNodeAarch64(valNode);   { x0 = inline string buffer }
    EmitI32($AA0003E2);           { mov x2, x0 }
    EmitI32($F9400040);           { ldr x0, [x2] (len) }
    EmitI32($91002041);           { add x1, x2, #8 (src) }
    procIdx := FindProc('PXXStrFromLit');
    if procIdx < 0 then Error('compiler error: PXXStrFromLit not found');
    EmitCallProc(procIdx);
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

procedure EmitWriteCStrA64;
{ x0 = PChar (NUL-terminated) -> strlen + write to stdout. Mirrors x86-64
  EmitWriteCStr so write(PChar) prints the string, not the pointer value. }
begin
  EmitI32($AA0003E1);   { mov x1, x0 (buf) }
  EmitI32($AA1F03E2);   { mov x2, xzr (len) }
  { scan: }
  EmitI32($39400003);   { ldrb w3, [x0] }
  EmitI32($34000083);   { cbz w3, done (+4 instr) }
  EmitI32($91000400);   { add x0, x0, #1 }
  EmitI32($91000442);   { add x2, x2, #1 }
  EmitI32($17FFFFFC);   { b scan (-4 instr) }
  { done: }
  EmitI32($D2800020);   { mov x0, #1 (stdout) }
  EmitI32($D2800808);   { mov x8, #64 (sys_write) }
  EmitI32($D4000001);   { svc #0 }
end;

procedure EmitWriteFloatNatA64;
var jnsOff, jbCarry, i, nJz: Integer;
    endJz: array[0..15] of Integer;
begin
  EmitI32($F81F0FF3);                                           { str x19, [sp, #-16]! }
  EmitI32($F81F0FF4);                                           { str x20, [sp, #-16]! }
  EmitI32($F81F0FF5);                                           { str x21, [sp, #-16]! }

  EmitI32($937FFC01);                                           { asr x1, x0, #63 }
  EmitI32($F100003F);                                           { cmp x1, #0 }
  jnsOff := CodeLen;
  EmitI32($5400000A);                                           { b.ge .pos }
  
  EmitLoadImmA64(1, $7FFFFFFFFFFFFFFF);
  EmitI32($8A010000);                                           { and x0, x0, x1 }
  EmitI32($F81F0FE0);                                           { str x0, [sp, #-16]! }
  EmitLoadImmA64(0, Ord('-'));
  EmitwriteCharA64;
  EmitI32($F84107E0);                                           { ldr x0, [sp], #16 }
  
  Patch32(jnsOff, $5400000A or (((CodeLen - jnsOff) div 4) and $7FFFF) shl 5);

  EmitI32($9E670000);                                           { fmov d0, x0 }
  EmitI32($9E780001);                                           { fcvtzs x1, d0 }
  EmitI32($9E620022);                                           { scvtf d2, x1 }
  EmitI32($1E623800);                                           { fsub d0, d0, d2 }
  
  EmitLoadImmA64(3, 1000000000000000);                          { scale = 10^15 }
  EmitI32($9E620063);                                           { scvtf d3, x3 }
  EmitI32($1E630800);                                           { fmul d0, d0, d3 }
  EmitI32($9E600002);                                           { fcvtns x2, d0 }
  
  EmitI32($EB03005F);                                           { cmp x2, x3 }
  jbCarry := CodeLen;
  EmitI32($5400000B);                                           { b.lt .nocarry }
  
  EmitI32($CB030042);                                           { sub x2, x2, x3 }
  EmitI32($91000421);                                           { add x1, x1, #1 }
  
  Patch32(jbCarry, $5400000B or (((CodeLen - jbCarry) div 4) and $7FFFF) shl 5);

  EmitI32($AA0103F3);                                           { mov x19, x1 }
  EmitI32($AA0203F4);                                           { mov x20, x2 }

  EmitI32($AA1303E0);                                           { mov x0, x19 }
  EmitwriteUIntA64;
  
  EmitLoadImmA64(0, Ord('.'));
  EmitwriteCharA64;

  EmitLoadImmA64(21, 100000000000000);                          { divisor = 10^14 }
  nJz := 0;
  for i := 0 to 14 do
  begin
    EmitI32($AA1403E0);                                         { mov x0, x20 }
    EmitI32($AA1503E1);                                         { mov x1, x21 }
    EmitI32($9AC10C02);                                         { sdiv x2, x0, x1 }
    EmitI32($9B018054);                                         { msub x20, x2, x1, x0 }
    EmitI32($9100C040);                                         { add x0, x2, #48 }
    EmitwriteCharA64;
    
    if i < 14 then
    begin
      EmitLoadImmA64(1, 10);
      EmitI32($9AC10EB5);                                       { sdiv x21, x21, x1 }
      
      EmitI32($B4000014);                                       { cbz x20, .end }
      endJz[nJz] := CodeLen - 4;
      Inc(nJz);
    end;
  end;

  for i := 0 to nJz - 1 do
    Patch32(endJz[i], $B4000014 or ((((CodeLen - endJz[i]) div 4) and $7FFFF) shl 5));

  EmitI32($F84107F5);                                           { ldr x21, [sp], #16 }
  EmitI32($F84107F4);                                           { ldr x20, [sp], #16 }
  EmitI32($F84107F3);                                           { ldr x19, [sp], #16 }
end;

procedure EmitWriteFloatFixedA64(decimals: Integer);
var jnsOff, jbCarry, loopStart, i: Integer;
    pow10, divisor: Int64;
begin
  pow10 := 1;
  for i := 1 to decimals do pow10 := pow10 * 10;

  EmitI32($F81F0FF3);                                           { str x19, [sp, #-16]! }
  EmitI32($F81F0FF4);                                           { str x20, [sp, #-16]! }

  EmitI32($937FFC01);                                           { asr x1, x0, #63 }
  EmitI32($F100003F);                                           { cmp x1, #0 }
  jnsOff := CodeLen;
  EmitI32($5400000A);                                           { b.ge .pos }
  
  EmitLoadImmA64(1, $7FFFFFFFFFFFFFFF);
  EmitI32($8A010000);                                           { and x0, x0, x1 }
  EmitI32($F81F0FE0);                                           { str x0, [sp, #-16]! }
  EmitLoadImmA64(0, Ord('-'));
  EmitwriteCharA64;
  EmitI32($F84107E0);                                           { ldr x0, [sp], #16 }
  
  Patch32(jnsOff, $5400000A or (((CodeLen - jnsOff) div 4) and $7FFFF) shl 5);

  EmitI32($9E670000);                                           { fmov d0, x0 }
  EmitLoadImmA64(2, pow10);
  EmitI32($9E620042);                                           { scvtf d2, x2 }
  EmitI32($1E620800);                                           { fmul d0, d0, d2 }
  EmitI32($9E600000);                                           { fcvtns x0, d0 }

  if decimals <= 0 then
  begin
    EmitwriteUIntA64;
    EmitI32($F84107F4);                                         { ldr x20, [sp], #16 }
    EmitI32($F84107F3);                                         { ldr x19, [sp], #16 }
    Exit;
  end;

  EmitLoadImmA64(2, pow10);
  EmitI32($9AC20C01);                                           { sdiv x1, x0, x2 }
  EmitI32($9B028034);                                           { msub x20, x1, x2, x0 }
  EmitI32($AA0103F3);                                           { mov x19, x1 }

  EmitI32($AA1303E0);                                           { mov x0, x19 }
  EmitwriteUIntA64;

  EmitLoadImmA64(0, Ord('.'));
  EmitwriteCharA64;

  for i := decimals - 1 downto 0 do
  begin
    divisor := 1;
    for loopStart := 1 to i do divisor := divisor * 10;
    EmitLoadImmA64(1, divisor);
    EmitI32($AA1403E0);                                         { mov x0, x20 }
    EmitI32($9AC10C02);                                         { sdiv x2, x0, x1 }
    EmitI32($9B018054);                                         { msub x20, x2, x1, x0 }
    EmitI32($9100C040);                                         { add x0, x2, #48 }
    EmitwriteCharA64;
  end;

  EmitI32($F84107F4);                                           { ldr x20, [sp], #16 }
  EmitI32($F84107F3);                                           { ldr x19, [sp], #16 }
end;

procedure EmitWriteFloatSciA64;
var jnsOff, jnzNz, jmpDone, laTop, laJb, leTop, leJge, jnsOff2, jmpSignDone, jmpExpSignDone: Integer;
    bdTop, clampB, roundB, ovB: Integer;
    i: Integer;
begin
  EmitI32($F81F0FF3);                                           { str x19, [sp, #-16]! }
  EmitI32($F81F0FF4);                                           { str x20, [sp, #-16]! }
  EmitI32($F81F0FF5);                                           { str x21, [sp, #-16]! }
 
  EmitI32($937FFC01);                                           { asr x1, x0, #63 }
  EmitI32($F100003F);                                           { cmp x1, #0 }
  jnsOff := CodeLen;
  EmitI32($5400000A);                                           { b.ge .pos }
  
  EmitLoadImmA64(1, $7FFFFFFFFFFFFFFF);
  EmitI32($8A010000);                                           { and x0, x0, x1 }
  EmitI32($F81F0FE0);                                           { str x0, [sp, #-16]! }
  EmitLoadImmA64(0, Ord('-'));
  EmitwriteCharA64;
  EmitI32($F84107E0);                                           { ldr x0, [sp], #16 }
  jmpSignDone := CodeLen;
  EmitI32($14000000);                                           { b .sign_done (patched) }
  
  Patch32(jnsOff, $5400000A or (((CodeLen - jnsOff) div 4) and $7FFFF) shl 5);
  EmitI32($F81F0FE0);                                           { str x0, [sp, #-16]! }
  EmitLoadImmA64(0, Ord(' '));
  EmitwriteCharA64;
  EmitI32($F84107E0);                                           { ldr x0, [sp], #16 }
  { .sign_done: }
  Patch32(jmpSignDone, $14000000 or (((CodeLen - jmpSignDone) div 4) and $03FFFFFF));

  EmitI32($F100001F);                                           { cmp x0, #0 }
  jnzNz := CodeLen;
  EmitI32($54000001);                                           { b.ne .nz }
  
  EmitLoadImmA64(0, Ord('0')); EmitwriteCharA64;
  EmitLoadImmA64(0, Ord('.')); EmitwriteCharA64;
  for i := 1 to 16 do
  begin
    EmitLoadImmA64(0, Ord('0')); EmitwriteCharA64;
  end;
  EmitLoadImmA64(0, Ord('E')); EmitwriteCharA64;
  EmitLoadImmA64(0, Ord('+')); EmitwriteCharA64;
  for i := 1 to 3 do
  begin
    EmitLoadImmA64(0, Ord('0')); EmitwriteCharA64;
  end;
  jmpDone := CodeLen;
  EmitI32($14000000);                                           { b .done }

  Patch32(jnzNz, $54000001 or (((CodeLen - jnzNz) div 4) and $7FFFF) shl 5);

  EmitI32($9E670000);                                           { fmov d0, x0 }
  EmitLoadImmA64(1, 10);
  EmitI32($9E620021);                                           { scvtf d1, x1 }
  EmitLoadImmA64(2, 1);
  EmitI32($9E620042);                                           { scvtf d2, x2 }
  
  EmitI32($D2800013);                                           { movz x19, #0 }

  laTop := CodeLen;
  EmitI32($1E612000);                                           { fcmp d0, d1 }
  laJb := CodeLen;
  EmitI32($5400000B);                                           { b.lt .ea }
  EmitI32($1E611800);                                           { fdiv d0, d0, d1 }
  EmitI32($91000673);                                           { add x19, x19, #1 }
  EmitI32($14000000 or (((laTop - CodeLen) div 4) and $03FFFFFF));

  Patch32(laJb, $5400000B or (((CodeLen - laJb) div 4) and $7FFFF) shl 5);
  
  leTop := CodeLen;
  EmitI32($1E622000);                                           { fcmp d0, d2 }
  leJge := CodeLen;
  EmitI32($5400000A);                                           { b.ge .val_done }
  EmitI32($1E610800);                                           { fmul d0, d0, d1 }
  EmitI32($D1000673);                                           { sub x19, x19, #1 }
  EmitI32($14000000 or (((leTop - CodeLen) div 4) and $03FFFFFF));

  Patch32(leJge, $5400000A or (((CodeLen - leJge) div 4) and $7FFFF) shl 5);

  { Build the 17-digit mantissa integer in x20, MSD-first: each step truncates
    a value in [0,10) (keeps ~17 accurate digits, unlike one fmul-by-1e16 which
    overflows the 53-bit mantissa). x21 = remaining digit count. d1 holds 10.0. }
  EmitI32($D2800014);                                           { movz x20, #0 }
  EmitLoadImmA64(21, 17);
  bdTop := CodeLen;
  EmitI32($9E780000);                                           { fcvtzs x0, d0 }
  EmitI32($F100241F);                                           { cmp x0, #9 }
  clampB := CodeLen;
  EmitI32($5400000D);                                           { b.le .ok }
  EmitI32($D2800120);                                           { movz x0, #9 }
  Patch32(clampB, $5400000D or (((CodeLen - clampB) div 4) and $7FFFF) shl 5);
  EmitLoadImmA64(1, 10);
  EmitI32($9B010294);                                           { madd x20, x20, x1, x0 }
  EmitI32($9E620002);                                           { scvtf d2, x0 }
  EmitI32($1E623800);                                           { fsub d0, d0, d2 }
  EmitI32($1E610800);                                           { fmul d0, d0, d1 }
  EmitI32($D10006B5);                                           { sub x21, x21, #1 }
  EmitI32($F10002BF);                                           { cmp x21, #0 }
  EmitI32($54000001 or ((((bdTop - CodeLen) div 4) and $7FFFF) shl 5)); { b.ne bdTop }

  { guard digit: round half-up }
  EmitI32($9E780000);                                           { fcvtzs x0, d0 }
  EmitI32($F100141F);                                           { cmp x0, #5 }
  roundB := CodeLen;
  EmitI32($5400000B);                                           { b.lt .noround }
  EmitI32($91000694);                                           { add x20, x20, #1 }
  Patch32(roundB, $5400000B or (((CodeLen - roundB) div 4) and $7FFFF) shl 5);

  { carry past the leading digit (9.99..->10.0): drop a digit, bump exponent }
  EmitLoadImmA64(1, 100000000000000000);                        { 10^17 }
  EmitI32($EB01029F);                                           { cmp x20, x1 }
  ovB := CodeLen;
  EmitI32($5400000B);                                           { b.lt .nov }
  EmitLoadImmA64(1, 10);
  EmitI32($9AC10C94);                                           { sdiv x20, x20, x1 }
  EmitI32($91000673);                                           { add x19, x19, #1 }
  Patch32(ovB, $5400000B or (((CodeLen - ovB) div 4) and $7FFFF) shl 5);

  { print 17 digits from x20 as d.<16 digits>; x21 = divisor 10^16 down to 1 }
  EmitLoadImmA64(21, 10000000000000000);                        { 10^16 }
  for i := 0 to 16 do
  begin
    EmitI32($AA1403E0);                                         { mov x0, x20 }
    EmitI32($AA1503E1);                                         { mov x1, x21 }
    EmitI32($9AC10C02);                                         { sdiv x2, x0, x1 }
    EmitI32($9B018054);                                         { msub x20, x2, x1, x0 }
    EmitI32($9100C040);                                         { add x0, x2, #48 }
    EmitwriteCharA64;
    if i = 0 then
    begin
      EmitLoadImmA64(0, Ord('.'));
      EmitwriteCharA64;
    end;
    if i < 16 then
    begin
      EmitLoadImmA64(1, 10);
      EmitI32($9AC10EB5);                                       { sdiv x21, x21, x1 }
    end;
  end;

  EmitLoadImmA64(0, Ord('E')); EmitwriteCharA64;

  EmitI32($F100027F);                                           { cmp x19, #0 }
  jnsOff2 := CodeLen;
  EmitI32($5400000A);                                           { b.ge .exppos }
  EmitLoadImmA64(0, Ord('-')); EmitwriteCharA64;
  EmitI32($CB1303F3);                                           { neg x19, x19 }
  jmpExpSignDone := CodeLen;
  EmitI32($14000000);                                           { b .exp_sign_done (patched) }

  Patch32(jnsOff2, $5400000A or (((CodeLen - jnsOff2) div 4) and $7FFFF) shl 5);
  EmitLoadImmA64(0, Ord('+')); EmitwriteCharA64;
  { .exp_sign_done: }
  Patch32(jmpExpSignDone, $14000000 or (((CodeLen - jmpExpSignDone) div 4) and $03FFFFFF));

  EmitLoadImmA64(1, 100);
  EmitI32($AA1303E0);                                           { mov x0, x19 }
  EmitI32($9AC10C02);                                           { sdiv x2, x0, x1 }
  EmitI32($9B018053);                                           { msub x19, x2, x1, x0 }
  EmitI32($9100C040);                                           { add x0, x2, #48 }
  EmitwriteCharA64;

  EmitLoadImmA64(1, 10);
  EmitI32($AA1303E0);                                           { mov x0, x19 }
  EmitI32($9AC10C02);                                           { sdiv x2, x0, x1 }
  EmitI32($9B018053);                                           { msub x19, x2, x1, x0 }
  EmitI32($9100C040);                                           { add x0, x2, #48 }
  EmitwriteCharA64;

  EmitI32($AA1303E0);                                           { mov x0, x19 }
  EmitI32($9100C000);                                           { add x0, x0, #48 }
  EmitwriteCharA64;

  { .done: }
  Patch32(jmpDone, $14000000 or (((CodeLen - jmpDone) div 4) and $03FFFFFF));

  EmitI32($F84107F5);                                           { ldr x21, [sp], #16 }
  EmitI32($F84107F4);                                           { ldr x20, [sp], #16 }
  EmitI32($F84107F3);                                           { ldr x19, [sp], #16 }
end;

procedure EmitVariantClearA64;
var pDone: Integer;
begin
  EmitI32($F81F0FE0);                                           { str x0, [sp, #-16]! }
  EmitI32($F9400000);                                           { ldr x0, [x0] (tag) }
  EmitI32($F100181F);                                           { cmp x0, #6 (VT_STRING) }
  pDone := CodeLen;
  EmitI32($54000001);                                           { b.ne .done }
  EmitI32($F94003E0);                                           { ldr x0, [sp] (addr) }
  EmitI32($F9400400);                                           { ldr x0, [x0, #8] }
  EmitStrDecRefA64;
  { .done }
  Patch32(pDone, $54000001 or (((CodeLen - pDone) div 4) and $7FFFF) shl 5);
  EmitI32($F94003E0);                                           { ldr x0, [sp] }
  EmitI32($D2800001);                                           { movz x1, #0 }
  EmitI32($F9000001);                                           { str x1, [x0] }
  EmitI32($F9000401);                                           { str x1, [x0, #8] }
  EmitI32($F84107E0);                                           { ldr x0, [sp], #16 }
end;

procedure EmitVariantRetainA64;
var pDone: Integer;
begin
  EmitI32($F81F0FE0);                                           { str x0, [sp, #-16]! }
  EmitI32($F9400000);                                           { ldr x0, [x0] (tag) }
  EmitI32($F100181F);                                           { cmp x0, #6 (VT_STRING) }
  pDone := CodeLen;
  EmitI32($54000001);                                           { b.ne .done }
  EmitI32($F94003E0);                                           { ldr x0, [sp] }
  EmitI32($F9400400);                                           { ldr x0, [x0, #8] }
  EmitStrIncRefA64;
  { .done }
  Patch32(pDone, $54000001 or (((CodeLen - pDone) div 4) and $7FFFF) shl 5);
  EmitI32($F84107E0);                                           { ldr x0, [sp], #16 }
end;

procedure EmitLoadVarA64(idx: Integer);
var tk: TTypeKind; sz: Integer; sgn: Boolean;
begin
  tk := Syms[idx].TypeKind;
  sz := TypeSize(tk);
  sgn := TypeSigned(tk);

  if tk = tySingle then
  begin
    if Syms[idx].Kind = skGlobal then
    begin
      EmitI32($18000041);  { ldr w1, [pc+8] }
      EmitI32($14000002);  { b [pc+8] }
      EmitGlobRef(Syms[idx].Offset);
      EmitI32($B9400020);  { ldr w0, [x1] }
    end
    else
    begin
      EmitLoadImmA64(9, Syms[idx].Offset);
      EmitI32($8B0903A9);  { add x9, x29, x9 }
      if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then
      begin
        EmitI32($F9400121);  { ldr x1, [x9] }
        EmitI32($B9400020);  { ldr w0, [x1] }
      end
      else
        EmitI32($B9400120);  { ldr w0, [x9] }
    end;
    EmitI32($1E270000);    { fmov s0, w0 }
    EmitI32($1E22C000);    { fcvt d0, s0 }
    EmitI32($9E660000);    { fmov x0, d0 }
    Exit;
  end;

  if Syms[idx].Kind = skGlobal then
  begin
    EmitI32($18000041);  { ldr w1, [pc+8] }
    EmitI32($14000002);  { b [pc+8] }
    EmitGlobRef(Syms[idx].Offset);
    if sz = 1 then
    begin
      if sgn then EmitI32($39800020) else EmitI32($39400020);
    end
    else if sz = 2 then
    begin
      if sgn then EmitI32($79800020) else EmitI32($79400020);
    end
    else if sz = 4 then
    begin
      if sgn then EmitI32($B9800020) else EmitI32($B9400020);
    end
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
        if sgn then EmitI32($39800020) else EmitI32($39400020);
      end
      else if sz = 2 then
      begin
        if sgn then EmitI32($79800020) else EmitI32($79400020);
      end
      else if sz = 4 then
      begin
        if sgn then EmitI32($B9800020) else EmitI32($B9400020);
      end
      else
        EmitI32($F9400020);
    end
    else
    begin
      if sz = 1 then
      begin
        if sgn then EmitI32($39800120) else EmitI32($39400120);
      end
      else if sz = 2 then
      begin
        if sgn then EmitI32($79800120) else EmitI32($79400120);
      end
      else if sz = 4 then
      begin
        if sgn then EmitI32($B9800120) else EmitI32($B9400120);
      end
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
  { A dynamic array's slot holds a pointer-sized heap handle, not an element.
    TypeSize(elementType) (e.g. 4 for `array of Integer`) would truncate the
    64-bit handle to 32 bits — `b := a` then stores a bad pointer and segfaults.
    Force a full pointer-width store. }
  if Syms[idx].IsArray and (Syms[idx].ArrLen = -1) then sz := TARGET_PTR_SIZE;

  if tk = tySingle then
  begin
    EmitI32($9E670000);    { fmov d0, x0 }
    EmitI32($1E624000);    { fcvt s0, d0 }
    EmitI32($1E260000);    { fmov w0, s0 }
    if Syms[idx].Kind = skGlobal then
    begin
      EmitI32($18000041);  { ldr w1, [pc+8] }
      EmitI32($14000002);  { b [pc+8] }
      EmitGlobRef(Syms[idx].Offset);
      EmitI32($B9000020);  { str w0, [x1] }
    end
    else
    begin
      EmitLoadImmA64(9, Syms[idx].Offset);
      EmitI32($8B0903A9);  { add x9, x29, x9 }
      if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then
      begin
        EmitI32($F9400121);  { ldr x1, [x9] }
        EmitI32($B9000020);  { str w0, [x1] }
      end
      else
        EmitI32($B9000120);  { str w0, [x9] }
    end;
    Exit;
  end;

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

{ isUnsigned selects unsigned condition codes (lo/ls/hi/hs) for a magnitude
  compare of unsigned operands; without it `(size_t)x <= 0xFFFF...F` used the
  signed `le` and read the RHS as -1 (bug-aarch64-unsigned-compare, the lua
  luaM_limitN limit=-1 wall). eq/ne are sign-agnostic. }
procedure EmitSetccA64Ex(opTk: Integer; isUnsigned: Boolean);
begin
  if opTk = Ord(tkEq) then EmitAsmA64('cset x0, eq')
  else if opTk = Ord(tkNeq) then EmitAsmA64('cset x0, ne')
  else if opTk = Ord(tkLt) then begin if isUnsigned then EmitAsmA64('cset x0, lo') else EmitAsmA64('cset x0, lt') end
  else if opTk = Ord(tkLe) then begin if isUnsigned then EmitAsmA64('cset x0, ls') else EmitAsmA64('cset x0, le') end
  else if opTk = Ord(tkGt) then begin if isUnsigned then EmitAsmA64('cset x0, hi') else EmitAsmA64('cset x0, gt') end
  else if opTk = Ord(tkGe) then begin if isUnsigned then EmitAsmA64('cset x0, hs') else EmitAsmA64('cset x0, ge') end
  else Error('target aarch64: unsupported compare operator');
end;

procedure EmitSetccA64(opTk: Integer);
begin
  EmitSetccA64Ex(opTk, False);
end;

procedure EmitSetccA64Float(opTk: Integer);
{ Float compare after `fcmp`: unordered (NaN operand) sets N=0 Z=0 C=1 V=1.
  IEEE wants every ordered relation FALSE for NaN and <> TRUE. The signed
  integer conditions `lt` (N<>V) and `le` (Z or N<>V) both fire on unordered,
  so use the FP-safe `mi` (N==1) for < and `ls` (C==0 or Z==1) for <=. eq/ne
  (Z-based) and gt/ge (N==V, both 0 on unordered) are already correct. }
begin
  if opTk = Ord(tkEq) then EmitAsmA64('cset x0, eq')
  else if opTk = Ord(tkNeq) then EmitAsmA64('cset x0, ne')
  else if opTk = Ord(tkLt) then EmitAsmA64('cset x0, mi')
  else if opTk = Ord(tkLe) then EmitAsmA64('cset x0, ls')
  else if opTk = Ord(tkGt) then EmitAsmA64('cset x0, gt')
  else if opTk = Ord(tkGe) then EmitAsmA64('cset x0, ge')
  else Error('target aarch64: unsupported float compare operator');
end;

procedure IREmitNodeAarch64(node: Integer);
var
  valNode, si, left, right, op, procIdx, argNode, nArgs, i, sz, wid: Integer;
  classIdx, elemSize, lo, hi, decs, specialId, jnsOff, jmpDone, j, itemNode, p1, p2: Integer;
  sVal: AnsiString;
  tk, lhsTk, rhsTk: TTypeKind;
  sgn, isComp, savedLValueWrite: Boolean;
begin
  if node = -1 then Exit;
  case IRKind[node] of
    IR_NOP, IR_BLOCK: ;

    IR_ASM:
      begin
        { Inline asm block: replay the parse-time-captured text lines
          (AsmParseBodyTextA64, asmenc.inc) through the aarch64 text engine.
          Emitting here, at final code positions, makes label fixups and
          @glob relocations natively correct. Labels are block-scoped. }
        AsmA64BlockBegin;
        for i := IRA[node] to IRA[node] + IRB[node] - 1 do
          AsmA64ProcessInlineLine(i);
        AsmA64BlockResolve;
      end;

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
          if (IRKind[valNode] = IR_CALL) and (IRA[valNode] = -Ord(tkArgStr)) then
          begin
            argNode := IRB[valNode];
            IREmitNodeAarch64(IRA[argNode]);    { x0 = argv index }
            EmitArgvToAnsiStringA64;            { x0 = new handle }
          end
          else
            EmitAnsiStringFromNodeA64(valNode); { x0 = new handle (retained) }
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
        if (Syms[si].TypeKind = tyString) and not Syms[si].IsArray then
        begin
          { Frozen inline-string assignment (s := <string>): copy [len:8][chars]
            from the source into s's buffer. Mirrors the x86-64 path; without it
            the scalar store below dropped the source ADDRESS into s's slot,
            clobbering its length prefix. }
          valNode := IRB[node];
          IREmitNodeAarch64(valNode);              { x0 = source addr (or char ordinal) }
          EmitI32($F81F0FE0);                      { str x0,[sp,#-16]! (push src) }
          if Syms[si].Kind = skParam then
          begin
            EmitLoadImmA64(9, Syms[si].Offset);
            EmitI32($8B0903A9);                    { add x9, x29, x9 }
            EmitI32($F9400120);                    { ldr x0, [x9] (forwarded buffer ptr) }
          end
          else
            EmitLoadVarAddrA64(si);                { x0 = global/local buffer addr }
          EmitI32($AA0003E6);                      { mov x6, x0 (dst) }
          EmitI32($F84107E5);                      { ldr x5, [sp],#16 (src) }
          if IntToTypeKind(IRTk[valNode]) = tyChar then
          begin
            { x5 = char ordinal -> [len=1][char] }
            EmitLoadImmA64(9, 1);
            EmitI32($F90000C9);                    { str x9, [x6] (len=1) }
            EmitI32($390020C5);                    { strb w5, [x6,#8] }
          end
          else
          begin
            EmitI32($F94000A9);                    { ldr x9, [x5] (len prefix) }
            EmitI32($F90000C9);                    { str x9, [x6] }
            EmitI32($AA0903E4);                    { mov x4, x9 (count) }
            EmitI32($910020A5);                    { add x5, x5, #8 }
            EmitI32($910020C6);                    { add x6, x6, #8 }
            EmitA64CopyBytes(4, 5, 6);
          end;
          Exit;
        end;
        IREmitNodeAarch64(IRB[node]);
        if TypeIsFloat(Syms[IRA[node]].TypeKind) and
           not TypeIsFloat(IntToTypeKind(IRTk[IRB[node]])) then
        begin
          { int value into a float slot: convert (bits stay in x0) }
          EmitI32($9E620000);                     { scvtf d0, x0 }
          EmitI32($9E660000);                     { fmov x0, d0 }
        end
        else if CProgramMode and (not TypeIsFloat(Syms[IRA[node]].TypeKind)) and
                TypeIsFloat(IntToTypeKind(IRTk[IRB[node]])) then
        begin
          { C double->int: float RHS (bits in x0) into an integer slot truncates
            (fcvtzs). Mirrors the x86-64/i386 cvttsd2si. }
          EmitI32($9E670000);                     { fmov d0, x0 }
          EmitI32($9E780000);                     { fcvtzs x0, d0 }
        end;
        EmitStoreVarA64(IRA[node]);
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
            it -- mirrors the x86-64/arm32 IR_LEA read/write gate. Previously
            this always loaded the handle regardless of InLValueWrite, so
            SetLength on the array itself wrote through the CURRENT (often nil)
            handle value instead of the slot, silently no-opping (or, one level
            down inside a nested array, computing a bogus small-integer
            "address" from a nil base plus an index stride and segfaulting on
            any index > 0) -- bug-nested-dynarray-cross-segfault. For a by-ref
            (var/out) named-dynarray param, EmitLoadVarAddrA64 already yields
            &caller_slot (it bakes in the by-ref deref), so the conditional ldr
            below reaches the data pointer on a read in both cases, and on a
            write leaves &caller_slot itself -- exactly what SetLength wants to
            publish through. v1: no COW either way. }
          EmitLoadVarAddrA64(si);               { x0 = slot address (&caller_slot if by-ref) }
          if not InLValueWrite then
            EmitI32($F9400000);                 { ldr x0, [x0] = data ptr }
        end
        else if (Syms[si].TypeKind = tyAnsiString) and not Syms[si].IsArray and
                not InLValueWrite then
        begin
          { Scalar managed string in read position: the slot holds the heap data
            pointer (handle); load it so Length / index / concat operate on the
            data, not the slot. Write position keeps the slot address (else
            branch) so a store can publish a new handle. A by-ref param keeps
            the forwarded caller slot address; Length / index add the final
            deref, mirroring i386. }
          EmitLoadVarAddrA64(si);               { x0 = slot address }
          if not ((Syms[si].Kind = skParam) and Syms[si].IsRef) then
            EmitI32($F9400000);                 { ldr x0, [x0] = handle }
        end
        else if (Syms[si].Kind = skParam) and
                (Syms[si].IsRef or Syms[si].IsArray or
                 (Syms[si].TypeKind = tyString) or (Syms[si].TypeKind = tySet)) then
        begin
          { By-ref, open-array, fixed-string, or set param: the slot holds a
            pointer the caller passed (the array data / buffer / forwarded slot),
            so load the pointer itself, not the slot address. Mirrors i386. }
          if Syms[si].IsRef then
            EmitLoadVarAddrA64(si)
          else
          begin
            EmitLoadVarAddrA64(si);
            EmitI32($F9400000);                 { ldr x0, [x0] = caller pointer }
          end;
        end
        else
          EmitLoadVarAddrA64(si);
      end;

    IR_SLOTADDR:
      begin
        { Raw slot address, unconditionally (defs.inc contract) — NOT
          EmitLoadVarAddrA64, whose by-ref auto-deref would hand back the
          caller's address for a var/const-record param; the stackless
          save/restore uses IR_SLOTADDR to write a by-ref param's own slot.
          Mirrors the x86-64/i386/arm32 raw-lea implementations. }
        if Syms[IRA[node]].Kind = skGlobal then
        begin
          EmitI32($18000040);  { ldr w0, [pc+8] }
          EmitI32($14000002);  { b [pc+8] }
          EmitGlobRef(Syms[IRA[node]].Offset);
        end
        else
        begin
          EmitLoadImmA64(0, Syms[IRA[node]].Offset);
          EmitI32($8B0003A0);  { add x0, x29, x0 }
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
          IREmitNodeAarch64(IRA[node]);   { x0 = slot address }
          InLValueWrite := savedLValueWrite;
          procIdx := FindProc('PXXReadVarStrM');
          if procIdx < 0 then Error('compiler error: PXXReadVarStrM not found');
          EmitCallProc(procIdx);
        end
        else if tk = tyChar then
        begin
          IREmitNodeAarch64(IRA[node]);   { x0 = target address }
          procIdx := FindProc('PXXReadVarChar');
          if procIdx < 0 then Error('compiler error: PXXReadVarChar not found');
          EmitCallProc(procIdx);
        end
        else if TypeIsOrdinal(tk) then
        begin
          IREmitNodeAarch64(IRA[node]);   { x0 = target address }
          EmitLoadImmA64(1, TypeSize(tk));      { x1 = size }
          procIdx := FindProc('PXXReadVarInt');
          if procIdx < 0 then Error('compiler error: PXXReadVarInt not found');
          EmitCallProc(procIdx);
        end
        else
          Error('target aarch64: read/readln target type not supported');
      end;

    IR_SETLEN_STR:
      begin
        { SetLength(ansistring-lvalue, n) -> PXXStrSetLen(slotAddr, n). IRA =
          slot-address node, IRB = new length. Address-based, so a record/var-
          param field needs no symbol reconstruction. }
        IREmitNodeAarch64(IRA[node]);     { x0 = slot address }
        EmitI32($F81F0FE0);              { str x0, [sp, #-16]! }
        IREmitNodeAarch64(IRB[node]);     { x0 = n }
        EmitI32($AA0003E1);              { mov x1, x0 (n) }
        EmitI32($F84107E0);              { ldr x0, [sp], #16 (slotAddr) }
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
        IREmitNodeAarch64(IRA[node]);     { x0 = slot addr }
        InLValueWrite := savedLValueWrite;
        EmitI32($F81F0FE0);               { str x0, [sp, #-16]! }
        IREmitNodeAarch64(IRB[node]);     { x0 = n }
        EmitI32($AA0003E1);               { mov x1, x0 (n) }
        EmitI32($F84107E0);               { ldr x0, [sp], #16 (slotAddr) }
        EmitLoadDataRefA64(2, GetOrAllocNodeDynDesc(node)); { x2 = desc }
        procIdx := FindProc('PXXDynSetLen');
        if procIdx < 0 then Error('compiler error: PXXDynSetLen not found');
        EmitCallProc(procIdx);
      end;

    IR_DYNUNIQUE:
      begin
        { Nested dyn-array copy-on-write. IRA = slot-address node. Read: load the
          level's data pointer; write: clone-if-shared via
          PXXDynArrayUnique(slotAddr, desc), returning the data pointer in x0. }
        IREmitNodeAarch64(IRA[node]);     { x0 = slot addr }
        if InLValueWrite then
        begin
          EmitLoadDataRefA64(1, GetOrAllocDynUniqueDesc(node)); { x1 = desc }
          procIdx := FindProc('PXXDynArrayUnique');
          if procIdx < 0 then Error('compiler error: PXXDynArrayUnique not found');
          EmitCallProc(procIdx);              { x0 = unique data ptr }
        end
        else
          EmitI32($F9400000);            { ldr x0, [x0] }
      end;

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
          procIdx := FindProc('PXXStrConcat');
          if procIdx < 0 then Error('compiler error: PXXStrConcat not found');
          EmitCallProc(procIdx);                             { x0 = result }
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

        if (tk = tyString) and (op = Ord(tkPlus)) then
        begin
          lhsTk := IntToTypeKind(IRTk[left]);
          rhsTk := IntToTypeKind(IRTk[right]);
          IREmitNodeAarch64(left);  EmitI32($F81F0FE0); { push lhs }
          IREmitNodeAarch64(right); EmitI32($F81F0FE0); { push rhs }

          EmitLoadImmA64(9, 272);
          EmitI32($CB2963FF);                           { sub sp, sp, x9 }
          EmitI32($910003E3);                           { mov x3, sp (buffer) }

          EmitI32($F94093E0);                           { x0 = lhs value [sp+288] }
          EmitA64StringParts(0, 5, 4, lhsTk, 288);      { x5=src, x4=len }
          EmitI32($AA0403E7);                           { mov x7, x4 (left len) }
          EmitI32($91002066);                           { add x6, x3, #8 (dst) }
          EmitA64CopyBytes(4, 5, 6);

          EmitI32($F9408BE0);                           { x0 = rhs value [sp+272] }
          EmitA64StringParts(0, 5, 4, rhsTk, 272);      { x5=src, x4=len }
          EmitI32($AA0403E9);                           { mov x9, x4 (right len) }
          EmitI32($91002066);                           { add x6, x3, #8 }
          EmitI32($8B0700C6);                           { add x6, x6, x7 }
          EmitA64CopyBytes(4, 5, 6);

          EmitI32($8B0900E7);                           { add x7, x7, x9 (total len) }
          j := CodeLen;
          EmitI32($F10400FF);                           { cmp x7, #256 }
          EmitI32($5400000D);                           { b.le cap_done }
          EmitLoadImmA64(7, 256);
          Patch32(j + 4, $5400000D or (((CodeLen - (j + 4)) div 4) and $7FFFF) shl 5);
          EmitI32($F9000067);                           { str x7, [x3] }
          EmitI32($AA1F03E0);                           { mov x0, xzr }
          EmitI32($B9000460);                           { str w0, [x3,#4] }
          EmitI32($AA0303E0);                           { mov x0, x3 }
          Exit;
        end;

        if ((op = Ord(tkEq)) or (op = Ord(tkNeq))) and
           ((IntToTypeKind(IRTk[left]) in [tyAnsiString, tyString, tyChar, tyPointer]) and
            (IntToTypeKind(IRTk[right]) in [tyAnsiString, tyString, tyChar, tyPointer])) and
           ((IntToTypeKind(IRTk[left]) in [tyAnsiString, tyString]) or
            (IntToTypeKind(IRTk[right]) in [tyAnsiString, tyString])) then
        begin
          { String/char equality via PXXStrEq(lenA, srcA, lenB, srcB). At least one
            operand is a string (managed handle or frozen inline); the other may be
            a frozen string, managed handle, or a single char. EmitA64StringParts
            decomposes each per its type. Without this, two frozen strings fell to
            the integer path below and compared buffer addresses (always unequal). }
          lhsTk := IntToTypeKind(IRTk[left]);
          rhsTk := IntToTypeKind(IRTk[right]);
          { A frozen string reached through a pointer deref / pointer field
            (`pstr^`, `rec.pstrField^`) is tagged tyPointer but its value is the
            buffer address — decode it as a frozen string (the condition above
            still requires the other side to be a genuine string, so a real
            pointer compare never lands here). Mirrors i386/x86-64. }
          if lhsTk = tyPointer then lhsTk := tyString;
          if rhsTk = tyPointer then rhsTk := tyString;
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
          procIdx := FindProc('PXXStrEq');
          if procIdx < 0 then Error('compiler error: PXXStrEq not found');
          EmitCallProc(procIdx);                             { x0 = 1/0 }
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

        lhsTk := IntToTypeKind(IRTk[left]);
        rhsTk := IntToTypeKind(IRTk[right]);
        if TypeIsFloat(lhsTk) or TypeIsFloat(rhsTk) or (op = Ord(tkSlash)) then
        begin
          IREmitNodeAarch64(left);
          EmitI32($F81F0FE0); { str x0, [sp, #-16]! }
          IREmitNodeAarch64(right);
          EmitI32($AA0003E1); { mov x1, x0 }
          EmitI32($F84107E0); { ldr x0, [sp], #16 }

          if not TypeIsFloat(lhsTk) then
            EmitI32($9E620000)  { scvtf d0, x0 }
          else
            EmitI32($9E670000); { fmov d0, x0 }

          if not TypeIsFloat(rhsTk) then
            EmitI32($9E620021)  { scvtf d1, x1 }
          else
            EmitI32($9E670021); { fmov d1, x1 }

          if op = Ord(tkPlus) then EmitI32($1E612800)        { fadd d0, d0, d1 }
          else if op = Ord(tkMinus) then EmitI32($1E613800)  { fsub d0, d0, d1 }
          else if op = Ord(tkStar) then EmitI32($1E610800)   { fmul d0, d0, d1 }
          else if op = Ord(tkSlash) then EmitI32($1E611800)  { fdiv d0, d0, d1 }
          else if (op = Ord(tkEq)) or (op = Ord(tkNeq)) or (op = Ord(tkLt)) or
                  (op = Ord(tkLe)) or (op = Ord(tkGt)) or (op = Ord(tkGe)) then
          begin
            EmitI32($1E612000); { fcmp d0, d1 }
            EmitSetccA64Float(op);
          end
          else
            Error('target aarch64: unsupported float binop');

          if not ((op = Ord(tkEq)) or (op = Ord(tkNeq)) or (op = Ord(tkLt)) or
                  (op = Ord(tkLe)) or (op = Ord(tkGt)) or (op = Ord(tkGe))) then
          begin
            EmitI32($9E660000); { fmov x0, d0 }
          end;
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
        else if op = Ord(tkDiv) then
        begin
          { UDIV for an unsigned dividend, SDIV otherwise (matches the arm32 /
            riscv32 backends, which key off the dividend type). Emitting SDIV for
            an unsigned operand whose top bit is set (e.g. size_t ~0) treated it
            as -1, so `MAX_SIZET/24` came out 0 and lua's table-size guard tripped
            a bogus "table overflow" (bug-aarch64-unsigned-div). }
          if TypeDivideUnsigned(IntToTypeKind(IRTk[left])) then EmitI32($9AC10800) { udiv x0, x0, x1 }
          else EmitI32($9AC10C00);                          { sdiv x0, x0, x1 }
        end
        else if op = Ord(tkMod) then
        begin
          if TypeDivideUnsigned(IntToTypeKind(IRTk[left])) then EmitI32($9AC10802) { udiv x2, x0, x1 }
          else EmitI32($9AC10C02);                          { sdiv x2, x0, x1 }
          EmitI32($9B018040);  { msub x0, x2, x1, x0 }
        end
        else if op = Ord(tkAnd) then EmitI32($8A010000)    { and x0, x0, x1 }
        else if op = Ord(tkOr) then EmitI32($AA010000)     { orr x0, x0, x1 }
        else if op = Ord(tkXor) then EmitI32($CA010000)    { eor x0, x0, x1 }
        else if op = Ord(tkShl) then
        begin
          EmitI32($9AC12000);                              { lsl x0, x0, x1 }
          { Wrap at the operand width: a <8-byte result shifted into bit 31 must
            read back as a 32-bit value (sign-extended for a signed operand,
            zero-extended for unsigned), not the wider 64-bit register content
            (bug-shl-signed-integer-width). 64-bit operands shift as-is. }
          if TypeSize(IntToTypeKind(IRTk[IRA[node]])) < 8 then
          begin
            if TypeSigned(IntToTypeKind(IRTk[IRA[node]])) then
              EmitI32($93407C00)                           { sxtw x0, w0 }
            else
              EmitI32($2A0003E0);                          { mov w0, w0 }
          end;
        end
        else if op = Ord(tkIdent) then
        begin
          { Logical shr on a <=32-bit operand: zero-extend (`mov w0, w0` clears the
            upper 32 of x0) so a sign-extended negative value's high bits don't
            leak into the 64-bit lsr (bug-shr-signed-integer-width). }
          if TypeSize(IntToTypeKind(IRTk[IRA[node]])) < 8 then
            EmitI32($2A0003E0);                            { mov w0, w0 }
          EmitI32($9AC12400);                              { lsr x0, x0, x1 }
        end
        else if op = Ord(tkShr) then
        begin
          { C signed >> (bug-c-signed-arith-shift-right): arithmetic shift.
            Mirrors the logical case above but sign-extends (`sxtw x0, w0`)
            instead of zero-extending for a <8-byte operand, and uses asrv
            instead of lsrv. }
          if TypeSize(IntToTypeKind(IRTk[IRA[node]])) < 8 then
            EmitI32($93407C00);                            { sxtw x0, w0 }
          EmitI32($9AC12800);                              { asr x0, x0, x1 }
        end
        else if (op = Ord(tkEq)) or (op = Ord(tkNeq)) or (op = Ord(tkLt)) or
                (op = Ord(tkLe)) or (op = Ord(tkGt)) or (op = Ord(tkGe)) then
        begin
          EmitI32($EB01001F); { cmp x0, x1 }
          { Unsigned magnitude compare when either operand is an unsigned ordinal
            (C usual-arithmetic-conversions make the whole compare unsigned). }
          EmitSetccA64Ex(op,
            TypeDivideUnsigned(IntToTypeKind(IRTk[left])) or
            TypeDivideUnsigned(IntToTypeKind(IRTk[right])));
        end
        else if op = Ord(tkIn) then
        begin
          { Set membership: x0 = element, x1 = set address. Result (0/1) -> x0. }
          EmitI32($F103FC1F);                   { cmp x0, #255 }
          p1 := CodeLen; EmitI32($54000008);    { b.hi out-of-range (patched) }
          EmitI32($D343FC02);                   { lsr x2, x0, #3 (byte index) }
          EmitI32($8B020022);                   { add x2, x1, x2 }
          EmitI32($39400042);                   { ldrb w2, [x2] (set byte) }
          EmitI32($D28000E3);                   { mov x3, #7 }
          EmitI32($8A030000);                   { and x0, x0, x3 (bit index) }
          EmitI32($D2800023);                   { mov x3, #1 }
          EmitI32($9AC02063);                   { lsl x3, x3, x0 }
          EmitI32($EA03005F);                   { tst x2, x3 }
          EmitI32($9A9F07E0);                   { cset x0, ne }
          p2 := CodeLen; EmitI32($14000000);    { b done (patched) }
          Patch32(p1, $54000008 or ((((CodeLen - p1) div 4) and $7FFFF) shl 5));
          EmitI32($D2800000);                   { mov x0, #0 }
          Patch32(p2, $14000000 or (((CodeLen - p2) div 4) and $03FFFFFF));
        end
        else
          Error('target aarch64: binop operator not yet supported');
      end;

    IR_CALL:
      begin
        procIdx := IRA[node];
        if procIdx = -Ord(tkGetMem) then
        begin
          { GetMem / New / class instantiation. For a class: alloc, store the
            VMT pointer at offset 0, run the ctor, return Self in x0. AAPCS:
            push each arg to a 16-byte temp (Self deepest), pop into x0..x7. }
          classIdx := IRC[node];
          argNode := IRB[node];               { size arg }
          IREmitNodeAarch64(IRA[argNode]);    { size -> x0 }
          EmitHeapAllocLockedA64;             { x0 = payload pointer }
          if classIdx < REC_UCLASS_BASE then
            Exit;                             { plain GetMem: pointer in x0 }
          EmitLoadDataRefA64(9, UClsVMTOffset[classIdx - REC_UCLASS_BASE]); { x9 = VMT addr }
          EmitI32($F9000009);                 { str x9, [x0] (VMT pointer) }
          j := FindUMeth(classIdx - REC_UCLASS_BASE, 'create');
          if j < 0 then
            Exit;                             { no ctor: instance pointer in x0 }
          p1 := UMthProc_[j];                 { ctor proc index }
          EmitI32($F81F0FE0);                 { str x0, [sp,#-16]! (Self, deepest) }
          nArgs := 1;
          argNode := IRB[node];               { size arg }
          argNode := IRB[argNode];            { first explicit ctor arg }
          while argNode <> -1 do
          begin
            IREmitNodeAarch64(IRA[argNode]);
            EmitI32($F81F0FE0);               { str x0, [sp,#-16]! }
            Inc(nArgs);
            argNode := IRB[argNode];
          end;
          if nArgs > 8 then
            Error('target aarch64: constructor with more than 8 parameters not supported');
          for i := nArgs - 1 downto 0 do
            EmitI32($F84107E0 + i);           { ldr x[i], [sp], #16 }
          EmitI32($F81F0FE0);                 { str x0, [sp,#-16]! (save Self) }
          EmitCallProc(p1);
          EmitI32($F84107E0);                 { ldr x0, [sp], #16 (Self = result) }
          Exit;
        end;
        if procIdx = -Ord(tkFreeMem) then
        begin
          argNode := IRB[node];               { pointer arg }
          IREmitNodeAarch64(IRA[argNode]);    { p -> x0 }
          EmitHeapFreeLockedA64;
          Exit;
        end;
        if procIdx = -102 then
        begin
          { SetLength(arr, n) -> PXXDynSetLen(slotAddr, n, desc). SetLength on
            a managed AnsiString -> PXXStrSetLen(slotAddr, n). }
          argNode := IRB[node];               { arg1 = array/string lvalue }
          valNode := IRB[argNode];            { arg2 = new length }
          left := IRA[argNode];               { IR_LEA or IR_LOAD_SYM node }
          if (IRKind[left] = IR_LOAD_SYM) and
             (Syms[IRA[left]].TypeKind = tyAnsiString) then
          begin
            si := IRA[left];
            if (Syms[si].Kind = skParam) and Syms[si].IsRef then
            begin
              EmitLoadImmA64(9, Syms[si].Offset);
              EmitI32($8B0903A9);             { add x9, x29, x9 }
              EmitI32($F9400120);             { ldr x0, [x9] caller slot addr }
            end
            else
              EmitLoadVarAddrA64(si);         { x0 = slot address }
            EmitI32($F81F0FE0);               { str x0, [sp, #-16]! }
            IREmitNodeAarch64(IRA[valNode]);  { x0 = n }
            EmitI32($AA0003E1);               { mov x1, x0 (n) }
            EmitI32($F84107E0);               { ldr x0, [sp], #16 (slotAddr) }
            procIdx := FindProc('PXXStrSetLen');
            if procIdx < 0 then Error('compiler error: PXXStrSetLen not found');
            EmitCallProc(procIdx);
            Exit;
          end;
          if IRKind[left] <> IR_LEA then
            Error('target aarch64: SetLength expects an array variable');
          si := IRA[left];
          if not (Syms[si].IsArray and (Syms[si].ArrLen = -1)) then
            Error('target aarch64: SetLength only supports dynamic arrays yet');
          { x0 = slot address. For a by-ref (var/out) param EmitLoadVarAddrA64
            already yields &caller_slot, exactly what PXXDynSetLen needs to resize
            and publish the new handle back into the caller's slot. }
          EmitLoadVarAddrA64(si);             { x0 = slot address (&caller_slot if by-ref) }
          EmitI32($F81F0FE0);                 { str x0, [sp, #-16]! }
          IREmitNodeAarch64(IRA[valNode]);    { x0 = n }
          EmitI32($AA0003E1);                 { mov x1, x0 (n) }
          EmitI32($F84107E0);                 { ldr x0, [sp], #16 (slotAddr) }
          EmitLoadDataRefA64(2, GetOrAllocSymRTTI(si)); { x2 = desc }
          procIdx := FindProc('PXXDynSetLen');
          if procIdx < 0 then Error('compiler error: PXXDynSetLen not found');
          EmitCallProc(procIdx);
          Exit;
        end;
        if procIdx = -101 then
        begin
          { SetLength(s, n) on a frozen inline string: store n into the 8-byte
            length prefix at [buffer+0]. The buffer is the symbol slot for a
            local/global; for a string param the slot holds a pointer P to it.
            Mirrors x86-64 EmitStoreStrLen. }
          argNode := IRB[node];
          valNode := IRB[argNode];
          left := IRA[argNode];
          if IRKind[left] <> IR_LEA then
            Error('target aarch64: SetLength expects a string variable');
          si := IRA[left];
          EmitLoadVarAddrA64(si);              { x0 = buffer addr (or &slot for a string param) }
          if (Syms[si].Kind = skParam) and TypeIsFrozenString(Syms[si].TypeKind) and
             not Syms[si].IsArray then
            EmitI32($F9400000);                { ldr x0, [x0] = P (param slot holds the pointer) }
          EmitI32($F81F0FE0);                  { str x0, [sp, #-16]! (push buffer addr) }
          IREmitNodeAarch64(IRA[valNode]);     { x0 = new length }
          EmitI32($F84107E1);                  { ldr x1, [sp], #16 (buffer addr) }
          EmitI32($F9000020);                  { str x0, [x1] (8-byte length prefix) }
          Exit;
        end;
        if procIdx = -Ord(tkLength) then
        begin
          { Length(arr): IR_LEA auto-loaded the data pointer; count at [handle-8]. }
          argNode := IRB[node];
          valNode := IRA[argNode];
          if (IntToTypeKind(IRTk[valNode]) = tyString) or
             ((IRKind[valNode] = IR_LEA) and
              (Syms[IRA[valNode]].TypeKind = tyString) and
              not Syms[IRA[valNode]].IsArray) or
             (((IRKind[valNode] = IR_LOAD_SYM) or (IRKind[valNode] = IR_LOAD_MEM)) and
              (IntToTypeKind(IRTk[valNode]) = tyPointer)) then
          begin
            { Frozen inline string: length is the 8-byte prefix at [buffer+0]. A
              frozen string reached through a pointer deref (`ps^`, `rec.pf^`)
              lowers to a bare pointer load whose value IS the buffer address;
              read the prefix there, mirroring x86-64's else catch-all. }
            IREmitNodeAarch64(valNode);       { x0 = frozen buffer addr }
            EmitI32($F9400000);               { ldr x0, [x0] }
            Exit;
          end;
          IREmitNodeAarch64(valNode);         { x0 = handle (or 0) }
          if (IRKind[valNode] = IR_INDEX) or (IRKind[valNode] = IR_FIELD) or
             ((IRKind[valNode] = IR_LEA) and (Syms[IRA[valNode]].Kind = skParam) and
              Syms[IRA[valNode]].IsRef and (Syms[IRA[valNode]].TypeKind = tyAnsiString) and
              not Syms[IRA[valNode]].IsArray) then
            EmitI32($F9400000);               { ldr x0, [x0] (deref slot to handle) }
          EmitI32($B4000040);                 { cbz x0, +8 (skip ldur) }
          EmitI32($F85F8000);                 { ldur x0, [x0, #-8] }
          Exit;
        end;
        if procIdx = -100 then
        begin
          { LoadFile(path, dst): read file into managed AnsiString dst. }
          argNode := IRB[node];
          left := IRA[argNode];               { path node }
          valNode := IRB[argNode];            { arg2 }
          right := IRA[valNode];              { dst node }
          if not ((IRKind[right] = IR_LOAD_SYM) and
                  (Syms[IRA[right]].TypeKind = tyAnsiString)) then
            Error('target aarch64: LoadFile expects a managed-string destination');
          si := IRA[right];
          IREmitNodeAarch64(left);             { x0 = path handle }
          procIdx := FindProc('PXXStrLoadFile');
          if procIdx < 0 then Error('compiler error: PXXStrLoadFile not found');
          EmitCallProc(procIdx);                    { x0 = new handle }
          EmitI32($F81F0FE0);                  { push new }
          EmitLoadVarA64(si);                  { x0 = old handle }
          EmitStrDecRefA64;
          EmitI32($F84107E0);                  { pop new }
          EmitStoreVarA64(si);
          Exit;
        end;
        if procIdx < 0 then
        begin
          specialId := -procIdx;
          if (specialId = Ord(tkOrd)) or (specialId = Ord(tkChr)) or
             (specialId = Ord(tkInteger_T)) or (specialId = Ord(tkLongWord_T)) or
             (specialId = Ord(tkChar_T)) or (specialId = Ord(tkBoolean_T)) or
             (specialId = Ord(tkString_T)) then
          begin
            { type-pun passthrough: evaluate the argument in place }
            argNode := IRB[node];
            IREmitNodeAarch64(IRA[argNode]);
            Exit;
          end;
          if specialId = Ord(tkArgCount) then
          begin
            EmitI32($18000040);                 { ldr w0, [pc+8] }
            EmitI32($14000002);                 { b [pc+8] }
            EmitGlobRef(BSS_INITIAL_RSP);
            EmitI32($F9400000);                 { ldr x0, [x0] = initial sp }
            EmitI32($F9400000);                 { ldr x0, [x0] = argc }
            EmitI32($D1000400);                 { sub x0, x0, #1 }
            Exit;
          end
          else if specialId = Ord(tkArgStr) then
          begin
            argNode := IRB[node];
            if argNode = -1 then
              Error('target aarch64: ArgStr expects an index');
            IREmitNodeAarch64(IRA[argNode]);  { x0 = argv index }
            argNode := IRB[argNode];
            if argNode = -1 then
              Error('target aarch64: ParamStr expression must be assigned directly');
            valNode := IRA[argNode];
            { Managed-string dest (scalar `string` is tyAnsiString by default):
              build a heap AnsiString from argv[index] and publish it (release
              dst's old handle), mirroring the LoadFile path. The fixed/short
              inline-buffer path below is for a frozen string dest only. }
            if (IRKind[valNode] = IR_LOAD_SYM) and
               (Syms[IRA[valNode]].TypeKind = tyAnsiString) then
            begin
              si := IRA[valNode];
              EmitArgvToAnsiStringA64;          { x0 (index) -> x0 = new handle }
              EmitI32($F81F0FE0);               { str x0, [sp,#-16]! (push new) }
              EmitLoadVarA64(si);               { x0 = old handle }
              EmitStrDecRefA64;
              EmitI32($F84107E0);               { ldr x0, [sp],#16 (pop new) }
              EmitStoreVarA64(si);
              Exit;
            end;
            if IRKind[valNode] <> IR_LEA then
              Error('target aarch64: ArgStr expects a string variable');
            EmitLoadArgvPtrA64;               { x0 = src }
            EmitI32($AA0003E5);               { mov x5, x0 (src) }
            EmitI32($AA0003E3);               { mov x3, x0 (scan) }
            EmitLoadImmA64(4, 0);             { x4 = len }
            p1 := CodeLen;
            EmitI32($39400066);               { ldrb w6, [x3] }
            p2 := CodeLen; EmitI32($34000006); { cbz w6, done }
            EmitI32($91000484);               { add x4, x4, #1 }
            EmitI32($91000463);               { add x3, x3, #1 }
            j := CodeLen; EmitI32($14000000); { b loop }
            Patch32(p2, $34000006 or (((CodeLen - p2) div 4) and $7FFFF) shl 5);
            Patch32(j, $14000000 or (((p1 - j) div 4) and $03FFFFFF));
            EmitI32($F104009F);               { cmp x4, #256 }
            j := CodeLen; EmitI32($5400000D); { b.le cap_done }
            EmitLoadImmA64(4, 256);
            Patch32(j, $5400000D or (((CodeLen - j) div 4) and $7FFFF) shl 5);
            EmitLoadVarAddrA64(IRA[valNode]); { x0 = dst }
            EmitI32($F9000004);               { str x4, [x0] }
            EmitI32($B900041F);               { str wzr, [x0,#4] }
            EmitI32($91002006);               { add x6, x0, #8 }
            EmitA64CopyBytes(4, 5, 6);
            Exit;
          end;
          if specialId = 200 then
          begin
            { int(x): float/Variant -> integer }
            argNode := IRB[node];
            valNode := IRA[argNode];
            IREmitNodeAarch64(valNode); { result in x0 }
            if TypeIsFloat(IntToTypeKind(IRTk[valNode])) then
            begin
              EmitI32($9E670000);   { fmov d0, x0 }
              EmitI32($9EFA0000);   { fcvtzs x0, d0 }
            end
            else if IntToTypeKind(IRTk[valNode]) = tyVariant then
            begin
              { Variant: x0 is address of variant slot. }
              EmitI32($F9400001);   { ldr x1, [x0] (tag) }
              EmitI32($F100063F);   { cmp x1, #3 (VT_DOUBLE) }
              jnsOff := CodeLen;
              EmitI32($54000081);   { b.ne .not_double (patched) }
              EmitI32($F9400400);   { ldr x0, [x0, #8] (payload) }
              EmitI32($9E670000);   { fmov d0, x0 }
              EmitI32($9EFA0000);   { fcvtzs x0, d0 }
              jmpDone := CodeLen;
              EmitI32($14000000);   { b .done (patched) }
              { .not_double }
              Patch32(jnsOff, $54000081 or (((CodeLen - jnsOff) div 4) and $7FFFF) shl 5);
              EmitI32($F9400400);   { ldr x0, [x0, #8] (payload) }
              { .done }
              Patch32(jmpDone, $14000000 or (((CodeLen - jmpDone) div 4) and $03FFFFFF));
            end;
            Exit;
          end
          else if (specialId = 203) or (specialId = 204) or
                  (specialId = 205) or (specialId = 206) then
          begin
            { Float intrinsics: 203 Trunc, 204 Round, 205 Frac, 206 Int }
            argNode := IRB[node];
            valNode := IRA[argNode];
            IREmitNodeAarch64(valNode); { result in x0 }
            if TypeIsFloat(IntToTypeKind(IRTk[valNode])) then
            begin
              EmitI32($9E670000);   { fmov d0, x0 }
              if specialId = 203 then
              begin
                EmitI32($9E780000); { fcvtzs x0, d0 }
              end
              else if specialId = 204 then
              begin
                EmitI32($9E600000); { fcvtns x0, d0 }
              end
              else if specialId = 206 then
              begin
                EmitI32($9E780000); { fcvtzs x0, d0 }
                EmitI32($9E620000); { scvtf d0, x0 }
                EmitI32($9E660000); { fmov x0, d0 }
              end
              else
              begin
                { 205 Frac = x - trunc(x) }
                EmitI32($9E780001); { fcvtzs x1, d0 }
                EmitI32($9E620021); { scvtf d1, x1 }
                EmitI32($1E613800); { fsub d0, d0, d1 }
                EmitI32($9E660000); { fmov x0, d0 }
              end;
            end
            else
            begin
              { integer argument }
              if specialId = 205 then
              begin
                EmitLoadImmA64(0, 0); { Frac(int) = 0 }
              end
              else if specialId = 206 then
              begin
                EmitI32($9E620000); { scvtf d0, x0 }
                EmitI32($9E660000); { fmov x0, d0 }
              end;
              { 203/204 Trunc/Round: x0 already holds it }
            end;
            Exit;
          end
          else if specialId = SPECIAL_IN then
          begin
            { x in [items]: constant single values or [lo..hi] ranges. }
            argNode := IRB[node];             { arg1 = test value }
            IREmitNodeAarch64(IRA[argNode]);  { x0 = test value }
            EmitI32($AA0003E1);               { mov x1, x0 }
            EmitLoadImmA64(4, 0);             { x4 = result accumulator }
            argNode := IRB[argNode];          { first set item }
            while argNode <> -1 do
            begin
              itemNode := IRA[argNode];
              if IRKind[itemNode] = IR_BLOCK then
              begin
                lo := Integer(IRIVal[IRA[itemNode]]);
                hi := Integer(IRIVal[IRB[itemNode]]);
                EmitLoadImmA64(2, lo);
                EmitI32($EB02003F);           { cmp x1, x2 }
                p1 := CodeLen; EmitI32($5400000B); { b.lt skip }
                EmitLoadImmA64(2, hi);
                EmitI32($EB02003F);           { cmp x1, x2 }
                p2 := CodeLen; EmitI32($5400000C); { b.gt skip }
                EmitLoadImmA64(4, 1);
                Patch32(p1, $5400000B or (((CodeLen - p1) div 4) and $7FFFF) shl 5);
                Patch32(p2, $5400000C or (((CodeLen - p2) div 4) and $7FFFF) shl 5);
              end
              else
              begin
                lo := Integer(IRIVal[itemNode]);
                EmitLoadImmA64(2, lo);
                EmitI32($EB02003F);           { cmp x1, x2 }
                EmitSetccA64(Ord(tkEq));      { x0 = equal ? 1 : 0 }
                EmitI32($AA000084);           { orr x4, x4, x0 }
              end;
              argNode := IRB[argNode];
            end;
            EmitI32($AA0403E0);               { mov x0, x4 }
            Exit;
          end
          else if specialId = Ord(tkSysOpen) then
          begin
            { AArch64 has openat, not open: openat(AT_FDCWD, path, flags, 0). }
            argNode := IRB[node];
            valNode := IRA[argNode];
            if IntToTypeKind(IRTk[valNode]) <> tyAnsiString then
              Error('target aarch64: SysOpen expects a managed AnsiString path');
            IREmitNodeAarch64(valNode);        { x0 = path }
            EmitI32($F81F0FE0);                { push path }
            argNode := IRB[argNode];
            IREmitNodeAarch64(IRA[argNode]);   { x0 = flags }
            EmitI32($AA0003E2);                { mov x2, x0 }
            EmitI32($F84107E1);                { pop x1 path }
            EmitLoadImmA64(0, -100);           { AT_FDCWD }
            EmitLoadImmA64(3, 0);              { mode }
            EmitLoadImmA64(8, 56);             { __NR_openat }
            EmitI32($D4000001);                { svc #0 }
            Exit;
          end
          else if specialId = Ord(tkSysRead) then
          begin
            argNode := IRB[node];
            IREmitNodeAarch64(IRA[argNode]);   { fd }
            EmitI32($F81F0FE0);
            argNode := IRB[argNode];
            IREmitNodeAarch64(IRA[argNode]);   { buf }
            EmitI32($F81F0FE0);
            argNode := IRB[argNode];
            IREmitNodeAarch64(IRA[argNode]);   { count }
            EmitI32($AA0003E2);                { x2 = count }
            EmitI32($F84107E1);                { x1 = buf }
            EmitI32($F84107E0);                { x0 = fd }
            EmitLoadImmA64(8, 63);             { __NR_read }
            EmitI32($D4000001);
            Exit;
          end
          else if specialId = Ord(tkSyswrite) then
          begin
            argNode := IRB[node];
            IREmitNodeAarch64(IRA[argNode]);   { fd }
            EmitI32($F81F0FE0);
            argNode := IRB[argNode];
            IREmitNodeAarch64(IRA[argNode]);   { buf }
            EmitI32($F81F0FE0);
            argNode := IRB[argNode];
            IREmitNodeAarch64(IRA[argNode]);   { count }
            EmitI32($AA0003E2);                { x2 = count }
            EmitI32($F84107E1);                { x1 = buf }
            EmitI32($F84107E0);                { x0 = fd }
            EmitLoadImmA64(8, 64);             { __NR_write }
            EmitI32($D4000001);
            Exit;
          end
          else if specialId = Ord(tkSysClose) then
          begin
            argNode := IRB[node];
            IREmitNodeAarch64(IRA[argNode]);   { fd }
            EmitLoadImmA64(8, 57);             { __NR_close }
            EmitI32($D4000001);
            Exit;
          end
          else if specialId = Ord(tkSysFchmod) then
          begin
            argNode := IRB[node];
            IREmitNodeAarch64(IRA[argNode]);   { fd }
            EmitI32($F81F0FE0);
            argNode := IRB[argNode];
            IREmitNodeAarch64(IRA[argNode]);   { mode }
            EmitI32($AA0003E1);                { x1 = mode }
            EmitI32($F84107E0);                { x0 = fd }
            EmitLoadImmA64(8, 52);             { __NR_fchmod }
            EmitI32($D4000001);
            Exit;
          end
          else if specialId = 210 then
          begin
            { bare `Eof` (stdin) -> PXXStdinEof: Boolean (portable builtin,
              shares the peek byte with PXXReadLine). }
            procIdx := FindProc('PXXStdinEof');
            if procIdx < 0 then Error('compiler error: PXXStdinEof not found');
            EmitCallProc(procIdx);
            Exit;
          end
          else
            Error('target aarch64: builtin/special call not yet supported');
        end;
        if ProcExternal[procIdx] then
        begin
          { External C call (AAPCS): integer/pointer args in x0..x7, FP args in
            v0..v7 (the two classes are allocated independently, mirroring the
            x86-64 SysV split), result in x0 / v0. The value model carries floats
            as double bits in a GPR, so a float arg is fmov'd into d[n] (single
            params then fcvt'd to s[n]); a single return is fcvt-widened back to
            double before bridging d0 -> x0. Args are pushed to 16-byte temp
            slots in order, then popped (reverse) into their target register; the
            per-arg register index is the count of preceding same-class params.
            The call goes through the external's GOT slot via EmitExternalCallA64. }
          if Procs[procIdx].ParamCount > 8 then
            Error('target aarch64: external call with more than 8 parameters not supported');
          { Independent class counts: AAPCS has 8 of each register class. }
          lo := 0; hi := 0;   { lo = int param count, hi = fp param count }
          for i := 0 to Procs[procIdx].ParamCount - 1 do
            if TypeIsFloat(Procs[procIdx].Params[i].TypeKind) then Inc(hi) else Inc(lo);
          if (lo > 8) or (hi > 8) then
            Error('target aarch64: external call exceeds 8 int or 8 fp argument registers');
          argNode := IRB[node];
          nArgs := 0;
          while argNode <> -1 do
          begin
            IREmitNodeAarch64(IRA[argNode]);
            EmitI32($F81F0FE0);                  { str x0, [sp, #-16]! (arg0 deepest) }
            Inc(nArgs);
            argNode := IRB[argNode];
          end;
          if (nArgs <> Procs[procIdx].ParamCount) and not ProcVariadic[procIdx] then
            Error('target aarch64: external call argument count mismatch');
          if ProcVariadic[procIdx] then
          begin
            { Variadic external (e.g. fcntl/open declared `int f(int,int,...)`):
              AArch64-Linux passes the variadic tail in x0..x7 then the stack,
              same as GP named args, so load every arg sequentially into x[i].
              (sqlite only reaches these in its file VFS; a :memory: DB never
              calls them, so this just has to link. >8 args unsupported.) }
            if nArgs > 8 then
              Error('target aarch64: variadic external call with more than 8 arguments not supported');
            for i := nArgs - 1 downto 0 do
              EmitI32($F84107E0 + i);            { ldr x[i], [sp], #16 }
          end
          else
          { Pop reverse (top = last arg) into the target register. }
          for i := nArgs - 1 downto 0 do
          begin
            { Count preceding same-class params to get this arg's register slot. }
            lo := 0; hi := 0;
            for j := 0 to i - 1 do
              if TypeIsFloat(Procs[procIdx].Params[j].TypeKind) then Inc(hi) else Inc(lo);
            EmitI32($F84107E9);                  { ldr x9, [sp], #16 }
            if TypeIsFloat(Procs[procIdx].Params[i].TypeKind) then
            begin
              EmitI32($9E670120 + hi);           { fmov d[hi], x9 }
              if Procs[procIdx].Params[i].TypeKind = tySingle then
                EmitI32($1E624000 + (hi shl 5) + hi); { fcvt s[hi], d[hi] }
            end
            else
              EmitI32($AA0903E0 + lo);           { mov x[lo], x9 }
          end;
          EmitExternalCallA64(RegisterExternal(procIdx));
          if TypeIsFloat(Procs[procIdx].RetType) then
          begin
            if Procs[procIdx].RetType = tySingle then
              EmitI32($1E22C000);                { fcvt d0, s0 (widen single result) }
            EmitI32($9E660000);                  { fmov x0, d0 (bridge to GPR bits) }
          end;
          Exit;
        end;

        { Aggregate result: push the caller's hidden destination first (deepest
          temp) so arg evaluation can't disturb it; it is popped into x8 (the
          AAPCS indirect-result register) just before the call. }
        if RetViaHiddenDest(Procs[procIdx].RetType) then
        begin
          IREmitNodeAarch64(IRC[node]);   { x0 = hidden destination }
          EmitI32($F81F0FE0);             { str x0, [sp, #-16]! }
        end;

        argNode := IRB[node];
        nArgs := 0;
        while argNode <> -1 do
        begin
          IREmitNodeAarch64(IRA[argNode]);
          EmitI32($F81F0FE0); { str x0, [sp, #-16]! (16-byte temp slot, arg0 deepest) }
          Inc(nArgs);
          argNode := IRB[argNode];
        end;
        { A variadic callee (e.g. lua's lua_pushfstring) legitimately receives
          more args than declared params. AAPCS-Linux passes variadic args in the
          same registers/stack as named ones, and the pxx value model carries
          every scalar (floats included) as bits in an x-register, so the generic
          push-all/pop-into-x[i] path below is already correct for them. Only the
          strict equality guard blocked it. }
        if (nArgs <> Procs[procIdx].ParamCount) and not ProcVariadic[procIdx] then
          Error('target aarch64: call argument count mismatch');

        if nArgs <= 8 then
        begin
          { All args fit in x0..x7: pop each temp into its register (unchanged). }
          for i := nArgs - 1 downto 0 do
            EmitI32($F84107E0 + i); { ldr x[i], [sp], #16 }
          if RetViaHiddenDest(Procs[procIdx].RetType) then
            EmitI32($F84107E8);   { ldr x8, [sp], #16 (hidden destination) }
          EmitCallProc(procIdx);
        end
        else
        begin
          if RetViaHiddenDest(Procs[procIdx].RetType) then
            Error('target aarch64: aggregate result with more than 8 params not supported');
          { AAPCS: args 0..7 in x0..x7, args 8.. in an outgoing stack block at sp.
            Build the block from the temp slots without consuming them, load the
            register args by offset, then drop block + temps after the call.
            (No proc in compiler.pas has >8 params, so this path never fires
            during self-host — the <=8 path above stays byte-identical.) }
          lo := nArgs - 8;                              { stack-arg count }
          hi := ((lo * 8 + 15) div 16) * 16;            { outgoing block bytes (16-aligned) }
          EmitI32($D10003FF or (hi shl 10));            { sub sp, sp, #hi }
          { temp slot for arg k is at [sp + hi + (nArgs-1-k)*16] }
          for i := 8 to nArgs - 1 do
          begin
            sz  := hi + (nArgs - 1 - i) * 16;           { temp byte offset }
            wid := (i - 8) * 8;                         { outgoing byte offset }
            EmitI32($F94003E9 or ((sz div 8) shl 10));  { ldr x9, [sp, #sz] }
            EmitI32($F90003E9 or ((wid div 8) shl 10)); { str x9, [sp, #wid] }
          end;
          for i := 0 to 7 do
          begin
            sz := hi + (nArgs - 1 - i) * 16;
            EmitI32($F94003E0 or i or ((sz div 8) shl 10)); { ldr x[i], [sp, #sz] }
          end;
          EmitCallProc(procIdx);
          EmitI32($910003FF or ((hi + nArgs * 16) shl 10)); { add sp, sp, #(hi+nArgs*16) }
        end;
      end;

    IR_CALL_IND:
      begin
        if IRCallDest[node] >= 0 then
          Error('target aarch64: aggregate/frozen-string result via an indirect call is not yet supported (feature-cross-virtual-indirect-hidden-dest)');
        { Indirect call through a proc-typed value. Push the callee address first
          (deepest temp slot) so arg evaluation can't disturb it, push args, pop
          args into x0..x7, pop the callee into x16, and `blr x16`. }
        procIdx := Integer(IRIVal[node]);                 { signature proc index }
        if Procs[procIdx].ParamCount + Integer(IRC[node]) > 8 then
          Error('target aarch64: indirect call with more than 8 parameters not supported');
        IREmitNodeAarch64(IRA[node]);                { x0 = callee address }
        EmitI32($F81F0FE0);                          { str x0, [sp, #-16]! (callee) }
        argNode := IRB[node];
        nArgs := 0;
        while argNode <> -1 do
        begin
          IREmitNodeAarch64(IRA[argNode]);
          EmitI32($F81F0FE0);                        { str x0, [sp, #-16]! }
          Inc(nArgs);
          argNode := IRB[argNode];
        end;
        for i := nArgs - 1 downto 0 do
          EmitI32($F84107E0 + i);                    { ldr x[i], [sp], #16 }
        EmitI32($F84107F0);                          { ldr x16, [sp], #16 (callee) }
        EmitI32($D63F0200);                          { blr x16 }
      end;

    IR_VIRTUAL_CALL:
      begin
        if IRCallDest[node] >= 0 then
          Error('target aarch64: aggregate/frozen-string result via a virtual call is not yet supported (feature-cross-virtual-indirect-hidden-dest)');
        { VMT dispatch. IRA=first arg, IRB=last arg, IRC=proc idx, IRIVal=slot.
          Push args to 16-byte temps (Self = param 0, deepest), pop into x0..x7,
          load the VMT pointer from [Self], call through [VMT + slot*8]. The data
          blob keeps 8-byte slots, so the scaled ldr reads the full address. }
        procIdx := IRC[node];
        j := Integer(IRIVal[node]);                  { VMT slot }
        argNode := IRA[node];
        nArgs := 0;
        while argNode <> -1 do
        begin
          IREmitNodeAarch64(IRA[argNode]);
          EmitI32($F81F0FE0);                        { str x0, [sp,#-16]! }
          Inc(nArgs);
          argNode := IRB[argNode];
        end;
        if nArgs > 8 then
          Error('target aarch64: virtual call with more than 8 parameters not supported');
        for i := nArgs - 1 downto 0 do
          EmitI32($F84107E0 + i);                    { ldr x[i], [sp], #16 }
        EmitI32($F9400009);                          { ldr x9, [x0] (VMT ptr) }
        EmitI32($F9400129 or (j shl 10));            { ldr x9, [x9, #slot*8] }
        EmitI32($D63F0120);                          { blr x9 }
      end;

    IR_COSWITCH:
      begin
        { __pxxcoswitch(pfrom, pto): pfrom -> x0, pto -> x1, bl CoSwitch. }
        argNode := IRA[node];                        { IR_ARG pfrom }
        IREmitNodeAarch64(IRA[argNode]);
        EmitI32($F81F0FE0);                          { str x0, [sp, #-16]! (push pfrom) }
        argNode := IRB[argNode];                     { IR_ARG pto }
        IREmitNodeAarch64(IRA[argNode]);
        EmitI32($AA0003E1);                          { mov x1, x0 (pto) }
        EmitI32($F84107E0);                          { ldr x0, [sp], #16 (pfrom) }
        EmitI32($94000000 or (((CoSwitchAddr - CodeLen) div 4) and $03ffffff)); { bl CoSwitch }
      end;

    IR_PROCADDR:
      begin
        { @proc -> x0 = absolute code address, via a PC-relative load of an
          8-byte literal patched at finalize. }
        if ProcExternal[IRA[node]] then
        begin
          EmitExternalProcAddr(IRA[node]);           { x0 = resolved external fn ptr (GOT) }
          Exit;
        end;
        EmitI32($58000040);                          { ldr x0, [pc, #8] (literal below) }
        EmitI32($14000003);                          { b .+12 (skip 8-byte literal) }
        if ProcAddrFixCount >= MAX_CALLFIX then Error('proc addr fixup overflow');
        ProcAddrFix[ProcAddrFixCount].CodePos := CodeLen;
        ProcAddrFix[ProcAddrFixCount].ProcIdx := IRA[node];
        Inc(ProcAddrFixCount);
        EmitI32(0); EmitI32(0);                      { 8-byte literal (patched) }
      end;

    IR_CONST_STR:
      begin
        sVal := GetTokenStrFromRaw(IRA[node], IRB[node]);
        si := InternStr(sVal);
        EmitLoadDataRefA64(0, Strs[si].Offset);  { x0 = [len][data] struct addr }
      end;

    IR_CONST_DATA:
      { Absolute data address (sentinel-resolvable), see the x86-64 case. }
      EmitLoadDataRefA64(0, Integer(IRIVal[node]));

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
        { base[index]: addr = base + (index - lo) * elemSize. For managed
          strings in write position, clone-if-shared before returning the byte
          address. Dynamic arrays use the handle loaded by IR_LEA. }
        left := IRA[node];
        IREmitNodeAarch64(left);                 { base -> x0 }
        if (InLValueWrite and (IRKind[left] = IR_LEA) and
            Syms[IRA[left]].IsArray and (Syms[IRA[left]].ArrLen = -1)) then
        begin
          { Indexing INTO a dynamic-array symbol during a write (`g[i] := x`,
            or the base level of a nested SetLength(a[i], n)): the write-mode
            IR_LEA branch (added for a SetLength target that IS the array
            symbol itself) leaves x0 one deref short of the data pointer --
            correct for THAT caller, but indexing always needs to read the
            array's own handle to use as a base; the real write happens at the
            computed element address further down. Deref once more (v1: no
            COW here either, matching the rest of this backend). }
          EmitI32($F9400000);                     { ldr x0, [x0] = data ptr }
        end
        else if ((IRKind[left] = IR_LEA) and (Syms[IRA[left]].TypeKind = tyAnsiString) and
            not Syms[IRA[left]].IsArray) or
           (((IRKind[left] = IR_FIELD) or (IRKind[left] = IR_INDEX)) and
            (IRTk[left] = Ord(tyAnsiString)) and (Integer(IRIVal[node]) = 1)) then
        begin
          if InLValueWrite then
          begin
            procIdx := FindProc('PXXStrUnique');
            if procIdx < 0 then Error('compiler error: PXXStrUnique not found');
            EmitCallProc(procIdx);                    { x0 = unique handle }
          end
          else if (IRKind[left] = IR_LEA) and (Syms[IRA[left]].Kind = skParam) and
                  Syms[IRA[left]].IsRef then
            EmitI32($F9400000)                   { ldr x0, [x0] (&handle -> handle) }
          else if (IRKind[left] = IR_FIELD) or (IRKind[left] = IR_INDEX) then
            EmitI32($F9400000);                  { ldr x0, [x0] = handle }
        end;
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
        tk := IntToTypeKind(IRTk[node]);
        if tk = tySingle then
        begin
          IREmitNodeAarch64(IRA[node]); { address -> x0 }
          EmitI32($B9400000);  { ldr w0, [x0] }
          EmitI32($1E270000);  { fmov s0, w0 }
          EmitI32($1E22C000);  { fcvt d0, s0 }
          EmitI32($9E660000);  { fmov x0, d0 }
          Exit;
        end;
        if (tk = tyDouble) or (tk = tyExtended) then
        begin
          IREmitNodeAarch64(IRA[node]); { address -> x0 }
          EmitI32($F9400000);  { ldr x0, [x0] }
          Exit;
        end;
        
        IREmitNodeAarch64(IRA[node]); { address -> x0 }
        if (tk = tyString) or (tk = tyFixedString) or (tk = tyShortString) then
        begin
          { A frozen/inline-string value IS its buffer address. Deref'ing a
            pointer-to-frozen-string (e.g. typinfo NamePtr^) yields that address
            — a pointer-width load, not a TypeSize(tyString)=8 load (which would
            be wrong on 32-bit). bug-cross-gate-masked-failures. }
          EmitI32($F9400000);          { ldr x0, [x0] (pointer width) }
          Exit;
        end;
        if not (TypeIsOrdinal(tk) or (tk = tyBoolean) or (tk = tyPointer) or
                (tk = tyChar) or (tk = tyUnknown) or
                (tk = tyAnsiString) or (tk = tyClass) or (tk = tyRecord)) then
          Error('target aarch64: load through pointer of this type not yet supported');
        { A small (<=8-byte) by-value record argument loads its packed bytes into
          x0 (TypeSize(tyRecord)=8 -> the sz=8 ldr below), mirroring x86-64 — lets
          a record temporary cross as a by-value arg (bug-aarch64-arm32-record-
          temp-byvalue-arg). }
        sz := TypeSize(tk);
        sgn := TypeSigned(tk);
        if sz = 1 then
        begin
          if sgn then EmitI32($39800000) else EmitI32($39400000); { ldrsb x0 (64-bit sign-ext) / ldrb w0, [x0] }
        end
        else if sz = 2 then
        begin
          if sgn then EmitI32($79800000) else EmitI32($79400000); { ldrsh x0 (64-bit sign-ext) / ldrh }
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
        if tk = tyString then
        begin
          { Frozen inline-string store through a pointer (PString(p)^ := s): copy
            the 8-byte length prefix, then the `length` chars. Mirrors i386. }
          valNode := IRB[node];
          IREmitNodeAarch64(valNode);              { x0 = source string addr }
          EmitI32($F81F0FE0);                      { str x0, [sp,#-16]! (push src) }
          savedLValueWrite := InLValueWrite;
          InLValueWrite := True;
          IREmitNodeAarch64(IRA[node]);            { x0 = dest addr }
          InLValueWrite := savedLValueWrite;
          EmitI32($AA0003E6);                      { mov x6, x0 (dst) }
          EmitI32($F84107E5);                      { ldr x5, [sp],#16 (src) }
          if IntToTypeKind(IRTk[valNode]) = tyChar then
            Error('target aarch64: char-to-inline-string store through pointer not yet supported');
          EmitI32($F94000A9);                      { ldr x9, [x5] (len prefix) }
          EmitI32($F90000C9);                      { str x9, [x6] }
          EmitI32($AA0903E4);                      { mov x4, x9 (count) }
          EmitI32($910020A5);                      { add x5, x5, #8 }
          EmitI32($910020C6);                      { add x6, x6, #8 }
          EmitA64CopyBytes(4, 5, 6);
          Exit;
        end;
        if tk = tyAnsiString then
        begin
          { Managed-string store through an address (field/slot): publish new,
            release old. }
          valNode := IRB[node];
          EmitAnsiStringFromNodeA64(valNode);   { x0 = new (retained) }
          EmitI32($F81F0FE0);                   { str x0, [sp, #-16]! (new) }
          savedLValueWrite := InLValueWrite;
          InLValueWrite := True;
          IREmitNodeAarch64(IRA[node]);         { x0 = slot address }
          InLValueWrite := savedLValueWrite;
          EmitI32($AA0003E1);                   { mov x1, x0 }
          EmitI32($F9400020);                   { ldr x0, [x1] old }
          EmitI32($F94003E2);                   { ldr x2, [sp] new }
          EmitI32($F9000022);                   { str x2, [x1] }
          EmitStrDecRefA64;                     { release old }
          EmitI32($910043FF);                   { add sp, sp, #16 }
          Exit;
        end;
        if tk = tySingle then
        begin
          IREmitNodeAarch64(IRB[node]); { value -> x0 }
          EmitI32($F81F0FE0);           { str x0, [sp, #-16]! }
          savedLValueWrite := InLValueWrite;
          InLValueWrite := True;
          IREmitNodeAarch64(IRA[node]); { address -> x0 }
          InLValueWrite := savedLValueWrite;
          EmitI32($F84107E1);           { ldr x1, [sp], #16 (value) }
          { An integer value into a Single slot must be int->double converted
            (scvtf) first; a float value is already double bits (fmov). Then
            narrow to single. Without the int case, `s.a := 10` reinterpreted the
            int as double bits -> ~0 (bug-single-field-element-in-aggregate). }
          if TypeIsFloat(IntToTypeKind(IRTk[IRB[node]])) then
            EmitI32($9E670020)          { fmov d0, x1 }
          else
            EmitI32($9E620020);         { scvtf d0, x1 (int -> double) }
          EmitI32($1E624000);           { fcvt s0, d0 }
          EmitI32($1E260001);           { fmov w1, s0 }
          EmitI32($B9000001);           { str w1, [x0] }
          Exit;
        end;
        if (tk = tyDouble) or (tk = tyExtended) then
        begin
          IREmitNodeAarch64(IRB[node]); { value -> x0 }
          EmitI32($F81F0FE0);           { str x0, [sp, #-16]! }
          savedLValueWrite := InLValueWrite;
          InLValueWrite := True;
          IREmitNodeAarch64(IRA[node]); { address -> x0 }
          InLValueWrite := savedLValueWrite;
          EmitI32($F84107E1);           { ldr x1, [sp], #16 (value) }
          { An integer value into a Double slot must be int->double converted
            (scvtf); a float value is already double bits. `d.a := 10` otherwise
            stored the raw integer (bug-single-field-element-in-aggregate). }
          if not TypeIsFloat(IntToTypeKind(IRTk[IRB[node]])) then
          begin
            EmitI32($9E620020);         { scvtf d0, x1 (int -> double) }
            EmitI32($9E660001);         { fmov x1, d0 }
          end;
          EmitI32($F9000001);           { str x1, [x0] }
          Exit;
        end;
        if not (TypeIsOrdinal(tk) or (tk = tyBoolean) or (tk = tyPointer) or
                (tk = tyChar) or (tk = tyClass) or (tk = tyUnknown)) then
          Error('target aarch64: store through pointer of this type not yet supported');
        IREmitNodeAarch64(IRB[node]); { value -> x0 }
        EmitI32($F81F0FE0);           { str x0, [sp, #-16]! }
        savedLValueWrite := InLValueWrite;
        InLValueWrite := True;
        IREmitNodeAarch64(IRA[node]); { address -> x0 }
        InLValueWrite := savedLValueWrite;
        EmitI32($F84107E1);           { ldr x1, [sp], #16 (value) }
        { C double->int: a float RHS (bits in x1) into an integer field/element
          truncates (fcvtzs). Mirrors IR_STORE_SYM. }
        if CProgramMode and TypeIsFloat(IntToTypeKind(IRTk[IRB[node]])) then
        begin
          EmitI32($9E670020);         { fmov d0, x1 }
          EmitI32($9E780001);         { fcvtzs x1, d0 }
        end;
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
        procIdx := FindProc('PXXMemMove');
        if procIdx < 0 then Error('compiler error: PXXMemMove not found');
        EmitCallProc(procIdx);
      end;

    IR_COPY_REC_MANAGED:
      begin
        { ARC record copy: retain src, release dest, then move. }
        IREmitNodeAarch64(IRB[node]);          { x0 = src }
        EmitI32($F81F0FE0);                    { str x0, [sp,#-16]! (src @ [sp+16]) }
        IREmitNodeAarch64(IRA[node]);          { x0 = dest }
        EmitI32($F81F0FE0);                    { str x0, [sp,#-16]! (dest @ [sp]) }
        procIdx := FindProc('PXXRecordRetain');
        if procIdx < 0 then Error('compiler error: PXXRecordRetain not found');
        EmitI32($F9400BE0);                    { ldr x0, [sp,#16] (src) }
        EmitLoadDataRefA64(1, -(RECORD_RTTI_DATAREF_BASE + (IRC[node] - REC_UCLASS_BASE)));
        EmitCallProc(procIdx);
        procIdx := FindProc('PXXRecordRelease');
        if procIdx < 0 then Error('compiler error: PXXRecordRelease not found');
        EmitI32($F94003E0);                    { ldr x0, [sp] (dest) }
        EmitLoadDataRefA64(1, -(RECORD_RTTI_DATAREF_BASE + (IRC[node] - REC_UCLASS_BASE)));
        EmitCallProc(procIdx);
        procIdx := FindProc('PXXMemMove');
        if procIdx < 0 then Error('compiler error: PXXMemMove not found');
        EmitI32($F94003E0);                    { ldr x0, [sp] (dest) }
        EmitI32($F9400BE1);                    { ldr x1, [sp,#16] (src) }
        EmitLoadImmA64(2, IRIVal[node]);       { x2 = count }
        EmitCallProc(procIdx);
        EmitI32($910083FF);                    { add sp, sp, #32 }
      end;

    IR_DEFAULT_MEM:
      begin
        IREmitNodeAarch64(IRA[node]);          { x0 = dest }
        if (IRC[node] >= 0) and RecordHasManagedFields(IRC[node]) then
        begin
          EmitI32($F81F0FE0);                  { str x0, [sp,#-16]! (dest) }
          procIdx := FindProc('PXXRecordRelease');
          if procIdx < 0 then Error('compiler error: PXXRecordRelease not found');
          EmitI32($F94003E0);                  { ldr x0, [sp] (dest) }
          EmitLoadDataRefA64(1, -(RECORD_RTTI_DATAREF_BASE + (IRC[node] - REC_UCLASS_BASE)));
          EmitCallProc(procIdx);
          procIdx := FindProc('PXXMemZero');
          if procIdx < 0 then Error('compiler error: PXXMemZero not found');
          EmitI32($F94003E0);                  { ldr x0, [sp] (dest) }
          EmitLoadImmA64(1, IRIVal[node]);     { x1 = count }
          EmitCallProc(procIdx);
          EmitI32($910043FF);                  { add sp, sp, #16 }
        end
        else
        begin
          procIdx := FindProc('PXXMemZero');
          if procIdx < 0 then Error('compiler error: PXXMemZero not found');
          EmitLoadImmA64(1, IRIVal[node]);     { x1 = count }
          EmitCallProc(procIdx);
        end;
      end;

    IR_CLASSREF:
      EmitLoadDataRefA64(0, -(CLASSREF_DATAREF_BASE + IRA[node])); { x0 = class RTTI blob addr }

    IR_VMTADDR:
      EmitLoadDataRefA64(0, UClsVMTOffset[IRA[node]]); { x0 = class VMT addr (is/as identity) }

    IR_IMTADDR:
      EmitLoadDataRefA64(0, IMTOff[IRA[node]]); { x0 = interface method table addr }

    IR_SET_LIT:
      EmitLoadDataRefA64(0, IRIVal[node]);   { x0 = set-literal blob addr }

    IR_SET_COPY:
      begin
        { Copy 32-byte set from src (IRB) to dest (IRA). }
        IREmitNodeAarch64(IRB[node]);            { x0 = source addr }
        EmitI32($F81F0FE0);                      { str x0, [sp,#-16]! }
        IREmitNodeAarch64(IRA[node]);            { x0 = dest addr }
        EmitI32($AA0003E6);                      { mov x6, x0 (dst) }
        EmitI32($F84107E5);                      { ldr x5, [sp],#16 (src) }
        EmitI32($D2800404);                      { mov x4, #32 }
        EmitA64CopyBytes(4, 5, 6);
      end;

    IR_SET_BINOP:
      begin
        { Set +/-/* over 4 qwords into the BSS scratch (IRIVal). }
        IREmitNodeAarch64(IRA[node]);            { x0 = lhs addr }
        EmitI32($F81F0FE0);                      { str x0, [sp,#-16]! }
        IREmitNodeAarch64(IRB[node]);            { x0 = rhs addr }
        EmitI32($AA0003E2);                      { mov x2, x0 (rhs) }
        EmitI32($F84107E1);                      { ldr x1, [sp],#16 (lhs) }
        EmitI32($18000043);                      { ldr w3, [pc+8] (scratch addr) }
        EmitI32($14000002);                      { b .+8 }
        EmitGlobRef(IRIVal[node]);
        for i := 0 to 3 do
        begin
          EmitI32($F9400024 or (i * 1024));      { ldr x4, [x1, #i*8] }
          EmitI32($F9400045 or (i * 1024));      { ldr x5, [x2, #i*8] }
          if IntToTokenKind(IRC[node]) = tkPlus then EmitI32($AA050084)   { orr x4,x4,x5 }
          else if IntToTokenKind(IRC[node]) = tkStar then EmitI32($8A050084) { and x4,x4,x5 }
          else if IntToTokenKind(IRC[node]) = tkMinus then EmitI32($8A250084); { bic x4,x4,x5 }
          EmitI32($F9000064 or (i * 1024));      { str x4, [x3, #i*8] }
        end;
        EmitI32($AA0303E0);                      { mov x0, x3 (result addr) }
      end;

    IR_SET_CMP:
      begin
        { Compare two 32-byte sets (4 qwords). x7 = differences, x9 = subset
          violations. }
        IREmitNodeAarch64(IRA[node]);            { x0 = lhs addr }
        EmitI32($F81F0FE0);                      { str x0, [sp,#-16]! }
        IREmitNodeAarch64(IRB[node]);            { x0 = rhs addr }
        EmitI32($AA0003E2);                      { mov x2, x0 (rhs) }
        EmitI32($F84107E1);                      { ldr x1, [sp],#16 (lhs) }
        EmitI32($D2800007);                      { mov x7, #0 (differences) }
        EmitI32($D2800009);                      { mov x9, #0 (violations) }
        for i := 0 to 3 do
        begin
          EmitI32($F9400024 or (i * 1024));      { ldr x4, [x1, #i*8] (lhs) }
          EmitI32($F9400045 or (i * 1024));      { ldr x5, [x2, #i*8] (rhs) }
          EmitI32($CA050086);                    { eor x6, x4, x5 }
          EmitI32($AA0600E7);                    { orr x7, x7, x6 }
          if (IRC[node] = Ord(tkLe)) or (IRC[node] = Ord(tkLt)) then
          begin
            EmitI32($8A250088);                  { bic x8, x4, x5 (lhs and not rhs) }
            EmitI32($AA080129);                  { orr x9, x9, x8 }
          end
          else if (IRC[node] = Ord(tkGe)) or (IRC[node] = Ord(tkGt)) then
          begin
            EmitI32($8A2400A8);                  { bic x8, x5, x4 (rhs and not lhs) }
            EmitI32($AA080129);                  { orr x9, x9, x8 }
          end;
        end;
        if IRC[node] = Ord(tkEq) then
        begin
          EmitI32($F10000FF);                    { cmp x7, #0 }
          EmitI32($9A9F17E0);                    { cset x0, eq }
        end
        else if IRC[node] = Ord(tkNeq) then
        begin
          EmitI32($F10000FF);                    { cmp x7, #0 }
          EmitI32($9A9F07E0);                    { cset x0, ne }
        end
        else if (IRC[node] = Ord(tkLe)) or (IRC[node] = Ord(tkGe)) then
        begin
          EmitI32($F100013F);                    { cmp x9, #0 }
          EmitI32($9A9F17E0);                    { cset x0, eq }
        end
        else { tkLt / tkGt: proper = subset AND unequal }
        begin
          EmitI32($F100013F);                    { cmp x9, #0 }
          EmitI32($9A9F17E0);                    { cset x0, eq }
          EmitI32($F10000FF);                    { cmp x7, #0 }
          EmitI32($9A9F07E1);                    { cset x1, ne }
          EmitI32($8A010000);                    { and x0, x0, x1 }
        end;
      end;

    IR_RTTI_REG:
      EmitLoadDataRefA64(0, -100);     { x0 = RTTI-registry addr (sentinel) }

    IR_RESOURCES:
      EmitLoadDataRefA64(0, -101);     { x0 = resource-table addr (sentinel) }

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

    IR_CLONE:
      begin
        { __pxxclone(flags, childStack, entry, arg, ctidptr): evaluate the five
          args left-to-right onto the stack, pop into x0..x4 (the clone stub's
          input contract: x0=flags x1=childStack x2=entry x3=arg x4=ctidptr),
          then bl the bare clone+trampoline stub. Child tid stays in x0. Stub is
          emitted lazily the first time we reach here. }
        EnsureCloneStub;
        argNode := IRA[node]; nArgs := 0;
        while argNode <> -1 do
        begin
          IREmitNodeAarch64(IRA[argNode]);
          EmitI32($F81F0FE0);           { str x0, [sp, #-16]! }
          Inc(nArgs);
          argNode := IRB[argNode];
        end;
        for i := nArgs - 1 downto 0 do
          EmitI32($F84107E0 + i);       { ldr x[i], [sp], #16  (i=4..0) }
        EmitI32($94000000 or (((CloneStubAddr - CodeLen) div 4) and $03FFFFFF)); { bl stub }
      end;

    IR_ATOMIC:
      begin
        { Atomic read-modify-write on addr^, returning the OLD value, via an
          LL/SC (ldxr/stxr) retry loop. Args pushed left-to-right; popped into
          x1=addr (+ x2=val/expected, x3=newval). Result (old) in x0. Encodings
          + branch offsets verified against aarch64-linux-gnu-as. }
        argNode := IRA[node]; nArgs := 0;
        while argNode <> -1 do
        begin
          IREmitNodeAarch64(IRA[argNode]);
          EmitI32($F81F0FE0);           { str x0, [sp, #-16]! }
          Inc(nArgs);
          argNode := IRB[argNode];
        end;
        case IRIVal[node] of
          ATOMIC_CAS:
            begin
              EmitI32($F84107E3);       { ldr x3, [sp], #16  newval }
              EmitI32($F84107E2);       { ldr x2, [sp], #16  expected }
              EmitI32($F84107E1);       { ldr x1, [sp], #16  addr }
              EmitI32($885F7C20);       { ldxr w0, [x1]      old }
              EmitI32($6B02001F);       { cmp  w0, w2 }
              EmitI32($54000061);       { b.ne +3 (done) }
              EmitI32($88047C23);       { stxr w4, w3, [x1] }
              EmitI32($35FFFF84);       { cbnz w4, -4 (retry) }
            end;
          ATOMIC_CAS64:
            begin
              EmitI32($F84107E3);       { ldr x3, [sp], #16 }
              EmitI32($F84107E2);       { ldr x2, [sp], #16 }
              EmitI32($F84107E1);       { ldr x1, [sp], #16 }
              EmitI32($C85F7C20);       { ldxr x0, [x1] }
              EmitI32($EB02001F);       { cmp  x0, x2 }
              EmitI32($54000061);       { b.ne +3 }
              EmitI32($C8047C23);       { stxr w4, x3, [x1] }
              EmitI32($35FFFF84);       { cbnz w4, -4 }
            end;
          ATOMIC_ADD:
            begin
              EmitI32($F84107E2);       { ldr x2, [sp], #16  delta }
              EmitI32($F84107E1);       { ldr x1, [sp], #16  addr }
              EmitI32($885F7C20);       { ldxr w0, [x1]      old }
              EmitI32($0B020004);       { add  w4, w0, w2 }
              EmitI32($88037C24);       { stxr w3, w4, [x1] }
              EmitI32($35FFFFA3);       { cbnz w3, -3 }
            end;
          ATOMIC_ADD64:
            begin
              EmitI32($F84107E2);       { ldr x2, [sp], #16 }
              EmitI32($F84107E1);       { ldr x1, [sp], #16 }
              EmitI32($C85F7C20);       { ldxr x0, [x1] }
              EmitI32($8B020004);       { add  x4, x0, x2 }
              EmitI32($C8037C24);       { stxr w3, x4, [x1] }
              EmitI32($35FFFFA3);       { cbnz w3, -3 }
            end;
          ATOMIC_XCHG64:
            begin
              EmitI32($F84107E2);       { ldr x2, [sp], #16  val }
              EmitI32($F84107E1);       { ldr x1, [sp], #16  addr }
              EmitI32($C85F7C20);       { ldxr x0, [x1] }
              EmitI32($C8037C22);       { stxr w3, x2, [x1] }
              EmitI32($35FFFFC3);       { cbnz w3, -2 }
            end;
          else { ATOMIC_XCHG }
            begin
              EmitI32($F84107E2);       { ldr x2, [sp], #16  val }
              EmitI32($F84107E1);       { ldr x1, [sp], #16  addr }
              EmitI32($885F7C20);       { ldxr w0, [x1] }
              EmitI32($88037C22);       { stxr w3, w2, [x1] }
              EmitI32($35FFFFC3);       { cbnz w3, -2 }
            end;
        end;
      end;

    IR_NEG:
      begin
        IREmitNodeAarch64(IRA[node]);
        if TypeIsFloat(IntToTypeKind(IRTk[node])) then
        begin
          EmitLoadImmA64(1, Int64($8000000000000000));
          EmitI32($CA010000); { eor x0, x0, x1 }
        end
        else
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
        decs := IRC[node];   { decimals, -1 = none }
        if IntToTypeKind(IRTk[node]) = tyVariant then
        begin
          IREmitNodeAarch64(valNode);              { x0 = slot addr }
          procIdx := FindProc('PXXWriteVariant');
          if procIdx < 0 then Error('compiler error: PXXWriteVariant not found');
          EmitCallProc(procIdx);
        end
        else if TypeIsFloat(IntToTypeKind(IRTk[node])) then
        begin
          IREmitNodeAarch64(valNode);
          if decs = -2 then EmitWriteFloatNatA64
          else if decs >= 0 then EmitWriteFloatFixedA64(decs)
          else EmitWriteFloatSciA64;
        end
        else if decs = -3 then
        begin
          { write(PChar): runtime NUL-terminated C string (strlen + write). }
          IREmitNodeAarch64(valNode);
          EmitWriteCStrA64;
        end
        else if IRKind[valNode] = IR_CONST_STR then
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
          else if TypeIsOrdinal(tk) or (tk = tyUnknown) then
          begin
            IREmitNodeAarch64(valNode);
            if (tk <> tyUnknown) and not TypeSigned(tk) then
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
      
    IR_VAR_STORE:
      begin
        tk := IntToTypeKind(IRC[node]);
        if tk = tyVariant then
        begin
          IREmitNodeAarch64(IRB[node]);                 { x0 = src addr }
          EmitVariantRetainA64;
          EmitI32($F81F0FE0);                           { str x0, [sp, #-16]! }
          IREmitNodeAarch64(IRA[node]);                 { x0 = dest addr }
          EmitVariantClearA64;
          EmitI32($AA0003E1);                           { mov x1, x0 }
          EmitI32($F84107E0);                           { ldr x0, [sp], #16 }
          EmitI32($A9400C02);                           { ldp x2, x3, [x0] }
          EmitI32($A9000C22);                           { stp x2, x3, [x1] }
        end
        else
        begin
          case tk of
            tyInteger, tyInt8, tyInt16, tyInt32: sz := VT_INT;
            tyInt64, tyNativeInt:                sz := VT_INT64;
            tyUInt8, tyUInt16, tyUInt32, tyUInt64,
            tyNativeUInt, tyPointer:             sz := VT_INT64;
            tyBoolean:                           sz := VT_BOOL;
            tyChar:                              sz := VT_CHAR;
            tyDouble, tySingle, tyExtended:      sz := VT_DOUBLE;
            tyString, tyAnsiString:              sz := VT_STRING;
          else
            Error('Variant := this type not yet supported');
          end;
          
          if tk = tyString then
          begin
            IREmitNodeAarch64(IRB[node]);   { x0 = inline string buffer }
            EmitI32($AA0003E2);             { mov x2, x0 }
            EmitI32($F9400040);             { ldr x0, [x2] (len) }
            EmitI32($91002041);             { add x1, x2, #8 (src) }
            procIdx := FindProc('PXXStrFromLit');
            if procIdx < 0 then Error('compiler error: PXXStrFromLit not found');
            EmitCallProc(procIdx);               { x0 = new AnsiString }
          end
          else if tk = tyAnsiString then
          begin
            IREmitNodeAarch64(IRB[node]);   { x0 = handle }
            EmitStrIncRefA64;
          end
          else
          begin
            IREmitNodeAarch64(IRB[node]);   { x0 = scalar value }
            if (tk = tyInteger) or (tk = tyInt8) or (tk = tyInt16) or (tk = tyInt32) then
              EmitI32($93407C00);           { sxtw x0, w0 }
          end;
          
          EmitI32($F81F0FE0);               { str x0, [sp, #-16]! }
          IREmitNodeAarch64(IRA[node]);     { x0 = dest addr }
          EmitVariantClearA64;
          EmitI32($F84107E1);               { ldr x1, [sp], #16 }
          EmitLoadImmA64(2, sz);
          EmitI32($F9000002);               { str x2, [x0] (tag) }
          EmitI32($F9000401);               { str x1, [x0, #8] (payload) }
        end;
      end;

    IR_VAR_BOX:
      begin
        tk := IntToTypeKind(IRC[node]);
        case tk of
          tyInteger, tyInt8, tyInt16, tyInt32: sz := VT_INT;
          tyInt64, tyNativeInt:                sz := VT_INT64;
          tyUInt8, tyUInt16, tyUInt32, tyUInt64,
          tyNativeUInt, tyPointer:             sz := VT_INT64;
          tyBoolean:                           sz := VT_BOOL;
          tyChar:                              sz := VT_CHAR;
          tyDouble, tySingle, tyExtended:      sz := VT_DOUBLE;
          tyString, tyAnsiString:              sz := VT_STRING;
        else
          Error('Variant operand: this scalar type not yet supported');
        end;

        if tk = tyString then
        begin
          IREmitNodeAarch64(IRB[node]);   { x0 = inline string buffer }
          EmitI32($AA0003E2);             { mov x2, x0 }
          EmitI32($F9400040);             { ldr x0, [x2] (len) }
          EmitI32($91002041);             { add x1, x2, #8 (src) }
          procIdx := FindProc('PXXStrFromLit');
          if procIdx < 0 then Error('compiler error: PXXStrFromLit not found');
          EmitCallProc(procIdx);               { x0 = new AnsiString }
        end
        else if tk = tyAnsiString then
        begin
          IREmitNodeAarch64(IRB[node]);   { x0 = handle }
          EmitStrIncRefA64;
        end
        else
        begin
          IREmitNodeAarch64(IRB[node]);   { x0 = scalar value }
          if (tk = tyInteger) or (tk = tyInt8) or (tk = tyInt16) or (tk = tyInt32) then
            EmitI32($93407C00);           { sxtw x0, w0 }
        end;

        EmitI32($F81F0FE0);               { str x0, [sp, #-16]! }
        IREmitNodeAarch64(IRA[node]);     { x0 = temp addr }
        EmitVariantClearA64;
        EmitI32($F84107E1);               { ldr x1, [sp], #16 }
        EmitLoadImmA64(2, sz);
        EmitI32($F9000002);               { str x2, [x0] (tag) }
        EmitI32($F9000401);               { str x1, [x0, #8] (payload) }
      end;

    IR_VAR_BINOP:
      begin
        isComp := IntToTypeKind(IRTk[node]) = tyBoolean;
        IREmitNodeAarch64(IRA[node]);                 { x0 = left addr }
        EmitI32($F81F0FE0);                           { str x0, [sp, #-16]! }
        IREmitNodeAarch64(IRB[node]);                 { x0 = right addr }
        EmitI32($AA0003E2);                           { mov x2, x0 (right) }
        EmitI32($F84107E1);                           { ldr x1, [sp], #16 (left) }
        
        if isComp then
          EmitLoadImmA64(0, 0)
        else
          EmitLoadGlobAddrA64(0, Integer(IRIVal[node]));
          
        EmitLoadImmA64(3, IRC[node]);
        if isComp then
          EmitLoadImmA64(4, 1)
        else
          EmitLoadImmA64(4, 0);
          
        procIdx := FindProc('PXXVarBinOp');
        if procIdx < 0 then Error('compiler error: PXXVarBinOp not found');
        EmitCallProc(procIdx);
      end;

    else
      Error('target aarch64: IR op not yet supported: ' + IROpName(IRKind[node]));
  end;
end;

procedure IREmitMachineCodeAarch64;
var i, lblId, pos, targetOffset, f, si, classIdx, procIdx: Integer;
    LabelFixupCount: Integer;
begin
  { Clear only this body's labels ([0, IRLabelCount) — see IREmitMachineCode). }
  for i := 0 to IRLabelCount - 1 do
    LabelPositions[i] := -1;
  LabelFixupCount := 0;

  { Nil-init hidden owning locals synthesised for materialised managed-string
    arguments (and the TVarRec array temp behind `array of const`). They are
    created during this body's IR lowering, after the parser's prologue
    zero-init pass, so they otherwise hold stale stack bytes — a conditional
    build / scope-exit cleanup would then read or DecRef garbage. skLocal only;
    main-program temps are skGlobal (BSS). Mirrors x86-64/i386/ARM32. }
  if CurProc >= 0 then
    for i := Procs[CurProc].ScopeBase to SymCount - 1 do
      if SymIsHiddenArgTemp[i] and (Syms[i].Kind = skLocal) then
      begin
        if (Syms[i].TypeKind = tyRecord) and not Syms[i].IsArray and
           (RecSize(Syms[i].RecName) > TARGET_PTR_SIZE) then
        begin
          { Managed-record temp: zero the full record (PXXMemZero) so every
            managed field starts nil, not just the first pointer-sized slot. }
          EmitLoadImmA64(9, Syms[i].Offset);
          EmitI32($8B0903A0);    { add x0, x29, x9 (dest) }
          EmitLoadImmA64(1, RecSize(Syms[i].RecName));   { x1 = count }
          procIdx := FindProc('PXXMemZero');
          if procIdx < 0 then Error('compiler error: PXXMemZero not found');
          EmitCallProc(procIdx);
        end
        else
        begin
          EmitI32($D2800000);    { movz x0, #0 }
          EmitStoreVarA64(i);    { store 0 into the local slot }
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
            EmitAsmA64(['b %', LabelPositions[lblId] - CodeLen])
          else
          begin
            if LabelFixupCount >= MAX_IR then Error('label fixup overflow');
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitAsmA64('b 0');
          end;
        end;

      IR_JUMP_IF_FALSE:
        begin
          lblId := IRA[i];
          IREmitNodeAarch64(IRB[i]); { condition -> x0 }
          if LabelPositions[lblId] <> -1 then
            EmitAsmA64(['cbz x0, %', LabelPositions[lblId] - CodeLen])
          else
          begin
            if LabelFixupCount >= MAX_IR then Error('label fixup overflow');
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitAsmA64('cbz x0, 0');
          end;
        end;

      IR_CALL:
        begin
          if IRIVal[i] = 1 then
            IREmitNodeAarch64(i);
        end;

      IR_CALL_IND:
        begin
          if IRStmtRoot[i] then
            IREmitNodeAarch64(i);
        end;

      IR_VIRTUAL_CALL:
        begin
          if IRStmtRoot[i] then
            IREmitNodeAarch64(i);
        end;

      IR_EXC_ENTER:
        begin
          lblId := IRA[i];
          EmitI32($D10203FF);                                         { sub sp, sp, #128 }
          EmitI32($18000041);                                         { ldr w1, [pc+8] }
          EmitI32($14000002);                                         { b [pc+8] }
          EmitGlobRef(BSS_EXC_TOP);
          EmitI32($F9400022);                                         { ldr x2, [x1] }
          EmitI32($F90003E2);                                         { str x2, [sp] }
          EmitI32($910003E2);                                         { mov x2, sp }
          EmitI32($F9000022);                                         { str x2, [x1] }
          EmitI32($910043E0);                                         { add x0, sp, #16 }
          EmitI32($94000000 or (((ExcSetJmpAddr - CodeLen) div 4) and $03ffffff)); { bl ExcSetJmpAddr }
          if LabelPositions[lblId] <> -1 then
            EmitI32($B5000000 or ((((LabelPositions[lblId] - CodeLen) div 4) and $7ffff) shl 5)) { cbnz x0, label }
          else
          begin
            if LabelFixupCount >= MAX_IR then Error('label fixup overflow');
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitI32($B5000000);
          end;
        end;

      IR_EXC_LEAVE:
        begin
          IREmitLeaveExceptionFramesAarch64(IRA[i]);
        end;

      IR_RAISE:
        begin
          if IRA[i] <> -1 then
          begin
            IREmitNodeAarch64(IRA[i]);                                { result in x0 }
            EmitI32($18000041);                                       { ldr w1, [pc+8] }
            EmitI32($14000002);                                       { b [pc+8] }
            EmitGlobRef(BSS_EXC_OBJ);
            EmitI32($F9000020);                                       { str x0, [x1] }
            classIdx := Integer(IRIVal[i]);
            EmitLoadImmA64(0, classIdx);                              { x0 = classIdx }
            EmitI32($18000041);                                       { ldr w1, [pc+8] }
            EmitI32($14000002);                                       { b [pc+8] }
            EmitGlobRef(BSS_EXC_CLS);
            EmitI32($F9000020);                                       { str x0, [x1] }
          end;
          EmitI32($94000000 or (((ExcRaiseAddr - CodeLen) div 4) and $03ffffff)); { bl ExcRaiseAddr }
        end;

      IR_EXC_STORE:
        begin
          si := IRA[i];
          EmitI32($18000041);                                         { ldr w1, [pc+8] }
          EmitI32($14000002);                                         { b [pc+8] }
          EmitGlobRef(BSS_EXC_OBJ);
          EmitI32($F9400020);                                         { ldr x0, [x1] }
          EmitStoreVarA64(si);
        end;

      IR_EXC_MATCH:
        begin
          lblId := IRA[i];
          EmitI32($18000041);                                         { ldr w1, [pc+8] }
          EmitI32($14000002);                                         { b [pc+8] }
          EmitGlobRef(BSS_EXC_CLS);
          EmitI32($F9400020);                                         { ldr x0, [x1] }
          EmitLoadImmA64(1, Integer(IRIVal[i]));                      { x1 = expected }
          EmitI32($EB01001F);                                         { cmp x0, x1 (subs xzr, x0, x1) }
          if LabelPositions[lblId] <> -1 then
            EmitI32($54000001 or ((((LabelPositions[lblId] - CodeLen) div 4) and $7ffff) shl 5)) { b.ne label }
          else
          begin
            if LabelFixupCount >= MAX_IR then Error('label fixup overflow');
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitI32($54000001);
          end;
        end;

      IR_EXC_MATCH_HIT:
        begin
          lblId := IRA[i];
          EmitI32($18000041);                                         { ldr w1, [pc+8] }
          EmitI32($14000002);                                         { b [pc+8] }
          EmitGlobRef(BSS_EXC_CLS);
          EmitI32($F9400020);                                         { ldr x0, [x1] }
          EmitLoadImmA64(1, Integer(IRIVal[i]));                      { x1 = expected }
          EmitI32($EB01001F);                                         { cmp x0, x1 (subs xzr, x0, x1) }
          if LabelPositions[lblId] <> -1 then
            EmitI32($54000000 or ((((LabelPositions[lblId] - CodeLen) div 4) and $7ffff) shl 5)) { b.eq label }
          else
          begin
            if LabelFixupCount >= MAX_IR then Error('label fixup overflow');
            LabelFixupPos[LabelFixupCount] := CodeLen;
            LabelFixupTarget[LabelFixupCount] := lblId;
            Inc(LabelFixupCount);
            EmitI32($54000000);
          end;
        end;

      IR_EXC_CLEAR:
        begin
          EmitI32($D2800000);                                         { movz x0, #0 }
          EmitI32($18000041);                                         { ldr w1, [pc+8] }
          EmitI32($14000002);                                         { b [pc+8] }
          EmitGlobRef(BSS_EXC_OBJ);
          EmitI32($F9000020);                                         { str x0, [x1] }
          EmitI32($18000041);                                         { ldr w1, [pc+8] }
          EmitI32($14000002);                                         { b [pc+8] }
          EmitGlobRef(BSS_EXC_CLS);
          EmitI32($F9000020);                                         { str x0, [x1] }
        end;

      IR_STORE_SYM, IR_WRITE, IR_WRITELN:
        IREmitNodeAarch64(i);

      IR_IO_LOCK:
        EmitI32($94000000 or (((IOLockAddr - CodeLen) div 4) and $03FFFFFF));   { bl io-lock stub }

      IR_IO_UNLOCK:
        EmitI32($94000000 or (((IOUnlockAddr - CodeLen) div 4) and $03FFFFFF)); { bl io-unlock stub }

      IR_NOP, IR_CONST_STR, IR_CONST_INT, IR_BLOCK,
      IR_LOAD_SYM, IR_LOAD_MEM, IR_BINOP, IR_NEG, IR_NOT, IR_ARG, IR_LEA, IR_SYSCALL,
      IR_SET_LIT, IR_SET_BINOP, IR_SET_CMP, IR_CONST_DATA,
      IR_SLOTADDR, IR_DYNUNIQUE,
      IR_FIELD, IR_INDEX, IR_VAR_BOX, IR_VAR_BINOP,
      IR_ATOMIC, IR_CLONE: ;
      { IR_ATOMIC / IR_CLONE are value nodes (return old value / child tid) that
        their parent store_sym consumes — like IR_SYSCALL above. Emitting them at
        statement level too ran the read-modify-write / thread-spawn TWICE (the
        result store then re-evaluated the side-effecting node). }
      { IR_LOAD_MEM is a pure value node (a deref); like IR_LOAD_SYM it must NOT
        be emitted at statement level — doing so re-evaluates its address operand,
        so `*f()` (deref of a call result) called f twice, advancing va_arg's
        cursor an extra slot and breaking every variadic call. x86-64's driver has
        no statement-level catch-all, so it never had this bug. }

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
    else if Code[pos+3] = $B5 then
      Patch32(pos, $B5000000 or (((targetOffset - pos) div 4) and $7ffff) shl 5 or (Code[pos] and $1f))
    else if Code[pos+3] = $54 then
      Patch32(pos, $54000000 or (((targetOffset - pos) div 4) and $7ffff) shl 5 or (Code[pos] and $1f))
    else
      Error('target aarch64: invalid instruction at label fixup');
  end;
end;
