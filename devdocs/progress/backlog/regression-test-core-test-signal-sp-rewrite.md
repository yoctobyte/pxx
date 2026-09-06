---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh test_signal_sprw26 "$(/tmp/test_signal_sprw26)" "$(printf 'caught, hits=1\nraiser-ran-on-the-spare-`. The job's own `src` (`test/test_signal_sp_rewrite.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_signal_sp_rewrite.pas at 0dd59f05cc3a in step 2/2, `tools/expect_same.sh test_signal_sprw26 "$(/tmp/test_signal_sprw26)" "$(printf 'caught, hits=1\nraiser-ran-on-the-spare…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T15:04:25Z
- **Test source:** test/test_signal_sp_rewrite.pas tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_signal_sprw26 "$(/tmp/test_signal_sprw26)" "$(printf 'caught, hits=1\nraiser-ran-on-the-spare-stack=TRUE\nand execution continued')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_signal_sp_rewrite.pas'` at 0dd59f05cc3a5187257914a4b9bfc6676f9378c7

## Range
> **The named sha `0dd59f05cc3a` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `0dd59f05cc3a`, last good `5a08811f33bc`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3144186/test_signal_sprw26  [code=69400B  data=3184B  bss=109132B  procs=138]
expect_same: MISMATCH [test_signal_sprw26]
--- expected
+++ actual
@@ -1,3 +1 @@
-caught, hits=1
-raiser-ran-on-the-spare-stack=TRUE
-and execution continued
+

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
