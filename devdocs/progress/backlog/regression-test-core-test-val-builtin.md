---
prio: 70
---

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_val_builtin.pas red at 7462448a21bd (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-16T03:13:30Z
- **Test source:** test/test_val_builtin.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_val_builtin.pas'` at 7462448a21bd6d106d58b6b07faf6d240f188a1b

## Range
bad `7462448a21bd`, last good `b225834a3648`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-657947/test_val_builtin26  [code=94437B  data=2760B  bss=9644B  procs=202]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
