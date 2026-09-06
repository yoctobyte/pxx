---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh test_global_init26 "$(/tmp/test_global_init26)" "$(printf 'k=42 q=5000000000 flag=TRUE\ntabsum=150\`. The job's own `src` (`test/test_cross_global_init.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_cross_global_init.pas at 74526018b122 in step 2/2, `tools/expect_same.sh test_global_init26 "$(/tmp/test_global_init26)" "$(printf 'k=42 q=5000000000 flag=TRUE\ntabsum=150…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T14:55:02Z
- **Test source:** test/test_cross_global_init.pas tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_global_init26 "$(/tmp/test_global_init26)" "$(printf 'k=42 q=5000000000 flag=TRUE\ntabsum=150\nlutsum=6000000000')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_cross_global_init.pas'` at 74526018b122848d8763c96fcad7c9ab2a5c7c7a

## Range
> **The named sha `74526018b122` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `74526018b122`, last good `47aac577a587`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3030466/test_global_init26  [code=69400B  data=3072B  bss=43612B  procs=136]
expect_same: MISMATCH [test_global_init26]
--- expected
+++ actual
@@ -1,3 +1,3 @@
 k=42 q=5000000000 flag=TRUE
 tabsum=150
-lutsum=6000000000
+lutsum=1705032704

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
