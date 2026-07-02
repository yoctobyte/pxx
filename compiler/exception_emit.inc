{ SPDX-License-Identifier: MPL-2.0 }
{ ===== Exception runtime emission ===== }

procedure EmitExceptionRuntime;
var unhandledJmp, si, cbzOffset, pos, bOffset: Integer;
begin
  if TargetArch = TARGET_X86_64 then
  begin
    { Save enough integer state to return from a raise into the protected frame. }
    ExcSetJmpAddr := CodeLen;
    EmitB($48); EmitB($89); EmitB($1F);                         { mov [rdi], rbx }
    EmitB($48); EmitB($89); EmitB($6F); EmitB($08);             { mov [rdi+8], rbp }
    EmitB($4C); EmitB($89); EmitB($67); EmitB($10);             { mov [rdi+16], r12 }
    EmitB($4C); EmitB($89); EmitB($6F); EmitB($18);             { mov [rdi+24], r13 }
    EmitB($4C); EmitB($89); EmitB($77); EmitB($20);             { mov [rdi+32], r14 }
    EmitB($4C); EmitB($89); EmitB($7F); EmitB($28);             { mov [rdi+40], r15 }
    EmitB($48); EmitB($8D); EmitB($44); EmitB($24); EmitB($08); { lea rax, [rsp+8] }
    EmitB($48); EmitB($89); EmitB($47); EmitB($30);             { mov [rdi+48], rax }
    EmitB($48); EmitB($8B); EmitB($04); EmitB($24);             { mov rax, [rsp] }
    EmitB($48); EmitB($89); EmitB($47); EmitB($38);             { mov [rdi+56], rax }
    EmitB($31); EmitB($C0);                                     { xor eax, eax }
    EmitB($C3);                                                 { ret }

    ExcLongJmpAddr := CodeLen;
    EmitB($48); EmitB($8B); EmitB($1F);                         { mov rbx, [rdi] }
    EmitB($48); EmitB($8B); EmitB($6F); EmitB($08);             { mov rbp, [rdi+8] }
    EmitB($4C); EmitB($8B); EmitB($67); EmitB($10);             { mov r12, [rdi+16] }
    EmitB($4C); EmitB($8B); EmitB($6F); EmitB($18);             { mov r13, [rdi+24] }
    EmitB($4C); EmitB($8B); EmitB($77); EmitB($20);             { mov r14, [rdi+32] }
    EmitB($4C); EmitB($8B); EmitB($7F); EmitB($28);             { mov r15, [rdi+40] }
    EmitB($48); EmitB($8B); EmitB($67); EmitB($30);             { mov rsp, [rdi+48] }
    EmitB($B8); EmitI32(1);                                     { mov eax, 1 }
    EmitB($FF); EmitB($67); EmitB($38);                         { jmp qword [rdi+56] }

    ExcRaiseAddr := CodeLen;
    EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_TOP);
    EmitB($48); EmitB($85); EmitB($C0);                         { test rax, rax }
    EmitB($0F); EmitB($84); unhandledJmp := CodeLen; EmitI32(0); { jz unhandled }
    EmitB($48); EmitB($8D); EmitB($78); EmitB(EXC_JMP_OFFSET);  { lea rdi, [rax+8] }
    EmitB($E9); EmitI32(ExcLongJmpAddr - (CodeLen + 4));        { jmp longjmp }
    Patch32(unhandledJmp, CodeLen - (unhandledJmp + 4));

    if not NoUnhandledHandler then
    begin
      si := InternStr('Unhandled exception');
      MovRaxImm(SYS_WRITE); MovRdiImm(2);
      EmitB($48); EmitB($BE); EmitDataRef(Strs[si].Offset + 8);
      MovRdxImm(Strs[si].Len); EmitSyscall;
      MovRaxImm(SYS_WRITE); MovRdiImm(2);
      EmitB($48); EmitB($BE); EmitDataRef(NEWLINE_OFFSET);
      MovRdxImm(1); EmitSyscall;
    end;
    EmitExit(1);
  end
  else if TargetArch = TARGET_I386 then
  begin
    ExcSetJmpAddr := CodeLen;
    EmitB($89); EmitB($18);                                     { mov [eax], ebx }
    EmitB($89); EmitB($70); EmitB($04);                         { mov [eax+4], esi }
    EmitB($89); EmitB($78); EmitB($08);                         { mov [eax+8], edi }
    EmitB($89); EmitB($68); EmitB($0C);                         { mov [eax+12], ebp }
    EmitB($8D); EmitB($4C); EmitB($24); EmitB($04);             { lea ecx, [esp+4] }
    EmitB($89); EmitB($48); EmitB($10);                         { mov [eax+16], ecx }
    EmitB($8B); EmitB($0C); EmitB($24);                         { mov ecx, [esp] }
    EmitB($89); EmitB($48); EmitB($14);                         { mov [eax+20], ecx }
    EmitB($31); EmitB($C0);                                     { xor eax, eax }
    EmitB($C3);                                                 { ret }

    ExcLongJmpAddr := CodeLen;
    EmitB($8B); EmitB($18);                                     { mov ebx, [eax] }
    EmitB($8B); EmitB($70); EmitB($04);                         { mov esi, [eax+4] }
    EmitB($8B); EmitB($78); EmitB($08);                         { mov edi, [eax+8] }
    EmitB($8B); EmitB($68); EmitB($0C);                         { mov ebp, [eax+12] }
    EmitB($8B); EmitB($60); EmitB($10);                         { mov esp, [eax+16] }
    EmitB($8B); EmitB($48); EmitB($14);                         { mov ecx, [eax+20] }
    EmitB($B8); EmitI32(1);                                     { mov eax, 1 }
    EmitB($FF); EmitB($E1);                                     { jmp ecx }

    ExcRaiseAddr := CodeLen;
    EmitB($A1); EmitGlobRef(BSS_EXC_TOP);                        { mov eax, [BSS_EXC_TOP] }
    EmitB($85); EmitB($C0);                                     { test eax, eax }
    EmitB($0F); EmitB($84); unhandledJmp := CodeLen; EmitI32(0); { jz unhandled }
    EmitB($8D); EmitB($40); EmitB(EXC_JMP_OFFSET_386);          { lea eax, [eax+EXC_JMP_OFFSET_386] }
    EmitB($E9); EmitI32(ExcLongJmpAddr - (CodeLen + 4));        { jmp longjmp }
    Patch32(unhandledJmp, CodeLen - (unhandledJmp + 4));

    if not NoUnhandledHandler then
    begin
      si := InternStr('Unhandled exception');
      EmitB($B8); EmitI32(4);                                   { mov eax, 4 (write) }
      EmitB($BB); EmitI32(2);                                   { mov ebx, 2 (stderr) }
      EmitB($B9); EmitDataRef(Strs[si].Offset + 8);             { mov ecx, msg }
      EmitB($BA); EmitI32(Strs[si].Len);                        { mov edx, len }
      EmitB($CD); EmitB($80);                                   { int 0x80 }

      EmitB($B8); EmitI32(4);
      EmitB($BB); EmitI32(2);
      EmitB($B9); EmitDataRef(NEWLINE_OFFSET);
      EmitB($BA); EmitI32(1);
      EmitB($CD); EmitB($80);
    end;
    EmitExit(1);
  end
  else if TargetArch = TARGET_ARM32 then
  begin
    ExcSetJmpAddr := CodeLen;
    EmitI32($E5804000);                                         { str r4, [r0] }
    EmitI32($E5805004);                                         { str r5, [r0, #4] }
    EmitI32($E5806008);                                         { str r6, [r0, #8] }
    EmitI32($E580700C);                                         { str r7, [r0, #12] }
    EmitI32($E5808010);                                         { str r8, [r0, #16] }
    EmitI32($E5809014);                                         { str r9, [r0, #20] }
    EmitI32($E580A018);                                         { str r10, [r0, #24] }
    EmitI32($E580B01C);                                         { str r11, [r0, #28] }
    EmitI32($E1A0100D);                                         { mov r1, sp }
    EmitI32($E5801020);                                         { str r1, [r0, #32] }
    EmitI32($E580E024);                                         { str lr, [r0, #36] }
    EmitI32($E3A00000);                                         { mov r0, #0 }
    EmitI32($E12FFF1E);                                         { bx lr }

    ExcLongJmpAddr := CodeLen;
    EmitI32($E5904000);                                         { ldr r4, [r0] }
    EmitI32($E5905004);                                         { ldr r5, [r0, #4] }
    EmitI32($E5906008);                                         { ldr r6, [r0, #8] }
    EmitI32($E590700C);                                         { ldr r7, [r0, #12] }
    EmitI32($E5908010);                                         { ldr r8, [r0, #16] }
    EmitI32($E5909014);                                         { ldr r9, [r0, #20] }
    EmitI32($E590A018);                                         { ldr r10, [r0, #24] }
    EmitI32($E590B01C);                                         { ldr r11, [r0, #28] }
    EmitI32($E5901020);                                         { ldr r1, [r0, #32] }
    EmitI32($E1A0D001);                                         { mov sp, r1 }
    EmitI32($E590E024);                                         { ldr lr, [r0, #36] }
    EmitI32($E3A00001);                                         { mov r0, #1 }
    EmitI32($E12FFF1E);                                         { bx lr }

    ExcRaiseAddr := CodeLen;
    EmitI32($E59F1000);                                         { ldr r1, [pc] }
    EmitI32($EA000000);                                         { b .+8 }
    EmitGlobRef(BSS_EXC_TOP);
    EmitI32($E5910000);                                         { ldr r0, [r1] }
    EmitI32($E3500000);                                         { cmp r0, #0 }
    unhandledJmp := CodeLen; EmitI32($0A000000);                { beq unhandled }
    EmitI32($E2800008);                 { add r0, r0, #8 }
    pos := CodeLen; EmitI32($EA000000);                         { b ExcLongJmpAddr }
    Patch32(pos, $EA000000 or ((((ExcLongJmpAddr - pos) div 4) - 2) and $00ffffff));
    Patch32(unhandledJmp, $0A000000 or ((((CodeLen - unhandledJmp) div 4) - 2) and $00ffffff));

    if not NoUnhandledHandler then
    begin
      si := InternStr('Unhandled exception');
      EmitI32($E3A07004);                                       { mov r7, #4 (sys_write) }
      EmitI32($E3A00002);                                       { mov r0, #2 (stderr) }
      EmitI32($E59F1000);                                       { ldr r1, [pc] }
      EmitI32($EA000000);                                       { b .+8 }
      EmitDataRef(Strs[si].Offset + 8);
      EmitLoadImmArm32(2, Strs[si].Len);                        { r2 = len }
      EmitI32($EF000000);                                       { svc #0 }

      EmitI32($E3A07004);                                       { mov r7, #4 }
      EmitI32($E3A00002);                                       { mov r0, #2 }
      EmitI32($E59F1000);                                       { ldr r1, [pc] }
      EmitI32($EA000000);                                       { b .+8 }
      EmitDataRef(NEWLINE_OFFSET);
      EmitI32($E3A02001);                                       { mov r2, #1 }
      EmitI32($EF000000);                                       { svc #0 }
    end;
    EmitExit(1);
  end
  else if TargetArch = TARGET_AARCH64 then
  begin
    ExcSetJmpAddr := CodeLen;
    EmitI32($F9000013);                                         { str x19, [x0] }
    EmitI32($F9000414);                                         { str x20, [x0, #8] }
    EmitI32($F9000815);                                         { str x21, [x0, #16] }
    EmitI32($F9000C16);                                         { str x22, [x0, #24] }
    EmitI32($F9001017);                                         { str x23, [x0, #32] }
    EmitI32($F9001418);                                         { str x24, [x0, #40] }
    EmitI32($F9001819);                                         { str x25, [x0, #48] }
    EmitI32($F9001C1A);                                         { str x26, [x0, #56] }
    EmitI32($F900201B);                                         { str x27, [x0, #64] }
    EmitI32($F900241C);                                         { str x28, [x0, #72] }
    EmitI32($F900281D);                                         { str x29, [x0, #80] }
    EmitI32($F9002C1E);                                         { str x30, [x0, #88] }
    EmitI32($910003E9);                                         { add x9, sp, #0 }
    EmitI32($F9003009);                                         { str x9, [x0, #96] }
    EmitI32($D2800000);                                         { movz x0, #0 }
    EmitI32($D65F03C0);                                         { ret }

    ExcLongJmpAddr := CodeLen;
    EmitI32($F9400013);                                         { ldr x19, [x0] }
    EmitI32($F9400414);                                         { ldr x20, [x0, #8] }
    EmitI32($F9400815);                                         { ldr x21, [x0, #16] }
    EmitI32($F9400C16);                                         { ldr x22, [x0, #24] }
    EmitI32($F9401017);                                         { ldr x23, [x0, #32] }
    EmitI32($F9401418);                                         { ldr x24, [x0, #40] }
    EmitI32($F9401819);                                         { ldr x25, [x0, #48] }
    EmitI32($F9401C1A);                                         { ldr x26, [x0, #56] }
    EmitI32($F940201B);                                         { ldr x27, [x0, #64] }
    EmitI32($F940241C);                                         { ldr x28, [x0, #72] }
    EmitI32($F940281D);                                         { ldr x29, [x0, #80] }
    EmitI32($F9402C1E);                                         { ldr x30, [x0, #88] }
    EmitI32($F9403009);                                         { ldr x9, [x0, #96] }
    EmitI32($9100013F);                                         { add sp, x9, #0 }
    EmitI32($D2800020);                                         { movz x0, #1 }
    EmitI32($D65F03C0);                                         { ret }

    ExcRaiseAddr := CodeLen;
    EmitI32($18000041);                                         { ldr w1, [pc+8] }
    EmitI32($14000002);                                         { b [pc+8] }
    EmitGlobRef(BSS_EXC_TOP);
    EmitI32($F9400020);                                         { ldr x0, [x1] }
    cbzOffset := CodeLen; EmitI32($B4000000);                   { cbz x0, unhandled }
    EmitI32($91004000);                 { add x0, x0, #16 }
    bOffset := CodeLen; EmitI32($14000000);                     { b ExcLongJmpAddr }
    Patch32(bOffset, $14000000 or (((ExcLongJmpAddr - bOffset) div 4) and $03ffffff));
    Patch32(cbzOffset, $B4000000 or ((((CodeLen - cbzOffset) div 4) and $7ffff) shl 5));

    if not NoUnhandledHandler then
    begin
      si := InternStr('Unhandled exception');
      EmitI32($D2800808);                                       { movz x8, #64 (sys_write) }
      EmitI32($D2800040);                                       { movz x0, #2 (stderr) }
      EmitI32($58000041);                                       { ldr x1, [pc+8] }
      EmitI32($14000003);                                       { b [pc+12] }
      EmitDataRef(Strs[si].Offset + 8);
      EmitI32($D2800002 + (Strs[si].Len shl 5));                { movz x2, #len }
      EmitI32($D4000001);                                       { svc #0 }

      EmitI32($D2800808);                                       { movz x8, #64 }
      EmitI32($D2800040);                                       { movz x0, #2 }
      EmitI32($58000041);                                       { ldr x1, [pc+8] }
      EmitI32($14000003);                                       { b [pc+12] }
      EmitDataRef(NEWLINE_OFFSET);
      EmitI32($D2800002 + (1 shl 5));                           { movz x2, #1 }
      EmitI32($D4000001);                                       { svc #0 }
    end;
    EmitExit(1);
  end
  else if (TargetArch = TARGET_XTENSA) or (TargetArch = TARGET_RISCV32) then
  begin
    ExcSetJmpAddr := CodeLen;
    ExcLongJmpAddr := CodeLen;
    ExcRaiseAddr := CodeLen;
    EmitExit(1);
  end;
end;
