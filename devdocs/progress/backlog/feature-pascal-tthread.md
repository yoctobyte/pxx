# Native Pascal TThread class (M3)

- **Type:** feature (RTL / language surface) — Track A
- **Status:** backlog
- **Opened:** 2026-06-30
- **Umbrella:** [[meta-multithreading]]. Needs M1 + M2. Sibling of the
  spawn/parallel-for sugar [[feature-parallel-processing]].

## Invariant

Threading is **opt-in**, off by default; the single-threaded self-build stays
**byte-identical**. **No libc** — built on [[feature-pal-thread-primitives]]
(syscalls only). Milestones land in any order under [[meta-multithreading]].

## Scope

The FPC-compatible `TThread` surface so Pascal threads "just work", on the PAL
(no libc):
- `TThread` abstract class: `Create(CreateSuspended)`, `Execute` (override),
  `Start`, `WaitFor`, `Terminate`/`Terminated`, `ReturnValue`,
  `FreeOnTerminate`, `Synchronize`/`Queue` (main-thread marshalling — later).
- Maps to PalThreadCreate/Join + an M2 event for suspend/resume + WaitFor.
- Honest interaction with managed strings/dynarrays passed across threads (ARC
  must be atomic — M0).

## Acceptance
- A `TThread` descendant runs, mutates shared state under an M2 lock, `WaitFor`
  returns the result; libc-free; matches FPC semantics for the covered subset.
  Self-build byte-identical. Replaces the libc-pthread test_multithreading.pas with
  a native one in the gate (opt-in target).
