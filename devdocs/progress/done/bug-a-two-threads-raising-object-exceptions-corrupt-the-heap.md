# Two threads raising object exceptions corrupt the heap (x86-64, --threadsafe)

- **Type:** bug (Track A — `compiler/ir.inc` exception lowering,
  `compiler/ir_codegen.inc` heap-lock discipline)
- **prio:** 75
- **Status:** done
## Symptom
Two threads, each raising a freshly constructed exception object in a loop,
SIGSEGV. Nothing else is needed — no shared object, no shared class, no
re-raise.

```pascal
procedure Spin(var hits: Integer);
var i: Integer;
begin
  for i := 1 to N do
    try raise TFoo.Create; except on E: TFoo do hits := hits + 1; end;
end;
```

One thread runs it, then a second joins. Measured:

```
compiler at 620989250^   rc=0    hitsA=20000 hitsB=20000
compiler at HEAD         rc=139  (SIGSEGV)
```

## It is the FREE, and only when both threads do it
A four-cell matrix, N=20000, one procedure raising an object and one raising an
Integer:

```
main    child   result
Int     Int     clean
Obj     Int     clean
Int     Obj     clean
Obj     Obj     SIGSEGV
```

And it is not allocation on a cloned thread in general — the same two threads
doing plain `TFoo.Create` / `o.Free` in a loop, 20000 iterations each, are
clean. Only the exception path breaks.

Threshold: N=1 and N=100 clean, N=1000 crashes. Deterministic at N=20000
(3 of 3).

Not the heap magazine: `-dPXX_NO_HEAP_MAG` crashes identically.

## Root cause
`620989250` made handler exit free the caught object by emitting a call to the
runtime proc `PXXObjFree`, which does `PXXClassFinalize` + `PXXFree`.

**On x86-64 the heap lock is emitted by CODEGEN at `tkGetMem`/`tkFreeMem` IR
sites, not taken inside the runtime helpers.** So a free reached by CALLING an
RTL routine takes no lock at all, and `PXXFree` mutates the free list bare.
`ir_codegen.inc` states the invariant in those words — the only call site that
acquires the lock on a runtime routine's behalf is `HeapLockedCallProcIdx1`,
and it names `PXXClassFinalizeManaged` and nothing else.

The asymmetry is worth stating because it inverts the usual expectation: on
i386 and aarch64 the locking lives INSIDE the Pascal helpers
(`PXX_TS_SOFTLOCK`), so those targets would be safe. x86-64 is the fast one and
the broken one — and it is also the ONLY target that can create a thread at
all, so "x86-64 only" is not a narrowing here, it is everything.

`620989250` is not careless: it introduced the first codegen-emitted call to an
allocator-mutating RTL routine outside the `tk*Mem` sites, and nothing in the
IR marks that class of call.

## Why the obvious fix is not obviously right
Wrapping the `PXXObjFree` call in `EmitAcquireHeapLock` the way
`HeapLockedCallProcIdx1` wraps `PXXClassFinalizeManaged` is the shape that
fits, but `PXXObjFree` runs `PXXClassFinalize` first — a destructor chain, and
on the COM path a self-locking free. That is precisely the deadlock the
REVERTED `cb2ed843` hit, and the reason `PXXClassFinalize` and
`PXXClassFinalizeManaged` are two procs with opposite lock requirements today.
A user destructor that allocates would deadlock.

The shape that probably works, and is what the split above already established
as the pattern: keep the finalize half unlocked and emit the plain free as a
`-Ord(tkFreeMem)` call, which is a real spelling the lowering can produce
(`ir_codegen.inc` dispatches on it) and which gets the lock and the magazine
for free. That needs `PXXObjFree` split so the headered/plain decision happens
before the free rather than inside it.

Not attempted here rather than attempted and rushed: it is compiler-plus-RTL
surgery in an area with a reverted deadlock behind it, and the diagnosis is the
part that was missing.

## What it blocks
`decide-does-raise-of-an-existing-object-transfer-ownership` resolves to
"`raise` always transfers" (FPC measured, see that ticket), which means
`test_exception_threads_race` must stop re-raising pre-made objects and
allocate per raise instead. It cannot, until this is fixed: the rewritten
phase 3 hits exactly this crash. So
`regression-test-threads-test-exception-threads-race` stays red on this, not on
the ownership question.

## Positive control available
A compiler built with `StatusSlotTlsIndex` forced to -1 for the exception
family (process-wide status slots, the pre-fix world) fails the same program
with rc=217 `Unhandled exception` rather than rc=139. Two distinguishable
failure modes, so a fix for this bug cannot be mistaken for a fix of the
shadow-chain bug the test was originally written for.

## FIXED 2026-09-01 (frankC) — the proc split, as diagnosed

The fix is the one this ticket specified: keep the finalize half unlocked and
emit the plain free as `-Ord(tkFreeMem)`, which is a real spelling the lowering
already dispatches on and which gets the codegen lock wrap AND the heap
magazine for free.

`compiler/ir.inc`, the exception handler-exit lowering, Pascal population only:

```
  before                              after
  PXXClassFinalizeManaged (locked)    PXXClassFinalize          (unlocked)
  PXXObjFree                          PXXClassFinalizeManaged   (locked)
    -> PXXClassFinalize                 IR_CALL -Ord(tkFreeMem) (locked+magazine)
    -> PXXFree            <-- BARE
```

This is the `.Free` desugar's shape reproduced, not a new one. The two paths
destroy the same kind of object and had drifted into two mechanisms — the
second one being the one that stayed broken, which is
`normalise-dont-special-case.md` exactly. It also fixes a second, quieter
disagreement: the old order ran the managed half BEFORE `PXXObjFree`'s inner
finalize, i.e. reversed relative to the desugar.

**The NilPy arm is unchanged and still calls `PXXObjFree`**, deliberately: a
headered instance may still be referenced and only the refcount knows, so it
must route to `PXXObjRelease`. The corpus has NO NilPy try/except test, so that
arm is uncovered by the tier — I carried a 500-iteration `raise`/`except` probe
by hand and it answers 3500 correctly.

### Measured

| | before | after |
| --- | --- | --- |
| `test_threadsafe_exception_two_threads.pas` | SIGSEGV 3/3 | OK 3/3, later 5/5 |
| phase 1 (single thread, same lowering) | clean 20000/20000 | clean |
| managed-field census (the d402a25b2 row) | allocs=10975 frees=10972 live=3 | **identical** |

The census row is the guard against the reordering: `live=3` unchanged means no
leak, and a NEGATIVE live would have been the double free that the first attempt
at the sibling bug produced (live=-2740).

`tools/gate.sh quick` GREEN, FPC seed canary PASS. Self-host fixedpoint
converged, `d76644e0676b`.

### The regression this unblocks

`regression-test-threads-test-exception-threads-race` is still red and still
correctly so: per `decide-does-raise-of-an-existing-object-transfer-ownership`
that test must be rewritten to construct per raise, and it could not be until
this was fixed. It can be now. That rewrite is NOT done here — it is a test
change with its own reasoning about what phase 3 can still detect once every
raise takes the heap lock, and the test's header says that serialisation is
what it was avoiding.

## Log
- 2026-09-01 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 4d71c93f3.
