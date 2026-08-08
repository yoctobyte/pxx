---
prio: 70
---

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-uforth#00 red at 378295f7c218 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-08T17:00:56Z
- **Test source:** unknown (see repro commands)

## Repro
`tools/testmgr.py --tier full --job 'test-uforth#00'` at 378295f7c218249cbb634433196aaf768ceaefb0

## Range
bad `378295f7c218`, last good `unknown`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
compiling uforth.py as Nil-Python ...
test-uforth: smoke PASS — compiles, STD.UFO loads, native + PYTHON-bodied words evaluate
running uforth's own corpora, DIFFERENTIAL against CPython ...
running the Forth 2012 / ANS suite per WORD SET, DIFFERENTIAL against CPython ...

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
