---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 2 of 5, `/tmp/test_nilpy_dictupdkw26 | diff -u test/test_nilpy_dict_update_keywords.expected -`, which names `test/test_nilpy_dict_update_keywords.expected`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_dict_update_keywords.npy at 16993f9196cf in step 2/5, `/tmp/test_nilpy_dictupdkw26 | diff -u test/test_nilpy_dict_update_keywords.expected -` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `883da23adb0a`).
  Untriaged.
- **Found:** 2026-09-10T13:44:50Z
- **Test source:** test/test_nilpy_dict_update_keywords.npy test/test_nilpy_dict_update_keywords.expected
- **Failing step:** line 2 of 5 of the job's recipe; it names `test/test_nilpy_dict_update_keywords.expected`.
  ```
  /tmp/test_nilpy_dictupdkw26 | diff -u test/test_nilpy_dict_update_keywords.expected -
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_dict_update_keywords.npy'` at 16993f9196cfbf820b5316b6cc0ccad881c6b7f8

## Range
> **The named sha `16993f9196cf` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `16993f9196cf`, last good `8dbfe1659549`, 7 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:66: warning: Nil Python: no class here declares a .update() with a parameter named 'r' — dispatching on the receiver at run time
pascal26:72: warning: Nil Python: no class here declares a .update() with a parameter named 'a' — dispatching on the receiver at run time
pascal26:72: warning: Nil Python: no class here declares a .update() with a parameter named 'a' — dispatching on the receiver at run time
ok: /tmp/testmgr-scratch-775162/test_nilpy_dictupdkw26  [code=1380120B  data=84876B  bss=58604B  procs=2274]
--- test/test_nilpy_dict_update_keywords.expected	2026-08-29 16:03:42.825941361 +0000
+++ -	2026-09-10 13:33:50.818628084 +0000
@@ -10,14 +10,4 @@
 {}
 {'sum': 6, 'txt': 'ab', 'none': None, 'lst': [1, 2]}
 {'p': 1, 'q': 2}
-{'r': 1, 's': 2}
-{'a': 1, 'b': 2, 'c': 3}
-{'x': 1, 'y': 2}
-True
-{'a': 0, 'b': 1, 'c': 2}
-{'k': 1, 'y': 2}
-{'k': 1, 'z': 9, 'w': 5}
-{'x': 1, 'b': 2}
-{'f': 7}
-{}
-{'q': 1}
+pyeval: host method update has no parameter named r

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-10 — auto-closed by the seven watcher: `test-nilpy#src:test/test_nilpy_dict_update_keywords.npy` passes at 8cc1b9a526b2 (tier full); it was red at 16993f9196cf. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
