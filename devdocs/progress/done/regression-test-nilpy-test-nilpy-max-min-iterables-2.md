---
prio: 70
track: N
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **This expectation records a REFUSAL** (ValueError). Before treating a converged bisect range as an accusation, check whether the named commit IMPLEMENTED the thing being refused -- a feature landing makes its own refusal test go red, and the bisect converges on it correctly. Not a verdict; the tool cannot decide this one.

> **origin/master has advanced 39 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_max_min_iterables.npy red at d8fae80063b0 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-30T06:57:06Z
- **Test source:** test/test_nilpy_max_min_iterables.npy test/test_nilpy_max_min_iterables.expected

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_max_min_iterables.npy'` at d8fae80063b05e72f0729ca466f3b76aaef12970

## Range
> **The named sha `d8fae80063b0` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `d8fae80063b0`, last good `e46dbffaa80d`, 176 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1393146/test_nilpy_maxmin_iter26  [code=1273680B  data=77175B  bss=53196B  procs=1860]
Unhandled exception: TypeError: expected a number, got object
--- test/test_nilpy_max_min_iterables.expected	2026-08-15 02:36:49.456276833 +0200
+++ -	2026-08-30 08:50:34.441609489 +0200
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

## Log
- 2026-08-30 — auto-closed by the seven watcher: `test-nilpy#src:test/test_nilpy_max_min_iterables.npy` passes at 023e802c88ea (tier full); it was red at 0200df7eabcd. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
