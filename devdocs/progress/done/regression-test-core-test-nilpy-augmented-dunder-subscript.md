---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 2 of 16, `/tmp/test_nilpy_augdunsub26 | diff -u test/test_nilpy_augmented_dunder_subscript.expected -`, which names `test/test_nilpy_augmented_dunder_subscript.expected`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **This expectation records a REFUSAL** (TypeError). Before treating a converged bisect range as an accusation, check whether the named commit IMPLEMENTED the thing being refused -- a feature landing makes its own refusal test go red, and the bisect converges on it correctly. Not a verdict; the tool cannot decide this one.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_augmented_dunder_subscript.npy at 67f0878f2e59 in step 2/16, `/tmp/test_nilpy_augdunsub26 | diff -u test/test_nilpy_augmented_dunder_subscript.expected -` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-16T01:50:14Z
- **Test source:** test/test_nilpy_augmented_dunder_subscript.npy test/test_nilpy_augmented_dunder_subscript.expected
- **Failing step:** line 2 of 16 of the job's recipe; it names `test/test_nilpy_augmented_dunder_subscript.expected`.
  ```
  /tmp/test_nilpy_augdunsub26 | diff -u test/test_nilpy_augmented_dunder_subscript.expected -
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_augmented_dunder_subscript.npy'` at 67f0878f2e594f042e00005391b213922d8f1047

## Range
> **The named sha `67f0878f2e59` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `67f0878f2e59`, last good `e572bd42501e`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
pascal26:42: warning: Nil Python: operator '-' is not defined for that type and int — both operand types are provable here, so this raises TypeError if it runs
pascal26:44: warning: Nil Python: operator '//' is not defined for that type and int — both operand types are provable here, so this raises TypeError if it runs
pascal26:46: warning: Nil Python: operator '%' is not defined for that type and int — both operand types are provable here, so this raises TypeError if it runs
pascal26:57: warning: Nil Python: operator '/' is not defined for that type and int — both operand types are provable here, so this raises TypeError if it runs
ok: /tmp/testmgr-scratch-4071561/test_nilpy_augdunsub26  [code=1359640B  data=89182B  bss=134274196B  procs=2200]
Segmentation fault (core dumped)
--- test/test_nilpy_augmented_dunder_subscript.expected	2026-09-11 21:30:21.992071315 +0200
+++ -	2026-09-16 03:46:16.925116553 +0200
@@ -1,11 +1 @@
 5
-6
-8
-22
-3.5
-1 9
-2 3
-13
-TypeError: 'OnlySet' object is not subscriptable
-TypeError: 'OnlyGet' object does not support item assignment
-3

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-16 — auto-closed by the borg watcher: `test-core#src:test/test_nilpy_augmented_dunder_subscript.npy` passes at 881fdee59b6f (tier native); it was red at 67f0878f2e59. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
