---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 1 of 13, `./compiler/pascal26 test/test_nilpy_unbound_builtin_method.npy /tmp/test_nilpy_unbndbuiltin26`, which names `test/test_nilpy_unbound_builtin_method.npy`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_unbound_builtin_method.npy at b4104386ae9c in step 1/13, `./compiler/pascal26 test/test_nilpy_unbound_builtin_method.npy /tmp/test_nilpy_unbndbuiltin26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1f06bcf02d3f`).
  Untriaged.
- **Found:** 2026-09-19T14:58:42Z
- **Test source:** test/test_nilpy_unbound_builtin_method.npy tools/expect_same.sh
- **Failing step:** line 1 of 13 of the job's recipe; it names `test/test_nilpy_unbound_builtin_method.npy`.
  ```
  ./compiler/pascal26 test/test_nilpy_unbound_builtin_method.npy /tmp/test_nilpy_unbndbuiltin26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_unbound_builtin_method.npy'` at b4104386ae9c393702223f151f8e29b902868140

## Range
> **The named sha `b4104386ae9c` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `b4104386ae9c`, last good `374150f061fc`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:19: error: Nil Python: append overrides TPyList.append with a different result type, in a class laid out after its base was compiled (it has several bases, or derives from one that does) -- annotate both results with the same type
(tail)
pascal26:19: error: Nil Python: append overrides TPyList.append with a different result type, in a class laid out after its base was compiled (it has several bases, or derives from one that does) -- annotate both results with the same type
  near: ( list ) :   >>> def append ( 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-19 — the borg watcher saw `test-core#src:test/test_nilpy_unbound_builtin_method.npy` GREEN at fbed9f690d29 (tier native) and did NOT close this: this is a repeat stub (`regression-test-core-test-nilpy-unbound-builtin-method-2`, not `regression-test-core-test-nilpy-unbound-builtin-method`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
