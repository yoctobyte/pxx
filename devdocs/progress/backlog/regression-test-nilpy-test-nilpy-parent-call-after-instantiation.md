---
prio: 70
track: N
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 11 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_parent_call_after_instantiation.npy red at b898d0543fc8 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-27T20:46:31Z
- **Test source:** test/test_nilpy_parent_call_after_instantiation.npy test/test_nilpy_parent_call_after_instantiation.expected

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_parent_call_after_instantiation.npy'` at b898d0543fc8499facc66706257ff08d39195520

## Range
> **The named sha `b898d0543fc8` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `b898d0543fc8`, last good `8b2cc332791e`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-25046/test_nilpy_parentcall26  [code=1271989B  data=57044B  bss=42108B  procs=1810]
--- test/test_nilpy_parent_call_after_instantiation.expected	2026-08-02 15:18:13.701581110 +0200
+++ -	2026-08-27 22:40:16.217688721 +0200
@@ -1,4 +1,2 @@
 E:A A
 F:B B
-C G:C
-H:G:C
Segmentation fault (core dumped)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
