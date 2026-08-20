---
prio: 70
---

> **origin/master has advanced 7 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_pascal_unit_keeps_fpc_method_shadowing.npy red at 57b9b7148d32 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-20T03:50:36Z
- **Test source:** test/test_nilpy_pascal_unit_keeps_fpc_method_shadowing.npy lib/rtl/classes.pas +2

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_pascal_unit_keeps_fpc_method_shadowing.npy'` at 57b9b7148d3290ac089cd9360c6e4553a4b44bfb

## Range
bad `57b9b7148d32`, last good `003d733936aa`, 7 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-4002277/test_nilpy_fpc_shadow26  [code=2568790B  data=74180B  bss=52788B  procs=2020]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
