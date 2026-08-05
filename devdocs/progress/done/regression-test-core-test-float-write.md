---
prio: 70
status: done
---

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_float_write.pas@1 red at ad8e212cf739 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-05T17:47:16Z
- **Test source:** test/test_float_write.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_float_write.pas@1'` at ad8e212cf739231cf0055e382af45703a8de4407

## Range
bad `ad8e212cf739`, last good `030b9a625d8c`, 4 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-550086/test_float_write_ir26  [code=49698B  data=1392B  bss=9484B  procs=93]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Resolved (2026-08-05) — caused by e7d4f3336, repaired

Mine, from the correctly-rounded-float fix. Two distinct causes:

**1. Algol / Fortran skeletons: a dependency the shim introduced.** Collapsing
the four float formatters into one made x86-64's `EmitWriteFloatSci` a SHIM onto
the runtime's `PXXWriteFloatSci`. The esoteric skeleton frontends link no RTL and
emit code immediately with no entry jump, so they cannot pull `builtinheap` —
they died with `compiler error: PXXWriteFloatSci not found`. (Pulling the unit
from `ParseGProgram` was tried: it compiles and then SEGFAULTS, because those
frontends have no entry jump for unit bodies to land behind.)

Repaired by keeping the original hand-written emitter as
`EmitWriteFloatSciSelfContained`, used ONLY when `FindProc` says the RTL writer
is absent. Every program that links the RTL — i.e. every real one — still gets
the exact formatter. The fallback carries a comment saying precisely what would
let someone delete it: give the probe frontends an entry jump.

**2. test_float_write / test_writeln_nonfinite_float: stale expectations.** They
encoded the OLD, WRONG digits:

| expectation | was | correct | oracle |
| --- | --- | --- | --- |
| 1234.5 | `1.2345000000000002E+003` | `1.2345000000000000E+003` | CPython `f'{1234.5:.16e}'` |
| 1e300 | `1.0000000000000007E+300` | `1.0000000000000001E+300` | FPC **and** CPython |

1234.5 is exactly representable, so trailing `...0002` was never right. Updated
against the oracles, not against pxx's own output.

**Verified:** `testmgr --tier native` **1158/1158 pass** (includes the
self-host fixedpoint and the fpc-bootstrap).
- 2026-08-05 — resolved, commit PENDING-COMMIT.
