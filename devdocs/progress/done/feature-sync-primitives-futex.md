# Sync primitives on futex — TCriticalSection/TMutex/TEvent/Once + atomics (M2)

- **Type:** feature (RTL) — Track A
- **Status:** done
- **Opened:** 2026-06-30
- **Umbrella:** [[meta-multithreading]]. Needs M1 ([[feature-pal-thread-primitives]]).

## Invariant

Threading is **opt-in**, off by default; the single-threaded self-build stays
**byte-identical**. **No libc** — built on [[feature-pal-thread-primitives]]
(syscalls only). Milestones land in any order under [[meta-multithreading]].

## Scope

Real synchronisation on `PalFutexWait/Wake`, replacing today's parse-compat
stubs in `lib/rtl/syncobjs.pas` (TCriticalSection methods are currently no-ops):
- **TMutex / TCriticalSection** — futex fast-path (atomic CAS uncontended, futex
  on contention); recursive variant if needed.
- **TEvent / condition variable** — futex sequence counter (the pthread_cond shape).
- **Once** — atomic state + futex (pthread_once shape).
- **Atomics surface** — InterlockedIncrement/Decrement/CompareExchange (lock-prefix
  x86-64; the cross atoms come with M5).

## Acceptance
- A multi-thread test (on M1) shows mutual exclusion (no lost updates under
  contention), event signal/wait, and once-runs-once; libc-free. Self-build
  byte-identical. The stub TCriticalSection becomes real without breaking the
  Synapse/single-thread parse-compat users.

## Status — M2 first slice LANDED (2026-06-30)

DONE (x86-64):
- Atomic intrinsics: `__pxxatomic_xchg(addr, val)`, `__pxxatomic_cas(addr, expected,
  newval)`, `__pxxatomic_add(addr, delta)` — AN_ATOMIC(73) -> IR_ATOMIC(63), x86-64
  lock-prefixed 32-bit rmw (xchg / lock cmpxchg / lock xadd), returns the OLD value.
  i386 + cross = clean compile-error (x86-64 first). test_atomic_counter: 4 threads ×
  200k atomic-adds = 800000 with zero lost updates.
- `lib/rtl/palsync.pas`: TMutex = Drepper 3-state futex mutex (MutexInit / MutexLock /
  MutexUnlock / MutexTryLock). Uncontended path is pure userspace (cas, no syscall);
  blocks via PalFutexWait only under real contention. test_mutex: 4 threads × 100k
  NON-atomic increments under the lock = 400000 exactly (proves mutual exclusion).
- Wired into `make test-threads`. Single-thread self-host byte-identical; libc-free.

REMAINING in M2:
- TEvent (auto/manual reset) + TConditionVariable on futex.
- Once / lazy-init guard (atomic CAS on a done-flag, futex for the racing waiters).
- 64-bit atomics + atomic load/store fences if a use needs them (current ops are 32-bit).
- TCriticalSection alias (FPC EnterCriticalSection/LeaveCriticalSection names) —
  trivial wrapper, lands with M3 TThread/FPC-compat surface ([[feature-pascal-tthread]]).

## Update — TEvent landed (2026-06-30)
TEvent (manual/auto-reset) added to lib/rtl/palsync.pas on the futex: EventInit/
Set/Reset/Wait. Manual = level-triggered "go gun" (wakes all, lost-wakeup-safe
either order); auto = one-waiter hand-off (CAS-consumes the signal). test_event
(manual start gun, 4 waiters) in make test-threads. Still remaining: condition
variable, Once. TCriticalSection alias still pending (with M3).

## Update — TRTLCriticalSection (FPC API) + RunOnce landed (2026-06-30)
- TRTLCriticalSection = TMutex under the FPC System names: InitCriticalSection /
  EnterCriticalSection / LeaveCriticalSection / TryEnterCriticalSection /
  DoneCriticalSection — so existing threaded Pascal compiles unchanged.
- RunOnce(var ctl: TOnceControl; proc): pthread_once-style; the initialiser runs
  exactly once across all racers (CAS 0->1 winner runs it, publishes 2 + futex-wakes;
  losers block until 2).
- test_critsec_once: 8 threads x 50k EnterCriticalSection increments = 400000 AND
  the once-initialiser ran exactly 1 time. In make test-threads.
Sync surface now: TMutex, TEvent, TRTLCriticalSection, RunOnce. Still open:
condition variable (TConditionVariable), 64-bit atomics if needed.

## Update — M2 COMPLETE: TConditionVariable + 64-bit atomics (2026-07-03)

- **64-bit atomics**: __pxxatomic_xchg64 / cas64 / add64 intrinsics
  (ATOMIC_*64 IRIVal codes on the existing IR_ATOMIC — no new IR op).
  x86-64 REX.W lock-prefixed rmw (lock cmpxchg/xadd, xchg), old value in
  rax. Cross targets keep the clean unsupported-node error like the 32-bit
  ops. test_atomic64: single-thread old-value/full-width semantics beyond
  2^32 + 4 threads × 200k adds seeded just below 2^32 (a 32-bit op would
  wrap) — zero lost updates.
- **TConditionVariable**: TCondVar in palsync (futex sequence-counter
  shape): CondWait snapshots Seq, drops the mutex, FUTEX_WAITs on the
  snapshot (a racing signal bumps Seq → stale expected → no lost wakeup),
  re-locks before return; CondSignal/CondBroadcast atomically bump + wake
  one/all. Spurious wakeups by design — callers loop on the predicate.
  test_condvar: 4-consumer bounded queue (cap 8, 80k items) with both
  signal directions + periodic broadcast; exact count + sum; 20/20 repeat
  runs clean.
- Both in make test-threads. Self-host byte-identical.

M2 fully closed: TMutex, TEvent, TRTLCriticalSection, RunOnce,
TConditionVariable, 32+64-bit atomics.
