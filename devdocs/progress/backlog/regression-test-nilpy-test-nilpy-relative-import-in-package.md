---
prio: 70
track: N
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 37 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_relative_import_in_package.npy red at ee62e6dc0582 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-29T18:57:16Z
- **Test source:** test/test_nilpy_relative_import_in_package.npy test/test_nilpy_relative_import_in_package.expected +1

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_relative_import_in_package.npy'` at ee62e6dc0582f6a018102c4e1d1d9a083d7e4f32

## Range
bad `ee62e6dc0582`, last good `154d1aa3fba6`, 76 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:10: error: undefined variable (RENAMED)
(tail)
pascal26:10: error: undefined variable (RENAMED)
  near: A   U  RENAMED >>>    

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
