# Native Pascal TThread class (M3)

- **Type:** feature (RTL / language surface) — Track A
- **Status:** done
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

## Update — Terminate/Terminated + ReturnValue (2026-06-30)
TThread now has FPC cooperative cancellation: Terminate sets a Terminated flag the
Execute body polls (`while not Self.Terminated do ...`); plus ReturnValue (Integer,
Execute sets, joiner reads after WaitFor). test_tthread_terminate in make
test-threads. NOTE: unqualified property access in a method is a pxx gap
([[bug-unqualified-property-in-method]]) so Execute must write `Self.Terminated` /
`Self.ReturnValue` for now — filed Track A. Still remaining: Synchronize/Queue,
virtual destructor/auto-join (needs virtual TObject.Destroy), OnTerminate,
CurrentThread, classes re-export.

## Update — Synchronize/Queue + auto-join destructor (2026-07-02, v152)

Pure-RTL slice in palthreadobj (compiler binary unchanged, hash identical):
- `Synchronize(m)` / `Queue(m)` with `m: TThreadMethod` (TMethod-shaped record,
  built by `m := @Self.SomeMethod`) + unit-level `CheckSynchronize` pump and
  `MainThreadID`. Mutex-guarded linked queue; Synchronize entries live on the
  caller's stack with a per-entry futex the main thread sets+wakes; Queue
  entries are heap-owned and freed by the pump. Called on the main thread both
  invoke directly (FPC parity). Console programs must pump CheckSynchronize —
  same contract as FPC.
- `destructor Destroy; virtual;` — auto-join: Terminate (cooperative) +
  WaitFor, so a bare `t.Free` on a running thread is safe. Descendants
  `override` + `inherited Destroy` (works: virtual dtor in own class + Free
  dispatch verified).
- test_tthread_sync in make test-threads (4 workers × 50 sync + 50 queue,
  main-tid asserted for every marshalled call; auto-join on a spinning
  thread); 20/20 repeat runs clean.
- Parser gaps found (worked around in test, not filed as blockers):
  `@Self.Method` directly as a call ARGUMENT (assignment-side only today) and
  indexed `arr[i].Free`.

Still remaining: FreeOnTerminate (self-free needs join-self guard),
OnTerminate, CurrentThread, Suspend/Resume, classes re-export.

## Update — M3 COMPLETE: FreeOnTerminate, OnTerminate, CurrentThread, Suspend/Resume (2026-07-03)

Pure-RTL slice in palthreadobj (no compiler change):
- **Heap handle refactor**: the kernel futex-writes TidWord at thread exit
  (CLONE_CHILD_CLEARTID), so FHandle moved inline→heap (FHandlePtr, alloc'd
  in Start) — otherwise FreeOnTerminate's self-free left a kernel
  write-after-free into the dead instance.
- **FreeOnTerminate**: launcher self-frees after Execute + OnTerminate;
  Destroy detects the self-call (tid match), skips the self-join, parks the
  heap handle on a reaper list; CheckSynchronize joins (frees the 1 MiB
  child stack) + releases parked handles.
- **OnTerminate**: parameterless TThreadMethod (not FPC's TNotifyEvent —
  Data already carries the receiver), fired after Execute, marshalled to
  the MAIN thread via Synchronize (main must pump, FPC contract).
- **CurrentThread**: unit-level function (pxx has no class-static
  properties) over a SyncLock-guarded registry (FNextThread chain,
  registered in Start / unregistered in Destroy); on the main thread
  returns a lazy placeholder instance (FPC TExternalThread analogue).
- **Suspend/Resume**: cooperative self-park on a futex gate (the async
  suspend FPC deprecated is unsafe by construction; other-thread Suspend =
  no-op). Resume releases the gate; on a never-started thread Resume acts
  as Start (legacy Create(True)+Resume).
- test_tthread_final in make test-threads (CurrentThread identity on worker
  + stable main placeholder, OnTerminate-on-main-tid, FreeOnTerminate with
  reaper drain, Suspend/Resume phases, late-start); 20/20 repeat runs clean.

Deliberately NOT done: classes re-export (kept isolated in palthreadobj to
not destabilise the shared unit — unchanged from the prior decision);
priority (no PAL surface for it).
