---
prio: 70
---

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_class_return.npy red at cd891b44a616 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host xeon). Untriaged.
- **Found:** 2026-08-03T22:59:39Z
- **Test source:** test/test_nilpy_class_return.npy

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_class_return.npy'` at cd891b44a6168085220aeeeb481b79885a679cdd

## Range
bad `cd891b44a616`, last good `unknown`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:63: error: unexpected token
(tail)
Expected: ), but got:  (Kind: 81, Line: 63)
pascal26:63: error: unexpected token
  near:    build_later   >>>  name  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
