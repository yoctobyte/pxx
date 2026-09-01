{ Two threads each raising and catching a freshly constructed exception object.
  bug-a-two-threads-raising-object-exceptions-corrupt-the-heap

  WHY THIS IS NOT COVERED BY test_exception_threads_race.pas, which also raises
  on two threads: that one is deliberately ALLOCATION-FREE (it re-raises objects
  made once, so the heap lock does not serialise the interleaving it watches).
  Allocation-free is exactly the case that could not fail here. This test is its
  complement and the two are not redundant.

  THE MECHANISM, so a future reader does not "simplify" the shape away: on
  x86-64 the heap lock is emitted by CODEGEN at the tkGetMem/tkFreeMem IR sites
  and is NOT taken inside the runtime helpers. Handler exit used to free the
  caught object by CALLING PXXObjFree, whose plain arm ends in a bare PXXFree —
  so the free list was mutated with no lock held. i386 and aarch64 lock inside
  the Pascal helpers (PXX_TS_SOFTLOCK) and were never exposed; x86-64 is the
  fast one, the broken one, and the only target that can create a thread at all.

  THE SINGLE-THREADED PHASE RUNS FIRST AND IS THE POINT. It performs the same
  N raises through the same lowering, so it separates "the free is wrong" from
  "the free is wrong CONCURRENTLY". Measured before the fix: phase 1 clean
  20000/20000, phase 2 SIGSEGV 3 of 3. A crash in phase 1 would mean something
  else entirely broke and this test would be the wrong one to read.

  N=20000 is the measured deterministic threshold, not a round number: N=1 and
  N=100 passed on the broken build and N=1000 crashed. Do not lower it. }
program test_threadsafe_exception_two_threads;

{$THREADSAFE ON}

const N = 20000;

type
  TFoo = class Code: Integer; end;

var
  hitsA, hitsB, ready, go: Integer;
  id: TThreadID;

{ Constructs per raise ON PURPOSE — that allocation and its matching free at
  handler exit are the whole subject. }
procedure Spin(var hits: Integer);
var i: Integer;
begin
  for i := 1 to N do
    try
      raise TFoo.Create;
    except
      on E: TFoo do hits := hits + 1;
    end;
end;

function Body(p: Pointer): PtrInt;
begin
  ready := 1;
  while go = 0 do ;
  Spin(hitsB);
  Body := 0;
end;

begin
  { phase 1 — the control: same lowering, one thread }
  Spin(hitsA);
  if hitsA <> N then
  begin WriteLn('FAIL: single-thread hits=', hitsA, ', want ', N); Halt(1); end;

  { phase 2 — one more thread, nothing else different }
  hitsA := 0;
  id := BeginThread(@Body, nil);
  while ready = 0 do ;
  go := 1;
  Spin(hitsA);
  WaitForThreadTerminate(id, 0);

  if hitsA <> N then
  begin WriteLn('FAIL: main-thread hits=', hitsA, ', want ', N); Halt(1); end;
  if hitsB <> N then
  begin WriteLn('FAIL: child-thread hits=', hitsB, ', want ', N); Halt(1); end;
  WriteLn('TS EXC TWO THREADS OK');
end.
