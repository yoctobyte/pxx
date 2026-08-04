---
prio: 70
---

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/csocket_loopback_b88.c red at 330f62af78d0 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host xeon). Untriaged.
- **Found:** 2026-08-04T23:06:27Z
- **Test source:** test/csocket_loopback_b88.c

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/csocket_loopback_b88.c'` at 330f62af78d0971ee8c39d5aa9bf6dc294aeaab7

## Range
bad `330f62af78d0`, last good `7d8929633721`, 58 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:1: error: C include file not found: "socket.c" (searched: test/, lib/crtl/include/, lib/crtl/src/, /tmp/testmgr-scratch-989299/../lib/crtl/include/, /tmp/testmgr-scratch-989299/../../lib/crtl/include/, lib/crtl/include/, <host system dirs>)
(tail)
pascal26:1: error: C include file not found: "socket.c" (searched: test/, lib/crtl/include/, lib/crtl/src/, /tmp/testmgr-scratch-989299/../lib/crtl/include/, /tmp/testmgr-scratch-989299/../../lib/crtl/include/, lib/crtl/include/, <host system dirs>)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
