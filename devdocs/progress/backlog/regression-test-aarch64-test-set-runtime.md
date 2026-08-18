---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-aarch64#src:test/test_set_runtime.pas red at 61e2448bac6d (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-18T04:23:41Z
- **Test source:** test/test_set_runtime.pas tools/run_target.sh

## Repro
`tools/testmgr.py --tier full --job 'test-aarch64#src:test/test_set_runtime.pas'` at 61e2448bac6d3f61657fb54a746d3e33d2ad96fc

## Range
bad `61e2448bac6d`, last good `e0f6748717e6`, 12 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:42: error: invalid optional IR node reference in block first
(tail)
pascal26:42: error: invalid optional IR node reference in block first
  near:   in cand   >>> end  unit 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
