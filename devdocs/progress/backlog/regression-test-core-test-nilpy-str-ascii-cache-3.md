---
prio: 70
track: N
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_str_ascii_cache.npy red at dc798834ba33 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T18:15:54Z
- **Test source:** test/test_nilpy_str_ascii_cache.npy tools/expect_same.sh +1

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_str_ascii_cache.npy'` at dc798834ba33aee86e1af089a8e2579da57087e7

## Range
> **The named sha `dc798834ba33` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `dc798834ba33`, last good `fc9e258e1b71`, 6 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-1206433/test_nilpy_asciicache26  [code=1273624B  data=77140B  bss=50652B  procs=1871]
Segmentation fault (core dumped)
expect_same: MISMATCH [test_nilpy_asciicache26.2]
--- expected
+++ actual
@@ -5,8 +5,6 @@
 7 f é False
 2 False ['é', 'l']
 True 0
-5 x True
-3 é False
+600  True
+129168  False
 ['a', 'b', 'c', 'd', 'e', 'f'] ['h', 'é', 'l', 'l', 'o']
-500 50
-100 25 é é

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
