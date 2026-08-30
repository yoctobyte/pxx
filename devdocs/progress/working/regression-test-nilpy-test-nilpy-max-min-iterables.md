---
prio: 70
track: N
status: working
owner: frankA
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **This expectation records a REFUSAL** (ValueError). Before treating a converged bisect range as an accusation, check whether the named commit IMPLEMENTED the thing being refused -- a feature landing makes its own refusal test go red, and the bisect converges on it correctly. Not a verdict; the tool cannot decide this one.

> **origin/master has advanced 47 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_max_min_iterables.npy red at 0200df7eabcd (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T02:33:24Z
- **Test source:** test/test_nilpy_max_min_iterables.npy test/test_nilpy_max_min_iterables.expected

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_max_min_iterables.npy'` at 0200df7eabcd33796c0f7ac151b80aafbf75b5fb

## Range
> **The named sha `0200df7eabcd` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `0200df7eabcd`, last good `3f854c927aac`, 6 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3750893/test_nilpy_maxmin_iter26  [code=1272141B  data=55351B  bss=53196B  procs=1860]
Unhandled exception: TypeError: expected a number, got object
--- test/test_nilpy_max_min_iterables.expected	2026-08-29 16:03:42.850941360 +0000
+++ -	2026-08-30 02:08:28.243527547 +0000
@@ -3,13 +3,3 @@
 3 1
 z a
 none none
-b b
-3 1
-c a
-3 0
-99 97
-6 2
-9 2
-[1, 2] [3]
-7 3 2.5 a
-ValueError: max() iterable argument is empty

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
