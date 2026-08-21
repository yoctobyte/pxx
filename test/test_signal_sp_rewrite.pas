program test_signal_sp_rewrite;
{ __pxxSigSPPtr — the address of the saved STACK POINTER inside the ucontext,
  the sibling of __pxxSigPCPtr
  (bug-a-stack-overflow-fault-to-raise-loops-forever-without-an-sp-reset).

  Rewriting the PC alone points the resumed code somewhere new but leaves it on
  the FAULTING frame's stack, which for a stack-overflow SIGSEGV is a stack with
  nothing left: the raise stub re-faults on its own prologue and the process
  spins on the guard page forever. Writing the SP too moves the resumed code
  onto ground that has room.

  The fault here is a plain nil write, NOT an overflow, on purpose. An overflow
  needs the handler itself to run off a sigaltstack, which only x86-64 installs
  so far, and this test has to hold on all five hosted targets — the per-arch SP
  offset is exactly the kind of table where one wrong entry is a silent wrong
  answer. test_stack_overflow_raise covers the overflow case where it works.

  `raiser-ran-on-the-spare-stack` is the assertion that matters. Surviving only
  shows the PC rewrite worked, which it already did before; it does not show the
  SP moved. So Raiser reports where its OWN frame lives: inside `spare`, a BSS
  array, it can only be there because the kernel resumed it on the SP we wrote.
  Rewriting the wrong ucontext word would land on the old stack (or crash),
  never inside the array.

  Oracle: the equivalent C — sigaction(SA_SIGINFO), then writing both
  uc_mcontext's PC and SP slots — behaves the same under gcc. }

type
  PPtrUInt = ^PtrUInt;

const
  SPARE = 65536;

var
  spare: array[0..SPARE - 1] of Byte;
  hits: Integer;
  onSpare: Boolean;
  p: ^Integer;

procedure Raiser;
var
  frame: Integer;
begin
  frame := 1;
  onSpare := (PtrUInt(@frame) >= PtrUInt(@spare[0])) and
             (PtrUInt(@frame) <= PtrUInt(@spare[SPARE - 1]));
  if frame = 1 then
    raise 99;
end;

procedure OnSegv;
begin
  Inc(hits);
  if hits > 3 then
    Halt(3);   { the loop this ticket is about — bail rather than hang the suite }
  { 256 bytes of headroom under the top: the resumed proc's prologue writes
    BELOW the SP the kernel restores. Aligned to 16 for every hosted ABI. }
  PPtrUInt(__pxxSigSPPtr)^ :=
    (PtrUInt(@spare[SPARE - 1]) - 256) and not PtrUInt(15);
  PPtrUInt(__pxxSigPCPtr)^ := PtrUInt(@Raiser);
end;

begin
  hits := 0;
  onSpare := False;
  SetSignalHandler(11, @OnSegv);
  try
    p := nil;
    p^ := 1;
    WriteLn('unreachable');
  except
    WriteLn('caught, hits=', hits);
  end;
  WriteLn('raiser-ran-on-the-spare-stack=', onSpare);
  WriteLn('and execution continued');
end.
