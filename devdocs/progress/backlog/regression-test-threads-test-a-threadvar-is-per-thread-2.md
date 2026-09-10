---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 11 is `tools/expect_same.sh test_threadvar_pt26 "$(/tmp/test_threadvar_pt26)" "$(printf 'kept=4/4\nzeroed-on-entry=4/4\nno-cros`. The job's own `src` (`test/test_a_threadvar_is_per_thread.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-threads#src:test/test_a_threadvar_is_per_thread.pas at 6ce37dd94d7c in step 2/11, `tools/expect_same.sh test_threadvar_pt26 "$(/tmp/test_threadvar_pt26)" "$(printf 'kept=4/4\nzeroed-on-entry=4/4\nno-cro…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `0c5ad13167ab`).
  Untriaged.
- **Found:** 2026-09-09T18:22:14Z
- **Test source:** test/test_a_threadvar_is_per_thread.pas tools/expect_same.sh
- **Failing step:** line 2 of 11 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_threadvar_pt26 "$(/tmp/test_threadvar_pt26)" "$(printf 'kept=4/4\nzeroed-on-entry=4/4\nno-crosstalk=4/4\ncontrol-raced=TRUE\nmain-copy=7\nTHREADVAR OK')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-threads#src:test/test_a_threadvar_is_per_thread.pas'` at 6ce37dd94d7cecfc3f0bea19c46844ff1398d2f2

## Range
> **The named sha `6ce37dd94d7c` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `6ce37dd94d7c`, last good `da32754014e2`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1452873/test_threadvar_pt26  [code=167704B  data=7440B  bss=55208B  procs=579]
expect_same: MISMATCH [test_threadvar_pt26]
--- expected
+++ actual
@@ -1,6 +1,6 @@
 kept=4/4
 zeroed-on-entry=4/4
 no-crosstalk=4/4
-control-raced=TRUE
+control-raced=FALSE
 main-copy=7
-THREADVAR OK
+THREADVAR FAIL

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-10 — the seven watcher saw `test-threads#src:test/test_a_threadvar_is_per_thread.pas` GREEN at dafc9b2f4d88 (tier full) and did NOT close this: the green is at the SAME sha the red was found at (`dafc9b2f4d88`), so no tree change separates them — the job returned two different answers about one tree, which is nondeterminism rather than evidence of a fix. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
