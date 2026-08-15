---
prio: 70
---

> **origin/master has advanced 10 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-asm#src:compiler/compiler.pas red at d2172550a236 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-14T23:04:26Z
- **Test source:** compiler/compiler.pas

## Repro
`tools/testmgr.py --tier native --job 'test-asm#src:compiler/compiler.pas'` at d2172550a236aea07e51f3dc97d1f814246299d4

## Range
bad `d2172550a236`, last good `59f70a2ce7b0`, 5 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1079028/test_asm_dis_self26.s  [-S disassembly]
ok: /tmp/testmgr-scratch-1079028/test_asm_dis_self26  [code=6928090B  data=210960B  bss=159489188B  procs=2747]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-08-15 — auto-closed by the plexus watcher: `test-asm#src:compiler/compiler.pas` passes at d61380078f35 (tier native); it was red at d2172550a236. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
