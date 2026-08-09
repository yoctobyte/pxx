---
prio: 70
---

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_delitem_dunder.npy red at 954727cee668 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-09T10:56:31Z
- **Test source:** test/test_nilpy_delitem_dunder.npy test/test_nilpy_delitem_dunder.expected

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_delitem_dunder.npy'` at 954727cee6680daf514fcd5bb929814a1ca3c522

## Range
bad `954727cee668`, last good `29d980110b58`, 15 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:67: error: Nil Python: del is supported on a dict subscript, a list index, a list slice, or a class with __delitem__ (del d[k], del l[i], del l[a:b], del c[k])
(tail)
pascal26:67: error: Nil Python: del is supported on a dict subscript, a list index, a list slice, or a class with __delitem__ (del d[k], del l[i], del l[a:b], del c[k])
  near:  del o    >>>    

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
