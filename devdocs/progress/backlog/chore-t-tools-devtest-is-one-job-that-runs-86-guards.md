---
track: T
prio: 45
status: backlog

---

# chore(T): `tools-devtest#00` is ONE job that serially runs 86 guards, and every number about it is now wrong

- **Type:** chore (Track T tooling — testmgr job shape / Makefile recipe).
- **Filed 2026-08-28 by Track T (face 2)**, from its own budget diagnostic
  firing on a quiet box during the v389 pin verify.
- **Owner lane:** T (`Makefile` recipe + testmgr class table). Not a compiler
  bug; nothing here is a lane's to fix but T's.

## The measurement

During the pin verify of v389 at the deepest tier (2026-08-28, host plexus,
testmgr pid 860008), the harness reported:

    tools-devtest#00 measured 251s against a 90s `unit` budget
    -> timeout raised to 502s for this run
    "the job belongs in a bigger class or should be split"

That is my own over-budget diagnostic doing exactly what it was written to do.
This ticket is the thing it was pointing at.

Three numbers that used to be true and are not:

| claim | where it is written | reality |
| --- | --- | --- |
| "~30s for the whole family" | `Makefile`, comment above `tools-devtest:` | **251s** measured |
| "runs 46 guard scripts" | `tools/testmgr.py`, note above `REASON_MAX` | **86** files match `tools/*devtest*.py` |
| `unit` class, 90s | testmgr `CLASSES` | exceeded by 2.8x |

Nobody wrote a wrong number. The family grew — six guards landed on the night
of 2026-08-27 alone — and the shape of the target is such that growth lands
entirely inside one job's wall time, where no estimate can follow it.

## Why the shape is the defect, not the numbers

`tools-devtest` is a shell `for` loop over `tools/*devtest*.py` inside a single
make recipe. testmgr sees **one** job. So:

1. **The budget cannot converge.** `dur` is EWMA'd toward a moving target that
   moves every time anyone adds a guard. The estimate is always behind, and
   "behind" here means the scheduler admits the job and then doubles its
   timeout — a workaround firing on a schedule.
2. **251s of strictly serial work sits in the critical path** of every tier
   that includes it on a 6-core box. These are 86 independent hermetic python
   processes: there is no reason for them to be serial except the recipe.
3. **A red names one of 86.** `REASON_MAX` capture was added precisely because
   `tools-devtest#00` = "fail" identified nothing; that mitigated the symptom
   by scraping the log. The job *name* still means "one of 86", which is why
   `regression-tools-devtest-00-2` needed a human to open the log and find
   `testmgr_hardcoded_tmp_devtest.py`.
4. **The growth is structural and will continue.** T adds a guard per defect
   found, by design. A shape whose cost is linear in guards-ever-written and
   whose parallelism is fixed at 1 gets worse every week it works correctly.

This is the same class as the defect the recipe's own comment already records
("an INCOMPLETE run reporting in the vocabulary of a complete one"): the
report's vocabulary is finer than its subject. There the fix was to tally
rather than stop at the first red. Here the fix is one level up — the *job* is
the wrong unit.

## Recommended fix

**One testmgr job per guard file**, named for the file rather than an index
(`tools-devtest#twatch_covering_devtest` and so on). That fixes all four at
once: each guard gets a budget it can actually hold, the family parallelises,
a red names itself, and adding a guard adds a job instead of extending one.

The alternative is fixed sharding, as `optdiff` does with 12 shards. It is
strictly worse here: it keeps the attribution problem (a shard names ~7 files)
and it re-introduces the moving-target estimate inside each shard. `optdiff`
shards because it sweeps ~900 *programs* with no natural per-file identity;
these 86 have names.

**Open question, deliberately not guessed:** per-file process overhead. If the
median guard is ~0.5s, 86 jobs of mostly-python-startup may cost more in
scheduler overhead than they save. **This is measurable and has not been
measured** — it needs `for f in tools/*devtest*.py; do /usr/bin/time -f "%e $f"
...` on an idle box, which is a ~250s CPU sweep and was not run tonight
because plexus is the user's workstation and the box was at load 12 under the
pin verify. Do that first; if the distribution is long-tailed (a few slow
guards, many trivial ones), the answer may be per-file for the slow tail and
one bucket for the rest.

## Not in scope

`bench_timing_devtest.py` stays excluded from the gate — load-sensitive by
construction, and the reasoning above the recipe still holds. Sharding does not
change that; if anything it argues for it, since a per-file job makes the
exclusion one skipped job rather than a `case` in a loop.

## Gate

Track T's own rule for its own tooling: the deepest testmgr tier green.
Specifically here, because the job COUNT changes: run a quick tier against a
scratch bare repo first and confirm nothing keys off `tools-devtest#00` as a
literal name. `devdocs/progress/tstate/**` history does — old entries name
`#00` and must stay readable. Check `repair_regressions` and the pinstatus
join before renaming anything.

---

## 2026-08-29 — parked again on the same precondition, and that is now the finding

Claimed, then released without implementing. The ticket's own first step is
*"measure per-file process overhead on an idle box"*, and the box is at **load
17.33** (twelve cores) — worse than the load 12 that deferred it when filed. A
per-file timing distribution measured under ~1.4x oversubscription is not a
distribution anyone should act on, and the whole point of the measurement is to
choose between per-file jobs and a bucketed tail.

Nothing implemented, because implementing without it is guessing at the one
question the ticket says not to guess at.

### The precondition has now failed twice, which changes the plan

**"Wait for an idle box" is not a plan on this machine.** plexus is the owner's
workstation *and* carries the watcher, and it has been at load >12 on both
occasions anyone came to do this. A step gated on a condition that keeps not
arriving is indistinguishable from a step nobody does.

The replacement is cheap and load-proof: **instrument the recipe to record each
guard's duration during the runs it already performs**, and read the
distribution off a few natural runs instead of commissioning a sweep. The data
wanted here is exactly what `make tools-devtest` is already doing 95 times in a
row — the only thing missing is that it does not write down how long each one
took.

That also fixes the measurement's own version of this ticket's defect: a sweep
run once by hand on a quiet box measures a machine state that never occurs in
production, whereas the recipe's own timings are the real ones, under the real
load, continuously.

Whoever picks this up: do the instrumentation first, let it ride for a few
runs, then decide per-file vs bucketed on data that describes the box the job
actually runs on. It is also the smaller change, and it is not load-sensitive.

### Current numbers, since they moved again

95 guard files (`86` in the ticket body, `46` in testmgr's note above
`REASON_MAX`, `~30s` in the Makefile comment). 94 green, 1 RED
(`testmgr_hardcoded_tmp_devtest.py`, the pre-existing NilPy `/tmp` race filed to
Track N). Three full runs today, each ~4 minutes wall.

The count in this ticket's title is already stale, which is its own argument.


### Correction, 2026-08-29 (same day): the box has TWELVE cores, not six

I wrote "six cores" above from the watcher's `--max-cores 6`, which is its own
budget, not the machine's. `nproc` is **12**. So load 17.33 was ~1.4x
oversubscription, not 3x — still loaded, and still the wrong condition for this
measurement, but I overstated it and the numbers are corrected in place.

**And the constraint has since moved.** The owner had plexus's watcher daemon
stopped this evening; load fell to **4.30** on those 12 cores (5-min 8.84,
15-min 10.71 — the trend is the daemon leaving). The box's largest continuous
consumer is gone.

That does NOT make this measurable right now: plexus is still the owner's
workstation, six sessions are live, and load 4.30 is not idle. But the reason
this ticket has been deferred twice is materially weaker than it was this
morning, and it is the first time that has been true. Whoever picks it up
should re-read the load rather than inherit "blocked on a busy box" from here.

- 2026-08-29 — the count in the title is now stale: `verify_assertions_devtest.py`
  added 9, so the single job runs 95. Noted rather than retitled, because the
  number is the symptom and the shape is the ticket — and it will be stale again
  by the time anyone reads this, which is itself part of the argument for
  splitting the job rather than counting it.
