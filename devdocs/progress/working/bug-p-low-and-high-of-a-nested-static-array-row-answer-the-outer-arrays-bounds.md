---
track: P
prio: 40
type: bug
blocked-by: []
summary: "`var m: array[5..9] of array[2..3] of LongInt` — `Low(m[5])` answers 5 and `High(m[5])` answers -1 where fpc 3.2.2 says 2 and 3. Low's two whole-array arms ask about the SYMBOL rather than the operand, so they fire on `Low(m[i])` exactly as on `Low(m)`; High's equivalents each carry an `(ASTKind[valNode] = AN_IDENT) and (ASTIVal[valNode] = idx)` guard and Low's do not. ADDING THE MISSING GUARD MAKES IT WRONG DIFFERENTLY, NOT RIGHT: pxx FLATTENS nested static dimensions, so `m[5]` is not a row value in this compiler's model at all and the guarded Low would fall to the `else 0` tail. That sentence is the whole content of this row and a microfix destroys it."
status: working
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
