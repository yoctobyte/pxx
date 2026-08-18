---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_stackless_gen.pas red at dfac1da00b04 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-18T20:57:06Z
- **Test source:** test/test_stackless_gen.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_stackless_gen.pas'` at dfac1da00b04ad41b85996873b19ad4c767d37ca

## Range
bad `dfac1da00b04`, last good `9d96253f2c14`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:141: error: for-in generator: a variant argument needs pylib (pycell_new) in scope
(tail)
pascal26:141: error: for-in generator: a variant argument needs pylib (pycell_new) in scope
  near: mv  score     >>>  writeln  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
