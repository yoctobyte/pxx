{ TCriticalSection excludes under real contention, and a waiter SLEEPS.

  Two properties, and the second is the one that regresses silently. The lock
  was a no-op stub until 2026-08-05 (four threads doing 2000 guarded increments
  summed to 7403, not 8000) and then a spinlock until 2026-08-09, because
  palsync's futex mutex was only reachable through palthread, which holds
  __pxxclone and so demands --threadsafe from everything that touches it
  (bug-b-futex-helpers-are-trapped-behind-pxxclone).

  Phase 1 is the exclusion count. Phase 2 holds the lock for HOLD_MS while three
  threads queue behind it: correct output is identical whether they sleep in the
  kernel or spin, so the assertion that separates the two is CPU TIME, checked
  by the caller (see lib-test). Spinning burnt 1.73 s of user CPU here; the
  futex mutex burns 0.00 s over the same 0.6 s of wall clock.

  Phase 2 also proves the wake path: if the futex wake were lost, WaitFor would
  hang rather than print. }
{$threadsafe on}
program lib_criticalsection_blocking;

uses palthreadobj, sysutils, syncobjs;

const
  BUMPS   = 2000;
  HOLD_MS = 600;

var
  Counter: Integer;
  Lock:    TCriticalSection;

type
  TBumper = class(TThread)
  public
    procedure Execute; override;
  end;

  TWaiter = class(TThread)
  public
    procedure Execute; override;
  end;

procedure TBumper.Execute;
var i: Integer;
begin
  for i := 1 to BUMPS do
  begin
    Lock.Acquire;
    try Counter := Counter + 1; finally Lock.Release; end;
  end;
end;

procedure TWaiter.Execute;
begin
  { blocks until the main thread lets go — this is the phase whose COST is
    the point, not its result }
  Lock.Acquire;
  Lock.Release;
end;

var
  b: array[0..3] of TBumper;
  w: array[0..2] of TWaiter;
  k: Integer;
begin
  Lock := TCriticalSection.Create;

  { --- phase 1: the lock excludes --- }
  Counter := 0;
  for k := 0 to 3 do
  begin
    b[k] := TBumper.Create(True);
    b[k].FreeOnTerminate := False;
    b[k].Start;
  end;
  for k := 0 to 3 do b[k].WaitFor;
  for k := 0 to 3 do b[k].Free;
  if Counter = 4 * BUMPS then writeln('count=', Counter)
  else writeln('count=', Counter, ' EXPECTED=', 4 * BUMPS);

  { --- phase 2: waiters block rather than spin (cost measured by the caller) --- }
  Lock.Acquire;
  for k := 0 to 2 do
  begin
    w[k] := TWaiter.Create(True);
    w[k].FreeOnTerminate := False;
    w[k].Start;
  end;
  Sleep(HOLD_MS);
  Lock.Release;
  for k := 0 to 2 do w[k].WaitFor;
  for k := 0 to 2 do w[k].Free;

  Lock.Free;
  writeln('CSBLOCK OK');
end.
