---
slug: bug-p-an-inline-pointer-alias-cast-loses-the-pointees-low-bound
title: "`PLo(@lo)^[3]` reads element 0 and `PLo(@lo)^[2] := 55` writes element 4: two of the three sites that mint an AN_INDEX over a deref never subtract the low bound"
track: P
prio: 50
type: bug
status: done
found: 2026-09-04
found-by: frankA
owner: frankA
blocked-by: []
commit: PENDING-COMMIT
summary: "FIXED. An AN_INDEX whose base is an AN_DEREF carries an ALREADY-NORMALISED subscript by convention -- the parser subtracts the pointee array's low bound, because ir.inc's `lo` ladder has no AN_DEREF arm and so cannot do it. THREE sites mint that node and only ONE did the subtraction: for `type TLo = array[1..5] of Integer; PLo = ^TLo`, the inline-cast READ `PLo(@lo)^[3]` gave 0 against fpc 3.2.2's 99, and the STORE `PLo(@lo)^[2] := 55` wrote into `lo[4]`. Silent both ways, no diagnostic, present in pin v403. Fixed by factoring the arithmetic into `FoldDerefArrayLowBound` (pasparser_lval.inc) and calling it from all three. Regression row: test/test_inline_ptr_cast_low_bound.pas, whose `.expected` is fpc's own output."
---

# The convention, which was the part nobody had written down

`ir.inc`'s low-bound ladder resolves an array's `lo` from the BASE node, and it
has arms for a symbol, an alias and a field — but none for `AN_DEREF`. So for
`p^[i]` the subtraction cannot happen in the IR at all, and the parser has to
hand it a subscript that is already zero-based.

That makes the normalisation a **precondition of the node shape**, not an
optimisation, and every site that mints `AN_INDEX` over a deref owes it. It was
enforced by one site doing it and nobody stating why.

## The three minting sites, measured at `f8b9e4394673`

| site | had the fold? |
| --- | --- |
| `pasparser_lval.inc` chain loop (~1848) | yes — the only one |
| `pasparser_expr.inc` pointer-alias cast loop (~7190) | **no** — the READ face |
| `pasparser_lval.inc` `ParseClassRecordSelectors` (~4847) | **no** — the STORE face |

Independently corroborated by `test/ast_slot_writes.expected`: the census keys
on the local variable NAME that writes each slot, and collapsing the three sites
removed exactly ONE name (`dpaLoNode`) and added one (`fdLoNode`). Had either of
the other two ever done the arithmetic, its own name would have disappeared too.

## How the second face was found

The READ was fixed first, from a differential against fpc 3.2.2, and the test
passed. The STORE was still wrong — and would have stayed wrong, because a test
that only reads through the same broken-then-fixed path cannot see it. It
surfaced only after a WRITE row (`wrote`) was added to the test:
`PLo(@lo)^[2] := 55` then printed `lo[4] = 55` while `lo[2]` was untouched.

*A fix verified through one face of a two-faced construct is verified on one
face.* The read and the write are parsed by different walkers here, which is the
whole reason this ticket exists.

## Why the N-D shapes are excluded

`BuildFlatNDIndex` already subtracts every dimension's low bound. Folding again
would index `(i - 2*lo0)`, correct only for `lo=0` — the case that hides it. All
three call sites pass their N-D state to the helper and it declines, which is
what the previously-inline copy did too.

## Gate

`make compiler/pascal26` (converged), `tools/gate.sh quick`, and
`test/test_inline_ptr_cast_low_bound.pas` — positive-controlled against the
pinned compiler, which differs on four rows (`viacast` 0 vs 99, `lastelem` 10 vs
111, `neg` 0 vs 8, `wrote` 88 vs 55).
