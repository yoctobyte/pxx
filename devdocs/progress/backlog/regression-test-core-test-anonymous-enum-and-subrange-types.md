---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh test_anontype26 "$(/tmp/test_anontype26 | tail -1)" "ALL OK"`. The job's own `src` (`test/test_anonymous_enum_and_subrange_types.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_anonymous_enum_and_subrange_types.pas at 5be4c0665c1e in step 2/2, `tools/expect_same.sh test_anontype26 "$(/tmp/test_anontype26 | tail -1)" "ALL OK"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-02T12:20:52Z
- **Test source:** test/test_anonymous_enum_and_subrange_types.pas tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_anontype26 "$(/tmp/test_anontype26 | tail -1)" "ALL OK"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_anonymous_enum_and_subrange_types.pas'` at 5be4c0665c1e7f765cbe019fb9f87b725fb1f5d0

## Range
> **The named sha `5be4c0665c1e` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `5be4c0665c1e`, last good `adb676557642`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1141262/test_anontype26  [code=69400B  data=4952B  bss=43740B  procs=135]
expect_same: MISMATCH [test_anontype26]
--- expected
+++ actual
@@ -1 +1 @@
-ALL OK
+FAILURES 1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
