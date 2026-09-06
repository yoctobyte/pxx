---
slug: feature-a-make-the-heap-lock-reentrant
title: "Make the codegen heap lock reentrant — the half of the arena ticket the owner parked, now unparked by his own trigger"
track: A
type: feature
prio: 60
status: backlog
owner: ""
created: 2026-09-06
found-by: owner (decision), vehicle filed by frankuser
blocked-by: []
summary: "DECIDED 2026-09-06 (decide-a-how-should-the-nilpy-managed-finalize-re-enter-the-heap-lock, arm (a)). The reentrancy half of feature-a-reentrant-heap-lock-and-per-thread-arenas -- parked by the owner 2026-08-21 with an explicit unpark trigger, 'a deadlock, or a new managed member kind whose release cannot be hoisted out of the lock' -- is unparked because a deadlock arrived: PXXClassFinalizeManaged re-enters itself through kind 6 via PyObjFinalize on a twelve-line NilPy program, one instance, one thread, exit 212. THIS IS THE VEHICLE TICKET: it closes THREE open leaks under one lock and unblocks __del__. A DEPTH COUNTER LOCAL TO THE WRAPPER IS NOT A SUBSTITUTE and this is measured -- the nested PXXClassFinalize runs its kind-4 pass whose FreeMem takes the lock at a DIFFERENT codegen site, so a wrapper-local counter still deadlocks there. The cost objection on record ('every acquire grows an owner check, on the allocator's hot path') was formed BEFORE the magazine landed and has never been measured: GetMem/FreeMem on x86-64 now have a lock-free per-thread fast path emitted at the call sites, so the check is paid on the SLOW path. It may still be real on i386/aarch64/arm32, which keep the global lock. Take that number; do not re-open the fork on it."
---

# Make the heap lock reentrant

The decision is made — see
[[decide-a-how-should-the-nilpy-managed-finalize-re-enter-the-heap-lock]] for the
four grounds and the owner's words. **This ticket is the work, not the argument.**

## What it must handle

`PXXClassFinalizeManaged` runs under the codegen heap lock, reaches kind 6,
releases the inner object, and `PyObjFinalize -> PXXClassFinalize` calls
`PXXClassFinalizeManaged` again — acquiring a non-reentrant spinlock the same
thread already holds. **One instance, one thread, no contention.**

```python
class Inner:
    def __init__(self, s): self.s = s
class Outer:
    def __init__(self): self.f = Inner("hello")
o = Outer()
o = 0
```

**A wrapper-local depth counter does not work, and this is measured rather than
assumed:** the nested `PXXClassFinalize` runs its kind-4 pass, whose `FreeMem`
takes the lock at a **different codegen site**. Reentrancy has to live in the
lock primitive — owner plus depth — not in one caller.

## What it closes

| ticket | why it falls out |
| --- | --- |
| `bug-a-nilpy-under-threadsafe-still-leaks-every-class-field...` | its fix is BUILT and MEASURED (399524 kB → 7844 kB) and was reverted only for this deadlock |
| `bug-a-threadsafe-builds-leak-every-variant-and-interface-element-of-a-dynamic-array` | `ManagedElemKindLocked` degrades kinds 4 and 6 to 0 for the same reentrancy reason |
| record COM-interface fields | named at the bottom of that bug, same cause |
| `feature-n-nilpy-has-no-__del__...` | under a reentrant lock a user finalizer runs in place and may allocate |

## The measurement that attaches, and is NOT a gate

**The owner check's cost on the acquire path, min-of-N interleaved A/B,
post-magazine**, on x86-64 AND on one target that keeps the global lock. The
number the objection was argued from has never been taken. Record it either way.
**Do not re-open the fork on it without talking to the owner** — he ruled with
the objection in front of him.

## Sequencing

`__del__` lands **after** this, not before: building a user finalizer against a
lock that cannot re-enter is building against the deadlock. Once this is in,
`__del__` becomes the real adversary for it — a user finalizer that allocates
while the walk is running — which is a better test than the twelve-line repro.
