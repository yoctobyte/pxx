---
prio: 70
---

# regression: optdiff#shard4/6 red at 6e0395e5495f (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-13T02:18:22Z
- **Test source:** tools/optdiff.sh

## Repro
`tools/testmgr.py --tier opt --job 'optdiff#shard4/6'` at 6e0395e5495f72a8c046d8a88c77183f7989dcd2

## Range
bad `6e0395e5495f`, last good `6e0395e5495f`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
OPT DIFF -O2: test/test_sqlite_crud.pas (rc 0 vs 0)
OPT DIFF -O3: test/test_sqlite_crud.pas (rc 0 vs 0)
optdiff shard 4/6: pass=146 skip=18 diff=1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
