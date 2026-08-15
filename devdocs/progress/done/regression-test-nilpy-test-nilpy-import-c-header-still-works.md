---
prio: 70
---

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_import_c_header_still_works.npy red at 36d1bffda39d (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-15T15:21:24Z
- **Test source:** test/test_nilpy_import_c_header_still_works.npy

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_import_c_header_still_works.npy'` at 36d1bffda39d58099b403745c48b95cd8c1d7c58

## Range
bad `36d1bffda39d`, last good `0d8e7393a09c`, 14 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:25: error: undefined variable (malloc)
(tail)
pascal26:23: warning: #include <features.h> resolved from the host system (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave
pascal26:23: warning: #include <features.h> resolved from the host system (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave
pascal26:23: warning: #include <features.h> resolved from the host system (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave
pascal26:23: warning: #include <features.h> resolved from the host system (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave
pascal26:25: error: undefined variable (malloc)
  near:  stdio  p  malloc >>>    

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-08-15 — auto-closed by the plexus watcher: `test-nilpy#src:test/test_nilpy_import_c_header_still_works.npy` passes at c8f5070671be (tier full); it was red at 63d1d0de90d3. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
