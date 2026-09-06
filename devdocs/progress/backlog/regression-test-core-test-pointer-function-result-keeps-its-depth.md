---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh test_ptrfnres26 "$(/tmp/test_ptrfnres26)" "$(cat test/test_pointer_function_result_keeps_its_depth.`. The job's own `src` (`test/test_pointer_function_result_keeps_its_depth.pas`, 3 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_pointer_function_result_keeps_its_depth.pas at 85d70d70076a in step 2/2, `tools/expect_same.sh test_ptrfnres26 "$(/tmp/test_ptrfnres26)" "$(cat test/test_pointer_function_result_keeps_its_depth…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T05:55:32Z
- **Test source:** test/test_pointer_function_result_keeps_its_depth.pas tools/expect_same.sh +1
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh test/test_pointer_function_result_keeps_its_depth.expected`.
  ```
  tools/expect_same.sh test_ptrfnres26 "$(/tmp/test_ptrfnres26)" "$(cat test/test_pointer_function_result_keeps_its_depth.expected)"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_pointer_function_result_keeps_its_depth.pas'` at 85d70d70076a1caf2c9700132e8d2231ead77c21

## Range
> **The named sha `85d70d70076a` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `85d70d70076a`, last good `d0f14a2608ad`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2962168/test_ptrfnres26  [code=159512B  data=6176B  bss=51876B  procs=557]
expect_same: MISMATCH [test_ptrfnres26]
--- expected
+++ actual
@@ -1,7 +1,7 @@
 deref   : hello
 witharg : hello
 method  : hello
-index   : eo
+index   : 1869376613111
 midx    : e
 viavar  : hello
 concat  : xhello

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
