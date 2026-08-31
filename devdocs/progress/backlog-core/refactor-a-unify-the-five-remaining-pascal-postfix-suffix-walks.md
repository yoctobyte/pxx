---
slug: refactor-a-unify-the-five-remaining-pascal-postfix-suffix-walks
title: "Unify the five remaining Pascal postfix suffix walks — hygiene, not bug-fixing, and the ASTIVal meaning must be settled first"
track: A
prio: 35
type: refactor
blocked-by: []
status: backlog
owner: ""
created: 2026-08-30
found-by: frankA (step 3 of refactor-a-the-pointer-suffix-walk-has-six-copies-in-the-pascal-frontend, re-scoped on its own measurement)
summary: "Successor to the six-copies ticket. Its inventory measured all six copies against FPC and found only site 6 diverging; site 6 is fixed. Unifying the remaining five is worth doing to prevent the NEXT site 6, but it has zero measured behavioural payoff and five conversions of regression risk, so it is filed at its real priority rather than inherited. Blocking design question inside: ASTIVal on an AN_DEREF currently means two different things."
---

# Unify the five remaining copies — with eyes open about what it buys

Successor to [[refactor-a-the-pointer-suffix-walk-has-six-copies-in-the-pascal-frontend]],
which did the inventory, found the six copies' actual behaviour, fixed the one
that was wrong, and **re-scoped this remainder on that measurement**.

## What the parent measured, so this ticket does not re-litigate it

Ten cells — two axes (a subscript after the field; a depth-2 deref) × the six
entry points — each diffed against `fpc 3.2.2`. **Only site 6 diverged**, on
both axes, and it is now fixed. Sites 1–5 agreed with FPC on both.

So the parent's premise — "six copies, therefore six chances to drift" — turned
out to be **one** copy that had drifted, not six. The remaining unification:

- **buys** — no second reader can fall behind the way site 6 did. Site 6's two
  defects (a parse error, and a silent wrong store) are exactly what six-way
  duplication produces, and it went unnoticed through the closure of its own
  twin's ticket, which fixed the identical defect on the record-name cast and
  never grepped for the alias-name sibling.
- **costs** — five conversions, each needing the A/B binary-identity standard
  (compiler built before and after, same sources, diffed), against zero measured
  behavioural payoff. A refactor with no failing test to turn green is one where
  the only possible outcome is a regression.

That is a real but *modest* case, so this is filed at prio 35 rather than
inheriting the parent's 55. It should be picked up when Track A wants the
hygiene, not as a bug fix.

## Settle this BEFORE writing the helper

`ASTIVal` on an `AN_DEREF` means **two different things** depending on which
copy wrote it:

| copies | `ASTIVal` holds |
| --- | --- |
| 1 (`pasparser_lval.inc`), 2 & 4 (`pasparser_expr.inc`) | the **ultimate base** record — bottom of the pointer chain |
| 3 & 5 (record-name casts), 6 (alias cast) | the **immediate pointee** record |

The two readers disagree in the same direction:

- `ResolveNodeRec`'s `AN_DEREF` arm tests `ASTIVal > 0` **ungated** and treats it
  as *"the record this deref yields"* — the **immediate-pointee** reading.
- `ResolveDerefShape`'s `AN_DEREF` arm reads it as the **ultimate base**, but
  only under `ASTSOffset > 0` — and the immediate-pointee writers all leave
  `ASTSOffset` at 0, so that gate is currently the only thing keeping the two
  meanings from colliding.

They coincide whenever remaining depth is 0 or 1, which is every shape in the
repo today. **A union helper that unconditionally stamps one meaning changes
what `ResolveNodeRec` answers on the other paths.** So: pick the meaning, move
`ResolveNodeRec`'s arm to match it, and do both in the same commit. Renaming the
field to say which it is would be cheap insurance.

## Approach

Convert **one copy at a time**, each under A/B binary identity: build the
compiler before and after, compile the same sources with both, diff the
binaries. "Tests pass" is not the standard here — the whole point is that these
tags are read by code no current test exercises, which is how site 6 stayed
broken.

Expect the union to be **strictly larger** than any one copy. A copy that stamps
fewer tags is not simpler; it is the one with the latent bug. That is not a
guess — it is what site 6 turned out to be.

## Out of scope, deliberately

NilPy's own three copies (`pyparser.inc:42567 / 47378 / 47524`) stay separate.
Duplication *across* languages is the rule
(`devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md`: share the AST and
the IR, duplicate the parser). They are worth reading as a second opinion on
what the walk must stamp, and must not be folded in.

## Gate

Per converted copy: `make compiler/pascal26` (the self-host fixedpoint) + A/B
binary identity across the `examples/` tree (33 programs build today) +
`test/test_cast_lvalue_suffix_siblings.pas` and
`test/test_cast_deref_chain_siblings.pas` green. `tools/gate.sh quick` before
any pin.

**Do not** take this concurrently with [[feature-a-typeref-migrate-consumers]]'s
step 2 — that one needs `ir.inc` and re-points `PtrBaseTk`, and these readers
are downstream of exactly that field's meaning.
