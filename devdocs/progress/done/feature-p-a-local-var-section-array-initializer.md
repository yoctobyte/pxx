---
track: P
prio: 45
type: feature
blocked-by: []
status: done
owner: "frankD"
created: 2026-09-06
summary: "FIXED 2026-09-06. `var CCNames: array[TCallingConvention] of String = ('', 'register', ...)` inside a routine was refused with `local var-section ARRAY initializer not supported; assign in statements` — a message that reads like a missing capability and was a missing FORK. THE CAPABILITY WAS PRESENT TWICE OVER: the same declaration at FILE SCOPE has always worked, and so has the local `const` spelling (both MEASURED at the reverted binary). `ParseVarSection` has its OWN array-initializer loop that already derives its dimensions from the declared SYMBOL — it is not the const path and needs nothing extracted from it — and that loop simply wrote `PendingInit*` at all of its element sites, which a routine has no table for. A new `RegisterVarInitElem(symIdx, elemIdx, kind, val, aux, tkOrd, isLocal)` makes that one choice in one place (mapping global kind 8, metaclass, to local kind 5) and the six element sites route through it. A routine-local DYNAMIC array is still refused, deliberately and with a narrower message: its element list is carried as an AST node (pending-init kind 10) and `FlushLocalInits` reads kinds 0/1/2/4/5/9, none of which holds a node — filed as the residual. Unblocked fcl-passrc rung 7 pparser.pp, which advanced from :635 to :2468. Test `test_a_routine_local_var_array_initializer` (test-core#234)."
---

# A local var-section array initializer

- **Type:** feature (compat — FPC-legal, refused) — **Track P**
  (`compiler/pasparser_decl.inc`).
- Found in fcl-passrc rung 7, [[feature-pascal-corpus-expansion]]; the second
  wall in `pparser.pp` (7823 lines).

## The measurement, and it is the whole ranking argument

```pascal
function ByConst(c: TCC): string;
const Names: array[TCC] of string = ('', 'register', 'cdecl');   { WORKS }
begin ByConst := Names[c]; end;

function ByVar(c: TCC): string;
var Names: array[TCC] of string = ('', 'register', 'cdecl');     { REFUSED }
begin ByVar := Names[c]; end;
```

fpc 3.2.2 `-Mobjfpc` prints `register/cdecl` for both. pxx prints it for the
first and refuses the second at parse time.

**So nothing about the shape is unsupported.** The element loop, the enum-indexed
bound, the string elements, the routine-local flush into the prologue — all of it
runs correctly today for the `const` spelling. This is one more enumerated door:
the var site already forks to `ParseRecordInitializerInto` for
`var L: TRec = (n: 9)`, and the array arm beside it is `Error(...)`.

## Why it is not a small fix anyway

The const array initializer is **not a routine**. It is ~315 lines inline in
`ParseConstSection` (roughly `pasparser_decl.inc:3556`–`:3910`) and it reads and
writes that routine's locals throughout: `cIdx`, `cLo`/`cHi`, `cElemTk`,
`cnNDims`, `cnDimLo[]`/`cnDimSpan[]`, `cDepth`, `cElem`, `cAi`, `isLocalConst`,
plus `LastTypeRecId` and the pointee state. It also **parses the type itself**,
from `array[` onward, which the var path has already done.

So the extraction has to split "parse the type" from "parse the initializer" and
give the second half its dimensions from the already-declared **symbol**
(`SymArrNDims`, the element kind, the bounds) rather than from the parse it
currently shares. That is the right design — one initializer parser, two
declaration spellings — and it is the step that stops being mechanical, because
each derived value has to be verified equal to what the parse produced rather
than assumed.

## Gate

Both spellings in one file asserting the same VALUES, plus a multi-dimensional
row and a record-element row (the two shapes most likely to differ between the
parse-derived and symbol-derived dimension lists). The const spelling is the
control and must not move: every const array in `lib/rtl` goes through this
code, so `gate.sh quick`, the fgl corpus and the conformance suite all bear on
the extraction.

## CORRECTION 2026-09-06, same day, by the author — the premise above is wrong

**"Why it is not a small fix anyway" is false, and so is the sentence in the
original summary that the work was an EXTRACTION from `ParseConstSection`.**
Everything the section says about the const initializer is accurate — it *is*
~315 lines inline, it *does* read that routine's locals — and none of it was
relevant, because **the var path never needed to call it.**

`ParseVarSection` has its **own** array-initializer loop, and that loop already
does the thing the ticket proposed building: it derives its dimensions from the
already-declared SYMBOL (`SymArrNDims`, `vRowSpan`, the element kind) rather
than from the parse. It was complete. It just wrote `PendingInit*` at every one
of its element sites — the global table — and a routine has no pending-init
table, so the whole loop was fenced off behind one `Error` for locals.

**How the wrong premise was formed:** I reasoned from the `const` spelling
working, concluded the machinery lived in `ParseConstSection`, and never looked
for a second copy in the routine I was about to edit. The global `var` spelling
already worked too, and that is the observation that would have settled it in
one line — `var G: array[...] of T = (...)` at file scope has always compiled.
**A capability that works in two places is evidence about where the code is, and
I sampled only one of them.** [[a-caller-census-cannot-find-an-absent-copy]]

## The fix as landed

`RegisterVarInitElem(symIdx, elemIdx, gKind, val, valAux, tkOrd, isLocal)` —
inserted immediately before `ParseVarSection` — writes `LocalInit*` when
`isLocal` and `PendingInit*` otherwise, maps global kind 8 (metaclass) to local
kind 5, and `Error`s on kind 10 for locals. The local block stops refusing
arrays wholesale and refuses only `isDyn`; `vIsLocal := CurProc >= 0` is
computed once beside `vNDims`; the four paren-loop element sites and both
`SpreadCharLiteral` calls route through the helper.

## What was measured, not assumed

- **The positive control fired**: with the fix backed out and the compiler
  rebuilt, the fixture fails at its first local array (`pascal26:47: error: local
  var-section ARRAY initializer not supported`). Binary sha returned to
  `5dc94380872f` after restore — the same one — so the revert/restore cycle did
  not drift the seed.
- **Both controls are pre-existing**: `global` and `localconst` print correctly
  *at the reverted binary*. They are in the fixture because this change threads a
  flag through code they both run, not because it supplies them.
- **Entry semantics agree with FPC.** pxx flushes local inits as an assignment on
  entry, every call; an initialised local could plausibly instead be a static
  initialised once (FPC's `{$J+}` typed-const behaviour). Measured: fpc 3.2.2
  `-Mobjfpc` prints `11 11 11` for a mutated-and-recalled initialised local,
  array and scalar alike, and so does pxx. The fixture asserts the agreement
  rather than avoiding the shape.

## Residual

A routine-local **dynamic** array initializer (`var v: array of Integer =
(1,2,3)` inside a routine) is still refused. fpc accepts it. See
[[feature-p-a-routine-local-dynamic-array-initializer]].

## Log

- 2026-09-06 — fixed, commit b612f30e8. The same commit rewrote this ticket's
  summary, which was wrong about where the code lived (see the CORRECTION
  above). Residual filed as
  [[feature-p-a-routine-local-dynamic-array-initializer]].
