# Sync primitives on futex — TCriticalSection/TMutex/TEvent/Once + atomics (M2)

- **Type:** feature (RTL) — Track A
- **Status:** backlog
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
