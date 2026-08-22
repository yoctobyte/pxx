---
track: P
prio: 30
type: feature
blocked-by: []
summary: "`SizeOf` accepts only a type name or an lvalue (variable, field, `a[i]`) — `SizeOf(i + 1)`, `SizeOf(Abs(i))`, `SizeOf(p^)`, `SizeOf('abc')` are all compile errors. FPC takes any expression, and it is the only portable way to ask what type an expression actually has."
status: done
---

# `SizeOf(<expression>)` is refused

Found 2026-08-22 by an FPC differential sweep over ordinal arithmetic
(`fpc -Mobjfpc -O1` 3.2.2 vs pxx `80bbe2f38`).

## The measurement

`var i: Integer; p: ^Integer; a: array[0..3] of Byte; r: record a, b: Integer; end;`

| expression | FPC | pxx |
| --- | --- | --- |
| `SizeOf(Integer)` | 4 | 4 |
| `SizeOf(i)` | 4 | 4 |
| `SizeOf(r.a)` | 4 | 4 |
| `SizeOf(a[0])` | 1 | 1 |
| `SizeOf(p^)` | 4 | **compile error** |
| `SizeOf(i + 1)` | 8 | **compile error** |
| `SizeOf(i * 2)` | 8 | **compile error** |
| `SizeOf(-i)` | 8 | **compile error** |
| `SizeOf(i shl 1)` | 4 | **compile error** |
| `SizeOf(Abs(i))` | 4 | **compile error** |
| `SizeOf(@i)` | 8 | **compile error** |
| `SizeOf('abc')` | 3 | **compile error** |
| `SizeOf(1)` | 1 | **compile error** |
| `SizeOf(Length(a))` | 8 | **compile error** |

Two different messages depending on shape:

```
error: SizeOf: unknown type or variable      { SizeOf(Abs(i)) }
error: unexpected token, Expected: )         { SizeOf(i shl 1) }
```

The second one is the tell: the argument is parsed as a *name*, not as an
expression, so the parser stops at the first operator rather than at the `)`.

## Why it matters beyond the missing rows

`SizeOf(<expr>)` is the only portable way to ask **what type an expression
actually has** — there is no `TypeOf` to print. The table above is exactly how
the shift/`Abs`/`Sqr` width rules in `devdocs/dev/pascal-dialect-divergences.md`
were confirmed against FPC: `SizeOf(i + 1)` = 8 and `SizeOf(i shl 1)` = 4 states
FPC's promotion rule in one line each. That probe cannot be written against pxx
today, so every future width question has to be answered indirectly by
overflowing a value and reading the wrap — which is what
[[compat-pascal-strict-fpc-abs-and-sqr-widths]] had to do.

It is also ordinary in real code: `GetMem(p, n * SizeOf(p^))` and
`Move(src, dst, SizeOf(rec.field))` are the idiomatic spellings, and `p^` is
already refused.

## Scope

Track P (`compiler/pasparser_*.inc`). The fix is to parse the argument as a full
expression and take `ASTTk`'s size when it is not a type name, keeping the
existing type-name arm first (`SizeOf(Integer)` must not resolve `Integer` as an
identifier). Two care points:

- **Do not evaluate the operand.** `SizeOf(f(x))` must not call `f` — FPC
  discards the expression and keeps only its type. Lower to a constant and drop
  the subtree.
- `SizeOf('abc')` is 3, not the size of a string handle: a string *literal* is
  typed as its own `array[1..3] of Char` here. Getting this row wrong is
  harmless-looking and wrong everywhere, so it belongs in the test.

Sibling `BitSizeOf` (if present) and `High`/`Low` of an expression are the same
parse shape; check them in the same pass rather than filing three tickets.

## Gate

Every row above matching `fpc -O1`, plus a test asserting no side effect from
`SizeOf(SideEffectingFunction)`, and self-host byte-identical.

## Resolution (2026-08-22) — dispatch in front of the name path, literals left open

`SizeOf`'s operand is now scanned before it is parsed: anything at bracket-depth
zero that is not an identifier or a `.` means the operand is an **expression**,
and it is parsed as one, sized from its static type, and **dropped**.

Dispatch, not replacement. The name path carries a pile of hard-won cases an
expression's `ASTTk` does not model — a variable's DECLARED type rather than its
element type, an N-D subscript naming a row versus a scalar, a dynamic-array
handle being pointer width — so it stays the path for anything shaped like a
name. Every previously-working row is asserted in the test for exactly that
reason.

One refinement the first cut needed: the name path indexes only a genuine ARRAY
symbol, so `SizeOf(s[1])` on a string reached it and died on the `[` with
"expected `)`" — a row that was broken *before* this ticket and would have
stayed broken. A subscript on a non-array symbol now routes to the expression
path too.

**No evaluation:** the operand subtree is allocated and then abandoned, so
nothing in it is lowered and `SizeOf(F(x))` cannot call `F`. The test asserts
the call counter is still 0 afterwards, and then calls `F` for real to prove the
counter works.

### Rows now matching `fpc -O1`

`p^` `@i` `i + 1` `i * 2` `-i` `i div 2` `Abs(i)` `(i)` `i > 0` `Byte(i)`
`q + 1` `d * 2` `s[1]` `SizeOf(i) div SizeOf(c)` — plus every name-shaped row
that already worked.

### Rows deliberately NOT matching, asserted at the pxx value

- `SizeOf(i shl 1)` = 8, fpc 4. Our shifts happen at native width and are not
  truncated to the operand's declared type — the decided dialect divergence
  (`devdocs/dev/pascal-dialect-divergences.md`,
  `decide-shift-operator-promotion-width`). Asserting it here means a change to
  either rule fails loudly instead of drifting. This is also the probe that
  ticket's table wanted and could not be written.
- `SizeOf(Length(a))` = 4, fpc 8. Not a `SizeOf` question — pxx's `Length`
  returns Integer where fpc's returns `SizeInt`. Recorded here because this is
  where it becomes visible.
- `SizeOf(s + 'x')` = 8, fpc 256. fpc's `string` is a ShortString; ours is a
  managed handle — `compat-pascal-string-n-is-not-a-shortstring`.

### Left open — LITERAL operands, still a compile error

Deliberate, not an oversight. fpc types a literal by its VALUE, not by the
expression's type: `SizeOf(1)` = 1, `SizeOf(256)` = 2, `SizeOf(65536)` = 4,
`SizeOf(-1)` = 1, `SizeOf(-129)` = 2, `SizeOf(3.5)` = 4 (Single), `SizeOf('a')`
= 1, `SizeOf('abc')` = 3, `SizeOf('')` = 1, `SizeOf(nil)` = 8, `SizeOf([1,2])`
= 2. Routing those through the expression path would answer 8, 8 and 8 silently
— a wrong size that reaches `GetMem` and `Move` — so the first token being a
literal keeps the existing error until someone models the rule. The table above
is the spec for whoever does; **refiled as
`feature-p-sizeof-of-a-literal`.**

A record-typed or untyped expression is refused for the same reason: the AST
carries no record id on a general node, so `TypeSize(tyRecord)` would be a
plausible wrong number. `SizeOf(r)` and `SizeOf(TR)` go through the name path
and are unaffected.

Gate: `make compiler/pascal26` (self-host fixedpoint) + `tools/gate.sh quick`
GREEN. Test `test/test_sizeof_of_an_expression.pas`, 29 assertions, wired into
`test-core`.

## Log
- 2026-08-22 — resolved, commit PENDING-COMMIT.
