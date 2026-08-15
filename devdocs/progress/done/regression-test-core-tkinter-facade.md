---
prio: 70
status: done
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

## TRIAGED AND FIXED 2026-08-16 — both were mine, both from the same commit pair

`undefined variable (Tk_)` was the qualified-only import rule
(`e94b8cda3`) applied too widely. `examples/tk/hello.npy`,
`widgets.npy` and `tkinter_facade.npy` all write `import tk` (or
`import tkinter as tk`) and then call a bare `TkInit()` / `Tk_()` — code CPython
would reject with a NameError, and NilPy accepting what CPython rejects is a
documented FEATURE of this dialect, not a defect. Hiding every routine of an
imported unit made that laxness a hard error.

The rule is now narrowed to the AMBUSH alone: a qualified-only unit's routine is
dropped only when the Python side (pylib/pyeval, or a compiler-minted proc)
declares the same name. `abs`/`min`/`max`/`round` are exactly that set;
`TkInit`, `Tk_` and `Trim` collide with nothing and still resolve. All ten
`examples/tk/*.npy` compile again, and the abs/min/max oracles stay green.
Pinned by a new section of `test/test_nilpy_import_does_not_publish_names.npy`.
- 2026-08-16 — resolved, commit a8a1cb9c1.
