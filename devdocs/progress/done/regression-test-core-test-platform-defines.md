---
prio: 70
---

# regression: test-core#src:test/test_platform_defines.pas@2 red at 96147f570d29 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-14T13:53:04Z
- **Test source:** test/test_platform_defines.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_platform_defines.pas@2'` at 96147f570d29941719baef78f44cfcec515eed7e

## Range
bad `96147f570d29`, last good `857903930528`, 7 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1217226/test_platform_defines_esp26  [code=32877B  data=1256B  bss=9432B  procs=76]
/tmp/testmgr-scratch-1217226/test_platform_defines_esp26: symbol lookup error: /tmp/testmgr-scratch-1217226/test_platform_defines_esp26: undefined symbol: calloc

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
- 2026-07-14 — resolved, commit d1ccab4c.
