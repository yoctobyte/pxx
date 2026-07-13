---
prio: 70
---

# regression: test-core#src:test/test_fpc_compat_batch2.pas red at f6bcbe6c1237 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-13T22:00:26Z
- **Test source:** test/test_fpc_compat_batch2.pas test/test_fgl_use.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_fpc_compat_batch2.pas'` at f6bcbe6c123765dbedd03a869faf0cd8181b7a1f

## Range
bad `f6bcbe6c1237`, last good `0348fae0ff33`, 3 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2770209/test_fpc_compat_batch226  [code=138472B  data=5556B  bss=9760B  procs=369]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
