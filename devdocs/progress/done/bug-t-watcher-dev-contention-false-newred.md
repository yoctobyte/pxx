---
track: T
prio: 45
type: bug
status: done
owner: claude@xeon
---

# Watcher and dev session on one box false-RED slow test-core jobs

- **Track:** T (test infra — false RED, costs a dev investigation)
- **Found:** 2026-07-19 by a Track A session, via tstate report
  `20260719T175151Z-e584d7b-borg.md`.

## Symptom

tstate reported NEW-RED at e584d7b4:

```
test-core#src:test/test_interface_mainbody_ascast_temp.pas
...
ok: /tmp/testmgr-scratch-4187991/test_imbt26  [code=36465B ...]
Terminated
```

The tell is `Terminated` with the compile line reading `ok` — a kill, not a
wrong result. The job passes standalone (`--tier native --job
'test-core#...ascast_temp.pas'` → GREEN, 111.5s), and the same dev session's
own `--tier full` at the same tree classified it "flaky (recovered on retry)".

## Cause (distinct from the existing shard tickets)

Not intra-run parallelism like
[[regression-testmgr-conformance-shard-timeout-under-load]] and
[[bug-t-qemu-conformance-false-timeout-under-load]] — those are one testmgr
oversubscribing itself. Here TWO testmgr processes from DIFFERENT checkouts
ran concurrently:

```
4168963 /usr/bin/python3 /home/rene/frankonpiler/tools/testmgr.py --tier full
4187991 /usr/bin/python3 /home/rene/trackt-watch/tools/testmgr.py --tier native
```

The watcher's dedicated clone and the dev checkout each size their own
parallelism to the whole box, so together they oversubscribe it ~2x. The jobs
that lose are the long ones: this test is 111.5s standalone, and the surviving
sibling in the same shell (`test_token_growth`, 12000 procs) is likewise slow.

## Why it matters

A false RED on a test named `..._ascast_temp` is expensive: the as-cast temp
lifetime bug is a REAL known landmine (layout-sensitive SIGSEGV, see
`project_interface_ascast_temp_lifetime_landmine`), so this specific job
false-REDing reads exactly like that landmine resurfacing and pulls a dev
session into a full investigation.

## Fix shapes (T's call)

- A cross-process lock or advisory token so the watcher defers while a dev
  testmgr is live on the same box (the xvfb lock is a precedent).
- Scale the timeout by observed load rather than wall-clock alone.
- Distinguish `Terminated` / exit 124 from a genuine failure in the report and
  auto-retry before declaring NEW-RED — the retry logic already exists in the
  dev path ("flaky, recovered on retry"); tstate's path did not apply it.

## Log
- 2026-08-03 (`claude@xeon`) — fixed by making testmgr aware of its co-tenants.

  Root cause confirmed and it is narrower than "two testmgrs": the run lock is
  `<repo>/.testmgr/run.lock`, i.e. PER-REPO, so a run in another clone is
  invisible to it by construction — and the watcher daemon lives in its own
  dedicated clone by design. `find_runs()` already scanned the box for runs in
  other clones (for orphan reaping); admission and reporting just never used it.

  Of the three fix shapes offered, this takes two and declines one:

  - **Cross-process defer (declined).** The watcher would stall behind any dev
    testmgr on the box. On xeon the daemon runs full tiers back to back, so the
    deferral would run in the other direction too, and one busy box would stop
    the fleet's coverage. The contention costs latency; it should not cost
    coverage.
  - **Timeout scaled by load (taken, narrowly).** Budgets stretch by
    `PEER_TIME_FACTOR` (2x) only while a co-tenant is actually live — two runs
    each sizing to the whole box roughly halve each other's share. Stretching
    beats retrying for the long jobs this bites: re-running a 111.5s job three
    times costs more than giving it the room once.
  - **Distinguish a kill from a verdict (taken).** A job killed by
    SIGTERM/SIGKILL/SIGHUP, or timed out, while a co-tenant was live is
    requeued in ANY class rather than declared RED — the same argument that
    makes the ETXTBSY signature safe in single-shot classes: a kill says
    nothing about the binary's CONTENTS. A nonzero EXIT is still RED under
    contention; laundering a real wrong answer would be far worse than the bug.
    Retries stay bounded by `RUN_RETRY_TRIES`, and on an idle box every one of
    these paths is a no-op, so single-shot stays single-shot.

  Found and fixed on the way: `find_runs()` counted any process whose argv
  merely CONTAINED `testmgr.py` — `timeout 600 python3 tools/testmgr.py`,
  `bash -c`, gate.sh, systemd-run — and derived an empty repo from a relative
  path. Harmless while it only inflated `--status`; once co-tenancy steered
  retries, a solo run would have detected its own `timeout` wrapper as a rival
  and stretched every budget. Now filtered on the executable actually being
  python, with relative paths resolved against that process's own cwd.

  Reported, not just logged: both the startup NOTE and the end-of-run report
  say the box was shared. twatch turns report text into the tstate report
  someone reads days later while deciding whether a red is real, and "the box
  was shared" is the first thing that triage needs.

  Verified on xeon with the watcher daemon live: a `--tier quick` run detects
  exactly one peer (`/home/neo/trackt-watch`, tier full) and no phantom, and
  prints the note in both places. `tools/testmgr_contention_devtest.py` pins
  all eight behaviours by driving `reap()` with stub processes.
- 2026-08-03 — resolved, commit 6cc0753da.
