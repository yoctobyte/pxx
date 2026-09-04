---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 5 is `tools/expect_same.sh test_lfss26.1 "$(/tmp/test_lfss26 | tail -1)" "LOADFILE SHORTSTRING OK"`. The job's own `src` (`test/test_loadfile_shortstring.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-threads#src:test/test_loadfile_shortstring.pas at 0aaaebfefaa8 in step 2/5, `tools/expect_same.sh test_lfss26.1 "$(/tmp/test_lfss26 | tail -1)" "LOADFILE SHORTSTRING OK"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-04T09:55:23Z
- **Test source:** test/test_loadfile_shortstring.pas tools/expect_same.sh
- **Failing step:** line 2 of 5 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_lfss26.1 "$(/tmp/test_lfss26 | tail -1)" "LOADFILE SHORTSTRING OK"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-threads#src:test/test_loadfile_shortstring.pas'` at 0aaaebfefaa8bef502e819758c0aa93f835710b0

## Range
> **The named sha `0aaaebfefaa8` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `0aaaebfefaa8`, last good `9849f2d4c712`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-3494690/test_lfss26  [code=65304B  data=3104B  bss=44004B  procs=134]
Segmentation fault (core dumped)
expect_same: MISMATCH [test_lfss26.1]
--- expected
+++ actual
@@ -1 +1 @@
-LOADFILE SHORTSTRING OK
+

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
