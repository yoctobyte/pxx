---
track: T
prio: 40
---

# chore(T): re-measure the tier ladder ratio — the matrix grew 37% and the default's own trigger has fired

- **Type:** chore (Track T tooling — watcher escalation ladder).
- **Filed 2026-08-28 by Track T (face 2).**
- **Not a defect.** The current default is correct as measured. What is stale
  is the *measurement*, and the code says so itself.

## The trigger fired

`twatch.py`'s `CONF_DEFAULTS` collapses the ladder to `native -> full` by
setting `mid_tier == tier == "full"`, and the comment above it is explicit
about why, with numbers (plexus, 2026-08-13):

    native   1224 jobs   170 s   (53% of the jobs, 21% of the wall)
    limited  1811 jobs   686 s   (78% of the jobs, 84% of the wall)
    full     2329 jobs   821 s

    "Running all three costs 1677 s per sha where native -> full costs 991 s
     for the SAME final coverage — 41% of the box spent buying 135 s of
     notice."

and it ends with an instruction:

    "RE-MEASURE THIS RATIO when the matrix grows again; it is the thing that
     went stale silently last time, because nothing ever re-checked it."

**It has grown again.** The v389 pin verify on 2026-08-28 ran **3202 jobs** at
the deepest tier, against **2329** at the measurement — **+37% in fifteen
days**, on the same box. The previous growth episode the comment records was
1084 -> 2343 in five weeks, so this is the same rate continuing, not a blip.

Nothing is known to be wrong. The point is that nobody knows whether it is
right, and the last time that was true the answer had already flipped.

## What to measure, and the one control that matters

Run `tools/testmgr.py` once per rung — `<native | limited | full>` — on one
sha, one box, one core budget, and record all three.

**Control for the core budget.** The 2026-08-13 numbers predate the 6-core
throttle; last night's deepest tier took ~1236 s wall at `--max-cores 3`,
against 821 s recorded for a smaller matrix at an unrecorded budget. Those two
numbers cannot be compared and this ticket should not pretend otherwise —
re-measure all three under one budget, record the budget, and replace the
comment's table wholesale rather than appending a row to it.

**Do it on an idle box.** Same constraint as
`chore-t-tools-devtest-is-one-job-that-runs-86-guards`: plexus is the owner's
workstation, and a three-rung sweep is tens of minutes of contention. That is
also why this is prio 40 and not higher — the cost of being stale is a
suboptimal rung, not a wrong verdict.

## What the answer changes

The question the ratio decides is whether `limited` earns a rung. The
2026-08-13 finding was that it does not, because the wall is dominated by a few
long serial jobs (`selfhost` alone was 131 s) that `limited` already pays in
full, while the deepest tier's extra jobs are parallel-friendly and nearly
free.

Both halves of that are exactly what 37% growth could move, and they can move
in opposite directions:

- if the growth landed on **parallel-friendly** jobs, the deep tier stayed
  cheap relative to `limited` and the collapse is still right — possibly more
  right;
- if it landed on **long serial** jobs, or if the core budget dropped enough
  that "parallel-friendly" stopped being free, `limited` becomes a genuinely
  cheaper preview again and the third rung is worth restoring.

A 3-core budget makes the second reading more plausible than it was at 6, since
parallel-friendly is precisely the property a core cap erodes. That is a
hypothesis, not a finding; it is written down so the measurement can refute it.

## Not a Track U decision, and I said otherwise first

This was initially handed to the owner as a judgment call, on the grounds that
it changes the watcher's CPU behaviour on their own workstation. That was
wrong, or at least premature: **no human judgment is needed to re-measure a
ratio.** The decision only exists if the measurement flips the answer, and if
it does, the numbers will make the call obvious. Filing it as a decision would
have asked the owner to arbitrate between two unmeasured options.

If the measurement *does* flip it, the resulting config change alters how much
CPU the watcher spends on the owner's machine — and **that** is a Track U
question, filed then, with numbers attached.

## Gate

Track T's own. The measurement is read-only, and the config change (if any) is
one key in `twatch.conf` plus a daemon restart. `mid_tier` is START-read, so a
change does nothing until the daemon restarts — check `code_fp` against the
clone's disk afterwards, per the two-hop rule
(`origin -> clone disk -> resident process`; `code_fp` answers the second hop
only).
