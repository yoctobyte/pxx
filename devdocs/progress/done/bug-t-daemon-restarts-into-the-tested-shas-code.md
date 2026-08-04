---
summary: "trackt start launches the clone's twatch.py, but the clone is detached at the sha under test — so a restart after a crash re-runs the crashing code, not the fix"
type: bug
track: T
prio: 65
status: done
---

# A restart runs the tested sha's watcher, not the current one

- **Type:** bug (Track T — `tools/trackt.py`, daemon lifecycle)
- **Found:** 2026-08-04 by `claude@xeon`, the hard way: it turned one bug into
  two outages.

## The defect

`daemon_script()` runs the CLONE's copy of `twatch.py` on purpose, so that the
watcher executes committed code and "restart to pick up a fix" means "pull,
then restart". Sound as far as it goes — but **the clone is detached at the sha
under test for most of every cycle, and always after a crash**, which is
exactly when someone restarts it. The copy it launches is then that sha's, i.e.
an arbitrary older version of the watcher's own code.

## What it cost

A side file I added broke `regen_index` (`KeyError: 'host'`) and took the
daemon down. I fixed it, landed the fix, and ran `trackt up` — which relaunched
the crashed code from `ac03897df`, because that is where the crash had left the
clone. The old code re-created the file it crashes on, and it died identically.

Two outages, one bug, and the diagnosis was actively misleading: Python renders
a traceback by reading the CURRENT file for source lines while the line NUMBERS
come from the loaded (old) code object. The log therefore showed the fixed
file's text under the old file's numbers, so the fix appeared to be in place.

## Fix

`ensure_clone_on_branch()` runs before the daemon is spawned: if HEAD is
detached, check the branch back out and fast-forward, saying so. If that cannot
be done — a dirty clone — `cmd_start` refuses rather than starting something
arbitrary, which is the same stance `twatch` already takes on a dirty clone.

Deliberately NOT solved by launching this checkout's copy instead: that is the
`--local-code` escape hatch, and making it the default would put uncommitted
agent edits into the watcher, which is the incident the dedicated clone exists
to prevent.

## Log
- 2026-08-04 — fixed; `tools/trackt_start_code_devtest.py` builds a scratch
  origin with an old and a fixed commit, detaches the clone on the old one (the
  post-crash state) and asserts the launcher returns it to the branch, leaves a
  current clone alone, and refuses a dirty one.
- 2026-08-04 — resolved, commit 1559ba406.
