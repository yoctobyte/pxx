program test_signal_num_threads_race;
{ __pxxSigNum must answer about THIS thread's signal, not whichever one the
  process parked last (bug-a-the-parked-signal-slots-are-process-wide-and-race).

  Two threads, each `tkill`-ing ITSELF, with a different signal each: main gets
  SIGUSR1, the worker SIGUSR2. The handler asks which thread it is on and
  compares __pxxSigNum against the signal that thread sends itself, so every
  delivery has exactly one right answer and it is known before the run starts.

  While the parked fields were process-wide BSS, two threads in the dispatch
  stub at once clobbered each other: 91104 wrong answers in 400000 deliveries
  (~23%, frankA, 2026-08-31), against ZERO for the same binary with the worker
  never started. That is the control that makes the number mean anything -- a
  count of mismatches proves nothing without a run that cannot produce them --
  and it is the FIRST phase here rather than a separate program, so the two
  numbers come from one binary and one build.

  The mismatch counter is deliberately non-atomic. It has to be read as
  "approximately N" when it is large, and exactly when it is 0, which is the
  only value this test accepts. hitsA/hitsB are also non-atomic and are printed
  only as evidence that both threads actually took their signals -- a run where
  the worker never started would otherwise pass on mismatch=0 alone, which is
  the "count the good, not the bad" trap.

  x86-64 only, like every thread test in this repo (see test_signal_threads on
  why that is a cluster and not a new precedent). }

const
  SYS_gettid = 186; SYS_tkill = 200;
  USR1 = 10; USR2 = 12;
  ROUNDS = 200000;

var
  mainTid, workerTid: Int64;
  mismatch, hitsA, hitsB, ready, go: Integer;
  id: TThreadID;

function Tid: Int64; begin Tid := __pxxrawsyscall(SYS_gettid); end;

procedure Hook;
var n: Integer; t: Int64;
begin
  t := Tid;
  n := __pxxSigNum;
  if t = mainTid then
  begin
    hitsA := hitsA + 1;
    if n <> USR1 then mismatch := mismatch + 1;
  end
  else
  begin
    hitsB := hitsB + 1;
    if n <> USR2 then mismatch := mismatch + 1;
  end;
end;

function Body(p: Pointer): PtrInt;
var i: Integer; r: Int64;
begin
  workerTid := Tid;
  ready := 1;
  while go = 0 do ;
  for i := 1 to ROUNDS do
    r := __pxxrawsyscall(SYS_tkill, workerTid, USR2);
  Body := 0;
end;

var i: Integer; r: Int64;
begin
  mainTid := Tid;
  SetSignalHandler(USR1, @Hook);
  SetSignalHandler(USR2, @Hook);

  { ---- phase 1: the CONTROL. One thread, so no other thread can park a value
    between this one's park and its read. Any mismatch here is a defect in the
    parking itself and would make phase 2 unreadable. ---- }
  for i := 1 to ROUNDS do
    r := __pxxrawsyscall(SYS_tkill, mainTid, USR1);
  WriteLn('single-thread-mismatch=', mismatch);
  WriteLn('single-thread-hits=', hitsA > 0);

  { ---- phase 2: two threads, each signalling itself ---- }
  mismatch := 0; hitsA := 0; hitsB := 0;
  id := BeginThread(@Body, nil);
  while ready = 0 do ;
  go := 1;
  for i := 1 to ROUNDS do
    r := __pxxrawsyscall(SYS_tkill, mainTid, USR1);
  WaitForThreadTerminate(id, 0);

  WriteLn('both-threads-took-signals=', (hitsA > 0) and (hitsB > 0));
  WriteLn('two-thread-mismatch=', mismatch);
end.
