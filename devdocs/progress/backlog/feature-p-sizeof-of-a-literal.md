---
track: P
prio: 20
type: feature
blocked-by: []
summary: "`SizeOf(1)`, `SizeOf('abc')`, `SizeOf(3.5)`, `SizeOf(nil)` are compile errors — the remaining half of feature-p-sizeof-of-an-expression, split out because fpc types a literal by its VALUE (SizeOf(1)=1, SizeOf(256)=2) rather than by the expression's type, so it needs its own rule."
status: backlog
---

# `SizeOf(<literal>)` is refused

Split out of [[feature-p-sizeof-of-an-expression]] when that landed on
2026-08-22. Expression operands now work; literal operands still raise
`SizeOf: unknown type or variable`.

They were left out **deliberately**: fpc types a literal by its VALUE, not by
the type the expression parser would give it, so routing them through the new
expression path would answer 8 for most of this table — a wrong size, silently,
that `GetMem` and `Move` would carry straight into the allocator.

## The rule to implement (measured, `fpc -Mobjfpc -O1` 3.2.2)

| operand | fpc | why |
| --- | --- | --- |
| `1` | 1 | smallest type holding the value |
| `127` | 1 | |
| `128` | 1 | unsigned range, so Byte |
| `255` | 1 | |
| `256` | 2 | |
| `32767` | 2 | |
| `32768` | 2 | still Word |
| `65535` | 2 | |
| `65536` | 4 | |
| `100000` | 4 | |
| `5000000000` | 8 | |
| `-1` | 1 | ShortInt |
| `-129` | 2 | SmallInt |
| `3.5` | 4 | a real literal is **Single**, not Double |
| `'a'` | 1 | Char |
| `''` | 1 | |
| `'abc'` | 3 | its LENGTH, not a string handle |
| `nil` | 8 | pointer width |
| `[1, 2]` | 2 | the set's storage size |

Two of these are traps worth calling out: `SizeOf(3.5)` is 4 because an untyped
real constant is Single-typed for this purpose even though it would promote to
Double in arithmetic; and `SizeOf('abc')` is 3 because a string literal is typed
as its own `array[1..3] of Char`. Both look harmless to get wrong and are wrong
everywhere, so both belong in the test.

`[1, 2]` also depends on `compat-pascal-set-storage-size-is-always-32-bytes` —
our sets are 32 bytes, so that row cannot match until that ticket does. Skip it
or assert the pxx value with a comment; do not "fix" set sizing from here.

## Where the code is

`compiler/pasparser_expr.inc`, the `szIsExpr` dispatch block at the top of the
`sizeof` intrinsic. Today the first token being a literal falls through to the
name path and its error. Add a literal arm ahead of that, keyed on the token
kind, implementing the table above.

## Prio

20. Nobody writes `SizeOf(1)` in earnest — the value of the parent ticket was
type-probing an expression, and that half has landed. This is conformance
tidiness, and the wrong answer is currently a loud compile error rather than a
silent number, which is the right failure mode to wait in.

## Gate

Every row above matching `fpc -O1` (except the set row, see above), the
expression and name paths unchanged, and self-host byte-identical.
