# Typed constant arrays (initialized const arrays)

- **Type:** feature
- **Status:** done
- **Owner:** —
- **Opened:** 2026-06-16 (found via conformance feature-probing)
- **Closed:** 2026-06-16

## Done (commit 54d5dda)

Landed alongside the `var = init` global-initializer fix: typed constants reuse
the pending-init machinery (storage allocated, elements compiled as assignments
before `main begin`). Scalar ordinal/Int64 + parenthesised ordinal/Int64 array
constants, globals only. `test_cross_typed_const` byte-identical all 4 targets,
matches FPC (incl. writing through a typed const — FPC semantics). Out of scope:
string/float/record-initializer constants, local typed consts.

## Gap

A typed constant with an array initializer does not parse:

```pascal
const A: array[0..3] of Integer = (10, 20, 30, 40);   { Expected: = }
```

Scalar typed constants work; the array-initializer form `( v0, v1, ... )` is not
handled. FPC accepts it and it is common for lookup tables.

## Scope

- Parse `const Name: <arraytype> = ( e0, e1, ... )` (and ideally nested/record
  initializers later).
- Emit the initializer into the data segment as the const's storage; `A[i]`
  reads from it. Read-only.
- Cross-target byte-identical; add `test_cross_typed_const` and wire into all four
  suites.

## Notes

- Found while probing the language surface differentially against FPC (same pass
  that produced case-ranges and the paren-deref fix). A missing feature, not a
  miscompile.
