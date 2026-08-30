---
track: P
prio: 25
type: refactor
blocked-by: []
summary: "NodeArrNDInfo returns False for a rank-1 array — every arm tests `>= 2`. Correct for its original caller (multi-subscript lowering, where rank 1 has no comma chain), but it makes the function unusable as the general 'what shape is this array' reader that three frontends now want. Not a Pascal defect: no Pascal program behaves wrong today."
status: backlog
owner: unassigned
---

# NodeArrNDInfo answers nothing for a rank-1 array

- **Type:** refactor / capability gap — **NOT a bug.** No Pascal program
  observes it: the multi-subscript path it serves has nothing to do for rank 1.
- **Found:** 2026-08-30 (frankC), building `CNodeArrayShape` for
  [[refactor-c-one-array-shape-reader-instead-of-four-ident-field-pairs]].

All three arms gate on rank >= 2 (`SymPtrElemNDims[sym] >= 2`,
`SymArrNDims[...] >= 2`, `UFldArrNDims[fIdx] >= 2`), so `int a[8]` /
`array[0..7] of Integer` answers False and fills no NDInfo.

**Why it matters to someone.** Track C's `CNodeArrayShape` wraps this function
as its one array-shape reader, and inherits the restriction: every caller that
wants rank 1 too must keep its own AN_IDENT/AN_FIELD pair beside the call,
which is the exact duplication that ticket exists to delete.
`CNodeDecaysToPointer` is the live example — it is *already correct* for both
spellings and handles rank 1, so routing it through `CNodeArrayShape` would be
a regression, and it stays hand-rolled.

**Why it is filed and not fixed.** `pasparser_call.inc` is Track P's file and
is held by the wasm/N lane. Also see
[[refactor-a-nodearrndinfo-is-a-symtab-query-living-in-a-pascal-parser-file]] —
if that lands, this ticket moves to A with the function.

## Fix sketch

Drop the `>= 2` tests to `>= 1` and let callers that need multi-dim say so
(`NDInfoNDims > 1`), rather than the reader deciding for them. Every current
caller already tests `nIdx` against `NDInfoNDims`, so raising rank-1 arrays
into the path should be inert for them — but that is the claim to *verify*,
not assume: `pasparser_lval.inc` errors on `nIdx <> NDInfoNDims`.

## Gate

`make compiler/pascal26` + the Pascal suite's array coverage. Track T sweeps
the matrix.
