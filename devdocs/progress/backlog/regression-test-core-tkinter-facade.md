---
prio: 70
---

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:examples/tk/tkinter_facade.npy red at f8b8a7eb5ed2 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-15T23:45:06Z
- **Test source:** examples/tk/tkinter_facade.npy lib/rtl/configparser.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:examples/tk/tkinter_facade.npy'` at f8b8a7eb5ed266fce811c26e44fbe82d1a56faf3

## Range
bad `f8b8a7eb5ed2`, last good `6bff7ae1b4de`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:8: error: undefined variable (Tk_)
(tail)
pascal26:8: error: undefined variable (Tk_)
  near:  StringVar  root  Tk_ >>>    

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
