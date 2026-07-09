---
prio: 70
---

# regression: test-lua#00 red at 074e902b62ef (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-09T17:05:42Z

## Repro
`tools/testmgr.py --tier full --job 'test-lua#00'` at 074e902b62ef8d793d9ee80bbe6a3cdc2f9ba351

## Range
bad `074e902b62ef`, last good `074e902b62ef`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
compiling lua runner ...
pascal26:4: warning: "/*" within comment
Expected: ), but got:  (Kind: 74, Line: 18246)
  near:     uintmax_t  >>>  str  
pascal26:18246: error: unexpected token ()

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
- 2026-07-09 — resolved, commit 801f6f5d.
