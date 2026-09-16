---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 2 of 15, `/tmp/test_nilpy_callsubst26 | diff -u test/test_nilpy_subscript_store_on_a_call_result.expected -`, which names `test/test_nilpy_subscript_store_on_a_call_result.expected`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_subscript_store_on_a_call_result.npy at 67f0878f2e59 in step 2/15, `/tmp/test_nilpy_callsubst26 | diff -u test/test_nilpy_subscript_store_on_a_call_result.expected -` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-16T01:50:14Z
- **Test source:** test/test_nilpy_subscript_store_on_a_call_result.npy test/test_nilpy_subscript_store_on_a_call_result.expected
- **Failing step:** line 2 of 15 of the job's recipe; it names `test/test_nilpy_subscript_store_on_a_call_result.expected`.
  ```
  /tmp/test_nilpy_callsubst26 | diff -u test/test_nilpy_subscript_store_on_a_call_result.expected -
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_subscript_store_on_a_call_result.npy'` at 67f0878f2e594f042e00005391b213922d8f1047

## Range
> **The named sha `67f0878f2e59` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `67f0878f2e59`, last good `e572bd42501e`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-4071561/test_nilpy_callsubst26  [code=1376024B  data=88848B  bss=176221316B  procs=2209]
--- test/test_nilpy_subscript_store_on_a_call_result.expected	2026-09-11 21:30:22.030538237 +0200
+++ -	2026-09-16 03:46:08.615284771 +0200
@@ -1,19 +1,2 @@
 7
 [10, 2, 3]
-51
-1 107
-169
-8.0
-8
-construction store survived
-{'n': 5}
-102
-{'row': [1, 10, 3]}
-[10, 7, 8]
-read-only receiver refused: 'RO' object does not support item assignment
-42
-1764
-[5, 2, 3]
-1 6
-5
-2
Segmentation fault (core dumped)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-16 — auto-closed by the borg watcher: `test-core#src:test/test_nilpy_subscript_store_on_a_call_result.npy` passes at 881fdee59b6f (tier native); it was red at 67f0878f2e59. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
