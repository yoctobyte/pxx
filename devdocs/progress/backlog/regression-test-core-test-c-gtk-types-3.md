---
prio: 70
track: P
---

> **Track guessed as P from the FAILING STEP** — line 1 of 2, `./compiler/pascal26 test/test_c_gtk_types.pas /tmp/test_c_gtk_types26`, which names `test/test_c_gtk_types.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 1 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_c_gtk_types.pas at 7867c5481c01 in step 1/2, `./compiler/pascal26 test/test_c_gtk_types.pas /tmp/test_c_gtk_types26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-05T17:58:16Z
- **Test source:** test/test_c_gtk_types.pas
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/test_c_gtk_types.pas`.
  ```
  ./compiler/pascal26 test/test_c_gtk_types.pas /tmp/test_c_gtk_types26
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_c_gtk_types.pas'` at 7867c5481c0126cd79daa92c74114b8dd3fc6ef3

## Range
> **The named sha `7867c5481c01` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `7867c5481c01`, last good `b8e3b3010249`, 87 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:2: error: uses: unit source not found: gtk
(tail)
pascal26:2: error: uses: unit source not found: gtk
  near: program test_c_gtk_types ; uses gtk >>> ; var window 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
