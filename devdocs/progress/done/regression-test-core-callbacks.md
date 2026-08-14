---
prio: 70
status: done
---

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:examples/tk/callbacks.npy red at 410b7a40b516 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-13T22:48:49Z
- **Test source:** examples/tk/callbacks.npy test/test_nilpy_kwargs_by_name.npy

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:examples/tk/callbacks.npy'` at 410b7a40b51663a8e3c404fe214d2ce8e5a6bd79

## Range
bad `410b7a40b516`, last good `77c55970f49c`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:50: error: undefined variable (print)
(tail)
pascal26:50: error: undefined variable (print)
  near: lambda first  last  print >>>  lambda scroll ok  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
- 2026-08-14 — resolved, commit PENDING-COMMIT.
