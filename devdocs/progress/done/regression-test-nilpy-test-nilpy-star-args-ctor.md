---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 1 of 2, `./compiler/pascal26 test/test_nilpy_star_args_ctor.npy /tmp/test_nilpy_star_args_ctor26`, which names `test/test_nilpy_star_args_ctor.npy`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 16 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_star_args_ctor.npy at 18f97d8f5f1f in step 1/2, `./compiler/pascal26 test/test_nilpy_star_args_ctor.npy /tmp/test_nilpy_star_args_ctor26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-05T23:47:03Z
- **Test source:** test/test_nilpy_star_args_ctor.npy test/test_nilpy_star_args_ctor.expected
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/test_nilpy_star_args_ctor.npy`.
  ```
  ./compiler/pascal26 test/test_nilpy_star_args_ctor.npy /tmp/test_nilpy_star_args_ctor26
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_star_args_ctor.npy'` at 18f97d8f5f1f45d26582b7ec7ff0b23dcbbd688c

## Range
> **The named sha `18f97d8f5f1f` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `18f97d8f5f1f`, last good `81a10ecb3dba`, 5 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:76: error: no overload of m matches these arguments
(tail)
pascal26:76: error: no overload of m matches these arguments
  near: ( "v" ) , q . >>> m ( "v" 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-06 — auto-closed by the seven watcher: `test-nilpy#src:test/test_nilpy_star_args_ctor.npy` passes at ef03a6282980 (tier full); it was red at 18f97d8f5f1f. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
