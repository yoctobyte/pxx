---
slug: decide-a-how-should-the-nilpy-managed-finalize-re-enter-the-heap-lock
track: U
prio: 40
type: decide
status: backlog
created: 2026-09-02
found-by: frankA
owner: ""
blocked-by: []
summary: "Measured 2026-09-02: unifying the managed-field walk so NilPy gets it too FIXES the 399524 kB -> 7844 kB leak and DEADLOCKS on one twelve-line program -- a class whose field is a class instance, one instance, one thread, exit 212. The recursion is PXXClassFinalizeManaged re-entering itself through kind 6; a list or dict field does NOT do it, and Pascal structurally cannot. Two ways out and neither is a default. (a) The reentrancy half of feature-a-reentrant-heap-lock-and-per-thread-arenas, which that ticket records as PARKED BY THE OWNER -- unparking it is his call, not a session's. (b) Defer the nested release: the kind-6 arm pushes onto a per-thread pending list and the codegen wrapper drains it just after EmitReleaseHeapLock, needing no change to the lock primitive but moving a finalizer to after the outer walk, an observable ordering change. Blocks bug-a-nilpy-under-threadsafe-still-leaks-every-class-field-and-it-cannot-ride-on-the-pascal-fix."
---

# How should the NilPy managed finalize re-enter the heap lock?

Track U. The measurement, the two arms and the numbers are on
[[bug-a-nilpy-under-threadsafe-still-leaks-every-class-field-and-it-cannot-ride-on-the-pascal-fix]],
section *"2026-09-02 (frankA) — the experiment RAN"*. This ticket is only the
fork.

## The fork

The unification is built and measured. It is right about everything except one
program, and that program is not exotic:

```python
class Inner:
    def __init__(self, s):
        self.s = s

class Outer:
    def __init__(self):
        self.f = Inner("hello")

o = Outer()
o = 0
```

`PXXClassFinalizeManaged` runs under the codegen heap lock, reaches kind 6,
releases the `Inner`, and `PyObjFinalize -> PXXClassFinalize` calls
`PXXClassFinalizeManaged` again — the wrapper acquires a non-reentrant spinlock
the same thread already holds. One instance, one thread, no contention.

## Option (a) — make the lock reentrant

The obvious fix, and it is exactly the half of
[[feature-a-reentrant-heap-lock-and-per-thread-arenas]] that ticket closed
WITHOUT doing: *"the reentrancy half stays parked by the owner and was never
touched."* That parking is why this is a decide and not a task. It is also the
only arm that fixes the sibling leaks under the same lock without further
thought — the dynamic-array element walk
([[bug-a-threadsafe-builds-leak-every-variant-and-interface-element-of-a-dynamic-array]],
where `ManagedElemKindLocked` degrades kinds 4 and 6 to 0 for the same reason)
and the record COM-interface fields named at the bottom of the bug ticket.

**Cost:** every acquire grows an owner check, on the allocator's hot path — the
path the magazine work was measured against. A depth counter local to the one
wrapper is NOT a substitute: the nested `PXXClassFinalize` runs its kind-4 pass,
whose `FreeMem` takes the lock at a DIFFERENT codegen site, so a wrapper-local
counter still deadlocks there.

## Option (b) — defer the nested release

The kind-6 arm of `PXXRecordRelease` pushes the object pointer onto a per-thread
pending list instead of calling `PXXObjRelease`. The codegen wrapper drains the
list immediately after `EmitReleaseHeapLock`, which is the one site that already
knows the lock is being dropped and is where the acquire is emitted today.

**Cost:** a finalizer now runs after the outer walk instead of during it. For
container teardown that is invisible; for anything user-visible it is an
observable ordering change, and NilPy is upward-compatible with CPython, where
the ordering is defined. It also needs a bound on the list, or a deep object
graph turns into an unbounded per-thread allocation at exactly the moment the
program is trying to free memory.

**It touches no lock primitive**, which is the part the owner parked, and that
is the whole reason it is worth putting beside (a) rather than assuming (a).

## Recommendation

**(b)**, scoped to the kind-6 arm only, unless the owner wants to unpark
reentrancy anyway for the two sibling leaks. (a) is the better end state and
strictly more expensive to get wrong; (b) is available to a session today. The
ordering objection against (b) is real but narrow, and narrower than it reads:
the only NilPy value whose release re-enters is a user class instance, and
**NilPy has no `__del__` at all** — `grep -rn __del__ compiler/ lib/ test/` is
empty, 2026-09-02. So there is no user-visible finalizer today whose ordering
(b) could change, and its cost is a cost against a feature nobody has built. If
`__del__` is ever added it lands on top of whichever arm is chosen here, which
is the argument for (a) rather than against (b).
