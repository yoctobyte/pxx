---
prio: 70
---

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-i386#src:test/test_dynarray_field.pas red at 899e51cda3ba (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-06T19:03:41Z
- **Test source:** test/test_dynarray_field.pas tools/run_target.sh

## Repro
`tools/testmgr.py --tier full --job 'test-i386#src:test/test_dynarray_field.pas'` at 899e51cda3ba24d5faa2e5e6d4c3985e3cdc53d1

## Range
bad `899e51cda3ba`, last good `unknown`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2456798/test_i386_dynfield  [code=67861B  data=2560B  bss=9504B  procs=100]
ok: /tmp/testmgr-scratch-2456798/test_i386_dynfield_x64  [code=50227B  data=2472B  bss=9548B  procs=100]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
