---
track: A
prio: 40
type: bug
blocked-by: []
summary: "NilPy under --threadsafe on x86-64 leaks every managed field of every reclaimed instance: 1044 kB -> 399420 kB on 200k constructions, same shape and same size as the Pascal leak fixed 2026-08-31. It did NOT ride along on that fix, and cannot: the Pascal fix works by emitting the heap-lock acquire at a CALL SITE, and NilPy has no call site -- the finalize is reached from PXXObjRelease at rc=0, from Pascal, from a dozen places. Needs a lock-discipline design, not a repeat of the same patch."
status: backlog
owner: frankS
---

# NilPy still leaks class fields under --threadsafe

- **Track A** (heap lock discipline). Measured 2026-08-31 by frankS
  immediately after fixing the Pascal half
  (`bug-a-threadsafe-on-x86-64-leaks-every-managed-class-field-and-it-is-not-benign`).
- **Filed rather than fixed because it is the same SYMPTOM through a different
  MECHANISM**, and the tempting move is to assume otherwise.

## The number

```python
class Holder:
    def __init__(self, s):
        self.s = s
# 200000 x Holder("y"*2000 + str(i))
```

| build | max RSS |
| --- | --- |
| `pascal26 npyleak.npy` | **1044 kB** |
| `pascal26 --threadsafe npyleak.npy` | **399420 kB** |

Same printed answer, 380x the memory. Compare the Pascal probe in the parent
ticket: 392 kB -> 398336 kB. Same shape, same size, and it survived the fix.

## Why it did not ride along

The Pascal fix works because a Pascal class's finalize has exactly **one**
reachable call site — the `Free` desugar in `ir.inc` — so the acquire could be
emitted THERE, around a call to the new `PXXClassFinalizeManaged`, and the
callee needs no lock of its own.

NilPy has no such site. `ir.inc` deliberately does **not** emit
`PXXClassFinalize` for a NilPy compilation (`if not isNilPy`, and the comment
above it records why: emitting it there finalized a headered instance twice).
The finalize instead runs from `PXXObjRelease` when a refcount reaches zero, via
`PXXObjFinalizeHook` -> `PyObjFinalize` -> `PXXClassFinalize`, whose managed half
is still behind `{$ifndef PXX_TS_HARDLOCK}`. `PXXObjRelease` is reached from the
object retain/release blobs (`EmitObjBlobBody`, which takes **no** lock), from
`PXXRecordRelease`'s kind-6 arm, from `PXXVarClear`, and from Pascal inside the
runtime. There is no single place to put an acquire.

## The two things that make it a design problem, not a patch

1. **The release blobs take no lock at all today.** `EmitObjBlobBody`
   (`ir_codegen.inc`) is a bare register-save wrapper around the Pascal proc.
   Wrapping *it* is the obvious move and is not obviously safe: the callee runs
   a user finalizer (container teardown, and in principle any NilPy-level
   `__del__`-shaped work), which is the same reason `PXXClassFinalize`'s kind-4
   pass must stay OUTSIDE the lock.
2. **The lock is not reentrant.** Anything reached under it that performs a
   string concat, a literal load or a `SetLength` goes through a blob that
   acquires again, and the program HANGS rather than crashing. The Pascal fix is
   safe only because its subtree is provably runtime-only;
   `test_threadsafe_class_finalize_kinds.pas` exists to keep that true. A NilPy
   finalizer has no such property.

## What is NOT known and should be measured first — ANSWERED 2026-09-02 (frankA)

**Can a NilPy program create a thread at all today?** *(the original question, kept
because the answer only means something against it:)* If it cannot, every one of
these frees is single-threaded and the gate is buying nothing on this path — in
which case the fix is to let the NilPy route run the managed pass unconditionally
and the whole design problem above evaporates. If it can, none of that holds.

**It can. The design problem does not evaporate.** `pyparser.inc` has a
`__pxxclone(flags, childStack, entry, arg, ctidptr)` builtin that refuses to
compile without `--threadsafe`, and a NilPy program using it starts a real
thread that runs real NilPy code: constructed, run, and now wired as
`test/test_nilpy_thread_clone.npy` — mmap a stack, clone, and the child sets a
global the parent spins on. 5 runs of 5, `child ran = 7`.

**Nobody had ever constructed one, and the natural spelling was broken**, which
is presumably why this stayed unmeasured: no `.npy` in the tree used
`__pxxclone`. Passing the entry point as a bare def name — the only spelling
NilPy has, since it has no `@` — got the BOXED callable every other value
position gets, and the box may even be a synthesized return-side wrapper with a
different ABI. So the child jumped into a value handle: on the pin, this exact
source is rc=139 three runs of three, with `tid nonzero = True` already printed.
Fixed in the same push (a bare def name at that one argument is read as an
address, as Pascal reads `@ThreadEntry` at the same position). The measurement
above is against the FIXED compiler; against the pin the answer is "it creates
the thread and the thread dies instantly", which is a yes to the question this
section asks and a no to any use of it.

So the frees on this path can genuinely race, `PXX_TS_HARDLOCK` is not gating
nothing, and the two obstacles below stand as written.

## Also still open, same lock, named in the parent

RECORD COM-interface fields (`PXXRecordReleaseIntf`) are the same
benign-by-assertion leak under the same lock, and were never measured either.

## 2026-09-02 (frankA) — the design, the one thing that blocks it, and why the experiment is now cheap

Leak reproduced at HEAD, same program, so the numbers below are against a live
defect and not a historical one: **1024 kB plain vs 399524 kB `--threadsafe`**,
390x, against the filed 1044 / 399420.

### "There is no single place to put an acquire" is not the constraint

The ticket's second obstacle rests on it, and the mechanism does not work the
way it assumes. `HeapLockedCallProcIdx1` keys on the **CALLEE**, not on a call
site: `ir_codegen.inc`'s IR_CALL arm tests `if procIdx + 1 =
HeapLockedCallProcIdx1` and wraps the call in `EmitAcquireHeapLock` /
`EmitReleaseHeapLock`, evaluating the argument outside the lock. So **every**
IR_CALL to `PXXClassFinalizeManaged` gets the lock, wherever it is written —
including one written in Pascal inside the runtime, such as the line at
`builtinheap.pas:4245` that `{$ifndef PXX_TS_HARDLOCK}` currently compiles out.

A NilPy compilation does not need a place to put an acquire. It needs that
`{$ifndef}` removed and the global set.

### Two things that then have to be settled, both concrete

1. **The global is only ever set by Pascal-only lowerings.** `ir.inc:11946`
   (the `Free` desugar) and `ir.inc:14187` (the caught-exception owner free) are
   the only writers, and a NilPy compilation lowers neither, so
   `HeapLockedCallProcIdx1` stays 0 and the call would be emitted UNLOCKED —
   which is a data race rather than a leak, i.e. a different bug, not a fix. It
   wants one assignment per compilation as soon as the proc row exists, with the
   two existing sites delegating to it rather than a third copy
   (`normalise-dont-special-case`).

2. **Removing the gate double-releases on the Pascal path**, because the `Free`
   desugar then emits the managed sweep a second time. The unification — drop
   the second emitted call, let `PXXClassFinalize` make the only one, and let
   the callee-keyed wrapper supply the lock — deletes a path instead of adding
   one, and is the shape to aim at.

### And the reason it is not free: the recursion is NilPy-specific

```
PXXClassFinalizeManaged            <- lock acquired here by the wrapper
  PXXRecordRelease
    kind 6 (a NilPy-object field)
      PXXObjRelease  -> rc = 0
        PXXObjFinalizeHook -> PyObjFinalize
          PXXClassFinalize
            PXXClassFinalizeManaged   <- the wrapper acquires AGAIN
```

The second acquire waits on a lock the first still holds, on the same thread.
This is obstacle 2 of this ticket, and it is now a specific chain rather than a
worry — **and it is why the Pascal path this design came from cannot see it**: a
Pascal class field holding another class instance is not ARC-managed, so kind 6
never appears there. Unification looks free from the Pascal side precisely
because the Pascal side cannot reach the case that breaks it.

### What changed since this was filed, and it changes the cost of finding out

*"the program HANGS rather than crashing"* was the expensive part — a hang is
indistinguishable from slow, so every experiment cost a timeout and returned
nothing. **`187a372a6` made that hang a named diagnosis**: the contended heap
lock now writes `Runtime error 212: the heap lock was never released` and
exits 212, measured 1.9s from the collision, 6 runs of 6.

So the experiment this ticket has been waiting for is now one build and one run:
remove the `{$ifndef PXX_TS_HARDLOCK}` at `builtinheap.pas:4245`, drop the
`Free` desugar's second emitted call, set `HeapLockedCallProcIdx1` once per
compilation, and run a NilPy program with a class whose field is another class
instance. Either the leak goes to zero and nothing deadlocks — in which case
the recursion above is not reachable for the shapes that matter and wants a test
proving so — or it exits 212 in two seconds naming the exact chain, which makes
the reentrant heap lock (`feature-a-reentrant-heap-lock-and-per-thread-arenas`,
and option 2 of
[[bug-a-the-threadsafe-allocator-is-not-async-signal-safe]]) the blocker, wired
as a hard `blocked-by`. **Not run here**: it changes the shared Pascal path and
belongs in a session that can carry the full-tier verification that implies.
