program compat;
{ async (per-thread coroutine scheduler) INSIDE parallel (OS-thread) workers.
  Each parallel-for worker gets its own reactor (CurR keys on gettid), spawns a
  coroutine that yields then writes its slot. Proves the two models compose. }
uses palparallel, scheduler;

const N = 400;
var res: array[0..N-1] of Integer;

procedure Work(arg: Pointer);
var idx: Integer;
begin
  idx := Integer(arg);
  CoYield;              { suspend on THIS thread's reactor }
  CoYield;
  res[idx] := idx * 2;  { disjoint slot }
end;

procedure Drive;
var i: Integer;
begin
  parallel for i := 0 to N-1 do
  begin
    Spawn(@Work, Pointer(i));
    RunUntilDone;        { runs this worker-thread's own scheduler to completion }
  end;
end;

var i, err: Integer;
begin
  for i := 0 to N-1 do res[i] := -1;
  Drive;
  err := 0;
  for i := 0 to N-1 do if res[i] <> i*2 then Inc(err);
  writeln('compat err=', err, ' (expect 0)');
  if err = 0 then writeln('ASYNC x PARALLEL OK') else writeln('ASYNC x PARALLEL FAIL');
end.
