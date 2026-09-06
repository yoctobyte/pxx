---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh test_parallel_for_private26 "$(/tmp/test_parallel_for_private26)" "$(cat test/test_parallel_for_pri`. The job's own `src` (`test/test_parallel_for_private.pas`, 3 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-threads#src:test/test_parallel_for_private.pas at 0dd59f05cc3a in step 2/2, `tools/expect_same.sh test_parallel_for_private26 "$(/tmp/test_parallel_for_private26)" "$(cat test/test_parallel_for_pr…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T15:04:25Z
- **Test source:** test/test_parallel_for_private.pas tools/expect_same.sh +1
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh test/test_parallel_for_private.expected`.
  ```
  tools/expect_same.sh test_parallel_for_private26 "$(/tmp/test_parallel_for_private26)" "$(cat test/test_parallel_for_private.expected)"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-threads#src:test/test_parallel_for_private.pas'` at 0dd59f05cc3a5187257914a4b9bfc6676f9378c7

## Range
> **The named sha `0dd59f05cc3a` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `0dd59f05cc3a`, last good `5a08811f33bc`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3144186/test_parallel_for_private26  [code=179992B  data=6688B  bss=51972B  procs=592]
expect_same: MISMATCH [test_parallel_for_private26]
--- expected
+++ actual
@@ -1,16 +1,16 @@
 SCRATCH 300000
 TYPES 30000
 SEED 0
-STR 4000
+STR 4378472
 OUTER 12345 9.5 TRUE Z <OUTER>
 SCRATCH 300000
 TYPES 30000
 SEED 0
-STR 4000
+STR 4378472
 OUTER 12345 9.5 TRUE Z <OUTER>
 SCRATCH 300000
 TYPES 30000
 SEED 0
-STR 4000
+STR 4378472
 OUTER 12345 9.5 TRUE Z <OUTER>
-PARPRIV OK
+PARPRIV BAD 3

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-06 — auto-closed by the seven watcher: `test-threads#src:test/test_parallel_for_private.pas` passes at b2a41d5f4fb9 (tier native); it was red at 0dd59f05cc3a. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
