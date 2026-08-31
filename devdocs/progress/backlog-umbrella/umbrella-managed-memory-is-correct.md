---
slug: umbrella-managed-memory-is-correct
title: "Managed memory is correct — heap, refcounts, leaks, managed fields"
track: A
prio: 75
type: umbrella
blocked-by: [bug-a-pxxalloc-does-not-check-the-mmap-return-so-oom-arrives-as-an-anonymous-segv, bug-a-managed-locals-leak-on-an-unwind-on-wasm32-and-xtensa, feature-a-reentrant-heap-lock-and-per-thread-arenas, bug-a-two-different-binaries-both-pass-the-self-host-fixedpoint-for-one-source-tree]
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
