---
slug: bug-t-two-devtests-measure-the-box-and-flake-the-fleet-job
track: T
type: bug
prio: 45
status: backlog
blocked-by: []
summary: "Two guards in the tools/*devtest*.py family assert on ambient timing and go red when the box is busy — which on plexus means whenever the watcher runs a tier, i.e. whenever the fleet job runs. bench_timing was FIXED (c194b01e9/415d8e9f2); twatch_bench_quiet_devtest.py is the surviving one, observed red at load 14 and green on immediate rerun. tools-devtest#00 stops at the first failing file, so one flake masks all 50 other guards."
---

# Two devtests measure the box, and one still does

`tools-devtest#00` runs 50 guard scripts and **stops at the first failure**, so a
guard that fails for an environmental reason does not merely report itself — it
hides every guard after it in glob order. That is not hypothetical: it is how the
2026-08-19 cascade's `tools-devtest#00` red was triaged to a different file than
the one the fleet actually hit.

Two members of the family assert on ambient timing.

## 1. `bench_timing_devtest.py` — FIXED

Asserted `max(old) - min(old) < 3.0`, a **spread** over five subprocess runs.
Measured red at load average 14 with `[117.4, 166.1, 115.8, 116.0, 116.0]` — one
scheduling stall in five — while the claim it is named for was true throughout.
Replaced with an on-grid count (`415d8e9f2`): a stall can only push a sample to a
later poll wakeup, never off the schedule.

It is still excluded from `tools-devtest` by a `case ... continue` in the
Makefile, added by `a1fd5715e`. Re-including it is
`chore-a-re-include-bench-timing-in-tools-devtest`.

## 2. `twatch_bench_quiet_devtest.py` — OPEN

Observed **red** during a full-family sweep on 2026-08-19 while the watcher was
running a full tier, and **green on an immediate rerun** of the same file. The
failure text was not captured before the rerun, so which check tripped is not
recorded — that is a gap in this ticket, not a claim that it does not matter.

The suspect shape is visible in the passing output:

```
  ok   quiet-box-benches — ratio 1.00 starts
  ok   a-third-of-the-box-busy-is-fine — 1.09-1.30 (4 of 12 cores busy) still benches
  ok   oversubscription-never-starts — 2.17x / 4.75x refused
```

Those ratios are measured against the **real box**. The gate under test is
"should benching start given the current load", and it is correct for that gate
to consult the machine — but a *devtest* for it must supply the load, not observe
it. On a box already at load 14 the quiet case cannot be produced at all, so the
first check tests whether plexus happens to be idle.

**Fix direction:** stub the load probe the way `csmith_target_devtest.py` stubs
`run()` — feed the ratios in and assert the decision, so every branch is
reachable regardless of what else is running. Keep one end-to-end check that the
probe returns a plausible number, and let that one be the only ambient-dependent
line.

## Why this keeps happening

Third instance in one day of a guard whose stated subject is not what its
predicate measures — after `tstate_reader_devtest.py` asserting
`head_detached(this repo) is False` (a fact about the runner) and
`bench_timing_devtest.py`'s spread. The family runs **detached at an arbitrary
sha on a box that is usually busy**, so any guard reading its own repo's branch,
mtimes, `origin/master`, or the machine's timing is testing the runner.

Standing rule for the next guard in this family: if deleting the code under test
would not change the outcome, or if running it on a different box would, it is
not guarding what its name says.

## Verification

Run the family while a tier is in flight — that is the fleet's actual
environment, and it is the only environment in which these two have ever failed:

```
PXX_TRACK=T for f in tools/*devtest*.py; do python3 "$f" >/dev/null 2>&1 || echo "RED $f"; done
```

Measured 2026-08-19 in a **detached** clone at HEAD with the box loaded: 50 of 50
green after the `bench_timing` fix. `twatch_bench_quiet` passed that sweep, which
is consistent with an intermittent load-dependent flake rather than a hard fail.
