---
prio: 70
---

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-c-conformance#shard1/6 red at 1b9b43e5b511 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-20T16:41:34Z
- **Test source:** tools/run_c_conformance.sh

## Repro
`tools/testmgr.py --tier full --job 'test-c-conformance#shard1/6'` at 1b9b43e5b511d53e9fbe55f3366e6ce9158ee0b9

## Range
bad `1b9b43e5b511`, last good `57b9b7148d32`, 132 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
FAIL 00206.c — exit code 254 (want 0)
FAIL 00212.c — exit code 252 (want 0)
test-c-conformance: 35 pass, 2 fail, 0 skip (of 37)
test-c-conformance: FAILURES: 00206.c(exit=254) 00212.c(exit=252)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
