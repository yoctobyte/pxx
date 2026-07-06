{ SPDX-License-Identifier: MPL-2.0 }
{ ===== Thread runtime emission ===== }

{ The only machine-code part of libc-free threading: a bare clone+trampoline stub.
  Everything else (futex wait/wake, mmap'd stacks, join, the PAL/TThread layers) is
  Pascal in the PXX-only RTL, built on __pxxrawsyscall.

  clone(2) cannot go through __pxxrawsyscall: after the syscall the CHILD resumes
  inside the syscall wrapper on a brand-new stack and would `ret` through a torn
  frame. The child must instead branch on its zero return, fetch the entry pointer +
  argument that the parent staged on the new stack, `call` the Pascal entry, then
  SYS_exit — never returning to Pascal code. That branch is why this is a hand-emitted
  stub rather than inline asm (pxx inline-asm has no branches yet).

  __pxxclone(flags, childStack, entry, arg, ctidptr): Int64
    flags     (arg1) -> clone flags. Callers pass PXX_CLONE_THREAD which includes
                        CLONE_PARENT_SETTID|CLONE_CHILD_CLEARTID so the kernel writes
                        the child tid into *ctidptr at clone time and clears it +
                        futex-wakes on exit (the join handshake).
    childStack(arg2) -> highest address of the child's stack (grows down); must be
                        16-byte aligned. The stub stages [entry][arg] just below it.
    entry     (arg3) -> ^procedure(arg: Pointer); cdecl-free, called with arg in rdi.
    arg       (arg4) -> opaque pointer handed to entry.
    ctidptr   (arg5) -> &tidword, the CLONE_*_*TID futex word used by join.
  Returns the child tid in the parent; the child path never returns.

  The IR_CLONE lowering moves the five args into the SysV arg regs (rdi,rsi,rdx,rcx,r8)
  and `call`s this stub, so the stub's input contract is exactly that register set.

  Emitted lazily and exactly once, the first time IR_CLONE is codegen'd, fronted by a
  `jmp` over itself so it is reached only by `call` (never fallen through). Lazy +
  self-contained means it works no matter where __pxxclone is used — main program or
  a `uses`d unit pulled in after the up-front runtime-stub region. CloneStubAddr = 0
  marks "not yet emitted". }

procedure EnsureCloneStub;
var
  jmpOver: Integer;
begin
  if CloneStubAddr <> 0 then Exit;
  if TargetArch = TARGET_X86_64 then
  begin
    { jump over the stub body — execution must reach it only via `call`. }
    EmitB($E9); jmpOver := CodeLen; EmitI32(0);
    CloneStubAddr := CodeLen;
    { input: rdi=flags rsi=childStack rdx=entry rcx=arg r8=ctidptr }
    EmitB($48); EmitB($83); EmitB($EE); EmitB($10);   { sub rsi, 16   (stage area) }
    EmitB($48); EmitB($89); EmitB($16);               { mov [rsi], rdx     (entry) }
    EmitB($48); EmitB($89); EmitB($4E); EmitB($08);   { mov [rsi+8], rcx   (arg) }
    EmitB($4C); EmitB($89); EmitB($C2);               { mov rdx, r8    (parent_tid = ctidptr) }
    EmitB($4D); EmitB($89); EmitB($C2);               { mov r10, r8    (child_tid  = ctidptr) }
    EmitB($45); EmitB($31); EmitB($C0);               { xor r8d, r8d   (tls = NULL) }
    EmitB($B8); EmitB($38); EmitB($00); EmitB($00); EmitB($00);   { mov eax, 56  (SYS_clone) }
    EmitB($0F); EmitB($05);                           { syscall }
    EmitB($48); EmitB($85); EmitB($C0);               { test rax, rax }
    EmitB($75); EmitB($0D);                           { jnz .parent  (skip 13 child bytes) }
    { ---- child: rsp = childStack-16, [rsp]=entry [rsp+8]=arg ---- }
    EmitB($58);                                       { pop rax  (entry) }
    EmitB($5F);                                       { pop rdi  (arg -> first int arg) }
    EmitB($FF); EmitB($D0);                           { call rax (entry(arg)) }
    EmitB($31); EmitB($FF);                           { xor edi, edi  (exit code 0) }
    EmitB($B8); EmitB($3C); EmitB($00); EmitB($00); EmitB($00);   { mov eax, 60  (SYS_exit) }
    EmitB($0F); EmitB($05);                           { syscall  (thread exits here) }
    { ---- .parent: rax already = child tid ---- }
    EmitB($C3);                                       { ret }
    { patch the jump-over to land here, past the stub. }
    Patch32(jmpOver, CodeLen - (jmpOver + 4));
  end;
  if TargetArch = TARGET_I386 then
  begin
    { i386 leg. Stub contract: plain stack args (pushed left-to-right by the
      IR_CLONE caller, so arg1 = flags is deepest), result in eax; ebx/esi/edi
      preserved on the parent path (the backend keeps values in them). i386
      clone(2) via int 0x80: eax=120, ebx=flags, ecx=child_stack,
      edx=parent_tid, esi=tls(user_desc*), edi=child_tid — NOTE tls and ctid
      are SWAPPED relative to x86-64's r10/r8 order. The child pops the staged
      entry, leaving arg at [esp] = exactly the stack-arg slot a `call` turns
      into the callee's [ebp+8]. }
    EmitB($E9); jmpOver := CodeLen; EmitI32(0);
    CloneStubAddr := CodeLen;
    { after the 3 saves: [esp+16]=ctidptr [esp+20]=arg [esp+24]=entry
      [esp+28]=childStack [esp+32]=flags (ret addr at [esp+12]) }
    EmitB($53);                                       { push ebx }
    EmitB($56);                                       { push esi }
    EmitB($57);                                       { push edi }
    EmitB($8B); EmitB($5C); EmitB($24); EmitB($20);   { mov ebx, [esp+32]  (flags) }
    EmitB($8B); EmitB($4C); EmitB($24); EmitB($1C);   { mov ecx, [esp+28]  (childStack) }
    EmitB($83); EmitB($E9); EmitB($08);               { sub ecx, 8         (stage area) }
    EmitB($8B); EmitB($44); EmitB($24); EmitB($18);   { mov eax, [esp+24]  (entry) }
    EmitB($89); EmitB($01);                           { mov [ecx], eax }
    EmitB($8B); EmitB($44); EmitB($24); EmitB($14);   { mov eax, [esp+20]  (arg) }
    EmitB($89); EmitB($41); EmitB($04);               { mov [ecx+4], eax }
    EmitB($8B); EmitB($54); EmitB($24); EmitB($10);   { mov edx, [esp+16]  (parent_tid = ctidptr) }
    EmitB($8B); EmitB($7C); EmitB($24); EmitB($10);   { mov edi, [esp+16]  (child_tid  = ctidptr) }
    EmitB($31); EmitB($F6);                           { xor esi, esi       (tls = NULL) }
    EmitB($B8); EmitB($78); EmitB($00); EmitB($00); EmitB($00);   { mov eax, 120  (SYS_clone) }
    EmitB($CD); EmitB($80);                           { int 0x80 }
    EmitB($85); EmitB($C0);                           { test eax, eax }
    EmitB($75); EmitB($0C);                           { jnz .parent  (skip 12 child bytes) }
    { ---- child: esp = childStack-8, [esp]=entry [esp+4]=arg ---- }
    EmitB($58);                                       { pop eax  (entry; arg stays at [esp]) }
    EmitB($FF); EmitB($D0);                           { call eax (entry(arg), caller-cleans convention) }
    EmitB($31); EmitB($DB);                           { xor ebx, ebx  (exit code 0) }
    EmitB($B8); EmitB($01); EmitB($00); EmitB($00); EmitB($00);   { mov eax, 1  (SYS_exit) }
    EmitB($CD); EmitB($80);                           { int 0x80  (thread exits here) }
    { ---- .parent: eax = child tid ---- }
    EmitB($5F);                                       { pop edi }
    EmitB($5E);                                       { pop esi }
    EmitB($5B);                                       { pop ebx }
    EmitB($C3);                                       { ret }
    Patch32(jmpOver, CodeLen - (jmpOver + 4));
  end;
  if TargetArch = TARGET_AARCH64 then
  begin
    { aarch64 leg. Stub input contract (set by IR_CLONE): x0=flags x1=childStack
      x2=entry x3=arg x4=ctidptr. aarch64 clone(2) arg order is x0=flags,
      x1=stack, x2=parent_tid, x3=tls, x4=child_tid (tls/ctid are NOT swapped the
      way x86-64 needs). Child resumes with sp = the stack arg; the stub stages
      [entry][arg] at the top so the child pops them. SYS_clone=220, SYS_exit=93,
      svc #0. Hex verified against aarch64-linux-gnu-as. }
    EmitI32($14000000);                 { b .parent-skip — patched below (branch over stub) }
    jmpOver := CodeLen - 4;
    CloneStubAddr := CodeLen;
    EmitI32($D1004021);                 { sub  x1, x1, #16        (stage area) }
    EmitI32($F9000022);                 { str  x2, [x1]           (entry) }
    EmitI32($F9000423);                 { str  x3, [x1, #8]       (arg) }
    EmitI32($AA0403E2);                 { mov  x2, x4             (parent_tid = ctidptr) }
    EmitI32($D2800003);                 { mov  x3, #0             (tls = NULL) }
    EmitI32($D2801B88);                 { mov  x8, #220           (SYS_clone) }
    EmitI32($D4000001);                 { svc  #0 }
    EmitI32($B50000E0);                 { cbnz x0, .parent  (+7 words) }
    { ---- child: sp = childStack-16, [sp]=entry [sp+8]=arg ---- }
    EmitI32($F94003E1);                 { ldr  x1, [sp]           (entry) }
    EmitI32($F94007E0);                 { ldr  x0, [sp, #8]       (arg -> x0) }
    EmitI32($D63F0020);                 { blr  x1                 (entry(arg)) }
    EmitI32($D2800000);                 { mov  x0, #0             (exit code 0) }
    EmitI32($D2800BA8);                 { mov  x8, #93            (SYS_exit) }
    EmitI32($D4000001);                 { svc  #0                 (thread exits here) }
    { ---- .parent: x0 = child tid ---- }
    EmitI32($D65F03C0);                 { ret }
    { patch the leading branch to land here (past the stub). B imm26 in words. }
    Patch32(jmpOver, $14000000 or (((CodeLen - jmpOver) div 4) and $03FFFFFF));
  end;
  { esp/riscv32 stay out of scope for threading; IR_CLONE guards them with a
    clean compile-error, so EnsureCloneStub is never reached there. }
end;
