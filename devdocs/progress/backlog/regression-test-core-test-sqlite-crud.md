---
prio: 70
---

# regression: test-core#src:test/test_sqlite_crud.pas red at ff90643ef2a3 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-13T16:45:17Z
- **Test source:** test/test_sqlite_crud.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_sqlite_crud.pas'` at ff90643ef2a36c4170df6999b1f3eb67a008c0b2

## Range
bad `ff90643ef2a3`, last good `37d789442c0f`, 7 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1714308/sqlite_crud26  [code=49372B  data=1632B  bss=9760B  procs=581]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
