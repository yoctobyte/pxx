---
prio: 70
---

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_writeln_nonfinite_float.pas red at ad8e212cf739 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-05T17:47:16Z
- **Test source:** test/test_writeln_nonfinite_float.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_writeln_nonfinite_float.pas'` at ad8e212cf739231cf0055e382af45703a8de4407

## Range
bad `ad8e212cf739`, last good `030b9a625d8c`, 4 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-550086/test_writeln_nonfinite26  [code=85920B  data=2336B  bss=9524B  procs=167]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
