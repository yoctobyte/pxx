---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 2 of 17, `/tmp/test_nilpy_zeroctor26 | diff -u test/test_nilpy_zero_argument_builtin_constructors.expected -`, which names `test/test_nilpy_zero_argument_builtin_constructors.expected`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_zero_argument_builtin_constructors.npy at d876977f4bb8 in step 2/17, `/tmp/test_nilpy_zeroctor26 | diff -u test/test_nilpy_zero_argument_builtin_constructors.expected -` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `f35167cd4e55`).
  Untriaged.
- **Found:** 2026-09-27T18:54:54Z
- **Test source:** test/test_nilpy_zero_argument_builtin_constructors.npy test/test_nilpy_zero_argument_builtin_constructors.expected
- **Failing step:** line 2 of 17 of the job's recipe; it names `test/test_nilpy_zero_argument_builtin_constructors.expected`.
  ```
  /tmp/test_nilpy_zeroctor26 | diff -u test/test_nilpy_zero_argument_builtin_constructors.expected -
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_zero_argument_builtin_constructors.npy'` at d876977f4bb8be3ba799d0ee179a2b391aef4e0b

## Range
> **The named sha `d876977f4bb8` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `d876977f4bb8`, last good `25ea38ef930d`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-119220/test_nilpy_zeroctor26  [code=479494B  data=103652B  bss=66444B  procs=2275  codeseg=483040B]
--- test/test_nilpy_zero_argument_builtin_constructors.expected	2026-09-11 21:30:22.035069937 +0200
+++ -	2026-09-27 20:50:39.124523110 +0200
@@ -8,8 +8,8 @@
 True True True True
 400
 [1, 2] 2 {'k': 0}
-('', 0, 1)
-('x', 3, 1)
+()
+()
 '' 0 []
 1 2 [0, 1]
 [0, 0, 0]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
