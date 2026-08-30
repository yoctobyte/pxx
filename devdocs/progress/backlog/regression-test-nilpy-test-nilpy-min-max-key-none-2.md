---
prio: 70
track: N
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 33 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_min_max_key_none.npy red at 9fa9e145ea79 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-30T08:44:28Z
- **Test source:** test/test_nilpy_min_max_key_none.npy test/test_nilpy_min_max_key_none.expected

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_min_max_key_none.npy'` at 9fa9e145ea79f8b9a9d598225059ae51150d26ce

## Range
> **The named sha `9fa9e145ea79` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `9fa9e145ea79`, last good `e46dbffaa80d`, 216 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2339552/test_nilpy_mmkeynone26  [code=1269528B  data=77183B  bss=52028B  procs=1868]
Unhandled exception: TypeError: '<' not supported between instances of 'int' and 'str'
--- test/test_nilpy_min_max_key_none.expected	2026-08-14 02:00:11.829874959 +0200
+++ -	2026-08-30 10:32:09.573328890 +0200
@@ -1,9 +1,3 @@
 1 3
 1 3
 (2, 9)
-a c
-0 2
-3 1
-1 2 1 2
-1.5 b
-(1, 9) [2]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
