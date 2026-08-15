---
prio: 70
---

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_float_pow_oracle.npy red at c9706630b486 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-15T23:49:55Z
- **Test source:** test/test_nilpy_float_pow_oracle.npy test/test_nilpy_float_pow_oracle.expected

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_float_pow_oracle.npy'` at c9706630b486c3fe27dfe131b692ecf7e8496c5a

## Range
bad `c9706630b486`, last good `f8b8a7eb5ed2`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26: error: cannot read input file: test/test_nilpy_float_pow_oracle.npy
(tail)
pascal26: error: cannot read input file: test/test_nilpy_float_pow_oracle.npy

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
