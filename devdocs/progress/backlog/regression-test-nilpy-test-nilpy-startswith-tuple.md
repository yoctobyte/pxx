---
prio: 70
track: N
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 11 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_startswith_tuple.npy red at b898d0543fc8 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-27T20:46:31Z
- **Test source:** test/test_nilpy_startswith_tuple.npy test/test_nilpy_startswith_tuple.expected

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_startswith_tuple.npy'` at b898d0543fc8499facc66706257ff08d39195520

## Range
> **The named sha `b898d0543fc8` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `b898d0543fc8`, last good `8b2cc332791e`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-25046/test_nilpy_swtuple26  [code=1277065B  data=55459B  bss=42588B  procs=1804]
Segmentation fault (core dumped)
--- test/test_nilpy_startswith_tuple.expected	2026-08-09 01:14:26.952809883 +0200
+++ -	2026-08-27 22:41:21.249287413 +0200
@@ -4,5 +4,3 @@
 plain      True True
 window     True True
 winmiss    False
-param      True False
-platform   False True

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
