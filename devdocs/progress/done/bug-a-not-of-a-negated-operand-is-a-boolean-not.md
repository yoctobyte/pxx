---
track: A
prio: 50
type: bug
blocked-by: []
summary: "`not -1` printed TRUE. A `not` over a unary minus was lowered as a BOOLEAN not (xor rax,1), so an integer expression answered a Boolean — the loudest possible wrong value, and it reached bit manipulation on any negated operand. The bitwise-vs-logical decision reads a whitelist of 'authoritative' operand node kinds that had grown one entry per reported shape; AN_NEG was never one of them. Found by an integer-arithmetic differential against FPC 3.2.2."
---

# `not` of a negated operand was a boolean not

- **Type:** bug (**silent wrong VALUE, and wrong TYPE**) — Track A
  (`compiler/pasparser_expr.inc`).
- **Status:** done
- **Opened:** 2026-08-21, from a 25-program integer-arithmetic differential
  against FPC 3.2.2.
- **Closed:** 2026-08-21.

## Symptom

```
                fpc     pxx
not 1      =     -2      -2
not (1)    =     -2      -2
not 0      =     -1      -1
not -1     =      0    TRUE
not (-1)   =      0    TRUE
not (- 1)  =      0    TRUE
not (n)    =     -6      -6      { n: Integer = 5 }
not (-n)   =      4    TRUE
not (1+1)  =     -3      -3
not (0-1)  =      0       0
```

The pattern is exact: **only a unary minus operand**. A binary minus
(`not (0-1)`) is fine, a plain variable is fine, a literal is fine. And the
wrong answer is not a wrong number — it is a *Boolean*, printed as `TRUE`, from
an expression whose operands are integers throughout.

That makes it both worse and better than the usual silent-wrong-value: worse
because the type is wrong too, so `x := not -mask` assigns 0 or 1 into an integer
and every bit downstream is gone; better because `TRUE` in numeric output is
visible the moment anyone prints it. It is the "plausible wrong value far from
the cause" case only when the result feeds arithmetic instead of a `WriteLn`.

## Root cause

Pascal spells bitwise complement and logical negation with the same word, so
`not` has to decide from the operand. `ParseFactor` cannot simply trust the
operand's `ASTTk`, and the comment above the decision says why at length: the
frontend tags some *logically Boolean* expressions as `tyInteger` (`not (a = b)`
and `not Eat(...)` appear in `compiler.pas` that way), so promoting every
integer-tagged operand to bitwise breaks self-host.

The compromise is a whitelist of operand node kinds whose type IS authoritative:
literal, identifier, array element, field, deref, nested bitwise `not`, ordinal
value-cast, `Ord(x)`, a call with a declared non-Boolean ordinal return type, and
an arithmetic `AN_BINOP`. Read the comment history and each entry arrived with
its own bug ticket: `not arr[i]`, `not rec.f`, `not ord(e)`, `not Int64(0)`,
`not(not(q))`, `not (q3 or q4)`.

`AN_NEG` was never on the list. Nothing about a unary minus is ambiguous — it is
as unambiguously numeric as the arithmetic `AN_BINOP` entry at the bottom of the
same condition, which was added for exactly that reason.

This is `normalise-dont-special-case.md` seen from the losing side: a whitelist
that grows one entry per report is a list of the shapes someone happened to hit,
not a rule. The honest fix is to stop mistagging Boolean expressions as integer
so the operand's type can simply be believed — filed as
`feature-a-trust-the-operand-type-for-not` — but that changes what self-host
compiles, so it is not a 4am change. Adding the one node kind that provably
cannot be Boolean is the right size here, and the ticket above records why the
list should not keep growing.

## Fix

`(ASTKind[left] = AN_NEG) or` in the authoritative-operand list, with a comment
pointing at the arithmetic-`AN_BINOP` arm it mirrors.

## Verification

`test/test_not_of_negated_operand.pas`, wired into `test-core`, **byte-identical
to fpc 3.2.2** across fourteen rows: the negated literal in three spellings, a
negated variable with and without parens, a negated Int64, the five shapes that
already worked (so a regression the other way shows), and two genuinely Boolean
operands (`not b`, `not (n = 5)`) that must stay logical.

Gate: `make compiler/pascal26` fixedpoint (byte-identical — the compiler's own
`not` uses stay on their existing path) + `tools/gate.sh quick` GREEN.

## Also found in the same run, and NOT bugs

`shr`/`shl` on a declared 32-bit operand diverge from FPC by decision
(`decide-shift-operator-promotion-width`), and `--strict-fpc` reproduces FPC on
all nine measured rows. Three of those rows were missing from the decision's own
table, which is why they read as regressions; they are now recorded in
`devdocs/dev/pascal-dialect-divergences.md` so the next differential stops
re-filing them.
