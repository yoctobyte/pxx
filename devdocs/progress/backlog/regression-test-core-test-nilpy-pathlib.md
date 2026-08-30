---
prio: 70
track: N
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_pathlib.npy red at dc798834ba33 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T18:15:54Z
- **Test source:** test/test_nilpy_pathlib.npy tools/expect_same.sh

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_pathlib.npy'` at dc798834ba33aee86e1af089a8e2579da57087e7

## Range
> **The named sha `dc798834ba33` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `dc798834ba33`, last good `fc9e258e1b71`, 6 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-1206433/test_nilpy_pathlib26  [code=1429272B  data=103388B  bss=83484B  procs=2170]
Segmentation fault (core dumped)
expect_same: MISMATCH [test_nilpy_pathlib26.2]
--- expected
+++ actual
@@ -2,7 +2,3 @@
 file
 .txt
 dir/sub
-dir/sub
-dir/sub
-False
-dir/sub

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
