---
prio: 70
---

# regression: test-core#src:test/cprintf_ll_b252.c@1 red at f5c8fbec6016 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-18T18:44:28Z
- **Test source:** test/cprintf_ll_b252.c

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/cprintf_ll_b252.c@1'` at f5c8fbec60164b1b6c0c220a12d66f744050bd04

## Range
bad `f5c8fbec6016`, last good `2dffbb7c65a2`, 4 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
