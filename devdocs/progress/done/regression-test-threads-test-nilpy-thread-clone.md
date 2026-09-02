---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 6 is `tools/expect_same.sh test_npy_clone26 "$(/tmp/test_npy_clone26)" "$(printf 'tid nonzero = True\nchild ran = 7')"`. The job's own `src` (`test/test_nilpy_thread_clone.npy`, 4 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-threads#src:test/test_nilpy_thread_clone.npy at dc018685fd56 in step 2/6, `tools/expect_same.sh test_npy_clone26 "$(/tmp/test_npy_clone26)" "$(printf 'tid nonzero = True\nchild ran = 7')"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-02T14:02:52Z
- **Test source:** test/test_nilpy_thread_clone.npy tools/expect_same.sh +2
- **Failing step:** line 2 of 6 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_npy_clone26 "$(/tmp/test_npy_clone26)" "$(printf 'tid nonzero = True\nchild ran = 7')"
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-threads#src:test/test_nilpy_thread_clone.npy'` at dc018685fd56c718b66181aecc5c5ec00077bbc6

## Range
> **The named sha `dc018685fd56` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `dc018685fd56`, last good `6f6ec7b36e0f`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-1900033/test_npy_clone26  [code=1347352B  data=77376B  bss=51404B  procs=1928]
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
- 2026-09-02 — auto-closed by the seven watcher: `test-threads#src:test/test_nilpy_thread_clone.npy` passes at 08f7de0715a8 (tier native); it was red at 43aa63d1b54d. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
