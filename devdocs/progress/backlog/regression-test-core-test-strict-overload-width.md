---
prio: 70
---

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_strict_overload_width.pas@1 red at fea1f33d2f30 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-16T07:00:28Z
- **Test source:** test/test_strict_overload_width.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_strict_overload_width.pas@1'` at fea1f33d2f304d829a0422bc36f938edc411bc57

## Range
bad `fea1f33d2f30`, last good `8938aed7d55b`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1184201/test_sow_default26  [code=236664B  data=9140B  bss=42784B  procs=561]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
