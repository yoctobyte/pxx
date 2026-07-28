---
prio: 70
---

# regression: test-core#src:examples/tk/facade_and_paths.npy red at d64a5d6a97b4 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-28T14:30:38Z
- **Test source:** examples/tk/facade_and_paths.npy

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:examples/tk/facade_and_paths.npy'` at d64a5d6a97b4484e3d5aefa0b475ab3817d11121

## Range
bad `d64a5d6a97b4`, last good `ebc63e8eafdc`, 6 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-683882/test_nilpy_facade_paths26  [code=1015424B  data=46544B  bss=24876B  procs=1157]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
