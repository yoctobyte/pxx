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
