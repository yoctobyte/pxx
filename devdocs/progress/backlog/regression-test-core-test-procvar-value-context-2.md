---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_procvar_value_context.pas red at a2ae11a64191 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-20T23:09:05Z
- **Test source:** test/test_procvar_value_context.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_procvar_value_context.pas'` at a2ae11a641911bbec759e4ccd454b9a6aca38ea6

## Range
bad `a2ae11a64191`, last good `6ab56d11a9aa`, 5 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2383069/test_procvar_value_context26  [code=58496B  data=1608B  bss=42516B  procs=125]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
