---
prio: 70
track: C
---

> **Track guessed as C** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/cglobal_fnptr_addressof_b161.c red at b645e1b2aff7 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-20T11:17:51Z
- **Test source:** test/cglobal_fnptr_addressof_b161.c

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/cglobal_fnptr_addressof_b161.c'` at b645e1b2aff7d0fc6f63267e833a4410c5a49fa8

## Range
bad `b645e1b2aff7`, last good `23730e49d446`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-651873/cglobal_fnptr_addressof_b16126  [code=90269B  data=504B  bss=4832B  procs=386]
Segmentation fault (core dumped)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
