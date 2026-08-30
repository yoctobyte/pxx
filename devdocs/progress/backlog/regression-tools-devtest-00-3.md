---
prio: 70
track: T
---

> **Track T by default: no lane could be inferred** (the job reported no test source). This is a FALLBACK, not a finding — nothing here says the defect is Track T's, only that the test source did not name an owner. Re-lane it before working it.

> **origin/master has advanced 30 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: tools-devtest#00 red at 0c99981669b7 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-30T04:14:14Z
- **Test source:** unknown (see repro commands)

## Repro
`tools/testmgr.py --tier full --job 'tools-devtest#00'` at 0c99981669b7d19df37f3ec53646cf78a5c86c31

## Range
> **The named sha `0c99981669b7` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `0c99981669b7`, last good `e46dbffaa80d`, 131 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
evtest.py
  tools-devtest: tools/twatch_cascade_range_devtest.py
  tools-devtest: tools/twatch_cascade_reason_devtest.py
  tools-devtest: tools/twatch_clone_clean_devtest.py
  tools-devtest: tools/twatch_close_stubs_devtest.py
  tools-devtest: tools/twatch_closure_status_devtest.py
  tools-devtest: tools/twatch_covering_devtest.py
  tools-devtest: tools/twatch_cross_currency_devtest.py
  tools-devtest: tools/twatch_diagnostics_devtest.py
  tools-devtest: tools/twatch_failing_step_devtest.py
  tools-devtest: tools/twatch_first_seen_devtest.py
  tools-devtest: tools/twatch_flaky_report_devtest.py
  tools-devtest: tools/twatch_full_commit_devtest.py
  tools-devtest: tools/twatch_gone_key_devtest.py
  tools-devtest: tools/twatch_heal_objectdb_devtest.py
  tools-devtest: tools/twatch_host_epoch_devtest.py
  tools-devtest: tools/twatch_idle_yield_devtest.py
  tools-devtest: tools/twatch_job_history_devtest.py
  tools-devtest: tools/twatch_no_testable_change_devtest.py
  tools-devtest: tools/twatch_opt_coverage_devtest.py
  tools-devtest: tools/twatch_pin_baseline_devtest.py
  tools-devtest: tools/twatch_pin_corroboration_devtest.py
  tools-devtest: tools/twatch_pin_straddle_devtest.py
  tools-devtest: tools/twatch_pin_verify_status_devtest.py
  tools-devtest: tools/twatch_pin_verify_why_devtest.py
  tools-devtest: tools/twatch_quiet_host_devtest.py
  tools-devtest: tools/twatch_refile_stub_devtest.py
  tools-devtest: tools/twatch_resume_devtest.py
  tools-devtest: tools/twatch_running_code_devtest.py
  tools-devtest: tools/twatch_skip_anchor_devtest.py
  tools-devtest: tools/twatch_stub_track_devtest.py
  tools-devtest: tools/twatch_timeout_staleness_devtest.py
  tools-devtest: tools/twatch_timeout_verdict_devtest.py
  tools-devtest: tools/twatch_verify_request_devtest.py
  tools-devtest: tools/verify_assertions_devtest.py
  tools-devtest: tools/whokilled_devtest.py
  tools-devtest: 114 green, 2 RED -- tools/exit_observable_devtest.py tools/progress_stale_edge_devtest.py

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
