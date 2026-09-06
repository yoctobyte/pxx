---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh test_tscfk26 "$(/tmp/test_tscfk26)" "$(printf 'errors=0\nKINDS OK')"`. The job's own `src` (`test/test_threadsafe_class_finalize_kinds.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-threads#src:test/test_threadsafe_class_finalize_kinds.pas at 918842a5fd43 in step 2/2, `tools/expect_same.sh test_tscfk26 "$(/tmp/test_tscfk26)" "$(printf 'errors=0\nKINDS OK')"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T12:52:28Z
- **Test source:** test/test_threadsafe_class_finalize_kinds.pas tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_tscfk26 "$(/tmp/test_tscfk26)" "$(printf 'errors=0\nKINDS OK')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-threads#src:test/test_threadsafe_class_finalize_kinds.pas'` at 918842a5fd4324bf93b3d2eeb84f7840a5844d22

## Range
> **The named sha `918842a5fd43` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `918842a5fd43`, last good `12af8ef60bfd`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-1028111/test_tscfk26  [code=175896B  data=9484B  bss=52020B  procs=613]
Segmentation fault (core dumped)
expect_same: MISMATCH [test_tscfk26]
--- expected
+++ actual
@@ -1,2 +1 @@
-errors=0
-KINDS OK
+

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
