---
slug: umbrella-managed-memory-is-correct
title: "Managed memory is correct — heap, refcounts, leaks, managed fields"
track: A
prio: 75
type: umbrella
blocked-by: [bug-a-pxxalloc-does-not-check-the-mmap-return-so-oom-arrives-as-an-anonymous-segv, bug-a-managed-locals-leak-on-an-unwind-on-wasm32-and-xtensa, feature-a-reentrant-heap-lock-and-per-thread-arenas, bug-a-two-different-binaries-both-pass-the-self-host-fixedpoint-for-one-source-tree, bug-a-string-release-has-two-implementations-that-already-disagree, bug-a-a-shared-ansistring-handle-in-a-parallel-loop-is-11x-slower]
created: 2026-08-31
summary: "GOAL, not a unit of work. The owner named memory management as ranking above float-bit and parity work. This is the axis a real program hits hardest and where a wrong answer is silent: a leak, a double free, a refcount that disagrees with itself. Correctness is the case here -- the perf profile is deliberately NOT the argument."
---

# Managed memory is correct

Named by the owner as ranking above float-digit and parity work, and it is the
axis a large real program (see `umbrella-compile-and-run-dosbox`) hits hardest.

## Correctness first, and the profile is NOT the argument

The measured -O2 profile is release thunk 7.72%, PXXAlloc 4.07%, str-slot assign
2.93%, PXXFree 2.48% — **18.2% total** (frankB, sha f92c42a69850). That is a
performance fact and it is deliberately not this umbrella's case. What ranks
here is that memory bugs are **silent and non-local**: a leak, a double free, or
two refcount implementations that disagree produce a plausible wrong value far
from the cause, which is the expensive shape.

An earlier ~47% figure for this area was measured on a `-O0` debug binary and
should not be quoted; the correction is in `LOGBOOK.md`.

Full goal: `devdocs/dev/the-goal-cross-cross.md`.


## Delivered against this goal so far

Wired in retrospectively, because work that closed before the umbrella existed
otherwise makes the goal look unattempted. Resolved children do not rank, so
this changes no priority — it makes the coverage legible.

- **`bug-a-string-release-has-two-implementations-that-already-disagree`** —
  exactly the shape this umbrella names. x86-64 hand-emitted its own retain and
  release and skipped the `MSTR_STATIC_RC` guard every other backend gets, then
  carried a compensating `inc` to cancel the unguarded `dec`. Two
  implementations of one rule, disagreeing, with a second mechanism hiding the
  first.
- **`bug-a-a-shared-ansistring-handle-in-a-parallel-loop-is-11x-slower`** —
  filed as perf and closed as both. Under `--threadsafe` a retain took a global
  spinlock to perform an increment; making refcount ops atomic and lock-free is
  a **correctness** change (the plain `inc` sites had to become `lock inc` or
  they would race the unlocked ones, and a lost increment frees a live block)
  that happens to be 5.5x faster.

Two things the second one turned up that belong to this goal rather than to that
ticket, and neither is filed because neither is a defect:

- **The heap spinlock never protected the refcount READERS.** `PXXStrUnique`'s
  COW decision is a plain unlocked load (`builtinheap.pas:3371`), and
  `HeapLockedCallProcIdx1` names `PXXClassFinalizeManaged` and nothing else. Any
  future reasoning that treats that lock as serialising rc against COW is wrong,
  and was wrong before the lock-free change too.
- **The residual is not a locking problem.** A shared handle in a parallel loop
  is still ~2.3x slower than serial, and that is twelve cores bouncing one cache
  line holding one refcount word. Only a scheme that stops writing the shared
  word — biased or deferred refcounting — removes it. Worth an umbrella child if
  anyone wants that; it is not a bug.
