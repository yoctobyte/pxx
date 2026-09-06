---
track: P
prio: 40
type: bug
blocked-by: []
summary: "`var m: array[5..9] of array[2..3] of LongInt` — `Low(m[5])` answers 5 and `High(m[5])` answers -1 where fpc 3.2.2 says 2 and 3. Low's two whole-array arms ask about the SYMBOL rather than the operand, so they fire on `Low(m[i])` exactly as on `Low(m)`; High's equivalents each carry an `(ASTKind[valNode] = AN_IDENT) and (ASTIVal[valNode] = idx)` guard and Low's do not. ADDING THE MISSING GUARD MAKES IT WRONG DIFFERENTLY, NOT RIGHT: pxx FLATTENS nested static dimensions, so `m[5]` is not a row value in this compiler's model at all and the guarded Low would fall to the `else 0` tail. That sentence is the whole content of this row and a microfix destroys it."
status: done
owner: frankB
---

# Low/High of a nested static array's row answer the outer array's bounds

- **Found:** 2026-09-06 (frankS), while fixing the same three intrinsics for a
  DYNAMIC array of fixed rows ([[feature-pascal-corpus-fpc-testsuite]],
  `0f7da3f4f`). That fix is landed and this is the sibling it does not cover.
- **Measured at compiler `1619c9df16f4`** against fpc 3.2.2.

```pascal
var m: array[5..9] of array[2..3] of LongInt;
begin
  writeln('Low(m)=', Low(m), ' High(m)=', High(m));        { pxx 5 9   fpc 5 9  }
  writeln('Low(m[5])=', Low(m[5]), ' High(m[5])=', High(m[5]));
end.                                                        { pxx 5 -1  fpc 2 3  }
```

## Why the obvious fix is wrong

`ParseFactor`'s Low chain opens with two arms testing `Syms[idx].IsArray`, where
`idx` is the symbol the operand STARTS at. They do not ask whether the operand
IS that identifier, so `Low(m[5])` takes the whole-array arm and answers the
outer lower bound. The High chain's matching arms each carry
`(ASTKind[valNode] = AN_IDENT) and (ASTIVal[valNode] = idx)`; Low's do not, and
that asymmetry is real.

**It is not the cause, though, and copying High's guard across only changes
which wrong answer comes out.** pxx FLATTENS nested static dimensions — the
declaration parser merges an anonymous nested `array[..]` element into the outer
dimension list (`VDIsArrND`, `VDNdDimLo/Span`), because `array[a] of array[b] of
T` has the same layout as `array[a,b] of T`. So there is no symbol, no type and
no node in this compiler that represents "one row of m". A guarded Low would
fall through to the `else 0` tail and answer 0 against fpc's 2. `High(m[5])`
already reaches its Length-1 tail and answers -1 for the same reason.

So the row is: **decide what `Low`/`High` of a subscript into a flattened static
array should answer, and give the answer a place to come from.** The dimension
spans are on the symbol (`SymArrDimLo`, `SymArrDimSpan`) and the subscript depth
is knowable at the intrinsic, so the information exists; nothing currently reads
it in that combination.

## What is already done and must not be redone

The DYNAMIC-array-of-fixed-rows case is fixed and tested
(`NodeFixedRowInfo` in `symtab.inc`, used by Length/Low/High;
`test_a_dynamic_array_of_fixed_rows_has_row_bounds`). There the row's extent is
on the base symbol as `SymDynElemRowLen`/`SymDynElemRowLo` and the element is a
real run of bytes with a stride, so the three intrinsics have something to read.
**A nested static array has no equivalent field because it has no equivalent
concept** — that is the difference between the two halves.

## If the flattening itself is the question

Then this is the wrong ticket and it wants a `decide-` in Track U. The flattening
is deliberate, documented at its two sites, and load-bearing for N-D indexing;
this row assumes it stays and asks only what the bounds intrinsics report over
it.

## Resolution (2026-09-06)

**The ticket's central sentence held and it is what shaped the fix.** *"Adding
the missing guard makes it wrong differently, not right"* — copying High's
`(ASTKind[valNode] = AN_IDENT) and (ASTIVal[valNode] = idx)` onto Low's two
arms sends `Low(m[5])` to the `else 0` tail, 0 against fpc's 2. So the guard
was never added and the two arms below are untouched: the new arm is asked
BEFORE them, and nothing reaches them with a subscripted operand any more.

**The answer had a place to come from after all, and both halves were already
recorded.** `ASTNDRowSubs[node]` holds k, the number of subscripts spelled —
`BuildPartialNDIndex` stamps it with the index arithmetic, one routine for
both, because they are one fact stated twice. `NodeArrNDInfo` holds the base's
dimension rows. They had never been asked TOGETHER. `NDRowDimBounds`
(`pasparser_call.inc`, beside `NDRowSourceInfo`) asks them and returns dim k's
Lo and Span; three arms read it, one each in the High, Low and Length chains.

`Length` was the third intrinsic with the same defect and is not in the
ticket's title: `Length(m[5])` answered 0.

### The part worth carrying out of this ticket

**`NDRowSourceInfo`, one function above the new reader and over the same data,
answers a DIFFERENT question — and both callers are right.** It returns the
flat product over the dimensions still unconsumed, which is exactly what a
const-array parameter needs and exactly what `Length` must not be told:
`Length(m[5])` on `array[5..9, 2..3, 7..10] of LongInt` is 2, not 8. **On a 2-D
array the two numbers are equal**, so a reader that answered the other question
would have been right on every array anyone had probed and wrong from three
dimensions on. That is why the new reader is a SIBLING rather than a widening,
and why rows 7..9 of the fixture are a 3-D array.

frankS's framing, which is sharper than "a partially consulted record": *one
function answering two questions with one name is the more expensive shape,
because the partially-consulted one is found by asking whether the column is
consulted where the cases are distinguished, and this one is only found by
noticing that two correct callers want different numbers.*

### Gate

`test/test_low_high_and_length_of_a_partial_subscript_answer_the_remaining_dimension.pas`
— 20 rows, `test-core`, byte-identical to fpc 3.2.2. With the arm reverted and
the compiler rebuilt, TWELVE of the first sixteen fail. The four survivors are
the three whole-array controls and `Low(z[0])` on a zero-based array, whose
right answer collides with the broken path's 0; that row is kept and labelled
as the one row here that cannot fail, with `Length(z[0]) = 2` beside it doing
the discriminating.

Rows 17..19b are a cross-track control frankS asked for: `BuildForInArrayLoop`
(`1f66c4eb4`, landed the same hour) stamps `ASTNDRowSubs := 1` on the element
access a for-in loop reads each row through, so it is the one node carrying
that column which `BuildPartialNDIndex` did not build. **A reader keyed on a
column gains every writer of that column, including the ones added after it.**
Measured on the merged tree: the three intrinsics answer the row's own bounds
inside the loop and the loop still yields whole rows.

### Not done here

`NodeArrNDInfo`'s own two gaps —
[[refactor-p-nodearrndinfo-answers-nothing-for-a-rank-1-array]] and
[[refactor-p-nodearrndinfo-yields-spans-but-not-the-element]] — are the rest of
Group 28 and are untouched. `FixedArrayAsArrayCtor` in `ir.inc` is a caller of
`NodeArrNDInfo` that re-primes it per element rather than once before the loop
(frankS), and depends on `NDInfoNDims`, `NDInfoLo[0]` and `NDInfoSpan[0]` plus
`BuildPartialNDRowIndex` setting both the arithmetic and the stamp. **Whoever
changes who owns that global state should know it will break silently rather
than loudly there**, because a stale `NDInfoSpan` produces a plausible wrong
row index. This fix adds a reader and moves no state, so it does not touch it.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
