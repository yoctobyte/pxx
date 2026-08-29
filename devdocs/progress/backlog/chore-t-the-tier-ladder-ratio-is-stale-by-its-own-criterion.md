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

## 2026-08-28 — a second reason to touch `mid_tier`, found from the other side

While fixing the `-O3` attribution gap I hit `mid_tier` from an angle this
ticket does not cover, and it is worth recording here rather than opening a
third ticket.

`last_full` is **the last REPLACING run**, not the last `full` tier — the name
is a historical accident. Under the shipped default (`mid_tier == deep_tier ==
full`) the two coincide and nothing is wrong today. Configure `mid_tier` to
`limited`, which is exactly what this ticket contemplates, and they diverge: a
`limited` run would refresh `last_full`, and the BREADTH staleness banner reads
`last_full` to decide whether any cross target has seen the tree. A `limited`
run covers no cross target. The banner would go quiet on evidence that does not
support it.

So enabling `mid_tier` is not purely a scheduling change; it silently widens
what the breadth banner vouches for. `last_by_tier` (`ecacf87bd`) answers the
question exactly — newest COMPLETE run at each tier, exact match, never
`covered_tiers` — and the banner should be moved onto it **before** any
`mid_tier` experiment, not after.

This is the same shape as the gap that ticket fixed, and as the four-gate-tier
survey that missed `opt`: **a knob whose reach is not visible in the output it
governs**. Noted, not ranked up — one good analogy is not evidence, and the
ranking should follow the measurement this ticket already asks for.

---

## 2026-08-29 — the prerequisite this ticket names is DONE; the measurement is not

Two separate things in here, and only one of them was blocked.

**Done:** the `last_full` interaction recorded in the section above. The breadth
banner now reads `breadth_full_run()` — the newest COMPLETE run at the `full`
tier, exact match — instead of `last_full`, so configuring `mid_tier` can no
longer make it vouch for cross-target coverage that never ran. Split out and
closed as
[[bug-t-the-breadth-banner-vouches-for-cross-targets-on-a-run-that-covers-none]]
rather than folded in here, so this ticket does not read as partly done while
its actual subject is untouched. 4 guards, 2 mutations.

That was this ticket's own instruction — *"the banner should be moved onto it
**before** any `mid_tier` experiment, not after"* — and it is the half that
needed no box time at all.

**Still blocked, on the same thing as last time:** the three-rung measurement.
plexus was at **load 17.33** on twelve cores when this was picked up, against the
load 12 that deferred
[[chore-t-tools-devtest-is-one-job-that-runs-86-guards]] the same way. This
ticket asks for tens of minutes of contention on the owner's workstation, and a
ratio measured under ~1.4x oversubscription cannot answer the question it is asked
— *"is `limited` a genuinely cheaper preview"* is precisely a question about
what contention does to parallel-friendly jobs.

### The pattern is now three tickets deep and worth naming

Three Track T tickets have the shape *"first, measure this on an idle box"*, and
plexus is never idle: it is the owner's workstation **and** it carries the
watcher. A step gated on a condition that does not arrive is indistinguishable
from a step nobody does, and in this ticket's case the staleness it exists to
correct goes on compounding meanwhile — the matrix grew 37% in fifteen days and
will have grown again by the time a quiet box appears.

**Seven changes this.** A second box means a measurement host that is not
someone's desktop, and this ticket plus the `tools-devtest` one are the two
best first jobs for it: both are pure measurement, both are read-only, both are
currently stuck for exactly one reason that seven removes. Worth handing over
together with that framing rather than as two unrelated stale chores.


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
