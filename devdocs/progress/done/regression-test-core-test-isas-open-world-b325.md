---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_isas_open_world_b325.pas red at a76303231306 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-19T13:59:40Z
- **Test source:** test/test_isas_open_world_b325.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_isas_open_world_b325.pas'` at a763032313063caaa4da3a0039d25959752c4b58

## Range
bad `a76303231306`, last good `952aada2cb5d`, 6 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:31: error: unexpected token
(tail)
Expected: ), but got:  (Kind: 81, Line: 31)
pascal26:31: error: unexpected token
  near: as=  PassesAs  L  >>>  Describe  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-08-19 — auto-closed by the plexus watcher: `test-core#src:test/test_isas_open_world_b325.pas` passes at 71099dcb1104 (tier native); it was red at a76303231306. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
