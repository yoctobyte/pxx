---
prio: 70
---

# regression: optdiff#shard5/6 red at a3f6e70a728f (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-18T20:48:46Z
- **Test source:** tools/optdiff.sh

## Repro
`tools/testmgr.py --tier opt --job 'optdiff#shard5/6'` at a3f6e70a728fdb8a50d5ae1dbbbf637d38bbd44a

## Range
bad `a3f6e70a728f`, last good `a3f6e70a728f`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Terminated
OPT DIFF -O3: test/test_stack_frame_intrinsics_b270.pas (rc 0 vs 0)
optdiff shard 5/6: pass=169 skip=27 diff=1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
