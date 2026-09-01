---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh test_ifbyval26 "$(/tmp/test_ifbyval26 | tail -1)" "total ok 25 / 25"`. The job's own `src` (`test/test_interface_byval_param_no_leak.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_interface_byval_param_no_leak.pas at 3f73ad2f6a08 in step 2/2, `tools/expect_same.sh test_ifbyval26 "$(/tmp/test_ifbyval26 | tail -1)" "total ok 25 / 25"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5ea286a98481`).
  Untriaged.
- **Found:** 2026-09-01T19:54:43Z
- **Test source:** test/test_interface_byval_param_no_leak.pas tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_ifbyval26 "$(/tmp/test_ifbyval26 | tail -1)" "total ok 25 / 25"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_interface_byval_param_no_leak.pas'` at 3f73ad2f6a08f46d3111aafd1e5a24c2d25ce7cc

## Range
> **The named sha `3f73ad2f6a08` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `3f73ad2f6a08`, last good `9801b0bcb2c6`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2195942/test_ifbyval26  [code=77592B  data=5304B  bss=43612B  procs=155]
expect_same: MISMATCH [test_ifbyval26]
--- expected
+++ actual
@@ -1 +1 @@
-total ok 25 / 25
+total ok 24 / 25

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-01 — auto-closed by the seven watcher: `test-core#src:test/test_interface_byval_param_no_leak.pas` passes at 889bfcf73256 (tier native); it was red at 3f73ad2f6a08. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
