---
prio: 70
---

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_star_methods_and_targets.npy red at 89dae725b972 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-15T10:08:51Z
- **Test source:** test/test_nilpy_star_methods_and_targets.npy

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_star_methods_and_targets.npy'` at 89dae725b972d7019a20e6df61cbc18c6c9862c6

## Range
bad `89dae725b972`, last good `4c9da77f9368`, 12 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:76: error: invalid symbol in lea
(tail)
pascal26:76: error: invalid symbol in lea
  near:   main    >>>  unit builtinheap 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
