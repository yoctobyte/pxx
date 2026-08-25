---
prio: 70
track: N
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_json_reparse_heap.npy red at a28bc3993a0e (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-25T11:28:59Z
- **Test source:** test/test_nilpy_json_reparse_heap.npy

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_json_reparse_heap.npy'` at a28bc3993a0e0caa0370b71abb1759287d3e9909

## Range
bad `a28bc3993a0e`, last good `d34ea0c3e6f0`, 9 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault
(tail)
ok: /tmp/testmgr-scratch-1206539/test_nilpy_jsonrep26  [code=2388648B  data=75864B  bss=75420B  procs=2002]
Segmentation fault

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
