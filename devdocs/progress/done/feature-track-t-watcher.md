---
prio: 70  # dev-speed lever: kills the 10+min full gate from the dev inner loop
---
# Track T face 1: standalone test watcher (twatch) — continuous offloaded gate

- **Type:** feature (test infra). Track A (tools; no compiler changes).
- **Opened:** 2026-07-07, from the Track T design discussion (user-approved).

## Concept (user, 2026-07-07)
Testing becomes a PERMANENT BACKGROUND PROCESS, offloaded from dev sessions.
Dev tracks gate pushes on quick native tests (testmgr quick + self-host
fixedpoint, ~40s); the full all-target matrix runs asynchronously on whatever
box is available. Accept delayed regression feedback; in exchange, a trivial
change no longer costs a 10+ minute wait. Every result is tied to an exact
git SHA so diving back into the offending change is one checkout.

## Deliverable: `tools/twatch.py` (Python 3, stdlib only)
Standalone daemon, no AI, built ON TOP of tools/testmgr.py (the
multi-process resource-aware runner — twatch relies on its adaptive
scheduling so it can run on the dev box, a low-power laptop, or the Xeon,
or ALL in parallel):

1. **Own dedicated clone.** Never shares a dev checkout (mid-run edits would
   poison results). Clone location configurable; syncs via the central
   GitHub repo — results are pushed there too (straightforwardest transport;
   multiple watcher hosts just push independently).
2. **Loop:** `git fetch` → new commits on master? → debounce (wait ~10-30s
   of repo quiet so commit bursts settle) → checkout newest HEAD →
   `testmgr --tier full` → report → push → repeat.
3. **Backfill / lazy bisect:** idle and a regression range spans >1 commit →
   test the midpoint commit (single failing job only, not the full tier).
   Ranges shrink toward single commits over time. Needs a small testmgr
   addition: `--job <name-glob>` to rerun one job in isolation.
4. **Sparse, standardized reports.** Noise-free by design: all-green =
   one-line state update; detail only on CHANGE (NEW-RED / FIXED vs the
   previously tested SHA). Per-tested-SHA report file:
   - header (machine-parseable): sha, parent-tested-sha, date, host
     fingerprint, calibration scale, tier, wall, verdict GREEN|RED
   - body: NEW-RED jobs / FIXED jobs / STILL-RED jobs; first-failure log
     verbatim; repro command line
5. **Publish target:** `devdocs/progress/tstate/` — reports land ONLY in
   this subfolder (the watcher's git identity is deliberately limited to
   it; ticket crafting is face 2's job, see
   feature-track-t-agent). Plus a regenerated `TSTATE.md` index: latest
   verdict per host, open regressions with commit ranges.
   Multi-host: report filename carries host tag; pushes are
   pull-rebase-retry so concurrent watchers don't fight.
6. **Ops:** git deploy key provided by user (or agent installs one);
   systemd-unit-or-nohup runbook in the file header; SIGINT-clean via
   testmgr's teardown; survives offline periods (just resumes at fetch).

## Protocol change that lands WITH this ticket
- CLAUDE.md gains Track T (testing infra lane): owns tools/testmgr.py,
  tools/twatch.py, devdocs/progress/tstate/**.
- Dev push gate officially relaxes to quick + self-host fixedpoint once a
  watcher is live; master MAY carry cross-target reds for hours — a NEW-RED
  is normal flow (ticket at ~70 via face 2), a core-job red older than a
  day is a revert candidate.

## Gate
- watcher runs unattended over a working session (>=10 commits), produces
  correct NEW-RED/FIXED diffs, pushes only tstate files, no orphan
  processes, survives kill -INT mid-run.
- one deliberately-broken commit (local branch test) yields a report naming
  the exact SHA and failing job with verbatim log.

## Non-goals here
Ticket crafting, analysis, testmgr maintenance by an agent — that is
feature-track-t-agent (face 2), blocked by this.

## Resolution (2026-07-07, fable-ac)
Landed `tools/twatch.py` + testmgr integration (`--job GLOB` bisect
primitive, `--report-json`). Verified against a scratch bare "central" repo
(quick tier only per user norm — no long runs to test tooling):
- fresh clone self-seeds compiler via `make seed-from-stable`;
- GREEN run publishes only <host>.json + TSTATE.md (sparse: no report file);
- deliberately-broken commit → RED report naming exact SHA, parent-tested
  SHA, NEW-RED job `test-quick#04`, verbatim log, one-line repro
  (`testmgr --tier quick --job 'test-quick#04'`);
- revert → FIXED recorded, open regression closed;
- publish commits touch ONLY devdocs/progress/tstate/**, rebase-retry push
  (multi-host safe); SIGINT exits clean, no orphans.
- CLAUDE.md gained the Track T lane definition (incl. relaxed dev push gate
  once a watcher is live).
Full-tier unattended soak over a real working session = first live
deployment task; the deliberately-broken-commit gate is scripted above and
repeatable.

## Log
- 2026-07-07 — resolved, commit HEAD.
