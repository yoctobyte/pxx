---
prio: 70
---

> **origin/master has advanced 12 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_basic_comprehensive.bas red at 7d4a3dbb99ce (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-23T23:22:22Z
- **Test source:** test/test_basic_comprehensive.bas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_basic_comprehensive.bas'` at 7d4a3dbb99ce2bc83a5fbde50a6844292c5bd21a

## Range
bad `7d4a3dbb99ce`, last good `df21e490d798`, 14 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:3906: error: compiler error: call to a runtime stub that was never emitted (code offset 0 is the ELF entry point). A frontend driver is missing its stub-emission call for the current flags/target.
(tail)
pascal26:3906: error: compiler error: call to a runtime stub that was never emitted (code offset 0 is the ELF entry point). A frontend driver is missing its stub-emission call for the current flags/target.
  in: /tmp/testmgr-scratch-1498618/compiler/builtin/builtinheap.pas
  near: Exit  end  end  >>> end  function 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
