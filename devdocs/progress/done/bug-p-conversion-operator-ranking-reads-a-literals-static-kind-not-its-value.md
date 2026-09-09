---
track: P
prio: 40
type: bug
blocked-by: []
status: done
owner: frankD
found-by: frankS
created: 2026-09-09
summary: "FIXED. Re-measured at HEAD (`fd0cce88c`, compiler `2a9e5179428f`) -- it had NOT evaporated, and re-measuring produced a sharper rule than the ticket recorded plus TWO more defects in the same lookup. fpc 3.2.2 types an untyped integer CONSTANT by value (smallest type that holds it, signed candidate before unsigned at each width), then ranks the conversion operators against that; a source-rank TIE is broken by DECLARATION ORDER, not refused; and `Integer`/`LongInt` must compare EQUAL for exactness. pxx got all three wrong: `d := 200` took the Int64 operator, a six-operator ladder refused EVERY row as `more than one conversion operator applies`, and `d := i` with an `i: Integer` refused too. Fixed by routing the assignment site through a new `OpConvSrcTkOfNode` (ir.inc) that asks `ASTConstIntValue` and re-types via the existing `LiteralIntKind`; by counting a tie as ambiguous only when the candidates convert from the SAME source type; and by using `SameExactTypeKind` for the rank-0 test. 48 measured rows byte-identical to fpc, fixture `test/test_conv_op_rank_literal_by_value.pas` (24 rows, `test_convrank26`)."
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


## Resolution (frankD, 2026-09-09)

Re-measured at HEAD first, as the ticket asked. It reproduced — and the
re-measurement is most of the value here, because **the ticket's single `200`
row would have certified a wrong rule.** "The narrowest type that fits wins"
gets `200 -> Byte` right and `5 -> Byte` wrong; fpc answers `5 -> Int64` for
that same operator pair. The `5` row is the discriminator the ticket lacked.

### What fpc actually does, measured (fpc 3.2.2 -Mobjfpc, 2026-09-09)

Type the constant by VALUE, then rank the operators against that type with the
ranks `OpConvSourceRank` **already implements** — exact kind (0), same
signedness (1), any integer (2) — and break a tie by **declaration order**.
The six-operator ladder pins the typing completely:

    5,127 -> ShortInt   128,200,255 -> Byte   256,32767 -> SmallInt
    32768,65535 -> Word   65536 -> LongInt   -1 -> ShortInt   -200 -> SmallInt

and the tie-break needs an identical candidate set in two orders to prove:

    operator :=(SmallInt) then operator :=(Int64),  d := 5  -> SmallInt
    operator :=(Int64)    then operator :=(SmallInt), d := 5 -> Int64

Signedness dominates width, which is why `{Byte,Int64}` answers `5 -> Int64`
and `200 -> Byte`, and why `{Word,SmallInt}` answers SmallInt in either order.

### Three defects, each with a row the other two do not fix

1. **The literal's static kind, not its value** — the filed defect.
   `ir.inc`'s implicit-assign site passed `ASTTk[rhs]`, and pxx types every
   literal `tyInteger`. Fixed with `OpConvSrcTkOfNode` (ir.inc, beside
   `IRLowerAST`), which re-types through the existing `LiteralIntKind`.
   *Before:* `200 -> Int64`.

2. **A source-rank tie was a refusal.** `FindOpConvRankedAmb` counted every
   equally-ranked candidate into `nBest`, and `FindOpConvToDestAmb` turns
   `nBest > 1` into `Incompatible types: more than one conversion operator
   applies to this assignment`. That refusal is correct for the shape it was
   written for — toperator92/95, two sized string results from the SAME source
   — and wrong for candidates whose PARAMETER types differ, where fpc takes the
   first declared. Now counted only when the tying candidate converts from the
   same source type. *Before:* every one of the ladder's twelve rows refused.

3. **`Integer` and `LongInt` did not compare equal** in the rank-0 test, so
   neither was exact and both tied at rank 1. `SameExactTypeKind` already
   states that rule for two other sites; it moved above `OpConvSourceRank` to
   become the third caller. *Before:* `d := i` with `i: Integer` and
   `{LongInt,Int64}` declared refused a program fpc compiles. As a bonus this
   also gets the DECLARATION-time refusal fpc gives for an `Integer`+`LongInt`
   operator pair (`overloaded functions have the same parameter list`), through
   `FindOpConvDeclDup`, which shares the rank.

### The node-shape half, and why the fixture asserts negatives

`ASTConstIntValue`, not `ASTKind = AN_INT_LIT`. A **negative** constant is not
a literal node: `ParseFactor`'s `tkMinus` arm builds an `AN_NEG` and types it
from the folded value. An AN_INT_LIT-keyed version of this fix was built and
measured — it passed all ten positive ladder rows and answered
`-1 -> LongInt`, `-200 -> LongInt`. `0-1` *does* fold to a literal andanswers
correctly, which is exactly what makes the wrong version look right. The folder
also covers a named `const` and a folded const expression, both of which fpc
ranks by value (measured, in the fixture).

### The caveat the parent ticket named

`LiteralIntKind` takes an `Int64` and never returns `tyUInt64`, so a literal
above `High(Int64)` would reach it as a negative number and come back
`tyInt8`. Guarded by leaving any node already tagged `tyUInt64` alone —
`NormalizeWideUnsignedLiteral` has typed it correctly and there is nothing to
re-derive. Asserted: `{QWord,Int64}` with `18446744073709551615` answers QWord
and with `High(Int64)` answers Int64, both matching fpc.

### Verification

48 probe rows across candidate sets, orders and values, all byte-identical to
fpc 3.2.2. Fixture `test/test_conv_op_rank_literal_by_value.pas` (24 rows,
`.expected` is fpc's own output), Makefile row `test_convrank26`, GREEN under
`testmgr --tier native`. `make compiler/pascal26` printed
`converged after 1 round(s)`; `tools/gate.sh quick` GREEN.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 0a4fc1c31.
