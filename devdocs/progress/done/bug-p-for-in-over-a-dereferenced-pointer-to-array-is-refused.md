---
slug: bug-p-for-in-over-a-dereferenced-pointer-to-array-is-refused
track: P
prio: 35
type: bug
status: done
owner:
blocked-by: []
summary: "`for x in p^ do` where `p: ^array[0..3] of Integer` is refused with \"for-in: not a generator, enum type, or iterable variable\". FPC accepts it and iterates the pointee; `for x in a do` over the same array works here. A clean compile-time REFUSAL, not a wrong value, so it is cheap to hit and cheap to diagnose. Measured identical on the pinned binary and at 3a53468cb267, i.e. NOT a regression from the p^[i] indexing fix that turned it up -- that work taught IsNodeArray this shape, which was necessary and evidently not sufficient: pasparser_stmt.inc's for-in arm gates on something else."
---

# `for x in p^` is refused

## Measured

```pascal
type TA = array[0..3] of Integer; PA = ^TA;
var a: TA; p: PA; x: Integer;
...
p := @a;
for x in a  do Write(x, ' ');   { works:  0 10 20 30 }
for x in p^ do Write(x, ' ');   { pascal26:9: error: for-in: not a generator,
                                  enum type, or iterable variable }
```

FPC prints `0 10 20 30` for both lines.

Pinned binary and `3a53468cb267` give the byte-identical message, so this is a
standing gap rather than fallout from
`bug-a-indexing-through-a-pointer-to-an-array-is-wrong-for-several-element-kinds`.

## The lead, and its limit

That ticket taught `IsNodeArray` to answer TRUE for this shape, and
`pasparser_stmt.inc:1212` does `isArr := IsNodeArray(contNode)` — so the obvious
guess is that the predicate is now right and some other test in the same arm
still refuses. **That guess has not been run.** The one thing actually measured
is that the message did not change when `IsNodeArray` did, which narrows it to
"not the `isArr` line alone" and no further.

`DerefPtrArraySym` / `DerefPtrArrayInfo` (`symtab.inc`) answer the shape, the
extent and the low bound for this exact spelling, so whatever the arm needs is
almost certainly already available to it.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 06a2d7aa7.

---

## 2026-09-04 (frankA) — FIXED in `d9604ea59` for a zero low bound; the rest is filed, not shipped

**The lead was right about the predicate and wrong about the arm.** This ticket
says *"the obvious guess is that the predicate is now right and some other test
in the same arm still refuses"*, and flags that the guess had not been run. Run:
**there was no arm to reach.** `for x in p^` never gets as far as
`ParseForInNodeAST`. Every bare-name for-in arm requires the next token to be
`do`, and `p` is followed by `^`, so the deref falls to the general
container-EXPRESSION path — which knew a class with `GetEnumerator` and a
dyn-array value and then gave up. That is why the message is the dispatch's
*"not a generator, enum type, or iterable variable"* and not
`ParseForInNodeAST`'s own *"unsupported iterable expression"*; the two messages
were the thing that located it.

`IsNodeArray` was never consulted for a non-IDENT, non-FIELD node, so teaching
it this shape could not have helped — necessary, and not merely "not
sufficient".

**Not materialised into a hidden local**, which is the move the two arms above
it in `ParseForInNodeAST` make and the obvious thing to copy. For a dyn array
that copies a HANDLE and still aliases the same elements; a static pointee would
be copied WHOLE, and iterating a private copy diverges from FPC the moment the
body writes through the pointer. `BuildForInArrayLoop` indexes the node it is
handed and `p^[i]` already lowers correctly, so the deref node goes in directly.
The test's `aliased=139` row exists to hold that decision in place.

### The boundary is wider than this ticket, and two rows are filed rather than fixed

| container | before | now |
| --- | --- | --- |
| `p^` (ptr to static array) | refused | **works** |
| bare var, record field, class field, dyn array | worked | works |
| `MkArr` — function returning a static array | refused | still refused |
| `o.GetArr` — method returning a static array | refused | still refused |

The two call rows are the same gap reached from a different shape source (the
`ProcRet*` columns rather than the pointer symbol's), which is a real difference
rather than a spelling, so they are
[[bug-p-for-in-over-a-static-array-returning-call-is-refused]] and not merged in
here.

### Deliberately half-fixed, and the half is asserted

**A non-zero low bound still refuses.** `BuildForInArrayLoop`'s own comment says
*"AN_INDEX subtracts the low bound itself, so `__i` in [lo..hi] is the correct
domain"* — true of the AN_IDENT container it was written for, **false for a
deref**: the subtraction keys on tags the lvalue walk stamps on a parser-built
`p^[i]`, and the bare AN_INDEX the builder synthesises carries none of them.
Measured with the bound admitted: `array[1..4]` holding `11 22 33 44` printed
`22 33 44 4310536`, and `array[5..7]` printed `0 0 4`. Shifted garbage, silently
— the one outcome worth refusing over. A hand-written `p1^[1]` is correct here
AND on pinned, so the defect is the synthesised node, not the index path.

Refusing is not a regression (it refused before), the Makefile asserts the
refusal so a later widening has to deal with the shift rather than ship it, and
the `staticLo` plumbing added for it was removed rather than left unexercised.
[[bug-p-for-in-over-a-deref-ignores-a-non-zero-low-bound]].
