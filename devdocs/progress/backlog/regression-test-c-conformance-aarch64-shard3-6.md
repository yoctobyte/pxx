---
prio: 70
---

# regression: test-c-conformance-aarch64#shard3/6 red at 90ae846bda82 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-13T00:11:15Z
- **Test source:** tools/run_c_conformance.sh

## Repro
`tools/testmgr.py --tier full --job 'test-c-conformance-aarch64#shard3/6'` at 90ae846bda8224968b0d18ea8e0fb46a7af35133

## Range
bad `90ae846bda82`, last good `90ae846bda82`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
FAIL 00040.c — exit code 124 (want 0)
test-c-conformance-aarch64: 36 pass, 1 fail, 0 skip (of 37)
test-c-conformance-aarch64: FAILURES: 00040.c(exit=124)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
