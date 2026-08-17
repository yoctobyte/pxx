---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_procvar_value_context.pas red at 0e4ad46330ca (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-17T19:25:20Z
- **Test source:** test/test_procvar_value_context.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_procvar_value_context.pas'` at 0e4ad46330ca3d81a4f2494eae6d4a4cd1182a42

## Range
bad `0e4ad46330ca`, last good `77b46c7cc860`, 5 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-450957/test_procvar_value_context26  [code=56343B  data=1608B  bss=9588B  procs=122]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-08-17 — auto-closed by the plexus watcher: `test-core#src:test/test_procvar_value_context.pas` passes at e6f2264d38ea (tier native); it was red at 0e4ad46330ca. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
