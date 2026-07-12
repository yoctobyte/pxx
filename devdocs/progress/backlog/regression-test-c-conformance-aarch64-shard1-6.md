---
prio: 70
---

# regression: test-c-conformance-aarch64#shard1/6 red at 96b6bac331d9 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-12T17:39:05Z
- **Test source:** tools/run_c_conformance.sh

## Repro
`tools/testmgr.py --tier full --job 'test-c-conformance-aarch64#shard1/6'` at 96b6bac331d9d8b9c838d0055a8e3841157314f1

## Range
bad `96b6bac331d9`, last good `96b6bac331d9`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
FAIL 00200.c — exit code 1 (want 0)
test-c-conformance-aarch64: 36 pass, 1 fail, 0 skip (of 37)
test-c-conformance-aarch64: FAILURES: 00200.c(exit=1)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
