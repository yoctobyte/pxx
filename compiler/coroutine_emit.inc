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
  end;
  { Other targets land in later phases (i386/aarch64/arm32/riscv32/xtensa). }
end;
{ EnableCoroutineRuntime lives in parser.inc (it must call EnableExceptionRuntime,
  defined there) — see near EnableExceptionRuntime. }
