---
prio: 70
---

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/cstr_table_2d_rows.c red at 7eef29e052d2 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-16T02:52:54Z
- **Test source:** test/cstr_table_2d_rows.c

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/cstr_table_2d_rows.c'` at 7eef29e052d2e2610fd0033cd9ac02e5607b2494

## Range
bad `7eef29e052d2`, last good `d10ded429269`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-602507/cstr_table_2d_rows26  [code=211390B  data=6088B  bss=25888B  procs=589]
FAIL row-stride: got 1 want 8

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
