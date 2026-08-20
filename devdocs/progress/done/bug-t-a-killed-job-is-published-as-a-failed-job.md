---
track: T
prio: 70
type: bug
blocked-by: []
summary: "testmgr's teardown() marked every in-flight job `fail`. That status is now read by two consumers that outlive the run — the published report and the resume partial — so a job that was merely killed alongside a real failure is published as a failure of its own, and twatch's merge (anything not PASSLIKE is red) files the fan-out as NEW-REDs. Reproduced in 6 seconds on the published path; observed on the live clone in a partial holding selfhost-fixedpoint#00 as a 26.7s `fail` after an 8-second run."
status: done
---

# A job that was KILLED is published as a job that FAILED

- **Track T** — `tools/testmgr.py`. T's own tool, so T fixes it.
- **Found by** plexus-T on 2026-08-20 while measuring why
  [[bug-t-the-push-rate-starves-breadth-coverage-entirely]]'s partial-carry
  still reads near zero. The starvation measurement is over there; this is what
  reading the partials turned up on the way.

## The defect

`Manager.teardown()` kills everything in flight and then does:

```python
for job in self.running:
    job.status = "fail"
```

That was **harmless for years**, and it is worth saying why: teardown fires when
the run is already over — SIGINT, the global deadline, a self-host red,
`--fail-fast` — and the only consumer of the status was this process's own exit
code, which is 130 or 1 either way. The status was cosmetic.

Two later consumers made it load-bearing:

1. **The report**, which outlives the run. The self-host-red and `--fail-fast`
   teardowns *publish* theirs — that is the whole point of "tear down and let
   the caller publish NOW". Every job that merely happened to be running
   alongside the real failure went out as a failure of its own, and twatch's
   merge (`PASSLIKE = ("pass", "skip")`, everything else is red) files that
   fan-out as NEW-REDs.
2. **The resume partial**, which is that report persisted. `carried_red()` makes
   a carried `fail` gate the next slice *by design* — "a carried RED is still a
   RED" — so a killed job would redden a run that never re-attempted it.

**A value that was cosmetic in one consumer became authoritative in a second.**
Nothing about teardown changed; what changed is who reads it.

## Measured, both halves

**The published path, reproduced in 6 seconds** (`--deadline 6` fires the same
teardown as SIGINT), before and after, same command:

```
BEFORE -> verdict RED
    pass test-quick#00
    fail test-quick#01  test/quick_canary_nilpy.npy  dur=5.5     <- killed at 5.5s of a 90s budget
AFTER  -> verdict RED
    pass test-quick#00
    (summary line: "1/16 pass, 1 killed mid-run, no verdict, 14 not run")
```

The nilpy canary was not failing. It was 5.5 seconds into a 90-second budget
when the deadline killed the run, and it was published as a red.

**The resume path, observed on the live clone**
(`/home/neo/trackt-watch/.testmgr/resume/ef3ea948003d-full.json`, saved
2026-08-20T02:36:28Z): 14 `fail`, 1 `pass`, from a full run aborted **eight
seconds** after it started. Among the fourteen:

```json
{"name": "selfhost-fixedpoint#00", "status": "fail", "dur": 26.7, "reason": ""}
```

That is the one red in this system that triggers `make revert`. It had not
failed; it had been killed. The partial was never carried — see the sibling
ticket for why breadth partials structurally cannot be — which is the only
reason this had not already fired.

The pin-verify path is the one that *does* carry (`carried_runs: 1`, 15 jobs),
and it keys on a frozen sha, so it is the path where a preempted slice's
`selfhost-fixedpoint#00` would have been carried into the next one.

## The fix

`teardown()` marks a killed job **`interrupted`**, and `interrupted` joins
`queued` / `skipped` / `carried` in the new `NO_VERDICT` tuple — extracted as
`reportable(jobs)` so it can be guarded without a full tier, the same reason
`report_job()` was extracted.

Omitted rather than emitted with an honest status, and that is deliberate:
twatch treats any status outside `PASSLIKE` as red, so a status it does not
already know would arrive as a NEW-RED — the bug wearing a new name. Omitting
lets the merge keep the job's **previous** verdict, which is the truthful answer
for work this run did not decide. The existing comment for `skipped` already
argued exactly this; `interrupted` is the same argument.

Three consumers had to agree, and they disagree on purpose:

| reader | question | counts `interrupted`? |
| --- | --- | --- |
| `done_count()` | is it still RUNNING? | **yes** — it stopped |
| `live_progress()` | was it DECIDED? | **no** — nothing judged it |
| `load_resume()` | may this verdict be carried? | **no** — allow-list, not deny-list |

`load_resume` needed no change: it was already an allow-list of judgements
(`pass`/`fail`/`timeout`/`skip`). That is what makes carrying a real `fail`
safe, and it is now commented as load-bearing rather than incidental.

The summary line names the count — `1/16 pass, 1 killed mid-run, no verdict` —
because the jobs sit in the denominator and are absent from the report, so this
is the only place they are visible at all. Same argument as the `not run (a job
they depend on failed)` term, which exists because `0/167 pass` was literally
true and invited the reader to go looking for 167 broken tests.

## Guards

`tools/testmgr_interrupted_status_devtest.py` — **12 guards**, and both halves
of the fix were neutered to confirm none is vacuous:

- reverting `teardown()` to `"fail"` reddens 5;
- dropping `"interrupted"` from `NO_VERDICT` reddens 3.

Including the two that would catch a fix that over-reached: a job that really
failed before the teardown keeps its `fail`, and a carried real `fail` still
reddens the run.

## Gate

`make tools-devtest` — 55 guards green.

## Log
- 2026-08-20 — resolved, commit PENDING-COMMIT.
