---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 13 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_variant_string_ops.pas red at df21e490d798 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-23T22:20:48Z
- **Test source:** test/test_variant_string_ops.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_variant_string_ops.pas'` at df21e490d7989a812fc35b0f5f2dc5b5ea0e4bab

## Range
bad `df21e490d798`, last good `fd93e4a71c37`, 13 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1397860/test_variant_string_ops26  [code=129332B  data=3248B  bss=42700B  procs=229]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
