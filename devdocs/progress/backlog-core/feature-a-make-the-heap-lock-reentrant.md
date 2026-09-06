---
slug: feature-a-make-the-heap-lock-reentrant
title: "Make the codegen heap lock reentrant — the half of the arena ticket the owner parked, now unparked by his own trigger"
track: A
type: feature
prio: 60
status: backlog
owner: frankH
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

## 2026-09-06 — taken by frankH, and the design, because the hard part is not the depth counter

**THE IDENTITY PROBLEM IS ALREADY SOLVED IN THIS TREE AND MUST BE REUSED, NOT
RE-DERIVED.** "Owner plus depth" needs a trustworthy answer to *which thread am
I*, and on x86-64 the obvious one is wrong: **`gs:[0]` is INHERITED across
clone**, so every thread pxx did not create — glibc `pthread_create`, which
`test/test_multithreading.pas` has used for months — reads the block of whoever
created it. gdb reported `gs_base = 0x411f98` for all five threads there, i.e.
`BSS_TLS_MAIN`. Taking that block's tid would answer *"the lock is already
mine"* for a lock this thread does not hold — **silent loss of mutual exclusion,
in the primitive whose entire job is mutual exclusion.** That is a strictly
worse failure than the deadlock we are fixing, and no content check catches it,
because inheritance reproduces the block byte for byte.

`EmitIoLockStubs` (`ir_codegen.inc`, the x86-64 arm ~1191, and the three ports
in `ir_codegen386.inc` / `_aarch64.inc` / `_arm32.inc`) already carries the
answer, from `feature-a-io-lock-owner-from-tls-not-gettid`: **trust the cached
`TLS_SLOT_TID` only when the reader's own `rsp` lies between the
`TLS_SLOT_STACK_LO` / `_HI` bounds that block's owner recorded**, and fall back
to a `gettid` syscall otherwise. The stack is the one thing inheritance cannot
fake. A `gettid` on every acquire is not an option here and was not there
either — measured at **43% of a 400k-Writeln run, one third of all syscalls**,
which is why that ticket exists.

### The shape that costs nothing on the fast path

The contended path is **already out of line** — `EmitHeapLockSlowStub`, a 5-byte
call the `jz` skips — and it is entered on exactly the two cases that matter:
contended, and re-entrant. So the *comparison* belongs there and is free.

What the fast path must still do is **record** ownership, and that is where the
cost objection actually lands. Proposal, no syscall and no atomic:

1. **Fast path, after winning the `xchg`:** load `gs:[0]`, check `rsp` against
   the block's `STACK_LO`/`_HI`, and only then set a per-thread
   *"I hold the heap lock"* flag in a free TLS slot. ~6 instructions, no
   syscall, no atomic, no lock-line traffic.
2. **Slow stub:** if that flag is set for the calling thread (same bounds
   check), this is RE-ENTRY — bump depth and return with the lock conceptually
   held. Otherwise spin exactly as today, including the 2^18 budget and the
   exit-212 diagnosis.
3. **Release:** decrement depth; clear the flag and store 0 to the lock word
   only at depth 0.

**The bounds check failing is FAIL-SAFE in the right direction.** A foreign
thread, a handler on the sigaltstack, or bounds nobody filled simply never sets
the flag, so it can never be granted false ownership — it spins and, if it truly
self-deadlocks, gets today's exit 212 rather than a corrupted free list. We
degrade to current behaviour exactly where identity is untrustworthy, which is
the property that makes this landable without solving foreign-thread TLS first.

`TLS_SLOT_FIRST_FREE = 13` and three map slots are free — **re-read that from
`defs.inc` rather than trusting this sentence**, it is a census with an owner
elsewhere and the numbers were one lower a fortnight ago.

### Scope note that shrinks the job

The codegen heap lock is **x86-64 only**: `EmitAcquireHeapLock` /
`EmitReleaseHeapLock` are `EmitAsmX64` in `ir_codegen.inc`, which is the x86-64
backend, and `EmitHeapLockSlowStub` refuses off x86-64 outright. The I/O lock is
the one that has four ports. So this is one emitter, not four — unlike the
cost measurement the ticket asks for, which still wants a target that keeps the
global lock.

### The measurement, restated now that the shape is known

With the recording moved to ~6 non-atomic instructions and the comparison out of
line, the number the objection was argued from is measuring something that no
longer exists in the proposal. **Take it anyway, min-of-N interleaved, and
record it either way** — and note the two instrument defines
(`-dPXX_ALLOC_CENSUS`, `-dPXX_HEAP_DEBUG`) turn the magazine OFF, so every
allocation under the leak instruments takes this lock and pays the recording.
That is a measurement-speed cost, not a shipped one, and it should be said out
loud rather than discovered.
