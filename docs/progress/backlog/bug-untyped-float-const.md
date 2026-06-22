# Untyped float const `const X = 1.5;` rejected (and `Single(expr)` value cast)

- **Type:** bug (compiler, front-end) — **Track A**
- **Status:** backlog
- **Severity:** LOW — clean idiomatic workaround exists (typed const).
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

## Log
- 2026-06-22 — Filed by Track B from the math-demo build.
