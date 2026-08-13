---
prio: 70
---

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_conformance_1.pas red at f9e4e1c44eda (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-13T06:14:50Z
- **Test source:** test/test_conformance_1.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_conformance_1.pas'` at f9e4e1c44edacc0dc08cc20f45c44944e0168105

## Range
bad `f9e4e1c44eda`, last good `8e5ed5e8b075`, 6 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1395221/test_conformance_1_26  [code=97275B  data=4428B  bss=9688B  procs=199]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
