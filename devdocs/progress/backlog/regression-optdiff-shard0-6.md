---
prio: 70
---

# regression: optdiff#shard0/6 red at 0ceeeaa004dc (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host xeon). Untriaged.
- **Found:** 2026-07-31T22:25:49Z
- **Test source:** tools/optdiff.sh

## Repro
`tools/testmgr.py --tier opt --job 'optdiff#shard0/6'` at 0ceeeaa004dcccba010df62365dcfc0f56cb19ec

## Range
bad `0ceeeaa004dc`, last good `unknown`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
OPT DIFF -O3: test/crtl_libc_oracle.c (rc 0 vs 0)
optdiff shard 0/6: pass=179 skip=31 diff=1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

---

**Same bug as its shard-twin.** `optdiff#shard5/6` and `optdiff#shard0/6` are
both `test/crtl_libc_oracle.c` failing at `-O3`; the shard index moved because
one test file was added. See [[bug-t-optdiff-shard-identity-is-positional]].
Work the compiler defect once, in [[regression-optdiff-shard5-6]].
