---
prio: 70
---

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/csystem_libs_granular_libc_b113.c red at b39ac8f02003 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-09T19:46:04Z
- **Test source:** test/csystem_libs_granular_libc_b113.c

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/csystem_libs_granular_libc_b113.c'` at b39ac8f02003edb70d9a8340bb87fec7636d2915

## Range
bad `b39ac8f02003`, last good `a3ab6ac85452`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:28: warning: C declaration of 'floor' disagrees with the Pascal routine 'Floor' on the result type (float vs non-float) — binding to the C declaration
pascal26:29: warning: C declaration of 'ceil' disagrees with the Pascal routine 'Ceil' on the result type (float vs non-float) — binding to the C declaration
ok: /tmp/testmgr-scratch-2661557/csystem_libs_granular_libc_b11326  [code=196314B  data=1128B  bss=5288B  procs=637]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-08-09 — auto-closed by the plexus watcher: `test-core#src:test/csystem_libs_granular_libc_b113.c` passes at 11019fe12085 (tier native); it was red at b39ac8f02003. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
