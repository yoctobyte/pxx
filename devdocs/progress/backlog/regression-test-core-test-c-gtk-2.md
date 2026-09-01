---
prio: 70
track: P
---

> **Track guessed as P from the FAILING STEP** — line 1 of 2, `./compiler/pascal26 test/test_c_gtk.pas /tmp/test_c_gtk26`, which names `test/test_c_gtk.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_c_gtk.pas at 1236bf31f930 in step 1/2, `./compiler/pascal26 test/test_c_gtk.pas /tmp/test_c_gtk26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5ea286a98481`).
  Untriaged.
- **Found:** 2026-09-01T23:24:59Z
- **Test source:** test/test_c_gtk.pas tools/expect_same.sh
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/test_c_gtk.pas`.
  ```
  ./compiler/pascal26 test/test_c_gtk.pas /tmp/test_c_gtk26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_c_gtk.pas'` at 1236bf31f93084fe322e626880cc6132a33cf64a

## Range
> **The named sha `1236bf31f930` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `1236bf31f930`, last good `ba98601dd917`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:311: error: call to undeclared function: __builtin_constant_p
(tail)
pascal26:311: error: call to undeclared function: __builtin_constant_p
  near:  __builtin_constant_p   str  >>>   str 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
