---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_typed_const_record.pas red at 406a40dfaffa (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-16T18:02:23Z
- **Test source:** test/test_typed_const_record.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_typed_const_record.pas'` at 406a40dfaffa9dbea2077cd1319605670801233f

## Range
bad `406a40dfaffa`, last good `17f671533234`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2793116/test_tc_record26  [code=54928B  data=1544B  bss=9524B  procs=113]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
