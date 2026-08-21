---
prio: 70
status: done
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

## Resolved — 2026-08-21 (agent-A)

Not a compiler regression at all: `tools/testmgr_hardcoded_tmp_devtest.py` is a
**ratchet**, and `test/test_read_text_char.pas` (landed inside the 132-commit
range) was the new entry that tripped it. It wrote
`/tmp/test_read_text_char_a.txt` and `_b.txt` at RUNTIME, so no Makefile sweep
could reach them — two concurrent runs of the suite would have shared one
scratch file, which is exactly what the devtest exists to prevent.

Fixed the way the devtest's own message asks for: the program now reads
`$TESTTMP` (`GetEnvironmentVariable`, defaulting to `/tmp`, which is the
sweep's own default so the behaviour is unchanged when it is unset) and builds
both paths from it. No entry added to `KNOWN`/`ALLOWED_PATHS` — the ratchet
stays where it is.

Verified: `testmgr_hardcoded_tmp_devtest.py` green (61 known, 0 unlisted); the
test still prints `total ok 25 / 25` with and without `TESTTMP` set, and FPC
3.2.2 compiles the edited source and prints the same line — so the FPC-derived
expectations it encodes are untouched.

Gate: `tools/gate.sh quick` GREEN.
- 2026-08-21 — resolved, commit PENDING-COMMIT.
