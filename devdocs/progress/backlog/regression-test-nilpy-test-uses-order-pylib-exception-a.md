---
prio: 70
---

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_uses_order_pylib_exception_a.pas red at be7f80936b0c (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-13T20:31:24Z
- **Test source:** test/test_uses_order_pylib_exception_a.pas

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_uses_order_pylib_exception_a.pas'` at be7f80936b0c0c95afadcb4d093ae8ba95ecea1c

## Range
bad `be7f80936b0c`, last good `7a3f93c5f7eb`, 44 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:4874: error: "argsv": no such member on this record/class
(tail)
pascal26:4874: error: "argsv": no such member on this record/class
  near: k    e  >>> argsv  TPyList 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
