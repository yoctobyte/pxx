---
slug: refactor-a-the-assignment-kind-funnel-needs-a-third-discriminator-not-a-third-special-case
track: A
type: refactor
prio: 55
status: backlog
found: 2026-09-06
found-by: frankS
owner: ""
blocked-by: []
summary: "`AssignKindsIncompatible(dstTk, srcTk)` (symtab.inc:4003) sees only two TYPE KINDS, and `if dstTk = srcTk then Exit(False)` is its second line -- so every pair the kind channel cannot express arrives as a MATCHING pair and is actively CERTIFIED rather than merely missed. THREE sibling checks now sit beside its one call site in ir.inc rescuing exactly that: enum identity (:12346, two enum types are both tyEnum -- used to store TFruit's 1 into a TColor and read back green), fixed-array-to-dynamic (:12420, both sides are the ELEMENT's kind -- stored the static array's ADDRESS in the handle slot, Length(d)=4310328 then SIGSEGV where fpc prints three elements, refused at af9c92a6f), and the procedural-value/bare-routine-name check above them. Each rescues one pair on its own channel: SemId, array depth plus `Kind <> skParam`, node shape. TWO IS A SMELL AND THREE IS A DESIGN FLAW (CLAUDE.md, root-cause-over-microfix). THE COUNT IS SETTLED AT THREE -- frankS read the enum sibling after this was filed and corrected their own count from two. THE FIX SHAPE IS THEIRS AND IT IS NOT A FOURTH DISCRIMINATOR: `AssignKindsIncompatible` returns a Boolean where the honest answer has a THIRD value, `the kind cannot decide this`. What the three checks have in common is that each already knows the kind's answer is not authoritative for its shape, so the thing to try is a predicate asking WHETHER THE KIND IS AUTHORITATIVE HERE, consulted BEFORE the comparison, with the three existing checks as its ARMS rather than its siblings. A discriminator bolted alongside is a fourth special case in disguise. THE FOURTH INSTANCE HAS ARRIVED (frankD, `12af8ef60`) AND IT NAMES A DIFFERENT AXIS THAN PREDICTED, WHICH IS THE WHOLE VALUE OF A FOURTH. The predicate frankS proposed ALREADY EXISTS -- `AssignSideKind` (ir.inc:183), consulted before the comparison, whose False return IS the third value, with five bails in its ident arm each commented `the kind is not authoritative for this side`. The real defect is that it is implemented TWICE, PER NODE SHAPE, and the copies had drifted: the field arm carried two bails where the ident arm had five, missing `IsArray` first, so `array of <record>` was refused as a FIELD and accepted as a VARIABLE -- same question, two answers, decided by spelling. AND THE AXIS SPLITS THE SIBLINGS INTO TWO GROUPS THAT ARE NOT ONE GROUP: per-side AUTHORITY (the bails, collapsible into one node-shape-independent question) versus pairwise IDENTITY (enum identity and fixed-to-dynamic, facts about both sides together that NO per-side predicate can express). So the honest shape is TWO changes, not one, and collapsing all five would put a pairwise fact in a per-side slot. Unscheduled by both seats; frankD offers a handover of the per-side half."
---

# The assignment kind funnel is certifying, not missing

`AssignKindsIncompatible(dstTk, srcTk: TTypeKind)` answers *"can this pair only
produce a wrong value or a crash"*. Its inputs are two kinds and nothing else,
and its second line is:

```pascal
if dstTk = srcTk then begin AssignKindsIncompatible := False; Exit; end;
```

**Every distinction the TTypeKind channel cannot carry therefore arrives here as
a matching pair**, and the funnel does not stay silent about it — it returns
"compatible". That is the dangerous direction: a check that says nothing can be
supplemented, a check that says YES has to be overruled.

## Three siblings, one call site, three different channels

All in `ir.inc`'s `AN_ASSIGN` arm, because every syntactic form of assignment
funnels through that node (`for` variables, `+=`, out-param clears, field
stores):

| sibling | what the kind channel says | what it took instead | the damage it was added for |
| --- | --- | --- | --- |
| enum identity, `:12346` | `tyEnum = tyEnum`, matching | `SymSemId` on both idents | `aColor := banana` stored TFruit's 1 into a TColor and read back **green** (tenum4) |
| fixed → dynamic array, `:12420` | element kind on both sides, matching | `NodeDynDepth` + `Syms[].Kind <> skParam` | stored the static array's ADDRESS in the handle slot: `Length(d) = 4310328`, then SIGSEGV, where fpc prints `len=3: 2 4 6` |
| procedural value / bare routine name, `:~12306` | — | node shape | FPC/Delphi parity on a procedural variable in a value context |

**Each was found by a crash or a wrong value in the field, never by the funnel.**
That is the signature the root-cause rule names: the mechanism serving one
concept has grown a case per discovery, and the next member of the class is
already in the tree waiting to be found the same way.

## THE FOURTH INSTANCE ARRIVED AND IT NAMES A DIFFERENT AXIS — read this before the section below

frankD, 2026-09-06, having read this ticket rather than a summary of it. **This
supersedes the fix shape recorded above**, which is left in place because it was
the reasoning that produced the condition this row set for itself.

**The predicate frankS proposed already exists.** It is `AssignSideKind`
(`ir.inc:183`), it is consulted BEFORE the comparison — it is the first two
conjuncts of the call site — and **its `False` return IS the third value**. Its
`AN_IDENT` arm has five bails, each with a comment saying the kind is not
authoritative for this side:

```pascal
if Syms[si].IsArray then Exit;          { the kind is the ELEMENT's }
if Syms[si].IsRef then Exit;            { by-ref/untyped: the slot holds an address }
if SymProcSig[si] >= 0 then Exit;       { procvar: the kind is the RESULT's }
if SymCellPtr[si] >= 0 then Exit;       { captured cell: one indirection away }
if RecIsReferenceShaped(Syms[si].RecName) then Exit;
```

**So the funnel does not need a third value bolted on. It has one.** What it has
instead is **that predicate implemented TWICE, per node shape, with the copies
drifted apart.** The field/element/deref arm, added later, carried two bails
where the identifier arm had five — and the missing one was the FIRST:
`IsArray`. So `array of <record>` as a FIELD typed as its element and was
refused, while the identical type as a VARIABLE took the arm that bails. **Same
question, two answers, decided by which spelling you used.** Landed at
`12af8ef60`.

### The axis, and it splits the three siblings into two groups that are not one group

| | fact about | can a per-side authority predicate absorb it? |
| --- | --- | --- |
| `AssignSideKind`'s five bails, and the field-arm fix | **one side, alone** — this side knows its kind is not its description | **yes**, and they should collapse into one node-shape-independent question |
| enum identity (`:12346`) | **both sides together** — these two enums are different types | **no** |
| fixed → dynamic array (`:12420`) | **both sides together** — a static array is being stored into a dynamic handle | **no** |

**PER-SIDE AUTHORITY versus PAIRWISE IDENTITY.** No per-side predicate can
express either pairwise fact, so consulting authority before the comparison
cannot absorb them. **frankS's "a discriminator bolted alongside is a fourth
special case in disguise" is right about the pairwise group and does not reach
the per-side one.**

**The honest shape is therefore TWO changes, not one:**

1. **Unify the per-side authority list** so it is asked once regardless of node
   shape. Real work, real payoff, and it is where the silent-per-spelling
   defects live.
2. **Leave the pairwise checks pairwise**, ideally behind one
   `AssignPairIdentityMismatch` rather than three inline arms.

**Collapsing all five into one predicate is the tidy answer and would put a
pairwise fact in a per-side slot.** That is the trap this ticket would otherwise
have walked into, and it is the reason a fourth instance was worth waiting for:
three said "design flaw", four said **which axis**.

## A FIFTH SITE — not a fifth instance, and it carries a measured disagreement

**SPLIT OUT 2026-09-06 (frankB) as
[[refactor-p-is-this-node-a-whole-array-is-answered-in-four-places-with-four-lists]]**,
Track P, Group 28 (the array's shape and who is allowed to ask about it). The
section below stays here because it is the funnel's own evidence; the WORK of
reconciling the four predicates is that row. **This ticket keeps the pairwise
half deliberately** — enum identity and fixed-to-dynamic are facts about two
sides together and no per-side predicate can express them, so moving the whole
ticket into a shape-readers group would quietly re-merge the two axes, and the
axis split is the most valuable thing on this row (frankS, who asked for the
split in this shape).

*"Is this node a whole array?"* is now answered in **four places with four
different lists**:

| site | predicate |
| --- | --- |
| `AssignSideKind`, ident arm | `Syms[].IsArray` |
| `AssignSideKind`, field arm (as of `12af8ef60`) | `NodeDynDepth` |
| the fixed→dynamic sibling | `NodeDynDepth` **plus** `Syms[].Kind <> skParam` |
| the lowering | `ASTNodeIsWholeArray` (widened from `AN_IDENT`-only, same commit) |

**They genuinely disagree, and the gap was measured rather than assumed:** for a
**static array FIELD**, `ASTNodeIsWholeArray` now answers True and `NodeDynDepth`
answers 0. Nothing is broken there today — `c.SA := b` on an `array[0..2] of TR`
field matches fpc, whole-assignment and per-element — **but the field-arm fix is
complete for dynamic arrays and silent about static ones**, and frankD wrote that
down rather than leaving it to be discovered.

## Availability — UNCLAIMED ON PURPOSE, by both seats, for stated reasons

**frankD** is not scheduling the collapse (rung 7, `pparser.pp` next) and offered
frankS the per-side half with the two arms and the measured disagreement.

**frankS declined, on scheduling and not on interest** (2026-09-06): they are
three landings into the array-parameter family, taking the per-side collapse
would mean holding two open questions in the same funnel, and **the pairwise half
is the one their instance sits in.** Their words, and the reason this section
exists rather than an `owner:`: *"leaving it unclaimed with the two arms and the
measured disagreement written down is better than my holding it slowly — I would
rather it wait for whoever is next in that funnel than be parked under my name."*

**So this row is deliberately ownerless and that is not neglect.** Everything the
next holder needs is written down: the axis, the two groups, the four
disagreeing sites, and the one measured shape where they disagree today.

## RANKED UP 45 -> 55 on frankS's argument, which is about the FIFTH SITE and not the funnel

Their reading, and it reclassifies the four-lists finding from tidiness to
defect-in-waiting: it is **a partially-consulted record**, the same shape as the
`ProcParamDynDepth` defect they landed the same day — *written by every
declaration parser, read by `ir.inc` at the call site, and ignored by the one
comparison that decides whether two declarations are the same routine.*

> **An absence can be found by a set difference. A column that one consumer reads
> and another ignores cannot** — both consumers exist, both compile, and the
> tables are complete. **The only question that surfaces it is: "what
> distinguishes these two, and is that thing consulted where they are
> distinguished?"**

Four consumers, one concept, and nothing that makes them answer together. **That
they agree today for every shape but one is what makes it dangerous rather than
safe** — a single disagreeing shape is a defect nobody will attribute to the
right cause, where four visibly different answers would have been fixed already.

## What a fix has to be, and what it must not become

Not a fourth sibling. The shared property is that **a `TTypeKind` pair is not a
type identity** — the kind is a REPRESENTATION class, and three separate
questions (which enum, which array shape, which storage class) are being asked of
a channel that cannot hold any of them. A discriminator that carries the symbol
or node on each side, rather than a kind pair distilled from them, answers all
three in one place and is the thing that stops the fourth from being a special
case too.

**The constraint that makes this non-trivial, and it is measured**, from the
array sibling: `ArrLen > 0` does NOT mean "fixed length". `AllocParam` stamps
`ArrLen := 1000` on EVERY array parameter as the open-array placeholder, so a
length test alone refuses the open-array case that must keep working — and an
open-array-to-dynamic assignment is a case **FPC rejects and we accept**, which
per CLAUDE.md is not a defect and must not regress. `Kind <> skParam` is the
property that separates them. Any richer discriminator has to keep that
distinction rather than rediscover it.

## Scope

`compiler/symtab.inc:4003` (the funnel) and the three sibling checks in
`compiler/ir.inc`. Not a behaviour change: every case currently refused must stay
refused and every case currently accepted must stay accepted, which makes the
existing rows the control set. Measure by cases-deleted, not lines.

**Filed by the coordinator, not by the author.** frankS named this residual in
the same breath as landing the third sibling — *"which by the two-is-a-smell rule
says the funnel needs a third discriminator, not a third special case; I have not
done that, I have added the second special case and said so"* — and a residual
that lives only in a commit message and a code comment has no reader. The third
count is theirs; the enum sibling is a reading of the tree by this seat, so **the
count above is three by my reading and two by theirs** — if the procedural check
turns out to be a different animal, it is still two, and two is still a smell.

## The fourth instance exists (frankD, 2026-09-06, `12af8ef60`) — and it splits the group in two

The condition this ticket set for attempting it is met. The fourth is **not** a
fourth sibling beside the funnel; it is on the authority predicate, and finding
it changes the fix shape.

**THE PREDICATE THIS TICKET PROPOSES ALREADY EXISTS AND IS CALLED
`AssignSideKind`.** "A predicate asking whether the kind is authoritative here,
consulted BEFORE the comparison" describes what it does today: returning `False`
IS the third value, and the AN_IDENT arm carries five bails that each say so in
their own comment — `IsArray`, `IsRef`, `SymProcSig`, `SymCellPtr`,
`RecIsReferenceShaped`. The funnel does not need a third value added. It has
one.

**What it has instead is that predicate implemented TWICE, per node shape, with
the copies drifted.** The AN_INDEX/AN_FIELD/AN_DEREF arm, added later, had two
bails where the identifier arm had five, and the missing one was the FIRST:
`IsArray`. So `array of <record>` as a FIELD typed as its element and
`Fld := nil` was refused as `cannot assign Pointer to record`, while the
identical type as a VARIABLE took the arm that bails. One question, two answers,
selected by spelling. Fixed by adding `NodeDynDepth(node) > 0` to the second arm
(`bug-a-a-nil-assignment-to-a-dynamic-array-field-is-lowered-as-a-record-zero`).

### The axis: PER-SIDE authority vs PAIRWISE identity — the three siblings are not one group

| | fact about | can a per-side predicate express it? |
| --- | --- | --- |
| `AssignSideKind`'s five bails + the new dyn-array bail | ONE side | **yes** — this is what it already is |
| enum identity (`:12346`) | the two sides TOGETHER | no |
| fixed → dynamic array (`:12420`) | the two sides TOGETHER | no |

"These two enums are different types" and "a static array is going into a
dynamic handle" are facts about a PAIR. No predicate consulted per-side before
the comparison can absorb either, so the unification this ticket proposes
reaches the first row and not the other two. **The honest shape is two changes:**
collapse the per-side authority list so it is answered once regardless of node
shape, and leave the pairwise checks pairwise — ideally behind one
`AssignPairIdentityMismatch` instead of three inline arms. Putting all five
behind one predicate would be the tidy answer and would file a pairwise fact in
a per-side slot.

This ticket's *"a discriminator bolted alongside is a fourth special case in
disguise"* is right about the pairwise group and does not reach the per-side one.

### A fifth SITE, not a fifth instance, and they disagree

"Is this node a whole array?" is now answered in four places with four lists:
`Syms[].IsArray` (AssignSideKind, ident arm), `NodeDynDepth` (its field arm, as
of `12af8ef60`), `NodeDynDepth` + `Syms[].Kind <> skParam` (the fixed→dyn
sibling), and `ASTNodeIsWholeArray` (the LOWERING, widened from AN_IDENT-only in
the same commit — it was answering False for a dyn-array field and sending the
store down the record-zero path).

**Measured, not assumed:** they disagree for a STATIC array field —
`ASTNodeIsWholeArray` answers True (via `RecFieldIsArray`) and `NodeDynDepth`
answers 0. Nothing is broken there today: `c.SA := b` on an
`array[0..2] of TR` field matches fpc for both the whole assignment and the
per-element loop. But the dyn-array fix is **complete for dynamic arrays and
silent about static ones**, and that is a stated gap rather than a discovered
one.

Unscheduled by frankD too — rung 7 has `pparser.pp` next. The per-side half can
be handed over with the two arms and the measured disagreement.
