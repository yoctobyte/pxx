program TestScheduler;
{ Cooperative coroutine scheduler: Spawn / CoYield / RunUntilDone. Two workers
  of different lengths interleave round-robin until both finish, then a third
  short one runs. Exercises the procedural-type spawn path (no asm entry shim)
  and the heap-stack / context-switch machinery. x86-64 only for now. }
uses scheduler;

procedure Counter(arg: Pointer);
var i, n: Integer;
begin
  n := Integer(arg);
  for i := 1 to n do
  begin
    writeln('c', n, ':', i);
    CoYield;
  end;
end;

procedure Once(arg: Pointer);
begin
  writeln('once ', Integer(arg));
end;

begin
  Spawn(@Counter, Pointer(2));
  Spawn(@Counter, Pointer(3));
  Spawn(@Once, Pointer(7));
  RunUntilDone;
  writeln('all done');
end.
