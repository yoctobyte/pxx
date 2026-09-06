---
slug: refactor-a-the-assignment-kind-funnel-needs-a-third-discriminator-not-a-third-special-case
track: A
type: refactor
prio: 45
status: backlog
found: 2026-09-06
found-by: frankS
owner: ""
blocked-by: []
summary: "`AssignKindsIncompatible(dstTk, srcTk)` (symtab.inc:4003) sees only two TYPE KINDS, and `if dstTk = srcTk then Exit(False)` is its second line -- so every pair the kind channel cannot express arrives as a MATCHING pair and is actively CERTIFIED rather than merely missed. THREE sibling checks now sit beside its one call site in ir.inc rescuing exactly that: enum identity (:12346, two enum types are both tyEnum -- used to store TFruit's 1 into a TColor and read back green), fixed-array-to-dynamic (:12420, both sides are the ELEMENT's kind -- stored the static array's ADDRESS in the handle slot, Length(d)=4310328 then SIGSEGV where fpc prints three elements, refused at af9c92a6f), and the procedural-value/bare-routine-name check above them. Each rescues one pair on its own channel: SemId, array depth plus `Kind <> skParam`, node shape. TWO IS A SMELL AND THREE IS A DESIGN FLAW (CLAUDE.md, root-cause-over-microfix). THE COUNT IS SETTLED AT THREE -- frankS read the enum sibling after this was filed and corrected their own count from two. THE FIX SHAPE IS THEIRS AND IT IS NOT A FOURTH DISCRIMINATOR: `AssignKindsIncompatible` returns a Boolean where the honest answer has a THIRD value, `the kind cannot decide this`. What the three checks have in common is that each already knows the kind's answer is not authoritative for its shape, so the thing to try is a predicate asking WHETHER THE KIND IS AUTHORITATIVE HERE, consulted BEFORE the comparison, with the three existing checks as its ARMS rather than its siblings. A discriminator bolted alongside is a fourth special case in disguise. DELIBERATELY NOT SCHEDULED YET (frankS): three is what tells you it is a design flaw, four is what tells you which axis -- attempt it when a fourth instance exists."
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
