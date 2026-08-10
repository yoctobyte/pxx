---
track: A
prio: 40
type: feature
blocked-by: []
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
