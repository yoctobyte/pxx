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

## Reproduced + localized 2026-07-08 (A+C session) — still parked (self-host risk)
Confirmed the repro (moved the `WsPos/WsStk/WsSp/WsStmtList/WsDone` var block
from defs.inc back to the top of wparser.inc):
`pascal26:80186: error: undefined variable — it is a global declared later,
declare it before use (WsPos)`.

The check that fires is `HiddenByDeclOrder` (symtab.inc:1655): a global is hidden
when `SymDeclTok[i] > CurBodyHdrTok`. Both are set from `TokPos`
(SymDeclTok at symtab.inc:1842; CurBodyHdrTok at parser.inc:15364, the routine
body header). For a var section at the TOP of an include with its functions
BELOW, SymDeclTok[WsPos] should be < the functions' CurBodyHdrTok — so the true
bug is that the late-include var section's recorded TokPos lands ABOVE the
using-body header. Suspect the two-pass prescan (PreScanPass + the pass2 TokPos
save/restore around parser.inc:16996-17102): the var block is likely (re)registered
in a pass where TokPos has already advanced past the bodies, or the include's
tokens aren't ordered monotonically vs the proc headers during prescan. Fix is in
that prescan token-ordering — shared parser internals, self-host risk — so left
parked behind the defs.inc workaround. Next picker: instrument SymDeclTok[WsPos]
and CurBodyHdrTok at the failing lookup to see the exact inversion.
