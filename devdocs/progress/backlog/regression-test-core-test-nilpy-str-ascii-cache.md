---
prio: 70
track: N
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_str_ascii_cache.npy red at a6698ac28e8b (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-29T19:00:03Z
- **Test source:** test/test_nilpy_str_ascii_cache.npy tools/expect_same.sh +1

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_str_ascii_cache.npy'` at a6698ac28e8b5dd3a62c2fd79b0c1d8b5c4be12a

## Range
> **The named sha `a6698ac28e8b` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `a6698ac28e8b`, last good `ee62e6dc0582`, 17 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1154419/test_nilpy_asciicache26  [code=1258808B  data=55220B  bss=50652B  procs=1859]
expect_same: MISMATCH [test_nilpy_asciicache26.2]
--- expected
+++ actual
@@ -6,7 +6,7 @@
 2 False ['é', 'l']
 True 0
 5 x True
-3 é False
+6 � True
 ['a', 'b', 'c', 'd', 'e', 'f'] ['h', 'é', 'l', 'l', 'o']
 500 50
 100 25 é é

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
