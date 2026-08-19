---
track: T
prio: 60
type: bug
blocked-by: []
summary: "Zero full-tier runs on HEAD in the 5h13m between 9bfb7fcfac03 (10:31:57Z) and ~15:45Z, while cross-target coverage read as fine because every native verdict was green. RE-MEASURED: the watcher is idle 54% of that window (~2.8h, 8x what a full tier needs) — breadth is not starved by pushes, it is queued behind pin verify, which needs a contiguous 21 minutes, gets idle slices with a median of 299s, and discards 100% on every abort. Breadth ran within minutes of pin verify finally retiring. Fix is resumability plus bounding consecutive idle, NOT reserving a slot."
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

## RE-MEASURED 2026-08-19 ~15:45Z — the headline held, the mechanism did not

Re-measured at current HEAD rather than quoted, because the numbers above are
five hours old. The window is the one that matters: from the last completed
`full` tier to the next one starting.

| | |
| --- | --- |
| last completed `full`-on-HEAD | `9bfb7fcfac03`, **10:31:57Z**, 1255.9s, GREEN |
| next `full`-on-HEAD start | ~**15:45Z** — **5h 13m later** |
| breadth starts in between | **0** |
| pin-verify starts in between | **16** |
| pin-verify *verdicts* in between | **1** (the last one, minutes ago) |
| native runs | 37, mean **236s**, total **2.4h** |
| aborted `full` runs | 13 — median **299s**, max **941s** |
| wall clock discarded by those aborts | **1.4h** |
| commits needing no gate (docs/tstate) | 18 |

**The headline claim holds: zero breadth runs in five hours.** The stated
mechanism above — *"the watcher is therefore never idle"* — is **wrong**, and
the correction changes which fix is right.

Native testing consumed 8740s of an 18900s window: the watcher was **idle 54%
of the time, about 2.8 hours of it.** Idle capacity exceeded what one full tier
needs (1256s) by roughly **8x**. Idle was never the scarce resource.

What is scarce is a *contiguous* window, and breadth never gets one because it
is not first in line for it:

1. `pin_mid` (branch 2) sits **above** idle-depth-on-HEAD (branch 3) in the
   ladder, deliberately — the pin is what B/C/D/E are building with right now.
2. Under the shipped default `mid_tier == tier`, that branch asks for a **full**
   tier on the pin: ~21 minutes.
3. Idle arrives in slices — the 13 aborted runs have a **median of 299s** and a
   max of 941s. A 21-minute job never fits, and every abort discards **100%** of
   the work.
4. So `pin_verify_due` never goes false, and **branch 3 is never reached.**
   Breadth is not starved by pushes directly; it is queued behind an item that
   cannot finish.

The confirmation is clean: pin verify finally retired (one 20.5-minute window,
`PIN v364 RED at full`) — and breadth started its first run in 5h13m **within
minutes of that**, with the push rate unchanged.

### What this does to the shapes below

- **Shape 1 (reserve breadth a slot) is now the wrong fix.** It spends
  fast-verdict latency to buy contiguity, when idle already supplies 8x the
  capacity needed. It treats a scheduling-order problem as a capacity problem.
- **Shape 2 (resumable) is the right one — and it must cover pin verify, not
  just breadth.** A perfectly resumable breadth would still never run, because
  branch 2 is ahead of it and unfinishable. Making *pin verify* resumable
  retires it, and unblocks breadth as a side effect.
- **New shape 4, cheaper than either: bound how much consecutive idle one
  unfinishable phase may hold.** Alternate, or cap it, so breadth gets turns.
  Costs fast-verdict latency exactly **nothing** — both phases are idle-only.
  Alone it does not finish a 21-minute job in 5-minute slices; with shape 2 it
  does.

Recommendation: **2 + 4**, neither of which touches the fast verdict. Shape 1
should be closed as measured-wrong rather than left open as an option.

### Self-inflicted instance, recorded because it generalises

`NOTEST_PREFIXES` is `("devdocs/", "docs/")`, so **`tools/**` is testable** —
correctly, since testmgr changes can change results. The consequence is that
**Track T's own tooling pushes preempt Track T's breadth run.** Pushing
`8ec77190c` cost the in-flight breadth run its first ~200 jobs. Until shape 2
lands, T tooling pushes should be batched, or held while a breadth run is in
flight.

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

## 2026-08-19 — shape 3 SHIPPED (the visibility half). 1 and 2 remain open.

The scheduling trade is untouched and still undecided; what is fixed is that the
hole is no longer silent.

**`--status` now prints a breadth line whenever a host has ever run a full
tier** — always, not only past the threshold, because the age IS the boundary of
the claim and a boundary nobody can see does not get checked:

```
tstate: host plexus  last 6fba42d69830 RED (native, ...); full through 9bfb7fcfac03 GREEN
tstate:   breadth — newest full tier is 4h old, 39 testable commit(s) behind
```

Past `BREADTH_STALE_SECS` (6h) it adds
`[STALE — no cross-target verdict on this tree; native GREEN does NOT cover
i386/arm32/riscv32/aarch64]`.

"Testable commits behind" counts what a gate OWES (`needs_test`), not raw
commits: on this repo the watcher's own publishes are most of the log, so a raw
count would read as alarming on a quiet day and bury the signal on a busy one.

**Published reports carry it too**, which is the half that matters days later —
a `native` report is what a reader reaches for, and GREEN on it says nothing
about the cross targets:

> **BREADTH IS 7h STALE.** The newest `full` tier on this host is 7h old, so no
> cross target has seen this tree. A `native` verdict covers x86-64 only — do
> not read it as matrix coverage.

A host that has **never** completed a full tier gets its own wording, because an
undefined age must not render as fine. A `full` report gets no banner — it *is*
the breadth run.

### The framing worth keeping, and why this was worth doing before the hard part

`--status` said UP and **was correct**: it measures whether commits were tested,
and they were. Every verdict said GREEN and each was true of the tier that
produced it. **The defect was never a wrong answer — it was a true answer to a
narrower question than the reader believes it is answering**, and this is that
shape at its most load-bearing, because CLAUDE.md tells every lane to run
`quick` + self-host and offload the matrix, and for four hours there was no
matrix.

The only thing standing between that and a wrong conclusion was one agent
warning another by hand. **A correctness property that depends on somebody
remembering is a habit, not a property**, and habits do not survive a context
clear.

**Gate:** `tools/twatch_breadth_visibility_devtest.py` (new, in
`make tools-devtest`) — the stale banner and its age, the never-ran wording, the
fresh case, the full-tier case, and that `secs_since` returns None rather than 0
on a malformed timestamp (0 would render "0h old" and mean the opposite).

**Still open:** shape 1 (reserve breadth a slot) and shape 2 (resumable
backfill). Both trade against fast-verdict latency, which is the dev loop's
latency, and neither should be decided from one busy afternoon.
