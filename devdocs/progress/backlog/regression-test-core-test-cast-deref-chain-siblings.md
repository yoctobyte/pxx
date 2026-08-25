---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_cast_deref_chain_siblings.pas red at 0bc0cfac61a8 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-25T12:31:10Z
- **Test source:** test/test_cast_deref_chain_siblings.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_cast_deref_chain_siblings.pas'` at 0bc0cfac61a878e4da78348389458d180061c417

## Range
bad `0bc0cfac61a8`, last good `a28bc3993a0e`, 7 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1349025/test_cast_sib26  [code=64635B  data=2112B  bss=42532B  procs=128]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
