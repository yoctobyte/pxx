---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_pascal_at_procvar_mode.pas@1 red at 23becd24b8e5 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-21T02:07:19Z
- **Test source:** test/test_pascal_at_procvar_mode.pas

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_pascal_at_procvar_mode.pas@1'` at 23becd24b8e5a952d29006a6efbab7e4a6068a0d

## Range
bad `23becd24b8e5`, last good `1b9b43e5b511`, 109 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2767347/test_pascal_at_procvar_d26  [code=58611B  data=1560B  bss=42476B  procs=121]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
