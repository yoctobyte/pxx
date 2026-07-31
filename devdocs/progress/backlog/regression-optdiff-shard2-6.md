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
