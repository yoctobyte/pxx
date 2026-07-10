---
prio: 30  # auto
---

# bug: impl-prescan rejects include-level var sections late in the include chain

- **Type:** bug (Track A — impl prescan / declaration ordering)
- **Status:** done
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

## Root cause CONFIRMED + partial fix attempted, REVERTED 2026-07-10 (A+B+C session)

Instrumented `SymDeclTok[WsPos]` / `CurBodyHdrTok` / every token edit on the
FAILING layout (WsPos = sym k=1698, stamped at TokPos≈521461, TokCount≈596326).

**Root cause (exact):** `AdjustPass2Spans` (lexer.inc:2064) fixes `DeclItemStart`/
`DeclItemEnd`/`Pass2BodyTok` when a **pass-2** token edit shifts the stream
(`ParseNestedRoutine` excises a nested body → `AdjustPass2Spans(finalCur,
-remCount)` at parser.inc ~14496; generic `InsertTokens` likewise) — but it does
**NOT** adjust `SymDeclTok[]`. So during pass 2 the body-header horizon
(`CurBodyHdrTok`, derived from the adjusted `DeclItemStart`) moves down with the
edits while `SymDeclTok[WsPos]` keeps its stale pass-1 token index → the
`SymDeclTok > CurBodyHdrTok` test in `HiddenByDeclOrder` fires falsely. bparser's
identical block survives only because fewer excisions accumulate before its
(earlier) include position.

**Partial fix tried:** add the parallel loop to `AdjustPass2Spans`
(`for k := 0 to SymCount-1 do if SymDeclTok[k] >= atPos then SymDeclTok[k] += delta`).
Confirmed it runs (19 adjustments hit k=1698). It makes MANY layouts pass — but it
is **necessary-but-insufficient / Heisenbug**: the per-excision `>= atPos` boundary
is individually correct, yet the clean `build` still inverts by a few tokens at the
exact self-source layout while any instrumentation (which shifts token positions)
makes it pass. Excision deltas are large (observed −93, −50, −36), so a 1-token
boundary flip swings `SymDeclTok[WsPos]` by ~90 and tips the `>` comparison. So
adjusting token INDICES on every edit is fundamentally fragile here — there is a
residual edit path (suspect a pass-1 edit while `Pass2Active=False`, where
`AdjustPass2Spans` early-exits and neither `DeclItemStart` nor `SymDeclTok` are
adjusted, leaving a layout-dependent skew), or a codegen sensitivity in the clean
build.

**Robust direction (for next picker, NOT yet done):** stop tracking token INDICES
(which shift under excision/insertion) and compare **immutable source char offsets**
instead — stamp `SymDeclTok := Tokens[TokPos].SOffset` and set `CurBodyHdrTok`
from the body header's `.SOffset`; source offsets never move under token-array
edits, so no per-edit adjustment is needed at all. Risk: generic-specialized /
lifted-nested-routine bodies carry synthetic or original `.SOffset`s (possibly 0),
which could break decl-order for those bodies — must be validated against the full
generic/nested corpus + self-host byte-identical before landing. That validation +
the shared-`parser.inc` `CurBodyHdrTok` change is more self-host risk than this
prio-30 warrants, so still parked behind the clean defs.inc workaround.

## Log
- 2026-07-10 — resolved, commit b6563fc5.
