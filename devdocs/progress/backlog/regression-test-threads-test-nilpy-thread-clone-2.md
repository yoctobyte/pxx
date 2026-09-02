---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 6 is `tools/expect_same.sh test_npy_clone26 "$(/tmp/test_npy_clone26)" "$(printf 'tid nonzero = True\nchild ran = 7')"`. The job's own `src` (`test/test_nilpy_thread_clone.npy`, 4 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 10 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-threads#src:test/test_nilpy_thread_clone.npy at 08f7de0715a8 in step 2/6, `tools/expect_same.sh test_npy_clone26 "$(/tmp/test_npy_clone26)" "$(printf 'tid nonzero = True\nchild ran = 7')"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-02T16:04:12Z
- **Test source:** test/test_nilpy_thread_clone.npy tools/expect_same.sh +2
- **Failing step:** line 2 of 6 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_npy_clone26 "$(/tmp/test_npy_clone26)" "$(printf 'tid nonzero = True\nchild ran = 7')"
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-threads#src:test/test_nilpy_thread_clone.npy'` at 08f7de0715a8a9cf5f2e739231b7ac7d2b18177f

## Range
> **The named sha `08f7de0715a8` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `08f7de0715a8`, last good `8476a5157557`, 9 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-2784241/test_npy_clone26  [code=1347352B  data=77376B  bss=51404B  procs=1928]
Segmentation fault (core dumped)
expect_same: MISMATCH [test_npy_clone26]
--- expected
+++ actual
@@ -1,2 +1 @@
 tid nonzero = True
-child ran = 7

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-02 — the seven watcher saw `test-threads#src:test/test_nilpy_thread_clone.npy` GREEN at 5ad048c2d9ae (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-nilpy-thread-clone-2`, not `regression-test-threads-test-nilpy-thread-clone`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-02 — the seven watcher saw `test-threads#src:test/test_nilpy_thread_clone.npy` GREEN at 9cf9771387c6 (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-nilpy-thread-clone-2`, not `regression-test-threads-test-nilpy-thread-clone`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-02 — the seven watcher saw `test-threads#src:test/test_nilpy_thread_clone.npy` GREEN at 72184098b614 (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-nilpy-thread-clone-2`, not `regression-test-threads-test-nilpy-thread-clone`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-02 — the seven watcher saw `test-threads#src:test/test_nilpy_thread_clone.npy` GREEN at afbc83e5a976 (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-nilpy-thread-clone-2`, not `regression-test-threads-test-nilpy-thread-clone`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-02 — the seven watcher saw `test-threads#src:test/test_nilpy_thread_clone.npy` GREEN at 7fff15ddc1eb (tier native) and did NOT close this: this is a repeat stub (`regression-test-threads-test-nilpy-thread-clone-2`, not `regression-test-threads-test-nilpy-thread-clone`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
