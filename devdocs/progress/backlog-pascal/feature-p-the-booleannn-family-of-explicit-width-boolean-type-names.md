---
slug: feature-p-the-booleannn-family-of-explicit-width-boolean-type-names
track: P
type: feature
prio: 45
status: backlog
created: 2026-09-06
found-by: frankB
owner: ""
blocked-by: [decide-how-a-type-carries-an-identity-its-kind-cannot-hold]
title: "`Boolean16` / `Boolean32` / `Boolean64` do not exist — a whole FPC type family, and one real corpus wall"
summary: "fpc has two sized-boolean families and we have one. `ByteBool`/`WordBool`/`LongBool` resolve (badly -- see bug-p-a-sized-boolean-is-true-and-not-true-at-the-same-time) and `Boolean16`/`Boolean32`/`Boolean64` are refused outright: `unknown type: Boolean16`. fpc sizes them 2/4/8 with Ord(True)=1, which is what distinguishes them from the *Bool family's all-bits-set. MEASURED CORPUS COST: uthlp.pp declares a Boolean16 and TWELVE tthlp* test files use that unit, so one missing name blocks twelve. They land in BuiltinScalarTypeKind, which frankA is actively collapsing with FindTypeAlias under refactor-p-five-dispatch-sites-for-one-named-type-cast -- ask them whether the rows go into the table as it stands or into the merged resolver before writing any. READ THE SIBLING BUG FIRST: adding these four names moves the corpus wall forward while `not` stays inverted on the three names we already ship, which looks like progress and is not."
---


> ### THE BLOCK WAS TRUE IN THE WORLD AND ABSENT FROM THE GRAPH — added 2026-09-06 by frank-coordinator, measured by frankA
>
> This row was filed today with `blocked-by: []`, at p45, where `next` would
> hand it to somebody who would then hit the wall the summary describes. The
> edge is added on frankA's measurement, in their words:
>
> > *"`defs.inc` has exactly two boolean kinds and both are one byte, so every
> > spelling `Boolean16` could have today is already a defect — `tyUInt16` is
> > right on width and wrong on `not`, `WriteLn` and `Ord`; `tyBoolean` is the
> > reverse and is the width failure the mapping's own comment exists to
> > forbid. There is no third option until the fork moves."*
>
> **That is a schedule claim, not a preference**, and it is what separates this
> row from the fork's other consumers: the other five are wrong behaviours in
> code that already exists — real, ranked, survivable. This one is code that
> **cannot be written correctly** at any spelling available today.
>
> **The coordination lesson is the absence, not the edge.** I had just told
> frankA that the fork has two edged consumers and that the ranker's
> `(unblocks 2)` therefore already reflected the picture — a correction that was
> arithmetically right and concluded the wrong thing, because I counted edges
> and read that as counting dependencies. **A missing edge is invisible to
> exactly the instrument you reach for to check whether an escalation is
> justified**, and the fork's real count was three. The sibling defect it names
> (`bug-p-a-sized-boolean-is-true-and-not-true-at-the-same-time`) already
> carried the edge; this one had the same blocker and no line saying so.

# The `BooleanNN` family does not exist

> **ORDERING HAZARD — READ THIS BEFORE DOING EITHER TICKET.** Every spelling
> `Boolean16` can have TODAY is already a defect: `tyUInt16` gets the width
> right and `not` / `WriteLn` / `Ord` wrong; `tyBoolean` gets those right and
> the width wrong (`defs.inc` has exactly two boolean kinds, `tyBoolean` and
> `tyBool8`, and both are ONE BYTE). So adding the four names moves the corpus
> wall forward while shipping four more instances of the sibling bug — it looks
> like progress and it is not. That converts
> `decide-how-a-type-carries-an-identity-its-kind-cannot-hold` from an argument
> to have before this work into a SCHEDULE for it: the fork is not optional
> here, it is the ordering constraint.


Measured 2026-09-06, commit `d3fe44947`, compiler `827722c842de`, against
fpc 3.2.2 — one program per name, both compilers.

| name | pxx | fpc |
| --- | --- | --- |
| `Boolean` | 1 | 1 |
| `Boolean16` | **refused** | 2 |
| `Boolean32` | **refused** | 4 |
| `Boolean64` | **refused** | 8 |
| `ByteBool` | 1 | 1 |
| `WordBool` | 2 | 2 |
| `LongBool` | 4 | 4 |
| `QWordBool` | **refused** | 8 |

## Two families, and the difference is not width

```
Ord(True)    Boolean 1   Boolean16 1   Boolean32 1   Boolean64 1
             ByteBool -1  WordBool -1   LongBool -1   QWordBool -1
```

`BooleanNN` is a Pascal boolean at a chosen width — 0 and 1. The `*Bool`
family is the C-ABI convention, all bits set. So these are not aliases of each
other and a fix that maps `Boolean16` onto `WordBool` is wrong in the same
direction the sibling bug is wrong: it would give it the -1 convention.

## The corpus cost, measured rather than asserted

`uthlp.pp` in the fpc testsuite needs `Boolean16`, and **twelve** files
reference `uthlp`: tthlp3, 4, 5, 6, 7, 8, 14, 18, 19, 26a, 26b, 26c. One
missing name, one shared unit, twelve blocked files. Found because they got
past the preprocessor for the first time at `a48ef8c33` and stopped here.

`QWordBool` is a different case in the same table: its three siblings exist and
work, so it is **an enumeration that stopped one short** rather than a family
nobody added. It is already named in the sibling bug's summary.

## Before writing any rows

**frankA is inside `BuiltinScalarTypeKind` this week**, collapsing it with
`FindTypeAlias` under `refactor-p-five-dispatch-sites-for-one-named-type-cast`
— and that ticket records that the ORDER between the two is load-bearing
(`FindTypeAlias` first; `4be17cb8f` fixed a door that asked the builtin table
before a user alias). Ask whether these names go into the table as it stands or
into the merged resolver. Doing it twice is the cost.

**And read `bug-p-a-sized-boolean-is-true-and-not-true-at-the-same-time`
first.** `not` on a sized boolean is an integer complement, so `a` and `not a`
are both true. Adding four names here moves the corpus wall forward while that
stays in — and the missing name is the one that produces an error message,
so it is the one that recruits an owner.
