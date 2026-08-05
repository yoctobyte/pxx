---
prio: 70
---

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_syncobjs.pas red at 9df868bf3680 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-05T08:11:39Z
- **Test source:** test/test_syncobjs.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_syncobjs.pas'` at 9df868bf3680ad066c398ff4370dc4858478e90e

## Range
bad `9df868bf3680`, last good `65baa25f64df`, 7 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-832624/test_syncobjs26  [code=75935B  data=2968B  bss=9500B  procs=169]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
