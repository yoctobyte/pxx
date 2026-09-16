---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 4 is `tools/expect_same.sh test_nilpy_dundergetset26 "$(/tmp/test_nilpy_dundergetset26)" "$(printf '%b' '20\n99\n[10, 99, 30]\`. The job's own `src` (`test/test_nilpy_dunder_getitem_setitem.npy`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `test_nilpy_dunder_getitem_setitem`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `expect_same`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_dunder_getitem_setitem.npy at 67f0878f2e59 in step 2/4, `tools/expect_same.sh test_nilpy_dundergetset26 "$(/tmp/test_nilpy_dundergetset26)" "$(printf '%b' '20\n99\n[10, 99, 30]…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-16T02:10:51Z
- **Test source:** test/test_nilpy_dunder_getitem_setitem.npy tools/expect_same.sh
- **Failing step:** line 2 of 4 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_nilpy_dundergetset26 "$(/tmp/test_nilpy_dundergetset26)" "$(printf '%b' '20\n99\n[10, 99, 30]\n42\n-1\n10\ncaught: TypeError')"
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_dunder_getitem_setitem.npy'` at 67f0878f2e594f042e00005391b213922d8f1047

## Range
> **The named sha `67f0878f2e59` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `67f0878f2e59`, last good `e572bd42501e`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-4094684/test_nilpy_dundergetset26  [code=1351448B  data=88202B  bss=54772B  procs=2197]
Segmentation fault (core dumped)
expect_same: MISMATCH [test_nilpy_dundergetset26]
--- expected
+++ actual
@@ -1,7 +1 @@
-20
-99
-[10, 99, 30]
-42
--1
-10
-caught: TypeError
+

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
