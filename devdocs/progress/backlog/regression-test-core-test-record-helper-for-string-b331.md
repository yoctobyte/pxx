---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_record_helper_for_string_b331.pas red at 2e7286e499d1 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-20T21:33:51Z
- **Test source:** test/test_record_helper_for_string_b331.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_record_helper_for_string_b331.pas'` at 2e7286e499d1993717b2b5f139254bf5736c695a

## Range
bad `2e7286e499d1`, last good `9ac7e74e367b`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:71: error: undefined variable (BITS)
(tail)
pascal26:71: error: undefined variable (BITS)
  near:  Writeln  bits:     BITS >>>   end 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
