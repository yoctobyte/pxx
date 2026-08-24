---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **This expectation records a REFUSAL** (a *_fail / {%FAIL} test). Before treating a converged bisect range as an accusation, check whether the named commit IMPLEMENTED the thing being refused -- a feature landing makes its own refusal test go red, and the bisect converges on it correctly. Not a verdict; the tool cannot decide this one.

> **origin/master has advanced 9 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_default_of_aggregate.pas red at 203438d2cf63 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-24T19:22:37Z
- **Test source:** test/test_default_of_aggregate.pas test/test_generic_cycle_fail.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_default_of_aggregate.pas'` at 203438d2cf6306c543194034cc6980662e5c23bf

## Range
bad `203438d2cf63`, last good `6d2af7ca7c23`, 7 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:76: error: incompatible types: cannot assign Int64 to AnsiString
pascal26:78: error: incompatible types: cannot assign Int64 to class
(tail)
pascal26:76: error: incompatible types: cannot assign Int64 to AnsiString
pascal26:78: error: incompatible types: cannot assign Int64 to class

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
