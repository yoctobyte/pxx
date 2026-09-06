---
slug: bug-p-a-class-helpers-class-method-is-refused-by-the-record-metaclass-rule
title: "a class helper's `class function` is refused by the RECORD metaclass rule, and the message calls the helper a record"
track: P
prio: 40
type: bug
status: working
owner: frankB
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

## Resolution — all three layers, and layer 3 was not a design question

frankS's three-layer analysis is what made this tractable, and layers 1 and 2
landed exactly as written. **Layer 3 was misdiagnosed, and the correction is the
transferable part.**

**Layer 1 — the declaration.** `pasparser_decl.inc`'s terecs5 guard now reads
`RecordMethodClassPrefix and not rmSawStatic and (UClsHelperTk[ci] <>
Ord(tyClass))`. The rule is about the TARGET, not about which parser is running:
`class helper for T` is parsed by the advanced-record member machinery because a
helper lives in the UCls tables with `UClsIsRecord` set, and its target is a
class, which HAS a metaclass. `record helper` and `type helper for LongInt` stay
refused, since neither of those targets has one either.

**Layer 2 — the metaclass lookup.** The `TA.Other` path in `pasparser_lval.inc`
was the THIRD member-lookup loop and the only one that never asked
`ClassHelperRecFor` — whose own note says it exists so a redirect cannot drift
between the two that do. It asks now, and keeps `hostCi`, the class the call was
spelled on.

### Layer 3: what `Self` is, and why the ticket could not see it

The ticket parked here, calling it a design question — *"which metaclass a class
helper's class method receives, and where it comes from at the call site"*. It
is not a fork. **Delphi's answer is that `Self` is the class reference the call
was SPELLED on**, and both halves of this compiler already knew how to carry
that:

- the metaclass receiver is already an `AN_CLASSREF` over a class index (the
  class-property arm, same file);
- an ordinary class method already types `Self` as `tyPointer` / `REC_NONE`
  (`pasparser_proc.inc`: *"class method: Self is the metaclass -- a class
  reference"*).

**The real defect is one level below where the ticket looked.** With layers 1
and 2 in, the call reached the body and crashed — the `Runtime error 216` the
ticket records, a segfault here. The cause is that a class helper's `Self` was
typed as a TARGET INSTANCE on both the decl and impl sides, so the class
reference passed at the call site is read as an object and `Self.ClassName`
fetches a VMT word from inside the RTTI blob. Forking both sides to the
metaclass when `UClsHelperTk = Ord(tyClass)` fixes it; they must be forked
TOGETHER or the impl never binds, which is the b321 lesson this file already
records twice.

frankS's own reading of the mislabel, which is better than mine: **"this needs a
decision" is a comfortable place to stop, and it is indistinguishable from "I
have not found the cause yet" right up until someone finds it.**

## Measured

`fpc -Mobjfpc` 3.2.2's own output, byte for byte:

```
A 1   the class's own method             E TA   Self is the SPELLED class
B 2   the helper's INSTANCE method       F TD   ...and TD here, not TA
C 3   the helper's CLASS method          G 2    instance path on the descendant
D 3   ...through a descendant's name
```

**ROWS E AND F ARE THE TEST AND C/D COULD NOT HAVE FOUND IT.** `Other` returns a
literal, so a fix that hard-wired the helper's target prints `3` for both C and D
and passes — an expected value colliding with what doing nothing produces, in a
file named for the feature. `ClassName` is the cheapest probe whose answer
differs per receiver.

## The rule was asserted nowhere, and that is a finding of its own

`a class method of a record must be declared static` appeared in no Makefile
assertion and no test — grepped both. **Narrowing it, or deleting it outright,
would have been invisible.** frankS's note: *a rule with no assertion is not a
rule; it is a comment that happens to be executable.*

`test_a_class_method_still_needs_static_where_there_is_no_metaclass` asserts it
for the three targets that genuinely have no metaclass — a plain record, a
`record helper`, a `type helper for LongInt` — one row per compile via
`-dROW_A/B/C` because `Error()` halts, plus a no-row build that must compile AND
run so the three greps cannot be reading an unrelated error.

Every existing helper test still passes: `test_class_helper_for_a_class`,
`test_type_helper_{const_array,for_spelling,on_a_value,property,typename_receiver}`,
`test_record_helper_for_string_b331`, `lib_string_helpers`.

## Not inherited: the 9 corpus rows

The ticket's `--all` census found 9 rows sharing this diagnostic and says
explicitly that whether they share the CAUSE is not established — only
`tgenfunc19.pp` was read. That number is not claimed here and this ticket closes
on its own construct.

**Gate:** `tools/gate.sh quick` with the tree DIRTY (16 PASS incl. the FPC seed
canary; the only RED is `pinned builds live lib/rtl`, frankZ's `8374118ec`
waiting on an owner-only pin) AND `PXX_ALLOW_FULL_SUITE=1 make test` — the
change alters how `Self` is typed for a whole method class, and the quick tier
has no class helper in it.
