---
prio: 70
---

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_forward_module_global.npy red at dbf783346025 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-15T04:12:43Z
- **Test source:** test/test_nilpy_forward_module_global.npy

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_forward_module_global.npy'` at dbf783346025ce00ed6885ae6a6b8d3afb4692b9

## Range
bad `dbf783346025`, last good `17c01ba0a0a0`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1806961/test_nilpy_fwdglob26  [code=2152178B  data=44616B  bss=8548B  procs=1603]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
