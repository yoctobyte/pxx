---
prio: 70
track: N
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 42 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_relative_import_in_package.npy red at edfcdcaf3a5c (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-29T22:11:03Z
- **Test source:** test/test_nilpy_relative_import_in_package.npy test/test_nilpy_relative_import_in_package.expected +1

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_relative_import_in_package.npy'` at edfcdcaf3a5c2333f6441947ee632d7b328480d2

## Range
> **The named sha `edfcdcaf3a5c` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `edfcdcaf3a5c`, last good `49bd043061c1`, 206 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:10: error: undefined variable (RENAMED)
(tail)
pascal26:10: error: undefined variable (RENAMED)
  near: A   U  RENAMED >>>    

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-08-29 — auto-closed by the seven watcher: `test-nilpy#src:test/test_nilpy_relative_import_in_package.npy` passes at 084ee09ef0ae (tier full); it was red at ee62e6dc0582. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
