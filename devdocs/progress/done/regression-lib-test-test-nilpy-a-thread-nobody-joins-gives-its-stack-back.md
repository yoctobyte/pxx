---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 6 is `tools/expect_same.sh test_nilpy_threadstack "$(/tmp/test_nilpy_threadstack | tail -n 1)" "THREADSTACK OK"`. The job's own `src` (`test/test_nilpy_a_thread_nobody_joins_gives_its_stack_back.npy`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `test_nilpy_a_thread_nobody_joins_gives_its_stack_back`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `expect_same`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:test/test_nilpy_a_thread_nobody_joins_gives_its_stack_back.npy at e977f78c3199 in step 2/6, `tools/expect_same.sh test_nilpy_threadstack "$(/tmp/test_nilpy_threadstack | tail -n 1)" "THREADSTACK OK"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-15T00:21:00Z
- **Test source:** test/test_nilpy_a_thread_nobody_joins_gives_its_stack_back.npy tools/expect_same.sh
- **Failing step:** line 2 of 6 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_nilpy_threadstack "$(/tmp/test_nilpy_threadstack | tail -n 1)" "THREADSTACK OK"
  ```

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:test/test_nilpy_a_thread_nobody_joins_gives_its_stack_back.npy'` at e977f78c31996ef1d7d9274ca5078558b21105c8

## Range
> **The named sha `e977f78c3199` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `e977f78c3199`, last good `19bcd974455c`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
note: threading -> mimic_threading (shim, subset)
ok: /tmp/testmgr-scratch-1544897/test_nilpy_threadstack  [code=1527576B  data=117132B  bss=92100B  procs=2449]
expect_same: MISMATCH [test_nilpy_threadstack]
--- expected
+++ actual
@@ -1 +1 @@
-THREADSTACK OK
+THREADSTACK FAIL

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-16 — auto-closed by the borg watcher: `lib-test#src:test/test_nilpy_a_thread_nobody_joins_gives_its_stack_back.npy` passes at 28d8539fec57 (tier full); it was red at e977f78c3199. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
