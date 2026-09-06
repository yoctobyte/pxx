---
track: P
prio: 45
type: refactor
blocked-by: []
status: done
owner: frankB
created: 2026-09-06
summary: "\"Is this node a whole array?\" was said to be answered in four places with four predicates. CENSUS TAKEN 2026-09-06 (frankB, with frankD's handover) AND IT CORRECTS THE PREMISE: there are THREE QUESTIONS and one duplicated predicate, not four answers to one. (1) is this lvalue a whole array of any kind -- `ASTNodeIsWholeArray`, spelled inline as `Syms[].IsArray` in AssignSideKind's AN_IDENT arm; (2) how many DYNAMIC levels remain -- `NodeDynDepth`; (3) is this a fixed-length NON-PARAMETER array symbol -- the fixed-to-dynamic guard, whose own comment records that `ArrLen > 0` does not mean fixed because AllocParam stamps 1000 on every array parameter. frankD's measured cell (a static array FIELD: WholeArray True, DynDepth 0) is questions 1 and 2 each answering CORRECTLY. A single predicate cannot serve all three and merging them is the mistake. LANDED: the AN_IDENT arm asks `ASTNodeIsWholeArray` (same answer, one name) and that reader gained the AN_DEREF arm via `DerefPtrArrayShape` -- MEASURED INERT for its sole caller and recorded as inert. The field arm was deliberately NOT merged: frankD chose `NodeDynDepth` because it already types six node classes, and merging toward `ASTNodeIsWholeArray` would narrow it to two. WHAT THE CENSUS FOUND INSTEAD: every whole-array assignment DESTINATION is unchecked in all four spellings and two of them SIGSEGV, because a bail in AssignSideKind means \"cannot type this\" and the funnel then stands down -- filed as bug-p-a-whole-array-assignment-destination-is-never-type-checked, a narrowing that needs its own evidence. Empty cells left named: the PARAMETER row, and a suspected fifth reader (`RecIsReferenceShaped` beside the field bail)."
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

## The census, and it corrects this ticket's own framing — 2026-09-06 (frankB), compiler `aa8f3c3b4b68`

**There are not four answers to one question. There are THREE questions and one
duplicated predicate**, and once they are named the "measured disagreement" in
this ticket stops being one.

| # | question | who asks it |
| --- | --- | --- |
| 1 | is this lvalue a **whole array**, of any kind? | `ASTNodeIsWholeArray`; and `AssignSideKind`'s AN_IDENT arm, which spelled the same test inline as `Syms[].IsArray` |
| 2 | how many **dynamic** `array of` levels remain? | `NodeDynDepth`; `AssignSideKind`'s element/field/deref arm asks `> 0` |
| 3 | is this a **fixed-length, non-parameter** array symbol? | the fixed→dynamic guard's four conjuncts |

frankD's cell — a static array FIELD answers True to `ASTNodeIsWholeArray` and 0
to `NodeDynDepth` — is question 1 and question 2 each answering **correctly**.
Neither is wrong; they are different questions. Question 3 is a third: its own
comment records that `ArrLen > 0` does NOT mean fixed-length, because
`AllocParam` stamps 1000 on every array parameter, so `Kind <> skParam` is the
property that separates them. A single predicate cannot serve all three, and
merging them is the mistake, not the fix.

### What IS wrong at that site, and it is not what this ticket predicted

`AssignSideKind`'s AN_IDENT arm asks question 1 and its element/field/deref arm
asks question 2, **at the same decision point**. But a bail there means *"I
cannot type this side"*, and the check then STANDS DOWN — so the arms do not
disagree about the outcome, they agree on it:

```pascal
type TSA = array[0..2] of AnsiString;
var sa: TSA; s: AnsiString; c: TC;  { c.SA: TSA; c.DA: array of AnsiString }
  sa   := s;    pxx ACCEPTED, SIGSEGV     fpc: Incompatible types
  c.SA := s;    pxx ACCEPTED, SIGSEGV     fpc: Incompatible types
  p^   := s;    pxx ACCEPTED, exit 0      fpc: Incompatible types
  c.DA := s;    pxx ACCEPTED, exit 0      fpc: Incompatible types
```

**Every whole-array destination is unchecked, in every spelling, and two of the
four segfault.** Filed as
[[bug-p-a-whole-array-assignment-destination-is-never-type-checked]] — it is a
NARROWING (the funnel would start refusing programs it accepts today) and it
needs its own evidence, not a refactor's.

### What landed here

1. `AssignSideKind`'s AN_IDENT arm asks `ASTNodeIsWholeArray(node)` instead of
   spelling `Syms[si].IsArray` inline. Byte-identical answer for AN_IDENT; one
   name for question 1.
2. `ASTNodeIsWholeArray` gained the **AN_DEREF** arm via `DerefPtrArrayShape`
   (Group 28's own generalisation). Its opening sentence says "this lvalue node"
   and `p^` on `^array[0..2] of T` or `^TDyn` is a whole array — the element is
   `p^[i]`, an AN_INDEX, which already falls out.

**MEASURED INERT, AND RECORDED AS INERT RATHER THAN CREDITED.** The sole caller
is the `X := nil` lowering, and `p^ := nil` through a pointer to a dynamic array
of records answers `len=0` byte-for-byte with fpc 3.2.2 with a live handle AND
with an already-nil one — the two shapes that produced the SIGSEGV that function
was written for. Another arm catches it. The arm is here because the QUESTION has
a right answer for a deref and this reader owns the question, not because a row
moved.

### The cell that is still empty, and it is not empty by accident

Nothing here measured a **parameter**. Question 3's whole existence is that a
parameter's recorded length is untrustworthy in both directions
(`AllocParam` stamps `ArrLen := 1000`), so a param row would be the most
informative cell of all — and the fixed→dynamic guard already excludes it by
name for that reason. Whoever picks up the narrowing above should start there.

### Gate

`make compiler/pascal26` converged; `--tier quick` GREEN; `run_fgl_corpus.sh`
7/7; the four `:= nil` deref/field probes byte-identical to fpc 3.2.2 before and
after.

### frankD's handover, and it settles the shape rather than adding detail

Asked for it before starting, per this ticket's own instruction. Three answers,
and the second is the one that decides what NOT to do:

**`NodeDynDepth` in the field arm was CHOSEN, and the reason is in the code
rather than in this ticket** — `ir.inc`, immediately above the bail: *"it already
types AN_FIELD, AN_INDEX and AN_DEREF (and calls, and Copy, and array
constructors), and a second derivation here would be a second answer to a
question already answered."* So the constraint on any unification is **not**
"agree with `ASTNodeIsWholeArray`" — it is *be the walk that already types calls,
Copy and array constructors*. **Merging that arm toward `ASTNodeIsWholeArray`
would narrow it from six node classes to two** and lose shapes it never had a bug
in. It was left exactly as it is, and the AN_IDENT arm is the only one that
changed.

**Two predicates, not one**, independently reached from both ends: frankD's cell
is the proof rather than an example, because both answers are correct. Merging
four readers into one has to pick one of the two and would silently hand the
wrong one to two of the four callers.

**A suspected FIFTH reader, unfilled and flagged as unfilled:** the field arm
bails on `NodeDynDepth > 0` before asking `RecIsReferenceShaped(rec)`, which is a
neighbouring question about the same node, and whether the two can disagree was
never probed. Treat it as an empty cell, not a checked one.

**The naming trap is live in this very function** and is the coordinator's
`SymBlockId` shape one file over: `ASTNodeIsWholeArray` promises the general
question and answered it for AN_IDENT only until this morning, then AN_IDENT and
AN_FIELD, and reads as the general one at every call site regardless. The
AN_DEREF arm added here closes the third of five node classes; AN_INDEX is
correctly False, and a CALL returning an array is the one still unanswered.

**And frankD's own cell is a weak green, by their own account:** `c.SA := b`
matches fpc both ways, measured as an OUTPUT comparison on x86-64. Anything here
whose answer is a width or a layout is invisible to that — the structurally
native-only blind spot CLAUDE.md names.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
