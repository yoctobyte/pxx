---
track: T
prio: 60
type: bug
blocked-by: []
summary: "76 testable pushes in the four hours since the last full tier completed, median interval 1-4 minutes, against a ~4-minute native run — so the watcher never reaches idle and the full matrix has not run ONCE. Cross-target coverage is currently zero while every native verdict is green, and two agents are waiting on cross answers that cannot arrive. Pin verify has been preempted 33 times for the same reason."
---

# The push rate starves breadth coverage entirely

Measured 2026-08-19 by Track T (plexus-T), while answering two cross-sweep
requests that turned out to be unanswerable.

## The measurement

| | |
| --- | --- |
| last completed `full` tier | `9bfb7fcfac03`, **10:31:57Z** |
| testable pushes since | **76** |
| median interval between them | **1-4 minutes** |
| a native run | ~**246s** (~4 min) |
| a full run | ~**1250s** (~21 min) |
| `full` runs in that window | **0** |
| `native` runs in that window | **30** |
| `pin verify preempted by a push` | **33** |

**Pushes arrive faster than a fast verdict completes.** The watcher is therefore
never idle, and every phase that runs only when idle — the full-matrix backfill,
pin verification, fuzz — is starved. It is not aborting the full tier; it never
schedules it.

## Why this is a bug and not just a busy day

The dev-track protocol in `devdocs/dev/track-t.md` is *"confirm native yourself,
offload the matrix to T"*. Every lane's push discipline rests on the matrix
actually running later. Right now it does not, and **nothing says so**:

- `twatch --status` reports **UP**, correctly — it measures whether commits have
  been tested, and they have, at `native`.
- every native verdict is **GREEN**.
- so the fleet reads as fully covered while **cross-target coverage is zero** and
  has been for four hours.

That is a coverage claim whose boundary nobody is checking, which is the failure
`track-t.md` has a whole section about. Two live instances today: `a54259aab`
(the `stdarg.h` bodies moved from `static` to external — the open question is
whether i386/arm32/riscv32 resolve `__pxx_va_start_impl32` now) and `354f734c1`
(`PXXWriteFloatSci` across five backends). Both have native GREEN. **Neither has
been near a cross target**, and the requesting agent would reasonably have read
the greens as confirmation had it not been told otherwise.

Pin verification is the second casualty and arguably the worse one: 33
preemptions means `pinstatus` cannot name a freshly-verified pin, and the pin is
what every other track builds against.

## Shape (T's call, not yet decided)

Sketching rather than prescribing, because the trade is real — the fast verdict
is load-bearing and its latency IS the dev loop's latency:

1. **Reserve breadth a slot.** After N fast verdicts, or T minutes since the last
   completed `full`, run the full tier and let the fast verdicts queue behind it.
   Simple, and it directly bounds the staleness. Costs fast-verdict latency
   exactly when the repo is busiest.
2. **Make the backfill resumable** rather than all-or-nothing, so a 21-minute
   run can complete across several idle slices instead of needing one contiguous
   window that never comes. More work; does not need to steal latency.
3. **Say so out loud.** Whatever else, `--status` and the tstate report should
   carry "no full-tier verdict for N hours" — the cheap half, and it converts a
   silent hole into a visible one. Worth doing even if 1 and 2 are declined.

(3) is separable and small; recommend it regardless.

## Note

Not caused by the two-phase design being wrong — the design says the fast verdict
wins and a backfill is discardable, which is right. What has changed is the
arrival rate crossing the point where "idle" stops occurring at all. A rate
threshold nobody set explicitly is worth naming before it is tuned.
