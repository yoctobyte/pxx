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
  shared: LongInt;                        { the positive control: races on purpose }
  Handles: array[0..NT-1] of TThreadHandle;
  Seen:    array[0..NT-1] of LongInt;
  Zero:    array[0..NT-1] of LongInt;     { was this thread's copy 0 on entry? }
  Cross:   array[0..NT-1] of LongInt;     { times `mine` read as another thread's }
  SawOther:array[0..NT-1] of LongInt;     { times `shared` read as another thread's }

procedure Body(arg: Pointer);
var idx, k: Integer;
begin
  idx := Integer(PtrUInt(arg));
  if mine = 0 then Zero[idx] := 1 else Zero[idx] := 0;
  mine := 100 + idx;
  for k := 1 to CHURN do
  begin
    shared := 900 + idx;
    if mine <> 100 + idx then Inc(Cross[idx]);
    if shared <> 900 + idx then Inc(SawOther[idx]);
  end;
  Seen[idx] := mine;
end;

var
  i, kept, zeroed, clean, raced: Integer;

begin
  mine := 7;
  shared := 7;
  for i := 0 to NT-1 do
  begin
    Seen[i] := -1; Zero[i] := -1; Cross[i] := 0; SawOther[i] := 0;
  end;

  for i := 0 to NT-1 do
    if PalThreadCreate(Handles[i], @Body, Pointer(PtrUInt(i)), 0) <> 0 then
      WriteLn('FAIL: could not spawn thread ', i);
  for i := 0 to NT-1 do PalThreadJoin(Handles[i]);

  kept := 0; zeroed := 0; clean := 0; raced := 0;
  for i := 0 to NT-1 do
  begin
    if Seen[i] = 100 + i then Inc(kept);
    if Zero[i] = 1 then Inc(zeroed);
    if Cross[i] = 0 then Inc(clean);
    if SawOther[i] > 0 then Inc(raced);
  end;

  WriteLn('kept=', kept, '/', NT);
  WriteLn('zeroed-on-entry=', zeroed, '/', NT);
  WriteLn('no-crosstalk=', clean, '/', NT);
  WriteLn('control-raced=', raced > 0);
  WriteLn('main-copy=', mine);
  if (kept = NT) and (zeroed = NT) and (clean = NT) and (raced > 0) and (mine = 7) then
    WriteLn('THREADVAR OK')
  else
    WriteLn('THREADVAR FAIL');
end.
