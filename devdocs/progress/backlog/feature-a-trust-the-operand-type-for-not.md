---
track: A
prio: 30
type: refactor
blocked-by: []
summary: "`not` decides bitwise-vs-logical from a WHITELIST of operand node kinds whose type is 'authoritative', because the frontend mistags some logically-Boolean expressions as tyInteger and self-host depends on those staying logical. The list has grown one entry per bug report — array element, field, deref, Ord(x), value-cast, nested not, and/or/xor at explicit width, and now AN_NEG — and every entry arrived AFTER someone shipped wrong bits. Fix the mistagging instead, then believe ASTTk."
---

# `not` should trust the operand's type, not a list of node kinds

- **Type:** refactor (removes a class of bugs rather than one) — Track A
  (`compiler/pasparser_expr.inc`, and wherever Boolean expressions get tagged
  `tyInteger`).
- **Status:** backlog
- **Opened:** 2026-08-21, closing
  `bug-a-not-of-a-negated-operand-is-a-boolean-not`.

## The shape

Pascal spells bitwise complement and logical negation with one word, so `not`
must pick from the operand. The obvious rule — "integer operand → bitwise,
Boolean operand → logical" — is not usable today, because the frontend tags some
expressions that are *logically Boolean* with `tyInteger`. `compiler.pas` itself
contains `not (a = b)` and `not Eat(...)` carrying `ASTTk = tyInteger`, and
trusting those flips them to `xor rax, 1`-vs-`not rax` the wrong way and breaks
the self-host fixedpoint.

So the code instead asks "is this operand node kind one whose type I believe?"
and consults a whitelist. Read `git log` on that condition and it is a museum:

| entry | arrived with |
| --- | --- |
| array element, field, deref | `not arr[i]` / `not rec.f` produced garbage masks |
| `Ord(x)` | `bug-pascal-not-of-ord-uses-boolean-negation` |
| ordinal value-cast | `not Int64(0)` printed TRUE |
| nested `not` | `not(not(q))` flipped the outer to boolean |
| `and`/`or`/`xor` at explicit width | `not (q3 or q4)` on qwords |
| arithmetic `AN_BINOP` | `not (x shr 1)` |
| `AN_NEG` | `not -1` printed TRUE (2026-08-21) |

Every one of those is the same bug, and every one was found by a user or a
differential rather than by the compiler. A whitelist of the shapes someone
happened to hit is not a rule; the next shape is already wrong and nobody knows
which it is.

## What to do instead

1. **Find the mistagging.** Enumerate where a Boolean-valued expression ends up
   with `ASTTk = tyInteger` — comparisons and logical `and`/`or`/`xor` are the
   named suspects. `PXXDBG` can print the inferred tag rather than reasoning
   about it (`devdocs/dev/debugging-playbook.md`: measure, do not reason).
2. **Fix the tags** so a Boolean expression is `tyBoolean`.
3. **Delete the whitelist** and drive `not` off `ASTTk` alone.

The self-host fixedpoint is the gate and the risk in one: `compiler.pas` relies
on the current behaviour of `not (a or b)` and `not (r and v)`, so step 2 must
land those as `tyBoolean` before step 3 can be believed. Doing 3 without 2 is
what the existing comment warns hung a self-compile once already.

## Why it is prio 30 and not higher

Nothing is known-broken today — the whitelist covers every shape anyone has
tried. This buys the *absence* of the next report, which is real but not urgent,
and it touches type inference under a byte-identical gate. Take it when there is
room to measure, not between two bug fixes.
