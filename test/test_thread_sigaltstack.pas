program test_thread_sigaltstack;
{ A CLONED THREAD NEEDS ITS OWN SIGNAL ALT STACK.

  sigaltstack(2) is PER-THREAD and is not inherited across clone(2). The only
  registration used to be the one in SigInstallAddr, reached from
  SetSignalHandler -- so whichever thread installed the handler was the only
  thread with an alt stack, and a cloned worker reported
  sp=0 flags=SS_DISABLE size=0.

  That matters for exactly one fault and it is the one with no second chance.
  An ordinary fault on a worker is FINE: a nil deref still has a usable stack,
  so the kernel pushes the signal frame onto it and the handler runs. A STACK
  OVERFLOW has no stack left by definition, so without an alt stack the kernel
  has nowhere to put the frame and kills the process outright.

  MEASURED BEFORE THE FIX, this program, one argument apart:

    main:    handled code=1 handler-in-bss=TRUE   rc=7
    worker:  no output at all                     rc=139

  THE SECOND ROW IS THE DISCRIMINATOR AND IT IS NOT "did we survive".
  Surviving only shows a handler ran, not WHERE. `handler-in-bss' compares the
  handler's own frame against the boundary between the image's BSS (low, a few
  megabytes) and mmap space (high). It must answer differently on the two
  threads, and that difference is the whole assertion:

    - MAIN's alt stack is the process-wide BSS buffer SetSignalHandler
      registers, so its handler frame is in BSS: TRUE.
    - The WORKER's is carved off the top of its own mmap'd stack by the clone
      stub, so its handler frame is in mmap space: FALSE.

  A fix that gave every thread the BSS buffer would pass "handled" on both rows
  and print TRUE twice -- and it would be wrong, because two threads faulting at
  once would push signal frames onto one region. }

const
  PXX_CLONE_THREAD = $350F00;
  SYS_mmap  = 9;
  SYS_futex = 202;
  FUTEX_WAIT = 0;
  PROT_RW   = 3;
  MAP_ANON_PRIV = $22;
  STK = 1024 * 1024;
  { Any pxx image's BSS sits within the first few MB of the load address; an
    mmap'd thread stack is far above it. Compared against a boundary rather
    than against either bound, so the row cannot pass by both sides drifting. }
  BSS_CEILING = $10000000;

var
  depth: Integer;
  tidword: Integer;

procedure OnSegv;
var
  hLocal: Integer;
  gap: PtrUInt;
begin
  hLocal := 1;
  if PtrUInt(@hLocal) > PtrUInt(__pxxSigAddr) then
    gap := PtrUInt(@hLocal) - PtrUInt(__pxxSigAddr)
  else
    gap := PtrUInt(__pxxSigAddr) - PtrUInt(@hLocal);
  WriteLn('handled code=', __pxxSigCode,
          ' off-faulting-stack=', gap > $10000,
          ' handler-in-bss=', PtrUInt(@hLocal) < BSS_CEILING);
  Halt(7);
end;

procedure Recurse;
var
  pad: array[0..255] of Integer;
begin
  Inc(depth);
  pad[0] := depth;
  pad[255] := depth;
  Recurse;
  { keeps `pad` live so the frame cannot be optimised into a tail call }
  if pad[0] <> pad[255] then WriteLn('never');
end;

procedure WorkerEntry(arg: Pointer);
begin
  Recurse;
end;

var
  stackBase, tid, ignore: Int64;
begin
  depth := 0;
  SetSignalHandler(11, @OnSegv);
  if ParamCount > 0 then
  begin
    WriteLn('worker');
    tidword := 0;
    stackBase := __pxxrawsyscall(SYS_mmap, 0, STK, PROT_RW, MAP_ANON_PRIV, -1, 0);
    if stackBase < 0 then begin WriteLn('mmap FAIL'); Halt(1); end;
    tid := __pxxclone(PXX_CLONE_THREAD, stackBase + STK, @WorkerEntry, nil, @tidword);
    if tid <= 0 then begin WriteLn('clone FAIL'); Halt(1); end;
    ignore := __pxxrawsyscall(SYS_futex, PtrUInt(@tidword), FUTEX_WAIT, tid, 0, 0, 0);
    WriteLn('joined without the worker halting -- its overflow was not handled');
    Halt(1);
  end
  else
  begin
    WriteLn('main');
    Recurse;
    WriteLn('unreachable');
    Halt(1);
  end;
end.
