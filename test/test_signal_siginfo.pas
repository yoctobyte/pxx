program test_signal_siginfo;
{ SA_SIGINFO, x86-64 (feature-signal-siginfo-ucontext, slice 1). The dispatch
  stub parks siginfo_t.si_code, siginfo_t.si_addr and the ucontext_t* before
  calling the hook; __pxxSigCode / __pxxSigAddr / __pxxSigContext read them.

  si_code is the load-bearing one: it is the ONLY carrier of WHICH fault
  occurred. The MXCSR status flags are 0x00 inside a handler because Linux
  hands it a clean FP state (measured), so the float-exception-mask work
  cannot distinguish div-zero from overflow without this.

  Both values are checked against the kernel's documented constants, and the
  fault address against the address this program deliberately wrote to. }

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
  tid := __pxxrawsyscall(186);            { gettid }
  tid := __pxxrawsyscall(200, tid, 10);   { tkill(tid, SIGUSR1) }
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
