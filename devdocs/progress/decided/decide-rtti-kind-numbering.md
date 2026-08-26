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

---

# RE-DECIDED 2026-08-26 — **option 3: the blob keeps pxx numbering, the unit names it and bridges it**

Decided by an agent under the same no-human-available rule. The 2026-08-25
record above stands as written; it is superseded, not deleted, because its
*derivation* was sound and only its *premise about the readers* was incomplete.

## What the 2026-08-25 decision did not measure

It priced the reader sweep as "`TypeKindSize`, `TypeKindSigned`, the pyexec
bridge, both RTTI tests" — four mechanical edits. Measured, it is ~40 sites in
`compiler/builtin/pylib.pas` and `compiler/builtin/pyeval.pas`, and, decisively,
**they are not type-identity tests. They are ABI trampoline selection.**

`lib/rtl/typinfo.pas:279` says so in the unit itself:

> *"Code + Arity + RetKind + ParamKinds, what the generic native-call
> trampoline needs."*

- `pyeval.pas:294` `TK_DOUBLE = 19` = `Ord(tyDouble)`, and
  `if (rk = TK_DOUBLE) and (n = 0)` casts `mi^.Code` to a **Double-returning**
  proc pointer (`TFpopFn`) — an xmm-return ABI.
- `pyeval.pas` `ptrFamily` accepts exactly `1, 2, 3, 13, 17, 6, 23`
  (tyInteger, tyBoolean, tyChar, tyInt64, tyPointer, tyClass, tyAnsiString):
  the **pointer-sized integer-register** class, and rejects everything else with
  a named diagnostic.
- `pylib.pas:4196` and `:18241-18260` pick between `TVarArgI` / `TVarArgD` /
  `TVarArgS` / `TVarArgB` / `TVarArgV` / `TVarArgO` the same way.

## Why option 1 cannot be implemented as instructed

`PxxTkToFPCKind` is **lossy in exactly the distinctions the trampoline runs on**,
because FPC's kind space is coarser than an ABI selector needs — FPC carries
width and float precision in `TTypeData` (`TOrdType` / `TFloatType`), not in the
kind word.

1. `tySingle`, `tyDouble` and `tyExtended` all map to `4` (tkFloat). A
   0-arg Single-returning host method would then be called through a
   Double-returning pointer: the callee leaves 32 bits in xmm0, the caller reads
   64. Today `rk = 19` means tyDouble and nothing else, and Single is correctly
   declined. **No value of the FPC-numbered field can separate them.**
2. `TypeKindSize` / `TypeKindSigned` answer *width and sign* from the kind word,
   and `SetOrdProp` (`typinfo.pas:515`) uses that width to choose
   `PUInt8^ / PUInt16^ / PInt32^ / PInt64^` **for the store**. FPC's `tkInteger`
   (1) covers ShortInt, Byte, SmallInt, Word, LongInt and LongWord — 1, 2 and 4
   bytes, signed and unsigned. Under option 1 a published `Byte` property is
   written 4 or 8 bytes wide: adjacent-field corruption, silently.
3. Everything not in the table maps to `0`, and `pylib.pas:4635` reads
   `mi^.RetKind <> 0` as *"is a function"*. Any unmapped return type silently
   becomes a procedure and its result is dropped.
4. The two numbering spaces **overlap with different meanings** on 1, 2, 11, 15,
   18 and 19 (pxx 15 = tyNativeInt vs FPC 15 = tkClass; pxx 2 = tyBoolean vs FPC
   2 = tkChar; pxx 19 = tyDouble vs FPC 19 = tkInt64). A missed reader in a
   ~40-site sweep does not fail loudly — it selects the wrong ABI.

So option 1 buys a true doc comment at the price of the silent-wrong-value class
the ticket was opened to remove, and it would need a width/precision sub-field
added to `PMethInfo`, `PFieldInfo` **and** `PPropInfo` to be implementable at
all — *adding* a mechanism where the 2026-08-25 derivation expected to delete one.

## A fourth field the earlier passes missed

`TPropInfo.OrdType` (`typinfo.pas:234`) is a *fourth* kind word in pxx numbering
— it is what `GetOrdProp`/`SetOrdProp` feed to `TypeKindSize`. Neither the bug
ticket nor the 2026-08-25 decision names it. Any "route the three words through
`PxxTkToFPCKind`" edit would have left it behind, in a field that decides how
many bytes a reflective store writes.

## The line, restated so it actually holds

The 2026-08-25 line was right and is kept: **the typinfo facade speaks FPC's
public numbering; the compiler's internal tags stay ours and stay private.**
What it got wrong is *where the seam sits*. `RetKind` / `ParamKinds` /
`TypeKind` / `OrdType` are **not** facade — the unit's own comment says they are
what the native-call trampoline needs. They are the private half. The facade is
`TypeInfo()`'s `TTypeInfoHdr.Kind` and `GetTypeData`, which already speak FPC's
numbering and are untouched.

So the seam is a **converter at the read boundary**, not a conversion at emit.

## The work

1. `lib/rtl/typinfo.pas` — a named `pxxTk*` constant block declaring the
   compiler's numbering as what it is, so the raw fields are spellable
   (`mi^.RetKind = pxxTkInt64`) instead of only mis-spellable.
2. `PxxKindToTypeKind()` — the read-side twin of `PxxTkToFPCKind`, so
   `PxxKindToTypeKind(mi^.RetKind) = Ord(tkInt64)` is correct and the two halves
   of the unit are relatable. The duplicated table is deliberate and
   cross-referenced both ways: emit-side lives in the compiler binary, read-side
   in every user program; they cannot share a source.
3. Fix the doc comments that assert `Ord(TTypeKind)` — `:44`, `:45`, `:60`,
   `:234`, `:279`, `:816` — and say, at `TypeKindSize`/`TypeKindSigned`, that
   decoding the compiler's numbering there is deliberate and why.
4. `TTypeKind` keeps its name and its FPC order, unchanged. No enum is added
   (constants, not a second `array[TPxxTypeKind]`-shaped enum, so the
   "two adjacent enums" smell the 2026-08-25 note objected to does not return).

## Log
- 2026-08-25 — decided option 1, commit 28c19f214.
- 2026-08-26 — **re-decided option 3**; option 1 measured unimplementable
  without new width fields, see above.
