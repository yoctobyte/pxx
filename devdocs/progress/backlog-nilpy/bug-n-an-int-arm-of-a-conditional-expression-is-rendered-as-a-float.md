---
name: bug-n-an-int-arm-of-a-conditional-expression-is-rendered-as-a-float
type: bug
track: N
prio: 40
status: open
summary: >
  `0 if y is None else float(y)` answers 0.0 under pxx where CPython answers 0.
  A conditional expression whose arms are an int and a float is typed tyDouble
  by PyWiden, and the INT arm's value is then rendered in that type -- a wrong
  value in printed output with no diagnostic. Module level and function body
  alike; nothing to do with None (the None arm of a ternary is a different
  defect, fixed separately).
---

## What was measured

2026-09-13, at the commit that fixed the None arm of the same construct. Both
rows below are one expression with one int arm and one float arm, and the int
arm is the one taken:

    def g(y):
        return 0 if y is None else float(y)
    print(repr(g(None)))        # CPython 0      pxx 0.0

    def g(y):
        return 0 if y else 1.5
    print(repr(g(0)))           # CPython 0      pxx 0.0

    y = None
    print(repr(0 if y is None else float(y)))    # CPython 0   pxx 0.0

The third row is module level, so this is not the def-return-type scan -- it is
the conditional expression's own node type.

## The mechanism

`pyparser.inc`, the conditional-expression parser (search the AN_TERNARY
construction): the node's ASTTk is `PyWiden(then, else)`, and PyWiden's numeric
arm answers tyDouble whenever either side is one. The taken arm's value is then
stored in the result's declared type, so an int arrives as a double.

PyWiden is RIGHT for an arithmetic expression -- `1 + 2.5` really is a float,
and CLAUDE.md's "double is the native evaluation type" covers that. A
conditional expression is not arithmetic: it yields ONE OF ITS ARMS unchanged,
so in Python `0 if c else 1.5` is the integer 0, not 0.0.

That distinction already has a name in this file. `PyWidenBinding` exists for
exactly it -- "the join for a NAME REBOUND across types ... is NOT the join for
an EXPRESSION" -- and its int-meets-float row redirects to tyVariant so each
binding renders as itself. Its own history ticket is
bug-nilpy-int-prints-as-float-when-the-name-is-widened-later, which is the same
observable one construct over.

## Recommendation, not a spec

Route the ternary's int-meets-float pair through PyWidenBinding rather than
PyWiden, on the argument that a ternary SELECTS a value the way a rebound name
holds one, instead of computing a new one. Measure before believing it: the
ternary's arms feed a single result slot and boxing every numeric ternary into
a variant has a cost the arithmetic case must not pay, so check what the
string/char and promo rows do under the swap, and check that an all-int ternary
still boxes nothing.

## Not covered here

A None arm of a conditional expression was a separate and worse defect (it
RAISED, `TypeError: expected a number, got NoneType`, on the shape
lekkerzeilen's world.Furniture.__init__ writes eleven times). Fixed in the same
session by giving PyInferExprType an arm for the None literal -- see the
logbook row. Do not read that fix as covering this one: it does not, and d9 in
that session's probe set is this row still failing after it.
