---
prio: 70
---

# regression: test-core#131 red at 83006e927e35 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-12T04:25:54Z
- **Test source:** test/cmath_sqrt_correctly_rounded_b240.c

## Repro
`tools/testmgr.py --tier native --job 'test-core#131'` at 83006e927e35b02e76728c3a292e08dbcc0b792e

## Range
bad `83006e927e35`, last good `7bf9e80393ed`, 7 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:145: error: call to undeclared function: copysign ()

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
