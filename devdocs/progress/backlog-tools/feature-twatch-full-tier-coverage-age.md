---
prio: 35
---

# No signal distinguishes "full tier is lagging" from "full tier never completes"

- **Type:** feature (watcher observability). **Track T.**
- **Found:** 2026-07-20.

## What
The full matrix (cross targets + corpus + conformance) only backfills while the
repo is idle, and aborts the moment a push lands — by design:

> the full tier (cross targets + corpus) backfills while the repo is idle and is
> ABORTED (SIGINT, verdict discarded) the moment a new push arrives — pushes
> always preempt.

A full run takes ~45 min. On a day with pushes arriving faster than that, every
attempt is preempted and `last_full` never advances. `CLAUDE.md` explicitly
accepts hours of lag ("master MAY carry cross-target reds for hours — tstate is
the truth"), so lag is fine. What is missing is the ability to tell **lag** from
**starvation**: both look like a `full through <old-sha>` line, and nothing
reports how old that verdict is or how many attempts were discarded.

## Observed (both states, same day)
- Morning: `full through 3d46e52fc733 RED` — stale by days, and the RED was a
  harness collapse rather than a real result. Nothing indicated the full tier
  had not completed since.
- Midday: several full runs preempted in a row
  (`twatch: aborting full run (new work preempts it)`) during an active push
  window.
- Afternoon: an idle window let it finish — `full through 2b47f3662bb8 GREEN`.

So the mechanism self-heals on a normal day. The gap is that during the hours
it does not, a dev reading `trackt status` cannot see that cross-target
coverage has stopped advancing, and `tstate: UP` (a *native*-tier statement)
reads as blanket reassurance.

## Suggested
1. Report full-tier coverage age in `trackt status` / `--status`, e.g.
   `full through <sha> GREEN (4h old, 6 attempts preempted)`.
2. Count consecutive preempted full runs; surface it once it crosses a
   threshold — the same shape as the publish-health drop streak added in
   b8f74a58, which solved exactly this class of invisible-stall problem.
3. Consider an anti-starvation escape hatch: after N preemptions, let one full
   run finish (or run it against the newest sha regardless of pushes). Needs a
   judgement call on whether stale-but-complete beats fresh-but-partial — that
   part may be a Track U question.

## Prio note
Low: this is observability, not correctness, and the mechanism demonstrably
recovers during idle windows. It earns its place because the *morning* case
looked identical to the healthy case, and that is precisely the failure mode
the watcher exists to eliminate.

## Related: `--status` reports DOWN while HEAD coverage is current (2026-07-20)

Same observability family, different symptom. `status()` walks commits newest
-> oldest and reports DOWN on the first one that needs testing, is not in the
`tested` set, and is older than the grace window. But the watcher tests
**HEADs**, not every individual commit — so on a busy day intermediate commits
are never individually gated, age past 45 minutes, and trip DOWN even though a
DESCENDANT HEAD tested GREEN and their content is therefore covered.

Observed twice today, e.g.:

```
ALERT: tstate: DOWN — 36fb2a553d7b untested for 48 min; run your own full gate
  ... while:
  watcher last tested : 50848b541ad6 GREEN (3 commits behind origin/master)
  36fb2a553d7b        : ancestor of 50848b541ad6 -> content covered
```

The verdict is defensible against the literal contract ("every commit older
than the grace window is tested by some host") but the ACTION it prescribes —
"run your own full gate" — is wrong in this state, and a dev who follows it
burns a full matrix for nothing. Worse, it desensitises: DOWN starts meaning
"probably nothing", which is exactly what a liveness signal must never mean.

Suggested: treat a commit as covered when it is an ancestor of a tested sha
whose verdict is known (that is what testing a HEAD actually establishes), and
reserve DOWN for genuine lag — the last verdict being stale, or HEAD having run
far ahead of the last tested sha. A per-commit-gating shortfall is still worth
reporting, but as a distinct, quieter line than "T is down, gate it yourself".

## Log
- 2026-08-03 — measured on xeon (`tools/tstate_stats.py`, 418 runs over 3 days),
  which corrects the number this ticket reasons from. A full run is **5.8 min
  median** (p90 6.6), not the ~45 min quoted above — that figure was borg's.
  Full-tier coverage reaches **42% of tested shas** with a **median 25.8 min**
  gap between successive full runs.

  So the starvation scenario is rarer than the ticket assumes: at ~6 min a run
  usually finds an idle window. It is NOT void, though — the max observed gap
  was **471 min (7.8h)**, which is exactly the invisible state described here,
  and nothing yet distinguishes it from healthy lag. Prio unchanged; what
  changed is that the numbers now exist, so suggestion 1 (report coverage age
  and preemption count in `trackt status`) can be built against real thresholds
  rather than a guess.
