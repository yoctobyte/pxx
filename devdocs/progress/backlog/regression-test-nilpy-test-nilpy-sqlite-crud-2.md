---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 1 of 14, `./compiler/pascal26 test/test_nilpy_sqlite_crud.npy /tmp/test_nilpy_sqlite_crud26`, which names `test/test_nilpy_sqlite_crud.npy`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 3 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 11 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_sqlite_crud.npy at 42d05b7c18c7 in step 1/14, `./compiler/pascal26 test/test_nilpy_sqlite_crud.npy /tmp/test_nilpy_sqlite_crud26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `883da23adb0a`).
  Untriaged.
- **Found:** 2026-09-10T22:29:45Z
- **Test source:** test/test_nilpy_sqlite_crud.npy tools/expect_same.sh +1
- **Failing step:** line 1 of 14 of the job's recipe; it names `test/test_nilpy_sqlite_crud.npy`.
  ```
  ./compiler/pascal26 test/test_nilpy_sqlite_crud.npy /tmp/test_nilpy_sqlite_crud26
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_sqlite_crud.npy'` at 42d05b7c18c795aac1fbfc07270794bc6165862d

## Range
> **The named sha `42d05b7c18c7` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `42d05b7c18c7`, last good `10b61073d389`, 6 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:7: error: undefined variable (sqlite3_open)
(tail)
note: sqlite3 -> mimic_sqlite3 (shim, subset)
pascal26:7: error: undefined variable (sqlite3_open)
  near: import sqlite3  db = sqlite3_open >>> ( "/tmp/test_nilpy_sqlite_crud.db" ) 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
