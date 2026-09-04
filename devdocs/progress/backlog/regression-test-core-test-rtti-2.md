---
prio: 70
track: P
---

> **Track guessed as P from the FAILING STEP** — line 1 of 5, `./compiler/pascal26 test/test_rtti.pas /tmp/test_rtti26`, which names `test/test_rtti.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 1 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_rtti.pas at 31f8b11bfddf in step 1/5, `./compiler/pascal26 test/test_rtti.pas /tmp/test_rtti26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-04T17:55:14Z
- **Test source:** test/test_rtti.pas
- **Failing step:** line 1 of 5 of the job's recipe; it names `test/test_rtti.pas`.
  ```
  ./compiler/pascal26 test/test_rtti.pas /tmp/test_rtti26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_rtti.pas'` at 31f8b11bfddf7e179bc7961abcd4ee64eb3441bf

## Range
bad `31f8b11bfddf`, last good `b040c90e6c8b`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:144: error: no overload of SetMethodProp matches these arguments
(tail)
pascal26:144: error: no overload of SetMethodProp matches these arguments
  argument types: (Pointer, Pointer, record)
  candidates:
    SetMethodProp(Pointer, Pointer, record)
  near: ) , p , meth ) >>> ; meth := 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-04 — the seven watcher saw `test-core#src:test/test_rtti.pas` GREEN at 035ded7723d1 (tier native) and did NOT close this: this is a repeat stub (`regression-test-core-test-rtti-2`, not `regression-test-core-test-rtti`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
