---
slug: decide-typeref-gains-a-pointer-depth-field
title: "TTypeRef has no pointer DEPTH field — does it gain one, or does depth stay outside?"
track: U
prio: 35
type: decide
blocked-by: []
status: decided
owner: ""
created: 2026-08-24
summary: "TTypeRef was landed to replace the 8-field tuple that ~90 sites redeclare, but as declared it carries PtrBaseTk/PtrBaseRec and DynDepth and no POINTER depth — so it cannot express `^PChar` any better than the pair it replaces. Every pointer table has since grown a depth field of its own (symbols, aliases, the type parser, C params, Pascal params, captures, proc returns). Either TTypeRef gains PtrDepth and the migration folds them all in, or depth is declared to live outside TTypeRef and the migration's value shrinks. Additive either way, but it changes a shared type mid-migration."
---

# The fork

`compiler/defs.inc`'s `TTypeRef` names the tuple that pointer identity is spelled
with, so it can eventually be carried as ONE value instead of five parallel
arrays. Its landing rule is *additive only; nothing reads it yet*.

As declared it has `Kind`, `PtrBaseTk`, `PtrBaseRec`, `DynDepth` (dynamic-array
nesting) and friends — but **no pointer depth**. Pointer depth is the only thing
that separates `PChar` from `^PChar`: they have the same immediate pointee and
the same ultimate base. Four bugs in two days came from a table that recorded
the pointee without the depth beside it.

# What has happened since it landed

Every pointer-carrying table now carries the depth explicitly:

| table | depth field |
| --- | --- |
| symbols | `SymPtrDepth` |
| type aliases | `AliasPtrDepth` |
| the Pascal type parser | `LastTypePointerDepth` |
| C parameters | `pdepths` / `ProcParamPtrDepth` |
| Pascal parameters | `ptypesPtrDepth` (2026-08-24) |
| nested-routine captures | `LiftCapPtrDepth` (2026-08-24) |
| proc returns | `ProcRetPtrDepth` (2026-08-24) |

That is seven spellings of one concept, which is exactly the sprawl `TTypeRef`
exists to end — and `TTypeRef` currently cannot absorb any of them.

# Options

1. **`TTypeRef` gains `PtrDepth`** (recommended). Additive: nothing reads a
   pointer depth off `TTypeRef` today because there is nothing to read. The
   migration then folds seven tables into one carrier, and `ir.inc:2506`'s
   "one level over a char base" test reads a field instead of a convention.
   Cost: a shared type changes mid-migration, so every lane's next `SetLength`
   site must be re-checked.
2. **Depth stays outside `TTypeRef`.** The record describes "what type", the
   depth stays a per-table integer. Cheaper today, but it concedes that the one
   field that actually distinguishes the confusable cases is the one the shared
   carrier does not carry — and the migration's remaining value is then mostly
   about record ids.
3. **Fold depth INTO `PtrBaseTk`'s meaning** (a sentinel encoding, e.g. base
   kind plus level count packed). Rejected on sight; it is the
   partial-index-sentinel mistake `IRNodePointerBase` already documents.

# Recommendation

Option 1, with the fold done lane by lane under the A/B binary comparison the
migration has used so far — the seven depth fields keep working until their lane
is cut over, and each cut-over is provably neutral or not.

Blocks: [[feature-a-typeref-migrate-consumers]] step 2.

---

# DECIDED 2026-08-25 — **option 1: `TTypeRef` gains `PtrDepth`**

Decided by an agent under the no-human-available rule
(`devdocs/progress/decided/README-agent-decisions.md`). **Derived**, and about
as cleanly as this repo's rules ever derive anything.

`root-cause-over-microfix.md`:

> *"**Count the mechanisms serving one concept.** Two lowerings for one language
> feature is a smell; three is a design flaw."*

The ticket's own table counts **seven**: `SymPtrDepth`, `AliasPtrDepth`,
`LastTypePointerDepth`, `pdepths`/`ProcParamPtrDepth`, `ptypesPtrDepth`,
`LiftCapPtrDepth`, `ProcRetPtrDepth`. Seven spellings of one integer, four of
them added in the two days before the ticket was filed, and *"four bugs in two
days came from a table that recorded the pointee without the depth beside it."*

Option 2 answers that by declaring the sprawl out of scope for the carrier built
to end it. That is not a cheaper option, it is a smaller `TTypeRef` — and it
concedes, in the ticket's own words, that *"the one field that actually
distinguishes the confusable cases is the one the shared carrier does not
carry."* A type-identity carrier that cannot distinguish `PChar` from `^PChar`
has not carried type identity.

Option 3 was already rejected on sight by the ticket and stays rejected: packing
depth into `PtrBaseTk`'s meaning is the partial-index-sentinel mistake
`IRNodePointerBase` documents.

## Why the risk is smaller than "changes a shared type mid-migration" sounds

The landing rule is *additive only; nothing reads it yet* — and nothing can read
a pointer depth off `TTypeRef` today because there is no such field to read. So
adding one cannot change any existing behaviour; it can only change record size,
which is why the ticket's caution is about `SetLength` sites rather than about
semantics.

The migration then folds seven tables into one carrier lane by lane, under the
A/B binary comparison already in use, each cut-over provably neutral or not.
That is `normalise-dont-special-case.md`'s *"one thing to get right instead of
two that must stay in step"*, times seven.

## Coordination note (Track A discipline, not part of the decision)

`compiler/defs.inc` is shared ground. The field lands as one additive commit
with no readers, and the lane-by-lane folds are separate commits — so a
concurrent lane's next `SetLength` site is re-checked against a landed shared
type rather than against a moving one.

## Re-filed as work

Track **A**: the field addition folds into
[[feature-a-typeref-migrate-consumers]], whose step 2 this was blocking. Prio
follows that ticket. Add `PtrDepth` to `TTypeRef` first, readers-free; then
`ir.inc:2506`'s "one level over a char base" test reads a field instead of a
convention, which is the first fold worth taking because it is where the four
bugs came from.

## Log
- 2026-08-25 — decided, commit 28c19f214.
