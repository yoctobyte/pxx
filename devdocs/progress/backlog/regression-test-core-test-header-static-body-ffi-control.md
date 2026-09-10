---
prio: 70
track: P
---

> **Track guessed as P from the FAILING STEP** — line 1 of 107, `./compiler/pascal26 -Itest/chdrstatic -Futest/chdrstatic test/test_header_static_body_ffi_control.pas /tmp/hdrstatic_ffi`, which names `test/test_header_static_body_ffi_control.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 4 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_header_static_body_ffi_control.pas at 7e4f69a34350 in step 1/107, `./compiler/pascal26 -Itest/chdrstatic -Futest/chdrstatic test/test_header_static_body_ffi_control.pas /tmp/hdrstatic_ff…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `883da23adb0a`).
  Untriaged.
- **Found:** 2026-09-10T10:47:04Z
- **Test source:** test/test_header_static_body_ffi_control.pas lib/crtl/src/string.c +2
- **Failing step:** line 1 of 107 of the job's recipe; it names `test/test_header_static_body_ffi_control.pas`.
  ```
  ./compiler/pascal26 -Itest/chdrstatic -Futest/chdrstatic test/test_header_static_body_ffi_control.pas /tmp/hdrstatic_ffi26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_header_static_body_ffi_control.pas'` at 7e4f69a343501a4b71ef7cfb5033e90fe5e4bcd5

## Range
bad `7e4f69a34350`, last good `e1ba463ce0c1`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:7: error: this build would die at exec: `hs_ffi_declared_only` is imported from libhdrstatic_ffi.so, which no library on this machine answers to. That soname was not declared anywhere — the compiler derived it from the name of the header you imported (hdrstatic_ffi.h), and a header file name is not a library name. Name the library explicitly instead, with an `external '<soname>'` clause carrying the soname the loader wants.
(tail)
pascal26:7: error: this build would die at exec: `hs_ffi_declared_only` is imported from libhdrstatic_ffi.so, which no library on this machine answers to. That soname was not declared anywhere — the compiler derived it from the name of the header you imported (hdrstatic_ffi.h), and a header file name is not a library name. Name the library explicitly instead, with an `external '<soname>'` clause carrying the soname the loader wants.
  near: hs_ffi_declared_only ( 1 ) ) ; >>> end . 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
