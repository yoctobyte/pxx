---
prio: 40
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
