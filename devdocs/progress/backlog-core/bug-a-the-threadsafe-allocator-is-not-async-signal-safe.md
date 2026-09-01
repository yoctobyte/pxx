---
track: A
prio: 40
type: bug
blocked-by: []
summary: "A signal handler that ALLOCATES hangs a --threadsafe program, measured: SIGUSR1 hammered from a sibling thread onto a main thread in a GetMem/FreeMem loop, handler calls GetMem, 20s timeout and no output. Cause is the pre-existing non-reentrant heap spinlock -- the handler re-enters the lock the interrupted flow is holding, which is the same hazard decide-interface-members-in-aggregates-lock-strategy parked for aggregates, arriving through signals instead. NARROWED BUT NOT FIXED by the per-thread magazine (feature-a-reentrant-heap-lock-and-per-thread-arenas): a handler whose traffic fits the magazine now completes -- 11.8M handler allocations against 3M in main, no aliasing, no dirty block -- because it never reaches the lock. A handler that MISSES still deadlocks, confirmed with a handler that retains 64 blocks and releases them in a batch: hangs identically with the magazine's re-entry guard present and absent, so the magazine is not the variable. NOT a regression from that work and not caused by it; it is the residual it leaves, filed so the exculpation has an owner. The magazine's own list is protected by TLS_SLOT_HEAP_MAGBUSY, which is reasoned and NOT verified by execution -- every test shape that would expose the aliasing hits this deadlock first, which is precisely why this ticket has to exist before that one can be called done."
status: backlog
owner: unassigned
---

# The --threadsafe allocator is not async-signal-safe

## The measurement, and the one that misled

`sigalloc`: main thread in a 2,000,000-iteration `GetMem(64)/FreeMem` loop, a
sibling thread hammering it with `tkill(SIGUSR1)`, and a handler that does one
`GetMem/FreeMem` of the same size.

| build | result |
| --- | --- |
| `--threadsafe -dPXX_NO_HEAP_MAG` | **hangs**, 20s timeout, no output |
| `--threadsafe` (magazine) | `survived hits=91464` |

That table is true and it is not the whole answer, which is the part worth
carrying. A second program — handler KEEPS its blocks in a 64-entry ring and
frees the batch when it wraps — **hangs on both**. The magazine did not fix the
hazard; it moved the threshold. A handler whose allocations fit the per-thread
magazine never touches the lock and therefore cannot deadlock on it. A handler
that misses reaches exactly the code that hung before.

## Why it hangs

`EmitAcquireHeapLock` is a plain TTAS spinlock with no owner and no depth. A
signal delivered while the interrupted flow holds it runs a handler that spins
on a lock only the interrupted flow can release, and that flow is not running.
This is the same non-reentrancy that
[[decide-interface-members-in-aggregates-lock-strategy]] took option (b) to
avoid for aggregate finalization, and that the owner parked on 2026-08-21 for
allocation generally. The unpark trigger recorded there is *"a real-world
project hitting it"* — a signal handler that allocates is a plausible way for
one to.

## What a fix has to decide

Not a small ticket, and the options are genuinely different animals:

1. **Block signals around the locked region.** Correct and obvious, and it puts
   two `rt_sigprocmask` syscalls around every allocation that misses the
   magazine. Almost certainly unaffordable; worth measuring before dismissing,
   because with the magazine in place the miss rate is now low.
2. **Make the lock reentrant** (owner + depth). The parked half of
   [[feature-a-reentrant-heap-lock-and-per-thread-arenas]]. Reentrancy alone is
   NOT sufficient here and that is the trap: a handler that re-enters the
   allocator mid-update sees a half-linked free list, so this needs the state to
   be consistent at every instruction boundary, not merely re-enterable.
3. **Declare it unsupported and DIAGNOSE it.** The honest cheap option. There is
   no way to detect "allocates" statically in a handler proc, but the runtime
   could set a per-thread in-allocator flag (one already exists —
   `TLS_SLOT_HEAP_MAGBUSY`) and have the locked path halt with a named error
   instead of spinning forever. A hang with no output is the worst of the three
   outcomes; a message naming the cause is the cheapest improvement available.

Option 3 is the recommendation for a first slice: it costs one test on a slot
that is already read on the same path, and it converts the failure this ticket
describes from a hang into a diagnosis.

## The residual this ticket owns

`TLS_SLOT_HEAP_MAGBUSY` guards the magazine's own list against a handler
interleaving with a pop or a push. It is **reasoned and unverified**: every test
shape that would expose the aliasing it prevents needs the handler to RETAIN its
block (a handler that allocates and frees pushes a doubly-handed block straight
back before main can observe it — the first version of that test came back GREEN
against a compiler with the guard deliberately removed), and every retaining
shape then misses the magazine and hits the deadlock above. Confirmed: that
program hangs with the guard present and absent alike, so the guard is not the
variable and the control could not be aimed.

Whoever fixes the deadlock unblocks the control. Until then the guard costs
nothing measurable (the single-thread benchmark row is 9ms either way) and its
absence cannot be shown to cost anything either.
