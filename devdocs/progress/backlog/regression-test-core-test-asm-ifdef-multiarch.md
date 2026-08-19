---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_asm_ifdef_multiarch.pas red at 498c6dea3f48 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-19T14:09:54Z
- **Test source:** test/test_asm_ifdef_multiarch.pas test/test_asm_att_reject.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_asm_ifdef_multiarch.pas'` at 498c6dea3f48816144fa8959a6534d131959a68c

## Range
bad `498c6dea3f48`, last good `7364f6c5bdfe`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1799398/test_asm_ifdef_ma26  [code=55229B  data=1528B  bss=9492B  procs=113]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
