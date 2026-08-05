{ SPDX-License-Identifier: Zlib }
unit syncobjs;

{ FPC's SyncObjs surface. TCriticalSection is a real lock.

  It was a NO-OP STUB until 2026-08-05 — every method an empty body, TryEnter
  always True — from back when generated code had no preemptive threads. The
  thread runtime landed since (palthread/palsync/palthreadobj), so threaded code
  was locking with nothing and losing updates in silence: four threads doing
  2000 guarded increments each summed to 7403 instead of 8000
  (tools/fpc_diff_probe.sh, thread-critical-section).

  WHY A SPINLOCK AND NOT palsync's FUTEX MUTEX: palsync uses palthread, and
  palthread contains __pxxclone, so anything reaching it fails to compile
  without --threadsafe. `uses syncobjs` must not start demanding that flag —
  Synapse's ssfpc.inc is exactly the kind of caller that would break, and it
  does no threading. The atomic intrinsics need no unit at all, so the lock here
  costs nothing in dependencies.

  The trade-off, stated plainly: an uncontended Acquire is one CAS, the same as
  any mutex. Under contention this SPINS rather than sleeping, so a waiter burns
  CPU while the holder runs, and on an oversubscribed box a waiter can spin
  through its whole timeslice. That is a performance property, not a correctness
  one — and it is unambiguously better than the no-op it replaces. Splitting the
  futex helpers out of palthread into their own unit would let this become a
  proper blocking mutex: bug-b-futex-helpers-are-trapped-behind-pxxclone.

  NOT RECURSIVE, matching FPC: TCriticalSection there initialises a default
  pthread mutex, which on glibc is not recursive either. Re-entering from the
  same thread hangs. Detecting that needs an owner thread id, which needs
  gettid, which lives in palthread — the same wall. }

interface

type
  TCriticalSection = class
  private
    FLock: Integer;   { 0 = free, 1 = held. The futex-word shape, so the
                        upgrade to a blocking mutex is a body change only. }
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
  FLock := 0;
end;

procedure TCriticalSection.Acquire;
begin
  { Test-and-test-and-set: the plain read in the inner loop keeps the cache line
    shared while waiting, instead of every waiter fighting for it exclusively
    with a CAS per iteration. }
  while __pxxatomic_cas(@FLock, 0, 1) <> 0 do
    while FLock <> 0 do
      ;
end;

procedure TCriticalSection.Release;
var ignore: Int64;
begin
  ignore := __pxxatomic_xchg(@FLock, 0);
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
  Result := __pxxatomic_cas(@FLock, 0, 1) = 0;
end;

end.
