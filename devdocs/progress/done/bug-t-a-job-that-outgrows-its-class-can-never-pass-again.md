---
track: T
prio: 60
type: bug
blocked-by: []
commit: PENDING-COMMIT
claimed-by: plexus-T
summary: "A job's class timeout is the budget for an UNMEASURED job, and `min(cls_to * scale, ...)` kept it as a ceiling over a MEASURED one. A job whose own EWMA passes its class budget is then killed at that ceiling on every run forever, and `learn_timeout` cannot rescue it because the same `min()` clamps the raise it just stored. Measured on `lib-test#src:test/crtl_exp2.c`: EWMA 107.5s under a 90s `unit` budget — RED in every full tier for three days while passing standalone in 73.5s."
status: done
---

# A job that outgrows its class can never pass again

Filed and fixed 2026-08-19 by Track T (plexus-T), from the standing open
regression on `lib-test#src:test/crtl_exp2.c`.

## The defect

`Manager.__init__` gives a job with trusted metrics a *tighter* budget than its
class default, so a hang is caught long before the coarse class figure fires:

```python
j.timeout = min(cls_to * scale,
                max(45.0, j.exp_dur * 10 + 15, cls_to * scale / 4))
```

The `min()` is deliberate and one-directional: measurement may only *shrink* the
budget. The case nobody wrote down is **`j.exp_dur` itself passing
`cls_to * scale`**. The job is then handed a budget it is already known not to
fit inside, and it is killed at the ceiling on every run, forever.

`learn_timeout()` looks like the rescue and is not. It raises the stored duration
after a kill, and its comment says the point is that "the next run gets room" —
but the next run rebuilds the budget through the same `min()`, which clamps the
raise straight back off. Its own safety note ("the class ceiling still bounds the
next budget, so the worst case is one class-length run") is exactly the bug seen
from the other side: for this job the ceiling *is* the binding constraint, so
the mechanism designed to give it room is a no-op.

## Why it read as a load flap for three days

This job passed standalone and failed in the tier, which is the signature of
contention — so it was triaged as contention twice, by two agents, and written
up as a duration signal with an arbitrary bisect landing.

The measurements say something sharper, and it inverts the intuition:

| | |
| --- | --- |
| standalone, idle box, `jobs=1` | **73.5s** — passes, and testmgr prints `NEAR BUDGET (74s of 90s)` |
| learned EWMA on `plexus` (n=13) | **107.5s** |
| `unit` class budget | **90s** |
| budget when ANOTHER CLONE shares the box | 90 x `PEER_TIME_FACTOR` = **180s** |

What makes the job slow in a tier is **intra-run parallelism** — 24 jobs on 12
cores — and intra-run parallelism does not extend anything. Only a *peer clone's*
run does (`effective_timeout`). So:

> **the job passed when the box was SHARED and failed when it had the box to
> itself.**

That is why "it's load" survived triage: it is load, and the sign is backwards
from the one everybody checked for.

## What each earlier reading got right, and where it stopped

- [[bug-t-a-timeout-bisects-to-an-innocent-commit]] — **right** that the bisect
  landing is arbitrary and the accused commit innocent. Its summary also says
  *"every step of the job runs clean standalone in seconds"*, which is true and
  is the sentence that closed the investigation. Every step was checked; the
  **job's total against its own budget** never was.
- [[chore-t-split-lib-test-into-jobs-that-name-what-failed]] — **right** that the
  key misdescribes what failed, and right to rerank on the crying-wolf argument.
  It treats the red as false, though. It is not false: the job cannot pass in a
  full tier. Splitting *would* have fixed it as a side effect, by making each
  piece small enough to fit — which is worth knowing, because it means the two
  tickets were never independent.

The instrument was reporting this the whole time and could not be heard:
`NEAR BUDGET` fires only on a **pass**, and only into stdout. Once the job
crossed the line and started timing out, the one warning built to catch this
(added by the parent ticket, for this job) went **silent** — precisely when it
became true. A signal that is emitted only in the state where it is not yet
needed is the `167/167 pass, 2 skip` shape one level down: see the
never-changed-number diagnostic in `devdocs/dev/track-t.md`.

## The fix

`tools/testmgr.py`:

1. **A measured job's budget is never below what it is measured to need.** When
   `exp_dur >= timeout`, the budget becomes `exp_dur * OUTGROWN_MARGIN` (2.0).
   The class figure goes back to being the default for an unmeasured job rather
   than a ceiling over a measured one.
2. **The raise is announced by name, at startup and again in the report.** A
   silently inflated budget would bury the misclassification that caused it — a
   job past its class wants splitting or reclassifying, and the bigger number is
   only what stops it being red in the meantime. `NOTE` lands beside the
   co-tenancy note, so it reaches the published tstate report and not just the
   scrollback.
3. **A timeout now prints the expectation next to the budget** (`budget was
   215s, expected 108s`). A budget alone reads as a hang; the pair is what
   separates "stuck" from "this job has been growing for weeks".

Exactly one job of 2742 was in the state on this box, so the change moves one
budget today. It is filed as a bug rather than a tuning chore because the failure
mode is silent, permanent, and indistinguishable from a regression by design:
the tier goes red, the bisect converges on an innocent commit, and every
individual step of the job passes when a human checks it.

## Gate

- `python3 tools/testmgr_outgrown_class_devtest.py` — new; covers the raise, the
  announcement, the untouched cases (comfortably-inside, too-few-samples, a
  bigger class), and `scale`.
- `tools/testmgr.py --tier full` green, with `lib-test#src:test/crtl_exp2.c`
  passing **in the tier** rather than only standalone, and the run confirmed
  solo (no co-tenancy NOTE) so the pass cannot be credited to a peer's
  `PEER_TIME_FACTOR` stretch.

## Follow-up, filed not implied

The `unit` classification of that job is still wrong — 23 recipe lines, five
`xvfb-run` GUI programs and two CPython oracle diffs are not a build-and-run
unit test. That is [[chore-t-split-lib-test-into-jobs-that-name-what-failed]],
which now has a second reason to happen and a corrected premise; updated there
rather than restated here.

## Log
- 2026-08-19 — resolved, commit c99f15692.
