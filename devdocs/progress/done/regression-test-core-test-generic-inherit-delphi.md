---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_generic_inherit_delphi.pas red at 98ed38202254 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-21T22:41:55Z
- **Test source:** test/test_generic_inherit_delphi.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_generic_inherit_delphi.pas'` at 98ed382022547bbe6624c779ee024a3ad1dea518

## Range
bad `98ed38202254`, last good `f74df41e851c`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:10: error: generic specialization nested deeper than 16 levels (or a rewrite loop)
(tail)
pascal26:10: error: generic specialization nested deeper than 16 levels (or a rewrite loop)
  near: type TBox  T   >>> class V  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-08-22 — auto-closed by the plexus watcher: `test-core#src:test/test_generic_inherit_delphi.pas` passes at b3594b8af2ff (tier native); it was red at 5179c4d4350b. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
