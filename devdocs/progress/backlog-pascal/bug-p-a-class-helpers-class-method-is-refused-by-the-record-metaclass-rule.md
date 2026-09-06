---
slug: bug-p-a-class-helpers-class-method-is-refused-by-the-record-metaclass-rule
title: "a class helper's `class function` is refused by the RECORD metaclass rule, and the message calls the helper a record"
track: P
prio: 40
type: bug
status: backlog
owner: ""
blocked-by: []
summary: "MEASURED 2026-09-06 at 67d173f13, compiler 98b6693be7f5. `TH = class helper for TA` with a non-static `class function Other: LongInt` is refused at the DECLARATION with `a class method of a record must be declared static` (pasparser_decl.inc:4357). fpc 3.2.2 -Mobjfpc compiles it and prints its result. TWO DEFECTS IN ONE LINE: the rule is CORRECT for records and for `type helper for <scalar>` -- neither has a metaclass, and terecs5 asserts it -- but ParseRecordMethodDecl also parses the members of a `class helper for T`, whose target IS a class and DOES have one; and the message tells the reader their class helper is a record. Adding `static` makes it compile, so the workaround hides the bug. WIDTH: 9 rows in the full 1362-file corpus fail on exactly this diagnostic (from the --all diag census), all in the helper cluster (182 files, 68 pass, 113 fail -- the corpus's largest). One curated skip row, tgenfunc19.pp, whose reason blames `generic global function + class helper method resolution via specialize` and never reaches either: it stops at line 15 on this. I ATTEMPTED THE FIX AND PARKED IT AT THE THIRD LAYER, which is why this is filed rather than landed -- each layer was measured, not predicted."
---

## What the fix actually needs — three layers, measured one at a time

**Layer 1, the declaration.** Guard the rule on the helper's TARGET, not on the
helper flavour: `UClsHelperTk[ci]` is set to the extended type's kind before
`ParseRecordFields` runs, so `and (UClsHelperTk[ci] <> Ord(tyClass))` admits a
class helper while leaving `record helper` and `type helper for LongInt`
refused exactly as terecs5 requires. Verified: the declaration is accepted.

**Layer 2, the metaclass lookup.** `TA.Other` then answered `class method not
found (Other)`. `ClassHelperRecFor` is the one resolver the two INSTANCE
member-lookup loops ask — its own note in symtab.inc says it exists so a
redirect cannot drift between them — and the METACLASS path in
`pasparser_lval.inc` (~1333) is the third loop that never asked it. Adding the
call there resolves the member. Verified.

**Layer 3, and this is the wall: WHAT IS `Self`?** With the member resolved,
the call reaches the body and dies with `Runtime error 216 (nil reference)`.
The class-helper decl note says both sides key Self off the TARGET kind, so an
instance call passes the instance pointer — but a `class function` wants the
METACLASS, and the helper row itself is `UClsIsRecord = True` with no VMT. The
existing arm "passes a by-value dummy Self because a helper has no metaclass",
which is right for an instance helper and is what produces the nil here.

So layer 3 is a design question — which metaclass a class helper's class method
receives, and where it comes from at the call site — not another guard to
widen. That is the whole reason this is a ticket.

## The trap for whoever takes it

**Layers 1 and 2 alone make it WORSE, not partly better.** They convert a clear
refusal at the declaration into `Runtime error 216` at the call: a wrong
VALUE-shaped failure, far from the cause, replacing an honest diagnostic.
Do not land them without layer 3. (frank-coordinator's framing, same day:
narrowing an over-broad guard is not one-sided — the rows it stops refusing
have to land somewhere, and that is only correct if the code they now reach
exists.)

**And the 9 rows are the WIDE set**, from the full 1362-file corpus, not the
curated 550 — do not compare that number to a curated one. Whether all nine
share this cause beyond the diagnostic is NOT established; only tgenfunc19.pp
was read.
