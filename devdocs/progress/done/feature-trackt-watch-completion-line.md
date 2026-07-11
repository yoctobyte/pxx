---
prio: 55
---

# trackt watch: print timestamped completion line per finished suite run

- **Type:** feature (Track T tooling — `tools/trackt.py` live view).
- **Requested:** 2026-07-11 by user.

## State
`trackt watch` (and the attach view of bare `trackt`) renders a single
in-place progress line while a suite runs. When the run finishes the line
is overwritten by the next phase/idle state — nothing persistent tells you
*when* a suite completed or with what result. You have to go dig in
`tstate/<host>.json` or the web UI history.

## Wanted
When a test suite run completes, the watch view prints a **persistent
timestamped line** with the results, e.g.:

    [2026-07-11T14:03:22Z] borg full GREEN 118s bfc0a6b16fb2

including NEW-RED / FIXED job names when present, and (optionally) the
commit hash — `--no-sha` suppresses it.

Implementation note: the completion facts are already published — twatch
appends one JSON line per finished run to `tstate/runs-<host>.ndjson`
(sha, date, tier, verdict, wall, new_red, fixed). The watch loop just
needs to tail those files and print new rows; no daemon change needed.

## Gate
Track T tooling gate: behavior verified against a scratch state dir;
`tools/testmgr.py --tier quick` unaffected (no testmgr change).

## Log
- 2026-07-11 — resolved, commit b3c8bdcb.
