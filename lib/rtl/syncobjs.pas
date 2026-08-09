{ SPDX-License-Identifier: Zlib }
unit syncobjs;

{ FPC's SyncObjs surface. TCriticalSection is a real lock.

  It was a NO-OP STUB until 2026-08-05 — every method an empty body, TryEnter
  always True — from back when generated code had no preemptive threads. The
  thread runtime landed since (palthread/palsync/palthreadobj), so threaded code
  was locking with nothing and losing updates in silence: four threads doing
  2000 guarded increments each summed to 7403 instead of 8000
  (tools/fpc_diff_probe.sh, thread-critical-section).

  It was a SPINLOCK until 2026-08-09, because palsync's futex mutex was only
  reachable through palthread, and palthread contains __pxxclone — so `uses
  syncobjs` would have started demanding --threadsafe, breaking callers that do
  no threading at all (Synapse's ssfpc.inc). Splitting the futex wrappers into a
  dependency-free `palfutex` removed that wall
  (bug-b-futex-helpers-are-trapped-behind-pxxclone), so this is now Drepper's
  3-state futex mutex: uncontended lock/unlock is still a single atomic with no
  syscall, but a waiter now SLEEPS in the kernel instead of burning its
  timeslice while the holder runs.

  NOT RECURSIVE, matching FPC: TCriticalSection there initialises a default
  pthread mutex, which on glibc is not recursive either. Re-entering from the
  same thread hangs. Detecting that needs an owner thread id, which needs gettid
  — that one does still live in palthread, behind the __pxxclone gate. }

interface

uses palsync;

type
  TCriticalSection = class
  private
    FLock: TMutex;   { 0 free | 1 locked | 2 locked+waiters — the futex word }
  public
    constructor Create;
    procedure Acquire;
    procedure Release;
    procedure Enter;
    procedure Leave;
    function TryEnter: Boolean;
  end;

implementation

constructor TCriticalSection.Create;
begin
  MutexInit(FLock);
end;

procedure TCriticalSection.Acquire;
begin
  MutexLock(FLock);
end;

procedure TCriticalSection.Release;
begin
  MutexUnlock(FLock);
end;

procedure TCriticalSection.Enter;
begin
  Acquire;
end;

procedure TCriticalSection.Leave;
begin
  Release;
end;

function TCriticalSection.TryEnter: Boolean;
begin
  Result := MutexTryLock(FLock);
end;

end.
