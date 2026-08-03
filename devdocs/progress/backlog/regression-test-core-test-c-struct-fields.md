---
prio: 70
---

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_c_struct_fields.pas red at 42786f141ea7 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host xeon). Untriaged.
- **Found:** 2026-08-03T10:55:23Z
- **Test source:** test/test_c_struct_fields.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_c_struct_fields.pas'` at 42786f141ea7b8b86f84b8f074d887f0e98c1401

## Range
bad `42786f141ea7`, last good `2028afba02ca`, 3 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2632327/c_struct_fields26  [code=74701B  data=2304B  bss=9540B  procs=163]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
