---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh test_sizeof_shadow26 "$(/tmp/test_sizeof_shadow26)" "$(printf 'a 12\nb 10\nc TRUE\nd 1\ne 1\nf 8\ng`. The job's own `src` (`test/test_sizeof_user_name_shadows_builtin.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_sizeof_user_name_shadows_builtin.pas at 5ad048c2d9ae in step 2/2, `tools/expect_same.sh test_sizeof_shadow26 "$(/tmp/test_sizeof_shadow26)" "$(printf 'a 12\nb 10\nc TRUE\nd 1\ne 1\nf 8\n…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-02T16:09:42Z
- **Test source:** test/test_sizeof_user_name_shadows_builtin.pas tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_sizeof_shadow26 "$(/tmp/test_sizeof_shadow26)" "$(printf 'a 12\nb 10\nc TRUE\nd 1\ne 1\nf 8\ng 4 8 2\nh 4 8 8\ni TRUE x 5')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_sizeof_user_name_shadows_builtin.pas'` at 5ad048c2d9ae35a65937eee29c7e4e1e498b2846

## Range
> **The named sha `5ad048c2d9ae` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `5ad048c2d9ae`, last good `08f7de0715a8`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2929954/test_sizeof_shadow26  [code=114456B  data=5800B  bss=43568B  procs=248]
expect_same: MISMATCH [test_sizeof_shadow26]
--- expected
+++ actual
@@ -7,3 +7,8 @@
 g 4 8 2
 h 4 8 8
 i TRUE x 5
+j 12
+k 6
+l 12 12
+m 10
+n 2 1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
