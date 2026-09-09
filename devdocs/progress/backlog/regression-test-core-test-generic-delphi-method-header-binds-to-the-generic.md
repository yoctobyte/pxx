---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh sweep_gendelphi26 "$(/tmp/sweep_gendelphi26)" "$(printf '100\n100\n10\n10\n7\n2\n4')"`. The job's own `src` (`test/test_generic_delphi_method_header_binds_to_the_generic.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_generic_delphi_method_header_binds_to_the_generic.pas at 5acbe362b034 in step 2/2, `tools/expect_same.sh sweep_gendelphi26 "$(/tmp/sweep_gendelphi26)" "$(printf '100\n100\n10\n10\n7\n2\n4')"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `0c5ad13167ab`).
  Untriaged.
- **Found:** 2026-09-09T09:11:36Z
- **Test source:** test/test_generic_delphi_method_header_binds_to_the_generic.pas tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh sweep_gendelphi26 "$(/tmp/sweep_gendelphi26)" "$(printf '100\n100\n10\n10\n7\n2\n4')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_generic_delphi_method_header_binds_to_the_generic.pas'` at 5acbe362b0340998e9b2bf0aff83b52473839874

## Range
> **The named sha `5acbe362b034` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `5acbe362b034`, last good `06e404587e29`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:50: warning: duplicate definition of 'TSvc$Int64.Sel' with the same parameter types; the later body wins, but calls written between the two bind to the earlier one
ok: /tmp/testmgr-scratch-1784719/sweep_gendelphi26  [code=69400B  data=4280B  bss=43532B  procs=144]
expect_same: MISMATCH [sweep_gendelphi26]
--- expected
+++ actual
@@ -1,7 +1,7 @@
 100
 100
-10
-10
+100
+100
 7
 2
 4

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
