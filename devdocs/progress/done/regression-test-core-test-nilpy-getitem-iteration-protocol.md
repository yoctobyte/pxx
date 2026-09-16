---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 2 of 11, `/tmp/test_nilpy_getitemiter26 | diff -u test/test_nilpy_getitem_iteration_protocol.expected -`, which names `test/test_nilpy_getitem_iteration_protocol.expected`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_getitem_iteration_protocol.npy at 67f0878f2e59 in step 2/11, `/tmp/test_nilpy_getitemiter26 | diff -u test/test_nilpy_getitem_iteration_protocol.expected -` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-16T01:50:14Z
- **Test source:** test/test_nilpy_getitem_iteration_protocol.npy test/test_nilpy_getitem_iteration_protocol.expected
- **Failing step:** line 2 of 11 of the job's recipe; it names `test/test_nilpy_getitem_iteration_protocol.expected`.
  ```
  /tmp/test_nilpy_getitemiter26 | diff -u test/test_nilpy_getitem_iteration_protocol.expected -
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_getitem_iteration_protocol.npy'` at 67f0878f2e594f042e00005391b213922d8f1047

## Range
> **The named sha `67f0878f2e59` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `67f0878f2e59`, last good `e572bd42501e`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-4071561/test_nilpy_getitemiter26  [code=1359640B  data=88698B  bss=56204B  procs=2199]
Segmentation fault (core dumped)
--- test/test_nilpy_getitem_iteration_protocol.expected	2026-09-11 21:30:22.007070834 +0200
+++ -	2026-09-16 03:46:32.621706264 +0200
@@ -1,24 +0,0 @@
-1
-2
-3
-[2, 4, 6]
-[1, 2, 3]
-(1, 2, 3)
-6
-3 1
-True False
-[1, 2, 3]
-[3, 2, 1]
-[(1, 'a'), (2, 'b'), (3, 'c')]
-[(0, 1), (1, 2), (2, 3)]
-['1', '2', '3']
-True True
-1 2 3
-1, 2, 3
-7
-8
-[4, 5, 6]
-6
-[1, 2, 3]
-6
-[1, 2, 3]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-16 — auto-closed by the borg watcher: `test-core#src:test/test_nilpy_getitem_iteration_protocol.npy` passes at 881fdee59b6f (tier native); it was red at 67f0878f2e59. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
