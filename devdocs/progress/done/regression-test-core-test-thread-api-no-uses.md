---
prio: 70
track: P
---

> **Track guessed as P from the FAILING STEP** — line 1 of 2, `./compiler/pascal26 test/test_thread_api_no_uses.pas /tmp/test_thread_api_no_uses26`, which names `test/test_thread_api_no_uses.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_thread_api_no_uses.pas at 970eabd8eadf in step 1/2, `./compiler/pascal26 test/test_thread_api_no_uses.pas /tmp/test_thread_api_no_uses26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5ea286a98481`).
  Untriaged.
- **Found:** 2026-09-01T19:41:04Z
- **Test source:** test/test_thread_api_no_uses.pas tools/expect_same.sh
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/test_thread_api_no_uses.pas`.
  ```
  ./compiler/pascal26 test/test_thread_api_no_uses.pas /tmp/test_thread_api_no_uses26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_thread_api_no_uses.pas'` at 970eabd8eadfc9c22bb57cdf2546668c082ea498

## Range
> **The named sha `970eabd8eadf` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `970eabd8eadf`, last good `1e37a55f6748`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:23: error: {$threadsafe on} must be the --threadsafe flag: the lock-implementation defines (PXX_TS_HARDLOCK on x86-64, PXX_TS_SOFTLOCK elsewhere) are applied before lexing, so the directive alone builds an RTL that disagrees with the codegen
(tail)
pascal26:23: error: {$threadsafe on} must be the --threadsafe flag: the lock-implementation defines (PXX_TS_HARDLOCK on x86-64, PXX_TS_SOFTLOCK elsewhere) are applied before lexing, so the directive alone builds an RTL that disagrees with the codegen

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-01 — auto-closed by the seven watcher: `test-core#src:test/test_thread_api_no_uses.pas` passes at 963c289544a2 (tier native); it was red at 970eabd8eadf. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
