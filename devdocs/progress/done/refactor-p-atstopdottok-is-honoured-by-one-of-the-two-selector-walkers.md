---
slug: refactor-p-atstopdottok-is-honoured-by-one-of-the-two-selector-walkers
title: "AtStopDotTok is read by ParseClassRecordSelectors and ignored by ParseLValueAST, so every caller carries a hand-written receiver route for the symbol-rooted case"
track: P
prio: 35
type: refactor
blocked-by: []
status: done
owner: frankD
created: 2026-09-08
summary: "DONE 2026-09-09. ParseLValueAST now reads AtStopDotTok, so all three stop-setting sites call ParseFactor and the symbol-root/class-name-root split is gone -- one fact about the walkers, encoded once. FIRST STEP ANSWERED, and the answer is NOT the ticket's: the two walks are NOT the same job. ParseLValueAST's loop is a SUPERSET -- it walks `[`, `.` and `^`, where ParseClassRecordSelectors walks `[` and `.` -- so the guard is written on the DOT only (`(CurTok.Kind <> tkDot) or ...`), which a bare copy of the other head would have got wrong by stopping the caret walk too. The second candidate loop in that file is in CompileLValueAddressInternal, a legacy DIRECT-EMIT path (it calls EmitB) and not an AST walk at all; it is not in this ticket's population. AND THE TICKET'S NAMED POSITIVE CONTROL DID NOT EXIST: it says both rows are already in test_delphi_parenless_methodref_chained_receiver.pas, and the FIELD-link row was not -- rows 4/5 reach the second link through a method CALL. Added rows 6/7 (`g.Inner.Foo` bind, `g.Inner.Bar` rewind) and confirmed them GREEN BEFORE the deletion, so a break could be told from a never-worked. Five selector/methodref fixtures green; gate GREEN; defs.inc's `-1 on every path but the one @ arm` corrected to the three arms that set it, which is what makes safe-by-construction checkable."
---

# The fact, and how it presents

Measured 2026-09-08 while fixing
`bug-p-a-delphi-parenless-method-reference-cannot-have-a-chained-receiver`.
The trial arm called `ParseFactor` for every receiver shape, and:

```
TG.F := TG.Create.Foo    class-name root -> ParseFactor's other route -> works
TG.F := g.Mk.Foo         symbol root     -> ParseLValueAST            -> walks past the stop
TG.F := g.Inner.Foo      symbol root, FIELD link                      -> same
```

The third row is the one that names the cause: a field link and a method-call
link fail identically, so the discriminator is the **root**, not the link. The
symptom is not a stop failure — it is `wrong number of parameters in call to
TG.Foo`, because the walk consumed the method name and the ordinary parse then
read it as a call. **A defect in the caller's shape reported as a defect in the
callee's arity.**

# The four sites

- `pasparser_expr.inc` ~1180 — the `@a.b.Foo` arm: hand-builds `AN_IDENT` and
  calls `ParseClassRecordSelectors`, and its comment explains the value and the
  reference "end at different places". Symbol root.
- `pasparser_expr.inc` ~1424 — the class-type sibling: *"the value half here is
  an ordinary factor, so it is parsed by the ordinary factor path rather than by
  a fourth hand-rolled walk"*. Class-name root, `ParseFactor`.
- `pasparser_call.inc`, `TryParseParenlessMethodRef` — both of the above, in one
  arm, because a trial has to handle either root.

The second bullet's comment is the tell: it congratulates itself on not adding a
fourth hand-rolled walk, and it is right — the duplication is not the walk, it
is the **route selection** around it.

# Why it is a refactor and not a bug

Every caller is correct today, and the fix that produced this note added the
route rather than fixing the walker precisely because the wider change is not
this ticket's risk to take. Nothing observably differs — *for the callers that
exist*, which is the qualifier that makes this a refactor rather than a
measurement.

# The change

Add `and ((AtStopDotTok < 0) or (TokPos - 1 <> AtStopDotTok))` to
`ParseLValueAST`'s selector continuation, then delete the symbol-root route from
all three callers and let `ParseFactor` serve both.

**It cannot regress a path that does not set the flag**: `AtStopDotTok` is `-1`
everywhere else, which its own declaration in `defs.inc` says. That comment
currently claims it is `-1` on every path but the `@a.b.Foo` arm — already stale,
since the parenless arm sets it too. Fix that line in the same commit.

## Positive control

Not "the three method-reference tests still pass" — they pass today. Assert that
a symbol-rooted receiver STOPS: after the change, the hand-written route deleted,
`TG.F := g.Inner.Foo` must still bind and `n := g.Inner.Bar` must still call.
Both rows already exist in
`test/test_delphi_parenless_methodref_chained_receiver.pas`, which is what makes
this cheap to attempt.

# Before unifying: check whether the second walker is ignoring the flag or doing without it on purpose

frankS, 2026-09-08, from the version of this it got wrong the same morning: it
put a strip ahead of a probe, correct for the case measured, and it broke two
tests because **the other walker did something extra it had not read** — that
copy REWROTE the name rather than only consuming the qualifier. *"The two
walkers were not merely inconsistent; they were doing different jobs."*

So the first step of this ticket is not the one-line guard. It is establishing
that `ParseLValueAST`'s selector handling is the SAME job as
`ParseClassRecordSelectors`' and merely lacks the stop — rather than a different
job that happens to look alike at the call site. If it is the second, the fix is
not to teach it the flag.

frankS also ranks this above 35 on the evidence that two of its three fixes that
day were the same animal — one rule, two walkers, one of which never learned it.
Left at 35 rather than re-ranked from outside; noted here so whoever picks it up
has the argument.


## Done — 2026-09-09 (frankD)

`ParseLValueAST`'s selector loop now carries the stop test, and all three
stop-setting sites are the same three lines — set the stop, `ParseFactor`, clear
it:

- `pasparser_expr.inc` ~1246, the `@a.b.Foo` arm (was: hand-built `AN_IDENT` +
  direct `ParseClassRecordSelectors`)
- `pasparser_expr.inc` ~1455, the class-type sibling (already `ParseFactor`)
- `pasparser_call.inc` ~1850, `TryParseParenlessMethodRef` (was: both routes in
  one `if`)

### The first step, which the ticket said to do before the guard

frankS's warning was to establish that the two walks are the SAME job rather
than two jobs that look alike at the call site. **They are not the same job, and
the difference changes the patch.** `ParseLValueAST`'s loop head is
`[tkLBrack, tkDot, tkCaret]`; `ParseClassRecordSelectors`' is `[tkDot,
tkLBrack]`. The first is a superset — it also walks pointer dereference. So the
guard is written on the DOT specifically:

```pascal
while (CurTok.Kind in [tkLBrack, tkDot, tkCaret]) and
      ((AtStopDotTok < 0) or (CurTok.Kind <> tkDot) or
       (TokPos - 1 <> AtStopDotTok)) do
```

Copying the other walker's head verbatim — the change as the ticket words it —
would have stopped the `^` walk at a token index that can never be a caret,
which is harmless today only because the two never co-occur at that index. The
narrow form says what is meant.

The other `while CurTok.Kind in [tkLBrack, tkDot]` in that file is in
`CompileLValueAddressInternal`, a legacy path that emits machine code directly
(`EmitB($50)`) rather than building AST. Not a walker in this sense and not
touched.

### THE NAMED POSITIVE CONTROL DID NOT EXIST

The ticket says *"Both rows already exist in
test/test_delphi_parenless_methodref_chained_receiver.pas, which is what makes
this cheap to attempt."* The bind row for a **field** link did not. Rows 4 and 5
reach the second link through a method CALL (`g.Mk.Foo`, `g.Mk.Bar`); nothing
reached it through a plain field, which is the shape the ticket itself names as
the one that identified the ROOT rather than the LINK as the discriminator.

Added as rows 6 and 7 — `TG.F := g.Inner.Foo` (bind) and `n := g.Inner.Bar`
(rewind) — and **run green BEFORE the route deletion**, so a failure afterwards
could be read as a break rather than as a row that never worked. `.expected` is
fpc 3.2.2's own output on the extended file.

### Verification

`test_a_method_pointer_can_be_taken_through_a_chain_of_selectors` (the `@` arm's
own control: `@o.Inner.Foo`, `@g.Mk.Foo`), `test_at_over_a_class_base_walks_every_selector`,
`test_delphi_parenless_methodref_chained_receiver`,
`test_a_procedural_member_is_callable_through_a_selector_chain` and
`test_method_pointer_arg_b361` — all GREEN. `tools/gate.sh quick` GREEN,
fixedpoint converged.

`defs.inc`'s declaration comment said `-1 = no stop, which is every path but the
one @ arm`, stale since the parenless arm landed and noted as such in this
ticket. Corrected to name all three, because the COUNT is what makes "safe by
construction" a checkable claim rather than an assurance.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 92175e59f.
