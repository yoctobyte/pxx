{ SPDX-License-Identifier: MPL-2.0 }
{ ===== Coroutine runtime emission ===== }

{ The only machine-code part of the stackful-coroutine / generator machinery: a
  bare context-switch routine. Everything else (heap stacks, scheduler, the
  iterator protocol, generator glue) is Pascal in the PXX-only RTL.

  TCoroCtx is just a saved stack pointer: TCoroCtx = record sp: Pointer end.
  All callee-saved registers and the per-stack exception-chain head live ON the
  switched stack, so CoSwitch only has to swap rsp.

  CoSwitch(pfrom, pto: Pointer)
    pfrom (rdi) -> ^TCoroCtx of the current context (its sp is written)
    pto   (rsi) -> ^TCoroCtx of the target context  (its sp is loaded)

  It saves the callee-saved set + BSS_EXC_TOP onto the current stack, stores rsp
  into [pfrom], loads rsp from [pto], restores that context's saved state and
  `ret`s — returning into wherever the target last called CoSwitch (or, for a
  freshly-built context, into its entry trampoline). Because the resume point is
  the return address on each stack, CoSwitch must be reached by `call`; it can
  never be inlined. }

procedure EmitCoroutineRuntime;
begin
  if TargetArch = TARGET_X86_64 then
  begin
    CoSwitchAddr := CodeLen;
    EmitB($55);                                                 { push rbp }
    EmitB($53);                                                 { push rbx }
    EmitB($41); EmitB($54);                                     { push r12 }
    EmitB($41); EmitB($55);                                     { push r13 }
    EmitB($41); EmitB($56);                                     { push r14 }
    EmitB($41); EmitB($57);                                     { push r15 }
    EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_TOP); { mov rax, [BSS_EXC_TOP] }
    EmitB($50);                                                 { push rax }
    EmitB($48); EmitB($89); EmitB($27);                         { mov [rdi], rsp }
    EmitB($48); EmitB($8B); EmitB($26);                         { mov rsp, [rsi] }
    EmitB($58);                                                 { pop rax }
    EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_EXC_TOP); { mov [BSS_EXC_TOP], rax }
    EmitB($41); EmitB($5F);                                     { pop r15 }
    EmitB($41); EmitB($5E);                                     { pop r14 }
    EmitB($41); EmitB($5D);                                     { pop r13 }
    EmitB($41); EmitB($5C);                                     { pop r12 }
    EmitB($5B);                                                 { pop rbx }
    EmitB($5D);                                                 { pop rbp }
    EmitB($C3);                                                 { ret }
  end
  else if TargetArch = TARGET_I386 then
  begin
    { i386: args on the stack (pfrom=[esp+4], pto=[esp+8] at entry). Callee-saved
      set = ebx,esi,edi,ebp; plus BSS_EXC_TOP. Load the two pointer args into
      scratch (ecx/edx) before the pushes move esp, then mirror the x86-64 swap. }
    CoSwitchAddr := CodeLen;
    EmitB($8B); EmitB($4C); EmitB($24); EmitB($04);             { mov ecx, [esp+4]  (pfrom) }
    EmitB($8B); EmitB($54); EmitB($24); EmitB($08);             { mov edx, [esp+8]  (pto) }
    EmitB($55);                                                 { push ebp }
    EmitB($53);                                                 { push ebx }
    EmitB($56);                                                 { push esi }
    EmitB($57);                                                 { push edi }
    EmitB($A1); EmitGlobRef(BSS_EXC_TOP);                       { mov eax, [BSS_EXC_TOP] }
    EmitB($50);                                                 { push eax }
    EmitB($89); EmitB($21);                                     { mov [ecx], esp }
    EmitB($8B); EmitB($22);                                     { mov esp, [edx] }
    EmitB($58);                                                 { pop eax }
    EmitB($A3); EmitGlobRef(BSS_EXC_TOP);                       { mov [BSS_EXC_TOP], eax }
    EmitB($5F);                                                 { pop edi }
    EmitB($5E);                                                 { pop esi }
    EmitB($5B);                                                 { pop ebx }
    EmitB($5D);                                                 { pop ebp }
    EmitB($C3);                                                 { ret }
  end
  else if TargetArch = TARGET_AARCH64 then
  begin
    { aarch64: pfrom=x0, pto=x1 (AAPCS64). Save GP callee-saved x19-x30 +
      BSS_EXC_TOP onto the current stack (x9/x10 scratch), swap sp via
      [x0]/[x1]. &BSS_EXC_TOP is loaded via a PC-relative 4-byte literal, the
      same shape as IR_EXC_ENTER. }
    CoSwitchAddr := CodeLen;
    EmitI32($A9BF53F3);   { stp x19, x20, [sp, #-16]! }
    EmitI32($A9BF5BF5);   { stp x21, x22, [sp, #-16]! }
    EmitI32($A9BF63F7);   { stp x23, x24, [sp, #-16]! }
    EmitI32($A9BF6BF9);   { stp x25, x26, [sp, #-16]! }
    EmitI32($A9BF73FB);   { stp x27, x28, [sp, #-16]! }
    EmitI32($A9BF7BFD);   { stp x29, x30, [sp, #-16]! }
    EmitI32($18000049);   { ldr w9, [pc, #8]  (-> &BSS_EXC_TOP) }
    EmitI32($14000002);   { b   .+8           (skip the literal) }
    EmitGlobRef(BSS_EXC_TOP);
    EmitI32($F940012A);   { ldr x10, [x9]     (exc_top value) }
    EmitI32($F81F0FEA);   { str x10, [sp, #-16]! }
    EmitI32($910003E9);   { mov x9, sp }
    EmitI32($F9000009);   { str x9, [x0]      (*pfrom = sp) }
    EmitI32($F9400029);   { ldr x9, [x1]      (sp <- *pto) }
    EmitI32($9100013F);   { mov sp, x9 }
    EmitI32($F84107EA);   { ldr x10, [sp], #16  (exc_top value) }
    EmitI32($18000049);   { ldr w9, [pc, #8]  (-> &BSS_EXC_TOP) }
    EmitI32($14000002);   { b   .+8 }
    EmitGlobRef(BSS_EXC_TOP);
    EmitI32($F900012A);   { str x10, [x9]     (BSS_EXC_TOP = value) }
    EmitI32($A8C17BFD);   { ldp x29, x30, [sp], #16 }
    EmitI32($A8C173FB);   { ldp x27, x28, [sp], #16 }
    EmitI32($A8C16BF9);   { ldp x25, x26, [sp], #16 }
    EmitI32($A8C163F7);   { ldp x23, x24, [sp], #16 }
    EmitI32($A8C15BF5);   { ldp x21, x22, [sp], #16 }
    EmitI32($A8C153F3);   { ldp x19, x20, [sp], #16 }
    EmitI32($D65F03C0);   { ret }
  end
  else if TargetArch = TARGET_ARM32 then
  begin
    { arm32: pfrom=r0, pto=r1 (AAPCS). Save callee-saved r4-r11 + lr +
      BSS_EXC_TOP onto the current stack (r2/r3 scratch), swap sp via [r0]/[r1].
      &BSS_EXC_TOP loaded via a PC-relative 4-byte literal (IR_EXC_ENTER shape).
      All 4-byte instructions keep the ARM alignment invariant. }
    CoSwitchAddr := CodeLen;
    EmitI32($E92D4FF0);   { push {r4-r11, lr} }
    EmitI32($E59F2000);   { ldr r2, [pc]   (-> &BSS_EXC_TOP) }
    EmitI32($EA000000);   { b .+8          (skip the literal) }
    EmitGlobRef(BSS_EXC_TOP);
    EmitI32($E5923000);   { ldr r3, [r2]   (exc_top value) }
    EmitI32($E52D3004);   { push {r3}      (str r3, [sp, #-4]!) }
    EmitI32($E580D000);   { str sp, [r0]   (*pfrom = sp) }
    EmitI32($E591D000);   { ldr sp, [r1]   (sp <- *pto) }
    EmitI32($E49D3004);   { pop {r3}       (ldr r3, [sp], #4) }
    EmitI32($E59F2000);   { ldr r2, [pc]   (-> &BSS_EXC_TOP) }
    EmitI32($EA000000);   { b .+8 }
    EmitGlobRef(BSS_EXC_TOP);
    EmitI32($E5823000);   { str r3, [r2]   (BSS_EXC_TOP = value) }
    EmitI32($E8BD4FF0);   { pop {r4-r11, lr} }
    EmitI32($E12FFF1E);   { bx lr }
  end;
  { Other targets land in later phases (riscv32/xtensa). }
end;
{ EnableCoroutineRuntime lives in parser.inc (it must call EnableExceptionRuntime,
  defined there) — see near EnableExceptionRuntime. }
