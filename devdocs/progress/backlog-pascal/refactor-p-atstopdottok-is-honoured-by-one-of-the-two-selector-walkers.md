---
slug: refactor-p-atstopdottok-is-honoured-by-one-of-the-two-selector-walkers
title: "AtStopDotTok is read by ParseClassRecordSelectors and ignored by ParseLValueAST, so every caller carries a hand-written receiver route for the symbol-rooted case"
track: P
prio: 35
type: refactor
blocked-by: []
status: open
owner: ""
created: 2026-09-08
summary: "`AtStopDotTok` names the one dot a selector walk must leave in the stream -- the mechanism behind every `a.b.Foo` method reference. Only ParseClassRecordSelectors consults it (pasparser_lval.inc, the `while CurTok.Kind in [tkDot, tkLBrack]` head). ParseLValueAST, which is where ParseFactor sends a SYMBOL-rooted designator, has its own selector handling and walks straight past the stop. So every caller that needs a bounded walk carries TWO routes: hand-build the receiver node and call ParseClassRecordSelectors when the root is a symbol, call ParseFactor when it is a class name. Four sites encode that one fact today. Teaching ParseLValueAST the flag is safe BY CONSTRUCTION -- AtStopDotTok is -1 on every path but these arms, so the check cannot change any other parse -- and would delete all four splits. Not a bug: every caller is correct today."
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
