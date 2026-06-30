# Meta: multithreading — libc-free Pascal threads (umbrella / epic)

- **Type:** meta (epic / index) — Track A (+ B for the C-shim consumer)
- **Status:** backlog (standing index)
- **Opened:** 2026-06-30
- **Goal (user):** Pascal threads that "just work", no libc. Code safe; heap +
  stack safe **and** optimized; pthread emulated with syscalls.

## Invariant (all multithreading tickets)

**Self-host is single-threaded and stays that way.** Every threading feature is
**opt-in** (a `uses`/flag/directive), **off by default**, and MUST NOT change the
single-threaded self-build — which stays **byte-identical** (the gate). Because of
this, milestones can land in **any order**; nothing here is allowed to perturb the
default single-threaded path. **No libc** — Linux syscalls only.

## Architecture — one PAL, two consumers

A single **libc-free PAL thread layer** (Linux `clone(2)` + `futex(2)` + mmap'd
stacks) underlies BOTH:
- **native Pascal threads** (`TThread`, `spawn`/`parallel for`), and
- the **C `pthread` shim** (for SQLite etc.).

Don't build two thread layers — the C shim is a thin façade over the same PAL.

## Milestones (land in any order; safety gates *using* threads, not building them)

- **M0 — runtime honesty (safety prerequisite to RUN threads).**
  [[feature-threadsafe-heap-contract]] · [[feature-threadsafe-io-serialization]] ·
  [[audit-shared-global-reentrancy-thread-safety]] (atomic refcounts + COW races +
  BSS scratch globals).
- **M1 — PAL thread primitives (keystone, scaffolding-first).**
  [[feature-pal-thread-primitives]] — `clone`/`futex`/stack/TLS, libc-free.
- **M2 — sync primitives on the futex.** [[feature-sync-primitives-futex]] (real
  TCriticalSection/TMutex/TEvent/Once + atomics; replaces today's syncobjs stubs).
- **M3 — native Pascal surface.** [[feature-pascal-tthread]] (TThread class) +
  [[feature-parallel-processing]] (spawn / parallel-for sugar).
- **M4 — C pthread shim.** [[feature-syscall-pthread-shim]] over the same PAL.
- **M5 — optimize.** [[feature-threadsafe-heap-optimize]] (per-thread arenas /
  lock-free fast path; cross-target the threadsafe atomics, today x86-64-only).

## Current state (2026-06-30 survey)
`--threadsafe` = x86-64 `lock`-prefix atomics on heap alloc + ARC refcounts
(correct, unoptimized, x86-64-only). Threads today go through real
`libpthread.so.0` (test_multithreading.pas) — NOT libc-free. syncobjs
TCriticalSection = parse-compat stubs. `pthread` unit = declarations only. No
`clone`-based creation yet. So M1/M2 are the green-field keystone.
