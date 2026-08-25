---
slug: bug-p-a-pointer-to-a-multidim-array-indexes-and-measures-the-flat-extent
title: "`qg^[i, j]` over a pointer to a 2-D array indexes with the wrong dims, and `Length(qg^)` answers the flattened count"
track: P
prio: 60
type: bug
blocked-by: []
status: backlog_new
owner: ""
created: 2026-08-25
summary: "`PG = ^TG` with `TG = array[0..1, 0..2] of LongWord`: `qg^[i, j]` prints `0 1 2 1 2 10` where FPC prints `0 1 2 10 11 12` — the comma subscript is not flattened against the pointee's dims — and `Length(qg^)` answers 6 (the flat extent) where FPC answers 2 (the first dimension). Predates and is not caused by the single-dim fix; the metadata it needs is now present."
---

# Measured, 2026-08-25 (HEAD, and identically on the pre-fix binary)

```pascal
type TG = array[0..1, 0..2] of LongWord; PG = ^TG;
var g: TG; qg: PG; i, j: Integer;
begin
  for i := 0 to 1 do for j := 0 to 2 do g[i, j] := i * 10 + j;
  qg := @g;
  for i := 0 to 1 do for j := 0 to 2 do Write(' ', qg^[i, j]);
end.
```

| | output | `Length(qg^)` |
| --- | --- | --- |
| fpc 3.2.2 | `0 1 2 10 11 12` | 2 |
| pxx | `0 1 2 1 2 10` | 6 |

`SizeOf(qg^)` is already right (24).

# Why it is now cheap

`bug-p-length-of-a-dereferenced-pointer-to-array-answers-zero` put the pointee's
shape on the pointer symbol: `SymPtrElemNDims[p]` is the dim count and
`SymArrDimLo/Span[p*MAX_ARR_DIMS + d]` the per-dim bounds — the same rows a real
array symbol uses, in a pointer symbol's otherwise-unused slots, exactly as
the C frontend's `elem (*p)[A][B]` already did. So both halves are reads that
nothing performs yet:

- `NodeArrNDInfo` answers False for an `AN_DEREF` base, so the comma-sugar chain
  in `ParseLValueAST` never builds the flattened index. Teaching it to accept a
  deref whose `DerefPtrArrayInfo` says N-D is the whole indexing fix.
- `DerefPtrArrayInfo` reports the FLAT extent. Length/High of a whole multi-dim
  array must answer the first dimension (the plain-variable arms right beside
  them already do exactly this, off `SymArrDimSpan[sym*MAX+0]`).

# Gate

`make compiler/pascal26` + the repro above diffed against fpc + `tools/gate.sh
quick`. Add the two rows back to
`test/test_pointer_to_a_named_fixed_array.pas`, whose header names this ticket
where they were removed.
