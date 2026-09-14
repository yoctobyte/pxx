---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 13 is `out=$(timeout 60 /tmp/test_ts_hl_diag26 2>&1); rc=$?; \ tools/expect_same.sh test_ts_hl_diag26_exit "$rc" "212" && \ too`. The job's own `src` (`test/test_threadsafe_heap_lock_deadlock_diag.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `test_threadsafe_heap_lock_deadlock_diag`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `expect_same`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas at 1e3e9a0b95d0 in step 2/13, `out=$(timeout 60 /tmp/test_ts_hl_diag26 2>&1); rc=$?; \ tools/expect_same.sh test_ts_hl_diag26_exit "$rc" "212" && \ to…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-14T00:02:26Z
- **Test source:** test/test_threadsafe_heap_lock_deadlock_diag.pas tools/expect_same.sh
- **Failing step:** line 2 of 13 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  out=$(timeout 60 /tmp/test_ts_hl_diag26 2>&1); rc=$?; \ tools/expect_same.sh test_ts_hl_diag26_exit "$rc" "212" && \ tools/expect_same.sh test_ts_hl_diag26_control "$(printf '%s\n' "$out" | sed -n 1p)" "contention-workers-finished=12" && \ tools/expect_same.sh test_ts_hl_diag26_named "$(printf '%s\n
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas'` at 1e3e9a0b95d0eb623f0d78b9024a9672a9c431b0

## Range
bad `1e3e9a0b95d0`, last good `82e070429d30`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2153415/test_ts_hl_diag26  [code=179992B  data=9664B  bss=55676B  procs=640]
expect_same: MISMATCH [test_ts_hl_diag26_exit]
--- expected
+++ actual
@@ -1 +1 @@
-212
+124

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
