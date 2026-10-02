---
track: N
prio: 35
type: bug
status: done
summary: 'FIXED 2026-10-02 (frankuser). A stackless generator now releases what it holds however it ends. Exhaustion and a plain return were fixed 2026-09-24. Early teardown (a break out of a for-in, a cursor dropped after next(), a generator never started, an inner generator inside an outer one) now CLOSES the instance: the state is set to SL_STATE_CLOSE and the step runs once more, restores the locals and jumps to the release tail. A return inside a try saves the locals and marks the state CLOSE before it exits. String, variant and nested-generator locals are released too. Close does not run a finally block (yield inside try is refused anyway).'
---

# A Nil Python generator instance leaks its locals and its argument cells

A deliberate trade made in [[feature-nilpy-yield-outside-a-for-loop]], recorded
here rather than left to be rediscovered as a mystery.

## What leaks, and why it was traded

**The locals.** A stackless generator's step function returns at every `yield`
and is re-entered at the next one, so its locals are NOT going out of scope —
they are the generator's live state, checkpointed into the heap instance. The
epilogue used to release them anyway, which freed the objects the instance still
pointed at; the symptom was silent and bad (a generator walking `for t in xs`
got a dangling list on its second step and the loop simply ENDED, one element
in). The references are therefore dropped when the instance is freed — which is
to say, not at all.

> **STALE, corrected 2026-09-04 (frankb-78).** This paragraph used to end
> *"`EmitManagedLocalCleanup` now exits early for a stackless routine"*. That
> blanket exit was replaced in `7946aa28f` by a per-symbol predicate,
> `StacklessPersistentSlotSym`, because the blanket form also skipped the step
> function's ORDINARY temps — which have no persistent slot, die inside one
> statement, and were leaking on both the normal and the unwind path. So a
> stackless routine's cleanup runs today and skips exactly the symbols that own
> a persistent slot. The conclusion above is unchanged and re-measured below;
> only the mechanism sentence was wrong.

**The argument cells.** A Nil Python variant parameter is by-ref, so the
instance slot holds an address that must outlive the loop. The for-in desugar
allocates a 16-byte `pycell_new` per variant argument and never frees it
(`GenMakeVariantArgCell`, parser.inc).

Both are **one-off per generator instance** — not per yield, not per step — so a
loop that runs a million times leaks nothing extra. A pipeline that creates a
million generators leaks a million small blocks.

## The shape of the fix

`SlFree` already runs at the end of the for-in desugar and knows the instance.
What it does not know is which slots hold managed values. Give it that — a
per-proc map of which persistent slots are variant / class / string — and the
release becomes a loop at instance teardown, which is also where a proper
generator OBJECT (see [[feature-nilpy-a-generator-as-a-first-class-value]])
would want it. Doing both at once is probably cheaper than doing either.

Note the ordering constraint that made this a trade in the first place: the
frame copy and the instance copy of a value are bitwise duplicates, and exactly
one of them is live at a time. Any release has to be at teardown, not at step
exit, or it re-creates the dangling-pointer bug this replaced.

## Narrowed 2026-08-19 — the instance BLOCK is now freed; the slot VALUES are not

`feature-nilpy-a-generator-as-a-first-class-value` added a cursor
(`PYITER_SLGEN`) that owns its generator instance and frees it at finalization,
and the `for` desugar already freed its own. So the *block* is reclaimed on both
paths and what remains is narrower than this ticket first described: the managed
values sitting in the persistent slots are dropped without being released, and
so is each variant argument's `pycell_new` cell.

Measured over 20 000 generators: **2.5 MB** peak through the `for` desugar,
**6.5 MB** as values. Flat rather than growing without bound, which is why this
stays a p40 and not a correctness item.

The fix is unchanged and is stated above: teardown needs a per-proc map of which
persistent slots hold managed values. Both teardown points now exist and are the
right place for it — `SlFree` in the desugar, and the `TPyIter` arm of
`PyObjFinalize` for a cursor. The ordering constraint still stands: release at
TEARDOWN, never at step exit, or it re-creates the dangling-pointer bug that
made a generator's second step read a freed list.


## Re-measured 2026-09-04 by frankb-78, and the two halves separate cleanly

At `7e271ff7d`, `-dPXX_ALLOC_CENSUS`, slope between N=2000 and N=8000 generators
(the census prints at geometric thresholds, so a raw live count over N is wrong).
Each row is one generator created and driven to exhaustion per iteration.

| generator | leaked blocks per instance |
| --- | --- |
| no arguments, no managed locals | **0** — flat, live=1 |
| one `int` argument, no managed locals | **1.0** (live 1804 @2000) |
| a class local, no arguments | **1.0** (live 1804 @2000) |
| both | **2.0** (live 3854 @2000, 15843 @8000) |

Row one is the control that matters: **the instance block itself is freed, and
so is every yielded value.** The desugar's `SlFree` works, and after
`7e271ff7d` it works on the unwind and early-exit paths too. What is left is
exactly the two things this ticket named, one block each, and they are
independent — either alone reproduces at 1.0.

The size classes back this up. The minimal generator allocates two classes
(32-byte and 80-byte) and frees both. Adding an int argument adds a **16**-byte
class — `pycell_new` — and one leak. Adding a class local adds a **48**-byte
class and one leak.

**The equivalent non-generator control is flat**: the same class built and
dropped inside an ordinary function is `allocs=3799 frees=3798 live=1` over the
same 2000 iterations. So neither leak is about the class or the argument; both
are about the generator instance's teardown.

## What blocks the fix, stated so the next session does not rediscover it

The release has to happen at instance teardown, and there are two teardown
points (`SlFree` in the for-in desugar, and the `TPyIter` arm of
`PyObjFinalize` for a cursor). Neither knows which persistent slots hold managed
values — that is per-proc compile-time knowledge, and `SlFree` is ordinary RTL
Pascal that receives only a pointer.

Three shapes were considered:

1. **A per-proc descriptor table, address stored in the instance header** (the
   header has free words at offsets 8, 32 and 40), with a new `SlRelease(g)` in
   the RTL walking it. Covers both teardown points. Needs a static table emitted
   per generator proc and a kind dispatch in the RTL.
2. **A generated finalizer procedure per generator proc, its address in the
   header.** Rejected: PXX cannot call through a stored proc pointer with
   arguments — the for-in desugar's own comment says so, which is why it calls
   the step function directly instead of through a pointer.
3. **Emit the releases as AST at the for-in site**, before `callFree`, reusing
   `GenMakeVariantAt(selfSym, off)` so an ordinary managed assignment does the
   release. Simplest, needs no RTL change — but it covers only the for-in path
   and leaves the cursor path (`feature-nilpy-a-generator-as-a-first-class-value`)
   leaking, and it duplicates the release at every for-in site.

(1) is the one that covers both points. Recording the per-slot kinds is the
shared prerequisite for all three: the slot allocator in `pasparser_stmt.inc`
already walks the symbols and assigns `SymGenSlot[i]`, so the kind map wants to
be built there, beside `ProcGenInstSize[gpi]`.

## Re-measured and half fixed (2026-09-24, frankb-12)

At HEAD before the fix, `-dPXX_ALLOC_CENSUS`, ~7800 generators each driven to
exhaustion by a for-in: no arguments/no managed locals live=1; an `int`
argument live=1 (**the argument-cell leak is gone**, closed by events);
a class local live=7815; both live=7815. So one leak remained: the class
local, one block per instance.

Mechanism, measured rather than assumed: a stackless step function
checkpoints locals into the instance at each yield (SLSaveLocals) and restores
them at entry, so on the EXHAUSTING return the frame value is the live one.
The shared epilogue skips it (StacklessPersistentSlotSym), which is right for
every yield-return and wrong for that one. A NilPy class-typed store does not
release in the IR assignment (NilPy's own store emits retain/release), so the
release is an explicit PXXObjRelease, the epilogue's SXR_OBJ action.

Fix, all AST in BuildStacklessStep so every backend gets it:
1. SLReleaseLocalsAtDone before setDone: PXXObjRelease + nil for each slotted
   class-typed LOCAL whose scope-exit action is SXR_OBJ;
2. the CURRENT variant region is cleared through the managed variant store,
   which dropped the last yielded object (a generator yielding its own local
   leaked one per instance even with (1));
3. SLRewriteReturns routes a plain `return` to the same tail (not inside a
   try block).

Per shape, 3000 generators each: exhausted with a reassigned local live=3;
yields its own object live=2; `return` part-way live=1; `break` live=2706
(unchanged: early teardown). Fixture
`test/test_nilpy_a_generator_releases_its_class_locals_when_exhausted.npy`
checks values against CPython plain and under -dPXX_HEAP_DEBUG (no
use-after-free), plus an assert_no_leak.sh row with bound 200: HEAD live=17,
pin v421 (4e32f1dde0ec) live=8349, fails the bound.

## Closed (2026-10-02, frankuser)

Early teardown, the half that was left. Measured on pin v452 with
`test/test_nilpy_a_generator_closed_early_or_exhausted_does_not_leak.npy`:
5000 passes leave live=187479 on the pin (about 37 blocks per pass) and
live=92 with the fix (bound 300). The `keep` control leaves 22564 and trips
the bound.

The mechanism is close, not a per-proc descriptor table. The step function
already knows its own slots, so the teardown does not have to:

1. `SL_STATE_CLOSE = -1` (defs.inc). `BuildStacklessStep` checks it right
   after `SLRestoreLocals` and jumps to the fall-off tail, so the release is
   the same code the exhaustion path runs, with the body skipped.
2. `GenSlCloseAndFree` (pasparser_stmt.inc) replaces the for-in desugar's bare
   `SlFree`: if DONE is 0, set STATE to CLOSE and call the step once, then
   `SlFree`, then nil the instance local.
3. The `TPyIter` finalizer (pylib.pas) does the same for a cursor: DONE 0 →
   STATE := -1 → `FGenStep(FGenInst)` before `FreeMem`.
4. `SLReleaseLocalsAtDone` now also releases variant locals (`PXXVarClear`)
   and string locals (`PXXStrDecRef`), and closes an inner for-in's generator
   instance (a `$slgen.<gpi>.<seq>` local). That last one is how an outer
   generator closed early closes the inner one it was iterating.
5. A `return` inside a try block cannot be routed to the tail (a goto out of a
   protected region), so `SLRewriteReturnsInTry` makes it save the locals and
   set STATE to CLOSE before it exits. Without that the slots held the values
   from the last yield and the close released stale copies: one block per
   generator.
6. `for x in Cls(...)` where `__iter__` is a generator: `pyiter_of_userobj`
   keeps the object alive in the cursor (FObj), and `pyiter_of_userobj_owned`
   drops the call's own reference, so a fresh iterable is freed with its cursor.

Under -dPXX_HEAP_DEBUG the fixture's output is identical to CPython's.

Not done: close does not run a `finally` (Python's GeneratorExit). A `yield`
inside `try` is refused by this lowering ("yield only allowed at top level or
inside for/while/if/case"), so there is no suspended try to unwind.
