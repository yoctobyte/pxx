---
prio: 30  # auto
---

# bug: impl-prescan rejects include-level var sections late in the include chain

- **Type:** bug (Track A — impl prescan / declaration ordering)
- **Status:** backlog
- **Opened:** 2026-07-06 (found by the Whitespace esoteric probe — exactly the
  kind of shared-internals find the probe category exists for)

## Symptom

A `var` section at the top of an include file placed LATE in compiler.pas's
include chain (observed at the `wparser.inc` position, after
c/b/py/r/a/z/l-parser includes) fails self-compilation with:

    error: undefined variable — it is a global declared later, declare it before use (WsPos)

even though the var section lexically PRECEDES every use (same file, top of
file, functions below it). The identical shape works fine in an EARLIER
include: bparser.inc's `BLineTarget*`/`BGosub*` block (added the same day for
the GOTO/GOSUB fix) compiles and self-hosts cleanly at include position ~90.

Not reproduced in isolation/minimized — the workaround was cheap (moved the
globals to defs.inc, see wparser.inc's header note), so the minimization is
left to whoever picks this up. Suspect the impl prescan records declaration
positions in a way that mis-orders late-include var sections relative to the
proc bodies that use them.

## Repro sketch

Revert the workaround: move the `WsPos/WsStk/WsSp/WsStmtList/WsDone` block
from defs.inc back to the top of wparser.inc and `make compiler/pascal26`.

## Impact

Low (workaround = declare frontend state in defs.inc, which is arguably
cleaner anyway and matches where C-frontend state lives). Filed for
correctness: "declared later" should not fire for a declaration that is
lexically first.
