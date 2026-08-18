---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nested_class_type_b348.pas red at ce57db4cdda5 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-18T03:59:00Z
- **Test source:** test/test_nested_class_type_b348.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nested_class_type_b348.pas'` at ce57db4cdda52a364f78588e0115fbe4c96828c7

## Range
bad `ce57db4cdda5`, last good `e0f6748717e6`, 9 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:64: error: invalid optional IR node reference in block first
(tail)
pascal26:64: error: invalid optional IR node reference in block first
  near:  FAILED   fails   >>> end  unit 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-08-18 — auto-closed by the plexus watcher: `test-core#src:test/test_nested_class_type_b348.pas` passes at 5b43ad800d23 (tier native); it was red at ce57db4cdda5. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
