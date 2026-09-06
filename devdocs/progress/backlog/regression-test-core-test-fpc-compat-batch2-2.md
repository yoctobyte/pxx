---
prio: 70
track: P
---

> **Track guessed as P from the FAILING STEP** — line 8 of 3, `fglsrc=""; \ if [ -f library_candidates/fpc-rtl/rtl/objpas/fgl.pp ]; then fglsrc=library_candidates/fpc-rtl/rtl/objpas; `, which names `test/test_fgl_use.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 4 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_fpc_compat_batch2.pas at 7b287013d34a in step 8/3, `fglsrc=""; \ if [ -f library_candidates/fpc-rtl/rtl/objpas/fgl.pp ]; then fglsrc=library_candidates/fpc-rtl/rtl/objpas;…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T00:07:20Z
- **Test source:** test/test_fpc_compat_batch2.pas tools/expect_same.sh +2
- **Failing step:** line 8 of 3 of the job's recipe; it names `test/test_fgl_use.pas tools/expect_same.sh tools/install_lib_candidates.sh`.
  ```
  fglsrc=""; \ if [ -f library_candidates/fpc-rtl/rtl/objpas/fgl.pp ]; then fglsrc=library_candidates/fpc-rtl/rtl/objpas; \ elif [ -f /usr/share/fpcsrc/3.2.2/rtl/objpas/fgl.pp ]; then fglsrc=/usr/share/fpcsrc/3.2.2/rtl/objpas; fi; \ if [ -n "$fglsrc" ]; then \ ./compiler/pascal26 --mimic-fpc -Fu$fglsr
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_fpc_compat_batch2.pas'` at 7b287013d34a81b59eb9f502ed5ca850da497b70

## Range
> **The named sha `7b287013d34a` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `7b287013d34a`, last good `5daad03f50d7`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1652538/test_fpc_compat_batch226  [code=327448B  data=33388B  bss=85316B  procs=851]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
