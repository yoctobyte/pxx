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
    EmitStatusSlotX64(0, BSS_EXC_TOP, False);                   { mov rax, [BSS_EXC_TOP] }
    EmitB($50);                                                 { push rax }
    EmitB($48); EmitB($89); EmitB($27);                         { mov [rdi], rsp }
    EmitB($48); EmitB($8B); EmitB($26);                         { mov rsp, [rsi] }
    EmitB($58);                                                 { pop rax }
    EmitStatusSlotX64(0, BSS_EXC_TOP, True);                    { mov [BSS_EXC_TOP], rax }
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
    EmitMovGlobAcc($A1, BSS_EXC_TOP);                       { mov eax, [BSS_EXC_TOP] }
    EmitB($50);                                                 { push eax }
    EmitB($89); EmitB($21);                                     { mov [ecx], esp }
    EmitB($8B); EmitB($22);                                     { mov esp, [edx] }
    EmitB($58);                                                 { pop eax }
    EmitMovGlobAcc($A3, BSS_EXC_TOP);                       { mov [BSS_EXC_TOP], eax }
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
  end
  else if TargetArch = TARGET_RISCV32 then
  begin
    { riscv32: pfrom=a0, pto=a1 (psABI). The saved frame is SIXTEEN bytes --
      exc_top, s0, ra, pad -- and the pad is what keeps sp 16-byte aligned,
      which the psABI requires at every call boundary.

      THREE SLOTS RATHER THAN THIRTEEN, and that is riscv32-specific rather
      than a shortcut: this backend's codegen never touches s1-s11 (the same
      fact exception_emit.inc's jmpbuf relies on, where the frame is likewise
      s0/sp/ra). Saving registers no generated code writes would cost 44 bytes
      per switch to preserve zeroes. If that ever stops being true, the
      exception stub is wrong in the same way and both move together.

      BSS_EXC_TOP is threaded through the switch exactly as arm32 and aarch64
      do it -- each coroutine stack owns its own exception chain, so the value
      travels with the stack rather than staying global. The address comes from
      the auipc + inline-literal trick the raise stub uses (auipc puts PC in the
      register, the jal steps over the 4-byte literal, the lw reads it back).
      feature-a-a-stackful-coroutine-is-four-targets-only-so-examples-net-httpdemo-cannot-cross }
    CoSwitchAddr := CodeLen;
    rv32_addi(reg_sp, reg_sp, -16);
    rv32_sw(reg_s0, reg_sp, 4);
    rv32_sw(reg_ra, reg_sp, 8);
    rv32_auipc(reg_t0, 0);                { &BSS_EXC_TOP }
    rv32_jal(reg_zero, 8);
    EmitGlobRef(BSS_EXC_TOP);
    rv32_lw(reg_t0, reg_t0, 8);
    rv32_lw(reg_t1, reg_t0, 0);           { t1 = exc_top }
    rv32_sw(reg_t1, reg_sp, 0);           { save it on THIS stack }
    rv32_sw(reg_sp, reg_a0, 0);           { *pfrom = sp }
    rv32_lw(reg_sp, reg_a1, 0);           { sp <- *pto }
    rv32_lw(reg_t1, reg_sp, 0);           { the other stack's exc_top }
    rv32_sw(reg_t1, reg_t0, 0);           { BSS_EXC_TOP = it }
    rv32_lw(reg_s0, reg_sp, 4);
    rv32_lw(reg_ra, reg_sp, 8);
    rv32_addi(reg_sp, reg_sp, 16);
    rv32_jalr(reg_zero, reg_ra, 0);       { ret }
  end
  else if (TargetArch = TARGET_XTENSA) and (XtensaABI = XTENSA_ABI_CALL0) then
  begin
    { xtensa Call0: pfrom=a2, pto=a3 (Call0 passes arg0..arg5 in a2..a7). The
      saved frame is SIXTEEN bytes — exc_top, a15, a0, pad — and the pad is what
      keeps sp 16-byte aligned, which the Call0 ABI requires at every call
      boundary. Same size and same slot ORDER as riscv32's, deliberately, so the
      RTL's priming block can be one arch-split with two register names rather
      than two layouts.

      THREE SLOTS, AND THE AUTHORITY FOR THAT IS exception_emit.inc, NOT A
      GUESS AT THE ABI. Call0's callee-saved set is nominally a12-a15, and this
      backend uses a15 as its frame pointer while treating a12/a13 as
      expression scratch (see the soft-mulhigh expansion, which movi's into
      both). The jmpbuf this compiler actually ships saves exactly
      (a15, sp, a0) — the direct mirror of riscv32's (s0, sp, ra) — so a
      setjmp/longjmp pair already asserts that nothing else survives a call
      here. A CoSwitch saving MORE than the jmpbuf would be claiming a
      guarantee the exception runtime does not make; saving less would break
      both. If that ever stops being true, the exception stub is wrong in the
      same way and the two move together — which is riscv32's own note, and it
      is load-bearing on xtensa rather than merely tidy.

      THE nop PADDING IS NOT COSMETIC AND riscv32 HAS NO EQUIVALENT. CoSwitch
      is reached by `call0`, whose target must be 4-BYTE ALIGNED — Call0 encodes
      the low two bits of the target as zero, so an unaligned entry silently
      enters at a DIFFERENT address rather than faulting. Every stub in
      exception_emit.inc pads for this reason; a coroutine switch that skipped
      it would work or not depending on how much code happened to precede it.

      BSS_EXC_TOP travels with the stack, as on arm32/aarch64/riscv32: each
      coroutine owns its own exception chain, so a `raise` inside a coroutine
      walks that coroutine's handlers. The address comes from the literal-pool
      idiom the raise stub uses (XtensaEmitLitHeader jumps over a 4-aligned
      literal slot; l32r with imm16=-1 word reads it back) rather than
      riscv32's auipc trick, because xtensa has no PC-relative add.
      feature-a-coswitch-for-xtensa-and-riscv32-the-scheduler-has-no-context-switch-there }
    while (CodeLen mod 4) <> 0 do xtensa_nop;
    CoSwitchAddr := CodeLen;
    xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, -16);
    xtensa_s32i(reg_xtensa_a15, reg_xtensa_sp, 4);
    xtensa_s32i(reg_xtensa_a0, reg_xtensa_sp, 8);
    XtensaEmitLitHeader;                            { a4 = &BSS_EXC_TOP }
    EmitGlobRef(BSS_EXC_TOP);
    xtensa_l32r(reg_xtensa_a4, $FFFF);
    xtensa_l32i(reg_xtensa_a5, reg_xtensa_a4, 0);   { a5 = exc_top }
    xtensa_s32i(reg_xtensa_a5, reg_xtensa_sp, 0);   { save it on THIS stack }
    xtensa_s32i(reg_xtensa_sp, reg_xtensa_a2, 0);   { *pfrom = sp }
    xtensa_l32i(reg_xtensa_sp, reg_xtensa_a3, 0);   { sp <- *pto }
    xtensa_l32i(reg_xtensa_a5, reg_xtensa_sp, 0);   { the other stack's exc_top }
    xtensa_s32i(reg_xtensa_a5, reg_xtensa_a4, 0);   { BSS_EXC_TOP = it }
    xtensa_l32i(reg_xtensa_a15, reg_xtensa_sp, 4);
    xtensa_l32i(reg_xtensa_a0, reg_xtensa_sp, 8);
    xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, 16);
    xtensa_ret;
  end
  else if TargetArch = TARGET_XTENSA then
    { WINDOWED, and refused SEPARATELY from the generic tail below so the
      message names the ABI rather than the target. The target is supported;
      this ABI is not, and the two want different answers from the reader.

      Why it is genuinely harder and not just unwritten: the windowed ABI keeps
      callee-saved state in a ROTATING REGISTER WINDOW rather than on the stack
      the way this switch assumes, so handing a stack to another context
      requires spilling the window first (and the spill area lives at [sp-16],
      which a switch that moves sp invalidates). It is not Call0's twin and the
      ticket says to sequence the two rather than bundle them. }
    Error('coroutines are not implemented for the xtensa WINDOWED ABI '
          + '(--xtensa-abi=windowed): a context switch has to spill the '
          + 'register window before another context can own the stack. The '
          + 'CALL0 ABI is supported and is the DEFAULT — drop '
          + '--xtensa-abi=windowed, or pass --xtensa-abi=call0 explicitly.')
  else if TargetArch = TARGET_WASM32 then
    Error('wasm32: coroutine context switch not implemented (a wasm module has '
          + 'no addressable stack pointer to swap)')
  else
    { FAIL-CLOSED DEFAULT FOR A TARGET THAT DOES NOT EXIST YET. As of
      2026-09-24 every target this compiler has reaches an arm above — x86-64,
      i386, aarch64, arm32, riscv32, xtensa (Call0 implemented, windowed
      refused by name) and wasm32 — so nothing routes here today and that is
      the point: a new TARGET_* lands with a refusal rather than with silence.

      WHAT SILENCE WOULD COST, and it is why this else is an Error and not a
      comment: falling through leaves CoSwitchAddr at 0 while the caller
      (EnableCoroutineRuntime) has already set CoroutineUsed, so the program
      CALLS ADDRESS ZERO — offset 0 of .text, i.e. the entry point, from inside
      user code. That is a hang or a re-entered program, not a diagnostic.

      Until 2026-09-24 the miscompile was masked downstream, because the
      backends refused IR_COSWITCH ('unsupported node in IR codegen: coswitch')
      so any program that got a stub also got a node they rejected. THAT MASK
      IS NOW GONE on xtensa — the lowering exists — which is exactly the
      fragility the 2026-08-31 note predicted: 'give riscv32 one without adding
      a stub arm here and the downstream guard disappears'. The same sentence
      now applies to the next backend that gains a lowering, so add the stub arm
      and the IR arm in ONE commit.
      refactor-a-target-dispatch-chains-fail-open }
    Error('coroutines are not implemented for target '
          + TargetArchName(TargetArch));
end;
{ EnableCoroutineRuntime lives in pasparser_name.inc (it must call EnableExceptionRuntime,
  defined there) — see near EnableExceptionRuntime. }
