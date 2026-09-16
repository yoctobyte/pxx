---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 2 of 7, `/tmp/test_nilpy_openworld26 | diff -u test/test_nilpy_open_world_method_dispatch.expected -`, which names `test/test_nilpy_open_world_method_dispatch.expected`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_open_world_method_dispatch.npy at 67f0878f2e59 in step 2/7, `/tmp/test_nilpy_openworld26 | diff -u test/test_nilpy_open_world_method_dispatch.expected -` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-16T02:10:51Z
- **Test source:** test/test_nilpy_open_world_method_dispatch.npy test/test_nilpy_open_world_method_dispatch.expected
- **Failing step:** line 2 of 7 of the job's recipe; it names `test/test_nilpy_open_world_method_dispatch.expected`.
  ```
  /tmp/test_nilpy_openworld26 | diff -u test/test_nilpy_open_world_method_dispatch.expected -
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_open_world_method_dispatch.npy'` at 67f0878f2e594f042e00005391b213922d8f1047

## Range
> **The named sha `67f0878f2e59` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `67f0878f2e59`, last good `e572bd42501e`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
he receiver at run time
pascal26:11: warning: Nil Python: no class declares a method or callable field .zero() — dispatching on the receiver at run time
pascal26:11: warning: Nil Python: no class declares a method or callable field .zero() — dispatching on the receiver at run time
pascal26:15: warning: Nil Python: no class declares a method or callable field .one() — dispatching on the receiver at run time
pascal26:15: warning: Nil Python: no class declares a method or callable field .one() — dispatching on the receiver at run time
pascal26:19: warning: Nil Python: no class declares a method or callable field .two() — dispatching on the receiver at run time
pascal26:19: warning: Nil Python: no class declares a method or callable field .two() — dispatching on the receiver at run time
pascal26:23: warning: Nil Python: no class declares a method or callable field .three() — dispatching on the receiver at run time
pascal26:23: warning: Nil Python: no class declares a method or callable field .three() — dispatching on the receiver at run time
pascal26:27: warning: Nil Python: no class declares a method or callable field .four() — dispatching on the receiver at run time
pascal26:27: warning: Nil Python: no class declares a method or callable field .four() — dispatching on the receiver at run time
pascal26:47: warning: Nil Python: no class declares a method or callable field .no_such_name() — dispatching on the receiver at run time
pascal26:47: warning: Nil Python: no class declares a method or callable field .no_such_name() — dispatching on the receiver at run time
ok: /tmp/testmgr-scratch-4094684/test_nilpy_openworld26  [code=1359640B  data=89369B  bss=55004B  procs=2207]
--- test/test_nilpy_open_world_method_dispatch.expected	2026-09-12 00:21:02.338505147 +0200
+++ -	2026-09-16 04:06:23.197870999 +0200
@@ -1,4 +1,4 @@
-cross True False
+cross 1 0
 arity z10 2 3 6 10
 miss 'Canopy' object has no attribute 'no_such_name'
 miss 'int' object has no attribute 'no_such_name'

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-16 — auto-closed by the borg watcher: `test-nilpy#src:test/test_nilpy_open_world_method_dispatch.npy` passes at 881fdee59b6f (tier full); it was red at 67f0878f2e59. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
