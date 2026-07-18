---
prio: 70
---

# regression: test-riscv32#src:test/test_cross_ptr_arith.pas red at f6cad82e8063 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-18T19:56:22Z
- **Test source:** test/test_cross_ptr_arith.pas tools/run_target.sh

## Repro
`tools/testmgr.py --tier full --job 'test-riscv32#src:test/test_cross_ptr_arith.pas'` at f6cad82e8063b9c1d3821ddd14896108ad701ada

## Range
bad `f6cad82e8063`, last good `f6cad82e8063`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
