---
prio: 70
---

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_stmt_call_result_selector_b318.pas red at 33cd0117f9f9 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-05T07:40:32Z
- **Test source:** test/test_stmt_call_result_selector_b318.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_stmt_call_result_selector_b318.pas'` at 33cd0117f9f98d0b2fa08b13fb1b8364e8ca1266

## Range
bad `33cd0117f9f9`, last good `1787b2cf4b61`, 7 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:43: error: "TBox.Poke" is a procedure and has no result to use in an expression
(tail)
pascal26:43: error: "TBox.Poke" is a procedure and has no result to use in an expression
  near: end  begin GetBox  Poke >>>  GetBox  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
