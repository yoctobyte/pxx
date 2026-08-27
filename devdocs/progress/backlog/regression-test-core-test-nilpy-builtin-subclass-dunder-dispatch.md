---
prio: 70
track: N
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_builtin_subclass_dunder_dispatch.npy red at c28e07a89f03 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-27T14:05:25Z
- **Test source:** test/test_nilpy_builtin_subclass_dunder_dispatch.npy

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_builtin_subclass_dunder_dispatch.npy'` at c28e07a89f036f56d3bb860e62045b1103e22aae

## Range
> **The named sha `c28e07a89f03` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `c28e07a89f03`, last good `0842d9684f7f`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:55: error: unexpected token
(tail)
Expected: ), but got: i (Kind: 1, Line: 55)
pascal26:55: error: unexpected token
  near: list  __getitem__  self  >>> i   

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
