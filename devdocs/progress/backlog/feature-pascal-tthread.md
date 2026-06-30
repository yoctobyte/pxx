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

## Status — M3 first slice LANDED (2026-06-30)

DONE (x86-64, pure RTL — no compiler change):
- `lib/rtl/palthreadobj.pas`: `TThread` class. Subclass + override `Execute`;
  Create(CreateSuspended), Start, WaitFor, Finished, ThreadID. A file-level
  trampoline (ThreadObjLauncher) virtual-dispatches into Execute on the spawned
  thread and sets FFinished on return. Built entirely on M1/M2 PAL — libc-free.
- test_tthread: 4 TThread workers, each Execute does 100k mutex-guarded increments;
  created suspended, started together, joined = 400000. In `make test-threads`.

REMAINING in M3 (FPC-compat surface):
- Virtual destructor / auto-join on Free — blocked on pxx's TObject not having a
  virtual Destroy in the parent chain (`override` rejected). Either add a virtual
  Destroy to the base object model (Track A) or document explicit WaitFor (current).
- Synchronize / Queue (run a proc on the main thread) — needs a main-thread message
  queue pumped from the main loop; deferred.
- ReturnValue / OnTerminate / Suspend-Resume / priority; TThread.CurrentThread.
- Re-export TThread from `classes` for drop-in FPC `uses classes` compatibility
  (kept isolated in palthreadobj for now to not destabilise the shared unit).
