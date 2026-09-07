---
track: A
prio: 45
type: bug
status: done
owner: ""
created: 2026-09-07
found-by: frankA
tags: [records, equality, cross-target, silent-wrong, arrays]
blocked-by: []
summary: "FIXED 2026-09-07. `a = b` on a record with an ARRAY member compared one machine word, because the field-wise expansion refused array members. Array members are now UNROLLED, one comparison per element, sized the way ABISysVWalkRec already sizes them -- `UFldArrLen` is the FLAT element count, read off the code that writes it, so a 2-D `array[0..2, 0..3]` compares all 12 cells and not the first 3. Measured correct on x86-64, i386, aarch64, arm32 and riscv32 for a 1-D int array, a 2-D array, an array of records, an array of AnsiString (content, not handle) and an array of Char; the pre-fix binary answered a wrong TRUE on four targets for a differing LAST element and, unpredicted by this ticket, on arm32/riscv32 for a differing FIRST element too. The code-size sweep found NO KNEE -- 55 bytes per leaf, flat from 100 to 1280 leaves -- so REC_CMP_UNROLL_MAX = 64 is a BUDGET (~3.5KB per comparison site), not a measured boundary, and above it the compiler now WARNS with the record's leaf count rather than falling back silently: the fallback is still wrong, and a silent cliff in correctness is worse than either answer. RESIDUAL: raising the cap is not the fix -- an array of a scalar has no interior padding, so the right shape is a byte-compare over any contiguous padding-free run, which needs a PXXMemCmp that does not exist yet."
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

## Fixed 2026-09-07 — array members are unrolled, and the cap announces itself

`RecFieldCmpElemSize` / `RecFieldCmpCount` size an array member the way
`ABISysVWalkRec` (abi.inc) already sizes one for the ABI, rather than deriving a
second answer for the same tables. `IRRecFieldwiseEqChain` unrolls one
comparison per element at those offsets, recursing for a record element.

**`UFldArrLen` is the FLAT element count**, read off the code that writes it
(`pasparser_decl.inc` multiplies `arrLen` by each `tdDimSpan`), not inferred
from a size that happened to match. A first-dimension-only count would have
compared 3 of a 2-D array's 12 elements and answered a wrong TRUE — the same
defect one level down — so the fixture's `2d last` row varies the LAST cell.

`IRRecordIsFieldwiseComparable` became `RecordFieldwiseCmpLeaves`, returning the
leaf COUNT instead of a Boolean: the caller needs both answers and a count from
a second walk is a second chance to disagree with the first.

### Measured on five targets

The acceptance row and more. Before: `lastelem` answered T on x86-64, aarch64,
arm32, riscv32 and F-for-everything on i386 — and **`firstel` (the FIRST element
differing) also answered T on arm32 and riscv32**, which this ticket did not
predict: the compared word is `n` plus padding, so on a 32-bit target the array
is entirely outside it. After: 20 of 20 cells correct on all five.

Also correct on all five: a 2-D `array[0..2, 0..3]` (12 cells, discriminated at
the last), an `array[0..2]` of two-field records, an `array[0..2] of AnsiString`
(content, not handle), and `array[0..7] of Char`.

`arr[Idx(0)] = arr[Idx(1)]` still calls `Idx` **twice**, not once per element,
with 9 leaves per operand. 200000 comparisons of a record holding an
`array[0..2] of AnsiString` return the right answer every time and both strings
read back intact under `-dPXX_HEAP_DEBUG`, so a borrowed element is neither
released nor retained.

### The cap is a BUDGET, and it says so out loud

The sweep the ticket asked for found **no knee**: 55 bytes of emitted code per
leaf, flat from 100 leaves to 1280 (x86-64, default `-O`, 20 comparison sites
per build to clear the 4096-byte quantum `code=` reports in). Linear with no
point where it stops costing, so no element count is the "right" one.
`REC_CMP_UNROLL_MAX = 64` is ~3.5KB per comparison site and covers the shapes
that occur, without letting one `=` on `array[0..65535] of Byte` emit 3.6MB.

*The first version of that sweep read `.text` out of `--emit-obj` objects and
reported 64 bytes at every element count — the exported symbol was the only
thing emitted, so the number could not move. The rows above are from
executables, where it does.*

**Above the cap the compiler now WARNS**, naming the record's leaf count and the
cap. That is the part that matters: above the cap `a = b` is still wrong, and
nothing in the source says which side of the line a record is on — adding one
element to an unrelated member moves it. A silent cliff in CORRECTNESS is worse
than either answer. Not an error: those programs compile today and some are
accidentally right, and breaking them to protect the others is the trade this
repo's guidance refuses.

### Residual — and raising the cap is NOT the fix

An array of a scalar has **no interior padding**, which is exactly what makes a
byte-wise compare unsafe for a whole record and safe over that run. The right
shape for large arrays is a byte-compare over any contiguous padding-free run —
O(1) code, no cap — and it needs a `PXXMemCmp` that does not exist
(`builtinheap.pas` has `PXXMemMove`, `PXXMemZero` and `PXXMemCopy` only).
Still refused, unchanged: dynamic-array members (a handle, not inline storage),
bit-fields, `tySet` / `tyVariant` / frozen-string / `tyExtended` members, and
any record whose fields overlap.

### Gate

`test-record-equality-cross-target` gains ten array rows and a two-armed
assertion on the warning: it must fire for `test/record_equality_over_unroll_cap.pas`
(101 leaves) and must be silent for the under-cap fixture. Both arms
positive-controlled by pointing them at the wrong log and confirming RED.

## Log
- 2026-09-07 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 0089e04f9.
