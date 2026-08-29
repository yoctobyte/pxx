program test_sched_reactors_wide;
{ More parallel-for workers than the OLD MAX_REACTORS (16), on any host.

  CurR used to initialise `slot := 0` and treat that initializer as its answer
  when every reactor was already in use, so the 17th thread silently adopted a
  LIVE thread's reactor: two OS threads driving one coroutine table, surfacing
  much later as 'coroutine stack overflow (canary clobbered)'.

  The worker count is SET here rather than inherited from the CPU count. That
  is the whole point of this test: the defect was reported as needing a 24-core
  box, but cores were only ever a proxy for the DEFAULT worker count, and
  PXXSetParForWorkers makes it reachable on a 4-core laptop. Before the fix this
  program failed roughly half its runs on a 12-core box.
  bug-a-the-17th-thread-silently-aliases-reactor-slot-0 }
uses palparallel, scheduler;

const
  N       = 400;
  WORKERS = 20;   { > the old ceiling of 16; <= PAR_MAX_WORKERS }

var res: array[0..N-1] of Integer;

procedure Work(arg: Pointer);
var idx: Integer;
begin
  idx := Integer(arg);
  CoYield;              { suspend on THIS thread's reactor }
  CoYield;
  res[idx] := idx * 2;  { disjoint slot — any aliasing shows up as a wrong value }
end;

procedure Drive;
var i: Integer;
begin
  parallel for i := 0 to N-1 do
  begin
    Spawn(@Work, Pointer(i));
    RunUntilDone;
  end;
end;

var i, err: Integer;
begin
  PXXSetParForWorkers(WORKERS);
  if PXXParForWorkers <> WORKERS then
  begin writeln('SCHED WIDE FAIL (workers=', PXXParForWorkers, ')'); Halt(1); end;
  for i := 0 to N-1 do res[i] := -1;
  Drive;
  err := 0;
  for i := 0 to N-1 do if res[i] <> i*2 then Inc(err);
  if err = 0 then writeln('SCHED WIDE OK') else writeln('SCHED WIDE FAIL err=', err);
end.
