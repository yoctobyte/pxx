---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_timer.pas red at 26dae20b9dec (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-20T14:21:17Z
- **Test source:** test/test_timer.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_timer.pas'` at 26dae20b9dec8eb36cb0e8182d358e4a00e5baed

## Range
bad `26dae20b9dec`, last good `24df0095adfe`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1152877/test_timer26  [code=102842B  data=2912B  bss=47304B  procs=223]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-08-20 — auto-closed by the plexus watcher: `test-core#src:test/test_timer.pas` passes at fe8a34230146 (tier native); it was red at 26dae20b9dec. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
