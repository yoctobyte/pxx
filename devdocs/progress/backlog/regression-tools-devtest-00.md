---
prio: 70
---

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: tools-devtest#00 red at 1b9b43e5b511 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-20T16:41:34Z
- **Test source:** unknown (see repro commands)

## Repro
`tools/testmgr.py --tier full --job 'tools-devtest#00'` at 1b9b43e5b511d53e9fbe55f3366e6ce9158ee0b9

## Range
bad `1b9b43e5b511`, last good `57b9b7148d32`, 132 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
est.py
  tools-devtest: tools/csmith_target_devtest.py
  tools-devtest: tools/devtest_autotriage.py
  tools-devtest: tools/devtest_gate_contention.py
  tools-devtest: tools/devtest_idle_ladder.py
  tools-devtest: tools/devtest_job_stdin.py
  tools-devtest: tools/devtest_mem_floor.py
  tools-devtest: tools/devtest_pin_atomic.py
  tools-devtest: tools/devtest_pin_gate_tier.py
  tools-devtest: tools/devtest_pin_lock_inherit.py
  tools-devtest: tools/devtest_pin_shadow.py
  tools-devtest: tools/devtest_pin_verify.py
  tools-devtest: tools/devtest_pinstatus.py
  tools-devtest: tools/devtest_report.py
  tools-devtest: tools/devtest_report_devtest.py
  tools-devtest: tools/devtest_skip_semantics.py
  tools-devtest: tools/devtest_slow_tier.py
  tools-devtest: tools/devtest_status_drift.py
  tools-devtest: tools/devtest_stub_lifecycle.py
  tools-devtest: tools/devtest_wedge_on_own_writes.py
  tools-devtest: tools/fuzz_compare_key_devtest.py
  tools-devtest: tools/job_reason_devtest.py
  tools-devtest: tools/progress_setfield_devtest.py
  tools-devtest: tools/progress_track_f_devtest.py
  tools-devtest: tools/report_exp_dur_devtest.py
  tools-devtest: tools/sync_pending_commit_devtest.py
  tools-devtest: tools/testmgr_contention_devtest.py
  tools-devtest: tools/testmgr_corpus_skip_devtest.py
  tools-devtest: tools/testmgr_cpu_budget_devtest.py
  tools-devtest: tools/testmgr_hardcoded_tmp_devtest.py
FAIL: tools/testmgr_hardcoded_tmp_devtest.py

FAIL: new hardcoded /tmp path(s) in compiled test sources. These are written at RUNTIME, so no Makefile sweep reaches them and testmgr cannot privatize them — two concurrent runs share the file:
  test/test_read_text_char.pas                         /tmp/test_read_text_char_a.txt
  test/test_read_text_char.pas                         /tmp/test_read_text_char_b.txt

Read the directory from the environment instead ($TESTTMP, which the sweep already exports; default /tmp keeps it byte-identical), or add it to ALLOWED_PATHS with a reason.

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
