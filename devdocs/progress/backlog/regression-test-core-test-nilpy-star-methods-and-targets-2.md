---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 1 of 2, `./compiler/pascal26 test/test_nilpy_star_methods_and_targets.npy /tmp/test_nilpy_starm26`, which names `test/test_nilpy_star_methods_and_targets.npy`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_star_methods_and_targets.npy at 18f97d8f5f1f in step 1/2, `./compiler/pascal26 test/test_nilpy_star_methods_and_targets.npy /tmp/test_nilpy_starm26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-05T23:36:52Z
- **Test source:** test/test_nilpy_star_methods_and_targets.npy tools/expect_same.sh
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/test_nilpy_star_methods_and_targets.npy`.
  ```
  ./compiler/pascal26 test/test_nilpy_star_methods_and_targets.npy /tmp/test_nilpy_starm26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_star_methods_and_targets.npy'` at 18f97d8f5f1f45d26582b7ec7ff0b23dcbbd688c

## Range
> **The named sha `18f97d8f5f1f` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `18f97d8f5f1f`, last good `81a10ecb3dba`, 5 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:47: error: no overload of take matches these arguments
(tail)
pascal26:47: error: no overload of take matches these arguments
  near: )  print ( b . >>> take ( 1 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
