program test_a_threadvar_is_per_thread;
{ feature-p-threadvar-is-not-supported-at-any-scope -- the half a single-threaded
  run physically cannot observe.

  THE POSITIVE CONTROL IS THE PLAIN GLOBAL, and it is the reason this file is
  worth its runtime. Every thread hammers `shared` and `mine` in the same loop
  with the same shape of write. If the threadvar were an ordinary global, BOTH
  would show cross-talk and both rows would fail; if the harness were inert,
  `shared` would show none and that row would fail. The two rows can only both
  pass if the compiler really is giving `mine` one copy per thread -- a control
  drawn from the population the question is about, not from a neighbouring one.

  IT ALSO ASSERTS THE ZERO. A cloned thread's block is carved off its own stack,
  which is reused memory, and the clone stub zeroes it -- so `mine` must read 0
  on entry to every child even though the main thread set its own copy to 7
  first. Without that the first thing a threadvar would carry is whatever the
  previous thread left on that stack.

  CHURN, not a single compare: a per-thread slot that happened to be right once
  proves nothing about a slot that is recomputed from gs on every access. The
  loop is what makes a wrong base show up.

  THE CONTROL USED TO BE `control-raced`, AND IT WAS LOAD-DEPENDENT -- 2026-09-16.
  It asserted that the deliberate race on `shared` ACTUALLY MANIFESTED
  (SawOther > 0 for some thread). A race manifesting is a property of the
  SCHEDULER, not of the compiler, so the row measured the host and not the tree.
  It went NEW-RED on borg at 881fdee59b6f with every feature row still passing
  -- `kept=4/4 zeroed-on-entry=4/4 no-crosstalk=4/4 main-copy=7`, and only
  `control-raced=TRUE -> FALSE`. Reproduced deterministically: `taskset -c 0`
  gives control-raced=FALSE 5/5 while the four feature rows stay 4/4, and the
  unpinned binary on 12 cores gives control-raced=TRUE 30/30. The race window is
  two instructions wide, so when the four threads are time-sliced onto one CPU
  instead of running on four, nothing lands in it. borg was measured at load
  12-19 that evening.

  THAT ALSO RULES OUT THE ALTERNATIVE, WHICH IS A REAL BUG IN THIS SUBSYSTEM:
  if `shared` had been wrongly rewritten as a threadvar -- RewriteThreadVarRefs
  poisoning a non-threadvar symbol, the failure mode the sibling row in this
  same Makefile target exists for -- cross-talk would vanish on ANY core count.
  It does not: 30/30 TRUE on 12 cores. `shared` is genuinely shared and the
  compiler was never at fault here.

  SO THE CONTROL IS NOW DETERMINISTIC AND ASSERTS THE SAME PROPOSITION TWO WAYS,
  neither of which needs the scheduler to cooperate:
    `distinct-tids` -- the four children report four DISTINCT PalThreadSelf
      values. This is the inertness claim the race was really standing in for:
      it fails if the threads never spawned, and it cannot be faked by a
      scheduler that happens to serialise them.
    `control-shared` -- after the join, the MAIN thread reads `shared` and must
      NOT see its own 7. A child's write to a plain global has to be visible
      here; if `shared` were per-thread it would still read 7. The join is the
      happens-before, so this is ordering, not luck.
  `control-shared` asserts `shared <> 7` and NOT a value: which child wrote last
  is scheduling-dependent (measured 903 here, but that is not a guarantee), so
  pinning the number would have planted the same kind of flake this change is
  removing.

  THE PLAIN-GLOBAL SUBSTITUTION IS STILL CAUGHT, AND STILL CAUGHT WHEN PINNED TO
  ONE CPU -- but NOT by the rows a reader would expect, which is the part worth
  writing down. Replacing `threadvar` with `var` in this exact file (measured
  2026-09-16, 0/10 passes on each):

      12 cores  kept=1/4  zeroed-on-entry=0/4  no-crosstalk=1/4  main-copy=103
      taskset   kept=4/4  zeroed-on-entry=0/4  no-crosstalk=4/4  main-copy=103

  `kept` and `no-crosstalk` STOP DISCRIMINATING under serial execution: if the
  threads do not overlap, a plain global still reads back each thread's own last
  write for the whole of that thread's run, so both rows go green on the broken
  program. What catches it on one CPU is `zeroed-on-entry` (thread 1 enters
  holding thread 0's leftover 100, not 0) and `main-copy` (main's 7 was
  overwritten to 103). Those two need no concurrency at all, which is why the
  discrimination survives the load conditions that broke the old control.

  NOT AN FPC DIFFERENTIAL: fpc reaches threads through cthreads and pxx through
  palthread, so the two programs cannot be the same source. The LANGUAGE surface
  is differential and lives in test_a_threadvar_is_a_variable.pas. }

uses palthread;

const
  NT = 4;
  CHURN = 200000;

threadvar
  mine: LongInt;

var
  shared: LongInt;                        { the positive control: a PLAIN global }
  Handles: array[0..NT-1] of TThreadHandle;
  Seen:    array[0..NT-1] of LongInt;
  Zero:    array[0..NT-1] of LongInt;     { was this thread's copy 0 on entry? }
  Cross:   array[0..NT-1] of LongInt;     { times `mine` read as another thread's }
  Tid:     array[0..NT-1] of Int64;       { this thread's own identity }

procedure Body(arg: Pointer);
var idx, k: Integer;
begin
  idx := Integer(PtrUInt(arg));
  Tid[idx] := PalThreadSelf;
  if mine = 0 then Zero[idx] := 1 else Zero[idx] := 0;
  mine := 100 + idx;
  for k := 1 to CHURN do
  begin
    shared := 900 + idx;
    if mine <> 100 + idx then Inc(Cross[idx]);
  end;
  Seen[idx] := mine;
end;

var
  i, j, kept, zeroed, clean, distinct: Integer;
  dup: Boolean;

begin
  mine := 7;
  shared := 7;
  for i := 0 to NT-1 do
  begin
    Seen[i] := -1; Zero[i] := -1; Cross[i] := 0; Tid[i] := -1;
  end;

  for i := 0 to NT-1 do
    if PalThreadCreate(Handles[i], @Body, Pointer(PtrUInt(i)), 0) <> 0 then
      WriteLn('FAIL: could not spawn thread ', i);
  for i := 0 to NT-1 do PalThreadJoin(Handles[i]);

  kept := 0; zeroed := 0; clean := 0; distinct := 0;
  for i := 0 to NT-1 do
  begin
    if Seen[i] = 100 + i then Inc(kept);
    if Zero[i] = 1 then Inc(zeroed);
    if Cross[i] = 0 then Inc(clean);
    dup := False;
    for j := 0 to i-1 do if Tid[j] = Tid[i] then dup := True;
    if (Tid[i] > 0) and (not dup) then Inc(distinct);
  end;

  WriteLn('kept=', kept, '/', NT);
  WriteLn('zeroed-on-entry=', zeroed, '/', NT);
  WriteLn('no-crosstalk=', clean, '/', NT);
  WriteLn('distinct-tids=', distinct, '/', NT);
  WriteLn('control-shared=', shared <> 7);
  WriteLn('main-copy=', mine);
  if (kept = NT) and (zeroed = NT) and (clean = NT) and (distinct = NT)
     and (shared <> 7) and (mine = 7) then
    WriteLn('THREADVAR OK')
  else
    WriteLn('THREADVAR FAIL');
end.
