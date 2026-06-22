# Untyped float const `const X = 1.5;` rejected (and `Single(expr)` value cast)

- **Type:** bug (compiler, front-end) — **Track A**
- **Status:** **DONE** — all three sub-gaps fixed, FPC-faithful, `make test` +
  cross-bootstrap green.
- **Severity:** LOW — clean idiomatic workaround existed (typed const).
- **Opened:** 2026-06-22
- **Owner:** — (Track A / "sis")
- **Found by:** Track B, building the float math demo.

## Summary

An **untyped constant with a floating-point value** is rejected at parse time;
FPC accepts it. A **typed** const works.

```pascal
const EPS = 0.001;          { PXX: pascal26:3: error: unexpected token () }
const EPS = 1e-9;           { PXX: rejected }
const EPS: Double = 0.001;  { PXX: OK }
```

Likely the untyped-const path doesn't accept a real literal (only integer/char/
string), or const-expr eval lacks float. FPC infers a real-typed const.

Also fails: a **negative** value in a *typed* float const (positive is fine):

```pascal
const A: Double = 1.0;    { OK }
const A: Double = -2.5;   { PXX: rejected }   { unary minus in const float init }
```

So const float-expression evaluation is missing both untyped-real inference and
unary minus on a real literal. Mixing typed + untyped consts in one block is fine.

## Second, related front-end gap (same area)

A **value typecast to a float type** isn't parsed as an expression:

```pascal
ChkS('x', Sqrt(Single(2.0)), ...);   { PXX: pascal26: error: expected expression }
```

Workaround: assign to a `Single` variable first, then pass it. (Used in
`examples/mathf/mathdemo.pas`.)

## Impact / workaround

`examples/mathf/mathdemo.pas` uses **typed** consts (`EPS: Double = …`) and a
`Single` temp instead of `Single(expr)`. Both are clean idiomatic Pascal, so this
is not blocking — just a front-end parity gap with FPC worth closing.

## Resolution (2026-06-22, Track A)

All three fixed in `compiler/parser.inc`:

1. **Untyped real const** (`const X = 1.5;`, `1e-9`, `-2.5`): the untyped-const
   path now detects a (optionally signed) float literal and stores the IEEE-754
   double bits tagged `tyDouble` via `ParseInitVal`; a use emits `AN_FLOAT_LIT`.
2. **Negative typed float const** (`const A: Double = -2.5;`): `ParseInitVal` is
   now sign-aware — a leading unary `-`/`+` before a `tkFloat` flips bit 63 of
   the bits (the lexer emits the sign as a separate token, so it previously fell
   to the integer `ConstEval` and was rejected).
3. **`Single(expr)` / `Double(expr)` value cast** in an expression: new
   `tkSingle_T/tkDouble_T/tkExtended_T` case in `ParseFactor`, desugared to a
   hidden float temp + assignment (the store coerces int->float / narrows
   double->single), reusing the generic assign-then-yield node. `Extended`
   aliases `Double`.

Verified identical to FPC: `test/test_float_const_and_cast.pas` (untyped + typed
+ negative + exponent consts, const-in-expression, `Single`/`Double` casts as
rvalue and in arithmetic). `make test` + fpc-check byte-identical;
cross-bootstrap (i386/aarch64/arm32) byte-identical.

**Minor known edge (NOT this feature):** a cast node placed *directly* in a
`writeln` with `:w:d` formatting — `writeln(Double(5):0:1)` — prints `5` not
`5.0` (a pre-existing writeln arg-type quirk on the synthesized node). Realistic
use (assign to a var first, or cast as a function arg) is correct + FPC-matching.
Unusual; left as-is.

## Log
- 2026-06-22 — Filed by Track B from the math-demo build.
- 2026-06-22 — DONE (Track A). Three front-end gaps closed; FPC-faithful.
