---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh sweep_promoint26 "$(/tmp/sweep_promoint26)" "$(printf '18446744073709551615\n0\ncrossed\n1844674407`. The job's own `src` (`test/test_promoint_bitwise.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_promoint_bitwise.pas at 0aff068c6d08 in step 2/2, `tools/expect_same.sh sweep_promoint26 "$(/tmp/sweep_promoint26)" "$(printf '18446744073709551615\n0\ncrossed\n184467440…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T13:36:18Z
- **Test source:** test/test_promoint_bitwise.pas tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh sweep_promoint26 "$(/tmp/sweep_promoint26)" "$(printf '18446744073709551615\n0\ncrossed\n18446744073709551616\n255\n255\n15')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_promoint_bitwise.pas'` at 0aff068c6d08caf3d9b2f8d4d5fd5886d27ac0c2

## Range
> **The named sha `0aff068c6d08` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `0aff068c6d08`, last good `bb18f83c859e`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1824622/sweep_promoint26  [code=245528B  data=6276B  bss=52100B  procs=650]
expect_same: MISMATCH [sweep_promoint26]
--- expected
+++ actual
@@ -1,6 +1,6 @@
-18446744073709551615
+-1
 0
-crossed
+not
 18446744073709551616
 255
 255

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
