---
track: A
prio: 45
type: bug
status: backlog
owner: ""
created: 2026-09-07
found-by: frankA
tags: [records, equality, cross-target, silent-wrong, arrays]
blocked-by: []
summary: "`a = b` on a record with an ARRAY member still compares one machine word, because the 2026-09-07 field-wise expansion refuses array members and falls back to the old path. Measured on the fixed compiler: `record n: Integer; v: array[0..3] of Integer end` with the same `n` and a different `v[3]` answers TRUE on x86-64/aarch64/arm32/riscv32 and FALSE-for-everything on i386 -- the original defect, unchanged, for this shape. The refusal is deliberate and safe (it preserves the old answer rather than inventing a new one) but arrays are the largest remaining population, and a fixed array of scalars is the common one: `record name: array[0..15] of Char` is an ordinary Pascal idiom and Rust's `#[derive(PartialEq)]` over `[T; N]` lands here too. The open questions are an element STRIDE (UFldArrLen plus the element kind, and UFldArrNDims/ArrDimSpan for the multi-dimensional case) and whether to unroll or emit a loop -- unrolling `array[0..1023]` inline is a code-size decision this ticket has to make, not assume."
---

# The refusal, and why it is where it is

`IRRecordIsFieldwiseComparable` in `compiler/ir.inc` exits on
`UFldIsArray[fbase + i]`. Everything else about the expansion already works for
these records: the scalar members compare correctly, the nested-record recursion
is in place, and the overlap test would still refuse a union.

So the change is bounded — one arm in the decide pass and one in the emitter —
and the work is in the two questions the scalar path did not have to answer.

## Element stride

A scalar member's span comes from `TypeStorageSize(kind)`. An array member's
does not: `UFldTk` holds the ELEMENT kind for an array field (its own comment
says so, and `UFldSemId`'s comment says a reader meaning "this field's VALUE is
an enum" must check `not UFldIsArray` first). `UFldArrLen` gives the count for
the one-dimensional case; `UFldArrNDims` / `UFldArrDimLo` / `UFldArrDimSpan`
carry the rest. A frozen-string member has an array-shaped storage that is NOT
this shape and must stay refused.

`RecFieldCmpSpan` currently answers a conservative 0 for an array, which makes
the OVERLAP test refuse the whole record rather than mis-measure it. Whatever
computes the stride has to feed that function too, or a union containing an
array becomes invisible to the overlap test — which is the segfault case.

## Unroll or loop

Unrolling is what the current emitter does for everything, and it is free for
`array[0..3]`. It is not free for `array[0..1023] of Byte`, which would emit
1024 loads, 1024 compares and 1023 `and`s inline, per comparison site.

A loop needs a counter, a label pair and an early exit — none of which the
expansion currently builds — and it changes the shape from "a value tree" to
"statements plus a result", which is a bigger change to the arm than the array
support itself. A stride-scaled `IR_INDEX` plus an unroll CAP, with the record
falling back to the old path above the cap, is the smaller answer and keeps the
"a refusal preserves the old answer" property this family relies on.

**A cap needs its failure point measured, not chosen** — sweep the emitted code
size against the element count and put the cap where it stops being free, rather
than at a round number.

## Acceptance

`record n: Integer; v: array[0..3] of Integer end`, same `n`, `v[3]` differing:
expected FALSE on all five targets. It answers TRUE on four and FALSE on i386
today, which is the same split the parent ticket's row 2 had — so the row is a
real positive control against the current binary and not only against the pin.
