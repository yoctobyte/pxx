---
prio: 70
track: P
---

> **Track guessed as P from the FAILING STEP** — line 1 of 4, `./compiler/pascal26 test/test_sqlite_crud_lazy.pas /tmp/test_sqlite_crud_lazy26`, which names `test/test_sqlite_crud_lazy.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 3 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_sqlite_crud_lazy.pas at f33eeb316d43 in step 1/4, `./compiler/pascal26 test/test_sqlite_crud_lazy.pas /tmp/test_sqlite_crud_lazy26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `97528b18bd0f`).
  Untriaged.
- **Found:** 2026-10-05T04:32:10Z
- **Test source:** test/test_sqlite_crud_lazy.pas tools/expect_same.sh +1
- **Failing step:** line 1 of 4 of the job's recipe; it names `test/test_sqlite_crud_lazy.pas`.
  ```
  ./compiler/pascal26 test/test_sqlite_crud_lazy.pas /tmp/test_sqlite_crud_lazy26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_sqlite_crud_lazy.pas'` at f33eeb316d4362d85006b8b0dae50990f28fcce0

## Range
> **The named sha `f33eeb316d43` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `f33eeb316d43`, last good `9f0bfc4a4bd3`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:1: error: undefined reference to extern variable `sqlite3_version': it is declared `extern' and used, and nothing defines it. An executable has no import for it to bind to, so it would read zero. Define it in one translation unit, or build with --emit-obj and link it where it is defined
(tail)
pascal26:1: error: undefined reference to extern variable `sqlite3_version': it is declared `extern' and used, and nothing defines it. An executable has no import for it to bind to, so it would read zero. Define it in one translation unit, or build with --emit-obj and link it where it is defined

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
