{ SPDX-License-Identifier: MPL-2.0 }
{ ===== Exception runtime emission ===== }

function StatusSlotTlsIndex(bssSlot: Integer): Integer;
{ THE map from a compiler-owned status slot to its per-thread TLS slot, or -1
  for "keep the process-wide one".

  Eight slots in two families, both moved for the same reason: the handler or
  the unwinder runs on whichever thread got there, and a process-wide slot is
  read by a thread that did not write it. The signal four produce a wrong VALUE
  (75875 in 400000 deliveries); the exception four CRASH, because the chain head
  is a pointer the unwinder longjmps to.

  -1 whenever the answer is "there is no block" for THIS emitter: not x86-64
  (the per-thread status slots are addressed gs-relative, and the aarch64 and
  arm32 blocks, which exist only in a static binary, are not wired to them);
  or --emit-obj/--shared, where nothing installed a base and `gs:` does not
  return 0, it FAULTS. Also -1 before the corresponding BSS group has
  been allocated, because until then every one of these globals is 0 and so are
  the others -- an identity test on 0 would match the wrong family.

  Decided entirely at EMISSION. No runtime branch exists anywhere downstream. }
begin
  StatusSlotTlsIndex := -1;
  if not TlsMainInstalled then Exit;
  if TargetArch <> TARGET_X86_64 then Exit;
  if SigBssAllocated then
  begin
    if bssSlot = BSS_SIG_CODE then begin StatusSlotTlsIndex := TLS_SLOT_SIG_CODE; Exit; end;
    if bssSlot = BSS_SIG_ADDR then begin StatusSlotTlsIndex := TLS_SLOT_SIG_ADDR; Exit; end;
    if bssSlot = BSS_SIG_CTX  then begin StatusSlotTlsIndex := TLS_SLOT_SIG_CTX;  Exit; end;
    if bssSlot = BSS_SIG_NUM  then begin StatusSlotTlsIndex := TLS_SLOT_SIG_NUM;  Exit; end;
  end;
  if ExceptionUsed then
  begin
    if bssSlot = BSS_EXC_TOP  then begin StatusSlotTlsIndex := TLS_SLOT_EXC_TOP;  Exit; end;
    if bssSlot = BSS_EXC_OBJ  then begin StatusSlotTlsIndex := TLS_SLOT_EXC_OBJ;  Exit; end;
    if bssSlot = BSS_EXC_CLS  then begin StatusSlotTlsIndex := TLS_SLOT_EXC_CLS;  Exit; end;
    if bssSlot = BSS_EXC_ADDR then begin StatusSlotTlsIndex := TLS_SLOT_EXC_ADDR; Exit; end;
  end;
end;

procedure EmitStatusSlotX64(reg, bssSlot: Integer; store: Boolean);
{ `mov <reg>, [slot]` / `mov [slot], <reg>` for a compiler-owned status slot,
  addressed per-thread when there is a block and absolutely when there is not.

  THE PER-THREAD FORM COSTS ONE BYTE AND NO EXTRA ACCESS. x86-64 cannot read a
  segment BASE into a register, which is why the block carries its own address
  at slot 0 -- but it can ADDRESS memory relative to gs directly, so
  `mov rax, gs:[8*k]` is the same instruction as `mov rax, [abs]` with a 0x65
  prefix in front. That matters here and did not matter for the signal fields:
  BSS_EXC_TOP is touched on every `try` entry and every `try` exit, which is a
  genuinely hot path, and a `mov rax, gs:[0]` load in front of each access would
  have been a real cost rather than a rounding error.

  The two encodings are otherwise identical -- same REX, same opcode, same
  modrm/SIB -- which is why this is one function with two tails instead of two
  functions. }
var t: Integer;
begin
  t := StatusSlotTlsIndex(bssSlot);
  if t >= 0 then EmitB($65);                    { gs: }
  if reg >= 8 then EmitB($4C) else EmitB($48);  { REX.W, +R for r8..r15 }
  if store then EmitB($89) else EmitB($8B);
  EmitB($04 + ((reg and 7) shl 3));             { mod=00 reg=<reg> rm=100 (SIB) }
  EmitB($25);                                   { SIB: no base, no index -> disp32 }
  if t >= 0 then EmitI32(8 * t) else EmitGlobRef(bssSlot);
end;

procedure EmitExceptionRuntime;
var unhandledJmp, si, cbzOffset, pos, bOffset, k: Integer;
    siColon, jo1, jo2, jc1, jc2, jc3, jc4, jm1, jm2, jm3, jm4: Integer;
    ExcValidateAddr, excSkip1, excSkip2, siCorrupt, unhandledJmp2: Integer;
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
    { RAISE SITE: the `call` that got us here pushed its own return address, so
      [rsp] IS the instruction after the `raise`. Record it for ExceptAddr before
      anything else runs. rax is reloaded right below, so clobbering it is free. }
    EmitB($48); EmitB($8B); EmitB($04); EmitB($24);             { mov rax, [rsp] }
    EmitStatusSlotX64(0, BSS_EXC_ADDR, True);                   { mov [EXC_ADDR], rax }
    EmitStatusSlotX64(0, BSS_EXC_TOP, False);                   { mov rax, [EXC_TOP] }

    { ---- VALIDATE THE FRAME BEFORE JUMPING INTO IT -----------------------
      A chain head is a POINTER THE UNWINDER JUMPS TO, so a corrupt one is not
      a wrong answer, it is a wild jump: `jmp [rdi+56]` with whatever is at that
      address. Measured 2026-09-14 on lekkerzeilen, four runs of the same
      binary: three SIGSEGV and one SIGBUS, because the restored rip is not
      always 0 -- and NOTHING IS PRINTED either way, so a program that hits this
      loses its diagnostics rather than reporting them. That is the whole cost:
      the raise was correct, the handler lookup was correct, and the only thing
      wrong was that the frame it named was dead.

      THE TEST IS AN EQUALITY AND THAT IS WHY IT WORKS. IR_EXC_ENTER emits
      `sub rsp, EXC_FRAME_SIZE` and then calls setjmp with rdi = rsp+8, so the
      `lea rax, [rsp+8]` inside setjmp -- one pushed return address deeper --
      stores EXACTLY THE FRAME'S OWN ADDRESS in the saved-rsp slot at +48. A
      live frame therefore satisfies `[frame+EXC_JMP_OFFSET+48] == frame`, and a
      dead one satisfies it only by coincidence.

      A ZERO TEST IS NOT ENOUGH AND WAS TRIED FIRST: dead stack is only zeroes
      on a page nothing has used yet. In lekkerzeilen the leaked frame read as
      all zeroes and a `!= 0` guard would have caught it; in the five-line
      reduction the same leak leaves a PLAUSIBLE stale jmpbuf behind, the guard
      passed it, and the process segfaulted exactly as before. Measured both
      ways 2026-09-14, with the ir.inc fix reverted to put the leak back.

      On failure WALK THE CHAIN ([rax+0] is the previous head) rather than
      jumping: an outer handler further up is still valid and is the right place
      to land. Falling off the end is the unhandled path, which prints.

      Publishing the surviving head to BSS_EXC_TOP is what makes the walk safe
      and is a no-op when nothing was skipped -- the landing pad's IR_EXC_LEAVE
      pops from that slot, so a pad reached after a skip must find ITS OWN frame
      there or it pops a frame nobody entered.

      THIS DOES NOT REPAIR THE LEAK AND IS NOT MEANT TO: the frame is on the
      chain because something failed to pop it, and that is
      bug-a-something-in-lekkerzeilen-s-startup-still-leaves-an-exception-frame-on-the-chain.
      What it buys is that the failure ARRIVES AS A MESSAGE. x86-64 only for
      now, deliberately -- the other five backends have the same shape and none
      of them is where this was measured. }
    ExcValidateAddr := CodeLen;
    EmitB($48); EmitB($85); EmitB($C0);                         { test rax, rax }
    EmitB($0F); EmitB($84); unhandledJmp := CodeLen; EmitI32(0); { jz unhandled }
    EmitB($48); EmitB($8B); EmitB($50);
      EmitB(EXC_JMP_OFFSET + 48);                               { mov rdx, [rax+56]  saved rsp }
    EmitB($48); EmitB($39); EmitB($C2);                         { cmp rdx, rax }
    EmitB($0F); EmitB($85); excSkip1 := CodeLen; EmitI32(0);    { jne skip }
    excSkip2 := excSkip1;
    EmitStatusSlotX64(0, BSS_EXC_TOP, True);                    { mov [EXC_TOP], rax }
    EmitB($48); EmitB($8D); EmitB($78); EmitB(EXC_JMP_OFFSET);  { lea rdi, [rax+8] }
    EmitB($E9); EmitI32(ExcLongJmpAddr - (CodeLen + 4));        { jmp longjmp }

    Patch32(excSkip1, CodeLen - (excSkip1 + 4));
    Patch32(excSkip2, CodeLen - (excSkip2 + 4));
    if not NoUnhandledHandler then
    begin
      { Say so. A skip that is silent is the same class of defect as the wild
        jump it replaces -- the program keeps going and nobody learns that the
        chain was broken. r8 carries the frame across the syscall, which
        clobbers rax/rcx/r11. }
      siCorrupt := InternStr('exception frame chain: a stale handler frame (its saved stack pointer is not its own address), skipping it');
      EmitB($49); EmitB($89); EmitB($C0);                       { mov r8, rax }
      MovRaxImm(SYS_WRITE); MovRdiImm(2);
      EmitB($48); EmitB($BE); EmitDataRef(Strs[siCorrupt].Offset + 8);
      MovRdxImm(Strs[siCorrupt].Len); EmitSyscall;
      MovRaxImm(SYS_WRITE); MovRdiImm(2);
      EmitB($48); EmitB($BE); EmitDataRef(NEWLINE_OFFSET);
      MovRdxImm(1); EmitSyscall;
      EmitB($4C); EmitB($89); EmitB($C0);                       { mov rax, r8 }
    end;
    { THE LINK OF A DEAD FRAME IS DEAD TOO, so it is followed only when it
      points strictly UP. The walk used to follow it blind: measured 2026-09-19
      on a `goto` out of a `try`, the skipped frame's link read 0x20,
      `mov rdx, [rax+56]` faulted on it, and the process died with the skip
      message but WITHOUT the "Unhandled exception" line this block exists to
      deliver. Rising is what an enclosing frame on the SAME stack does (pushed
      earlier, so higher), and it also guarantees the walk ends. It is NOT a
      law across stacks: a stackful generator links its chain to its
      resumer's, and GetMem'd and mmap'd stacks lie in either order -- so this
      test is applied only here, AFTER a frame has already failed validation,
      where the chain is known to be broken and ending on the unhandled path
      (which prints) is the goal. Never promote it to the validation itself.
      Zero lands on the unhandled path too, as it always did. }
    EmitB($48); EmitB($8B); EmitB($10);                         { mov rdx, [rax]  previous head }
    EmitB($48); EmitB($39); EmitB($C2);                         { cmp rdx, rax }
    EmitB($0F); EmitB($86); unhandledJmp2 := CodeLen; EmitI32(0); { jbe unhandled }
    EmitB($48); EmitB($89); EmitB($D0);                         { mov rax, rdx }
    EmitB($E9); EmitI32(ExcValidateAddr - (CodeLen + 4));       { jmp validate }
    Patch32(unhandledJmp, CodeLen - (unhandledJmp + 4));
    Patch32(unhandledJmp2, CodeLen - (unhandledJmp2 + 4));

    if not NoUnhandledHandler then
    begin
      si := InternStr('Unhandled exception');
      MovRaxImm(SYS_WRITE); MovRdiImm(2);
      EmitB($48); EmitB($BE); EmitDataRef(Strs[si].Offset + 8);
      MovRdxImm(Strs[si].Len); EmitSyscall;

      { Detail line: `Unhandled exception: <ClassName>: <Message>`. r13 = the
        object, r12 = its class RTTI blob ([[obj+0] - 8], i.e. __pxxRttiOf; note
        BSS_EXC_CLS is a compile-time class INDEX, not a blob, so it is useless
        here). Every field read is range-guarded, so raising something that is
        NOT an Exception degrades to the bare line rather than faulting.
        Layouts: blob+0 -> frozen name (Int64 length, chars at +8); an
        Exception's `msg` is its first field (obj+8) and holds a managed
        AnsiString pointer whose length sits at ptr-8. }
      siColon := InternStr(': ');
      EmitStatusSlotX64(13, BSS_EXC_OBJ, False);                 { mov r13, [BSS_EXC_OBJ] }
      EmitB($4D); EmitB($31); EmitB($E4);                         { xor r12, r12 }
      EmitB($49); EmitB($81); EmitB($FD); EmitI32(65536);         { cmp r13, 65536 }
      EmitB($0F); EmitB($82); jo1 := CodeLen; EmitI32(0);         { jb  objbad }
      EmitB($49); EmitB($8B); EmitB($45); EmitB($00);             { mov rax, [r13] }
      EmitB($48); EmitB($85); EmitB($C0);                         { test rax, rax }
      EmitB($0F); EmitB($84); jo2 := CodeLen; EmitI32(0);         { jz  objbad }
      EmitB($4C); EmitB($8B); EmitB($60); EmitB($F8);             { mov r12, [rax-8] }
      Patch32(jo1, CodeLen - (jo1 + 4)); Patch32(jo2, CodeLen - (jo2 + 4));

      EmitB($4D); EmitB($85); EmitB($E4);                         { test r12, r12 }
      EmitB($0F); EmitB($84); jc1 := CodeLen; EmitI32(0);         { jz  noclass }
      EmitB($49); EmitB($8B); EmitB($34); EmitB($24);             { mov rsi, [r12] }
      EmitB($48); EmitB($85); EmitB($F6);                         { test rsi, rsi }
      EmitB($0F); EmitB($84); jc2 := CodeLen; EmitI32(0);         { jz  noclass }
      EmitB($48); EmitB($8B); EmitB($16);                         { mov rdx, [rsi] }
      EmitB($48); EmitB($85); EmitB($D2);                         { test rdx, rdx }
      EmitB($0F); EmitB($8E); jc3 := CodeLen; EmitI32(0);         { jle noclass }
      EmitB($48); EmitB($81); EmitB($FA); EmitI32(256);           { cmp rdx, 256 }
      EmitB($0F); EmitB($83); jc4 := CodeLen; EmitI32(0);         { jae noclass }
      MovRaxImm(SYS_WRITE); MovRdiImm(2);
      EmitB($48); EmitB($BE); EmitDataRef(Strs[siColon].Offset + 8);
      MovRdxImm(Strs[siColon].Len); EmitSyscall;
      EmitB($49); EmitB($8B); EmitB($34); EmitB($24);             { mov rsi, [r12] }
      EmitB($48); EmitB($8B); EmitB($16);                         { mov rdx, [rsi] }
      EmitB($48); EmitB($83); EmitB($C6); EmitB($08);             { add rsi, 8 }
      MovRaxImm(SYS_WRITE); MovRdiImm(2); EmitSyscall;
      Patch32(jc1, CodeLen - (jc1 + 4)); Patch32(jc2, CodeLen - (jc2 + 4));
      Patch32(jc3, CodeLen - (jc3 + 4)); Patch32(jc4, CodeLen - (jc4 + 4));

      EmitB($49); EmitB($81); EmitB($FD); EmitI32(65536);         { cmp r13, 65536 }
      EmitB($0F); EmitB($82); jm1 := CodeLen; EmitI32(0);         { jb  nomsg }
      EmitB($49); EmitB($8B); EmitB($75); EmitB($08);             { mov rsi, [r13+8] }
      EmitB($48); EmitB($81); EmitB($FE); EmitI32(65536);         { cmp rsi, 65536 }
      EmitB($0F); EmitB($82); jm2 := CodeLen; EmitI32(0);         { jb  nomsg }
      EmitB($48); EmitB($8B); EmitB($56); EmitB($F8);             { mov rdx, [rsi-8] }
      EmitB($48); EmitB($85); EmitB($D2);                         { test rdx, rdx }
      EmitB($0F); EmitB($8E); jm3 := CodeLen; EmitI32(0);         { jle nomsg }
      EmitB($48); EmitB($81); EmitB($FA); EmitI32(4096);          { cmp rdx, 4096 }
      EmitB($0F); EmitB($83); jm4 := CodeLen; EmitI32(0);         { jae nomsg }
      MovRaxImm(SYS_WRITE); MovRdiImm(2);
      EmitB($48); EmitB($BE); EmitDataRef(Strs[siColon].Offset + 8);
      MovRdxImm(Strs[siColon].Len); EmitSyscall;
      EmitB($49); EmitB($8B); EmitB($75); EmitB($08);             { mov rsi, [r13+8] }
      EmitB($48); EmitB($8B); EmitB($56); EmitB($F8);             { mov rdx, [rsi-8] }
      MovRaxImm(SYS_WRITE); MovRdiImm(2); EmitSyscall;
      Patch32(jm1, CodeLen - (jm1 + 4)); Patch32(jm2, CodeLen - (jm2 + 4));
      Patch32(jm3, CodeLen - (jm3 + 4)); Patch32(jm4, CodeLen - (jm4 + 4));

      MovRaxImm(SYS_WRITE); MovRdiImm(2);
      EmitB($48); EmitB($BE); EmitDataRef(NEWLINE_OFFSET);
      MovRdxImm(1); EmitSyscall;
    end;
    EmitExit(EXITCODE_UNHANDLED_EXCEPTION);
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
    { raise site = the return address the `call` pushed (see the x86-64 note) }
    EmitB($8B); EmitB($04); EmitB($24);                         { mov eax, [esp] }
    EmitMovGlobAcc($A3, BSS_EXC_ADDR);                      { mov [BSS_EXC_ADDR], eax }
    EmitMovGlobAcc($A1, BSS_EXC_TOP);                        { mov eax, [BSS_EXC_TOP] }
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
    EmitExit(EXITCODE_UNHANDLED_EXCEPTION);
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
    { raise site: `bl` put it in lr. Same idea as x86-64's [rsp], different ABI. }
    EmitI32($E59F1000);                                         { ldr r1, [pc] }
    EmitI32($EA000000);                                         { b .+8 }
    EmitGlobRef(BSS_EXC_ADDR);
    EmitI32($E581E000);                                         { str lr, [r1] }
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
    EmitExit(EXITCODE_UNHANDLED_EXCEPTION);
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
    { raise site: `bl` put it in x30 (lr) }
    EmitI32($18000041);                                         { ldr w1, [pc+8] }
    EmitI32($14000002);                                         { b [pc+8] }
    EmitGlobRef(BSS_EXC_ADDR);
    EmitI32($F900003E);                                         { str x30, [x1] }
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
    EmitExit(EXITCODE_UNHANDLED_EXCEPTION);
  end
  else if TargetArch = TARGET_RISCV32 then
  begin
    { riscv32, hosted AND ESP bare (feature-esp-bare-exceptions): nothing in
      the frames is hosted-specific; bare only skips the unhandled-message
      write(2) below (no syscalls on bare — an unhandled raise parks via
      EmitExit, same terminal behaviour as before, but handled raises now
      unwind). jmpbuf = s0, sp, ra (codegen never touches s1-s11 —
      see the interrupt-prologue note in symtab.inc). Direct jal to
      ExcSetJmp/ExcRaise doesn't push, so the stub's sp/ra ARE the try
      point's. Glob addresses via the inline auipc+literal trick
      (EmitLoadGlobAddrRISCV32 is declared later, in the backend include). }
    ExcSetJmpAddr := CodeLen;
    rv32_sw(reg_s0, reg_a0, 0);
    rv32_sw(reg_sp, reg_a0, 4);
    rv32_sw(reg_ra, reg_a0, 8);
    rv32_addi(reg_a0, reg_zero, 0);
    rv32_jalr(reg_zero, reg_ra, 0);                             { ret 0 }

    ExcLongJmpAddr := CodeLen;
    rv32_lw(reg_s0, reg_a0, 0);
    rv32_lw(reg_sp, reg_a0, 4);
    rv32_lw(reg_t0, reg_a0, 8);
    rv32_addi(reg_a0, reg_zero, 1);
    rv32_jalr(reg_zero, reg_t0, 0);                             { resume at try, a0=1 }

    ExcRaiseAddr := CodeLen;
    { raise site: `jal ra` put it in ra }
    rv32_auipc(reg_t1, 0);                                      { &EXC_ADDR literal }
    rv32_jal(reg_zero, 8);
    EmitGlobRef(BSS_EXC_ADDR);
    rv32_lw(reg_t1, reg_t1, 8);
    rv32_sw(reg_ra, reg_t1, 0);                                 { [EXC_ADDR] := ra }
    rv32_auipc(reg_t1, 0);                                      { &EXC_TOP literal }
    rv32_jal(reg_zero, 8);
    EmitGlobRef(BSS_EXC_TOP);
    rv32_lw(reg_t1, reg_t1, 8);
    rv32_lw(reg_a0, reg_t1, 0);                                 { top frame }
    unhandledJmp := CodeLen;
    rv32_beq(reg_a0, reg_zero, 0);                              { patched: unhandled }
    rv32_addi(reg_a0, reg_a0, EXC_JMP_OFFSET_RV32);
    EmitRiscv32CallToCode(reg_zero, ExcLongJmpAddr);   { tail jump, never returns }
    Patch32(unhandledJmp, EncodeRISCVBEQ(reg_a0, reg_zero, CodeLen - unhandledJmp));

    if (not NoUnhandledHandler) and (not EspBareBoot) then
    begin
      si := InternStr('Unhandled exception');
      rv32_addi(reg_a0, reg_zero, 2);                           { stderr }
      rv32_auipc(reg_a1, 0);
      rv32_jal(reg_zero, 8);
      EmitDataRef(Strs[si].Offset + 8);
      rv32_lw(reg_a1, reg_a1, 8);
      EmitLoadImmRISCV32(reg_a2, Strs[si].Len);
      rv32_addi(reg_a7, reg_zero, 64);                          { write }
      EmitI32($00000073);
      rv32_addi(reg_a0, reg_zero, 2);
      rv32_auipc(reg_a1, 0);
      rv32_jal(reg_zero, 8);
      EmitDataRef(NEWLINE_OFFSET);
      rv32_lw(reg_a1, reg_a1, 8);
      rv32_addi(reg_a2, reg_zero, 1);
      rv32_addi(reg_a7, reg_zero, 64);
      EmitI32($00000073);
    end;
    EmitExit(EXITCODE_UNHANDLED_EXCEPTION);
  end
  else if (TargetArch = TARGET_XTENSA) and (XtensaABI = XTENSA_ABI_CALL0) then
  begin
    { Xtensa Call0 (feature-esp-bare-exceptions). jmpbuf = a15 (frame ptr),
      sp, a0 (return address) — the direct mirror of riscv32's (s0, sp, ra);
      no register windows to spill on Call0. A direct call0 to
      ExcSetJmp/ExcRaise doesn't push, so the stub's sp/a0 ARE the try
      point's. Stubs are entered via call0, whose target must be 4-aligned
      (3-byte instructions), hence the nop padding before each entry. There
      is no hosted xtensa, so no unhandled-message write — an unhandled
      raise parks via EmitExit(EXITCODE_UNHANDLED_EXCEPTION), same as the
      old stub. }
    while (CodeLen mod 4) <> 0 do xtensa_nop;
    ExcSetJmpAddr := CodeLen;
    xtensa_s32i(reg_xtensa_a15, reg_xtensa_a2, 0);
    xtensa_s32i(reg_xtensa_sp, reg_xtensa_a2, 4);
    xtensa_s32i(reg_xtensa_a0, reg_xtensa_a2, 8);
    xtensa_movi(reg_xtensa_a2, 0);
    xtensa_ret;

    while (CodeLen mod 4) <> 0 do xtensa_nop;
    ExcLongJmpAddr := CodeLen;
    xtensa_l32i(reg_xtensa_a15, reg_xtensa_a2, 0);
    xtensa_l32i(reg_xtensa_sp, reg_xtensa_a2, 4);
    xtensa_l32i(reg_xtensa_a0, reg_xtensa_a2, 8);
    xtensa_movi(reg_xtensa_a2, 1);
    xtensa_ret;                                                 { resume at try, a2=1 }

    while (CodeLen mod 4) <> 0 do xtensa_nop;
    ExcRaiseAddr := CodeLen;
    { raise site: call0 put it in a0 }
    XtensaEmitLitHeader;                                        { a3 = &EXC_ADDR }
    EmitGlobRef(BSS_EXC_ADDR);
    xtensa_l32r(reg_xtensa_a3, $FFFF);
    xtensa_s32i(reg_xtensa_a0, reg_xtensa_a3, 0);               { [EXC_ADDR] := a0 }
    XtensaEmitLitHeader;                                        { a3 = &EXC_TOP }
    EmitGlobRef(BSS_EXC_TOP);
    xtensa_l32r(reg_xtensa_a3, $FFFF);
    xtensa_l32i(reg_xtensa_a2, reg_xtensa_a3, 0);               { top frame }
    xtensa_movi(reg_xtensa_a4, 0);
    xtensa_beq(reg_xtensa_a2, reg_xtensa_a4, 9);                { no handler -> park }
    xtensa_addi(reg_xtensa_a2, reg_xtensa_a2, EXC_JMP_OFFSET_XT);
    { RECORDED, AND THE SHAPE DELIBERATELY NOT CHANGED -- the Call0 twin of the
      windowed arm below, found by censusing for the sibling after fixing that
      one rather than by anything failing. It is a `j`, which never widens, so
      the `beq ..., 9` above stays a correct byte count and the two-defect
      problem the windowed arm had does not exist here. What DOES apply is the
      other half: an unrecorded code->code reference is safe only because both
      endpoints sit in the unowned stub blob, which nothing asserts.
      CODEREF_ANCHOR_J re-encodes it in place, so recording costs no bytes. }
    RecordCodeRefFull(CodeLen, ExcLongJmpAddr, 0, CODEREF_ANCHOR_J);
    xtensa_j(ExcLongJmpAddr - CodeLen);
    EmitExit(EXITCODE_UNHANDLED_EXCEPTION);
  end
  else if TargetArch = TARGET_XTENSA then
  begin
    { --- Xtensa WINDOWED: a longjmp that uses no privileged instruction -----
      MEASURED end to end before any of this was written --
      devdocs/dev/xtensa-windowed-spill-probes.md and its builder
      devdocs/dev/xtensa-windowed-longjmp-probe.py, which transfers control 20
      frames deep back into a call8 frame under qemu-xtensa with both save areas
      intact (rc 50) and fails with the spill removed (rc 52).

      WHY NOT NEWLIB'S DESIGN. newlib's windowed longjmp declares exactly one
      live window through `wsr.windowstart` and then lets an ordinary RETW
      underflow the target frame back from memory. Both that and the
      `rsr.windowbase` that computes its operand SIGILL under qemu-xtensa
      linux-user, and the Linux `spill_registers` syscall it uses in setjmp is
      `Unknown syscall 0` there -- it returns without spilling, so a probe that
      only checks for a crash reports it working. What is left is the call-chain
      spill, which the plan had filed as the bare-metal-only fallback and which
      is in fact the one primitive available on every profile.

      THE MECHANISM. A RETW takes its window increment from the top two bits of
      a0 and reloads the target frame through the window UNDERFLOW handler --
      but only for a window whose windowstart bit is clear. So: spill everything
      (which clears those bits and writes every frame to memory), write the try
      frame's two save areas back the way they were when setjmp ran, forge a0
      and a1, and RETW. The hardware does the transfer.

      THE TWO SAVE AREAS ARE IN DIFFERENT PLACES AND ONLY ONE IS VOLATILE, which
      is the whole reason the jmpbuf is 11 words:
        a0-a3 at [callee_sp - 16] -- inside the CALLEE region, so by the time a
          raise happens some deeper frame owns it. setjmp copies it out and
          longjmp puts it back; that is what makes the transfer pretend the
          stack is as it was.
        a4-a7 at [try_frame_caller_sp - 32] -- inside the try frame's OWN frame,
          stable across everything it calls. [F_sp-32], [cs-16] and [cs-20] were
          each tried first and each wrong.

      BOTH STUBS ARE ENTERED BY CALL8 and that is load-bearing twice over: the
      forged call size must equal the size of the call being unwound to, and
      longjmp's own a2 must land in the physical register setjmp's did, which is
      what delivers the 1. EmitXtensaCall8ToCode, never EmitXtensaCallToCode.

      Stubs are entered by CALLn, whose target must be 4-aligned. }
    while (CodeLen mod 4) <> 0 do xtensa_nop;
    ExcSpillAddr := CodeLen;
    { The spill: a self-recursive CALL8 chain deep enough to walk the window
      base past a wrap of the 64-register file. 16 frames x 8 = 128 registers,
      twice the largest file, so it does not depend on which core we are on. }
    xtensa_entry(reg_xtensa_sp, 32);
    xtensa_movi(reg_xtensa_a3, 0);
    { BRANCH DISTANCES ARE LITERAL HERE, not patched after the fact:
      XtensaPatchSkipOver lives in ir_codegen_xtensa.inc, which is include #245
      to this file's #129, and FPC is single-pass. Every instruction skipped is
      a fixed 3 bytes and the recursive call is xtensa_call8 rather than
      EmitXtensaCall8ToCode for the same reason -- a helper that MIGHT widen to
      the long form would make the distance a guess. Both targets are inside
      this blob, so the direct form always reaches. }
    xtensa_beq(reg_xtensa_a2, reg_xtensa_a3, 12);      { count = 0: -> retw }
    xtensa_addi(reg_xtensa_a2, reg_xtensa_a2, -1);
    xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);
    { RECORDED WITHOUT WIDENING, which is why the note above stands unchanged:
      it objects to EmitXtensaCall8ToCode because that helper MIGHT widen and
      the `beq ..., 12` above counts fixed 3-byte instructions. Recording is a
      separate concern from choosing the form -- CODEREF_ANCHOR_CALL8 says
      "re-encode this short call8 in place", so the slot stays 3 bytes and DCE
      can still re-aim it and protect the target. The two were coupled only
      because the helper did both. }
    RecordCodeRefFull(CodeLen, ExcSpillAddr, 0, CODEREF_ANCHOR_CALL8);
    xtensa_call8(ExcSpillAddr - CodeLen);
    xtensa_retw;

    while (CodeLen mod 4) <> 0 do xtensa_nop;
    ExcSetJmpAddr := CodeLen;                          { a2 = &jmpbuf }
    xtensa_entry(reg_xtensa_sp, 32);
    xtensa_movi(reg_xtensa_a10, 16);
    EmitXtensaCall8ToCode(ExcSpillAddr);
    xtensa_addi(reg_xtensa_a8, reg_xtensa_sp, -16);    { the try frame's a0-a3 }
    for k := 0 to 3 do
    begin
      xtensa_l32i(reg_xtensa_a9, reg_xtensa_a8, k * 4);
      xtensa_s32i(reg_xtensa_a9, reg_xtensa_a2, k * 4);
    end;
    xtensa_l32i(reg_xtensa_a8, reg_xtensa_a8, 4);      { a8 = the try frame's sp }
    xtensa_addi(reg_xtensa_a8, reg_xtensa_a8, -16);
    xtensa_l32i(reg_xtensa_a8, reg_xtensa_a8, 4);      { a8 = ITS caller's sp }
    xtensa_s32i(reg_xtensa_a8, reg_xtensa_a2, 40);
    xtensa_addi(reg_xtensa_a8, reg_xtensa_a8, -32);    { the try frame's a4-a7 }
    for k := 0 to 3 do
    begin
      xtensa_l32i(reg_xtensa_a9, reg_xtensa_a8, k * 4);
      xtensa_s32i(reg_xtensa_a9, reg_xtensa_a2, 16 + k * 4);
    end;
    xtensa_s32i(reg_xtensa_a0, reg_xtensa_a2, 32);     { return address + call bits }
    xtensa_s32i(reg_xtensa_sp, reg_xtensa_a2, 36);     { this stub's own sp }
    xtensa_movi(reg_xtensa_a2, 0);
    xtensa_retw;

    while (CodeLen mod 4) <> 0 do xtensa_nop;
    ExcLongJmpAddr := CodeLen;                         { a2 = &jmpbuf }
    xtensa_entry(reg_xtensa_sp, 32);
    xtensa_movi(reg_xtensa_a10, 16);
    EmitXtensaCall8ToCode(ExcSpillAddr);
    xtensa_l32i(reg_xtensa_a7, reg_xtensa_a2, 36);     { setjmp's sp }
    xtensa_addi(reg_xtensa_a8, reg_xtensa_a7, -16);
    for k := 0 to 3 do
    begin
      xtensa_l32i(reg_xtensa_a9, reg_xtensa_a2, k * 4);
      xtensa_s32i(reg_xtensa_a9, reg_xtensa_a8, k * 4);
    end;
    xtensa_l32i(reg_xtensa_a8, reg_xtensa_a2, 40);
    xtensa_addi(reg_xtensa_a8, reg_xtensa_a8, -32);
    for k := 0 to 3 do
    begin
      xtensa_l32i(reg_xtensa_a9, reg_xtensa_a2, 16 + k * 4);
      xtensa_s32i(reg_xtensa_a9, reg_xtensa_a8, k * 4);
    end;
    xtensa_l32i(reg_xtensa_a0, reg_xtensa_a2, 32);     { forge the return }
    xtensa_movi(reg_xtensa_a2, 1);
    xtensa_mov(reg_xtensa_sp, reg_xtensa_a7);          { a1 LAST: everything above reads it }
    xtensa_retw;

    while (CodeLen mod 4) <> 0 do xtensa_nop;
    ExcRaiseAddr := CodeLen;
    xtensa_entry(reg_xtensa_sp, 32);
    { a0 is the raise site's return address WITH its two call-size bits, so
      EXC_ADDR records a value 0x40000000 above the address on windowed. It is
      a diagnostic slot with no reader on this target (the Call0 arm below
      parks rather than printing), and masking it would cost a shift pair for
      nothing -- but it is not the same number Call0 stores, so say so. }
    XtensaEmitLitHeader;
    EmitGlobRef(BSS_EXC_ADDR);
    xtensa_l32r(reg_xtensa_a3, $FFFF);
    xtensa_s32i(reg_xtensa_a0, reg_xtensa_a3, 0);
    XtensaEmitLitHeader;
    EmitGlobRef(BSS_EXC_TOP);
    xtensa_l32r(reg_xtensa_a3, $FFFF);
    xtensa_l32i(reg_xtensa_a2, reg_xtensa_a3, 0);      { top handler frame }
    xtensa_movi(reg_xtensa_a4, 0);
    { THE ONLY ARM OF THE SIX THAT HARDCODED ITS DISPLACEMENT, and the only one
      that spelled its stub call raw. Both are 2026-09-22 and they are one fix,
      because separating them would turn a latent bug into a live one.

      The raw `xtensa_call8(ExcLongJmpAddr - CodeLen)` recorded no CodeRef, so
      DCE neither protected __pxx_longjmp's bytes nor re-aimed the displacement
      -- the same defect EmitXtensaCall8ToCode was written for, two call sites
      up in this same procedure (ExcSpillAddr, twice). A SPELLING, not a shape:
      grepping for the construct finds the helper, not this.

      And `9` was correct only while the call is the SHORT form: 3 (beq) + 3
      (addi) + 3 (call8). EmitXtensaCall8ToCode widens to a literal slot when
      the target is out of reach, which would leave that 9 landing inside the
      widened call. So the branch is patched from CodeLen like its five
      siblings (x86-64 :153, :303, arm32 :368, aarch64, riscv32 :507) rather
      than counting bytes that a helper is now allowed to choose.

      EmitXtensaCall8ToCode and NOT EmitXtensaCallToCode -- the prescription in
      bug-a-two-code-to-code-references-are-unrecorded named the latter, and it
      is the CALL0 helper: __pxx_longjmp is entered with its argument in a10 by
      the addi below, which is the windowed CALL8 convention, and the call0
      helper would pass it in a2 and rotate no window. The distinction is the
      one EmitXtensaCall8ToCode's own header is named for. }
    unhandledJmp := CodeLen;
    xtensa_beq(reg_xtensa_a2, reg_xtensa_a4, 4);       { patched below: no handler -> park }
    xtensa_addi(reg_xtensa_a10, reg_xtensa_a2, EXC_JMP_OFFSET_XTW);
    EmitXtensaCall8ToCode(ExcLongJmpAddr);             { never returns here }
    Patch24(unhandledJmp,
            EncodeXtensaBranch(1, reg_xtensa_a2, reg_xtensa_a4,
                               CodeLen - unhandledJmp));
    EmitExit(EXITCODE_UNHANDLED_EXCEPTION);
  end
  { NO SECOND riscv32 ARM. The park-and-exit stub this arm replaced was spelled
    `(TargetArch = TARGET_XTENSA) or (TargetArch = TARGET_RISCV32)`, and the
    riscv32 half of that condition was ALREADY unreachable -- the real riscv32
    arm above is unconditional and takes every riscv32 build, hosted and bare.
    It read as "riscv32 has no runtime either", which stopped being true when
    feature-esp-bare-exceptions gave it one and nobody trimmed the condition.
    Verified before deleting: the arm above has no inner guard and no early
    Exit, so nothing reaches here with TargetArch = TARGET_RISCV32. }
  else if TargetArch = TARGET_WASM32 then
  begin
    { NO RUNTIME, and that is the design rather than a gap. Every other arm of
      this chain emits machine code — a setjmp, a longjmp, a raise stub that
      walks the handler chain — because a raise has to reach a landing pad
      through an address. wasm has no code addresses at all: its calls are
      function INDICES and its branches are structural, so there is nothing an
      emitted stub could be reached BY. The whole mechanism therefore lives in
      the lowering — a raise sets a pending flag and two status slots, then
      branches to the enclosing handler's pad through the br_table dispatch
      the bodies already have, and every call site checks the flag afterwards.
      No engine proposal, no version dependency, no trampoline.
      devdocs/dev/wasm/phase5-exceptions.md, test/wasm/proto/check.sh.

      -1, NOT CodeLen. The xtensa arm four lines above sets its three addresses
      to CodeLen and follows them with EmitExit, which is right there: its
      stub is REACHABLE — a `call` to that offset is expressible — so the trap
      is the difference between a clean exit and running whatever follows.
      Here nothing can reach these values, so the useful thing is not a trap
      but a POISON: -1 is not a plausible code offset, so if a future shared
      path ever does route wasm through IREmitCodeCall, it shows up as an
      obviously wrong number rather than as a silent branch to offset 0.

      Erroring here was correct until the lowering existed and is now wrong:
      it would refuse every program containing `try`, including the ones the
      lowering handles. }
    ExcSetJmpAddr  := -1;
    ExcLongJmpAddr := -1;
    ExcRaiseAddr   := -1;
  end
  else
    Error('compiler error: no exception runtime for target '
          + TargetArchName(TargetArch)
          + ' — add an arm here when adding a target');
end;
