---
prio: 70
---

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/cmath_trig_family_b385.c red at 93d6232f05d1 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-09T12:49:19Z
- **Test source:** test/cmath_trig_family_b385.c

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/cmath_trig_family_b385.c'` at 93d6232f05d164054d5570e717155b29c8bfdd94

## Range
bad `93d6232f05d1`, last good `0df2b14318f5`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:4254: warning: C declaration of 'nan' does not match the Pascal routine 'NaN' which takes 0 parameter(s), not 1 — binding to the C declaration, not the Pascal routine
ok: /tmp/testmgr-scratch-1505560/cmath_trig_family_b38526  [code=304909B  data=6320B  bss=26320B  procs=733]
FAIL 20 got=0.78539816339744828 want=0.46364760900080609

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
