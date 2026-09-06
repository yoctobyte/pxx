---
track: P
prio: 45
type: feature
blocked-by: []
status: open
owner: ""
created: 2026-09-06
summary: "`var CCNames: array[TCallingConvention] of String = ('', 'register', ...)` inside a routine is refused with `local var-section ARRAY initializer not supported; assign in statements`. IT IS A DOOR, NOT A CAPABILITY GAP, AND THAT IS THE MEASUREMENT THAT MAKES THIS CHEAP TO RANK: the same declaration spelled `const` in the same routine COMPILES AND RUNS correctly today, so the whole element-parsing, folding and local-init machinery already exists and works for exactly this shape — only the `var` path never got an entry to it. The var site (pasparser_decl.inc:2703) already forks to ParseRecordInitializerInto for the local RECORD form; the array form is the arm that was never added. The work is not the fix, it is the EXTRACTION: the const array initializer is ~315 lines inline in ParseConstSection (~3556-3910) and entangled with that routine's locals (cIdx, cLo/cHi, cElemTk, cnNDims, cnDimLo/cnDimSpan, cDepth, cElem, isLocalConst). A reusable `ParseArrayInitializerInto(symIdx, isLocal)` would have to derive the dimension list and element kind from the ALREADY-DECLARED symbol instead of from the parse it currently shares — which is the cleaner design and is also the part that stops being mechanical. Blocks fcl-passrc rung 7 pparser.pp at :635."
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
