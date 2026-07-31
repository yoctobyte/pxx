---
summary: "a new watcher host's first run auto-files a bogus 17-job cascade ticket; NEW-RED is meaningless without a per-host baseline"
type: task
track: T
prio: 60
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
