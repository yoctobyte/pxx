program test_stack_overflow_raise;
{ A stack overflow, caught by an ordinary try/except and survived
  (bug-a-stack-overflow-fault-to-raise-loops-forever-without-an-sp-reset).

  This is the fault that needs BOTH ucontext rewrites, and it is why
  __pxxSigSPPtr exists:

    * sigaltstack + SA_ONSTACK (test_signal_altstack) gets the HANDLER running.
      Without it the kernel cannot even push a signal frame and just kills the
      process — but the handler was never the hard part.
    * __pxxSigPCPtr points the resumed code at a raise stub. On its own this
      LOOPS: the kernel resumes that stub on the FAULTING frame's stack pointer,
      which after an overflow is a stack with nothing left, so the stub faults
      on its own prologue, is redirected again, and the process spins on the
      guard page until something kills it. Measured before the fix: the same
      PC and the same fault address on every hit after the first.
    * __pxxSigSPPtr is the missing half — it moves the resumed stub onto a
      spare stack that has room.

  `hits=1` is the assertion that matters: it is the difference between a
  redirect that took and the fault loop. Recursion depth is deliberately not
  printed — it depends on RLIMIT_STACK and on frame layout, exactly the kind of
  environment-dependent number that makes a test flap.

  x86-64 only, because only x86-64 installs its handlers with SA_ONSTACK so far;
  on the other four hosted targets the handler cannot run for THIS fault at all
  (bug-a-four-hosted-targets-install-signal-handlers-without-an-altstack). The
  per-arch SP offset is covered on all five by test_signal_sp_rewrite, which
  faults in a way that leaves the handler a stack.

  Once the exception is caught, the unwind restores SP from the setjmp buffer of
  the frame owning the `except` — a frame on the ORIGINAL stack — so the
  borrowed one is simply abandoned and the program keeps running normally. }

type
  PPtrUInt = ^PtrUInt;

const
  SPARE = 65536;

var
  spare: array[0..SPARE - 1] of Byte;
  hits: Integer;
  depth: Integer;
  after: Integer;

procedure Raiser;
begin
  raise 99;
end;

procedure OnSegv;
begin
  Inc(hits);
  if hits > 3 then
    Halt(3);   { the fault loop this ticket is about — bail, do not hang }
  PPtrUInt(__pxxSigSPPtr)^ :=
    (PtrUInt(@spare[SPARE - 1]) - 256) and not PtrUInt(15);
  PPtrUInt(__pxxSigPCPtr)^ := PtrUInt(@Raiser);
end;

procedure Recurse;
var
  pad: array[0..255] of Int64;
begin
  Inc(depth);
  pad[0] := depth;
  pad[255] := depth;
  Recurse;
  if pad[0] <> pad[255] then
    WriteLn('impossible');
end;

begin
  hits := 0;
  depth := 0;
  SetSignalHandler(11, @OnSegv);
  WriteLn('recursing');
  try
    Recurse;
    WriteLn('unreachable');
  except
    WriteLn('caught a stack overflow, hits=', hits);
  end;
  { Ordinary work after the recovery: the original stack is intact. }
  after := 0;
  while after < 1000 do
    Inc(after);
  WriteLn('and execution continued, after=', after);
end.
