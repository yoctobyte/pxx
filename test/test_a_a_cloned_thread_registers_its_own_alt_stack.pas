program test_a_a_cloned_thread_registers_its_own_alt_stack;
{ EVERY clone leg gives the child its own signal alt stack.

  sigaltstack(2) is per-thread and is not inherited across clone(2), so the
  clone stub carves one off the top of the child's stack and registers it
  before the entry runs. That was the x86-64 leg only. On i386, aarch64 and
  arm32 a worker reported sp=0 flags=SS_DISABLE size=0, so a stack overflow
  on it could not be handled.

  The assertion is the REGISTRATION, read back from inside each worker with
  sigaltstack(NULL, &old). It is not the delivery: SA_ONSTACK delivery is
  known not to take effect under qemu-user
  (bug-a-riscv32-sa-onstack-has-no-effect-under-qemu), and qemu is how these
  targets run here. A row asserting delivery could not tell "the stub is
  wrong" from "qemu ignores the flag". The read-back has to be emulated
  correctly for the program to see anything at all.

  Per worker: the size is the compiler's SIG_ALTSTACK_SIZE (32768), flags is
  0 (not SS_DISABLE = 2), the alt stack lies above the worker's own frame
  within its 1 MB stack mapping (the carve is at the TOP of that mapping), and
  the two workers' alt stacks are distinct, which a shared buffer would not be.

  Measured before the fix, on aarch64, arm32 and i386 under qemu-user:
  `registered=0/2 size-ok=0/2 above-own-frame=0/2 distinct=FALSE`.
  bug-a-the-clone-stub-registers-a-signal-alt-stack-on-x86-64-only }

uses palthread;

const
{$ifdef CPUAARCH64}
  SYS_SIGALTSTACK = 132;
{$else}
{$ifdef CPUARM}
  SYS_SIGALTSTACK = 186;
{$else}
{$ifdef CPUI386}
  SYS_SIGALTSTACK = 186;
{$else}
  SYS_SIGALTSTACK = 131;
{$endif}
{$endif}
{$endif}
  NT = 2;
  ALT_SIZE = 32768;
  STACK_SPAN = 1024 * 1024;

var
  AltSp, AltFlags, AltSize, OwnFrame: array[0..NT-1] of PtrUInt;
  Handles: array[0..NT-1] of TThreadHandle;
  { Both workers stay alive until both have read their registration.
    PalThreadCreate reaps a dead thread's stack, so a worker that had already
    exited could hand its mapping to the next one, and `distinct` would then
    compare one address with itself (seen once on aarch64 before this
    barrier). }
  Done: array[0..NT-1] of Integer;

procedure Body(arg: Pointer);
var
  idx: Integer;
  ss: array[0..2] of PtrUInt;   { ss_sp, ss_flags (int, padded on 64-bit), ss_size }
  ignore: Int64;
  here: Integer;
begin
  idx := Integer(PtrUInt(arg));
  ss[0] := 0; ss[1] := 0; ss[2] := 0;
  ignore := __pxxrawsyscall(SYS_SIGALTSTACK, 0, Int64(PtrUInt(@ss[0])), 0, 0, 0, 0);
  here := idx;
  AltSp[idx] := ss[0];
  AltFlags[idx] := ss[1] and $FFFFFFFF;
  AltSize[idx] := ss[2];
  OwnFrame[idx] := PtrUInt(@here);
  Done[idx] := 1;
  while (Done[0] = 0) or (Done[1] = 0) do ;
end;

var
  i, reg, sizeOk, above: Integer;
begin
  for i := 0 to NT-1 do Done[i] := 0;
  for i := 0 to NT-1 do
    if PalThreadCreate(Handles[i], @Body, Pointer(PtrUInt(i)), 0) <> 0 then
    begin
      WriteLn('create FAIL');
      Halt(1);
    end;
  for i := 0 to NT-1 do PalThreadJoin(Handles[i]);
  reg := 0; sizeOk := 0; above := 0;
  for i := 0 to NT-1 do
  begin
    if (AltSp[i] <> 0) and (AltFlags[i] = 0) then Inc(reg);
    if AltSize[i] = ALT_SIZE then Inc(sizeOk);
    if (AltSp[i] > OwnFrame[i]) and (AltSp[i] - OwnFrame[i] < STACK_SPAN) then Inc(above);
  end;
  WriteLn('registered=', reg, '/', NT, ' size-ok=', sizeOk, '/', NT,
          ' above-own-frame=', above, '/', NT,
          ' distinct=', AltSp[0] <> AltSp[1]);
end.
