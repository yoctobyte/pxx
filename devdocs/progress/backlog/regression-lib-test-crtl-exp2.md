---
prio: 70
---

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:test/crtl_exp2.c red at 096da361dd93 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-16T11:09:21Z
- **Test source:** test/crtl_exp2.c examples/tk/hello.npy +5

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:test/crtl_exp2.c'` at 096da361dd93823dc6aa56f7a344de5f343127ec

## Range
bad `096da361dd93`, last good `459e96f985d1`, 32 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1820057/crtl_exp2  [code=228732B  data=5400B  bss=23080B  procs=582]
  tk-nilpy: ok

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
