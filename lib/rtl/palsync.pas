unit palsync;
{ M2 libc-free synchronisation primitives (meta-multithreading). A futex-backed
  mutex built on the atomic intrinsics (__pxxatomic_cas/xchg) + PalFutexWait/Wake
  from the M1 thread PAL. No libc — pure Linux futex syscalls.

  TMutex is Drepper's 3-state futex mutex ("Futexes Are Tricky"): it spins through
  no syscall at all in the uncontended fast path, and only enters the kernel
  (futex) when a thread genuinely has to block. State: 0 = free, 1 = locked with no
  waiters, 2 = locked and at least one waiter may be sleeping.

  x86-64 first (the atomic intrinsics are x86-64 today). }

interface

uses palthread;

type
  PMutex = ^TMutex;
  { Keep a TMutex alive (and its address stable) for as long as threads use it —
    the futex word IS m.State. Zero-initialise with MutexInit (or just rely on
    a zeroed record: State 0 = free). }
  TMutex = record
    State: Integer;   { 0 free | 1 locked | 2 locked+waiters }
  end;

{ Initialise to the free state. }
procedure MutexInit(var m: TMutex);

{ Acquire, blocking via futex only under contention. }
procedure MutexLock(var m: TMutex);

{ Release, waking one waiter only if any may be sleeping. }
procedure MutexUnlock(var m: TMutex);

{ Non-blocking acquire; True if it took the lock. }
function MutexTryLock(var m: TMutex): Boolean;

type
  PEvent = ^TEvent;
  { Futex-backed event. Manual-reset stays signalled until EventReset and releases
    every waiter (a one-shot "go" gun); auto-reset releases exactly one waiter per
    EventSet and clears itself (hand-off). Keep alive + address-stable like TMutex. }
  TEvent = record
    State:  Integer;   { 0 = unsignalled | 1 = signalled }
    Manual: Boolean;
  end;

{ Initialise unsignalled. }
procedure EventInit(var e: TEvent; manualReset: Boolean);
{ Signal: wake all waiters (manual) or one (auto). }
procedure EventSet(var e: TEvent);
{ Clear the signalled state (mainly meaningful for manual-reset). }
procedure EventReset(var e: TEvent);
{ Block until signalled; auto-reset consumes the signal. }
procedure EventWait(var e: TEvent);

implementation

procedure MutexInit(var m: TMutex);
begin
  m.State := 0;
end;

function MutexTryLock(var m: TMutex): Boolean;
begin
  { took it iff it was free (0) and we swapped in 1 }
  Result := __pxxatomic_cas(@m.State, 0, 1) = 0;
end;

procedure MutexLock(var m: TMutex);
var
  c: Integer;
begin
  { fast path: free -> locked-no-waiters }
  c := Integer(__pxxatomic_cas(@m.State, 0, 1));
  if c <> 0 then
  begin
    { contended: drive the state to 2 and sleep until it becomes free }
    if c <> 2 then
      c := Integer(__pxxatomic_xchg(@m.State, 2));
    while c <> 0 do
    begin
      PalFutexWait(@m.State, 2);                  { sleep while State = 2 }
      c := Integer(__pxxatomic_xchg(@m.State, 2));
    end;
  end;
end;

procedure MutexUnlock(var m: TMutex);
begin
  { if there were waiters (state was 2), drop to free and wake exactly one }
  if Integer(__pxxatomic_xchg(@m.State, 0)) = 2 then
    PalFutexWake(@m.State, 1);
end;

const
  WAKE_ALL = $7FFFFFFF;

procedure EventInit(var e: TEvent; manualReset: Boolean);
begin
  e.State := 0;
  e.Manual := manualReset;
end;

procedure EventSet(var e: TEvent);
var ignore: Integer;
begin
  ignore := Integer(__pxxatomic_xchg(@e.State, 1));
  if e.Manual then PalFutexWake(@e.State, WAKE_ALL)
  else PalFutexWake(@e.State, 1);
end;

procedure EventReset(var e: TEvent);
var ignore: Integer;
begin
  ignore := Integer(__pxxatomic_xchg(@e.State, 0));
end;

procedure EventWait(var e: TEvent);
begin
  if e.Manual then
  begin
    { stays signalled — just wait for State to become non-zero }
    while e.State = 0 do
      PalFutexWait(@e.State, 0);
  end
  else
  begin
    { auto-reset — atomically consume the signal (1 -> 0); sleep until available }
    while Integer(__pxxatomic_cas(@e.State, 1, 0)) <> 1 do
      PalFutexWait(@e.State, 0);
  end;
end;

end.
