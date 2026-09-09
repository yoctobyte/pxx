---
track: P
prio: 40
type: bug
blocked-by: []
status: open
owner: unassigned
found-by: frankS
created: 2026-09-09
summary: "Split out of [[bug-p-a-constant-expression-that-overflows-int64-stays-signed]] when its PROMOTION half closed 2026-09-09 -- this is the second, smaller half and it is a DIFFERENT site with a DIFFERENT rule, so it does not belong inside a done/ ticket. `FindOpConvToDest` is handed `ASTTk[rhs]`, so an integer literal ranks as its STATIC kind: with two conversion operators to one destination, `b := 200` picks the Int64 overload where fpc 3.2.2 picks the Byte one. fpc types a literal BY VALUE first and ranks that -- which is the rule pxx ALREADY implements for CALL arguments, via `LiteralIntKind` in pasparser_lval.inc, so this is one concept with two mechanisms and only one of them is right. NOT MEASURED AT HEAD BY ME: the observable is frankS's from 2026-09-06 at compiler `4b22a668e6ab`; the promotion fix that landed since touches ParseSimpleExpr's result TYPE and not the ranking, so it is unlikely to have moved this, but re-run the two-operator probe before working it."
---

# Conversion-operator ranking reads a literal's static kind, not its value

The parent ticket's promotion half is closed; this is the residual it named,
filed rather than left inside it so `ready` can hand it to somebody.

**The rule fpc uses:** type the literal by VALUE, then rank. `200` is a Byte
before it is an Int64, so a `Byte` conversion operator outranks an `Int64` one.

**What pxx does:** `FindOpConvToDest` receives `ASTTk[rhs]` — the node's static
kind — and ranks that. A literal that parsed as `tyInteger`/`tyInt64` therefore
never offers its narrow reading to the ranker.

**The same rule already exists here, one site over.** `LiteralIntKind`
(`pasparser_lval.inc`) types a literal by value for CALL arguments and is right.
So this is `normalise-dont-special-case` territory: one concept, two mechanisms,
and the second one is the one that stayed broken. Prefer routing the ranker
through the existing helper over adding a third.

**Do not reach for `LiteralIntKind` blindly**, per the parent: it takes
`v: Int64`, so a value above `High(Int64)` cannot be passed to it at all, and it
caps at `tyInt64` and never returns `tyUInt64`. A literal in the unsigned band
needs its own arm or a widened helper.

## Before working it

Re-run the observable at HEAD. It was measured by frankS on 2026-09-06 at
compiler `4b22a668e6ab` and I have **not** re-measured it — the promotion fix
that landed 2026-09-09 changes `ParseSimpleExpr`'s result TYPE, not the ranking,
so it should not have moved this, but "should not have" is not a measurement.
Two conversion operators to one destination, `b := 200`, and see which is
chosen.
