---
prio: 70
track: B
---

> **Track guessed as B from the FAILING STEP** — line 2 of 22, `./compiler/pascal26 --target=xtensa --platform=posix --xtensa-soft-mulhigh test/lib_signals_fpc.pas /tmp/sig_xt`, which names `test/lib_signals_fpc.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 4 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-threads#src:test/lib_signals_fpc.pas at b1f2b7d8812d in step 2/22, `./compiler/pascal26 --target=xtensa --platform=posix --xtensa-soft-mulhigh test/lib_signals_fpc.pas /tmp/sig_xt` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `f35167cd4e55`).
  Untriaged.
- **Found:** 2026-09-28T06:12:23Z
- **Test source:** test/lib_signals_fpc.pas tools/expect_same.sh +2
- **Failing step:** line 2 of 22 of the job's recipe; it names `test/lib_signals_fpc.pas`.
  ```
  ./compiler/pascal26 --target=xtensa --platform=posix --xtensa-soft-mulhigh test/lib_signals_fpc.pas /tmp/sig_xt
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-threads#src:test/lib_signals_fpc.pas'` at b1f2b7d8812dce14468da84ec8e1e0e867f3c412

## Range
> **The named sha `b1f2b7d8812d` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `b1f2b7d8812d`, last good `9a245b91c409`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:46: error: incompatible types: @OneHandler uses the Pascal convention but the procedural type uses cdecl -- declare both the same way
pascal26:50: error: incompatible types: @OneHandler uses the Pascal convention but the procedural type uses cdecl -- declare both the same way
pascal26:65: error: incompatible types: @Other uses the Pascal convention but the procedural type uses cdecl -- declare both the same way
pascal26:70: error: incompatible types: @Other uses the Pascal convention but the procedural type uses cdecl -- declare both the same way
pascal26:71: error: incompatible types: @Other uses the Pascal convention but the procedural type uses cdecl -- declare both the same way
(tail)
ok: /tmp/testmgr-scratch-426107/sig_oracle  [code=25005B  data=7760B  bss=63300B  procs=719  codeseg=28384B]
pascal26:46: error: incompatible types: @OneHandler uses the Pascal convention but the procedural type uses cdecl -- declare both the same way
pascal26:50: error: incompatible types: @OneHandler uses the Pascal convention but the procedural type uses cdecl -- declare both the same way
pascal26:65: error: incompatible types: @Other uses the Pascal convention but the procedural type uses cdecl -- declare both the same way
pascal26:70: error: incompatible types: @Other uses the Pascal convention but the procedural type uses cdecl -- declare both the same way
pascal26:70: error: incompatible types: @Other uses the Pascal convention but the procedural type uses cdecl -- declare both the same way
pascal26:71: error: incompatible types: @Other uses the Pascal convention but the procedural type uses cdecl -- declare both the same way
pascal26:71: error: incompatible types: @Other uses the Pascal convention but the procedural type uses cdecl -- declare both the same way

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
