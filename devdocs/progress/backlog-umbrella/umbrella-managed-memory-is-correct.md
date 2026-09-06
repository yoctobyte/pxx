---
slug: umbrella-managed-memory-is-correct
title: "Managed memory is correct — heap, refcounts, leaks, managed fields"
track: A
prio: 75
type: umbrella
blocked-by: [bug-a-pxxalloc-does-not-check-the-mmap-return-so-oom-arrives-as-an-anonymous-segv, bug-a-managed-locals-leak-on-an-unwind-on-wasm32-and-xtensa, feature-a-reentrant-heap-lock-and-per-thread-arenas, bug-a-two-different-binaries-both-pass-the-self-host-fixedpoint-for-one-source-tree, bug-a-string-release-has-two-implementations-that-already-disagree, bug-a-a-shared-ansistring-handle-in-a-parallel-loop-is-11x-slower, bug-a-an-interface-as-cast-retains-on-every-execution-and-releases-once-per-scope, bug-a-a-generator-instance-is-not-freed-when-an-exception-escapes-the-for-in, bug-a-a-generator-body-raising-past-a-managed-temp-is-not-covered-by-the-unwind-landing-pad, bug-nilpy-a-generator-instance-leaks-its-locals-and-argument-cells, bug-nilpy-a-managed-local-in-an-unwound-frame-is-never-released, bug-nilpy-except-x-as-e-still-leaks-every-exception-the-bare-arm-fix-did-not-cover-it, bug-a-only-the-pascal-frontend-ever-asks-for-an-unwind-landing-pad, feature-pascal-management-operators-nested-and-array, feature-pascal-management-operators-copy-and-addref, feature-a-record-rtti-descriptors-for-initializearray-and-finalizearray]
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


## Attempted 2026-09-04 — ten managed-memory constructs, looped, slope measured

**This umbrella had SIX blockers and all six were `done/`.** Per this file's own
rule that is not "finished", it is "nobody has attempted the cell". So it was
attempted the way the rule says — by running the target rather than by triaging
the backlog.

Ten Pascal constructs that own managed memory, each looped 2000 and 8000 times
under `-dPXX_ALLOC_CENSUS`, with the SLOPE as the measurement (the census prints
at geometric thresholds, so a raw live count over N is wrong). String concat,
string function result, dynamic array, dynamic array of strings, class
create/free, variant assign, exception raise/catch, open array, record with
managed fields, `for c in s`. Then six more: interface local, interface by-value
parameter, class with managed fields destroyed, record management operators,
nested dynamic arrays, and a raise through a frame holding managed locals.

**Fifteen flat. One was not**, and it is now
`bug-a-an-interface-as-cast-retains-on-every-execution-and-releases-once-per-scope`
— fixed the same day, verified against the FPC oracle and on five cross targets.

### Two instrument failures worth more than the negative result

**A probe whose managed value is CONSTANT-FOLDED reports a flat zero while
measuring nothing.** `v := 'str' + Chr(65)` allocates nothing at all; the
program produced no census line whatsoever and the harness read that as a
tooling glitch. Every probe now derives its managed value from the loop counter,
and the harness asserts that a probe ALLOCATED proportionally to N before
believing its slope.

**And the fix for that was itself a guard that could not fail, twice.** First
`allocs > 0` — which `allocs=1` clears while measuring nothing. Then
`allocs >= N` — too strict, because the last census threshold is typically
~0.94 of the true total, so it rejected seven honest probes whose last line read
1871 at N=2000. **A precondition that fails on good input is as useless as one
that passes on bad**, and both errors were made while explicitly trying to write
a control. The bound is N/2.

The positive control is a shape measured to leak on the same day
(`bug-a-a-generator-instance-is-not-freed-when-an-exception-escapes-the-for-in`'s
residual, 0.999 blocks per escaping raise) and it is in every run above.

### What the negative result is and is not

It is: fifteen common constructs do not leak in a steady-state loop, on
x86-64, at the default `-O`. It is not a statement about cross targets,
`--threadsafe`, the NilPy or C frontends, or any construct not in the list —
generics and the `lib/pcl` containers are the obvious untouched neighbours.

## Attempted 2026-09-04 (frankb-78): the NilPy frontend, exception paths

The Pascal sweep above says "not a statement about the NilPy frontend". Running
the same instrument there found the gap that sweep could not:

**No Nil-Python function had ever been given an unwind landing pad.** The pad
is shared machinery and complete; `ProcCleanupFrameWanted := True` was written
in exactly one file. Every managed local live in an `.npy` frame an exception
unwound past leaked one heap block per raise — 1 for a string local, 2 for a
list, 3 for three strings, 0 with no managed local and 0 when the frame is not
unwound. Fixed; the guard is a census row, because the printed output is
byte-identical before and after (18509 live vs 4).
[[bug-nilpy-a-managed-local-in-an-unwound-frame-is-never-released]]

**This is the umbrella's own lesson repeating one level up.** The Pascal sweep
was fifteen honest constructs measured on a frontend that *asks* for the pad;
it was structurally unable to observe a frontend that does not. The same grep
says C, Rust and Zig still never ask — filed unmeasured and named as such,
[[bug-a-only-the-pascal-frontend-ever-asks-for-an-unwind-landing-pad]], because
the whole point of this one was that a slope, not a reading, settled it.

Still open and re-measured on the fixed binary, so it is not this:
`except X as e:` leaks 2.997 blocks per catch, identically whether the handler
uses `e` or not.
[[bug-nilpy-except-x-as-e-still-leaks-every-exception-the-bare-arm-fix-did-not-cover-it]]

## 2026-09-06 (frankS) — three management-operator blockers wired in

`class operator Initialize` / `Finalize` / `Copy` / `AddRef` on a record ARE
managed fields, and the three tickets that carry them were sitting at prio 30,
35 and unfiled with no edge to this umbrella — so `effective_prio` could not
reach them and they ranked below their own goal. **The membership was stated in
prose and absent from frontmatter, which is exactly the state the ranker cannot
see.** Two of the three had no frontmatter at all beyond `track` and `prio`: no
slug, no status, no summary.

Each is now backed by fpc-testsuite rows rather than by shape — six live
`tmoperator` rows measured at `88a0b3d93835`, splitting two / one / three across
them, with the failing line recorded per row.
