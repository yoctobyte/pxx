---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 1 of 7, `./compiler/pascal26 -DPy_LIMITED_API=0x030c0000 -DCYTHON_COMPRESS_STRINGS=0 -Futest/nilpy_units -Ilib/cpyext/include tes`, which names `test/test_cpyext_cython.npy`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 14 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_cpyext_cython.npy at 523c10e42d90 in step 1/7, `./compiler/pascal26 -DPy_LIMITED_API=0x030c0000 -DCYTHON_COMPRESS_STRINGS=0 -Futest/nilpy_units -Ilib/cpyext/include te…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1f06bcf02d3f`).
  Untriaged.
- **Found:** 2026-09-19T11:13:08Z
- **Test source:** test/test_cpyext_cython.npy tools/expect_same.sh
- **Failing step:** line 1 of 7 of the job's recipe; it names `test/test_cpyext_cython.npy`.
  ```
  ./compiler/pascal26 -DPy_LIMITED_API=0x030c0000 -DCYTHON_COMPRESS_STRINGS=0 -Futest/nilpy_units -Ilib/cpyext/include test/test_cpyext_cython.npy /tmp/test_cpyext_cython26
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_cpyext_cython.npy'` at 523c10e42d90e48c4dcad3b2a514c5608caa4310

## Range
bad `523c10e42d90`, last good `2f7bee67cc0a`, 5 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:19: error: __thread errno: the per-thread variable area is full (0 bytes). It is a fixed cap and not a shortage of memory: the block is reserved by EmitTlsMainInstall, which runs before parsing, so its size is baked in before any thread-local has been seen. Raise it on the COMMAND LINE and recompile this program -- no compiler rebuild: -dPXX_TLS_USER_4K, _8K or _16K (also _0, _1K, _2K to shrink it). lib/rtl/palthread.pas reads the real size through __pxxTlsBlockSize, so it follows without being edited.
(tail)
pascal26:19: error: __thread errno: the per-thread variable area is full (0 bytes). It is a fixed cap and not a shortage of memory: the block is reserved by EmitTlsMainInstall, which runs before parsing, so its size is baked in before any thread-local has been seen. Raise it on the COMMAND LINE and recompile this program -- no compiler rebuild: -dPXX_TLS_USER_4K, _8K or _16K (also _0, _1K, _2K to shrink it). lib/rtl/palthread.pas reads the real size through __pxxTlsBlockSize, so it follows without being edited.
  in: /tmp/testmgr-scratch-480283/compiler/../lib/crtl/include/errno.h
  near: extern __thread int errno >>>  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
