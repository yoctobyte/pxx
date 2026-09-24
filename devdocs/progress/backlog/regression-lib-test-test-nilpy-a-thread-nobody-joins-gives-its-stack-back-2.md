---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 6 is `tools/expect_same.sh test_nilpy_threadstack "$(/tmp/test_nilpy_threadstack | tail -n 1)" "THREADSTACK OK"`. The job's own `src` (`test/test_nilpy_a_thread_nobody_joins_gives_its_stack_back.npy`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `test_nilpy_a_thread_nobody_joins_gives_its_stack_back`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `expect_same`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 7 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:test/test_nilpy_a_thread_nobody_joins_gives_its_stack_back.npy at 503514455013 in step 2/6, `tools/expect_same.sh test_nilpy_threadstack "$(/tmp/test_nilpy_threadstack | tail -n 1)" "THREADSTACK OK"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `f35167cd4e55`).
  Untriaged.
- **Found:** 2026-09-24T16:59:53Z
- **Test source:** test/test_nilpy_a_thread_nobody_joins_gives_its_stack_back.npy tools/expect_same.sh
- **Failing step:** line 2 of 6 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_nilpy_threadstack "$(/tmp/test_nilpy_threadstack | tail -n 1)" "THREADSTACK OK"
  ```

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:test/test_nilpy_a_thread_nobody_joins_gives_its_stack_back.npy'` at 5035144550139e34e3ca1c3c5d62a45a6d987902

## Range
> **The named sha `503514455013` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `503514455013`, last good `8e2464989f2a`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
note: threading -> mimic_threading (shim, subset)
ok: /tmp/testmgr-scratch-96264/test_nilpy_threadstack  [code=730751B  data=130568B  bss=102660B  procs=2597  codeseg=732896B]
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
- 2026-09-24 — the borg watcher saw `lib-test#src:test/test_nilpy_a_thread_nobody_joins_gives_its_stack_back.npy` GREEN at a7c5f8b0736b (tier full) and did NOT close this: this is a repeat stub (`regression-lib-test-test-nilpy-a-thread-nobody-joins-gives-its-stack-back-2`, not `regression-lib-test-test-nilpy-a-thread-nobody-joins-gives-its-stack-back`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
