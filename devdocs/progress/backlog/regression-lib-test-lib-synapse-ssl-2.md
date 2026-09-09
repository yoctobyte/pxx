---
prio: 70
track: B
---

> **Track guessed as B from the FAILING STEP** — line 1 of 21, `stable_linux_amd64/default/pinned --mimic-fpc -dPXX_DYNLIB_LIBC -Fuexternal/synapse -Fulib/rtl -Fulib/rtl/platform/posix`, which names `test/lib_synapse_ssl.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **This commit CANNOT be the cause.** The job builds only with `$(PXX_STABLE)`, and this commit moved no `stable_linux_amd64/**` — so the bytes that compiled it are unchanged. Look at flakiness or box load, not at the named sha; the bisect is unsound here and has been skipped.

> **origin/master has advanced 7 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:test/lib_synapse_ssl.pas at fca28056d8ec in step 1/21, `stable_linux_amd64/default/pinned --mimic-fpc -dPXX_DYNLIB_LIBC -Fuexternal/synapse -Fulib/rtl -Fulib/rtl/platform/posi…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `0c5ad13167ab`).
  Untriaged.
- **Found:** 2026-09-09T16:32:30Z
- **Test source:** test/lib_synapse_ssl.pas tools/expect_same.sh
- **Failing step:** line 1 of 21 of the job's recipe; it names `test/lib_synapse_ssl.pas`.
  ```
  stable_linux_amd64/default/pinned --mimic-fpc -dPXX_DYNLIB_LIBC -Fuexternal/synapse -Fulib/rtl -Fulib/rtl/platform/posix test/lib_synapse_ssl.pas /tmp/lib_synapse_ssl
  ```

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:test/lib_synapse_ssl.pas'` at fca28056d8ec2483d3a9a1b0f064842164f92b46

## Range
> **The named sha `fca28056d8ec` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `fca28056d8ec`, last good `0e3ba86d5208`, **4 observable commit(s)** in range (it builds with `$(PXX_STABLE)`, so `compiler/` commits cannot have caused it and are dropped; pin moves, `lib/` and `test/` are kept) — the watcher narrows this by idle bisect.

## Log tail
```
pascal26:2039: error: undefined variable (SetString)
pascal26:2077: error: undefined variable (SetString)
pascal26:2178: error: undefined variable (SetString)
(tail)
pascal26:2039: error: undefined variable (SetString)
  in: external/synapse/synautil.pas
  near: ( var APtr : PANSIChar ; >>> AEtx : PANSIChar 
pascal26:2077: error: undefined variable (SetString)
  in: external/synapse/synautil.pas
  near: do begin SearchForLineBreak ( APtr , >>> AEtx , bol 
pascal26:2178: error: undefined variable (SetString)
  in: external/synapse/synautil.pas
  near: <= AEtx ) and ( SynaFpc >>> . strlcomp ( 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
