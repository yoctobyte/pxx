---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 7 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_setlength_grow_capacity.pas red at 10dada0b7689 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-25T16:38:27Z
- **Test source:** test/test_setlength_grow_capacity.pas test/test_dynarray_concat_rejected.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_setlength_grow_capacity.pas'` at 10dada0b7689fee546516eec7ea90d1da4256053

## Range
bad `10dada0b7689`, last good `d20300d288eb`, 7 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1853321/test_setlength_grow_capacity26  [code=65250B  data=2016B  bss=42480B  procs=128]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
