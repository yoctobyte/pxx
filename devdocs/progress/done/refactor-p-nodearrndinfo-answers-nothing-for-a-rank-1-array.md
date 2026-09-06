---
track: P
prio: 25
type: refactor
blocked-by: []
summary: "NodeArrNDInfo returns False for a rank-1 array — every arm tests `>= 2`. Correct for its original caller (multi-subscript lowering, where rank 1 has no comma chain), but it makes the function unusable as the general 'what shape is this array' reader that three frontends now want. Not a Pascal defect: no Pascal program behaves wrong today."
status: done
owner: frankB
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

## Premise holds verbatim at HEAD (frankS, 2026-09-05, Track P structural pass)

`NodeArrNDInfo` is `compiler/pasparser_call.inc:619`. Both arms still gate on
rank 2:

- the `AN_IDENT` arm — `(ASTIVal[node] >= 0) and (SymArrNDims[ASTIVal[node]] >= 2)`
- the `AN_FIELD` arm — `(fIdx >= 0) and (UFldArrNDims[fIdx] >= 2)`

`Result := False` is the initialiser, so a rank-1 array falls through both and
the function answers False. Not stale.

**No behavioural probe can settle this ticket and none should be attempted** —
the summary says so itself (*"no Pascal program behaves wrong today"*), and a
staleness pass that reaches for a repro here will find nothing and must not read
that as a close. Structural claims are checked structurally; the check is a grep
for the two `>= 2` guards, and it takes ten seconds.

## Resolution (2026-09-06)

**THE FIX SKETCH WAS A NO-OP AND THAT IS THE FINDING.** It said to *"drop the
`>= 2` tests to `>= 1`"*. `SymArrNDims` and `UFldArrNDims` are **0** for a
rank-1 array, not 1 — read off every writer:

- `ParseVarDecl` sets `VDIsArrND` only when `VDNdCnt <> 1`; the rank-1 branch
  writes `VDArrLo`/`VDArrHi` instead and `SymArrNDims` is left at the 0
  `AllocArray` stamps.
- The field side writes `UFldArrNDims` only `if fNDims >= 2`. `RecFieldArrLo`'s
  own comment says so in as many words: *"UFldArrNDims stays 0/1 so nothing
  that dispatches on the N-D shape changes."*

So `>= 1` is False on exactly the arrays the change was meant to admit, and the
whole edit does nothing. A structural claim, settled structurally, which is what
this ticket's own staleness note says is the right method for it. (One
cross-check that fails differently: `RecFieldArrNDims`'s doc comment claims *"1
for a 1-D array"*, and its writer disagrees — the C frontend's
`UFldArrNDims[...] := bfNDims[k]` is unconditional, so the column means 1 from C
and 0 from Pascal. That disagreement is not resolved here; it is a fresh
instance of this group's own subject and is noted, not chased.)

### What landed instead

`NodeArrShape` — **any rank, one included** — with dim 0 **synthesised** in each
arm from the columns that actually hold it:

| arm | rank-1 low bound | rank-1 span |
| --- | --- | --- |
| ident | `Syms[].ConstVal` | `Syms[].ArrLen` |
| record field | `UFldArrDimLo[fi*MAX]` | `UFldArrLen[fi]` |
| deref, pointer symbol | `SymArrDimLo[sym*MAX]` | `SymPtrElemArrLen[sym]` |
| deref, ArrType row | `ArrTypeLo[ai]` | `ArrTypeHi - ArrTypeLo + 1` |

`NodeArrNDInfo` is now **that function plus a `>= 2` refusal**, and
`DerefPtrArrayNDInfo` likewise over `DerefPtrArrayShape` — so the four-spelling
switch is written ONCE and the two contracts are named after what each answers.
No existing caller changed, which matters: one of them
(`cparser.inc`) carries a correctness comment citing the `>= 2` restriction by
name, and `ir.inc`'s `FixedArrayAsArrayCtor` re-primes the globals per element
and would break silently rather than loudly (frankS).

**THE RANK-1 ADMISSION IS AN `or` BESIDE THE ND CONDITION, NEVER AN EXTRA
`and` OVER IT.** The first draft rewrote the ident guard as
`IsArray and DynDepth = 0 and ArrLen > 0`, which would have been a **narrowing
wearing a widening's commit message** — a multi-dim symbol failing any of those
three would have silently left the ND path. The ND disjunct is byte-identical
to what it was.

**The refusal clears `NDInfoNDims`.** A rank-1 shape left in the globals under a
False return is a *plausible* answer sitting where a stale one used to sit, and
this family's failure mode is always a plausible wrong stride rather than a
crash.

### It has a real caller, and it closed a segfault

The widening was not landed as a capability nobody uses.
`DerefPtrArrayInfo`'s own two-spelling switch is **deleted** — it now reads the
shape (`flatCount` as the product of the spans, measured against both the old
sources rather than assumed) — and, more to the point,
[[bug-p-a-pointer-to-a-fixed-array-segfaults-as-a-copying-open-array-argument]]
is fixed by an `AN_DEREF` arm in `ir.inc`'s `StaticArraySourceInfo` that asks
`DerefPtrArrayShape`. `Take(p^)` on `^array[3..7] of LongInt` given to a
`const array of LongInt` used to SIGSEGV; a fifth private switch over the two
deref spellings is what the arm would have had to be without this ticket.

Track C's `CNodeArrayShape` and `CNodeDecaysToPointer` are the other named
beneficiaries and are **not** touched — `cparser.inc` belongs to whoever holds
[[refactor-c-one-array-shape-reader-instead-of-four-ident-field-pairs]]. The
capability they were waiting on exists now.

### Gate

`test/test_a_pointer_to_a_fixed_array_is_a_copying_open_array_argument.pas`
(7 rows) and
`test/test_a_partial_nd_row_reaches_a_copying_parameter_through_every_base_spelling.pas`
(8 rows), both `test-core` and byte-identical to fpc 3.2.2, plus every existing
array row unchanged — which is the claim that mattered, since the ND contract's
callers must not be able to tell this happened.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
