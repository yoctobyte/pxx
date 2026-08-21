---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/fpcv.pas@2 red at 16a540b759c5 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-21T20:38:54Z
- **Test source:** test/fpcv.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/fpcv.pas@2'` at 16a540b759c53a2be03c3013751d90741ef38e40

## Range
bad `16a540b759c5`, last good `69e61a7bfda9`, 12 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-780297/fpcv26  [code=272689B  data=21384B  bss=75860B  procs=614]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
