---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh test_typenames26 "$(/tmp/test_typenames26 | tail -1)" "ALL OK"`. The job's own `src` (`test/test_builtin_type_names_cast_and_declare.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_builtin_type_names_cast_and_declare.pas at b6815e5b8675 in step 2/2, `tools/expect_same.sh test_typenames26 "$(/tmp/test_typenames26 | tail -1)" "ALL OK"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T05:14:07Z
- **Test source:** test/test_builtin_type_names_cast_and_declare.pas tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_typenames26 "$(/tmp/test_typenames26 | tail -1)" "ALL OK"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_builtin_type_names_cast_and_declare.pas'` at b6815e5b8675574de5b67897c9ac06f5c87afeab

## Range
bad `b6815e5b8675`, last good `f1148d82c2d4`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2297346/test_typenames26  [code=163608B  data=7360B  bss=52308B  procs=555]
expect_same: MISMATCH [test_typenames26]
--- expected
+++ actual
@@ -1 +1 @@
-ALL OK
+1 FAILURES

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
