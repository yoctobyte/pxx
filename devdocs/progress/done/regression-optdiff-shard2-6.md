---
prio: 70
---

# regression: optdiff#shard2/6 red at d87301219197 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host xeon). Untriaged.
- **Found:** 2026-07-31T23:07:16Z
- **Test source:** tools/optdiff.sh

## Repro
`tools/testmgr.py --tier opt --job 'optdiff#shard2/6'` at d873012191977487f5a792efd6971578bfa0e588

## Range
bad `d87301219197`, last good `unknown`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
OPT DIFF -O3: test/crtl_libc_oracle.c (rc 0 vs 0)
optdiff shard 2/6: pass=180 skip=31 diff=1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

---

**Duplicate.** Same failure as `regression-optdiff-shard{0,5}-6`:
`test/crtl_libc_oracle.c` segfaulting at `-O3`. The shard index moved because
test files were added — see [[bug-t-optdiff-shard-identity-is-positional]].
Work the compiler defect once, in [[regression-optdiff-shard5-6]].

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
