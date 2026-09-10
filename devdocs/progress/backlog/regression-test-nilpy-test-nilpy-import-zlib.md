---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 1 of 10, `./compiler/pascal26 test/test_nilpy_import_zlib.npy /tmp/test_nilpy_import_zlib26`, which names `test/test_nilpy_import_zlib.npy`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 13 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_import_zlib.npy at 814fe90dfb65 in step 1/10, `./compiler/pascal26 test/test_nilpy_import_zlib.npy /tmp/test_nilpy_import_zlib26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `883da23adb0a`).
  Untriaged.
- **Found:** 2026-09-10T23:27:48Z
- **Test source:** test/test_nilpy_import_zlib.npy tools/expect_same.sh
- **Failing step:** line 1 of 10 of the job's recipe; it names `test/test_nilpy_import_zlib.npy`.
  ```
  ./compiler/pascal26 test/test_nilpy_import_zlib.npy /tmp/test_nilpy_import_zlib26
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_import_zlib.npy'` at 814fe90dfb6558e1f7cdb85718ad11f32f68c8ce

## Range
> **The named sha `814fe90dfb65` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `814fe90dfb65`, last good `ea21a78cd17a`, 5 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:20: error: undefined variable (compressBound)
(tail)
pascal26:20: error: undefined variable (compressBound)
  near: import zlib  print ( compressBound >>> ( 1000 ) 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
