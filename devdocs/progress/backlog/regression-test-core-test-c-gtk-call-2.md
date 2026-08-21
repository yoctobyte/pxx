---
prio: 70
---

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_c_gtk_call.pas red at 98ed38202254 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-21T22:41:55Z
- **Test source:** test/test_c_gtk_call.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_c_gtk_call.pas'` at 98ed382022547bbe6624c779ee024a3ad1dea518

## Range
bad `98ed38202254`, last good `f74df41e851c`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:2: warning: #include <alloca.h> resolved from the host system (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave
pascal26:2: warning: #include <dirent.h> resolved from the host system (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave
pascal26:2: warning: #include <features.h> resolved from the host system (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave
pascal26:2: warning: #include <linux/limits.h> resolved from the host system (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave
ok: /tmp/testmgr-scratch-968330/test_c_gtk_call26  [code=140327B  data=3420B  bss=42476B  procs=14048]
gtk_init resolved and called successfully!

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
