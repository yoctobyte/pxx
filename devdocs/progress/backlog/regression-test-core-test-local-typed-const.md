---
prio: 70
---

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_local_typed_const.pas red at 88b863e7c731 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-16T07:47:35Z
- **Test source:** test/test_local_typed_const.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_local_typed_const.pas'` at 88b863e7c7311d5f1da708ba3ce7bcfe172e09b3

## Range
bad `88b863e7c731`, last good `6891a4d56494`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:41: error: invalid IR symbol reference in load_sym
(tail)
pascal26:41: error: invalid IR symbol reference in load_sym
  near:  WriteLn  SumTable   >>> end  unit 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
