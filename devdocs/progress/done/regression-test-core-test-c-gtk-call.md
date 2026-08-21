---
prio: 70
---

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_c_gtk_call.pas red at ef7f17d45caa (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-21T11:33:41Z
- **Test source:** test/test_c_gtk_call.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_c_gtk_call.pas'` at ef7f17d45caae7d515cccd2dfee82fc68148e36b

## Range
bad `ef7f17d45caa`, last good `0531b3b6735a`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:2: warning: #include <alloca.h> resolved from the host system (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave
pascal26:2: warning: #include <dirent.h> resolved from the host system (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave
pascal26:2: warning: #include <features.h> resolved from the host system (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave
pascal26:2: warning: #include <linux/limits.h> resolved from the host system (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave
ok: /tmp/testmgr-scratch-4105457/test_c_gtk_call26  [code=137673B  data=3252B  bss=42468B  procs=14038]
gtk_init resolved and called successfully!

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-08-21 — auto-closed by the plexus watcher: `test-core#src:test/test_c_gtk_call.pas` passes at de2de369ea6a (tier native); it was red at ef7f17d45caa. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
