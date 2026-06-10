{ ===== Emitter ===== }

procedure EnsureSpaces; forward;
procedure EmitLoadImmArm32(rd: Integer; v: Int32); forward;
procedure EmitwriteSyscallArm32(dataOff, len: Integer); forward;

procedure EmitB(b: Byte); inline;
begin
  if CodeLen >= MAX_CODE then Error('code overflow');
  Code[CodeLen] := b; Inc(CodeLen);
end;

procedure EmitI32(v: Int64);
begin
  EmitB(Byte(v and $FF)); EmitB(Byte((v shr 8) and $FF));
  EmitB(Byte((v shr 16) and $FF)); EmitB(Byte((v shr 24) and $FF));
end;

procedure EmitI64(v: Int64);
begin EmitI32(v and $FFFFFFFF); EmitI32((v shr 32) and $FFFFFFFF); end;

procedure Patch32(pos: Integer; v: Int64);
begin
  Code[pos]   := Byte(v and $FF); Code[pos+1] := Byte((v shr 8) and $FF);
  Code[pos+2] := Byte((v shr 16) and $FF); Code[pos+3] := Byte((v shr 24) and $FF);
end;

procedure Patch8(pos: Integer; v: Byte);
begin
  Code[pos] := v;
end;

procedure MovRaxImm(v: Int64); begin EmitB($48); EmitB($B8); EmitI64(v); end;
procedure MovRbxImm(v: Int64); begin EmitB($48); EmitB($BB); EmitI64(v); end;
procedure MovRdiImm(v: Int64); begin EmitB($48); EmitB($BF); EmitI64(v); end;
procedure MovRsiImm(v: Int64); begin EmitB($48); EmitB($BE); EmitI64(v); end;
procedure MovRdxImm(v: Int64); begin EmitB($48); EmitB($BA); EmitI64(v); end;

procedure EmitSyscall; begin EmitB($0F); EmitB($05); end;

procedure EmitDataRef(dataOff: Integer);
{ Absolute data-address placeholder; width follows the target's pointer size
  (writeELF patches 8 bytes, writeELF32 patches 4). }
begin
  if FixCount >= MAX_FIXUPS then Error('fixup overflow');
  Fixups[FixCount].CodePos := CodeLen; Fixups[FixCount].DataOff := dataOff;
  Inc(FixCount);
  if (TargetArch = TARGET_I386) or (TargetArch = TARGET_ARM32) then EmitI32(0) else EmitI64(0);
end;

procedure EmitGlobRef(bssOff: Integer);
{ Emit 4-byte placeholder for absolute BSS address }
begin
  if GlobFixCount >= MAX_GLOBFIX then Error('global fixup overflow');
  GlobFix[GlobFixCount].CodePos := CodeLen;
  GlobFix[GlobFixCount].BSSoff  := bssOff;
  Inc(GlobFixCount); EmitI32(0);
end;

procedure EmitwriteSyscallA64(dataOff, len: Integer);
begin
  EmitI32($D2800808);  { movz x8, #64 }
  EmitI32($D2800020);  { movz x0, #1 }
  EmitI32($58000041);  { ldr x1, [pc+8] }
  EmitI32($14000003);  { b [pc+12] }
  EmitDataRef(dataOff);
  EmitI32($D2800002 + (len shl 5)); { movz x2, #len }
  EmitI32($D4000001);  { svc #0 }
end;

procedure EmitwriteSyscall(dataOff, len: Integer);
begin
  if TargetArch = TARGET_I386 then
  begin
    { i386 int 0x80 ABI: eax=4 (write), ebx=fd, ecx=buf, edx=len }
    EmitB($B8); EmitI32(4);
    EmitB($BB); EmitI32(STDOUT);
    EmitB($B9); EmitDataRef(dataOff);
    EmitB($BA); EmitI32(len);
    EmitB($CD); EmitB($80);
    Exit;
  end;
  if TargetArch = TARGET_ARM32 then
  begin
    EmitwriteSyscallArm32(dataOff, len);
    Exit;
  end;
  if TargetArch = TARGET_AARCH64 then
  begin
    EmitwriteSyscallA64(dataOff, len);
    Exit;
  end;
  MovRaxImm(SYS_WRITE); MovRdiImm(STDOUT);
  EmitB($48); EmitB($BE); EmitDataRef(dataOff);
  MovRdxImm(len); EmitSyscall;
end;

procedure EmitMmapArena;
{ Emit an anonymous mmap. Caller sets rsi = length; on return rax = base
  address. Clobbers rax, rcx, r11, rdi, rdx, r10, r8, r9 (mmap syscall ABI);
  rsi is preserved by the kernel. }
begin
  MovRdiImm(0);                          { addr = NULL }
  MovRdxImm(3);                          { PROT_READ | PROT_WRITE }
  EmitB($49); EmitB($BA); EmitI64($22);  { mov r10, MAP_PRIVATE|MAP_ANONYMOUS }
  EmitB($49); EmitB($B8); EmitI64(-1);   { mov r8, -1  (fd) }
  EmitB($49); EmitB($B9); EmitI64(0);    { mov r9, 0   (offset) }
  MovRaxImm(SYS_MMAP);
  EmitSyscall;
end;

procedure EmitExitA64(code: Int64);
begin
  EmitI32($D2800BC8);  { movz x8, #94 }
  EmitI32($D2800000 + (code shl 5)); { movz x0, #code }
  EmitI32($D4000001);  { svc #0 }
end;

procedure EmitExitArm32(code: Integer);
begin
  EmitI32($E3A070F8);  { mov r7, #248  (sys_exit_group) }
  EmitLoadImmArm32(0, code);
  EmitI32($EF000000);  { svc #0 }
end;

procedure EmitExit(code: Int64);
{ exit_group, not exit: terminate every thread. A bare exit (60) only ends
  the calling thread, so a program that started worker threads (e.g. via
  gtk_init / GLib) would leave the process alive after main returns. For a
  single-threaded program the two are equivalent. }
begin
  if TargetArch = TARGET_I386 then
  begin
    { i386 int 0x80 ABI: eax=252 (exit_group), ebx=code }
    EmitB($B8); EmitI32(252);
    EmitB($BB); EmitI32(code);
    EmitB($CD); EmitB($80);
    Exit;
  end;
  if TargetArch = TARGET_ARM32 then
  begin
    EmitExitArm32(code);
    Exit;
  end;
  if TargetArch = TARGET_AARCH64 then
  begin
    EmitExitA64(code);
    Exit;
  end;
  MovRaxImm(SYS_EXIT_GROUP); MovRdiImm(code); EmitSyscall;
end;

{ ===== String table ===== }

function InternStr(const s: AnsiString): Integer;
var i, j: Integer; len: Int64; match: Boolean;
begin
  for i := 0 to StrCount-1 do
  begin
    if Strs[i].Len = Length(s) then
    begin
      match := True;
      for j := 1 to Length(s) do
        if Strs[i].Text[j] <> s[j] then match := False;
      if match then begin Result := i; Exit; end;
    end;
  end;
  if StrCount >= MAX_STRS then Error('string table overflow');
  Strs[StrCount].Text   := s;
  Strs[StrCount].Offset := DataLen;
  Strs[StrCount].Len    := Length(s);
  
  { Write 8-byte length prefix }
  len := Length(s);
  for j := 0 to 7 do
  begin
    if DataLen >= MAX_DATA then Error('data overflow');
    Data[DataLen] := Byte((len shr (j * 8)) and $FF);
    Inc(DataLen);
  end;
  
  for j := 1 to Length(s) do
    begin if DataLen >= MAX_DATA then Error('data overflow'); Data[DataLen] := Ord(s[j]); Inc(DataLen); end;

  { Explicit NUL terminator after the chars so the char data at Offset+8 is a
    valid C string for PChar()/const char* interop. The alignment padding below
    used to supply this only incidentally (and not at all when the char count
    was already 8-aligned). }
  if DataLen >= MAX_DATA then Error('data overflow');
  Data[DataLen] := 0;
  Inc(DataLen);

  { Align to 8 bytes }
  while (DataLen mod 8) <> 0 do
  begin
    if DataLen >= MAX_DATA then Error('data overflow');
    Data[DataLen] := 0;
    Inc(DataLen);
  end;
  
  Result := StrCount; Inc(StrCount);
end;

procedure EmitLoadImmA64(rd: Integer; v: Int64);
begin
  if (v >= 0) and (v <= 65535) then
    EmitI32($D2800000 + (v shl 5) + rd)
  else
  begin
    { Fallback to PC-relative load }
    if (rd >= 0) and (rd <= 30) then
      EmitI32($58000040 + rd)  { ldr x[rd], [pc+8] }
    else
      Error('target aarch64: unsupported constant destination register');
    EmitI32($14000003);  { b [pc+12] }
    EmitI64(v);
  end;
end;

procedure EmitwriteCharA64;
begin
  { Load BSS_INTBUF address into w1 }
  EmitI32($18000041);  { ldr w1, [pc+8] }
  EmitI32($14000002);  { b [pc+8] }
  EmitGlobRef(BSS_INTBUF);
  { strb w0, [x1] }
  EmitI32($39000020);
  { Make syscall: write(1, x1, 1) }
  EmitI32($D2800808);  { movz x8, #64 }
  EmitI32($D2800020);  { movz x0, #1 }
  EmitI32($D2800022);  { movz x2, #1 }
  EmitI32($D4000001);  { svc #0 }
end;

procedure EmitwriteIntA64;
var jnsOff, loopStart: Integer;
begin
  { Test if x0 is positive }
  EmitI32($F100001F);  { cmp x0, #0 }
  { b.ge positive }
  jnsOff := CodeLen;
  EmitI32($5400000A);
  
  { Negative: print minus, then negate }
  EmitI32($CB0003E0);  { neg x0, x0 }
  
  { Save x0 on stack because we need to preserve it during write syscall }
  EmitI32($F81F0FE0);  { str x0, [sp, #-16]! }
  EmitwriteSyscallA64(MINUS_OFFSET, 1);
  EmitI32($F84107E0);  { ldr x0, [sp], #16 }
  
  { Patch the b.ge positive jump }
  Patch32(jnsOff, $5400000A or (((CodeLen - jnsOff) div 4) and $7ffff) shl 5);
  
  { EmitwriteUIntA64 logic starts here }
  EmitI32($D2800001);  { mov x1, #0  (digit count) }
  EmitI32($D2800142);  { mov x2, #10 }
  
  { Load BSS_INTBUF + INTBUF_SIZE into w3 }
  EmitI32($18000043);  { ldr w3, [pc+8] }
  EmitI32($14000002);  { b [pc+8] }
  EmitGlobRef(BSS_INTBUF + INTBUF_SIZE);
  
  loopStart := CodeLen;
  EmitI32($9AC20C04);  { sdiv x4, x0, x2 }
  EmitI32($9B028085);  { msub x5, x4, x2, x0 }
  EmitI32($AA0403E0);  { mov x0, x4 }
  EmitI32($9100C0A5);  { add x5, x5, #48 }
  EmitI32($D1000463);  { sub x3, x3, #1 }
  EmitI32($39000065);  { strb w5, [x3] }
  EmitI32($91000421);  { add x1, x1, #1 }
  
  EmitI32($F100001F);  { cmp x0, #0 }
  { b.ne loopStart }
  EmitI32($54000001 or (((loopStart - CodeLen) div 4) and $7ffff) shl 5);
  
  { Write syscall: write(1, x3, x1) }
  EmitI32($AA0103E2);  { mov x2, x1 }
  EmitI32($AA0303E1);  { mov x1, x3 }
  EmitI32($D2800020);  { mov x0, #1 }
  EmitI32($D2800808);  { mov x8, #64 }
  EmitI32($D4000001);  { svc #0 }
end;

procedure EmitwriteUIntA64;
var loopStart: Integer;
begin
  EmitI32($D2800001);  { mov x1, #0  (digit count) }
  EmitI32($D2800142);  { mov x2, #10 }
  
  { Load BSS_INTBUF + INTBUF_SIZE into w3 }
  EmitI32($18000043);  { ldr w3, [pc+8] }
  EmitI32($14000002);  { b [pc+8] }
  EmitGlobRef(BSS_INTBUF + INTBUF_SIZE);
  
  loopStart := CodeLen;
  EmitI32($9AC20C04);  { sdiv x4, x0, x2 }
  EmitI32($9B028085);  { msub x5, x4, x2, x0 }
  EmitI32($AA0403E0);  { mov x0, x4 }
  EmitI32($9100C0A5);  { add x5, x5, #48 }
  EmitI32($D1000463);  { sub x3, x3, #1 }
  EmitI32($39000065);  { strb w5, [x3] }
  EmitI32($91000421);  { add x1, x1, #1 }
  
  EmitI32($F100001F);  { cmp x0, #0 }
  { b.ne loopStart }
  EmitI32($54000001 or (((loopStart - CodeLen) div 4) and $7ffff) shl 5);
  
  { Write syscall: write(1, x3, x1) }
  EmitI32($AA0103E2);  { mov x2, x1 }
  EmitI32($AA0303E1);  { mov x1, x3 }
  EmitI32($D2800020);  { mov x0, #1 }
  EmitI32($D2800808);  { mov x8, #64 }
  EmitI32($D4000001);  { svc #0 }
end;

procedure EmitwriteIntWA64(width: Integer);
var jnsOff, loopStart, jleOff, jzOff: Integer;
begin
  { Test if x0 is positive }
  EmitI32($F100001F);  { cmp x0, #0 }
  { b.ge positive (forward jump) }
  jnsOff := CodeLen;
  EmitI32($5400000A);
  
  { Negative: print minus, then negate }
  EmitI32($CB0003E0);  { neg x0, x0 }
  EmitI32($D2800029);  { movz x9, #1 }
  jzOff := CodeLen;
  EmitI32($14000000);  { b positive }
  
  { Patch jnsOff }
  Patch32(jnsOff, $5400000A or (((CodeLen - jnsOff) div 4) and $7ffff) shl 5);
  EmitI32($D2800009);  { movz x9, #0 }
  
  { Patch jzOff }
  Patch32(jzOff, $14000000 or (((CodeLen - jzOff) div 4) and $03ffffff));

  { Digit conversion starts here }
  EmitI32($D2800001);  { mov x1, #0  (digit count) }
  EmitI32($D2800142);  { mov x2, #10 }
  
  { Load BSS_INTBUF + INTBUF_SIZE into w3 }
  EmitI32($18000043);  { ldr w3, [pc+8] }
  EmitI32($14000002);  { b [pc+8] }
  EmitGlobRef(BSS_INTBUF + INTBUF_SIZE);
  
  loopStart := CodeLen;
  EmitI32($9AC20C04);  { sdiv x4, x0, x2 }
  EmitI32($9B028085);  { msub x5, x4, x2, x0 }
  EmitI32($AA0403E0);  { mov x0, x4 }
  EmitI32($9100C0A5);  { add x5, x5, #48 }
  EmitI32($D1000463);  { sub x3, x3, #1 }
  EmitI32($39000065);  { strb w5, [x3] }
  EmitI32($91000421);  { add x1, x1, #1 }
  
  EmitI32($F100001F);  { cmp x0, #0 }
  { b.ne loopStart }
  EmitI32($54000001 or (((loopStart - CodeLen) div 4) and $7ffff) shl 5);

  { Save digit start/count; compute padding = width - digits - sign }
  { stp x1, x3, [sp, #-32]! }
  EmitI32($A9BE0FE1);
  { str x9, [sp, #16] }
  EmitI32($F9000BE9);
  
  { Compute padding in x4: x4 = width - x1 - x9 }
  EmitLoadImmA64(4, width);
  EmitI32($CB010084);  { sub x4, x4, x1 }
  EmitI32($CB090084);  { sub x4, x4, x9 }
  EmitI32($F100009F);  { cmp x4, #0 }
  
  jleOff := CodeLen;
  EmitI32($5400000D);  { b.le no_pad }
  
  { Print padding: write(1, SpacesOffset, x4) }
  EnsureSpaces;
  EmitI32($AA0403E2);  { mov x2, x4 (len) }
  EmitI32($58000041);  { ldr x1, [pc+8] }
  EmitI32($14000003);  { b [pc+12] }
  EmitDataRef(SpacesOffset);
  EmitI32($D2800020);  { mov x0, #1 }
  EmitI32($D2800808);  { mov x8, #64 }
  EmitI32($D4000001);  { svc #0 }
  
  { Patch jleOff }
  Patch32(jleOff, $5400000D or (((CodeLen - jleOff) div 4) and $7ffff) shl 5);
  
  { Restore x9 }
  { ldr x9, [sp, #16] }
  EmitI32($F9400BE9);
  EmitI32($F100053F);  { cmp x9, #1 }
  
  jzOff := CodeLen;
  EmitI32($54000001);  { b.ne no_sign }
  
  { Write minus sign: write(1, MINUS_OFFSET, 1) }
  EmitI32($D2800022);  { mov x2, #1 }
  EmitI32($58000041);  { ldr x1, [pc+8] }
  EmitI32($14000003);  { b [pc+12] }
  EmitDataRef(MINUS_OFFSET);
  EmitI32($D2800020);  { mov x0, #1 }
  EmitI32($D2800808);  { mov x8, #64 }
  EmitI32($D4000001);  { svc #0 }
  
  { Patch jzOff }
  Patch32(jzOff, $54000001 or (((CodeLen - jzOff) div 4) and $7ffff) shl 5);
  
  { Write digits: write(1, x3, x1) }
  { ldp x1, x3, [sp], #32 }
  EmitI32($A8C20FE1);
  EmitI32($AA0103E2);  { mov x2, x1 }
  EmitI32($AA0303E1);  { mov x1, x3 }
  EmitI32($D2800020);  { mov x0, #1 }
  EmitI32($D2800808);  { mov x8, #64 }
  EmitI32($D4000001);  { svc #0 }
end;

procedure EmitwriteUIntWA64(width: Integer);
var loopStart, jleOff: Integer;
begin
  EmitI32($D2800001);  { mov x1, #0  (digit count) }
  EmitI32($D2800142);  { mov x2, #10 }
  
  { Load BSS_INTBUF + INTBUF_SIZE into w3 }
  EmitI32($18000043);  { ldr w3, [pc+8] }
  EmitI32($14000002);  { b [pc+8] }
  EmitGlobRef(BSS_INTBUF + INTBUF_SIZE);
  
  loopStart := CodeLen;
  EmitI32($9AC20C04);  { sdiv x4, x0, x2 }
  EmitI32($9B028085);  { msub x5, x4, x2, x0 }
  EmitI32($AA0403E0);  { mov x0, x4 }
  EmitI32($9100C0A5);  { add x5, x5, #48 }
  EmitI32($D1000463);  { sub x3, x3, #1 }
  EmitI32($39000065);  { strb w5, [x3] }
  EmitI32($91000421);  { add x1, x1, #1 }
  
  EmitI32($F100001F);  { cmp x0, #0 }
  { b.ne loopStart }
  EmitI32($54000001 or (((loopStart - CodeLen) div 4) and $7ffff) shl 5);

  { Save digit start/count; compute padding = width - digits }
  { stp x1, x3, [sp, #-32]! }
  EmitI32($A9BE0FE1);
  
  { Compute padding in x4: x4 = width - x1 }
  EmitLoadImmA64(4, width);
  EmitI32($CB010084);  { sub x4, x4, x1 }
  EmitI32($F100009F);  { cmp x4, #0 }
  
  jleOff := CodeLen;
  EmitI32($5400000D);  { b.le no_pad }
  
  { Print padding: write(1, SpacesOffset, x4) }
  EnsureSpaces;
  EmitI32($AA0403E2);  { mov x2, x4 (len) }
  EmitI32($58000041);  { ldr x1, [pc+8] }
  EmitI32($14000003);  { b [pc+12] }
  EmitDataRef(SpacesOffset);
  EmitI32($D2800020);  { mov x0, #1 }
  EmitI32($D2800808);  { mov x8, #64 }
  EmitI32($D4000001);  { svc #0 }
  
  { Patch jleOff }
  Patch32(jleOff, $5400000D or (((CodeLen - jleOff) div 4) and $7ffff) shl 5);
  
  { Write digits: write(1, x3, x1) }
  { ldp x1, x3, [sp], #32 }
  EmitI32($A8C20FE1);
  EmitI32($AA0103E2);  { mov x2, x1 }
  EmitI32($AA0303E1);  { mov x1, x3 }
  EmitI32($D2800020);  { mov x0, #1 }
  EmitI32($D2800808);  { mov x8, #64 }
  EmitI32($D4000001);  { svc #0 }
end;

procedure EmitLoadImmArm32(rd: Integer; v: Int32);
begin
  if (v >= 0) and (v <= 255) then
    EmitI32($E3A00000 or (rd shl 12) or v)
  else
  begin
    EmitI32($E59F0000 or (rd shl 12));  { ldr rd, [pc] }
    EmitI32($EA000000);                 { b .+8 }
    EmitI32(v);                         { literal }
  end;
end;

procedure EmitwriteSyscallArm32(dataOff, len: Integer);
begin
  EmitI32($E3A07004);  { mov r7, #4 }
  EmitI32($E3A00001);  { mov r0, #1 }
  EmitI32($E59F1000);  { ldr r1, [pc] }
  EmitI32($EA000000);  { b .+8 }
  EmitDataRef(dataOff);
  EmitLoadImmArm32(2, len);
  EmitI32($EF000000);  { svc #0 }
end;

procedure EmitwriteCharArm32;
begin
  { Load BSS_INTBUF address into r1 }
  EmitI32($E59F1000);  { ldr r1, [pc] }
  EmitI32($EA000000);  { b .+8 }
  EmitGlobRef(BSS_INTBUF);
  { strb r0, [r1] }
  EmitI32($E5C10000);
  { Make syscall: write(1, r1, 1) }
  EmitI32($E3A07004);  { mov r7, #4 }
  EmitI32($E3A00001);  { mov r0, #1 }
  EmitI32($E3A02001);  { mov r2, #1 }
  EmitI32($EF000000);  { svc #0 }
end;

procedure EmitwriteIntArm32;
var jnsOff, loopStart: Integer;
begin
  { Test if r0 is positive }
  EmitI32($E3500000);  { cmp r0, #0 }
  { bpl positive }
  jnsOff := CodeLen;
  EmitI32($5A000000);
  
  { Negative: print minus, then negate }
  EmitI32($E2600000);  { rsb r0, r0, #0 }
  
  { Save r0 on stack because we need to preserve it during write syscall }
  EmitI32($E92D0001);  { push {r0} }
  EmitwriteSyscallArm32(MINUS_OFFSET, 1);
  EmitI32($E8BD0001);  { pop {r0} }
  
  { Patch the bpl positive jump }
  Patch32(jnsOff, $5A000000 or ((((CodeLen - jnsOff) div 4) - 2) and $00ffffff));
  
  { EmitwriteUIntArm32 logic starts here }
  EmitI32($E3A01000);  { mov r1, #0  (digit count) }
  EmitI32($E3A0200A);  { mov r2, #10 }
  
  { Load BSS_INTBUF + INTBUF_SIZE into r3 }
  EmitI32($E59F3000);  { ldr r3, [pc] }
  EmitI32($EA000000);  { b .+8 }
  EmitGlobRef(BSS_INTBUF + INTBUF_SIZE);
  
  loopStart := CodeLen;
  EmitI32($E714F210);  { sdiv r4, r0, r2 }
  EmitI32($E0050294);  { mul r5, r4, r2 }
  EmitI32($E0405005);  { sub r5, r0, r5 }
  EmitI32($E1A00004);  { mov r0, r4 }
  EmitI32($E2855030);  { add r5, r5, #48 }
  EmitI32($E2433001);  { sub r3, r3, #1 }
  EmitI32($E5C35000);  { strb r5, [r3] }
  EmitI32($E2811001);  { add r1, r1, #1 }
  
  EmitI32($E3500000);  { cmp r0, #0 }
  { bne loopStart }
  EmitI32($1A000000 or ((((loopStart - CodeLen) div 4) - 2) and $00ffffff));
  
  { Write syscall: write(1, r3, r1) }
  EmitI32($E1A02001);  { mov r2, r1 }
  EmitI32($E1A01003);  { mov r1, r3 }
  EmitI32($E3A00001);  { mov r0, #1 }
  EmitI32($E3A07004);  { mov r7, #4 }
  EmitI32($EF000000);  { svc #0 }
end;

procedure EmitwriteUIntArm32;
var loopStart: Integer;
begin
  EmitI32($E3A01000);  { mov r1, #0  (digit count) }
  EmitI32($E3A0200A);  { mov r2, #10 }
  
  { Load BSS_INTBUF + INTBUF_SIZE into r3 }
  EmitI32($E59F3000);  { ldr r3, [pc] }
  EmitI32($EA000000);  { b .+8 }
  EmitGlobRef(BSS_INTBUF + INTBUF_SIZE);
  
  loopStart := CodeLen;
  EmitI32($E714F210);  { sdiv r4, r0, r2 }
  EmitI32($E0050294);  { mul r5, r4, r2 }
  EmitI32($E0405005);  { sub r5, r0, r5 }
  EmitI32($E1A00004);  { mov r0, r4 }
  EmitI32($E2855030);  { add r5, r5, #48 }
  EmitI32($E2433001);  { sub r3, r3, #1 }
  EmitI32($E5C35000);  { strb r5, [r3] }
  EmitI32($E2811001);  { add r1, r1, #1 }
  
  EmitI32($E3500000);  { cmp r0, #0 }
  { bne loopStart }
  EmitI32($1A000000 or ((((loopStart - CodeLen) div 4) - 2) and $00ffffff));
  
  { Write syscall: write(1, r3, r1) }
  EmitI32($E1A02001);  { mov r2, r1 }
  EmitI32($E1A01003);  { mov r1, r3 }
  EmitI32($E3A00001);  { mov r0, #1 }
  EmitI32($E3A07004);  { mov r7, #4 }
  EmitI32($EF000000);  { svc #0 }
end;

procedure EmitwriteIntWArm32(width: Integer);
var jnsOff, loopStart, jleOff, jzOff: Integer;
begin
  { Test if r0 is positive }
  EmitI32($E3500000);  { cmp r0, #0 }
  { bpl positive }
  jnsOff := CodeLen;
  EmitI32($5A000000);
  
  { Negative: print minus, then negate }
  EmitI32($E2600000);  { rsb r0, r0, #0 }
  EmitI32($E3A09001);  { mov r9, #1 }
  jzOff := CodeLen;
  EmitI32($EA000000);  { b positive }
  
  { Patch jnsOff }
  Patch32(jnsOff, $5A000000 or ((((CodeLen - jnsOff) div 4) - 2) and $00ffffff));
  EmitI32($E3A09000);  { mov r9, #0 }
  
  { Patch jzOff }
  Patch32(jzOff, $EA000000 or ((((CodeLen - jzOff) div 4) - 2) and $00ffffff));

  { Digit conversion starts here }
  EmitI32($E3A01000);  { mov r1, #0  (digit count) }
  EmitI32($E3A0200A);  { mov r2, #10 }
  
  { Load BSS_INTBUF + INTBUF_SIZE into r3 }
  EmitI32($E59F3000);  { ldr r3, [pc] }
  EmitI32($EA000000);  { b .+8 }
  EmitGlobRef(BSS_INTBUF + INTBUF_SIZE);
  
  loopStart := CodeLen;
  EmitI32($E714F210);  { sdiv r4, r0, r2 }
  EmitI32($E0050294);  { mul r5, r4, r2 }
  EmitI32($E0405005);  { sub r5, r0, r5 }
  EmitI32($E1A00004);  { mov r0, r4 }
  EmitI32($E2855030);  { add r5, r5, #48 }
  EmitI32($E2433001);  { sub r3, r3, #1 }
  EmitI32($E5C35000);  { strb r5, [r3] }
  EmitI32($E2811001);  { add r1, r1, #1 }
  
  EmitI32($E3500000);  { cmp r0, #0 }
  { bne loopStart }
  EmitI32($1A000000 or ((((loopStart - CodeLen) div 4) - 2) and $00ffffff));

  { Save digit start/count and sign flag on stack }
  EmitI32($E92D020A);  { push {r1, r3, r9} }
  
  { Compute padding in r4: r4 = width - r1 - r9 }
  EmitLoadImmArm32(4, width);
  EmitI32($E0444001);  { sub r4, r4, r1 }
  EmitI32($E0444009);  { sub r4, r4, r9 }
  EmitI32($E3540000);  { cmp r4, #0 }
  
  jleOff := CodeLen;
  EmitI32($DA000000);  { ble no_pad }
  
  { Print padding: write(1, SpacesOffset, r4) }
  EnsureSpaces;
  EmitI32($E1A02004);  { mov r2, r4 (len) }
  EmitI32($E59F1000);  { ldr r1, [pc] }
  EmitI32($EA000000);  { b .+8 }
  EmitDataRef(SpacesOffset);
  EmitI32($E3A00001);  { mov r0, #1 }
  EmitI32($E3A07004);  { mov r7, #4 }
  EmitI32($EF000000);  { svc #0 }
  
  { Patch jleOff }
  Patch32(jleOff, $DA000000 or ((((CodeLen - jleOff) div 4) - 2) and $00ffffff));
  
  { Restore digit start/count and sign flag from stack }
  EmitI32($E8BD020A);  { pop {r1, r3, r9} }
  
  EmitI32($E3590001);  { cmp r9, #1 }
  jzOff := CodeLen;
  EmitI32($1A000000);  { bne no_sign }
  
  { Write minus sign: write(1, MINUS_OFFSET, 1) }
  { Save r1, r3 because write syscall clobbers them }
  EmitI32($E92D000A);  { push {r1, r3} }
  EmitwriteSyscallArm32(MINUS_OFFSET, 1);
  EmitI32($E8BD000A);  { pop {r1, r3} }
  
  { Patch jzOff }
  Patch32(jzOff, $1A000000 or ((((CodeLen - jzOff) div 4) - 2) and $00ffffff));
  
  { Write digits: write(1, r3, r1) }
  EmitI32($E1A02001);  { mov r2, r1 }
  EmitI32($E1A01003);  { mov r1, r3 }
  EmitI32($E3A00001);  { mov r0, #1 }
  EmitI32($E3A07004);  { mov r7, #4 }
  EmitI32($EF000000);  { svc #0 }
end;

procedure EmitwriteUIntWArm32(width: Integer);
var loopStart, jleOff: Integer;
begin
  EmitI32($E3A01000);  { mov r1, #0  (digit count) }
  EmitI32($E3A0200A);  { mov r2, #10 }
  
  { Load BSS_INTBUF + INTBUF_SIZE into r3 }
  EmitI32($E59F3000);  { ldr r3, [pc] }
  EmitI32($EA000000);  { b .+8 }
  EmitGlobRef(BSS_INTBUF + INTBUF_SIZE);
  
  loopStart := CodeLen;
  EmitI32($E714F210);  { sdiv r4, r0, r2 }
  EmitI32($E0050294);  { mul r5, r4, r2 }
  EmitI32($E0405005);  { sub r5, r0, r5 }
  EmitI32($E1A00004);  { mov r0, r4 }
  EmitI32($E2855030);  { add r5, r5, #48 }
  EmitI32($E2433001);  { sub r3, r3, #1 }
  EmitI32($E5C35000);  { strb r5, [r3] }
  EmitI32($E2811001);  { add r1, r1, #1 }
  
  EmitI32($E3500000);  { cmp r0, #0 }
  { bne loopStart }
  EmitI32($1A000000 or ((((loopStart - CodeLen) div 4) - 2) and $00ffffff));

  { Save digit start/count on stack }
  EmitI32($E92D000A);  { push {r1, r3} }
  
  { Compute padding in r4: r4 = width - r1 }
  EmitLoadImmArm32(4, width);
  EmitI32($E0444001);  { sub r4, r4, r1 }
  EmitI32($E3540000);  { cmp r4, #0 }
  
  jleOff := CodeLen;
  EmitI32($DA000000);  { ble no_pad }
  
  { Print padding: write(1, SpacesOffset, r4) }
  EnsureSpaces;
  EmitI32($E1A02004);  { mov r2, r4 (len) }
  EmitI32($E59F1000);  { ldr r1, [pc] }
  EmitI32($EA000000);  { b .+8 }
  EmitDataRef(SpacesOffset);
  EmitI32($E3A00001);  { mov r0, #1 }
  EmitI32($E3A07004);  { mov r7, #4 }
  EmitI32($EF000000);  { svc #0 }
  
  { Patch jleOff }
  Patch32(jleOff, $DA000000 or ((((CodeLen - jleOff) div 4) - 2) and $00ffffff));
  
  { Restore digit start/count from stack }
  EmitI32($E8BD000A);  { pop {r1, r3} }
  
  { Write digits: write(1, r3, r1) }
  EmitI32($E1A02001);  { mov r2, r1 }
  EmitI32($E1A01003);  { mov r1, r3 }
  EmitI32($E3A00001);  { mov r0, #1 }
  EmitI32($E3A07004);  { mov r7, #4 }
  EmitI32($EF000000);  { svc #0 }
end;



