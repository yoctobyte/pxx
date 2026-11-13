{ SPDX-License-Identifier: MPL-2.0 }
{ ===== Thread runtime emission ===== }

procedure EmitCodeAbsToRdx(targetOff: Integer); forward;   { defined in ir_codegen.inc, included later; the FPC seed build resolves in source order. Moved here from frontend_forwards.inc (included after this file). bug-a-fpc-seed-drift-emitasmx64-forward }

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
                        16-byte aligned. The stub carves the child's hidden-destination
                        scratch (CLONE_RETBUF_SIZE, every leg) and TlsBlockSize-byte
                        TLS block (x86-64) off the top, then stages [entry][arg] just
                        below that, so the caller must provide at least
                        CLONE_RETBUF_SIZE + TlsBlockSize + 16 usable bytes.
    entry     (arg3) -> ^procedure(arg: Pointer); cdecl-free, called with arg in rdi.
                        An entry that RETURNS something through the caller-owned hidden
                        destination is called correctly too -- the stub points that
                        register at the scratch above and the child discards the result
                        by exiting. Every NilPy `def` is such an entry (they all return a
                        Variant), which is why nothing set the register was a crash and
                        not a curiosity.
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

function TargetHasTlsBlock: Boolean;
{ Does this target give every thread its own TLS block, the one __pxxTlsBase
  and `threadvar` reach? The ONE predicate; the parser's refusals, the entry
  install and the clone legs all ask it.

  x86-64 installs the block in gs, which no libc uses. aarch64 (tpidr_el0) and
  arm32 (TPIDRURO, set with the set_tls syscall) have ONE thread register, and
  glibc owns it whenever the loader brought glibc in. So on those two targets
  the block is installed in a STATIC binary only. The entry code checks at
  RUNTIME: a static binary starts with the register at 0, and a dynamic one
  starts with it pointing at glibc's TCB. The ELF writer then refuses a dynamic
  binary that reads the block (TlsBaseUsed), so no program can get glibc's TCB
  back from __pxxTlsBase.

  i386 (since 2026-09-27) installs the block in fs through set_thread_area and
  a GDT TLS entry. glibc on i386 uses gs, so, as on x86-64, the two coexist and
  the block is installed in a dynamic binary too. riscv32 and the rest have no
  threads at all (the --threadsafe gate). }
begin
  TargetHasTlsBlock := (TargetArch = TARGET_X86_64) or (TargetArch = TARGET_AARCH64)
                    or (TargetArch = TARGET_ARM32) or (TargetArch = TARGET_I386);
end;

procedure EnsureCloneStub;
var
  jmpOver: Integer;
  pNoInst, pNoInst2, pCopy: Integer;   { the child's skip-the-install branches (aarch64, arm32) }
  pParent: Integer;   { the child/parent split, patched in ALL FOUR legs: rel8 on
                        x86-64/i386, a branch immediate on aarch64/arm32 }
  fbChild: Integer;   { --os=freebsd: the thr_new entry that becomes a clone child }
  pFbB, pFbFail, imm: Integer;   { the aarch64 thr_new leg's patch sites }
  obChild: Integer;   { --os=openbsd: where the translator's __tfork sends the child }

{ The child's kernel entries. Bare instructions everywhere but --os=openbsd,
  where a `syscall` outside the translator's pinned site is killed
  (pinsyscalls), so the child goes through the translator like any other
  code: the thunk saves what the stub needs, and the translator's own frames
  sit below the stage area, on the thread's stack. }
function ChildSys: AnsiString;
begin
  if (TargetKernel = KERNEL_OPENBSD) or (TargetKernel = KERNEL_NETBSD)
     or (TargetKernel = KERNEL_DRAGONFLY) then ChildSys := 'syscall'
  else ChildSys := 'syscall_raw';
end;

begin
  if CloneStubAddr <> 0 then Exit;
  if TargetArch = TARGET_X86_64 then
  begin
    { jump over the stub body — execution must reach it only via `call`. }
    AsmScopeBegin;
    EmitAsmX64(['jmp over']);
    { --os=freebsd: thr_new starts a thread at a FUNCTION (rdi = its arg, rsp
      the kernel's choice), where clone resumes it after the syscall on the
      stack it was handed. This entry turns the one into the other: the arg is
      the stage area, so the child continues at `child` exactly as a clone
      child would, with rsp = the stage. feature-port-freebsd-native }
    fbChild := 0;
    if TargetKernel = KERNEL_FREEBSD then
    begin
      fbChild := CodeLen;
      { ctidptr, parked at stage-8 by the parent, moves into the child's own
        TLS block before anything is pushed over it: slot 14 is i386's
        TLS_SLOT_FS_ENTRY and never written on x86-64 (the block is zeroed). }
      EmitAsmX64([
        'mov rsp, rdi',
        'mov rax, [rsp-8]',
        'mov [rsp+%], rax', 16 + 8 * TLS_SLOT_FS_ENTRY,
        'jmp child']);
    end;
    { --os=openbsd: __tfork resumes the child after the syscall like clone
      does, but that syscall is inside the translator (obsdabi's ObTforkA),
      so ObTforkA sends the child here instead, with rsp = the stage area. }
    obChild := 0;
    if (TargetKernel = KERNEL_OPENBSD) or (TargetKernel = KERNEL_NETBSD)
       or (TargetKernel = KERNEL_DRAGONFLY) then
    begin
      obChild := CodeLen;
      EmitAsmX64(['jmp child']);
    end;
    CloneStubAddr := CodeLen;
    { input: rdi=flags rsi=childStack rdx=entry rcx=arg r8=ctidptr }
    { ---- carve the child's TLS block off the top of its stack ---- }
    { TlsBlockSize bytes = the slot map (16 named slots plus the 64 magazine
      heads and 64 counts behind them) followed by TlsUserBytes of
      source-declared `threadvar` storage. NO SLOT COUNT IN THIS SENTENCE: the
      previous one said 80 and the answer was 144 by the time anyone read it --
      defs.inc owns the census and this is a consumer.
      Zeroed, slot 0 = its own address (the convention __pxxTlsBase reads
      through). The zeroing is not merely hygiene for the magazine tail: an
      all-zero magazine IS "every size class empty", so a fresh thread's
      allocator fast path is correct with no initialisation of its own -- and
      it is now also what makes every `threadvar` start a thread's life at 0,
      which the language requires and a test asserts.
      Zeroed rather than trusted: palthread hands us
      fresh anonymous mmap, but __pxxclone is reachable directly and a reused
      stack would otherwise present the previous thread's slots as this one's.
      cld because rep stosq reads DF and only the ABI (not this stub's caller)
      guarantees it clear. rdi holds flags and rcx holds arg, so both are saved
      across stosq's fixed-register contract. }
    { ---- carve the child's SIGNAL ALT STACK, above the TLS block ---- }
    { sigaltstack(2) is PER-THREAD and is NOT inherited across clone. The only
      other registration is in SigInstallAddr, which runs on whichever thread
      called SetSignalHandler -- so before this, a cloned worker reported
      sp=0 flags=SS_DISABLE size=0 and a stack overflow on it was UNHANDLEABLE:
      the fault happens because there is no stack left, so the kernel has
      nowhere to push the signal frame and kills the process outright. Measured
      on one binary, one argument apart: overflow on main is handled and exits
      7; the same overflow on a __pxxclone worker exits 139 with the handler
      never entered.

      ABOVE THE TLS BLOCK, not below it, and that is the whole of the placement
      argument. The child's rsp starts just under the TLS block and grows DOWN
      from there, so anything carved BELOW would be the region the thread's own
      stack runs through -- the alt stack would be overwritten by ordinary
      calls long before a fault needed it. Carved from the top, the alt stack
      is at the highest addresses of the mapping and the guard page is at the
      lowest, so it is still mapped at the moment the stack is exhausted, which
      is the only property it needs.

      Not a shared BSS buffer: two threads faulting at once would push signal
      frames onto one region. That is why this is per-thread storage and not a
      second use of BSS_SIG_ALTSTK.

      Costs SIG_ALTSTACK_SIZE of every thread's stack (32KB of palthread's 1MB
      default) and one syscall per thread. The floor a caller must now supply is
      TlsBlockSize + SIG_ALTSTACK_SIZE + CLONE_RETBUF_SIZE plus whatever the
      thread actually uses;
      __pxxclone is reachable directly, so a caller passing a stack smaller than
      that was already carving a TLS block out of nothing. }
    { ---- carve the child's HIDDEN-DESTINATION SCRATCH, above everything ----
      Topmost on purpose: every other offset in this leg is expressed from the
      child's rsp, so putting the new region at the TOP leaves all of them
      unchanged and the scratch is the one address computed with the full sum.
      See CLONE_RETBUF_SIZE for why the register must be set at all. }
    EmitAsmX64([
      'sub rsi, %', CLONE_RETBUF_SIZE,
      'sub rsi, %', SIG_ALTSTACK_SIZE,
      'sub rsi, %', TlsBlockSize,
      'cld',
      'push rdi',                       { flags }
      'push rcx',                       { arg }
      'mov rdi, rsi',
      'xor eax, eax',
      'mov ecx, %', TlsBlockSize div 8, { slot count }
      'rep stosq',
      'pop rcx',
      'pop rdi',
      'mov [rsi], rsi',                 { slot 0 = self }
      'sub rsi, 16',                    { stage area }
      'mov [rsi], rdx',                 { entry }
      'mov [rsi+8], rcx']);             { arg }
    if TargetKernel = KERNEL_FREEBSD then
    begin
      { thr_new(&param, 104). The kernel starts the thread on
        [stack_base, stack_base+size) with a fake return slot at the top, so
        the top is put 16 below the stage area: the slot lands below stage-16
        and stage-8 carries ctidptr to the child's entry, which moves it into
        TLS slot 14 for the exit path. The new tid is
        written to a scratch long on THIS stack (thr_new stores longs; the
        caller's word is an int), then stored as CLONE_PARENT_SETTID would --
        after the child may already be running, which the exit path allows
        for. CF set = error, rax the positive errno. }
      EmitAsmX64([
        'mov [rsi-8], r8',              { ctidptr: the child entry moves it into its TLS block }
        'sub rsp, 112']);               { thr_param (104) + tid scratch (8) }
      EmitCodeAbsToRdx(fbChild);
      EmitAsmX64([
        'mov [rsp], rdx',               { start_func }
        'mov [rsp+8], rsi',             { arg = the stage area }
        'lea rax, [rsi-4112]',
        'mov [rsp+16], rax',            { stack_base = stage - 16 - 4096 }
        'mov qword [rsp+24], 4096',     { stack_size }
        'xor eax, eax',
        'mov [rsp+32], rax',            { tls_base }
        'mov [rsp+40], rax',            { tls_size }
        'mov [rsp+64], rax',            { flags (int) + pad }
        'mov [rsp+72], rax',            { rtp }
        'mov [rsp+80], rax',            { spare[0..2] }
        'mov [rsp+88], rax',
        'mov [rsp+96], rax',
        'mov [rsp+104], rax',           { tid scratch }
        'lea rax, [rsp+104]',
        'mov [rsp+48], rax',            { child_tid }
        'mov [rsp+56], rax',            { parent_tid }
        'mov rdi, rsp',
        'mov esi, 104',
        'mov eax, 455',                 { thr_new }
        'syscall_raw',
        'jb fbfail',
        'mov eax, [rsp+104]',           { the tid (lwpid_t fits 32 bits) }
        'test r8, r8',
        'jz fbnoset',
        'mov [r8], eax',                { CLONE_PARENT_SETTID }
      'fbnoset:',
        'add rsp, 112',
        'jmp parent',
      'fbfail:',
        'neg rax',
        'add rsp, 112',
        'jmp parent',
      'child:']);
    end
    else if (TargetKernel = KERNEL_OPENBSD) or (TargetKernel = KERNEL_NETBSD)
            or (TargetKernel = KERNEL_DRAGONFLY) then
    begin
      { Linux clone through the translator, with the child's resume address
        in r9 (clone's unused sixth argument). The translator maps it to
        __tfork (OpenBSD), _lwp_create (NetBSD) or lwp_create2 (DragonFly,
        started at a resume routine); the parent returns here
        with the tid, the child never does. }
      EmitCodeAbsToRdx(obChild);
      EmitAsmX64([
        'mov r9, rdx',
        'mov rdx, r8',                  { parent_tid = ctidptr }
        'mov r10, r8',                  { child_tid  = ctidptr }
        'xor r8d, r8d',                 { tls = NULL }
        'mov eax, 56',                  { SYS_clone }
        'syscall',
        'test rax, rax',
        'jnz parent',
      'child:']);
    end
    else
    begin
      EmitAsmX64([
        'mov rdx, r8',                  { parent_tid = ctidptr }
        'mov r10, r8',                  { child_tid  = ctidptr }
        'xor r8d, r8d',                 { tls = NULL }
        'mov eax, 56',                  { SYS_clone }
        'syscall_raw',
        'test rax, rax']);
      { jnz .parent -- COMPUTED. It was 30 hand-counted bytes over ten
        instructions of child setup, and every one of them is a line someone may
        add to. }
      { rel32, not rel8: the child sequence passed 127 bytes when it gained the
        init-image copy (2026-09-24), and PatchRel8 refused it at build time. }
      EmitAsmX64(['jnz parent']);
    end;
    { ---- child: rsp = tlsBlock-16, [rsp]=entry [rsp+8]=arg ---- }
    { Install the TLS block FIRST, before anything Pascal runs. clone does not
      reset the thread pointer, so a child that skipped this would read the PARENT's block --
      not a null base you could test for, but a valid-looking pointer into
      someone else's storage. Doing it here rather than in the RTL launcher is
      what makes that unreachable: every pxx thread passes through this stub,
      whatever frontend or library created it.
      arch_prctl acts on the CALLING thread, which is why no CLONE_SETTLS, no
      sixth argument and no per-arch tls plumbing are involved
      (feature-a-thread-local-storage-via-clone-settls). GS, not fs: fs belongs
      to libc, and a pxx program may link one. syscall clobbers rcx and r11;
      both are dead here (arg was staged on the stack above). }
    { r12 = the PARENT's init-image pointer, read through gs BEFORE the
      install replaces it. See TLS_SLOT_INIT_IMAGE. }
    if TlsUserBytes > 0 then
    begin
      EmitAsmX64(['mov r12, gs:[%]', 8 * TLS_SLOT_INIT_IMAGE]);
    end;
    if TargetKernel = KERNEL_FREEBSD then
      EmitAsmX64([
        'lea rax, [rsp+16]',
        'push rax',                     { sysarch takes a POINTER to the base }
        'mov rsi, rsp',
        'mov edi, 131',                 { AMD64_SET_GSBASE }
        'mov eax, 165',                 { sysarch }
        'syscall_raw',
        'add rsp, 8'])
    else if not KernelLibc then
    EmitAsmX64([
      'mov edi, 0x1001',              { ARCH_SET_GS }
      'lea rsi, [rsp+16]',
      'mov eax, 158',                   { arch_prctl }
      ChildSys]);
    { ---- start the user area from the init image, when there is one ----
      The block was zeroed above; the image holds every thread-local's
      initial value (0 where it has no initialiser), so this is the start C
      requires for `__thread int x = 5;`. The pointer is handed on in the
      new block's own slot, so a thread this thread creates copies it too. }
    if TlsUserBytes > 0 then
    begin
      EmitAsmX64([
        'test r12, r12',
        'jz short nocopy',
        'mov rsi, r12',
        'lea rdi, [rsp+%]', 16 + TLS_USER_FIRST_OFF,
        'mov ecx, %', TlsUserBytes,
        'cld',
        'rep movsb',
        'mov [rsp+%], r12', 16 + 8 * TLS_SLOT_INIT_IMAGE,
      'nocopy:']);
    end;
    { --os=openbsd --rtl-libc: the install comes AFTER the image copy. The
      child's block is where ld.so put it (below fs, already live), and the
      translator's arch_prctl copies the staged block there, so the staged
      block must be complete first. r12's read above already went to that
      block, whose init-image slot ObClone seeded from the parent's. }
    if KernelLibc then
      EmitAsmX64([
        'mov edi, 0x1001',              { ARCH_SET_GS }
        'lea rsi, [rsp+16]',
        'mov eax, 158',                 { arch_prctl }
        ChildSys]);
    { ---- register the alt stack carved above, on THIS thread ---- }
    { The stack_t is built on the child's own stack rather than in BSS for the
      same reason the buffer is per-thread: a shared struct is a race between
      two threads registering at once, and this one is dead the instant the
      syscall returns. 32 rather than 24 keeps rsp 16-aligned across the call.
      altBase = tlsBlock + TlsBlockSize, and tlsBlock is rsp+16 -- the stage
      area holding (entry, arg) is the 16 bytes below it.
      rdi, rsi and rax are all dead here: rdi and rsi were arch_prctl's
      arguments and entry/arg live on the stack. }
    if TargetKernel = KERNEL_FREEBSD then
      EmitAsmX64([                      { FreeBSD stack_t: ss_sp, ss_size, ss_flags }
        'lea rsi, [rsp+%]', 16 + TlsBlockSize,
        'sub rsp, 32',
        'mov [rsp], rsi',               { ss_sp }
        'mov qword [rsp+8], %', SIG_ALTSTACK_SIZE,
        'mov qword [rsp+16], 0',        { ss_flags }
        'mov rdi, rsp',
        'xor esi, esi',
        'mov eax, 53',                  { sigaltstack }
        'syscall_raw',
        'add rsp, 32'])
    else
    EmitAsmX64([
      'lea rsi, [rsp+%]', 16 + TlsBlockSize,
      'sub rsp, 32',
      'mov [rsp], rsi',                 { ss_sp }
      'mov qword [rsp+8], 0',           { ss_flags }
      'mov qword [rsp+16], %', SIG_ALTSTACK_SIZE,
      'mov rdi, rsp',                   { new }
      'xor esi, esi',                   { old = nil }
      'mov eax, 131',                   { sigaltstack }
      ChildSys,
      'add rsp, 32']);
    { r10 = the hidden-destination scratch, BEFORE the two pops move rsp.
      An entry with no result ignores r10; one that returns a record/set/frozen
      string/Variant/promo-int copies its result there and the child discards
      it by exiting. rsp is still the stage area here, so the scratch is
      stage + 16 (past entry/arg) + the TLS block + the alt stack. }
    EmitAsmX64([
      'lea r10, [rsp+%]', 16 + TlsBlockSize + SIG_ALTSTACK_SIZE,
      'pop rax',                        { entry }
      'pop rdi',                        { arg -> first int arg }
      'call rax']);                     { entry(arg) }
    if TargetKernel = KERNEL_FREEBSD then
      { CLONE_CHILD_CLEARTID by hand: zero the tid word and wake its waiters
        (both umtx queues -- a joiner may wait shared or private), then
        thr_exit. ctidptr is in this thread's TLS slot 14 (put there by the
        thr_new entry). The word is cleared only once the PARENT has stored
        the tid (it does so after thr_new returns, and this child may get
        here first), or the store would resurrect a dead thread for its
        joiner. }
      EmitAsmX64([
        'mov rbx, gs:[%]', 8 * TLS_SLOT_FS_ENTRY,
        'test rbx, rbx',
        'jz fbnoclr',
      'fbspin:',
        'mov eax, [rbx]',
        'test eax, eax',
        'jnz fbclr',
        'mov eax, 331',                 { sched_yield }
        'syscall_raw',
        'jmp fbspin',
      'fbclr:',
        'xor eax, eax',
        'mov [rbx], eax',
        'mov rdi, rbx',
        'mov esi, 3',                   { UMTX_OP_WAKE }
        'mov edx, 0x7fffffff',
        'xor r10d, r10d',
        'xor r8d, r8d',
        'mov eax, 454',                 { _umtx_op }
        'syscall_raw',
        'mov rdi, rbx',
        'mov esi, 16',                  { UMTX_OP_WAKE_PRIVATE }
        'mov edx, 0x7fffffff',
        'xor r10d, r10d',
        'xor r8d, r8d',
        'mov eax, 454',
        'syscall_raw',
      'fbnoclr:',
        'xor edi, edi',
        'mov eax, 431',                 { thr_exit(NULL) }
        'syscall_raw'])
    else
      EmitAsmX64([
        'xor edi, edi',                 { exit code 0 }
        'mov eax, 60',                  { SYS_exit }
        ChildSys]);                     { the thread exits here }
    EmitAsmX64([
    'parent:',                          { rax already = child tid }
      'ret',
    'over:']);                          { the jump-over lands past the stub }
    AsmScopeEnd;
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
    EmitAsm386([
      'push ebx',
      'push esi',
      'push edi',
      'mov ebx, [esp+32]',               { flags }
      'mov ecx, [esp+28]'                { childStack }
    ]);
    { carve the hidden-destination scratch off the top first — see
      CLONE_RETBUF_SIZE. i386 carries that pointer in ecx. }
    EmitB($81); EmitB($E9); EmitI32(CLONE_RETBUF_SIZE); { sub ecx, CLONE_RETBUF_SIZE }
    { ---- carve the child's TLS block below the scratch, as the other legs
      do, zeroed for the same reasons (see the x86-64 leg). eax, edx and edi
      are free here: edx and edi are loaded below, edi was saved above. ---- }
    EmitB($81); EmitB($E9); EmitI32(TlsBlockSize);    { sub ecx, TlsBlockSize }
    EmitAsm386([
      'mov edi, ecx',
      'xor eax, eax',
      'mov edx, %', TlsBlockSize div 4,  { dword count }
      '.z:',
      'mov [edi], eax',
      'add edi, 4',
      'dec edx',
      'jnz short .z'
    ]);
    EmitAsm386([
      'mov [ecx], ecx',                  { slot 0 = self }
      'sub ecx, 8',                      { stage area }
      'mov eax, [esp+24]',               { entry }
      'mov [ecx], eax',
      'mov eax, [esp+20]',               { arg }
      'mov [ecx+4], eax',
      'mov edx, [esp+16]',               { parent_tid = ctidptr }
      'mov edi, [esp+16]',               { child_tid  = ctidptr }
      'xor esi, esi',                    { tls = NULL }
      'mov eax, 120',                    { SYS_clone }
      'int 128',
      'test eax, eax'
    ]);
    { jnz .parent -- COMPUTED, like the x86-64 leg above. The 12 was correct,
      but a hand-counted displacement here is the arm that stays wrong the day
      someone edits the child sequence and only looks at one leg. }
    { rel32, not rel8: the block install (2026-09-27) brought the child
      sequence near 127 bytes, the limit the x86-64 leg passed. }
    EmitB($0F); EmitB($85); pParent := CodeLen; EmitI32(0);   { jnz .parent }
    { ---- child: esp = the stage area, [esp]=entry [esp+4]=arg, block at esp+8 ---- }
    { Install the block, but ONLY if the parent was running on one. clone
      copies fs and the kernel copies the GDT TLS entries, so the child starts
      on the PARENT's block: the entry number is right, its base is not.
      set_thread_area on that same entry re-points it for this thread alone
      (the TLS entries are per task). fs = 0 means nothing installed a block
      (a --shared/--emit-obj host, which has no pxx entry point), and then
      nothing here may touch fs. }
    EmitAsm386([
      'mov eax, fs',
      'and eax, 0xffff'
    ]);
    EmitB($74); pNoInst := CodeLen; EmitB(0);         { jz .noinst }
    { esi = the PARENT's init-image pointer, read through fs BEFORE the
      install; see the x86-64 leg. }
    if TlsUserBytes > 0 then
    begin
      EmitB($64); EmitB($8B); EmitB($35); EmitI32(8 * TLS_SLOT_INIT_IMAGE);  { mov esi, fs:[8*slot] }
    end;
    EmitAsm386([
      'lea edx, [esp+8]',                { the block }
      'shr eax, 3'                       { entry number }
    ]);
    EmitB($89); EmitB($82); EmitI32(8 * TLS_SLOT_FS_ENTRY);  { mov [edx+8*slot], eax }
    EmitAsm386([
      'sub esp, 16',                     { user_desc }
      'mov [esp], eax',                  { entry_number }
      'mov [esp+4], edx'                 { base_addr }
    ]);
    EmitB($C7); EmitB($44); EmitB($24); EmitB($08); EmitI32($FFFFF);  { limit, in pages }
    EmitB($C7); EmitB($44); EmitB($24); EmitB($0C); EmitI32($51);     { flags; see EmitTlsMainInstall }
    EmitAsm386([
      'mov ebx, esp',
      'mov eax, 243',                    { set_thread_area }
      'int 128',
      'add esp, 16'
    ]);
    { Reload fs so its cached descriptor is the new base. Linux already does
      this for a selector that names the modified entry, but the reload is two
      instructions and makes that a fact of this stub. }
    EmitAsm386([
      'mov eax, fs',
      'mov fs, eax'
    ]);
    if TlsUserBytes > 0 then
    begin
      EmitAsm386('test esi, esi');
      EmitB($74); pCopy := CodeLen; EmitB(0);         { jz .nocopy }
      { the slot BEFORE the copy: rep movsb advances esi past the image }
      EmitB($89); EmitB($B2); EmitI32(8 * TLS_SLOT_INIT_IMAGE);  { mov [edx+8*slot], esi }
      EmitB($8D); EmitB($BA); EmitI32(TLS_USER_FIRST_OFF);  { lea edi, [edx+user] }
      EmitAsm386([
        'mov ecx, %', TlsUserBytes,        { mov ecx, TlsUserBytes }
        'cld'
      ]);
      EmitB($F3); EmitB($A4);                         { rep movsb }
      PatchRel8(pCopy);                               { .nocopy: }
    end;
    PatchRel8(pNoInst);                               { .noinst: }
    EmitAsm386('pop eax');  { entry; arg stays at [esp] }
    { ecx = the hidden-destination scratch. esp now points at arg; the TLS
      block sits between it and the scratch, so the scratch base is
      esp+4+TlsBlockSize. }
    EmitB($8D); EmitB($8C); EmitB($24); EmitI32(4 + TlsBlockSize);  { lea ecx, [esp+4+TlsBlockSize] }
    EmitB($FF); EmitB($D0);                           { call eax (entry(arg), caller-cleans convention) }
    EmitAsm386([
      'xor ebx, ebx',                    { exit code 0 }
      'mov eax, 1',                      { SYS_exit }
      'int 128'                          { thread exits here }
    ]);
    { ---- .parent: eax = child tid ---- }
    Patch32(pParent, CodeLen - (pParent + 4));
    EmitAsm386([
      'pop edi',
      'pop esi',
      'pop ebx',
      'ret'
    ]);
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
    { --os=freebsd: thr_new's entry, as on x86-64. The kernel starts the
      thread at a function with x0 = its arg (the stage area) and its own sp;
      this makes it the clone child: sp = the stage, ctidptr (parked at
      stage-8 by the parent) into the new block's slot 14 for the exit path,
      then the shared child code. thr_new copies the parent's tpidr_el0, so
      that code's "running on a pxx block" test reads the same as after
      clone. feature-port-freebsd-native }
    fbChild := 0; pFbB := 0;
    if TargetKernel = KERNEL_FREEBSD then
    begin
      fbChild := CodeLen;
      EmitI32($9100001F);               { mov  sp, x0 }
      EmitI32($F85F83E9);               { ldur x9, [sp, #-8]      (ctidptr) }
      EmitI32($F90003E9 or (((16 + 8 * TLS_SLOT_FS_ENTRY) div 8) shl 10));   { str x9, [sp, #16+8*slot] }
      pFbB := CodeLen; EmitI32($14000000);   { b .child (patched) }
    end;
    CloneStubAddr := CodeLen;
    EmitI32($D1040021);                 { sub  x1, x1, #256       (hidden-dest scratch) }
    { ---- carve the child's TLS block below the scratch ----
      The same block the x86-64 leg carves, zeroed for the same reasons (see
      there): every threadvar starts at 0, and a reused stack must not hand
      over the previous thread's slots. x9/x10 are caller-saved scratch.
      TlsBlockSize is a nonzero multiple of 16, so the loop terminates and sp
      stays 16-aligned. }
    EmitLoadImmA64(9, TlsBlockSize);    { x9 = TlsBlockSize }
    EmitI32($CB090021);                 { sub  x1, x1, x9 }
    EmitI32($AA0103EA);                 { mov  x10, x1 }
    EmitI32($F800855F);                 { .z: str xzr, [x10], #8 }
    EmitI32($F1002129);                 { subs x9, x9, #8 }
    EmitI32($54FFFFC1);                 { b.ne .z }
    EmitI32($F9000021);                 { str  x1, [x1]           (slot 0 = self) }
    EmitI32($D1004021);                 { sub  x1, x1, #16        (stage area) }
    EmitI32($F9000022);                 { str  x2, [x1]           (entry) }
    EmitI32($F9000423);                 { str  x3, [x1, #8]       (arg) }
    if TargetKernel = KERNEL_FREEBSD then
    begin
      { thr_new(&param, 104), the x86-64 leg's parameter block: the thread
        starts at fbChild with the stage area as its argument, on a 4 KiB
        stack ending 16 below the stage (the stage-8 word carries ctidptr).
        The tid lands in a scratch long and is stored to ctidptr as
        CLONE_PARENT_SETTID would. C set = error, x0 the positive errno.
        The `svc` is raw: this IS the kernel call, not a Linux one. }
      EmitI32($F81F8024);               { stur x4, [x1, #-8]      (ctidptr for the child) }
      EmitI32($D101C3FF);               { sub  sp, sp, #112 }
      imm := fbChild - CodeLen;
      EmitI32($10000000 or ((imm and 3) shl 29) or (((imm div 4) and $7FFFF) shl 5) or 9);  { adr x9, fbChild }
      EmitI32($F90003E9);               { str  x9, [sp]           (start_func) }
      EmitI32($F90007E1);               { str  x1, [sp, #8]       (arg = stage) }
      EmitI32($D1400429);               { sub  x9, x1, #1, lsl #12 }
      EmitI32($D1004129);               { sub  x9, x9, #16 }
      EmitI32($F9000BE9);               { str  x9, [sp, #16]      (stack_base) }
      EmitI32($D2820009);               { mov  x9, #4096 }
      EmitI32($F9000FE9);               { str  x9, [sp, #24]      (stack_size) }
      for imm := 5 to 13 do
        if (imm <> 6) and (imm <> 7) then
          EmitI32($F90003FF or (imm shl 10));   { str xzr, [sp, #8*imm] }
      { tls_base = the new block: thr_new does NOT hand the child the
        parent's tpidr_el0 (measured: it starts at 0), it sets the one given
        here. The block's init-image slot comes from the parent's block first,
        so the child code's threadvar copy finds it where clone leaves it. }
      EmitI32($D53BD04A);               { mrs  x10, tpidr_el0 }
      EmitI32($B400006A);               { cbz  x10, +3 }
      EmitI32($F940014A or (TLS_SLOT_INIT_IMAGE shl 10));          { ldr x10, [x10, #8*slot] }
      EmitI32($F900002A or ((2 + TLS_SLOT_INIT_IMAGE) shl 10));    { str x10, [x1, #16+8*slot] }
      EmitI32($91004029);               { add  x9, x1, #16        (the block) }
      EmitI32($F90013E9);               { str  x9, [sp, #32]      (tls_base) }
      EmitI32($9101A3E9);               { add  x9, sp, #104       (tid scratch) }
      EmitI32($F9001BE9);               { str  x9, [sp, #48]      (child_tid) }
      EmitI32($F9001FE9);               { str  x9, [sp, #56]      (parent_tid) }
      EmitI32($910003E0);               { mov  x0, sp }
      EmitI32($D2800D01);               { mov  x1, #104 }
      EmitI32($D28038E8);               { mov  x8, #455           (thr_new) }
      EmitI32($D4000001);               { svc  #0 }
      pFbFail := CodeLen; EmitI32($54000002);   { b.cs .fbfail (patched) }
      EmitI32($B9406BE0);               { ldr  w0, [sp, #104]     (the tid) }
      EmitI32($B4000044);               { cbz  x4, +2 }
      EmitI32($B9000080);               { str  w0, [x4] }
      EmitI32($9101C3FF);               { add  sp, sp, #112 }
      EmitI32($D65F03C0);               { ret }
      Patch32(pFbFail, $54000002 or ((((CodeLen - pFbFail) div 4) and $7FFFF) shl 5));
      EmitI32($CB0003E0);               { neg  x0, x0 }
      EmitI32($9101C3FF);               { add  sp, sp, #112 }
      EmitI32($D65F03C0);               { ret }
      Patch32(pFbB, $14000000 or (((CodeLen - pFbB) div 4) and $03FFFFFF));
      pParent := -1;
    end
    else if (TargetKernel = KERNEL_NETBSD) or (TargetKernel = KERNEL_OPENBSD) then
    begin
      { --os=netbsd: Linux clone through the translator, which starts an LWP
        from a ucontext (nbsdabi's NbClone) with pc = x5, the child entry
        below, sp = the stage area and the thread pointer = the new block.
        --os=openbsd takes the same leg: obsdabi's ObClone runs __tfork with
        tf_tcb = the new block, and ObTforkA sends the child to x5.
        As with thr_new the child does not inherit the parent's thread
        pointer, so the init-image slot is copied into the new block first.
        The kernel call is a `bl` into the shared thunk and this stub `ret`s
        through x30, hence the Leaf form. }
      EmitI32($D53BD04A);               { mrs  x10, tpidr_el0 }
      EmitI32($B400006A);               { cbz  x10, +3 }
      EmitI32($F940014A or (TLS_SLOT_INIT_IMAGE shl 10));          { ldr x10, [x10, #8*slot] }
      EmitI32($F900002A or ((2 + TLS_SLOT_INIT_IMAGE) shl 10));    { str x10, [x1, #16+8*slot] }
      EmitI32($AA0403E2);               { mov  x2, x4             (parent_tid = ctidptr) }
      EmitI32($D2800003);               { mov  x3, #0             (tls) }
      pFbB := CodeLen; EmitI32($10000005);   { adr  x5, .child (patched) }
      EmitI32($D2801B88);               { mov  x8, #220           (SYS_clone) }
      EmitSvcA64Leaf;
      pParent := CodeLen; EmitI32($B5000000);   { cbnz x0, .parent (patched) }
      imm := CodeLen - pFbB;
      Patch32(pFbB, $10000000 or ((imm and 3) shl 29) or (((imm div 4) and $7FFFF) shl 5) or 5);
    end
    else
    begin
    EmitI32($AA0403E2);                 { mov  x2, x4             (parent_tid = ctidptr) }
    EmitI32($D2800003);                 { mov  x3, #0             (tls = NULL) }
    EmitI32($D2801B88);                 { mov  x8, #220           (SYS_clone) }
    EmitI32($D4000001);                 { svc  #0 }
    { cbnz x0, .parent -- COMPUTED, like the x86-64 and i386 legs. It was a
      hand-counted +7 words over the child sequence below, and the very next
      line added to that sequence (the x8 scratch) made it land one instruction
      short -- inside the child path, in the PARENT. Three legs had already
      been converted for exactly this reason and this one had not. }
    pParent := CodeLen; EmitI32($B5000000);   { cbnz x0, .parent (patched) }
    end;
    { ---- child: sp = the stage area, [sp]=entry [sp+8]=arg, block at sp+16 ---- }
    { Install the block, but ONLY if the parent was running on a pxx block.
      clone inherits tpidr_el0, so the register holds either the parent's pxx
      block, whose slot 0 is its own address, or glibc's TCB in a dynamic
      binary, whose first word is the dtv pointer. Taking the register in the
      second case would break glibc on this thread, and TargetHasTlsBlock says
      why that binary never reads the block anyway. }
    EmitI32($D53BD049);                 { mrs  x9, tpidr_el0 }
    pNoInst := CodeLen; EmitI32($B4000009);   { cbz  x9, .noinst (patched) }
    EmitI32($F940012A);                 { ldr  x10, [x9] }
    EmitI32($EB0A013F);                 { cmp  x9, x10 }
    pNoInst2 := CodeLen; EmitI32($54000001);  { b.ne .noinst (patched) }
    { x11 = the parent's init-image pointer; see the x86-64 leg. }
    EmitI32($F9400000 or (TLS_SLOT_INIT_IMAGE shl 10) or (9 shl 5) or 11);  { ldr x11, [x9, #8*slot] }
    EmitI32($910043E9);                 { add  x9, sp, #16        (the block) }
    EmitI32($D51BD049);                 { msr  tpidr_el0, x9 }
    if TlsUserBytes > 0 then
    begin
      if (TLS_USER_FIRST_OFF > 4095) or (TlsUserBytes mod 8 <> 0) then
        Error('compiler error: the aarch64 clone leg copies the init image with a 12-bit offset and 8-byte steps');
      pCopy := CodeLen; EmitI32($B400000B);   { cbz  x11, .nocopy (patched) }
      EmitI32($91000000 or (TLS_USER_FIRST_OFF shl 10) or (9 shl 5) or 12);  { add x12, x9, #user }
      EmitLoadImmA64(13, TlsUserBytes);       { x13 = count }
      EmitI32($AA0B03EE);                 { mov  x14, x11 }
      EmitI32($F84085CF);                 { .c: ldr x15, [x14], #8 }
      EmitI32($F800858F);                 { str  x15, [x12], #8 }
      EmitI32($F10021AD);                 { subs x13, x13, #8 }
      EmitI32($54FFFFA1);                 { b.ne .c }
      EmitI32($F9000000 or (TLS_SLOT_INIT_IMAGE shl 10) or (9 shl 5) or 11);  { str x11, [x9, #8*slot] }
      Patch32(pCopy, $B400000B or ((((CodeLen - pCopy) div 4) and $7FFFF) shl 5));
    end;
    Patch32(pNoInst, $B4000009 or ((((CodeLen - pNoInst) div 4) and $7FFFF) shl 5));
    Patch32(pNoInst2, $54000001 or ((((CodeLen - pNoInst2) div 4) and $7FFFF) shl 5));
    EmitI32($F94003E1);                 { ldr  x1, [sp]           (entry) }
    EmitI32($F94007E0);                 { ldr  x0, [sp, #8]       (arg -> x0) }
    { x8 = the hidden-destination scratch (AAPCS XR, which is also what this
      compiler's own aggregate-return convention uses) — see CLONE_RETBUF_SIZE.
      It sits above the stage area and the TLS block. }
    EmitI32($910043E8);                 { add  x8, sp, #16 }
    EmitLoadImmA64(9, TlsBlockSize);
    EmitI32($8B090108);                 { add  x8, x8, x9         (scratch) }
    EmitI32($D63F0020);                 { blr  x1                 (entry(arg)) }
    EmitI32($D2800000);                 { mov  x0, #0             (exit code 0) }
    EmitI32($D2800BA8);                 { mov  x8, #93            (SYS_exit) }
    { thread exits here; under --os=freebsd through the translator, whose exit
      clears and wakes the tid word from slot 14 }
    EmitSvcA64;
    { ---- .parent: x0 = child tid ---- }
    if pParent >= 0 then
      Patch32(pParent, $B5000000 or ((((CodeLen - pParent) div 4) and $7FFFF) shl 5));
    EmitI32($D65F03C0);                 { ret }
    { patch the leading branch to land here (past the stub). B imm26 in words. }
    Patch32(jmpOver, $14000000 or (((CodeLen - jmpOver) div 4) and $03FFFFFF));
  end;
  if TargetArch = TARGET_ARM32 then
  begin
    { arm32 EABI leg. Stub input contract (set by IR_CLONE): r0=flags
      r1=childStack r2=entry r3=arg r4=ctidptr. EABI clone(2) arg order is
      r0=flags, r1=stack, r2=parent_tid, r3=tls, r4=child_tid; r7=SYS_clone(120);
      svc 0. Child resumes with sp = the stack arg; the stub stages [entry][arg]
      at the top so the child pops them. SYS_exit=1. Hex verified against clang
      -march=armv7-a. }
    EmitI32($EA000000); jmpOver := CodeLen - 4;   { b .end (patched below) }
    CloneStubAddr := CodeLen;
    { r9/r10 are callee-saved under AAPCS and the block carve needs them. Only
      the PARENT restores them; the child runs on a fresh stack. }
    EmitI32($E92D0600);                 { push {r9, r10} }
    EmitI32($E2411C01);                 { sub r1, r1, #256      (hidden-dest scratch) }
    { ---- carve the child's TLS block, as the aarch64 leg does ---- }
    EmitLoadImmArm32(9, TlsBlockSize);  { r9 = TlsBlockSize }
    EmitI32($E0411009);                 { sub r1, r1, r9 }
    EmitI32($E1A0A001);                 { mov r10, r1 }
    EmitI32($E3A0C000);                 { mov r12, #0 }
    EmitI32($E48AC004);                 { .z: str r12, [r10], #4 }
    EmitI32($E2599004);                 { subs r9, r9, #4 }
    EmitI32($1AFFFFFC);                 { bne .z }
    EmitI32($E5811000);                 { str r1, [r1]          (slot 0 = self) }
    EmitI32($E2411010);                 { sub r1, r1, #16       (stage area) }
    EmitI32($E5812000);                 { str r2, [r1]          (entry) }
    EmitI32($E5813004);                 { str r3, [r1, #4]      (arg) }
    EmitI32($E1A02004);                 { mov r2, r4            (parent_tid = ctidptr) }
    EmitI32($E3A03000);                 { mov r3, #0            (tls = NULL) }
    EmitI32($E3A07078);                 { mov r7, #120          (SYS_clone) }
    EmitI32($EF000000);                 { svc 0 }
    EmitI32($E3500000);                 { cmp r0, #0 }
    { bne .parent -- COMPUTED, same story as the aarch64 leg above: the +7 was
      correct until the child sequence grew by one instruction. }
    pParent := CodeLen; EmitI32($1A000000);   { bne .parent (patched) }
    { ---- child: sp = the stage area, [sp]=entry [sp+4]=arg, block at sp+16 ---- }
    { Install only over a pxx block; see the aarch64 leg. }
    EmitI32($EE1D9F70);                 { mrc p15, 0, r9, c13, c0, 3  (TPIDRURO) }
    EmitI32($E3590000);                 { cmp r9, #0 }
    pNoInst := CodeLen; EmitI32($0A000000);   { beq .noinst (patched) }
    EmitI32($E599A000);                 { ldr r10, [r9] }
    EmitI32($E159000A);                 { cmp r9, r10 }
    pNoInst2 := CodeLen; EmitI32($1A000000);  { bne .noinst (patched) }
    { r8 = the parent's init-image pointer; see the x86-64 leg. }
    EmitI32($E5998000 or (8 * TLS_SLOT_INIT_IMAGE));   { ldr r8, [r9, #8*slot] }
    EmitI32($E28D0010);                 { add r0, sp, #16       (the block) }
    EmitLoadImmArm32(7, $F0005);        { r7 = __ARM_NR_set_tls }
    EmitI32($EF000000);                 { svc 0 }
    if TlsUserBytes > 0 then
    begin
      if TlsUserBytes mod 4 <> 0 then
        Error('compiler error: the arm32 clone leg copies the init image in 4-byte steps');
      EmitI32($E3580000);                 { cmp r8, #0 }
      pCopy := CodeLen; EmitI32($0A000000);   { beq .nocopy (patched) }
      EmitI32($E28DA010);                 { add r10, sp, #16      (the block) }
      EmitLoadImmArm32(12, TLS_USER_FIRST_OFF);
      EmitI32($E08AA00C);                 { add r10, r10, r12     (its user area) }
      EmitLoadImmArm32(9, TlsUserBytes);  { r9 = count }
      EmitI32($E1A03008);                 { mov r3, r8 }
      EmitI32($E4932004);                 { .c: ldr r2, [r3], #4 }
      EmitI32($E48A2004);                 { str r2, [r10], #4 }
      EmitI32($E2599004);                 { subs r9, r9, #4 }
      EmitI32($1AFFFFFB);                 { bne .c }
      EmitI32($E28DA010);                 { add r10, sp, #16 }
      EmitI32($E58A8000 or (8 * TLS_SLOT_INIT_IMAGE));   { str r8, [r10, #8*slot] }
      Patch32(pCopy, $0A000000 or ((((CodeLen - pCopy) div 4) - 2) and $00FFFFFF));
    end;
    Patch32(pNoInst, $0A000000 or ((((CodeLen - pNoInst) div 4) - 2) and $00FFFFFF));
    Patch32(pNoInst2, $1A000000 or ((((CodeLen - pNoInst2) div 4) - 2) and $00FFFFFF));
    EmitI32($E59D1000);                 { ldr r1, [sp]          (entry) }
    EmitI32($E59D0004);                 { ldr r0, [sp, #4]      (arg -> r0) }
    { r12 (ip) = the hidden-destination scratch — see CLONE_RETBUF_SIZE. It
      sits above the stage area and the TLS block. }
    EmitI32($E28DC010);                 { add r12, sp, #16 }
    EmitLoadImmArm32(9, TlsBlockSize);
    EmitI32($E08CC009);                 { add r12, r12, r9      (scratch) }
    EmitI32($E12FFF31);                 { blx r1                (entry(arg)) }
    EmitI32($E3A00000);                 { mov r0, #0            (exit code 0) }
    EmitI32($E3A07001);                 { mov r7, #1            (SYS_exit) }
    EmitI32($EF000000);                 { svc 0                 (thread exits here) }
    { ---- .parent: r0 = child tid ---- }
    Patch32(pParent, $1A000000 or (((((CodeLen - pParent) div 4) - 2)) and $00FFFFFF));
    EmitI32($E8BD0600);                 { pop {r9, r10} }
    EmitI32($E1A01FC0);                 { mov r1, r0, asr #31   sign-extend tid into Int64 hi word }
    EmitI32($E12FFF1E);                 { bx lr }
    { patch the leading branch to land here (ARM pc is 2 instr ahead). }
    Patch32(jmpOver, $EA000000 or (((((CodeLen - jmpOver) div 4) - 2)) and $00FFFFFF));
  end;
  { esp/riscv32 stay out of scope for threading; IR_CLONE guards them with a
    clean compile-error, so EnsureCloneStub is never reached there. }
end;
