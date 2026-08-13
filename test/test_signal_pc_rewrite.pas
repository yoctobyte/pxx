program test_signal_pc_rewrite;
{ Rewriting the saved PC in the signal ucontext (feature-signal-siginfo-ucontext,
  the rest of item 1). __pxxSigPCPtr hands back the ADDRESS of the interrupted
  program counter inside the ucontext the kernel passed the handler, so pointing
  it somewhere else makes the kernel resume THERE instead of re-running the
  faulting instruction. That is what turns a hardware fault into a catchable
  Pascal exception, and this test does exactly that end to end.

  Two asserts, and the first is what makes the second trustworthy:

  1. The program faults by CALLING $DEAD0000, so the saved PC must BE $DEAD0000.
     That is an exact check of the per-arch offset — on a jump fault no other
     ucontext word equals it except a fault-address field, and rewriting the
     wrong word would corrupt an unrelated register instead.
  2. The handler points the PC at Raiser, returns, and the `raise` that runs
     there is caught by the try/except the faulting code was already inside.

  Why (2) works at all: the exception runtime unwinds through its OWN shadow
  stack (BSS_EXC_TOP, a chain of setjmp buffers), not through the hardware call
  stack, so a raise is legal from a context the kernel resumed at an arbitrary
  PC with the faulting frame's SP. The redirect target must never RETURN,
  though — it is entered with a link register full of pre-fault garbage.

  WHICH exception a fault should raise stays a library question this test does
  not answer (see decide-int-div-zero-behavior-unification): it raises a bare
  ordinal, which needs no exception class and no sysutils. }

type
  TProc0 = procedure;
  PPtrUInt = ^PtrUInt;

var
  q: TProc0;
  hits: Integer;

procedure Raiser;
begin
  raise 42;
end;

procedure OnSegv;
begin
  Inc(hits);
  WriteLn('pc-is-the-fault=', PPtrUInt(__pxxSigPCPtr)^ = PtrUInt($DEAD0000));
  WriteLn('code=', __pxxSigCode, ' addr=', PtrUInt(__pxxSigAddr));
  PPtrUInt(__pxxSigPCPtr)^ := PtrUInt(@Raiser);
  { Returning now resumes in Raiser instead of re-executing the faulting call. }
end;

begin
  hits := 0;
  SetSignalHandler(11, @OnSegv);
  try
    q := TProc0(Pointer(PtrUInt($DEAD0000)));
    q();
    WriteLn('unreachable: the handler did not redirect');
  except
    WriteLn('caught a fault as an exception, hits=', hits);
  end;
  WriteLn('and execution continued');
end.
