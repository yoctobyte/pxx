---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 1 of 75, `./compiler/pascal26 --no-shims test/test_nilpy_import_sqlite.npy /tmp/test_nilpy_import_sqlite26`, which names `test/test_nilpy_import_sqlite.npy`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 4 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_import_sqlite.npy at 62fc7c1e802a in step 1/75, `./compiler/pascal26 --no-shims test/test_nilpy_import_sqlite.npy /tmp/test_nilpy_import_sqlite26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `97528b18bd0f`).
  Untriaged.
- **Found:** 2026-10-05T05:03:58Z
- **Test source:** test/test_nilpy_import_sqlite.npy lib/rtl/zlib.pas +2
- **Failing step:** line 1 of 75 of the job's recipe; it names `test/test_nilpy_import_sqlite.npy`.
  ```
  ./compiler/pascal26 --no-shims test/test_nilpy_import_sqlite.npy /tmp/test_nilpy_import_sqlite26
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_import_sqlite.npy'` at 62fc7c1e802a126b623b3219bbaf6020750733e9

## Range
> **The named sha `62fc7c1e802a` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `62fc7c1e802a`, last good `2e07225c3cd1`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:1: error: undefined reference to extern variable `sqlite3_version': it is declared `extern' and used, and nothing defines it. An executable has no import for it to bind to, so it would read zero. Define it in one translation unit, or build with --emit-obj and link it where it is defined
(tail)
pascal26:1: error: undefined reference to extern variable `sqlite3_version': it is declared `extern' and used, and nothing defines it. An executable has no import for it to bind to, so it would read zero. Define it in one translation unit, or build with --emit-obj and link it where it is defined

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
