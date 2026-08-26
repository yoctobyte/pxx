---
prio: 70
track: N
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/dev has advanced 11 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_lowercase_name_vs_class.npy red at 99f1dc81a039 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-26T07:38:43Z
- **Test source:** test/test_nilpy_lowercase_name_vs_class.npy test/test_nilpy_lowercase_name_vs_class.expected

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_lowercase_name_vs_class.npy'` at 99f1dc81a039d8785db504b9f9b8917cf4e59783

## Range
> **The named sha `99f1dc81a039` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `99f1dc81a039`, last good `43b46283325f`, 54 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault
(tail)
ok: /tmp/testmgr-scratch-701739/test_nilpy_lowercase_name_vs_class26  [code=1246353B  data=55857B  bss=42436B  procs=1787]
Segmentation fault
--- test/test_nilpy_lowercase_name_vs_class.expected	2026-08-11 03:40:42.119641597 +0200
+++ -	2026-08-26 09:27:18.163047457 +0200
@@ -5,4 +5,3 @@
 F 3
 isinst True
 F 4
-valdef 5

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
