---
prio: 70
---

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-smoke#src:compiler/compiler.pas red at b11e604f8043 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host xeon). Untriaged.
- **Found:** 2026-08-02T12:24:57Z
- **Test source:** compiler/compiler.pas test/bootstrap_features.pas

## Repro
`tools/testmgr.py --tier native --job 'test-smoke#src:compiler/compiler.pas'` at b11e604f80437ae06888c3a38988b18247cf7320

## Range
bad `b11e604f8043`, last good `07e4f8424e6f`, 3 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-653976/pascal26-self  [code=6048122B  data=181032B  bss=154010164B  procs=2379]
sh: 6: /tmp/testmgr-scratch-653976/pascal26-self: Text file busy

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-08-02 — auto-closed by the xeon watcher: `test-smoke#src:compiler/compiler.pas` passes at f3e839eb7675 (tier native); it was red at b11e604f8043. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
