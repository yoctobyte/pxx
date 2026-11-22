---
slug: bug-c-a-designator-ending-in-an-index-into-a-2d-member-stores-a-list-as-one-scalar
track: C
prio: 25
type: bug
status: done
closed: 2026-11-22
created: 2026-11-22
found-by: claude-pxx (fixing bug-c-a-chained-designator-onto-an-array-member-stores-one-scalar)
tags: [cfront, initializer, designator]
blocked-by: []
summary: "`struct { short m2[2][2]; } x = { .m2[1] = {8, 9} };` gives m2 = {0, 0, 8, 0} (gcc: {0, 0, 8, 9}). Through a chain (`.d.m2[1] = {8, 9}`) as well. CInitDesignatedDescend's `[i]` arm keeps the element type and falls to CInitLeaf, which reads `{8, 9}` as a braced scalar. It should walk the remaining dimension as a sub-array, as CInitWalkArray does. Not seen in real code yet."
---

# A designator ending in an index into a 2-D member stores a list as one scalar

Repro: test/c_designator_chain_onto_array_member.c with its `i` initializer
written as `.d.m2[1] = {8, 9}` (the test spells it positionally to stay
green). The pin gets this wrong too.

## Done (2026-11-22)

The bug was wider than the summary. Measured against gcc, with a struct
holding `short m2[2][3]`, both inside functions and at file scope:

| initialiser | gcc | pxx before |
|---|---|---|
| `.m2[1] = {8, 9}` | m2 = 0 0 0 8 9 0 | 0 8 0 0 0 0 |
| `.m2[1][2] = 7` | 7 at flat 5 | 7 at flat 2 (the last index alone) |
| `.m2[0][1] = 3, 4, 5` | 3 4 5 at [0][1] [0][2] [1][0] | 3 there, 4 and 5 went to the next member |
| `.d.m2[1] = {6, 7, 8}` | row 1 | 6 at flat 1 |

Fix: CInitDesignatedArrayMember, reached from both designator entry points
(the record walk's `.m[...]` and the end of a `.a.b.m[...]` chain) for an
array member followed by `[`.
- Each index is scaled by the elements below its level.
- A chain that stops above the element level walks the sub-array the way
  CInitWalkArray walks a row, and a string fills a char row.
- One element is a leaf, a braced record, or a further `.field`/`[i]`
  descent for record elements.
- Then the following positional values fill the next elements while the
  array has room (C11 6.7.9p17). The comma before a value that does not
  fit is left for the record walk. That continuation is for scalar
  elements only; after a record element the record walk goes on with the
  next member, as before.

Test c_designator_into_array_member (gcc-checked: x86-64, i386, riscv32)
covers all four rows above plus 1-D continuation, char rows from a string
(braced and not), struct-element arrays (`.pts[1].y`, `.pts[1] = {1, 2}`),
3-D sub-arrays, a continuation that spills into the next member, and
static and automatic objects.
