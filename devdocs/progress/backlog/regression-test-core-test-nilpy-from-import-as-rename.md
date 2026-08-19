---
prio: 70
track: N
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_from_import_as_rename.npy red at 9bbbbef6c055 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-19T12:04:36Z
- **Test source:** test/test_nilpy_from_import_as_rename.npy test/test_nilpy_renamed_class_is_not_a_module.npy

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_from_import_as_rename.npy'` at 9bbbbef6c055ea4c823867de7960f4ac05d93348

## Range
bad `9bbbbef6c055`, last good `fbf06b40826c`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:44: error: callable value of a def with no signature record
(tail)
pascal26:44: error: callable value of a def with no signature record
  near: onearg  R    >>>  unit builtinheap 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
