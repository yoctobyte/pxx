---
prio: 70
---

# regression: test-nilpy#src:test/test_nilpy_import_sqlite.npy red at 6840247771d5 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host xeon). Untriaged.
- **Found:** 2026-08-01T15:22:19Z
- **Test source:** test/test_nilpy_import_sqlite.npy

## Repro
`tools/testmgr.py --tier native --job 'test-nilpy#src:test/test_nilpy_import_sqlite.npy'` at 6840247771d51adced4f9bc6656ca8c959f1364b

## Range
bad `6840247771d5`, last good `eeae1e4a3057`, 9 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2734294/test_nilpy_import_sqlite26  [code=1180031B  data=32300B  bss=8296B  procs=1531]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

---

## CLOSED — the jobs are green (Track T, 2026-08-01)

Verified against live tstate at full-tier sha `832a0ad03776` (GREEN, 345.5s):
**every job this ticket names is passing, and xeon reports 0 failing jobs across
the whole 1637-job matrix.**

Closed as an auto-filed stub whose underlying failure is gone, not as work done
here. Left in `done/` rather than deleted so the signal history stays readable.

For the optdiff ones specifically: the compiler defect behind them was
[[bug-c-wide-string-literal-narrow-in-value-context]], and the reason there are
several tickets for one bug is
[[bug-t-optdiff-shard-identity-is-positional]] — the failure migrated shard
identity (5 -> 0 -> 2) as test files landed, re-filing itself each time. That
ticket is still open and is the thing worth fixing; these stubs are its symptom.
- 2026-08-01 — resolved, commit 832a0ad03.
