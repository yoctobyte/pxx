---
slug: feature-p-a-generic-method-cannot-be-used-from-across-a-uses-clause
title: "A generic method works in one file and not across a uses clause, because the use sits behind the declaration in the token stream"
track: P
prio: 30
type: feature
blocked-by: []
status: backlog
owner: ""
created: 2026-09-05
summary: "ExpandGenericMethod rewrites a generic method into one ordinary method per concrete type argument, and every edit it makes is at or ABOVE the class body. A program calling a USED UNIT\'s generic method is the shape where a use sits BELOW the declaration -- unit tokens are appended after the program\'s -- so the expansion bails out whole and the row still reports the old parse error. tgenfunc7 and tgenfunc9. The free ROUTINE already solved this, at the uses clause; the method needs the same move plus TokPos and DeclItem-span bookkeeping the routine did not."
---

# The shape

`0ee1e272f` made a generic method work in one file, both surfaces, instance and
class. It does that by rewriting the declaration, the definition and every use
into one ordinary method per concrete type argument, in the token stream,
before the class-body parser sees any of it.

Every one of those edits is at or above the class body, and the expansion
**bails out whole** if any use site sits below it. That is deliberate: a
removal behind `TokPos` invalidates `TokPos` and every `DeclItem` span already
recorded, and `AdjustPass2Spans` is a no-op outside the body pass, so a
half-rewrite would be worse than the parse error.

A use below the declaration is not exotic — it is what a program calling a used
unit's generic method looks like, because **a unit's tokens are appended after
the importing program's**. `tgenfunc7` and `tgenfunc9` are that shape and stay
skipped, with the reason on their `pxx.skip` rows.

# The precedent, and where it stops being one

The free ROUTINE has exactly this problem and solved it:
`SpecializeImportedGenericFuncUses` re-runs the sweep from the END OF THE USES
CLAUSE, *"the one site where 'every template this clause just imported is
registered, and every use of one lies ahead of here' is true"* — the same site
`DesugarImportedDelphiGenericUses` uses for the class side.

The method cannot simply borrow it. The routine sweep only REWRITES uses and
splices a body at the cursor; the method expansion also has to edit a CLASS BODY
that was already parsed, and the class is in the unit, behind the program. So
the shape is probably: register the generic method at class-parse time without
expanding, then expand at the uses clause the way the routine does — which
means the class needs to gain members after its body closed, and that is the
part nobody has measured.

# What to measure first

Whether a class can gain a method after `ParseTypeSection` has closed its body.
If it can, this is the routine's fix applied to a second lane. If it cannot, the
answer is probably to defer the whole class body rather than to expand in place,
and the estimate is very different. One afternoon either way, and it decides the
design.

# Gate

`tgenfunc7` and `tgenfunc9` compiling, each **diffed against fpc 3.2.2 output**
rather than scored on its exit code, plus the conformance fail list read BY
NAME (this area turns `%FAIL` rows red — `tgeneric31` and `tgenfunc14` both did
during the parent ticket), plus `make test` and the self-host fixedpoint.
