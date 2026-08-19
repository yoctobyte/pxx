---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_ctor_result_member.pas red at a76303231306 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-19T13:59:40Z
- **Test source:** test/test_ctor_result_member.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_ctor_result_member.pas'` at a763032313063caaa4da3a0039d25959752c4b58

## Range
bad `a76303231306`, last good `952aada2cb5d`, 6 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1766299/test_tcrm26  [code=95828B  data=3040B  bss=9540B  procs=205]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
