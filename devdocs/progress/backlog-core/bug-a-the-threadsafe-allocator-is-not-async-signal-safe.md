---
track: A
prio: 40
type: bug
blocked-by: []
summary: "A signal handler that ALLOCATES cannot proceed on a --threadsafe program: it re-enters the non-reentrant global heap spinlock the interrupted flow is holding, and that flow is not running. STILL TRUE, STILL NOT FIXED. What changed 2026-09-02 is the OUTCOME: option 3 landed, so instead of hanging with no output at all the program now writes `Runtime error 212: the heap lock was never released` naming this ticket and exit_group(212)s, measured 1.9s from the collision, 6 runs of 6. The lock itself is unchanged and the fast path is byte-identical; only the contended branch moved out of line into EmitHeapLockSlowStub. Options 1 (block signals around the locked region) and 2 (reentrancy plus instruction-boundary-consistent state) are the actual fix and are untouched, which is why this stays open. The per-thread magazine still narrows the population -- a handler whose traffic fits it never reaches the lock -- so the reproducing configuration is `--threadsafe -dPXX_NO_HEAP_MAG` with a RETAINING handler. The residual this ticket owns is unchanged: TLS_SLOT_HEAP_MAGBUSY is still reasoned and not verified by execution, because the shapes that would aim a control at it still cannot complete -- they now exit 212 instead of hanging, which makes the aiming failure visible but no less real."
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

## 2026-09-02 — option 3 landed (frankA, Track A)

The hang is now a diagnosis. Nothing else about the defect moved.

**What shipped.** `EmitAcquireHeapLock`'s fast path is unchanged and
byte-identical (push / mov / `lock xchg` / test / branch-over-one-thing); what
the branch skips is now a 5-byte call to `EmitHeapLockSlowStub` instead of an
unbounded wait loop. The stub spins TTAS+pause with a counter that RESETS on
every observation of a free lock, acquires and returns with the lock held, and
on exhaustion writes the named message to stderr and `exit_group(212)`. Four
call sites, mirroring `EmitDiv0Stub`: the shared `EmitProgramPrologue` plus the
Pascal, C and NilPy drivers, each of which rolls its own prologue. Verified the
string is present in a `--threadsafe` binary from all three hand-rolled drivers
and absent without the flag.

**Not the detection this ticket recommended, deliberately.** The text proposes
`TLS_SLOT_HEAP_MAGBUSY` as the in-allocator flag to test. That slot lives in a
TLS block a foreign thread SHARES with its creator (measured earlier in the same
session, on the foreign-thread work), so a slot test would false-positive and
halt a working program. The counter needs no per-thread state at all.

**`HEAP_LOCK_SPIN_LIMIT` was MEASURED, and the measurement corrected the
reasoning.** The comment first written for it said ordinary contention could
never approach the limit because the counter resets. That is wrong, and the
sweep says so: what the counter really measures is *how long the holder has been
off the CPU*, and a holder preempted mid-allocation is off it for a scheduler
quantum. On frankA (12 cores), twelve threads in a bare `GetMem/FreeMem` loop
with `-dPXX_NO_HEAP_MAG` — every allocation on the lock — behave like this:

| limit | legitimate-contention result |
| --- | --- |
| 2^3 … 2^16 | **falsely diagnoses**, every run |
| 2^18 | **falsely diagnoses**, 5 of 5 |
| 2^20 | clean, 3 of 3 |
| 2^22, 2^24 | clean, 3 of 3 each |
| 2^28 (shipped) | clean; also clean at 64 threads on 12 cores, magazine off (5 runs) and on (3 runs) |

So the shipped value sits 1024x above the highest limit that produced a false
positive. The margin is against a longer STALL, not against more contention —
more contention does not move this number.

**A boundary in this ticket's own text that did not reproduce.** The summary
said the retaining-handler program "hangs identically with the magazine's
re-entry guard present and absent, so the magazine is not the variable". The
shape run here — 64-entry ring, `GetMem(p, 96)`, freed as a batch on wrap, 2M
main-thread rounds, SIGUSR1 hammered from a sibling — **survived with the
magazine on**, `hits=880359`, rc=0, and hung only under `-dPXX_NO_HEAP_MAG`.
Not a contradiction of the defect, and not a claim the original measurement was
wrong: a ring whose blocks exceed the magazine's per-bin capacity would miss it
where this one hits. It does mean the reproducing configuration has to name the
define, which the new test row does.

**Test.** `test/test_threadsafe_heap_lock_deadlock_diag.pas`, two phases in one
binary. Phase 1 is the twelve-thread contention run above and must NOT diagnose
— a control that demonstrably CAN fail, since it fires at a limit of 2^18.
Phase 2 is the retaining handler and must exit 212 with the named message. On
the pre-fix pin the same source prints the phase-1 line and then hangs to the
60s timeout, so the row fails pre-fix on the exit code.
