---
slug: decide-a-how-should-the-nilpy-managed-finalize-re-enter-the-heap-lock
track: U
prio: 40
type: decide
status: decided
created: 2026-09-02
found-by: frankA
owner: ""
blocked-by: []
summary: "DECIDED 2026-09-06 BY THE OWNER: arm (a), THE REENTRANT LOCK -- his own 2026-08-21 unpark trigger ('a deadlock, or a new managed member kind whose release cannot be hoisted out of the lock') has fired. Closes THREE of the six open leaks under one lock, not one, and unblocks __del__. The hot-path objection was formed before the magazine landed and has never been measured; take that number, do not re-open on it. Measured 2026-09-02: unifying the managed-field walk so NilPy gets it too FIXES the 399524 kB -> 7844 kB leak and DEADLOCKS on one twelve-line program -- a class whose field is a class instance, one instance, one thread, exit 212. The recursion is PXXClassFinalizeManaged re-entering itself through kind 6; a list or dict field does NOT do it, and Pascal structurally cannot. Two ways out and neither is a default. (a) The reentrancy half of feature-a-reentrant-heap-lock-and-per-thread-arenas, which that ticket records as PARKED BY THE OWNER -- unparking it is his call, not a session's. (b) Defer the nested release: the kind-6 arm pushes onto a per-thread pending list and the codegen wrapper drains it just after EmitReleaseHeapLock, needing no change to the lock primitive but moving a finalizer to after the outer walk, an observable ordering change. Blocks bug-a-nilpy-under-threadsafe-still-leaks-every-class-field-and-it-cannot-ride-on-the-pascal-fix."
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

## 2026-09-06 — DECIDED BY THE OWNER: (a), THE REENTRANT LOCK

Asked directly, with both arms and their costs in front of him. He had already
said he leaned (a) against the ticket's recommendation of (b), and asked for
advice rather than for confirmation. The advice given was **(a)**, on four
grounds, and he took it: *"good. decided then."*

**1. THE UNPARK TRIGGER IS HIS OWN AND IT HAS FIRED.**
`feature-a-reentrant-heap-lock-and-per-thread-arenas` records, 2026-08-21:

> *"i'm good and if we ever encounter a real world project that has an issue, we
> will look at it again."*
>
> **Unpark trigger: a real-world project hitting it. A deadlock, or a new managed
> member kind whose release cannot be hoisted out of the lock. Not "it would be
> tidier".**

**A deadlock is one of the two named triggers.** Twelve lines, one instance, one
thread, exit 212. This is not an override of a parked decision; it is the
condition he specified, arriving.

**2. THE HOT-PATH COST OBJECTION WAS FORMED BEFORE THE THING THAT WEAKENS IT.**
The stated cost is *"every acquire grows an owner check, on the allocator's hot
path — the path the magazine work was measured against."* **The magazine work
then landed.** `GetMem`/`FreeMem` on x86-64 now have a lock-free per-thread
magazine fast path emitted at the call sites; the hot path largely does not take
the lock at all, so an owner check is paid on the SLOW path. **The objection has
never been measured, and it inherited a premise that has since moved.** It still
stands on i386/aarch64/arm32, which keep the global lock.

**3. (b)'s FAILURE MODE IS WORSE THAN THE LEAK IT FIXES.** The pending list needs
a bound, or a deep object graph becomes unbounded per-thread allocation *at the
moment the program is trying to free memory*. A leak degrades; an OOM during
teardown does not.

**4. THE STRUCTURAL ONE, WHICH WEIGHED HEAVIEST.**
`decide-interface-members-in-aggregates-lock-strategy` already took (b) — the
unlocked-pass discipline — and recorded the standing objection against it: *every
future release site must remember to run outside the lock, where a reentrant lock
would delete the hazard class.* **This is the second site that forgot.** Taking
(b) again is choosing to meet it a third time.

## What this changes beyond this ticket

**(a) closes three of the six open leaks under one lock, not one** — this row,
the dynamic-array element walk (`ManagedElemKindLocked` degrades kinds 4 and 6 to
0 for the same reentrancy reason), and the record COM-interface fields. The
ticket's recommendation of (b) was written when only one was in view.

It also unblocks
[[feature-n-nilpy-has-no-__del__-and-its-absence-is-load-bearing-in-an-open-fork]]:
under (a) a user finalizer runs in place and may allocate, so the CPython
ordering question (b) would have raised does not arise.

## The one measurement that still attaches

**The owner check's cost on the acquire path, min-of-N interleaved A/B,
POST-magazine.** Not as a gate — the decision is made — but because the number
this arm was argued against has never been taken, and the non-magazine targets
(i386, aarch64, arm32) are where it could still be real. Take it and record it;
do not re-open the fork on it without talking to the owner.
