---
prio: 70
---

# regression: test-core#src:test/test_basic_comprehensive.bas red at 3f2828476c6c (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-18T06:32:19Z
- **Test source:** test/test_basic_comprehensive.bas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_basic_comprehensive.bas'` at 3f2828476c6cbac56775a81e1aa2791208d1d239

## Range
bad `3f2828476c6c`, last good `4e380fda9a3d`, 6 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:8: error: IR_UNSUPPORTED: frontend could not lower AST node (kind 78) — a frontend gap, would miscompile ()
  near: pascal_mul  a  b  >>> end  end 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

- 2026-07-19 (backlog sweep) **RESOLVED.** Fixed 09474309 (AST region-swap missed per-frontend ASTNodeCount reset); watcher recorded FIXED at 81525fb0, full GREEN followed.
- 2026-07-19 — resolved, commit 09474309.
