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

## What is NOT known and should be measured first

**Can a NilPy program create a thread at all today?** If it cannot, every one of
these frees is single-threaded and the gate is buying nothing on this path — in
which case the fix is to let the NilPy route run the managed pass unconditionally
and the whole design problem above evaporates. If it can, none of that holds.
That measurement is cheap and nobody has made it; do it before designing
anything.

## Also still open, same lock, named in the parent

RECORD COM-interface fields (`PXXRecordReleaseIntf`) are the same
benign-by-assertion leak under the same lock, and were never measured either.
