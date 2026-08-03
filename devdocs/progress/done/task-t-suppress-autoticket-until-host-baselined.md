---
summary: "a new watcher host's first run auto-files a bogus 17-job cascade ticket; NEW-RED is meaningless without a per-host baseline"
type: task
track: T
prio: 60
status: done
owner: claude@xeon
---

# Don't auto-file cascade tickets from a host's first run

- **Type:** tooling (Track T — `tools/twatch.py`, `autoticket`)
- **Found:** 2026-07-31, enrolling the xeon watcher box.

## What happens

`diff_jobs()` computes NEW-RED as *red now, green in this host's previously
recorded `jobs` map*. On a host's **first** run that map is empty, so
`prev_jobs.get(n, "pass")` defaults every unknown job to "pass" and **every red
is a NEW-RED**. With `autoticket=on` the watcher then files a cascade ticket
against whatever sha it happened to test.

xeon's first run did exactly this: 17 "newly red" jobs blamed on
`110774a14648`, a **tstate-only commit that touches no code**. All 17 were host
environment gaps (missing `libgtk2.0-dev` / `libsqlite3-dev` / `tk-dev` /
`libc6:i386`) plus a stale seed (see
[[task-t-seed-from-stable-defeats-rebuild]]). Rejected as
`rejected/regression-cascade-110774a14648.md`.

A false cascade ticket is worse than a false tstate row: it lands on the board
at `prio: 70`, names an innocent sha, and costs another agent a triage cycle.

## Fix

In `tools/twatch.py`, suppress **ticket filing** (not reporting) when the host
has no baseline to diff against:

- if `st["jobs"]` was empty before this run, publish the tstate report as usual
  but mark the verdict `BASELINE` and file **no** ticket;
- same guard when the red count exceeds some fraction of all jobs (a sweep that
  reds >N% of the matrix is an environment or infra fault, not a code
  regression — a commit that breaks 17 unrelated subsystems at once essentially
  does not exist);
- keep the first run's results as the baseline so the *second* run produces
  real NEW-RED signal.

Operationally, `trackt setup` should also leave `autoticket` off until the host
has one clean baseline, and `trackt status` should show whether the host is
baselined yet.

## Related

The same "no baseline ⇒ everything is new" defaulting is why a host that has
never run cannot distinguish "this test never worked here" from "this test just
broke" — which is the question the cutover comparison exists to answer.

## Log
- 2026-08-03 (`claude@xeon`) — both guards land in `twatch.publish()`, as one
  rule: **publish everything, file nothing you cannot stand behind.** The
  verdict, the job map and the report are written in every case; only ticket
  filing is gated.

  - **No baseline yet** — `had_baseline` is captured BEFORE `diff_jobs()`
    consumes it. On such a run no ticket is filed AND no ledger entries are
    opened: entries would name a sha that cannot have caused them, which is
    exactly the existing empty-range rule, so this reuses its reasoning rather
    than inventing a second one. The statuses still land in `st["jobs"]`,
    which IS the baseline the second run produces real NEW-RED against, so the
    ticket's "keep the first run's results" requirement is met by doing
    nothing special.
  - **Matrix-wide red** — more than `INFRA_FAULT_FRAC` (25%) of the reported
    jobs newly red suppresses the ticket as an environment fault. The cascade
    rule already collapsed such a sweep to ONE ledger entry; what was missing
    was the judgement that it is not worth a ticket at prio 70 against an
    innocent sha. This is the half that pays off on xeon alone, which is why
    it was built now while the multi-host work is parked
    ([[decide-t-queue-scope-2026-08-03]]).

  `--status` now shows `[NOT BASELINED — NEW-RED not meaningful yet]` on a host
  with no recorded job map, so a fresh enrollment's green is not mistaken for
  coverage — the operational half of the ask. The publish message says
  `BASELINE:N red` instead of `NEW-RED:...`, so git log carries it too.

  Not done, deliberately: leaving `autoticket` off in `trackt setup` until a
  host is baselined. The code guard makes the config knob redundant, and a
  default that must be flipped back on later is the same class of thing as the
  retire flag rejected in [[task-t-borg-open-regression-is-permanently-stale]]
  — something to forget.

  `tools/twatch_baseline_devtest.py` pins both guards, the strict boundary (a
  run exactly at the fraction still files), the empty-matrix case, and — as the
  documented premise — that `diff_jobs()` against an empty map really does mark
  every red as new.
- 2026-08-03 — resolved, commit PENDING-COMMIT.
