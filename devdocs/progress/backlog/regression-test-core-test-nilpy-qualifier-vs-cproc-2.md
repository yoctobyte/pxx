---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 1 of 3, `./compiler/pascal26 -Futest/nilpy_units test/test_nilpy_qualifier_vs_cproc.npy /tmp/test_nilpy_qual_cproc26`, which names `test/test_nilpy_qualifier_vs_cproc.npy`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_qualifier_vs_cproc.npy at 5e9c8da7481e in step 1/3, `./compiler/pascal26 -Futest/nilpy_units test/test_nilpy_qualifier_vs_cproc.npy /tmp/test_nilpy_qual_cproc26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1f06bcf02d3f`).
  Untriaged.
- **Found:** 2026-09-19T10:43:37Z
- **Test source:** test/test_nilpy_qualifier_vs_cproc.npy tools/expect_same.sh
- **Failing step:** line 1 of 3 of the job's recipe; it names `test/test_nilpy_qualifier_vs_cproc.npy`.
  ```
  ./compiler/pascal26 -Futest/nilpy_units test/test_nilpy_qualifier_vs_cproc.npy /tmp/test_nilpy_qual_cproc26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_qualifier_vs_cproc.npy'` at 5e9c8da7481e6e9e62afed990d1847f1c7d91588

## Range
> **The named sha `5e9c8da7481e` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `5e9c8da7481e`, last good `2f7bee67cc0a`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:19: error: __thread errno: the per-thread variable area is full (0 bytes). It is a fixed cap and not a shortage of memory: the block is reserved by EmitTlsMainInstall, which runs before parsing, so its size is baked in before any thread-local has been seen. Raise it on the COMMAND LINE and recompile this program -- no compiler rebuild: -dPXX_TLS_USER_4K, _8K or _16K (also _0, _1K, _2K to shrink it). lib/rtl/palthread.pas reads the real size through __pxxTlsBlockSize, so it follows without being edited.
(tail)
pascal26:19: error: __thread errno: the per-thread variable area is full (0 bytes). It is a fixed cap and not a shortage of memory: the block is reserved by EmitTlsMainInstall, which runs before parsing, so its size is baked in before any thread-local has been seen. Raise it on the COMMAND LINE and recompile this program -- no compiler rebuild: -dPXX_TLS_USER_4K, _8K or _16K (also _0, _1K, _2K to shrink it). lib/rtl/palthread.pas reads the real size through __pxxTlsBlockSize, so it follows without being edited.
  in: /tmp/testmgr-scratch-418715/compiler/../lib/crtl/include/errno.h
  near: extern __thread int errno >>>  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-19 — the borg watcher saw `test-core#src:test/test_nilpy_qualifier_vs_cproc.npy` GREEN at 361c03dc6ded (tier native) and did NOT close this: this is a repeat stub (`regression-test-core-test-nilpy-qualifier-vs-cproc-2`, not `regression-test-core-test-nilpy-qualifier-vs-cproc`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
