---
type: bug
track: A
prio: 5
summary: "FIXED 2026-09-06 -- 7939 live -> 3 at the SAME allocation count (13891), 1000 trips of a dyn array of Variants and of COM interfaces. ManagedElemKindLocked's ThreadSafeMode degradation of kinds 4 and 6 is deleted because the heap lock is reentrant (feature-a-make-the-heap-lock-reentrant, owner decision arm (a)); _Release -> Destroy -> FreeMem still re-enters the lock and the lock now survives it. The trade this ticket declined to dispute was correct and is simply no longer necessary. POSITIVE CONTROL: the same program with -dPXX_NO_REENTRANT_HEAPLOCK hits rc=212 with the heap-lock diagnosis on stderr (message checked, not just the code), so the reentrancy is load-bearing rather than assumed. The record COM-interface fields named at the bottom were NOT closed by this and ARE closed now, later the same day: both {$ifndef PXX_TS_HARDLOCK} guards on PXXRecordReleaseIntf are lifted, test_interface_containers under --threadsafe is byte-identical to native, and -dPXX_NO_REENTRANT_HEAPLOCK gives rc=212 there too. See bug-a-array-of-records-with-interface-fields-leaks-the-interfaces."
tags: [memory-leak, threadsafe, variant, interfaces, dynarray]
blocked-by: [feature-a-make-the-heap-lock-reentrant]
status: done
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

## 2026-09-06 — FIXED. The degradation is gone because the lock re-enters.

The owner ruled arm (a) of
`decide-a-how-should-the-nilpy-managed-finalize-re-enter-the-heap-lock`, the
heap lock gained owner+depth (`feature-a-make-the-heap-lock-reentrant`), and
`ManagedElemKindLocked`'s `if ThreadSafeMode then kind := 0` for kinds 4 and 6
is deleted. Nothing about the trade this ticket declined to dispute has changed
— `_Release -> Destroy -> FreeMem` still re-enters the same lock. **The lock now
survives it.**

`test/test_threadsafe_dynarray_releases_variant_and_interface_elements.pas`,
1000 trips of each shape, `-dPXX_ALLOC_CENSUS`:

| | allocs | frees | live |
| --- | --- | --- | --- |
| pinned (pre-fix) | 13891 | 5952 | **7939** |
| HEAD | 13891 | 13888 | **3** |
| HEAD `-dPXX_NO_REENTRANT_HEAPLOCK` | — | — | **rc=212, the deadlock** |

Same allocation count on the two that finish, so this is the free side alone,
which is what this ticket said it would be.

**The third row is what makes the first two mean something.** With reentrancy
switched off in the same tree, this exact program hits the heap-lock deadlock
diagnosis — so the row cannot pass for a reason unrelated to the fix, and the
reentrancy is demonstrated load-bearing rather than assumed. Verified by the
stderr TEXT and not only by the exit code: 212 arriving for another reason would
pass the control and prove nothing.

### The route this ticket recommended is NOT the one taken, and it was right to name both

It said: a reentrant heap lock, **or** a separate unlocked interface/variant
pass — noting the unlocked pass was proven twice already (class fields,
`PXXRecordRetainIntf`/`ReleaseIntf`) and this was the third site. The fork chose
the lock. The standing objection to the unlocked-pass route is what decided it:
every future release site must then remember to run outside the lock, which is
per-site discipline that arm (a) exists to delete.

### Not closed by this: the record COM-interface fields

`builtinheap.pas` still carries two `{$ifndef PXX_TS_HARDLOCK}` guards on
`PXXRecordReleaseIntf` inside the dyn-array-of-records walks — the row named at
the bottom of this ticket. Same shape, should fall the same way, deliberately
left for a change that can measure it on its own rather than riding in on a
commit whose control is about elements.

- 2026-09-06 — resolved, commit 3bb71fd79 (the fix and the close are one commit).

## 2026-09-06, later — the record row IS closed

The two `{$ifndef PXX_TS_HARDLOCK}` guards this ticket deliberately left standing
are lifted, under
[[bug-a-array-of-records-with-interface-fields-leaks-the-interfaces]], whose own
resolution had named the reentrant heap lock as the unblocking condition.
`test_interface_containers --threadsafe` is byte-identical to native; the same
program with `-dPXX_NO_REENTRANT_HEAPLOCK` dies rc=212 with the heap-lock text.
