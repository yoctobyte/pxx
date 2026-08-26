---
slug: bug-t-two-devtests-measure-the-box-and-flake-the-fleet-job
track: T
type: bug
prio: 45
status: done
blocked-by: []
summary: "Two guards in the tools/*devtest*.py family assert on ambient timing and go red when the box is busy — which on plexus means whenever the watcher runs a tier, i.e. whenever the fleet job runs. bench_timing was FIXED (c194b01e9/415d8e9f2); twatch_bench_quiet_devtest.py is the surviving one, observed red at load 14 and green on immediate rerun. tools-devtest#00 stops at the first failing file, so one flake masks all 50 other guards."
owner: trackt-1
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

---

## Resolution (2026-08-26) — the mechanism, and two corrections to this ticket

### The flake, named and reproduced

Neither of the three cases this ticket named. It is
**`case_reference_is_self_calibrating`**, which does not appear in the excerpt
above because it PASSED in the sweep that was quoted. It called
`twatch.box_speed()` three times against the real box and asserted on the
relationship between three ambient measurements:

```python
r1, t1 = twatch.box_speed("h")        # measured
twatch._BENCH_RT["h"]["probe_ref"] = t1 / 4
r2, _ = twatch.box_speed("h")         # measured
assert r2 > 2.0
```

`r2 > 2.0` reduces to `t2 > t1/2`: it holds only while the second probe is no
more than **twice as fast** as the first. Nothing in the reference logic says
that; it is a fact about the runner. Reproduced deterministically by supplying a
stalled first probe and a clean second one — the one shape that breaks it:

```
stalled first probe t1=40ms, clean second -> r2=1.0
old assertion `r2 > 2.0`: FAIL
```

`1.0` is the maximally wrong answer, and it arrives with no sign of being one.

**Why it is rare rather than constant, which the ticket could not explain:**
`box_speed` takes `min()` of `BENCH_PROBE_SAMPLES=3` probes, so a single
momentary stall is absorbed. The flake needs a load *window* that covers all
three samples of the first call and has lifted by the second — i.e. a tier
finishing mid-devtest. That is exactly the 2026-08-19 observation (red during a
full tier, green on immediate rerun) and exactly why it is not reproducible on
demand.

### Fix

`probe_returning()` supplies `speed_probe`'s return value, so the case exercises
the reference ARITHMETIC — min-so-far, downward tracking, per host — which is
pure. Supplying also let the assertions get **stronger**: `r2 == 4.0` where
observing forced the loose `r2 > 2.0` that a fast second probe broke, and
`probe_ref == t1` for downward tracking where the old file could only say
`< t1 * 4`. One assertion the old file never made is now there: a SLOWER probe
must not raise the reference (min-so-far, not last-seen).

Per the fix direction's "keep one end-to-end check": `case_probe_returns_a_
plausible_number` calls the real `speed_probe()` and asserts only what no load
can change — a monotonic clock across real work is positive and finite. It does
**not** assert how long it took. That is the assertion this file just removed.

### Correction 1 — part 1 is fixed, not open

`tools-devtest` no longer stops at the first failure. Fixed **2026-08-25 by
`5f080ccf3`** (reported by frank1-72), after this ticket was filed: it
accumulates a count, prints every FAIL with 25 lines of its log, and reports
`N green, M RED -- <files>`. Confirmed live this session when it printed
`tools-devtest: 75 green, 1 RED -- tools/report_exp_dur_devtest.py` and kept
going. The premise was true when written; it was overtaken.

### Correction 2 — the three named suspects do not measure anything

> Those ratios are measured against the **real box**.

They are not. All three pass frozen literals to the predicate — `1.09, 1.19,
1.30` and `2.17, 4.75` — and time nothing. They were correct all along.

**How the misdiagnosis happened, because the shape will recur:** the triage read
the *passing output*, and the passing output said `Measured on the 12-core
xeon`. That note described the **provenance of a constant** and was read as
describing a **runtime action**. The one case that really did call `box_speed()`
said nothing about measuring, so it was not in the excerpt at all — the file
advertised the wrong three and concealed the fourth.

Same family as the repo's other reporting defects (*no evidence of X and could
not look for X must never print the same*), one level out: **a note that
describes where a number came from is read as describing what the code does.**
The docstrings now say `FROZEN observations ... fed in as literals`, and say so
where a triage will read it.

### Standing rule, extended

The ticket's own rule — *if deleting the code under test would not change the
outcome, or if running it on a different box would, it is not guarding what its
name says* — held. Add the corollary this ticket demonstrates: **a guard's
human-readable note is triage evidence, so it must describe what the guard DID,
not where its constants came from.**

### Verification

`python3 tools/twatch_bench_quiet_devtest.py` — 10 cases green (8 before), under
load, with `case_probe_returns_a_plausible_number` reporting a 241ms real probe
(~5x its idle time, i.e. the loaded box the old case could not survive).

## Log
- 2026-08-26 — resolved, commit 4ab326451.

### Addendum — the margin, measured

A natural-reproduction run (300 trials of the old case's exact arithmetic, box
at load 5-8 with a tier in flight) did **not** reproduce it: 0 failures on all
three assertions. That is a useful negative rather than a refutation, because it
came with the distance to the edge:

```
n=300 samples=3 iters=1000000
  r1==1.0 failed: 0
  r2>2.0  failed: 0   (needs t2 > t1/2)
  r3==1.0 failed: 0
  t2/t1  min=0.659 p01=0.728 med=1.000 max=1.750
```

The assertion fails at `t2/t1 <= 0.5`. The worst of 300 ordinary loaded samples
was **0.659** — within 32% of firing, with no headroom left for the load-14 full
tier under which it was actually observed red. A guard whose margin is 1.3x on a
busy box is not "flaky under exceptional conditions"; it is correct by luck at
the load it usually meets.

It also confirms the `min()`-of-three explanation over a simpler one: a spike
would have shown up as isolated low samples in 300 trials, and none appeared.
The failure needs a sustained window, which is why it tracks tiers rather than
noise.
