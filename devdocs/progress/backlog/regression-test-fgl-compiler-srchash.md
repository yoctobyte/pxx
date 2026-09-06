---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/run_fgl_corpus.sh ./compiler/pascal26 library_candidates/fpc-rtl/rtl/objpas`. The job's own `src` (`tools/compiler_srchash.sh`, 3 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 12 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-fgl#src:tools/compiler_srchash.sh at 3b13f585f5f4 in step 2/2, `tools/run_fgl_corpus.sh ./compiler/pascal26 library_candidates/fpc-rtl/rtl/objpas` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T00:21:35Z
- **Test source:** tools/compiler_srchash.sh compiler/.pascal26.fixedpoint +1
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/run_fgl_corpus.sh`.
  ```
  tools/run_fgl_corpus.sh ./compiler/pascal26 library_candidates/fpc-rtl/rtl/objpas
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-fgl#src:tools/compiler_srchash.sh'` at 3b13f585f5f4755371f7a45c73a3ec9270dcbc95

## Range
> **The named sha `3b13f585f5f4` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `3b13f585f5f4`, last good `5daad03f50d7`, 5 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
FAIL ifclist.pas -- compile error:
pascal26:892: error: undefined variable (IFoo)
FAIL list_int.pas -- compile error:
pascal26:981: error: undefined variable (TFPGListEnumeratorSpec)
FAIL list_str.pas -- compile error:
FAIL objectlist.pas -- compile error:
pascal26:892: error: undefined variable (TThing)
(tail)
self-host fixedpoint: verified — 1 round(s), 36d5ec10a24c (stamp read back; sources match it)
PASS fpslist.pas
FAIL ifclist.pas -- compile error:
    pascal26:987: note: TODO : fix inlining to work! InternalItems[Result]^
    pascal26:1124: note: TODO : fix inlining to work! InternalItems[Result]^
    pascal26:1248: note: TODO : fix inlining to work! InternalItems[Result]^
    pascal26:892: error: undefined variable (IFoo)
FAIL list_int.pas -- compile error:
    pascal26:987: note: TODO : fix inlining to work! InternalItems[Result]^
    pascal26:1124: note: TODO : fix inlining to work! InternalItems[Result]^
    pascal26:1248: note: TODO : fix inlining to work! InternalItems[Result]^
    pascal26:981: error: undefined variable (TFPGListEnumeratorSpec)
FAIL list_str.pas -- compile error:
    pascal26:987: note: TODO : fix inlining to work! InternalItems[Result]^
    pascal26:1124: note: TODO : fix inlining to work! InternalItems[Result]^
    pascal26:1248: note: TODO : fix inlining to work! InternalItems[Result]^
    pascal26:981: error: undefined variable (TFPGListEnumeratorSpec)
PASS map_int.pas
PASS map_str.pas
FAIL objectlist.pas -- compile error:
    pascal26:987: note: TODO : fix inlining to work! InternalItems[Result]^
    pascal26:1124: note: TODO : fix inlining to work! InternalItems[Result]^
    pascal26:1248: note: TODO : fix inlining to work! InternalItems[Result]^
    pascal26:892: error: undefined variable (TThing)
test-fgl: 3 pass, 4 fail, 0 skip (of 7)
test-fgl: FAILURES: ifclist.pas(compile) list_int.pas(compile) list_str.pas(compile) objectlist.pas(compile)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
