---
slug: bug-p-for-in-over-a-dereferenced-pointer-to-array-is-refused
track: P
prio: 35
type: bug
status: backlog
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
