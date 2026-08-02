---
prio: 70
---

> **origin/master has advanced 7 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: optdiff#shard8/12 red at 28eb1a105ddb (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host xeon). Untriaged.
- **Found:** 2026-08-02T14:10:52Z
- **Test source:** tools/optdiff.sh

## Repro
`tools/testmgr.py --tier opt --job 'optdiff#shard8/12'` at 28eb1a105ddb027c2ee7b8e2240677c9433243d4

## Range
bad `28eb1a105ddb`, last good `unknown`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
OPT DIFF -O3: test/ctime_localtime.c (rc 0 vs 0)
Segmentation fault (core dumped)
optdiff shard 8/12: pass=100 skip=16 diff=1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
