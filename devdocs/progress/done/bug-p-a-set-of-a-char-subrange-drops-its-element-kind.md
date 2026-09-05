---
slug: bug-p-a-set-of-a-char-subrange-drops-its-element-kind
title: "`Low`/`High` of a `set of 'c'..'k'` answered 99 and 107 — the element kind was fine and the set was flagged a subrange"
track: P
prio: 35
type: bug
status: done
owner: ""
created: 2026-09-05
found-by: frankB
blocked-by: []
summary: "FIXED 2026-09-05, AND THE SLUG IS THE MISDIAGNOSIS: the element kind was never dropped. `SymSetElemTk` held tyChar throughout -- `for c in s` reads that same field and was green the whole time, which is the measurement that separates the two explanations. What leaked was `LastTypeIsSub`: parsing the ELEMENT of `set of 'c'..'k'` left it set, and AllocVar copies it onto the SET symbol, so the set variable was flagged SymIsSub with the element bounds 99..107. TryOrdinalVarBound tests SymIsSub BEFORE its set arm, so the subrange arm answered the right ordinal typed with the SET kind and printed 99. One line in ParseSetElemSpec clears it. The named set TYPE spelling (`Low(TS)`, refused as `undefined variable`) is also closed, by TrySetTypeBound shared between the const evaluator and the expression path -- it was prerequisite 1 in this ticket and is now the third asserted spelling. Prerequisite 2 (folding the third `parse lo..hi` copy) was NOT needed and is not done: that copy is correct."
---

# The measurement

```pascal
var b: set of 'c'..'k';
WriteLn(Low(b), ' ', High(b));   { pxx: 99 107    fpc: c k }
```

Verified PRE-EXISTING against pin v403.

# Why it was split from its filing partner

The parent ticket carried two defects under one slug, and they turned out to
share a family and not a mechanism. Half 1 was **one missing column** in
`RegisterGeneralAlias` plus its read sites — fixed 2026-09-05, and the fix
touched nothing this half needs. Half 2 is the third copy of a subrange parse
and a `Low`/`High` question that is not answerable yet.

A reader who took the parent slug at face value would have fixed half 1 and
closed the ticket, which is the failure the Track P campaign is grouping by
CONSTRUCT to avoid.

# What it needs, in order

1. **`Low`/`High` of a set TYPE NAME** — refused today with
   `undefined variable (SI)`. Until that answers, only the set-VARIABLE
   spelling can be asserted, which is half a test.
2. **Fold the third `parse lo..hi` copy.** The other two were folded into one
   shared body on 2026-09-05; `ParseSetElemSpec` still has its own, guarded on
   `tkInteger`, which is exactly why a char subrange misses it. Folding is the
   likely fix rather than adding a char arm to the copy.

# The fork this sits under

[[decide-how-a-type-carries-an-identity-its-kind-cannot-hold]] (Track U, p55)

# RESOLVED 2026-09-05 — the mechanism above is WRONG, kept for the reader

The section "What it needs, in order" named two prerequisites. **Item 1 was
real and is done. Item 2 was not needed and the copy it names is correct.**

## What actually happened

`ParseSetElemSpec` parses the element through `ParseTypeKind`, which for
`'c'..'k'` reaches `ParseSubrangeTail`. That routine sets `LastTypeIsSub`,
`LastTypeSubLo` and `LastTypeSubHi` — correctly, for the ELEMENT. Nothing
cleared them, and `AllocVar` copies all three onto whatever symbol it is
building, which here is the SET.

So the set variable carried `SymIsSub = True` with bounds 99..107.
`TryOrdinalVarBound` tests `SymIsSub` in its FIRST arm and the set in a later
one, so `Low(s)` never reached the set arm at all: it answered 99 — the right
ordinal, from the right bounds — and typed it with `Syms[].TypeKind`, which is
`tySet`. An integer came out.

One line at the end of `ParseSetElemSpec` clears the three globals. The
element's own subrange bounds already have a home three lines above it, in
`LastTypeSetElemLo/Hi`.

## The reading that was wrong, and why it looked right

`99 107` where fpc gives `c k` is exactly what a lost element kind produces.
The bounds are right and only the type is wrong, which is the signature of a
kind being dropped somewhere. And there WAS a plausible place for it to be
dropped — the third `parse lo..hi` copy, guarded on `tkInteger`, one line from
the char path.

**The discriminator was `for c in s`, and it costs one line.** For-in over a
set reads `SymSetElemTk` — the ticket that fixed it says so in
`ParseSetElemSpec`'s own header — and it worked. If the element kind were
dropped, for-in would have been refused. So the field was correct and the arm
that reads it was never reached, which is a different bug in a different
routine from the one this ticket named.

Same shape as [[bug-p-a-char-array-row-through-a-pointer-deref-loads-short]]
the same night: a true measurement (`99` is the right ordinal) supporting a
false cause, with the actual defect one layer away. **Ask what ELSE reads the
field you think was lost, and check whether that consumer is happy.** A field
with a second reader is cheap to exculpate and nothing prompts you to try.

## Also closed here: the set TYPE NAME spelling

`Low(TS)` / `High(TS)` for `TS = set of 'c'..'k'` answered `undefined variable
(TS)`. `TrySetTypeBound` is the new arm, written as ONE function called from
both `TryConstHighLowValue` and `TryFoldHighLowType` — the same shape
`TryArrayTypeBound` already has, and for the reason those two carry in their
own comments: one concept in two places, and a rule spelled once per caller
fails by a MISSING copy that no diff of the callers can find.

Its three-way is `TryOrdinalVarBound`'s set arm exactly (element subrange, then
element enum range, then element kind bounds), because the type name and the
variable must not answer differently for the same set.

## Tests

`test/test_low_high_carry_the_ordinals_identity.{pas,expected}` — 15 rows, fpc
oracle. Row E is the for-in row, green before and after, present because it is
the reading that decided this. Rows I and J are controls that CANNOT
distinguish a fix from a no-op (an integer subrange and an integer set print as
integers either way) and are there only to catch a widening. Row K asserts the
ordinals through `Ord`, which was green throughout — the assertion class that
could not have seen any of this.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
