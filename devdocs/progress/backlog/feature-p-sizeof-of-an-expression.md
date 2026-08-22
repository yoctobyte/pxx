---
track: P
prio: 30
type: feature
blocked-by: []
summary: "`SizeOf` accepts only a type name or an lvalue (variable, field, `a[i]`) — `SizeOf(i + 1)`, `SizeOf(Abs(i))`, `SizeOf(p^)`, `SizeOf('abc')` are all compile errors. FPC takes any expression, and it is the only portable way to ask what type an expression actually has."
status: backlog
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
