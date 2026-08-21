---
track: T
prio: 70
type: bug
blocked-by: []
summary: "Every native run on plexus since 14:28 today has ended at wall 3600.x — the one-hour cap — and publishes verdict RED. The last three carry new_red: [] AND still_red: [], i.e. a RED with nothing attributed: the run is killed before it can name anything. So Track T has had no usable verdict for six hours while looking, to --status and to every agent, exactly like a persistent regression. A timeout must not publish as RED."
---

# The native tier times out and publishes a RED with nothing in it

- **Type:** bug (Track T tooling — the report format and the tier budget).
- **Status:** urgent
- **Opened:** 2026-08-21 21:5x, noticed by a Track A session checking whether
  its own pushes had been swept.

## The evidence

`devdocs/progress/tstate/runs-plexus.ndjson`, native tier, today:

| time | sha | wall | verdict | new_red | still_red |
| --- | --- | --- | --- | --- | --- |
| 11:33 | ef7f17d45 | 437.4 | RED | 2 | 6+ |
| 11:50 | 71bd9319d | 731.9 | RED | 0 | 6+ |
| 12:46 | f4dab5ffe | **3266.6** | RED | 0 | 6+ |
| 13:24 | a6105d12b | 2181.8 | RED | 0 | 6+ |
| 14:28 | de2de369e | **3600.3** | RED | 0 | 6+ |
| 15:30 | 99dcac2a2 | **3600.4** | RED | 1 | 6+ |
| 16:31 | 777bc43fe | **3600.3** | RED | 0 | 1 |
| 17:33 | 13f7e0a1c | **3600.5** | RED | 0 | **0** |
| 18:35 | d7b5113da | **3600.3** | RED | 0 | **0** |
| 19:37 | 69e61a7bf | **3600.2** | RED | 0 | **0** |

Two things happen here, and the second is the reason this is filed as urgent
rather than as a perf note.

**1. The tier stopped fitting its budget.** Wall time went 437 → 731 → 3266 and
has been pinned at the 3600 cap for six consecutive runs. `wall: 3600.x` on
every one of them is not a coincidence — that is the cap, not a measurement.

**2. A timed-out run publishes a RED that says nothing.** The last three runs
report `new_red: []` and `still_red: []`. A RED verdict with an empty finding
list is not "everything failed"; it is "the run never got far enough to
attribute anything, and the still-red list emptied because those jobs were never
reached". The published report is 14 lines and contains no failure at all.

Downstream, that is indistinguishable from a real regression:

- `tools/twatch.py --status` prints `last 69e61a7bfda9 RED (native)`;
- CLAUDE.md tells every dev agent that a core-job red older than a day is a
  revert candidate;
- an agent that goes looking for the cause finds an empty report and has no way
  to tell a timeout from a genuine failure except by noticing that `wall` is
  exactly the cap.

## What to change

1. **A timeout is its own verdict.** Publish `verdict: TIMEOUT` (or `RED` plus
   an explicit `timed_out: true` and a line in the report saying which job was
   running when the clock ran out). `--status` should render it as "no verdict",
   not as a failure. This is the part that matters: a verdict nobody can act on
   is worse than no verdict, because it costs a session an hour to find out.
2. **Do not empty `still_red` on an incomplete run.** Jobs that were never
   reached are unknown, not fixed. Carrying the previous run's list forward
   (marked stale) beats silently reporting zero.
3. **Then the budget.** Either raise the native cap, shard it, or make the tier
   composition smaller. Worth measuring *why* it grew 8x first — a genuine hang
   in one job looks exactly like this from the outside, and load does not
   usually multiply a 437-second run by eight.

## Load context, stated honestly

Plexus is shared: a Track A session has been running `tools/gate.sh quick` all
evening, and each of those is ~2 minutes of all-core self-host compile every few
minutes. `gate.sh` itself warns about this in the other direction ("Track T
tooling is running here, expect 2-3x longer"). So contention is real and is part
of the picture — but the jump from 731s to 3266s happened at 12:46, and a
sustained 8x is a large amount to attribute to a neighbour. Measure before
concluding; do not assume it is only load, and do not assume it is only a hang.

## Consequence to record

**Nothing pushed to origin/master after roughly 14:00 today has a usable Track T
verdict.** That includes the whole of tonight's Track A run (90429d1b1 through
d54cebf07). Each of those landed on `make compiler/pascal26` fixedpoint +
`tools/gate.sh quick` GREEN, which is the documented per-fix loop, but the
breadth those commits are *supposed* to get asynchronously has not happened.
