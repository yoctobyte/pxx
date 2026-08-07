---
prio: 70
---

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_dynarray_params.pas red at 34670fe9b872 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-07T06:56:07Z
- **Test source:** test/test_dynarray_params.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_dynarray_params.pas'` at 34670fe9b872dcfeee0e4a283c44cf0742466800

## Range
bad `34670fe9b872`, last good `06786c25ffc8`, 7 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3219155/test_dynarray_params26  [code=51782B  data=1536B  bss=9700B  procs=99]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
