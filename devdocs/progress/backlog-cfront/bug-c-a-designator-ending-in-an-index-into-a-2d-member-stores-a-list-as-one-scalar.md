---
slug: bug-c-a-designator-ending-in-an-index-into-a-2d-member-stores-a-list-as-one-scalar
track: C
prio: 25
type: bug
status: backlog
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
