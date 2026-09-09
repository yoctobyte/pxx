---
prio: 70
track: T
---

> **Track T from the job NAME `tools-devtest`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`none`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: tools-devtest#00 at fc2ce3d02553 in step 1/1, `n=0; bad=0; failed=''; \ for f in tools/*devtest*.py; do \ case "$f" in *bench_timing_devtest.py) continue ;; esac; \ p…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `0c5ad13167ab`).
  Untriaged.
- **Found:** 2026-09-09T06:23:41Z
- **Test source:** unknown (see repro commands)
- **Failing step:** line 1 of 1 of the job's recipe; it names no source file of its own — so it is the JOB's sources, one line up, that are unproven here, not this step's.
  ```
  n=0; bad=0; failed=''; \ for f in tools/*devtest*.py; do \ case "$f" in *bench_timing_devtest.py) continue ;; esac; \ printf ' tools-devtest: %s\n' "$f"; \ if python3 "$f" > /tmp/tools_devtest.log 2>&1; then \ n=$((n+1)); \ else \ bad=$((bad+1)); failed="$failed $f"; \ echo " FAIL: $f"; tail -25 /tm
  ```

## Repro
`tools/testmgr.py --tier full --job 'tools-devtest#00'` at fc2ce3d025534ee225181dd7daae6ac240e8c422

## Range
bad `fc2ce3d02553`, last good `e8f1cb9f4dff`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ols-devtest: tools/twatch_first_seen_devtest.py
  tools-devtest: tools/twatch_flaky_report_devtest.py
  tools-devtest: tools/twatch_full_commit_devtest.py
  tools-devtest: tools/twatch_gone_key_devtest.py
  tools-devtest: tools/twatch_heal_objectdb_devtest.py
  tools-devtest: tools/twatch_host_epoch_devtest.py
  tools-devtest: tools/twatch_idle_tier_try_devtest.py
  tools-devtest: tools/twatch_idle_yield_devtest.py
  tools-devtest: tools/twatch_job_history_devtest.py
  tools-devtest: tools/twatch_job_name_track_devtest.py
  tools-devtest: tools/twatch_no_testable_change_devtest.py
  tools-devtest: tools/twatch_opt_coverage_devtest.py
  tools-devtest: tools/twatch_pin_baseline_devtest.py
  tools-devtest: tools/twatch_pin_corroboration_devtest.py
  tools-devtest: tools/twatch_pin_identity_devtest.py
  tools-devtest: tools/twatch_pin_straddle_devtest.py
  tools-devtest: tools/twatch_pin_verify_status_devtest.py
  tools-devtest: tools/twatch_pin_verify_why_devtest.py
  tools-devtest: tools/twatch_publish_deletion_devtest.py
  tools-devtest: tools/twatch_quiet_host_devtest.py
  tools-devtest: tools/twatch_range_causality_devtest.py
  tools-devtest: tools/twatch_refile_stub_devtest.py
  tools-devtest: tools/twatch_requested_reds_devtest.py
  tools-devtest: tools/twatch_requested_report_devtest.py
  tools-devtest: tools/twatch_resume_devtest.py
  tools-devtest: tools/twatch_running_code_devtest.py
  tools-devtest: tools/twatch_skip_anchor_devtest.py
  tools-devtest: tools/twatch_skip_jobs_devtest.py
  tools-devtest: tools/twatch_stub_track_devtest.py
  tools-devtest: tools/twatch_timeout_staleness_devtest.py
  tools-devtest: tools/twatch_timeout_verdict_devtest.py
  tools-devtest: tools/twatch_toolchain_devtest.py
  tools-devtest: tools/twatch_verify_request_devtest.py
  tools-devtest: tools/verify_assertions_devtest.py
  tools-devtest: tools/whoholds_devtest.py
  tools-devtest: tools/whokilled_devtest.py
  tools-devtest: 158 green, 1 RED -- tools/tstate_reader_devtest.py

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-09 — the seven watcher saw `tools-devtest#00` GREEN at 8c0ccdd019f8 (tier full) and did NOT close this: this is a repeat stub (`regression-tools-devtest-00-4`, not `regression-tools-devtest-00`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-09 — the seven watcher saw `tools-devtest#00` GREEN at 3b5005e79ea4 (tier full) and did NOT close this: this is a repeat stub (`regression-tools-devtest-00-4`, not `regression-tools-devtest-00`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
