---
prio: 70
---

# regression: optdiff#shard0/6 red at 110835ca0693 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-18T22:40:53Z
- **Test source:** tools/optdiff.sh

## Repro
`tools/testmgr.py --tier opt --job 'optdiff#shard0/6'` at 110835ca0693ed682f0b9a1db35d8cea2196534e

## Range
bad `110835ca0693`, last good `110835ca0693`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Terminated
OPT DIFF -O3: test/test_stack_frame_intrinsics_b270.pas (rc 0 vs 0)
optdiff shard 0/6: pass=175 skip=21 diff=1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
