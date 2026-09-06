---
track: P
prio: 45
type: refactor
blocked-by: []
status: open
owner: ""
created: 2026-09-06
summary: "\"Is this node a whole array?\" is answered in four places with four different predicates -- `Syms[].IsArray` (AssignSideKind's ident arm), `NodeDynDepth` (its field arm), `NodeDynDepth` plus `Kind <> skParam` (the fixed-to-dynamic sibling), and `ASTNodeIsWholeArray` (the lowering). THEY GENUINELY DISAGREE AND IT IS MEASURED, not assumed: for a static array FIELD, ASTNodeIsWholeArray answers True and NodeDynDepth answers 0 (frankD, `12af8ef60`). Nothing is broken today -- `c.SA := b` on an `array[0..2] of TR` field matches fpc both ways -- which is exactly the problem: agreeing on all but one shape is worse than disagreeing visibly, because four obviously different answers get reconciled the first time anyone looks. SPLIT OUT of refactor-a-the-assignment-kind-funnel-needs-a-third-discriminator-not-a-third-special-case (backlog-core p55) at frankS's direction: that ticket also carries the PAIRWISE half (enum identity, fixed-to-dynamic -- facts about two sides together that no per-side predicate can express) and the axis split between per-side authority and pairwise identity is the most valuable thing on it. Moving the whole ticket into a shape-readers group would quietly re-merge the two axes. This row is the per-side shape question only."
---

# "Is this node a whole array?" is answered in four places with four lists

- **Type:** refactor — **Track P** (Group 28, THE ARRAY'S SHAPE AND WHO IS
  ALLOWED TO ASK ABOUT IT).
- **Split out, not moved.** The parent stays in `backlog-core`:
  [[refactor-a-the-assignment-kind-funnel-needs-a-third-discriminator-not-a-third-special-case]].
  Read it for the funnel and for the pairwise half; this row is only the
  per-side shape question, which is the half that belongs with the other array
  shape readers.

## The four

| site | predicate |
| --- | --- |
| `AssignSideKind`, ident arm | `Syms[].IsArray` |
| `AssignSideKind`, field arm (as of `12af8ef60`) | `NodeDynDepth` |
| the fixed→dynamic sibling | `NodeDynDepth` **plus** `Syms[].Kind <> skParam` |
| the lowering | `ASTNodeIsWholeArray` |

**Measured disagreement:** for a **static array FIELD**, `ASTNodeIsWholeArray`
answers True and `NodeDynDepth` answers 0. `c.SA := b` on an
`array[0..2] of TR` field matches fpc today, whole-assignment and per-element,
so nothing is broken — **the field-arm fix is complete for dynamic arrays and
silent about static ones**, and frankD wrote that down rather than leaving it
to be found.

## Why it ranks with the shape readers rather than with the funnel

Three of Group 28's rows are *"the reader could not ask the question it
actually had"*. This is the fourth form: **four readers ask, and get four
answers.**

frankS's classification, which is the reason this is a separate row: **a
partially-consulted record** is found by a set difference — is that column
consulted where the cases are distinguished — while **four predicates that
agree on all but one shape cannot be found that way**, because every consumer
exists and every one compiles. *Agreeing on all but one shape is worse than
disagreeing visibly*: four obviously different answers get reconciled the first
time anyone looks at them together, and four that agree in every probed case do
not.

Compare the sibling already closed in this group,
[[bug-p-low-and-high-of-a-nested-static-array-row-answer-the-outer-arrays-bounds]]:
there, `NDRowSourceInfo` answers a different question off the same data and
**both its callers are right**. That one is found by noticing two correct
callers want different numbers. This one is found by asking four readers the
same question. Neither is found by grepping for an absence.

## Availability

Deliberately ownerless in the parent, for stated reasons: frankD is at rung 7
(`pparser.pp` next) and offered a handover of the per-side half with the two
arms and the measured disagreement; frankS declined on scheduling, not
interest, because their instance sits in the pairwise half. **frankD's
handover offer is live.** Take the handover before starting.

## What would settle it

One predicate, node-shape-independent, that every one of the four consults —
and, before that, a probe per shape (ident, field, param, deref, index) crossed
with static and dynamic, recording what each of the four answers **today**. The
disagreement above is one cell of that table and it is the only cell anyone has
filled in.

**Do not collapse the pairwise checks into it.** Enum identity and
fixed-to-dynamic are facts about two sides TOGETHER; a per-side predicate
cannot express them, and putting one in a per-side slot is the specific
mistake the parent's axis split exists to prevent.
