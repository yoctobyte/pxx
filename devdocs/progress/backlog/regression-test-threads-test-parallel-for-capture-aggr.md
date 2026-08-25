---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-threads#src:test/test_parallel_for_capture_aggr.pas red at b936d125601e (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-25T06:10:56Z
- **Test source:** test/test_parallel_for_capture_aggr.pas

## Repro
`tools/testmgr.py --tier native --job 'test-threads#src:test/test_parallel_for_capture_aggr.pas'` at b936d125601ea26a9e570d65be152ff3a35d04a0

## Range
bad `b936d125601e`, last good `0626344011cf`, 6 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:23: error: this value cannot be indexed — only arrays, strings and pointers can (g)
pascal26:24: error: this value cannot be indexed — only arrays, strings and pointers can (d)
pascal26:24: error: this value cannot be indexed — only arrays, strings and pointers can (g)
(tail)
pascal26:23: error: this value cannot be indexed — only arrays, strings and pointers can (g)
  in: /tmp/testmgr-scratch-584035/compiler/../lib/rtl/palthread.pas
  near: begin g   i  >>>  cfg  
pascal26:24: error: this value cannot be indexed — only arrays, strings and pointers can (d)
  in: /tmp/testmgr-scratch-584035/compiler/../lib/rtl/palthread.pas
  near:  d   i  >>>  g  
pascal26:24: error: this value cannot be indexed — only arrays, strings and pointers can (g)
  in: /tmp/testmgr-scratch-584035/compiler/../lib/rtl/palthread.pas
  near:  g   i  >>>    

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
