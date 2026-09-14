---
prio: 70
track: C
---

> **Track guessed as C from the FAILING STEP** — line 15 of 17, `sh test/crtl_declaration_census.sh stable_linux_amd64/default/pinned /tmp`, which names `test/crtl_declaration_census.sh`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 3 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **The SLUG names `crtl_atexit`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `crtl_declaration_census`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:test/crtl_atexit.c at 934ba04180e9 in step 15/17, `sh test/crtl_declaration_census.sh stable_linux_amd64/default/pinned /tmp` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-14T17:57:27Z
- **Test source:** test/crtl_atexit.c tools/expect_same.sh +1
- **Failing step:** line 15 of 17 of the job's recipe; it names `test/crtl_declaration_census.sh`.
  ```
  sh test/crtl_declaration_census.sh stable_linux_amd64/default/pinned /tmp
  ```

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:test/crtl_atexit.c'` at 934ba04180e95d273bc57583fc2d8311cd0a96e8

## Range
bad `934ba04180e9`, last good `b984ad07e38f`, **1 observable commit(s)** in range (it builds with `$(PXX_STABLE)`, so `compiler/` commits cannot have caused it and are dropped; pin moves, `lib/` and `test/` are kept) — the watcher narrows this by idle bisect.

## Log tail
```
pascal26:218: error: expected 'begin' before 'weakexternal'
(tail)
ok: /tmp/testmgr-scratch-3543567/crtl_atexit  [code=327448B  data=13304B  bss=76520B  procs=873]
main-returns
h3
h2
h1
via-exit
child-exit
via-_Exit
  lib-test: crtl_atexit is self-contained (no DT_NEEDED)
FAIL: census TU did not compile
pascal26:218: error: expected 'begin' before 'weakexternal'
  in: stable_linux_amd64/default/../../lib/rtl/palthread.pas
  near: ) : Integer ; cdecl ; >>> weakexternal 'libc.so.6' name 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
