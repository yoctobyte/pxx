---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 30 is `tools/expect_same.sh test_nilpy_deadalias26 "$(/tmp/test_nilpy_deadalias26)" "$(python3 test/test_nilpy_a_dead_guarded_i`. The job's own `src` (`test/test_nilpy_a_dead_guarded_import_arm_still_binds_its_unit_alias.npy`, 3 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 12 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_a_dead_guarded_import_arm_still_binds_its_unit_alias.npy at 8b188a3beac3 in step 2/30, `tools/expect_same.sh test_nilpy_deadalias26 "$(/tmp/test_nilpy_deadalias26)" "$(python3 test/test_nilpy_a_dead_guarded_…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `883da23adb0a`).
  Untriaged.
- **Found:** 2026-09-11T00:59:11Z
- **Test source:** test/test_nilpy_a_dead_guarded_import_arm_still_binds_its_unit_alias.npy tools/expect_same.sh +1
- **Failing step:** line 2 of 30 of the job's recipe; it names `tools/expect_same.sh test/test_nilpy_a_dead_guarded_import_arm_still_binds_its_unit_alias.npy`.
  ```
  tools/expect_same.sh test_nilpy_deadalias26 "$(/tmp/test_nilpy_deadalias26)" "$(python3 test/test_nilpy_a_dead_guarded_import_arm_still_binds_its_unit_alias.npy)"
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_a_dead_guarded_import_arm_still_binds_its_unit_alias.npy'` at 8b188a3beac3de68822ae8b9a8872892a02e26f1

## Range
bad `8b188a3beac3`, last good `1c520914979b`, 7 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1389833/test_nilpy_deadalias26  [code=1371928B  data=84620B  bss=55156B  procs=2287]
Unhandled exception: AttributeError: 'NoneType' object has no attribute 'B'
expect_same: MISMATCH [test_nilpy_deadalias26]
--- expected
+++ actual
@@ -1,3 +1,2 @@
 dead-arm fallback 27 fallback
 live-arm primary 99 primary
-absolute fallback 27 fallback

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-11 — auto-closed by the seven watcher: `test-nilpy#src:test/test_nilpy_a_dead_guarded_import_arm_still_binds_its_unit_alias.npy` passes at 840b21cfcf5d (tier full); it was red at 8b188a3beac3. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
