---
slug: chore-a-re-include-bench-timing-in-tools-devtest
track: A
type: chore
prio: 30
status: backlog
blocked-by: []
summary: "One line: `tools-devtest` skips `bench_timing_devtest.py` with an explicit `case ... continue`, added by a1fd5715e because the guard was load-sensitive. It has been fixed (c194b01e9) and is green under load average 14. Deleting the skip re-arms the only guard for bug-t-bench-sub-second-timings-quantized-to-50ms, which has not run in the fleet since the family was wired up."
---

# Re-include bench_timing_devtest.py in `tools-devtest`

`Makefile:11271` reads:

```make
	for f in tools/*devtest*.py; do \
	  case "$$f" in *bench_timing_devtest.py) continue ;; esac; \
```

Delete that `case` line. That is the whole ticket.

## Why it was skipped, and why it no longer needs to be

`a1fd5715e` (2026-08-19) wired the `tools/*devtest*.py` family into a single job
so the guards would stop rotting, and excluded this one file. The exclusion was
justified at the time: the guard asserted `max(old) - min(old) < 3.0` over five
subprocess runs — a **spread**, which measures the machine rather than the code.
On a box running a full tier it fails for reasons that have nothing to do with
the property under test.

Measured 2026-08-19 at load average 14: `[117.4, 166.1, 115.8, 116.0, 116.0]`.
One scheduling stall in five. The claim the check is *named* for was true
throughout — `min(old)` sat 2.3 ms from the 113.5 ms poll wakeup, exactly as
`bug-t-bench-sub-second-timings-quantized-to-50ms` predicts — and the guard went
red anyway.

`c194b01e9` replaced the spread with an on-grid count: a scheduling stall can
only push a sample to a **later** poll wakeup, never off the wakeup schedule, so
"4 of 5 samples sit on a grid point" is the same statement made about the code.
It still discriminates — the fixed path's continuous timings score 0/5. Green
4/4 under the same load that produced the red.

## Why this is a Track A ticket for a one-line change

The `tools-devtest` recipe exists solely to run Track T's guards, so arguably T
should own that line. But it lives in `Makefile`, and T's push lane is
`tools/testmgr.py` / `tools/twatch*` / `tools/fuzz.sh` / `tools/pasmith*` /
`tstate/**` and nothing else. T filed rather than reached across, the same call
made for the recipe markers in
`bug-t-makefile-inner-timeouts-are-invisible-to-testmgrs-contention-logic`.

**If the lane boundary should put the `tools-devtest` recipe under T, say so and
T will maintain it** — that is a Track U call, not something to settle by
editing.

## Verification

Run `PXX_TRACK=T python3 tools/bench_timing_devtest.py` a few times while the box
is busy. It prints the five old-path samples, the true duration and the grid
point it snapped to, so a future flake is legible rather than a bare FAIL.

The cost of re-including it is ~1.5s (ten subprocess launches).

---

## The justification above was WRONG, and the ticket is now actionable for a different reason — Track T, 2026-08-30

**Do not act on the "Why it no longer needs to be" section as written.** Its
central claim — that `c194b01e9`'s on-grid count is load-invariant — rests on a
sentence that is false, and I measured it tonight:

> *"a scheduling stall can only push a sample to a **later** poll wakeup, never
> off the wakeup schedule"*

It can, and it does. The stall does not have to land in the child or between
wakeups: it lands in the **parent**, between the poll wakeup and the clock read
that follows it, and *that* delay is not quantized by anything. On this box at
load ~9.5 with eight agents running:

```
old (subprocess.run timeout=): [169.4, 119.0, 115.8, 119.1, 117.1]
                               ->  2/5 within 4 ms of a grid point   FAIL
```

`min(old)` was 115.8 — **+2.3 from the 113.5 ms wakeup**, exactly what
`bug-t-bench-sub-second-timings-quantized-to-50ms` predicts. The claim the check
is *named* for was true and the check said FAIL, which is the same failure the
spread version had, one abstraction along. A **count of contaminated samples is
a measurement of contamination**; so is a spread. Both are properties of the box.

Had Track A taken this ticket as written, it would have re-armed a guard that
reds under load — into `tools-devtest`, which sits in the **limited and full**
tiers, i.e. the watcher's matrix.

**Fixed at `8c592615d`** (Track T's own file, no Makefile touched). Scheduling
noise is one-sided and additive — it can only make a sample later, never earlier
— so the **minimum** is the least-contaminated estimate of each path's behaviour
and the only statistic here that does not degrade as the box gets busier. More
samples improve a minimum; they make a count and a spread worse. Both halves are
now stated about minima, and the *pair* discriminates: `min(old)` sits ON the
grid, `min(new)` is 8 ms+ below it. A continuous clock cannot satisfy the first
(`TARGET_MS` is chosen to sit between 63.5 and 113.5) and a grid cannot satisfy
the second.

Verified three ways rather than one:

- **replay** of the recorded load-red data: v2 fails it, v3 passes it;
- **vacuity**: a continuous 70 ms path scores `near_grid=False`, so v3 cannot be
  satisfied by the thing it is meant to reject;
- **negative control**: making the old path use `_timed_run` reds both halves.

Green three consecutive runs at load 3.8, and it passes the recorded load-9.5
data by replay. The remaining exposure is honest: nothing has yet run it *live*
at load 14, because manufacturing that load on the owner's workstation is not a
measurement worth taking.

**So the one-line change this ticket asks for is now safe, and the ticket stays
Track A's** for the reason it already gives — the recipe is in `Makefile` and T's
push lane is not. The lane question it raises at the bottom is still open and
still a Track U call.
