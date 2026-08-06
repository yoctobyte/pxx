---
prio: 70
---

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_pyexpr_semantics.npy red at 9294bce2c800 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-06T08:04:09Z
- **Test source:** test/test_nilpy_pyexpr_semantics.npy

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_pyexpr_semantics.npy'` at 9294bce2c800eaa1dc7242e6ffd01120aaa20ca7

## Range
bad `9294bce2c800`, last good `unknown`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:3: error: Nil Python: annotate the type / too dynamic [a=6 b=28]
(tail)
pascal26:3: error: Nil Python: annotate the type / too dynamic [a=6 b=28]
  near:       >>>   show 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
