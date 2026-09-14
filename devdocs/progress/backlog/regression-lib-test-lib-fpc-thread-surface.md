---
prio: 70
track: B
---

> **Track guessed as B from the FAILING STEP** — line 1 of 6, `stable_linux_amd64/default/pinned --threadsafe -Fulib/rtl test/lib_fpc_thread_surface.pas /tmp/lib_fpc_thread_surface`, which names `test/lib_fpc_thread_surface.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:test/lib_fpc_thread_surface.pas at 934ba04180e9 in step 1/6, `stable_linux_amd64/default/pinned --threadsafe -Fulib/rtl test/lib_fpc_thread_surface.pas /tmp/lib_fpc_thread_surface` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-14T17:57:27Z
- **Test source:** test/lib_fpc_thread_surface.pas tools/expect_same.sh
- **Failing step:** line 1 of 6 of the job's recipe; it names `test/lib_fpc_thread_surface.pas`.
  ```
  stable_linux_amd64/default/pinned --threadsafe -Fulib/rtl test/lib_fpc_thread_surface.pas /tmp/lib_fpc_thread_surface
  ```

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:test/lib_fpc_thread_surface.pas'` at 934ba04180e95d273bc57583fc2d8311cd0a96e8

## Range
bad `934ba04180e9`, last good `b984ad07e38f`, **1 observable commit(s)** in range (it builds with `$(PXX_STABLE)`, so `compiler/` commits cannot have caused it and are dropped; pin moves, `lib/` and `test/` are kept) — the watcher narrows this by idle bisect.

## Log tail
```
pascal26:218: error: expected 'begin' before 'weakexternal'
(tail)
pascal26:218: error: expected 'begin' before 'weakexternal'
  in: lib/rtl/palthread.pas
  near: ) : Integer ; cdecl ; >>> weakexternal 'libc.so.6' name 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
