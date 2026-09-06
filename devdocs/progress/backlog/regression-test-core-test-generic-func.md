---
prio: 70
track: P
---

> **Track guessed as P from the FAILING STEP** — line 1 of 2, `./compiler/pascal26 test/test_generic_func.pas /tmp/test_generic_func26`, which names `test/test_generic_func.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_generic_func.pas at b2a41d5f4fb9 in step 1/2, `./compiler/pascal26 test/test_generic_func.pas /tmp/test_generic_func26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T16:20:47Z
- **Test source:** test/test_generic_func.pas tools/expect_same.sh
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/test_generic_func.pas`.
  ```
  ./compiler/pascal26 test/test_generic_func.pas /tmp/test_generic_func26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_generic_func.pas'` at b2a41d5f4fb93afe09b23d1b7ee3999eaa906523

## Range
> **The named sha `b2a41d5f4fb9` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `b2a41d5f4fb9`, last good `29c40526f145`, 9 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:26: error: expected 'begin' before 'Max_Integer'
(tail)
pascal26:26: error: expected 'begin' before 'Max_Integer'
  near: B := tmp ; end ; >>> Max_Integer as MaxIntF 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
