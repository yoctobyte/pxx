---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 2 of 5, `/tmp/test_nilpy_delitem26 | diff -u test/test_nilpy_delitem_dunder.expected -`, which names `test/test_nilpy_delitem_dunder.expected`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **This expectation records a REFUSAL** (TypeError). Before treating a converged bisect range as an accusation, check whether the named commit IMPLEMENTED the thing being refused -- a feature landing makes its own refusal test go red, and the bisect converges on it correctly. Not a verdict; the tool cannot decide this one.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_delitem_dunder.npy at 67f0878f2e59 in step 2/5, `/tmp/test_nilpy_delitem26 | diff -u test/test_nilpy_delitem_dunder.expected -` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-16T02:10:51Z
- **Test source:** test/test_nilpy_delitem_dunder.npy test/test_nilpy_delitem_dunder.expected
- **Failing step:** line 2 of 5 of the job's recipe; it names `test/test_nilpy_delitem_dunder.expected`.
  ```
  /tmp/test_nilpy_delitem26 | diff -u test/test_nilpy_delitem_dunder.expected -
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_delitem_dunder.npy'` at 67f0878f2e594f042e00005391b213922d8f1047

## Range
> **The named sha `67f0878f2e59` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `67f0878f2e59`, last good `e572bd42501e`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-4094684/test_nilpy_delitem26  [code=1355544B  data=88732B  bss=55124B  procs=2198]
--- test/test_nilpy_delitem_dunder.expected	2026-09-11 21:30:22.000737443 +0200
+++ -	2026-09-16 04:06:52.487720601 +0200
@@ -1,13 +1 @@
-read   1
-keys   ['a', 'b', 'c', 'd']
-del a
-after  ['b', 'c', 'd']
-key evaluated
-del b
-after2 ['c', 'd']
-onlydel 7
-nodel  TypeError
-dict   {'y': 2}
-index  [0, 2, 3, 4]
-slice  [0, 4]
-readdel TypeError
+read   
\ No newline at end of file
Segmentation fault (core dumped)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
