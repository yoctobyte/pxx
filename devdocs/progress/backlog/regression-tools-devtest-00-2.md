---
prio: 70
---

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: tools-devtest#00 red at 8787cfe4235a (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-27T15:14:29Z
- **Test source:** unknown (see repro commands)

## Repro
`tools/testmgr.py --tier full --job 'tools-devtest#00'` at 8787cfe4235a9f6f869e8b365586bc1fce8c4a54

## Range
> **The named sha `8787cfe4235a` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `8787cfe4235a`, last good `62a4242203a3`, 10 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
e_devtest.py
  tools-devtest: tools/testmgr_retry_signature_devtest.py
  tools-devtest: tools/testmgr_tmp_var_devtest.py
  tools-devtest: tools/testmgr_unseed_devtest.py
  tools-devtest: tools/tools_scope_devtest.py
  tools-devtest: tools/trackt_detect_role_devtest.py
  tools-devtest: tools/trackt_start_code_devtest.py
  tools-devtest: tools/tstate_reader_devtest.py
  tools-devtest: tools/twatch_baseline_devtest.py
  tools-devtest: tools/twatch_behind_vs_down_devtest.py
  tools-devtest: tools/twatch_bench_quiet_devtest.py
  tools-devtest: tools/twatch_blame_range_devtest.py
  tools-devtest: tools/twatch_branch_devtest.py
  tools-devtest: tools/twatch_breadth_slot_devtest.py
  tools-devtest: tools/twatch_breadth_visibility_devtest.py
  tools-devtest: tools/twatch_cascade_count_devtest.py
  tools-devtest: tools/twatch_cascade_range_devtest.py
  tools-devtest: tools/twatch_clone_clean_devtest.py
  tools-devtest: tools/twatch_close_stubs_devtest.py
  tools-devtest: tools/twatch_diagnostics_devtest.py
  tools-devtest: tools/twatch_first_seen_devtest.py
  tools-devtest: tools/twatch_full_commit_devtest.py
  tools-devtest: tools/twatch_gone_key_devtest.py
  tools-devtest: tools/twatch_heal_objectdb_devtest.py
  tools-devtest: tools/twatch_host_epoch_devtest.py
  tools-devtest: tools/twatch_idle_yield_devtest.py
  tools-devtest: tools/twatch_no_testable_change_devtest.py
  tools-devtest: tools/twatch_pin_baseline_devtest.py
  tools-devtest: tools/twatch_pin_corroboration_devtest.py
  tools-devtest: tools/twatch_pin_straddle_devtest.py
  tools-devtest: tools/twatch_pin_verify_status_devtest.py
  tools-devtest: tools/twatch_quiet_host_devtest.py
  tools-devtest: tools/twatch_refile_stub_devtest.py
  tools-devtest: tools/twatch_resume_devtest.py
  tools-devtest: tools/twatch_timeout_staleness_devtest.py
  tools-devtest: tools/twatch_timeout_verdict_devtest.py
  tools-devtest: tools/whokilled_devtest.py
  tools-devtest: 78 green, 1 RED -- tools/testmgr_hardcoded_tmp_devtest.py

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
