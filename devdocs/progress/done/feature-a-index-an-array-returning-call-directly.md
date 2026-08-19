---
summary: "`MkArr[i]` and `MkArr2[i,j].field` off a call result: FPC accepts every array-result spelling, pxx accepted exactly one and by accident of routing"
track: A
prio: 40
type: feature
blocked-by: []
status: done
owner: frankonpiler-an
---

# Index an array-returning call directly: `MkArr[i]`, `MkR2[i,j].field`

- **Type:** feature (FPC accepts all of these) — **Track A**
- **Split from** [[bug-a-indexing-a-function-call-result-drops-the-field-selector]],
  which fixed the SILENT half (a dropped field selector) and left these refused
  with a diagnostic.

FPC accepts `f(...)[i]` for every array result. pxx accepts exactly one
spelling, and by accident of routing. Measured 2026-08-10:

| expression | today |
| --- | --- |
| `MkS[2]` — string result | works (own arm, hidden temp + `AN_COMMA`) |
| `MkRec.a` — record result | works |
| `MkR[i].field` — array OF RECORD result | works (fixed; arrives via the record selector arm because `Procs[].RetType` is the ELEMENT kind) |
| `MkArr[i]` — array of a SCALAR | refused: `cannot index the result of an array-returning function directly` |
| `MkDyn[i]` — dynamic-array result | refused, same message |
| `MkR2[i,j].field` — N-D result | parse error: the selector walker's bracket arm reads ONE expression |

## The one move that covers all of them

Do **not** add an arm per element kind. `ApplyCallResultPtrSuffix`'s AnsiString
arm already has the shape: materialise the call result into a hidden temp and
yield `(tmp := call, tmp[i])` via `AN_COMMA`, so the call is evaluated exactly
once and the index has an addressable base.

Here the temp must be **shaped like the array** — `AllocArray` over the result
type's flattened bounds plus the `SymArrNDims`/`SymArrDimLo`/`SymArrDimSpan`
stamp — because then `NodeArrNDInfo` recognises it and `BuildFlatNDIndex` gives
the N-D spelling for free, and the record-element case stops depending on the
routing accident.

It needs one new fact: **`ProcRetArrAi`** — the ArrType index of an array
result. Nothing records it (`ProcRetFixedArrBytes` keeps only a byte count), and
the parser computes it already as `retArrAi`; it just is not stored per-proc.

## The open question — file a `decide-` if it does not settle itself

A **dynamic-array** result is a heap handle with an ownership story, not a value
copied into a temp: the temp must own its reference and release at scope exit,
or the result leaks / is freed twice. If that does not fall out of the existing
managed-local machinery, land the FIXED-array half and refuse the dyn one with
the existing message rather than guessing.

## Gate

All six rows above matching FPC, `test/test_index_call_result_field.pas`
extended with the N-D call row it currently leaves unasserted, plus
`test/test_aggregate_function_results.pas` green and self-host byte-identical.

---

## RESOLVED 2026-08-19 — `frankonpiler-an` (Track A, sole-A confirmed)

`ApplyCallResultPtrSuffix` (`compiler/parser.inc`) grew one arm for an
array-returning call: materialise the result into a hidden temp and yield
`(tmp := call, tmp[i])` through `AN_COMMA`, the same move the `tyAnsiString`
arm next door already made. `AN_INDEX` needs an ADDRESSABLE base; the comma
also buys single evaluation by construction (the test asserts a call counter).

Measured against FPC compiling the same file — `test/test_index_a_call_result_directly.pas`,
whose `.expected` is FPC's own output, wired into `test-core`:

| row | before | after |
| --- | --- | --- |
| `MkS[2]` string result | worked | works |
| `MkArr[1]` scalar element | refused | **20** = FPC |
| `MkArr2[1,2]` N-D | parse error | **12** = FPC |
| `MkArr2[1][2]` bracket spelling | parse error | **12** = FPC |
| `MkStr[1]`, `array[0..2] of string[8]` | parse error | **`mid`** = FPC |
| `MkR[1].a` array of record | worked | works |
| `MkR2[1,1].a` N-D of record | parse error | **11** = FPC |
| `MkR2[1][1].a` | parse error | **11** = FPC |
| single evaluation (call counter) | — | **10** = FPC |
| `MkDyn[1]` dynamic | refused | still refused, same message |

Dynamic-array results stay refused deliberately: a dyn result is a heap handle
with an ownership story, not a value copied into a temp, so the temp would have
to own its reference and release at scope exit. Refusing beats guessing at a
lifetime — and the refusal is a clear sentence, not `unexpected token`.

### Three things worth keeping

**A byte count can size a temp but cannot SHAPE one.** The obvious material was
`ProcRetFixedArrBytes`, and it is not enough: it gets you a slot of the right
length with no bounds, no element type, and no dim spans. The fix needed a new
`ProcRetArrAi` (the ArrType index) so the temp could be built with `AllocArray`
over the type's real bounds plus the `SymArrNDims`/`SymArrDimLo`/`SymArrDimSpan`
stamp — i.e. shaped exactly like the callee's own Result slot. That is what made
`NodeArrNDInfo` recognise it, so the N-D spellings came free instead of needing
arms of their own. Initialised to **-1, not 0**, because zero is a VALID ArrType
index.

**A frozen-string element printed `3` where FPC printed `mid`** — a SILENT wrong
value, strictly worse than the parse error it replaced, and it would have shipped
if the row had been checked for "compiles" rather than diffed. Two causes, and the
first one masked the second: the element type was read from `Procs[].RetType`
instead of from the ArrType entry (which is the authority on the element's WIDTH),
and the index node was tagged with `Ord(tk)` where the normal index path at
`parser.inc:5863` uses `StrValTk(tk)`. A frozen string's STORAGE kind is
`tyFixedString` and its VALUE kind is `tyString`; every `= tyString` check
downstream keys on the latter, so the storage kind reached `WriteLn` as something
that printed the length word.

**The record spelling had no arm of its own and should never have had one.**
`Procs[].RetType` carries the ELEMENT kind, so an `array of record` result read as
`tyRecord` and fell into the class/record selector arm by accident. It happened to
work 1-D, and could not work N-D, because that arm consumes a single subscript —
which is exactly why `MkR2[i,j].a` was `unexpected token`. What decides the arm is
whether the RESULT is an array, not what its elements happen to be. So the record
arm now yields the `[` spelling to the array arm, and the array arm hands the tail
back to `ParseClassRecordSelectors` after the index — on the `AN_INDEX` node and
not on the `AN_COMMA`, because a field selector needs an addressable base and
`tmp[i]` is one while the comma's yielded value is not. Net: one path, two rows
fixed, and a case deleted rather than added (`normalise-dont-special-case`).

Gate: `make compiler/pascal26` fixedpoint + `tools/gate.sh quick`.

## Log
- 2026-08-19 — resolved, commit 1df7a1926.
