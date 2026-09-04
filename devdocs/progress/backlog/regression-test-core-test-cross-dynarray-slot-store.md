---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 4 is `tools/expect_same.sh dsspal26/wasm32 "$(tools/run_target.sh wasm32 /tmp/dsspal.wasm)" "DYNSLOTSTORE OK"`. The job's own `src` (`test/test_cross_dynarray_slot_store.pas`, 4 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# first-ever red: test-core#src:test/test_cross_dynarray_slot_store.pas@2 at 8860639aa3ee in step 2/4, `tools/expect_same.sh dsspal26/wasm32 "$(tools/run_target.sh wasm32 /tmp/dsspal.wasm)" "DYNSLOTSTORE OK"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-04T14:43:13Z
- **Test source:** test/test_cross_dynarray_slot_store.pas tools/expect_same.sh +2
- **Failing step:** line 2 of 4 of the job's recipe; it names `tools/expect_same.sh tools/run_target.sh`.
  ```
  tools/expect_same.sh dsspal26/wasm32 "$(tools/run_target.sh wasm32 /tmp/dsspal.wasm)" "DYNSLOTSTORE OK"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_cross_dynarray_slot_store.pas@2'` at 8860639aa3ee39f7dbf85d44204643ef368b092e

## Range
bad `8860639aa3ee`, and this is the job's **first-ever run** — there is no earlier passing sha, so no interval contains the cause and every commit a range could name is equally innocent. **No idle bisect will happen**; a red here is a finding about the job, not a regression from the commits around it.

## Log tail
```
ok: /tmp/testmgr-scratch-1536290/dsspal.wasm  [code=3499B  data=3360B  bss=1090908B  procs=137]
wasmtime not found (looked on PATH and in ~/.local/bin)
expect_same: MISMATCH [dsspal26/wasm32]
--- expected
+++ actual
@@ -1 +1 @@
-DYNSLOTSTORE OK
+

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
