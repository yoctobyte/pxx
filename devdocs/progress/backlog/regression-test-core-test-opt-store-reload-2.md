---
prio: 70
track: P
---

> **Track guessed as P from the FAILING STEP** — line 1 of 28, `./compiler/pascal26 test/test_opt_store_reload.pas /tmp/test_opt_sr_O0 >/dev/null`, which names `test/test_opt_store_reload.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_opt_store_reload.pas at 2c09be089d8d in step 1/28, `./compiler/pascal26 test/test_opt_store_reload.pas /tmp/test_opt_sr_O0 >/dev/null` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1f06bcf02d3f`).
  Untriaged.
- **Found:** 2026-09-19T17:14:49Z
- **Test source:** test/test_opt_store_reload.pas tools/expect_same.sh
- **Failing step:** line 1 of 28 of the job's recipe; it names `test/test_opt_store_reload.pas`.
  ```
  ./compiler/pascal26 test/test_opt_store_reload.pas /tmp/test_opt_sr_O0 >/dev/null
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-core#src:test/test_opt_store_reload.pas'` at 2c09be089d8db296b8e2e4a9eb83b8e487fa93a4

## Range
> **The named sha `2c09be089d8d` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `2c09be089d8d`, last good `ff2d50a2bde9`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26: error: the output file was truncated: /tmp/testmgr-scratch-2865077/test_opt_sr_O0
(tail)
pascal26: error: the output file was truncated: /tmp/testmgr-scratch-2865077/test_opt_sr_O0
  a write stored fewer bytes than it was asked to; the file on disk is incomplete.
  usual cause: the filesystem is full (ENOSPC) or a file-size limit.

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
