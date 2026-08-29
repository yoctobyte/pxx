---
prio: 70
track: N
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 12 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_str_ascii_cache.npy red at c513c0190421 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-29T19:28:01Z
- **Test source:** test/test_nilpy_str_ascii_cache.npy tools/expect_same.sh +1

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_str_ascii_cache.npy'` at c513c0190421a2a0c0eccb2eb99a7f4be6cf1aca

## Range
> **The named sha `c513c0190421` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `c513c0190421`, last good `1bffdc06510a`, 120 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-944164/test_nilpy_asciicache26  [code=1258808B  data=55220B  bss=50652B  procs=1859]
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

## Log
- 2026-08-29 — auto-closed by the seven watcher: `test-core#src:test/test_nilpy_str_ascii_cache.npy` passes at 2b33ab009963 (tier native); it was red at a6698ac28e8b. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
