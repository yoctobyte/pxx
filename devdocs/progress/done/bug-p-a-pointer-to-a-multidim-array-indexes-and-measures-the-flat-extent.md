---
slug: bug-p-a-pointer-to-a-multidim-array-indexes-and-measures-the-flat-extent
title: "`qg^[i, j]` over a pointer to a 2-D array indexes with the wrong dims, and `Length(qg^)` answers the flattened count"
track: P
prio: 60
type: bug
blocked-by: []
status: done
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

## Log
- 2026-08-26 — resolved, commit 46e8e1c65.

# Resolved 2026-08-26

Both halves were reads that nothing performed, exactly as filed — plus one
interaction the ticket did not foresee.

**Indexing.** `NodeArrNDInfo` grew an `AN_DEREF` arm reading `SymPtrElemNDims`
and the `SymArrDimLo/Span` rows off the POINTER symbol (a pointer symbol has
`SymArrNDims = 0`, so those slots are free — the C frontend's `elem (*p)[A][B]`
has stored them there all along). Both syntaxes now flatten correctly: comma
`qg^[i, j]` and bracket-chain `qg^[i][j]`.

**Measuring.** `DerefPtrArrayInfo` reports TWO counts instead of one, because
its callers want different ones and a multi-dim pointee is where they stop
coinciding: `elemCount` = the first dimension's span (Length/High/Low),
`flatCount` = the product over every dim (SizeOf). For a 1-D pointee they are
equal, which is why one number served until now. This is the same split the
plain-VARIABLE arms beside each caller already make.

**The interaction, which is the part worth remembering.** The `p^[i]` arm in
`ParseLValueAST` normalises a non-zero low bound by subtracting `dpaLo` from
the built subscript. `BuildFlatNDIndex` *already* subtracts every dimension's
low bound, dim 0 included — so once the ND path started firing for a deref,
that arm double-counted it and indexed `(i - 2*lo0)`. Correct only for the
`lo = 0` case that hid it, which is exactly the case the original repro used.
Guarded with `not isND`.

## Verified against fpc 3.2.2, byte-identical

`test/test_pointer_to_a_named_fixed_array.pas` now carries the two rows its
header promised, plus a non-zero-low-bound 2-D case that is what separates a
correct flatten from a double-subtracting one. `.expected` is regenerated from
FPC's own output on that source. Also checked outside the suite: 3-D, record
elements with a trailing field selector, and the 1-D regression path (where the
`dpaLo` subtraction still applies and must).

## Not affected, checked rather than assumed

The C frontend calls `NodeArrNDInfo` too, but its entry is
`(ASTKind[node] = AN_IDENT) and NodeArrNDInfo(node)` — short-circuit, so an
`AN_DEREF` never reaches the new arm, and the inner `internal: multi-dim ND info
lost` re-queries pass the same AN_IDENT node. NilPy has no `^` syntax and never
calls `DerefPtrArrayInfo`.

## Still open, deliberately

A pointer to a named DYNAMIC array — `Length(pdy^)` answers 1 where fpc says 5.
Different mechanism (the pointee is a HANDLE, so there is no compile-time
extent to fold): [[bug-p-length-of-a-pointer-to-a-dynamic-array-answers-one]].
