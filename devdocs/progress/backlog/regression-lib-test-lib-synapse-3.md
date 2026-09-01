---
prio: 70
track: B
---

> **Track guessed as B from the FAILING STEP** — line 1 of 2, `stable_linux_amd64/default/pinned --mimic-fpc -Fuexternal/synapse -Fulib/rtl -Fulib/rtl/platform/posix test/lib_synapse.`, which names `test/lib_synapse.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **This commit CANNOT be the cause.** The job builds only with `$(PXX_STABLE)`, and this commit moved no `stable_linux_amd64/**` — so the bytes that compiled it are unchanged. Look at flakiness or box load, not at the named sha; the bisect is unsound here and has been skipped.

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:test/lib_synapse.pas at 889bfcf73256 in step 1/2, `stable_linux_amd64/default/pinned --mimic-fpc -Fuexternal/synapse -Fulib/rtl -Fulib/rtl/platform/posix test/lib_synapse…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5ea286a98481`).
  Untriaged.
- **Found:** 2026-09-01T21:55:48Z
- **Test source:** test/lib_synapse.pas tools/expect_same.sh
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/lib_synapse.pas`.
  ```
  stable_linux_amd64/default/pinned --mimic-fpc -Fuexternal/synapse -Fulib/rtl -Fulib/rtl/platform/posix test/lib_synapse.pas /tmp/lib_synapse
  ```

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:test/lib_synapse.pas'` at 889bfcf7325633e2c400c82877a9ceef69a48800

## Range
> **The named sha `889bfcf73256` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `889bfcf73256`, last good `12c916c5c9ca`, **22 observable commit(s)** in range (it builds with `$(PXX_STABLE)`, so `compiler/` commits cannot have caused it and are dropped; pin moves, `lib/` and `test/` are kept) — the watcher narrows this by idle bisect.

## Log tail
```
pascal26:0: error: incompatible types: cannot assign ShortString to Char
(tail)
pascal26:0: error: incompatible types: cannot assign ShortString to Char
pascal26:0: error: incompatible types: cannot assign ShortString to Char

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
