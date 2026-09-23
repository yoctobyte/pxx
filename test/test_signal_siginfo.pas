program test_signal_siginfo;
{ SA_SIGINFO (feature-signal-siginfo-ucontext). The dispatch
  stub parks siginfo_t.si_code, siginfo_t.si_addr and the ucontext_t* before
  calling the hook; __pxxSigCode / __pxxSigAddr / __pxxSigContext read them.

  si_code is the load-bearing one: it is the ONLY carrier of WHICH fault
  occurred. The MXCSR status flags are 0x00 inside a handler because Linux
  hands it a clean FP state (measured), so the float-exception-mask work
  cannot distinguish div-zero from overflow without this.

  Both values are checked against the kernel's documented constants, and the
  fault address against the address this program deliberately wrote to.

  Arch-independent by design — it is the canary for BOTH failure modes on every
  target: the si_addr assert catches a wrong union offset (16 on the 64-bit
  targets, 12 on ILP32, where the preamble is not padded), and the negative
  SI_TKILL catches a lost sign. Only the two raw syscall numbers differ. }

const
{$ifdef CPUX86_64}
  SYS_gettid = 186; SYS_tkill = 200;
{$endif}
{$ifdef CPUAARCH64}
  SYS_gettid = 178; SYS_tkill = 130;   { asm-generic unistd }
{$endif}
{$ifdef CPURISCV32}
  SYS_gettid = 178; SYS_tkill = 130;   { asm-generic unistd }
{$endif}
{$ifdef CPUARM}
  SYS_gettid = 224; SYS_tkill = 238;   { ARM EABI }
{$endif}
{$ifdef CPUI386}
  SYS_gettid = 224; SYS_tkill = 238;
{$endif}
{$ifdef CPUXTENSA}
  { xtensa has its OWN numbering and is not asm-generic: gettid 127, tkill 124.
    NOT copyable from any arm above -- 224 is `sigaltstack` here, where it is
    gettid on ARM and i386, and 130 is `prctl`, where it is tkill under
    asm-generic. Copying either arm would call a real but wrong syscall and get
    a plausible return.
    MEASURED 2026-09-23 by two instruments that fail differently: qemu-xtensa
    -strace names 124 `tkill` and 127 `gettid` (one syscall per PROCESS, so a
    number that terminates the probe costs only its own row); and functionally,
    tkill(gettid(), 0) = 0 while tkill(999999, 0) = -1 errno=3 ESRCH. Controls:
    120 getpid, 126 set_tid_address, 150 getppid, 224 sigaltstack all reproduce
    the numbers already settled in the tree.
    bug-a-xtensa-tkill-syscall-number-is-unlocated }
  SYS_gettid = 127; SYS_tkill = 124;
{$endif}

var
  p: ^Integer;
  tid: Int64;
  stage: Integer;

procedure OnSegv;
begin
  { SEGV_MAPERR = 1, and si_addr is the address that faulted — $DEAD0000, so a
    wrong union offset cannot pass by accident. }
  WriteLn('segv code=', __pxxSigCode);
  WriteLn('segv addr=', PtrUInt(__pxxSigAddr));
  WriteLn('ctx set=', __pxxSigContext <> nil);
  stage := 2;
  { Fall through to the SIGUSR1 half; returning from a SIGSEGV handler would
    re-execute the faulting store forever, so this half never returns. }
  tid := __pxxrawsyscall(SYS_gettid);
  tid := __pxxrawsyscall(SYS_tkill, tid, 10);   { tkill(tid, SIGUSR1) }
  WriteLn('unreachable-a');
  Halt(1);
end;

procedure OnUsr1;
begin
  { SI_TKILL = -6. NEGATIVE on purpose: si_code is a signed 32-bit field, and a
    zero-extended load answers 4294967290 here — which is exactly what the
    stub's shl/sar pair prevents (the mini-assembler has no movsxd). }
  WriteLn('usr1 code=', __pxxSigCode);
  WriteLn('stage=', stage);
  Halt(0);
end;

begin
  stage := 1;
  SetSignalHandler(11, @OnSegv);
  SetSignalHandler(10, @OnUsr1);
  p := Pointer(PtrUInt($DEAD0000));
  p^ := 1;                                { -> SIGSEGV }
  WriteLn('unreachable-b');
  Halt(1);
end.
