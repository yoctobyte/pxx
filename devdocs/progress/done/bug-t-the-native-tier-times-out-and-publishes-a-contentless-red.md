---
track: T
prio: 85
type: bug
blocked-by: []
summary: "Every native run on plexus since 14:28 today has ended at wall 3600.x — the one-hour cap — and publishes verdict RED. The last three carry new_red: [] AND still_red: [], i.e. a RED with nothing attributed: the run is killed before it can name anything. So Track T has had no usable verdict for six hours while looking, to --status and to every agent, exactly like a persistent regression. A timeout must not publish as RED."
---

# The native tier times out and publishes a RED with nothing in it

- **Type:** bug (Track T tooling — the report format and the tier budget).
- **Status:** done
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

---

## 2026-08-25 — item 3 is DONE (root cause found); items 1 and 2 remain

**This stopped being an outage today.** The "measure why it grew 8x first"
instruction in item 3 was the right one, and the answer was not load:

`test/test_c_gtk_call.pas` began hanging on 08-21 because the BOX changed, not
the repo. plexus was headless until borg's PSU failed on 08-20; gdm brought a
desktop up at 06:04:48 and at-spi-bus-launcher three seconds later. From then
on every test job inherited a live session bus, and GTK's accessibility bridge
blocked forever after `gtk_init`. Measured at 9170a6193, same binary each run:
hangs at 240s / at 90s built from pinned v374 / **0.31s with `NO_AT_BRIDGE=1`**;
the sibling `test_c_gtk.pas` passes in 0.21s. Unsetting
`DBUS_SESSION_BUS_ADDRESS` alone does NOT help — the bridge autolaunches a bus.

One hang cost three days because two Track T defects amplified it:
`learn_timeout()` recorded the kill time as the job's *duration*, and the
outgrown-class path doubled that into the next budget with nothing bounding the
result — 90s → 2902s → 3522s on record, a 7045s budget against a 3600s
deadline, honoured. Fixed in `2a129cfb9`: the a11y bridge is off in
`job_env()`, no budget may exceed half the deadline, a duration at the ceiling
is not recorded, and a metric already latched is dropped on load (that fired on
the live daemon: *"dropped a latched metric for test_c_gtk_call.pas (2902s…)"*).

**First completed native tier since 08-22**, on `dev` at c59796cd1: **468.4s**,
one attributable NEW-RED, two FIXED, `test_c_gtk_call.pas` PASS in 6.5s.

**What is still open here — and it is the part this ticket is actually named
after.** Items 1 and 2 were never about the GTK job:

1. a torn-down run still publishes `verdict: RED`, not `TIMEOUT` /
   `timed_out: true`, and `--status` still renders it as a failure;
2. an incomplete run still empties `still_red`, reporting never-reached jobs as
   fixed.

Both are report-format work and both survive this fix — the next hang, in any
job, publishes the same uninterpretable red. What has changed is the urgency:
the tier fits its budget again, so this is no longer six hours of blind fleet.
Whether it stays in `urgent/` is the coordinator's call, not mine.

## Items 1 and 2 fixed, 2026-08-25 (Track T)

Both report-format defects are closed. Item 3 (the budget) was closed
separately and differently than this ticket expected — see below.

**1. A timeout is its own verdict.** `testmgr.verdict_for()` maps the deadline
teardown's exit code (`TIMEOUT_RC = 124`, what `timeout(1)` uses, so it collides
with neither 1 nor 130) to `verdict: TIMEOUT`. The report JSON always carries
`timed_out`, `deadline` and `unreached`, so a consumer tests a field instead of
pattern-matching `wall` against a deadline it has to guess — which stopped being
guessable the moment the deadline began scaling with the core budget. The
markdown opens with a banner saying the run has NO verdict, how many jobs it
never reached, and that unreached is not fixed. `--status` renders it as
"TIMEOUT — no verdict, torn down at the deadline".

**2. An incomplete run may not evict anything.** The real mechanism was one
level below `still_red`: on a `full` run the job map is REPLACED, so jobs the
run "could have produced and didn't" are dropped. That rule's premise is that
the run was capable of running them — a teardown falsifies it, and every job the
clock cut off had its red silently deleted. An absent job then counts as having
passed (`prev_jobs.get(n, "pass")`), so it reads as fixed until it returns as a
NEW-RED. Incomplete runs now merge instead of replacing, skip the orphan prune,
file no tickets, open no ledger entries, and do not record `last_full` — so a
torn-down run can never again be mistaken for breadth coverage. The report gains
a **NOT REACHED — red at last look, unknown now** section listing them by name.

Guard: `tools/twatch_timeout_verdict_devtest.py`, 7 cases, including the two
that keep the fix honest — a legacy report with no `timed_out` field must read
as complete (every consumer uses the predicate to withhold an inference, so a
wrong True would freeze the map forever), and a complete run must get no banner,
because a disclaimer that appears on ordinary reds trains the reader to skip it.

**On item 3, the budget: the diagnosis in this ticket was incomplete.** The 8x
growth was a GTK at-spi bridge hang, host-coupled to this box becoming a
workstation on 08-20 — fixed in `2a129cfb9` (`NO_AT_BRIDGE=1` / `GTK_A11Y=none`
in the job environment, plus the metric-healing and per-job-ceiling guards that
stop a kill time from being learned as a duration). The ticket's instinct to
measure first — "a genuine hang in one job looks exactly like this from the
outside" — was right, and it was a hang.

A second, unrelated budget defect surfaced while fixing this one: the 3600s
deadline is a WALL-CLOCK number and did not move when the watcher was throttled
to 6 of 12 cores. The matrix is ~24000 cpu-seconds, so it cannot fit an hour at
any packing — the ceiling was unsatisfiable by construction and every breadth
run would have been torn down at the same minute. `scaled_deadline()`
(`b61125007`) stretches the default by the throttle factor; an explicit
`--deadline` is untouched, and the per-job ceiling is a fraction of the result
so it follows automatically.

Follow-up NOT done, deliberately, and worth its own ticket if it bites: a sha
whose only run TIMED OUT still counts as "tested" for staleness purposes. That
is the wrong direction (it claims coverage the run did not produce), but it is a
separate mechanism from the report format and expanding scope at the end of a
session is how the next incomplete fix gets written.

## Log
- 2026-08-25 — resolved, commit PENDING-COMMIT.
