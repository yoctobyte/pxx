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

  Four of the five hosted targets: x86-64, i386, arm32, aarch64. All four now
  install with sigaltstack + SA_ONSTACK
  (bug-a-four-hosted-targets-install-signal-handlers-without-an-altstack).

  riscv32 is excluded and it is NOT the SP rewrite that fails there — its
  registration is correct and verified (the sigaltstack syscall succeeds, and
  the flags word assembles to $18000004 in the emitted binary), but the handler
  still runs on the FAULTING stack under qemu-riscv32, so for a stack overflow
  it never runs at all. The identical construction works under qemu-i386,
  qemu-arm and qemu-aarch64 of the same build, which points at qemu-user's
  riscv signal frame rather than at us; unverifiable without hardware. Filed as
  bug-a-riscv32-sa-onstack-has-no-effect-under-qemu.

  The per-arch SP offset itself is covered on all five by test_signal_sp_rewrite,
  which faults in a way that leaves the handler a stack.

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
