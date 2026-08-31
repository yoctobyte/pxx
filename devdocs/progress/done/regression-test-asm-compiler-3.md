---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 28 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-asm#src:compiler/compiler.pas red at 5944ee686c10 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-30T06:29:38Z
- **Test source:** compiler/compiler.pas

## Repro
`tools/testmgr.py --tier full --job 'test-asm#src:compiler/compiler.pas'` at 5944ee686c10298c6e7f3d5f204925f196058e86

## Range
bad `5944ee686c10`, last good `5dbcc861e3fc`, 24 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:4836: warning: bare own name 'TargetDisplayName' reads the result of parameterless function TargetDisplayName; write TargetDisplayName() for a recursive call, or Result to read the result
ok: /tmp/testmgr-scratch-1111999/test_asm_dis_self26.s  [-S disassembly]
ok: /tmp/testmgr-scratch-1111999/test_asm_dis_self26  [code=9547600B  data=430448B  bss=76381820B  procs=3500]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-08-31 — auto-closed by the seven watcher: `test-asm#src:compiler/compiler.pas` passes at e436930bac42 (tier native); it was red at 44ec32358394. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
