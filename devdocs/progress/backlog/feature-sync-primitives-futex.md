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
