---
prio: 70
---

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_uses_order_pylib_exception_b.pas red at 60502ed0c353 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-15T17:19:29Z
- **Test source:** test/test_uses_order_pylib_exception_b.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_uses_order_pylib_exception_b.pas'` at 60502ed0c353c52af40748d96bc4563f47007896

## Range
bad `60502ed0c353`, last good `36d1bffda39d`, 48 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:51: error: on: unknown exception class
(tail)
pascal26:51: error: on: unknown exception class
  near:  except on ex  ExceptionBase >>> do WriteLn  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
