---
prio: 70
status: done
---

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_augmented_assign_class_dunder.npy red at e8450c58d67e (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-06T07:39:29Z
- **Test source:** test/test_nilpy_augmented_assign_class_dunder.npy

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_augmented_assign_class_dunder.npy'` at e8450c58d67efc3df7d655782ec6f72255dbdaa6

## Range
bad `e8450c58d67e`, last good `412fda7a3102`, 7 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:28: error: Nil Python: annotate the type / too dynamic [a=6 b=28]
(tail)
pascal26:28: error: Nil Python: annotate the type / too dynamic [a=6 b=28]
  near: a  Acc    >>>  a  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
- 2026-08-06 — resolved, commit 48150cd3b.
