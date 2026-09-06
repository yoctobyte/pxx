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
summary: "`AssignKindsIncompatible(dstTk, srcTk)` (symtab.inc:4003) sees only two TYPE KINDS, and `if dstTk = srcTk then Exit(False)` is its second line -- so every pair the kind channel cannot express arrives as a MATCHING pair and is actively CERTIFIED rather than merely missed. THREE sibling checks now sit beside its one call site in ir.inc rescuing exactly that: enum identity (:12346, two enum types are both tyEnum -- used to store TFruit's 1 into a TColor and read back green), fixed-array-to-dynamic (:12420, both sides are the ELEMENT's kind -- stored the static array's ADDRESS in the handle slot, Length(d)=4310328 then SIGSEGV where fpc prints three elements, refused at af9c92a6f), and the procedural-value/bare-routine-name check above them. Each rescues one pair on its own channel: SemId, array depth plus `Kind <> skParam`, node shape. TWO IS A SMELL AND THREE IS A DESIGN FLAW (CLAUDE.md, root-cause-over-microfix): the funnel needs a discriminator richer than a TTypeKind pair, not a fourth sibling. frankS named this residual on landing the third and deliberately did not take it."
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
