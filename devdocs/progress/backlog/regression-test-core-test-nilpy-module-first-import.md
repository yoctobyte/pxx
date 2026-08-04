---
prio: 70
---

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_module_first_import.npy red at b9e334fbd649 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host xeon). Untriaged.
- **Found:** 2026-08-04T04:26:26Z
- **Test source:** test/test_nilpy_module_first_import.npy

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_module_first_import.npy'` at b9e334fbd64912075887e9e10d7629daa17ff93e

## Range
bad `b9e334fbd649`, last good `48d007d6febb`, 2 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-209474/test_nilpy_module_first_import26  [code=1353849B  data=35544B  bss=8676B  procs=1228]
Segmentation fault (core dumped)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
