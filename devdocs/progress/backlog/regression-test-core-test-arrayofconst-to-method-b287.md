---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_arrayofconst_to_method_b287.pas red at a195f67d754b (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-26T16:41:03Z
- **Test source:** test/test_arrayofconst_to_method_b287.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_arrayofconst_to_method_b287.pas'` at a195f67d754bd886fbef7a26b2d3aa1b5a0e44df

## Range
> **The named sha `a195f67d754b` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `a195f67d754b`, last good `90892318c94c`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:22: error: set item must be one character
(tail)
pascal26:22: error: set item must be one character
  near:  Log  class: %s = %d   >>> answer   

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
