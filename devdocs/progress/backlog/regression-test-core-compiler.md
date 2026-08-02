---
prio: 70
---

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:compiler/compiler.pas@2 red at 96cffaf08de5 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host xeon). Untriaged.
- **Found:** 2026-08-02T12:17:38Z
- **Test source:** compiler/compiler.pas tools/progress.sh

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:compiler/compiler.pas@2'` at 96cffaf08de5ac209b2721b29ade3a1fe1130d81

## Range
bad `96cffaf08de5`, last good `65c53ad280bc`, 4 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:135844: error: global fixup overflow
  near:  ProcCount  ]   >>> end  unit 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
