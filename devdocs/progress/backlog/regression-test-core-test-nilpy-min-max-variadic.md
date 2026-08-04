---
prio: 70
---

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_min_max_variadic.npy red at 9305672dbcd5 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host xeon). Untriaged.
- **Found:** 2026-08-04T03:59:18Z
- **Test source:** test/test_nilpy_min_max_variadic.npy

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_min_max_variadic.npy'` at 9305672dbcd5f66880058f28120d237032e6fedc

## Range
bad `9305672dbcd5`, last good `c51086424657`, 3 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:5: error: no overload of min matches these arguments
(tail)
pascal26:5: error: no overload of min matches these arguments
  argument types: (Integer, Integer, Integer)
  candidates:
    min(Int64, Int64, Int64, Int64, Int64)
  near:       >>>    

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
