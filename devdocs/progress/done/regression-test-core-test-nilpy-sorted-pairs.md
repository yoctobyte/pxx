---
prio: 70
---

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_sorted_pairs.npy red at bb845b13ceb3 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-15T06:45:02Z
- **Test source:** test/test_nilpy_sorted_pairs.npy

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_sorted_pairs.npy'` at bb845b13ceb3c2f2d94f63dfe35f366489826f04

## Range
bad `bb845b13ceb3`, last good `31216f26dcb7`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2210398/test_nilpy_sortpairs26  [code=2246151B  data=45200B  bss=9948B  procs=1630]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-08-15 — auto-closed by the plexus watcher: `test-core#src:test/test_nilpy_sorted_pairs.npy` passes at 894b1c6c8a23 (tier native); it was red at bb845b13ceb3. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
