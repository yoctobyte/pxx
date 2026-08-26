---
track: U
prio: 40
type: decide
blocked-by: []
summary: "typinfo.pas declares TTypeKind in FPC's order (tkInt64=19) but the RTTI blob the compiler emits carries the COMPILER's TTypeKind (tyInt64=13), so `if mi^.RetKind = Ord(tkInt64)` is silently false. Three ways out; they differ in whether the RTTI blob's numbering — a compiler ABI — changes. Recommendation: option 2. Needs a human call because option 1 breaks already-compiled consumers and option 2 spends the FPC-compatibility argument the FPC-ordered enum was added for."
---

# Which numbering do the RTTI kind fields carry?

- **Type:** decision (Track U) — the fork inside
  [[bug-a-rtti-kind-numbers-are-the-compilers-not-the-typinfo-enum-the-unit-documents]]
- **Status:** decided
- **Opened:** 2026-08-22

## Why this is here and not just done

The bug ticket is fully diagnosed and even carries a recommendation, so it looks
ready to pick up. It is not, and the reason is worth stating: **the RTTI blob's
kind numbering is an ABI.** Option 1 changes the bytes a compiled program's RTTI
section contains, so every already-compiled consumer — including anything a user
built with a pinned pxx — starts reading a different meaning out of the same
field, with no diagnostic. That is the exact silent-wrong-value class this repo
pays most for, and it is not a call an agent should make from the code alone.

Escalated per the Track U rule rather than guessed at.

## The fork

Full measurement, the self-contradiction inside `typinfo.pas`, and the
trade-offs are in the bug ticket. In one line each:

1. **Emit FPC's numbering** — map in `rtti_emit.inc`. Best FPC-source
   compatibility; **breaks the RTTI ABI** and needs a sweep of every reader
   (`TypeKindSize`, `TypeKindSigned`, the pyexec bridge, both RTTI tests).
2. **Keep the compiler's numbering, stop calling it `TTypeKind`** — declare
   `TPxxTypeKind` with the compiler's order, retype the RTTI fields to it, fix
   the three doc comments. No ABI change, no reader sweep; leaves FPC-source
   `array[TTypeKind] of X` working. Cost: the two enums stay adjacent in one
   unit, which is how the confusion happened.
3. **Both, plus converters** — most code, deletes the fewest cases.

## Recommendation

**Option 2**, carried over from the bug ticket and unchanged after review: the
value of matching FPC here is small — nobody ports FPC code that reads *our*
method-RTTI blob — while `array[TTypeKind] of X` is common and option 2 leaves
it alone. Option 1 spends an ABI break to buy compatibility for a case that
does not occur.

The one thing that would flip it: if the RTTI blob is ever meant to be read by
FPC-built code, or by a tool that also reads FPC's, then the numbering must be
FPC's and the ABI break is worth taking **now**, while the set of compiled
consumers is small.

## Once decided

Re-file as plain work in Track A (the emit side) with the `lib/rtl/typinfo.pas`
half noted for Track B; U holds the open question, not the work.

---

# DECIDED 2026-08-25 — **option 1: the blob carries FPC's numbering**

Decided by an agent under the no-human-available rule (see
`devdocs/progress/decided/README-agent-decisions.md`). Recorded as a
**derivation**, not a preference, because the measurement below removes the
objection the ticket was escalated on.

## The premise that does not hold

The whole case for option 2 rests on one sentence: *"the RTTI blob's kind
numbering is an ABI ... every already-compiled consumer — including anything a
user built with a pinned pxx — starts reading a different meaning out of the
same field."*

Measured, `compiler/pasparser_prog.inc:565`:

> *"whole-program compiler with no .ppu model"*

**There is no separate compilation.** A program's RTTI blob is emitted by the
same compiler run that links the `lib/rtl/typinfo.pas` which reads it. A
consumer cannot be older than its emitter, so there is no cross-version ABI to
break — only an in-tree reader sweep, and the ticket already enumerates it
(`TypeKindSize`, `TypeKindSigned`, the pyexec bridge, both RTTI tests). A user's
already-built binary keeps working because its bytes and its reader shipped
together and neither is being rewritten.

Option 2's entire cost advantage was avoiding a break that cannot occur.

## The principle that then settles it

`normalise-dont-special-case.md`: *"When the frontend can reach a construct
through two shapes ... Resist it. Normalise the special shape into the general
one ... it is a way of having **one** thing to get right instead of two that
must stay in step."* And `root-cause-over-microfix.md`: *"Count the mechanisms
serving one concept. Two is a smell."*

Option 2 keeps **two numberings alive in one unit** and renames one so the
collision is quieter. That is the smell, preserved with better labelling — and
the ticket says so itself: *"the two enums stay adjacent in one unit, which is
how the confusion happened."* Option 1 deletes one of the two.

## And the machinery already exists

`compiler/rtti_emit.inc:811` already has `PxxTkToFPCKind`, and
`EmitTypeInfoHeaders` already calls it: a `TypeInfo()` header's Kind word is
**already** emitted in FPC's numbering (`tkClass` is hard-coded to 15 at
`rtti_emit.inc:896`). So the compiler already commits to FPC's numbering on the
half of the RTTI surface that a user sees through the facade, and the method/
field blob is the half that was left behind. Option 1 is not a new policy — it
is finishing one that is already half-applied, which is why the two numberings
were confusable in the first place.

## The line this draws, and it governs three tickets

**The typinfo/variants FACADE speaks FPC's public numbering; the compiler's
internal tags stay ours and stay private.** `PxxTkToFPCKind` is the seam. That
same line answers `decide-classinfo-*` and `decide-vartype-returns-pxx-tags-not-fpc-codes`,
which were three spellings of one unstated question.

## Re-filed as work

Track **A** (emit side) with the `lib/rtl/typinfo.pas` half noted for Track B —
`bug-a-rtti-kind-numbers-are-the-compilers-not-the-typinfo-enum-the-unit-documents`
is now unblocked and carries the work. Its fix is: route `RetKind`,
`TypeKind` and the `ParamKinds` words through the existing `PxxTkToFPCKind`,
then sweep the four in-tree readers, then fix the three doc comments in
`typinfo.pas`. `TTypeKind` keeps its name and its FPC order; no `TPxxTypeKind`
is introduced.

## Log
- 2026-08-25 — decided, commit 28c19f214.
