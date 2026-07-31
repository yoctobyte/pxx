---
prio: 70
---

# regression: optdiff#shard5/6 red at 2add2ebb487b (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host xeon). Untriaged.
- **Found:** 2026-07-31T21:34:01Z
- **Test source:** tools/optdiff.sh

## Repro
`tools/testmgr.py --tier opt --job 'optdiff#shard5/6'` at 2add2ebb487b2791784b7538dfe21df144ce856e

## Range
bad `2add2ebb487b`, last good `unknown`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
OPT DIFF -O3: test/crtl_libc_oracle.c (rc 0 vs 0)
optdiff shard 5/6: pass=179 skip=31 diff=1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
