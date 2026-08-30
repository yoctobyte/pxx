---
track: T
prio: 55
type: bug
status: done
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

---

## 2026-08-30 — the n-gate half is now closed too. FIXED.

The fork this ticket was filed to escalate is dissolved rather than answered,
and that is the whole design:

> a fix must let a never-passed job earn room **without** letting a hang do the
> same, and today nothing in the stored data distinguishes "slow box" from
> "hung job" on a first encounter

Nothing distinguishes them, so **do not try to**. Bound the offer instead and the
distinction stops mattering: **one** grant, then the class figure forever. The
slow job passes at the raised budget and starts earning real metrics; the hung
job is killed at the second budget, the grant is spent, and nothing grows. The
cost of guessing wrong is one class-length run, once, and it is named in the
report both times. That is why this landed as work rather than as a Track U
`decide-*`.

### The mechanism

`UNPROVEN_ESCALATIONS = 1`, and a named rule beside it:

```python
def unproven_budget(m, cls_budget):
    """The one-off budget a job with no trusted metrics may have, or None."""
    if not m or not m.get("dur"):                    return None
    if int(m.get("n") or 0) >= METRICS_MIN_RUNS:     return None   # trusted path owns it
    if int(m.get("esc") or 0) >= UNPROVEN_ESCALATIONS: return None # grant spent, forever
    want = m["dur"] * OUTGROWN_MARGIN
    return want if want > cls_budget else None
```

A function and not three inline lines because it **is** the rule, and everything
around it in `Manager.__init__` needs a whole run to reach.

Four things make the bound actually bound, and each is a place it could have
leaked:

1. **Only the BUDGET comes from an unproven metric.** `exp_dur` / `exp_cores` /
   `est_mem` drive launch order and admission and still require a passing
   sample, so such a job is scheduled exactly as it is today and only gets more
   room to finish. An unproven metric must not be allowed to reserve memory.
2. **The GRANT is counted, not the timeout that prompted it.** Counting
   timeouts spends the offer on the run that merely *discovered* the job was
   slow — before anything had been offered — so a job would go straight from
   "no data" to "grant exhausted" without ever receiving one. `Job.escalated`
   carries the grant into `learn_timeout()`.
3. **A timeout at a granted budget records no duration.** That number is the
   budget *we* chose, not something the job revealed — the same argument the
   existing ceiling refusal makes one branch above. Recording it is what turns
   one grant into a doubling per run; it is precisely how 90s became 2902s
   became 3522s.
4. **A pass clears the counter.** It counts CONSECUTIVE unproven timeouts, not
   lifetime ones — a job that passes, is broken by a later commit and times out
   deserves the same one grant a new job gets, and a counter that never reset
   would silently deny it.

Reported by name on both events: the grant says what was observed, against what
budget, that it is once, and that a second timeout is the job's own signal;
the refusal says the budget reverts and that the job hangs, is misclassified, or
is too big for this box.

### Sized before it was written

Locally, 2818 metric entries: **1 at n=0, 79 at n=1, 2738 trusted**. Under the
most permissive assumption (every unproven job in the smallest class) at most
**17** would see a raised budget; in the `qemu` class where the ticket's jobs
live, 12. And the raise is a **ceiling only** — it cannot turn a passing job
into a failing one, it can only delay a hang's kill by one class-length run,
once.

"Unproven" is `n < METRICS_MIN_RUNS`, not `n == 0`, and that is deliberate. `n
== 0` is the ticket's title but it is the wrong set: a job rescued by the grant
passes once, reaches n=1 — still below the gate — and falls into the identical
trap one step later. Scoping to the set the main gate actually excludes is what
makes the escape complete rather than one-run-deep.

### Verified end to end with a second instrument, not only with its own guards

`tools/testmgr_unproven_budget_devtest.py`, 9 guards, each checked against its
own broken condition — bound removed → 3 red (sequence `[240, 480, 480, 480]`);
granted-timeout recording restored → 2 red (`[240, 480, 960, 960]`, the ratchet
itself); pass no longer clearing the counter → 1 red.

But the guards exercise `unproven_budget()` and the two `learn` methods, and
**not** the wiring in `Manager.__init__` — the exact sampling gap that made a
seven-guard suite agree with itself and still be wrong earlier tonight
([[bug-a-testtmp-defaults-to-a-path-every-checkout-shares]]). So the wiring was
observed directly: a metric was injected for a real quick-tier job
(`test-quick#19`, n=0, dur=120) and `testmgr --tier quick` was run.

```
testmgr: test-quick#19 has no trusted metrics on this box and was observed to
         need 145s against a 109s `unit` budget — raised to 240s for this run,
         ONCE. If it times out again the budget reverts to the class figure
         permanently, and that timeout is the job's own signal rather than a
         harness kill.
  PASS   test-quick#19    unit    0.8s
```

and the metric afterwards was `{'dur': 72.28, 'n': 1}` — **no `esc` key**: the
grant was offered, the job passed, and the counter went back to full. That is
the success path, observed rather than modelled. The injected key was restored
afterwards and only that key; the run's other learning is real and discarding it
would have been worse than the injection.

One instrument error, recorded for the same reason as the last: a chained shell
ran the third negative control against a file the previous control's restore had
not yet replaced, so it reported the *previous* control's two failures and the
guard actually under test stayed green. Re-run with the file state asserted
before and after the edit, it produced exactly one red, the right one. **The
apparatus's state is a measurement too.**

### Both recommendations landed, in the order the ticket gave them

The probe fix (preferred) landed earlier today and gave `calibrate()` real
range; this is the secondary, and it covers what the probe cannot — a single
job slow for its own reasons on one host, rather than a uniformly slow box.

### Gate

`make compiler/pascal26`: self-host fixedpoint verified, `9120da105197`.
`testmgr --tier quick` GREEN (the run above). Eight testmgr-adjacent devtests
green plus the new 9.

Note the box carried two other testmgr runs (`/home/neo/frankA` quick,
`/home/neo/trackt-watch` full) and load ~18 throughout, so no timing in any of
this is a signal.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
