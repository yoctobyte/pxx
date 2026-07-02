{ SPDX-License-Identifier: Zlib }
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

type
  { FPC-compatible critical-section API — a TMutex under familiar names so existing
    threaded Pascal (InitCriticalSection/EnterCriticalSection/...) compiles as-is. }
  TRTLCriticalSection = TMutex;
  PRTLCriticalSection = ^TRTLCriticalSection;

procedure InitCriticalSection(var cs: TRTLCriticalSection);
procedure DoneCriticalSection(var cs: TRTLCriticalSection);      { futex needs no teardown }
procedure EnterCriticalSection(var cs: TRTLCriticalSection);
procedure LeaveCriticalSection(var cs: TRTLCriticalSection);
function  TryEnterCriticalSection(var cs: TRTLCriticalSection): Boolean;

type
  { One-time initialiser guard. Zero-initialise (0) before first use. RunOnce calls
    proc exactly once across all racing threads; later/lost racers block until the
    winner finishes. }
  TOnceControl = Integer;   { 0 = pending | 1 = running | 2 = done }
  TOnceProc = procedure;

procedure RunOnce(var ctl: TOnceControl; proc: TOnceProc);

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

procedure InitCriticalSection(var cs: TRTLCriticalSection);
begin
  MutexInit(cs);
end;

procedure DoneCriticalSection(var cs: TRTLCriticalSection);
begin
  { nothing to release — a futex word owns no kernel resource }
end;

procedure EnterCriticalSection(var cs: TRTLCriticalSection);
begin
  MutexLock(cs);
end;

procedure LeaveCriticalSection(var cs: TRTLCriticalSection);
begin
  MutexUnlock(cs);
end;

function TryEnterCriticalSection(var cs: TRTLCriticalSection): Boolean;
begin
  Result := MutexTryLock(cs);
end;

procedure RunOnce(var ctl: TOnceControl; proc: TOnceProc);
var ignore: Int64;
begin
  if ctl = 2 then Exit;                              { fast path: already done }
  if Integer(__pxxatomic_cas(@ctl, 0, 1)) = 0 then
  begin
    { we won the race — run the initialiser exactly once, then publish + wake }
    proc();
    ignore := __pxxatomic_xchg(@ctl, 2);
    PalFutexWake(@ctl, WAKE_ALL);
  end
  else
    { someone else is running it — wait until they publish done (2) }
    while ctl <> 2 do
      PalFutexWait(@ctl, 1);
end;

end.
