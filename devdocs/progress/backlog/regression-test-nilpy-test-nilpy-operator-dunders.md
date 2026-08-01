---
prio: 70
---

# regression: test-nilpy#src:test/test_nilpy_operator_dunders.npy red at 6840247771d5 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host xeon). Untriaged.
- **Found:** 2026-08-01T15:22:19Z
- **Test source:** test/test_nilpy_operator_dunders.npy test/test_nilpy_operator_dunder_missing_fail.npy

## Repro
`tools/testmgr.py --tier native --job 'test-nilpy#src:test/test_nilpy_operator_dunders.npy'` at 6840247771d51adced4f9bc6656ca8c959f1364b

## Range
bad `6840247771d5`, last good `eeae1e4a3057`, 9 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2734294/test_nilpy_opdunder26  [code=1190167B  data=32768B  bss=8532B  procs=1046]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
