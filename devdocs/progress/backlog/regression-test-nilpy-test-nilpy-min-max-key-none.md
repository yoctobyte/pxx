---
prio: 70
track: N
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 47 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_min_max_key_none.npy red at 0200df7eabcd (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T02:33:24Z
- **Test source:** test/test_nilpy_min_max_key_none.npy test/test_nilpy_min_max_key_none.expected

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_min_max_key_none.npy'` at 0200df7eabcd33796c0f7ac151b80aafbf75b5fb

## Range
> **The named sha `0200df7eabcd` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `0200df7eabcd`, last good `3f854c927aac`, 6 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3750893/test_nilpy_mmkeynone26  [code=1265231B  data=55455B  bss=52028B  procs=1862]
Unhandled exception: TypeError: expected a number, got object
--- test/test_nilpy_min_max_key_none.expected	2026-08-29 16:03:42.852941360 +0000
+++ -	2026-08-30 02:07:44.379079193 +0000
@@ -1,9 +1,2 @@
 1 3
 1 3
-(2, 9)
-a c
-0 2
-3 1
-1 2 1 2
-1.5 b
-(1, 9) [2]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
