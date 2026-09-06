---
track: P
prio: 50
type: bug
blocked-by: []
status: done
owner: "frankB"
created: 2026-09-06
summary: "`Take(p^)` where `p: ^array[3..7] of LongInt` and Take takes `const array of LongInt` SEGFAULTS -- a dead process, not a wrong value. StaticArraySourceInfo (ir.inc), the ONE resolver both the by-value/const arm and the var/out arm ask what static array is behind an argument, knew four shapes -- plain identifier, record field, partial N-D row, slice -- and not the deref, so `p^` fell past all four to the scalar tail and the callee received the pointer's own bytes where the array's address belonged. THE NEIGHBOUR THAT WORKED IS WHY NOBODY HIT IT: `p2^[1]`, a ROW of a 2-D pointee, reaches the AN_INDEX arm and was always right, so the deref spelling worked for a subscript OF the pointee and not for the pointee ITSELF, and every existing probe for pointer-to-array arguments used the subscripted form. fpc 3.2.2 prints the elements in every mode. Found while probing the rank-1 widening of DerefPtrArrayShape and confirmed PRE-EXISTING at HEAD by reverting the whole change set and rebuilding."
---

# A pointer to a fixed array segfaults as a copying open-array argument

- **Type:** bug — **Track P** (`compiler/ir.inc`, `StaticArraySourceInfo`).
- Group 28, THE ARRAY'S SHAPE AND WHO IS ALLOWED TO ASK ABOUT IT.

## Repro

```pascal
type TA1 = array[3..7] of LongInt; PA1 = ^TA1;
var a1: TA1; p1: PA1; i: LongInt;
procedure Take(const x: array of LongInt);
var k: LongInt;
begin Write('[', Length(x), ']');
  for k := 0 to High(x) do Write(' ', x[k]); WriteLn; end;
begin
  for i := 3 to 7 do a1[i] := i * 2;
  p1 := @a1;
  Take(a1);   { both: [5] 6 8 10 12 14 }
  Take(p1^);  { fpc: [5] 6 8 10 12 14   pxx: prints `[` then SIGSEGV }
end.
```

Same in every copying mode — `const`, by value, and `var` (where the copy-back
never happens either).

## Cause

`StaticArraySourceInfo` is *"the ONE resolver, called from both the
by-value/`const` arm and the `var`/`out` arm"* — its own comment says it was
two near-identical copies that had already drifted, and that *"a third shape
would have had to be written into both, and the one that got it second is the
one that stays broken."* It has arms for `AN_IDENT`, `AN_FIELD`, `AN_INDEX`
(the partial N-D row) and `AN_SLICE`. **`AN_DEREF` is the fifth shape and was
never written.**

## Fix

An `AN_DEREF` arm asking **`DerefPtrArrayShape`**, not a fifth private switch
over the two deref spellings (the pointer SYMBOL and the pointee's ArrType
row). That reader answered only for rank >= 2 until
[[refactor-p-nodearrndinfo-answers-nothing-for-a-rank-1-array]] widened it, and
this arm is its **first caller** — the capability ticket and this bug close
together, which is what made the widening worth doing rather than filing.

`NDInfoNDims <> 1` refuses a multi-dim pointee here, mirroring the ident arm's
`SymArrNDims <= 1`: an open array is one dimension. The frozen-string capacity
comes from `DerefPtrArrayElem`, which is honest about serving only the deref
spelling; it is deliberately not an NDInfo column, because two of that reader's
four arms have no element-capacity column to fill.

## Gate

`test/test_a_pointer_to_a_fixed_array_is_a_copying_open_array_argument.pas` —
7 rows, `test-core`, byte-identical to fpc 3.2.2: const, by value, and `var`
with the assertion on the ORIGINAL (a read-only row would pass with the
copy-back broken); a record element, where the stride is visible; the non-zero
low bound, which must not leak into the count; the plain-variable control; and
row 6, the 2-D-row neighbour that always worked, kept as the boundary.

The positive control is the crash itself: measured at HEAD with the whole
change set reverted and the compiler rebuilt, the repro dies with SIGSEGV.

## Residual, not fixed here

**A SLICE of a deref is refused.** `Take(p1^[4..6])` answers `no overload of
Take matches these arguments` under pxx and prints `[3] 8 10 12` under fpc.
That refusal happens at overload matching, before this resolver is reached, so
it is a different door — and the `AN_SLICE` arm recurses into this function, so
the slice would work the moment the argument is accepted. Compat, not a wrong
value.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit ce5a257d9.
