program TestTimer;
{ Async timers over the reactor (x86-64). Three coroutines nap for different
  durations, spawned out of order; each is a timerfd parked on the same epoll,
  so they sleep concurrently (total ~150ms, not 300) and wake in duration order
  regardless of spawn order. Deterministic: the wake order is the sorted order. }
uses scheduler;

procedure Napper(arg: Pointer);
var ms: Integer;
begin
  ms := Integer(arg);
  CoSleep(ms);
  writeln('woke ', ms);
end;

begin
  Spawn(@Napper, Pointer(100));
  Spawn(@Napper, Pointer(50));
  Spawn(@Napper, Pointer(150));
  RunUntilDone;
  writeln('done');
end.
