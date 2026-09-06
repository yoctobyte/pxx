---
type: bug
track: A
prio: 5
summary: under --threadsafe a dynamic array of Variants or of COM interfaces never releases its elements — 3848 live blocks per 1000 trips against 4 in a default build; deliberate (it prevents a deadlock) and correct as a choice, but the residual leak had no ticket and no number
tags: [memory-leak, threadsafe, variant, interfaces, dynarray]
blocked-by: [feature-a-make-the-heap-lock-reentrant]
---

## Measured

1000 trips, `-dPXX_ALLOC_CENSUS`, x86-64, on `42507851cdde`. Same source, same
binary path, the only difference is `--threadsafe`:

    shape                                    default   --threadsafe
    dyn array of Variant                          4      3848   LEAK
    dyn array of COM interface                    4      3848   LEAK
    dyn array of Variant + grow/shrink/regrow     4      3916   LEAK
    ---- unaffected, for contrast ----
    dyn array of AnsiString                       4         4
    dyn array of PromoInt                         9         9
    a plain local Variant                         1         1

Roughly four leaked blocks per trip, i.e. one per element, which is the whole
array.

## Why it happens, and why the choice is right

`ManagedElemKindLocked` (symtab.inc ~2998) degrades element kinds 4 (COM
interface) and 6 (Variant) to 0 when `ThreadSafeMode` is set, so the walk skips
them. Its header explains the mechanism and the choice is not conservatism:
releasing an interface element runs `_Release -> Destroy -> FreeMem`, and FreeMem
re-acquires the same NON-REENTRANT spinlock the dynamic-array paths already hold,
so the program would HANG rather than leak. Kind 5 (promo) is deliberately not
refused, because a promo payload is only ever an AnsiString and its release is
the same `PXXStrDecRef` kind 1 has always done under that lock — which the
measurements above confirm: promo is the one managed kind that stays clean.

**A hang is worse than a leak and this ticket does not dispute the trade.**

## What is missing is the price, and an owner for the residual

The header calls it "the pre-existing leak" and routes lifting it to
`decide-interface-members-in-aggregates-lock-strategy`. That decision is
**decided**, and `feature-a-reentrant-heap-lock-and-per-thread-arenas` is
**done** — but done for the ALLOCATOR half only. Its own summary says
"REENTRANCY STAYED PARKED AND UNNEEDED": the magazine fast path was built in the
emitter precisely so nothing could re-enter the non-reentrant lock. So the lock
is still non-reentrant, the degradation is still required, and the leak is still
there — while both tickets that would lead a reader to it read as closed.

That is the gap this ticket exists to close: a deliberate leak whose two
reference points are both marked done, with no open ticket naming it and no
number attached to "benign".

**It is not benign at the scale it applies to.** Any `--threadsafe` program
holding Variants or interfaces in dynamic arrays leaks the whole array on every
release, forever. `--threadsafe` is what a long-running server build uses, which
is the workload where an unbounded leak matters most.

## Fixing it needs the reentrancy half, or a split unlocked pass

Both routes are already described in the decided ticket: a reentrant heap lock,
or a separate interface/variant pass emitted OUTSIDE the lock — the latter being
exactly what `bug-a-class-managed-fields-not-finalized-on-destroy` did for class
fields (kind-4 pass first and unlocked), and what
`PXXRecordRetainIntf/ReleaseIntf` already do for record members. The container
case was left behind when those landed.

Note the shape of the existing solution before designing a new one: the unlocked
pass is a proven pattern here, used twice, and this is the third site.

## Measuring notes for whoever takes it

`-dPXX_ALLOC_CENSUS` and `-dPXX_HEAP_DEBUG` both disable the per-thread magazine
(they instrument `PXXAlloc` and the magazine bypasses it), so census numbers
describe the locked path — which is the path this bug is about, so the
instrument and the defect agree here. Do not assume that holds for a throughput
measurement.

STATIC arrays are NOT gated and do not leak: their scope-exit walk is emitted
outside any lock. Only the dynamic-array paths hold it.
