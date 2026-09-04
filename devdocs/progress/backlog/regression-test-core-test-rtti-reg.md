---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh test_rtti_reg26 "$(/tmp/test_rtti_reg26)" "$(printf 'Count: 3\nClass 0: TInterfacedObject\nClass 1:`. The job's own `src` (`test/test_rtti_reg.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_rtti_reg.pas at 6b08a2ae84f2 in step 2/2, `tools/expect_same.sh test_rtti_reg26 "$(/tmp/test_rtti_reg26)" "$(printf 'Count: 3\nClass 0: TInterfacedObject\nClass 1…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-04T15:56:12Z
- **Test source:** test/test_rtti_reg.pas tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_rtti_reg26 "$(/tmp/test_rtti_reg26)" "$(printf 'Count: 3\nClass 0: TInterfacedObject\nClass 1: TBase\nClass 2: TChild')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_rtti_reg.pas'` at 6b08a2ae84f25d82d969d88c528f776847a93801

## Range
> **The named sha `6b08a2ae84f2` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `6b08a2ae84f2`, last good `3d68386f85e7`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2090791/test_rtti_reg26  [code=65304B  data=3648B  bss=43524B  procs=136]
expect_same: MISMATCH [test_rtti_reg26]
--- expected
+++ actual
@@ -1,4 +1,4 @@
 Count: 3
-Class 0: TInterfacedObject
-Class 1: TBase
-Class 2: TChild
+Class 0: TInterface
+Class 1: 
+Class 2: 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
