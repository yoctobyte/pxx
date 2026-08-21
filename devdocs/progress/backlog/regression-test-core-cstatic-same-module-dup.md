---
prio: 70
track: C
---

> **Track guessed as C** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 13 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/cstatic_same_module_dup.c red at 99dcac2a2ade (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-21T15:30:27Z
- **Test source:** test/cstatic_same_module_dup.c

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/cstatic_same_module_dup.c'` at 99dcac2a2ade0352ceb8fe8fc8aadbc2071ca422

## Range
bad `99dcac2a2ade`, last good `de2de369ea6a`, 11 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
