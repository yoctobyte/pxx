---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_strict_overload_width.pas@1 red at 943c706936b3 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-20T09:25:51Z
- **Test source:** test/test_strict_overload_width.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_strict_overload_width.pas@1'` at 943c706936b329e1777d68892c8e4eb444211ea8

## Range
bad `943c706936b3`, last good `b24bb1474624`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-326413/test_sow_default26  [code=293112B  data=9124B  bss=53920B  procs=586]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
