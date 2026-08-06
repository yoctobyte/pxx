---
prio: 70
---

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_exception_unhandled.pas@1 red at 899e51cda3ba (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-06T18:55:45Z
- **Test source:** test/test_exception_unhandled.pas test/test_threadsafe_layout_rtti.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_exception_unhandled.pas@1'` at 899e51cda3ba24d5faa2e5e6d4c3985e3cdc53d1

## Range
bad `899e51cda3ba`, last good `ce6cdc29af37`, 6 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2450276/test_exception_unhandled26  [code=47206B  data=1440B  bss=9516B  procs=95]
ok: /tmp/testmgr-scratch-2450276/test_threadsafe_layout_rtti26  [code=50900B  data=2236B  bss=9548B  procs=99]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
