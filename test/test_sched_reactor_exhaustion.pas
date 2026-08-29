program test_sched_reactor_exhaustion;
{ The reactor table EXHAUSTED — the arm that used to alias slot 0.

  Built with -dPXX_SCHED_TINY_REACTORS, which lowers MAX_REACTORS to 2, so three
  or more worker threads overrun it deterministically on any host. That define
  exists for exactly this test: with the shipping ceiling of 64 (= the
  PAR_MAX_WORKERS cap on a parallel-for's width) the arm is unreachable from
  Pascal at all, and an unreachable guard is an untested one.

  Must print the named fatal ONCE and exit 216 — not corrupt, not hang, and
  above all not exit 0. Earlier attempts at this guard did each of those:
  Halt raced and exited 0 with several threads refused, and serialising Halt
  deadlocked against its own thread-join. It uses exit_group directly now.
  bug-a-the-17th-thread-silently-aliases-reactor-slot-0 }
uses palparallel, scheduler;

procedure Work(arg: Pointer);
begin
  CoYield;
end;

procedure Drive;
var i: Integer;
begin
  parallel for i := 0 to 63 do
  begin
    Spawn(@Work, Pointer(i));
    RunUntilDone;
  end;
end;

begin
  PXXSetParForWorkers(4);        { 4 threads, 2 reactors }
  Drive;
  writeln('UNREACHED: the exhaustion guard did not fire');
end.
