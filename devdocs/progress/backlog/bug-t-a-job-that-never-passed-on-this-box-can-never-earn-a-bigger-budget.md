---
track: T
prio: 55
type: bug
status: backlog
blocked-by: []
found: 2026-08-30
found-by: claude@plexus (Track T face 2), while closing regression-cascade-154d1aa3fba6
summary: "learn_timeout() raises a timed-out job's expected duration so 'the next run gets room', but deliberately leaves n=0, and the only consumer of that duration is gated on n >= METRICS_MIN_RUNS. So the raise is written and never read for a job that has NEVER PASSED on this host -- which is precisely the job it cannot rescue. calibrate() cannot cover for it either: it returns max(1.0, dt/0.35) and plexus measures 0.26s, so the floor is the answer on every box measured so far, and a 2010 Westmere gets the same budgets as a 2013 Ivy Bridge."
---

# A job that has never passed on this box can never earn a bigger budget

## How it was found

Closing `rejected/regression-cascade-154d1aa3fba6` — an 18-job cascade filed
from the watcher box `seven` against twelve innocent Track R commits. Fourteen
of the eighteen went green once the box was provisioned. Of the four left,
**three have never passed on `seven` at all** (`job_last_pass` empty), and two
of those are TIMED OUT rather than failed.

The triage on that ticket called them "duration signals, landing within 0.4% of
their budgets" and asked for "per-box budget review". That framing is right
about the symptom and wrong about the cause, which is not a budget table.

## What is actually wrong — two facts, both read off the source and the state

### 1. The raise is written and never read

`tools/testmgr.py:3141 learn_timeout()` exists for exactly this. Its docstring
says it raises the stored expectation *"so the next run gets room"*, and the
comment block above its call site (`:3120`) records the incident it was written
for — `test-uforth` learned 17.8s, grew to 1416s, and timed out forever because
`learn()` only runs on a PASS.

But it ends with:

```python
m["n"] = int(m.get("n") or 0)      # not a passing sample; do not count
```

and the **only** consumer of the duration it just raised is:

```python
# tools/testmgr.py:2692
if m and m.get("n", 0) >= METRICS_MIN_RUNS:      # METRICS_MIN_RUNS = 2
    j.exp_dur = m["dur"] * scale
    ...
    if j.exp_dur >= j.timeout:                   # the "outgrown" escape
        j.timeout = j.exp_dur * OUTGROWN_MARGIN
```

Falling out of that branch lands on `:2727`, `j.timeout = cls_to * scale` — the
flat class figure.

So the rescue works for a job that **used to pass and got slower** (uforth: n=5,
branch live). It does nothing for a job that has **never passed on this host**:
n stays 0 forever, `dur` is raised on every run and read on none, and the job is
killed at the same class budget in perpetuity. `test-uforth` was the case that
got fixed; the case that looks identical from the outside was not.

Verified there is no other reader: `m["dur"]` is consumed at `:2693` (behind the
n-gate), `:2831` (`heal_latched_metrics`, which only *deletes*), `:3160`/`:3162`
(learn_timeout itself) and `:3232` (`learn()`, pass-only).

### 2. The calibration that should have absorbed this is inert

`calibrate()` (`:3581`) times one `test/hello.pas` compile and returns
`max(1.0, dt / PROBE_REF)` with `PROBE_REF = 0.35`.

Measured on plexus (Xeon E5-2620 v2, 2013, 12 threads), three runs of the exact
probe: **0.25s / 0.27s / 0.26s** → `max(1.0, 0.74)` = **1.0**. Not a
measurement — the floor.

`seven`'s own full-tier report records `scale: 1.0` too
(`tstate/reports/20260829T220513Z-f2706f4-seven.md`), and `seven` is a dual
Xeon E5645 (Westmere, 2010, no AVX). **The two boxes therefore receive
byte-identical budgets**, and the floor is doing all the work on both.

The floor itself is correct (never shrink a budget below the reference box).
The problem is resolution: a 0.26s single-threaded compile, dominated by process
startup and page cache, has almost no dynamic range, and the budgets it scales
govern **qemu-user emulation** and a 93-script Python suite — work whose cost
tracks single-core IPC and guest instruction mix, where a 2010 Westmere and a
2013 Ivy Bridge are much further apart than 0.26s vs ~0.33s.

## Why it matters beyond three jobs

A permanently-red job on one box is not a quiet inefficiency. It enters
`new_red` on the run that first sees it, and `file_cascade_ticket` takes
`new_red` wholesale — so it lands on the board at prio 70 naming a range of
commits it cannot have been caused by. That is one of the four reds that kept
`regression-cascade-154d1aa3fba6` open, and it is a **standing** contribution:
the job will time out on every future full tier on `seven` and can never clear.

`seven` is, as of this writing, the box publishing the **newest completed full
tier in the fleet** — the only current source of cross-target truth. Budgets
that are wrong there are wrong where it costs most.

## The fork — why this is a ticket and not a patch

Both guards in this area are load-bearing and they pull opposite ways.

The n-gate is not an oversight; it is what stops a **hang** from ratcheting its
own budget. `heal_latched_metrics` (`:2818`) documents that exact climb
happening for real — `test_c_gtk_call.pas` went 90s → 2902s → 3522s off the
outgrown path while its three sibling GTK tests sat at 7-8s.

So a fix must let a never-passed job earn room **without** letting a hang do the
same, and today nothing in the stored data distinguishes "slow box" from "hung
job" on a first encounter. That is the decision this ticket is asking for.

## Recommendation (not a decision)

**Preferred — fix it at the source, in the probe.** Give `calibrate()` dynamic
range that covers the workload it scales: keep the hello.pas compile and add a
short **qemu-user** run, because the qemu class is where the host gap is widest
and two of the three affected jobs are in it. A box that is 1.9x slower under
emulation then gets 1.9x budgets everywhere, no per-job risk is taken, and the
n-gate stays exactly as it is. This also fixes every *other* slow box the fleet
ever enrolls, which is the recurring shape here (`seven` is the second fresh box
to file a mass false cascade; `rejected/regression-cascade-110774a14648` was the
first).

**Secondary, if the probe fix is not enough.** Allow a job with **no metric at
all** on this host exactly one bounded escalation — budget `cls_to * scale`,
then `observed * OUTGROWN_MARGIN` once, then stop — capped by the existing
`deadline * MAX_JOB_DEADLINE_FRAC` clamp and **named in the report**, so a
timeout at the raised budget reads as a real signal rather than another
harness kill. One escalation cannot ratchet; a hang is killed at the second
budget and stays killed.

**Not recommended:** raising the class figures. The classes are per-workload and
correct on the reference box; making them big enough for the slowest box in the
fleet costs every fast box its hang detection.

## Repro

```
# the inert calibration, on any box in the fleet so far
for i in 1 2 3; do /usr/bin/time -f %e ./compiler/pascal26 test/hello.pas /tmp/probe26; done
# -> ~0.26s against PROBE_REF=0.35, so max(1.0, 0.74) = 1.0
```

```
# the unreadable raise
sed -n '3141,3170p' tools/testmgr.py     # learn_timeout: m["n"] stays 0
sed -n '2690,2730p' tools/testmgr.py     # the consumer: gated on n >= 2
```

State: `devdocs/progress/tstate/seven.json` — `job_last_pass` is absent for
`test-aarch64#src:test/test_parallel_reduction.pas`, `tools-devtest#00` and
`test-sqlite-threads-aarch64#src:compiler/.pascal26.fixedpoint`, all three red
in every full tier that box has run.

## Related

- `rejected/regression-cascade-154d1aa3fba6` — the cascade this fell out of.
- `backlog/bug-t-a-test-targets-timeout-class-is-decided-by-a-substring-and-is-right-by-accident` — the *other* half of "which budget does this job get", and independent of this one: that ticket is about picking the wrong class, this one is about the class figure never being scaled to the box.
- `done/task-t-suppress-autoticket-until-host-baselined` — the guard that was supposed to stop a fresh box's first sweep from filing a cascade. It shipped, and `seven` filed one anyway.

---

## PARTIALLY FIXED 2026-08-30 — the probe now has range; the n-gate is untouched

The "preferred" recommendation above landed. `calibrate()` now runs **two**
probes and combines them with `max()`:

- the existing `hello.pas` compile (also the compiler-health check), and
- a generated fixed compute loop, cross-compiled to aarch64 and **run under
  qemu-user** — 8,000,000 iterations, ~0.36s on the reference box.

The emulated axis is where the fleet's boxes actually differ, and it is where
the false timeouts landed. Measured on plexus after the change:

```
testmgr: budgets x1.00 (native probe 0.58, emulated probe 0.89) — at the floor,
         so neither probe raised it
```

Three things that line does that nothing did before: it reports the scale on
**every** run, it shows the two components separately, and it **says out loud
when the floor is the answer**. "The floor is the answer" is precisely what went
unnoticed for the life of this function; a line that appeared only when the
probe found something could never have reported finding nothing.

Cost: ~0.65s added to every testmgr invocation (a cross-compile plus the
emulated run) — ~2% of a `quick` tier, ~0.6% of `native`. Every failure path in
`calibrate_emulated()` returns **None = no opinion**, never a small number: no
emulator on PATH, a cross-compile that does not build, a run that exits nonzero.
A box with no qemu at all now skips those jobs anyway (see below).

Guards: `tools/testmgr_calibrate_range_devtest.py`, 15 checks — and its docstring
says which of them are on new behaviour rather than letting the count speak.

**Expected effect on `seven`, stated as expectation and not as measurement:** if
it is ~1.5x slower under emulation than plexus, its qemu budget goes 240s ->
~360s and `test-aarch64#test_parallel_reduction` (240.4s) passes. That is a
prediction; the box's next full tier is what settles it, and the `scale:` field
in its report header is where to read the answer.

### What is still open, and it is why this ticket stays in backlog

**The n-gate is untouched, deliberately.** `learn_timeout()` still leaves `n=0`
and its consumer still requires `n >= METRICS_MIN_RUNS`, so a job that has never
passed on a box still cannot earn a budget from its own observed duration. The
probe fix routes *around* that for the case where the box is uniformly slow; it
does not fix a single job that is slow for its own reasons on one host.

**And one limitation the fix introduces, stated because the scale is a single
global number:** a box slow only under emulation now gets generous *native*
budgets too. A budget is a ceiling, so that costs hang-detection latency — one
class-length run before the kill — not a wrong verdict. The converse case, a box
slow only natively, is still served by a probe with ~1.3x of range, and no
second probe helps it. Per-class scales would; that is a larger change than this
one and is not attempted here.

### Related, landed the same day

`apply_host_tool_skips()` — a job whose qemu emulator is not on PATH is now
**skipped with a reason naming `tools/install_qemu.sh`**, rather than red. Same
family as this ticket (a host fact reported as a defect in the tree), and it is
what makes enrolling `test-xtensa` into the full tier safe on a box that never
installed qemu-xtensa.
