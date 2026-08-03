---
prio: 70
---

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/cstatic_init_cast.c red at 6995a1a0d618 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host xeon). Untriaged.
- **Found:** 2026-08-03T15:03:39Z
- **Test source:** test/cstatic_init_cast.c

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/cstatic_init_cast.c'` at 6995a1a0d61817b767126d0d9ed818770e7ae9c3

## Range
bad `6995a1a0d618`, last good `c3920992b93d`, 7 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2904592/cstatic_init_cast26  [code=161798B  data=5208B  bss=22432B  procs=487]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
