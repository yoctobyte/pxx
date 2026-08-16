---
track: C
prio: 60
type: bug
blocked-by: []
summary: "`sizeof((int[]){1,2,3})` answered 8 — the pointer size — for every array compound literal, so the NARGS idiom `sizeof((int[]){__VA_ARGS__})/sizeof(int)` counted 2 for any argument list, silently."
---

# sizeof of an array compound literal is the pointer size

- **Type:** bug (silent wrong value) — **Track C** (`compiler/cparser.inc`).
- **Found:** 2026-08-16, by a gcc-differential sweep over the preprocessor,
  through the argument-counting macro that uses this shape.

## Measured (before)

```
sizeof((int[]){1,2,3})        gcc 12   pxx 8
sizeof((int[]){1})            gcc  4   pxx 8
sizeof((char[]){1,2,3,4,5})   gcc  5   pxx 8
sizeof((int[4]){0})           gcc 16   pxx 8
NARGS(1,2,3)                  gcc  3   pxx 2
```

## Root cause

A compound literal is an OBJECT; only its use decays to a pointer, and `sizeof`
is not a use. `ParseCSizeof` has no arm for the `( type [N] ) {` shape, so it
fell through to the general-expression arm, which parses the operand and sizes
it by its RESULT type — the decayed pointer.

## Fix

An arm before the type-name arm: peek the cast, take the extent (or count the
top-level initializer elements for `[]`, which is what
`CBraceTopLevelInitCountAt` already does for the initializer paths), and yield
the constant. Anything that is not this shape rewinds and falls through
untouched — a record compound literal, a parenthesised expression, and
`sizeof(int[3])` all keep their own arms.

Note for the next reader: the count is taken while the parser still sits on the
`)`, because that is when `TokPos` IS the opening brace's index.

## Result

`test/csizeof_compound_literal.c` — unsized/sized/char/double literals, three
`NARGS` arities, and the four shapes that already worked — returns 42 under
both gcc and pxx.

## Gate

`make compiler/pascal26` + the test + `tools/gate.sh quick` — GREEN, including
the FPC seed canary, which needed a `CIsCastAhead` forward: the new call site
sits above its definition and the seed compiles the includes in order.
